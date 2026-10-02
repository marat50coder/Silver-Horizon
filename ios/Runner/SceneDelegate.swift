import Flutter
import UIKit
import UserNotifications

class SceneDelegate: FlutterSceneDelegate {
  static let launchRouteKey = "flutter.gleam_launch_route"

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    // Write the tap URL BEFORE Flutter boots. SharedPreferences is read
    // from UserDefaults on the first Dart frame — if we call super first
    // the coordinator already consumed an empty key and opened the cached
    // first WebView page instead of the push destination.
    if let response = connectionOptions.notificationResponse,
       let destination = Self.destination(
         inside: response.notification.request.content.userInfo
       ) {
      persist(destination)
    }

    super.scene(scene, willConnectTo: session, options: connectionOptions)
  }

  static func persist(_ destination: String) {
    let defaults = UserDefaults.standard
    defaults.set(destination, forKey: launchRouteKey)
    defaults.synchronize()
    #if DEBUG
    NSLog("[HZ.ROUTE] captured notification destination")
    #endif
  }

  static func destination(
    inside payload: [AnyHashable: Any]
  ) -> String? {
    let candidates = ["deep_link", "target", "url", "deeplink", "link"]

    func firstValue(in dictionary: [AnyHashable: Any]) -> String? {
      for candidate in candidates {
        guard let value = dictionary[candidate] as? String else { continue }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
      }
      return nil
    }

    if let direct = firstValue(in: payload) { return direct }

    for container in ["payload", "data"] {
      if let nested = payload[container] as? [AnyHashable: Any],
         let value = firstValue(in: nested) {
        return value
      }
    }
    return nil
  }
}
