import 'package:flutter/services.dart';

/// The thin platform channel over the OS hardware video encoders (ADR 0004):
/// MediaCodec on Android, VideoToolbox on iOS — silent H.264 MP4, explicit per-frame PTS
/// (VFR carries the finale's authored durations). No Windows host exists (deliberate:
/// Windows exports WebP/GIF via the shipped encoders).
///
/// Contract (all methods invoked from the export isolate via
/// BackgroundIsolateBinaryMessenger): `start` → `feed`×N (awaited per frame — the
/// backpressure) → `finish` → output path. `abort` cleans up after cancel/error.
/// A missing host handler (platform without the channel) surfaces as
/// [MissingPluginException] from `start` — callers treat it as "MP4 unsupported here".
class Mp4EncoderChannel {
  static const MethodChannel _channel = MethodChannel('club.makapix.app/timelapse');

  Future<void> start({
    required int width,
    required int height,
    required int fps,
    required int bitrateBps,
    required String path,
  }) {
    return _channel.invokeMethod<void>('start', {
      'width': width,
      'height': height,
      'fps': fps,
      'bitrateBps': bitrateBps,
      'path': path,
    });
  }

  /// Feed one tightly-packed I420 frame (w*h*3/2 bytes) at [ptsUs]. Awaited: at most one
  /// frame is in flight, so the encoder thread never queues unboundedly.
  Future<void> feed(Uint8List i420, int ptsUs) {
    return _channel.invokeMethod<void>('feed', {'bytes': i420, 'ptsUs': ptsUs});
  }

  /// Drain, stop, and return the finished MP4's path.
  Future<String> finish() async {
    return await _channel.invokeMethod<String>('finish') ?? '';
  }

  Future<void> abort() async {
    try {
      await _channel.invokeMethod<void>('abort');
    } catch (_) {/* cleanup is best-effort */}
  }
}
