import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Install the UNUserNotificationCenter delegate BEFORE super. Firebase
    // only swizzles the delegate chain after `Firebase.initializeApp()`
    // runs from Dart, which on a cold-start push launch happens AFTER
    // SceneDelegate.scene(_:willConnectTo:) has already fired. Having a
    // delegate in place from the first moment guarantees:
    //   • `connectionOptions.notificationResponse` is populated for scene,
    //   • `userNotificationCenter(_:didReceive:)` fires for warm taps,
    //   • `userNotificationCenter(_:willPresent:)` fires in foreground,
    // regardless of whether Firebase has initialized yet.
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }
    application.registerForRemoteNotifications()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    if let destination = SceneDelegate.destination(
      inside: response.notification.request.content.userInfo
    ) {
      SceneDelegate.persist(destination)
    }
    super.userNotificationCenter(
      center,
      didReceive: response,
      withCompletionHandler: completionHandler
    )
  }

  // Allow the banner / sound to appear even while the app is foreground —
  // without this the backend push lands silently and the user never sees
  // the tap they would otherwise follow.
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler:
      @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .list, .sound, .badge])
    } else {
      completionHandler([.alert, .sound, .badge])
    }
  }
}
