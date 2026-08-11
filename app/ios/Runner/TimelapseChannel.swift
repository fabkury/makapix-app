import AVFoundation
import Flutter
import Foundation

/// The Timelapse export's VideoToolbox host (ADR 0004) — the iOS twin of Android's
/// TimelapseEncoder.kt. The "club.makapix.app/timelapse" MethodChannel receives
/// tightly-packed I420 frames with explicit presentation timestamps from the Dart export
/// isolate and hardware-encodes a silent H.264 MP4 via AVAssetWriter (which drives
/// VTCompressionSession underneath).
///
/// UNVERIFIED ON DEVICE: iOS builds only in Codemagic cloud CI (docs/BUILDING.md); this
/// file compiles there and ships with the next TestFlight build for a later device pass.
///
/// Threading: all work runs on one serial queue; Dart awaits each `feed`, so at most one
/// frame is in flight (the backpressure contract shared with the Android host).
class TimelapseChannel: NSObject {
  private let queue = DispatchQueue(label: "club.makapix.app.timelapse")
  private var writer: AVAssetWriter?
  private var input: AVAssetWriterInput?
  private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
  private var outputPath: String?
  private var width = 0
  private var height = 0

  static func register(with messenger: FlutterBinaryMessenger) {
    let instance = TimelapseChannel()
    let channel = FlutterMethodChannel(name: "club.makapix.app/timelapse", binaryMessenger: messenger)
    channel.setMethodCallHandler(instance.handle)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    queue.async {
      do {
        switch call.method {
        case "start":
          guard let args = call.arguments as? [String: Any],
                let w = args["width"] as? Int,
                let h = args["height"] as? Int,
                let bitrate = args["bitrateBps"] as? Int,
                let path = args["path"] as? String
          else { throw TimelapseError.badArgs }
          try self.start(width: w, height: h, bitrateBps: bitrate, path: path)
          DispatchQueue.main.async { result(nil) }
        case "feed":
          guard let args = call.arguments as? [String: Any],
                let data = args["bytes"] as? FlutterStandardTypedData,
                let ptsUs = args["ptsUs"] as? Int
          else { throw TimelapseError.badArgs }
          try self.feed(i420: data.data, ptsUs: Int64(ptsUs))
          DispatchQueue.main.async { result(nil) }
        case "finish":
          let path = try self.finish()
          DispatchQueue.main.async { result(path) }
        case "abort":
          self.abort()
          DispatchQueue.main.async { result(nil) }
        default:
          DispatchQueue.main.async { result(FlutterMethodNotImplemented) }
        }
      } catch {
        self.abort()
        DispatchQueue.main.async {
          result(FlutterError(code: "ENCODE_FAILED", message: "\(call.method): \(error)", details: nil))
        }
      }
    }
  }

  private func start(width w: Int, height h: Int, bitrateBps: Int, path: String) throws {
    abort() // a stale unfinished export never blocks a new one
    guard w % 2 == 0, h % 2 == 0 else { throw TimelapseError.oddDimensions }
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.removeItem(at: url)
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: w,
      AVVideoHeightKey: h,
      AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitrateBps],
    ])
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: input,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8Planar,
        kCVPixelBufferWidthKey as String: w,
        kCVPixelBufferHeightKey as String: h,
      ])
    guard writer.canAdd(input) else { throw TimelapseError.writerRejectedInput }
    writer.add(input)
    guard writer.startWriting() else { throw writer.error ?? TimelapseError.startFailed }
    writer.startSession(atSourceTime: .zero)
    self.writer = writer
    self.input = input
    self.adaptor = adaptor
    self.outputPath = path
    self.width = w
    self.height = h
  }

  private func feed(i420: Data, ptsUs: Int64) throws {
    guard let input = input, let adaptor = adaptor, let pool = adaptor.pixelBufferPool else {
      throw TimelapseError.notStarted
    }
    guard i420.count == width * height * 3 / 2 else { throw TimelapseError.badFrameSize }
    var maybeBuffer: CVPixelBuffer?
    guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &maybeBuffer) == kCVReturnSuccess,
          let buffer = maybeBuffer
    else { throw TimelapseError.bufferAlloc }
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    // Copy the tightly-packed planes honoring the buffer's per-plane bytesPerRow.
    var src = 0
    i420.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
      for p in 0..<3 {
        let pw = p == 0 ? width : width / 2
        let ph = p == 0 ? height : height / 2
        let dst = CVPixelBufferGetBaseAddressOfPlane(buffer, p)!
        let stride = CVPixelBufferGetBytesPerRowOfPlane(buffer, p)
        for row in 0..<ph {
          memcpy(dst + row * stride, raw.baseAddress! + src, pw)
          src += pw
        }
      }
    }
    // Backpressure: Dart awaits each feed; briefly spin the serial queue until the writer
    // drains (non-realtime input, so this settles quickly).
    while !input.isReadyForMoreMediaData {
      usleep(2000)
    }
    guard adaptor.append(buffer, withPresentationTime: CMTime(value: ptsUs, timescale: 1_000_000))
    else { throw writer?.error ?? TimelapseError.appendFailed }
  }

  private func finish() throws -> String {
    guard let writer = writer, let input = input, let path = outputPath else {
      throw TimelapseError.notStarted
    }
    input.markAsFinished()
    let done = DispatchSemaphore(value: 0)
    writer.finishWriting { done.signal() }
    done.wait()
    let error = writer.error
    self.writer = nil
    self.input = nil
    self.adaptor = nil
    self.outputPath = nil
    if let error = error { throw error }
    return path
  }

  private func abort() {
    if let writer = writer, writer.status == .writing {
      writer.cancelWriting()
    }
    if let path = outputPath {
      try? FileManager.default.removeItem(atPath: path)
    }
    writer = nil
    input = nil
    adaptor = nil
    outputPath = nil
  }
}

enum TimelapseError: Error {
  case badArgs
  case oddDimensions
  case writerRejectedInput
  case startFailed
  case notStarted
  case badFrameSize
  case bufferAlloc
  case appendFailed
}
