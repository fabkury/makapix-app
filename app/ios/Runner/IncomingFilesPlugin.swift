import Flutter
import UIKit

/// The native half of "Open in Makapix" (the Dart half and channel protocol live in
/// lib/shell/incoming_files.dart). Registered from AppDelegate as an ordinary plugin so
/// the engine's UIScene compatibility layer delivers file-open events here through the
/// legacy UIApplicationDelegate callbacks:
///  - warm opens:  scene:openURLContexts: → sceneFallbackOpenURLContexts: →
///                 application(_:open:options:)
///  - cold starts: scene:willConnectToSession:options: → sceneWillConnectFallback: →
///                 application(_:didFinishLaunchingWithOptions:) with the URL in the
///                 launch options
/// Payloads are buffered here and drained by Dart, so delivery never depends on the
/// Flutter side being up yet. Returning "handled" also keeps the engine's deep-linking
/// from pushing a file:// URL into the navigator.
public class IncomingFilesPlugin: NSObject, FlutterPlugin {
  /// Only the document types the app registers for (CFBundleDocumentTypes), and a size
  /// cap far above any real .mkps/.mkpx yet far below anything that could hurt — the
  /// engine's own budget checks are the real gate once the bytes reach Dart.
  private static let allowedExtensions: Set<String> = ["mkps", "mkpx"]
  private static let maxBytes = 64 * 1024 * 1024
  private static let maxQueued = 4

  private let channel: FlutterMethodChannel
  private var pending: [[String: Any]] = []

  init(channel: FlutterMethodChannel) {
    self.channel = channel
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "club.makapix.app/incoming_files", binaryMessenger: registrar.messenger())
    let instance = IncomingFilesPlugin(channel: channel)
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.addApplicationDelegate(instance)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "drainPendingFiles":
      let drained = pending
      pending.removeAll()
      result(drained)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - File-open entry points (via the engine's scene→application fallbacks)

  public func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any] = [:]
  ) -> Bool {
    if let url = launchOptions[.url] as? URL, ingest(url) {
      return false  // claimed — stops the engine deep-linking this launch URL
    }
    return true
  }

  public func application(
    _ application: UIApplication, open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    return ingest(url)
  }

  /// Read the file into the bounded queue and nudge Dart. Returns true when consumed.
  private func ingest(_ url: URL) -> Bool {
    guard url.isFileURL,
      IncomingFilesPlugin.allowedExtensions.contains(url.pathExtension.lowercased())
    else { return false }
    // Handed-over documents may be security-scoped (shares / file providers); the call
    // returns false when scoped access wasn't needed, which is fine to ignore.
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    guard let data = try? Data(contentsOf: url), !data.isEmpty,
      data.count <= IncomingFilesPlugin.maxBytes
    else { return false }
    if pending.count >= IncomingFilesPlugin.maxQueued {
      pending.removeFirst()
    }
    pending.append([
      "name": url.lastPathComponent,
      "bytes": FlutterStandardTypedData(bytes: data),
    ])
    channel.invokeMethod("filesPending", arguments: nil)
    return true
  }
}
