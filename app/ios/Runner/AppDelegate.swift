import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // The Timelapse MP4 encoder channel (ADR 0004) — a hand-written host, not a plugin,
    // registered through a registrar so it works under the scene-based implicit engine.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "TimelapseChannel") {
      TimelapseChannel.register(with: registrar.messenger())
    }
  }
}
