import Flutter
import UIKit
import UserNotifications

class SceneDelegate: FlutterSceneDelegate {
  static let launchRouteKey = "flutter.gleam_launch_route"

  /// Keys the config endpoint / backend may use for the destination URL.
  /// Must stay a superset of what the real production push payloads carry
  /// — a payload shaped as `{"click_url": "..."}` was silently dropped
  /// before this list was expanded, so a killed-app tap opened the cached
  /// first page instead of the push target.
  static let urlKeys: [String] = [
    "click_url", "clickUrl", "clickurl",
    "deep_link", "deepLink", "deeplink",
    "target_url", "targetUrl", "target",
    "destination", "dest",
    "url", "link", "href",
    "open_url", "openUrl",
    "landing_url", "offer_url", "redirect_url", "action_url", "web_url",
  ]

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
      Self.persist(destination)
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
    return extract(from: payload)
  }

  // MARK: - URL extraction

  private static func extract(from any: Any?) -> String? {
    guard let any = any else { return nil }

    if let string = any as? String {
      let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.isEmpty { return nil }
      if isHttp(trimmed) { return trimmed }
      // Nested JSON blob (some backends send `data: "{...}"`).
      if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
        if let parsed = parseJson(trimmed) {
          return extract(from: parsed)
        }
      }
      return nil
    }

    if let dict = any as? [AnyHashable: Any] {
      // Lowercase lookup table so clickURL / Click_Url / CLICKURL match.
      var lower: [String: Any] = [:]
      for (key, value) in dict {
        lower[String(describing: key).lowercased()] = value
      }
      for key in urlKeys {
        if let hit = extract(from: lower[key.lowercased()]) { return hit }
      }
      // Recurse into every nested value — covers `data`, `payload`, `aps.alert`,
      // and any custom container the backend decides to use.
      for value in dict.values {
        if let hit = extract(from: value) { return hit }
      }
      return nil
    }

    if let array = any as? [Any] {
      for item in array {
        if let hit = extract(from: item) { return hit }
      }
      return nil
    }

    return nil
  }

  private static func isHttp(_ raw: String) -> Bool {
    return raw.hasPrefix("http://") || raw.hasPrefix("https://")
  }

  private static func parseJson(_ raw: String) -> Any? {
    guard let data = raw.data(using: .utf8) else { return nil }
    return try? JSONSerialization.jsonObject(
      with: data,
      options: [.fragmentsAllowed]
    )
  }
}
