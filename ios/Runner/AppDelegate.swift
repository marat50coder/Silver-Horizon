import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Keep every hx_* export from the Rust math static library linked
    // into the release binary — without a visible compile-time reference
    // iOS `-dead_strip` would drop them, and the Dart FFI lookups would
    // fail at runtime with `Invalid argument(s): Failed to lookup symbol`.
    RustGlue.ensureLinked()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
