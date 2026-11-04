import Flutter
import UIKit
import UserNotifications

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
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NotificationCleanup") else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "omni_code/notification_cleanup", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      guard call.method == "clear",
        let args = call.arguments as? [String: Any],
        let sessionId = args["session_id"] as? String,
        let kind = args["kind"] as? String
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      let requestId = args["request_id"] as? String
      let center = UNUserNotificationCenter.current()
      center.getDeliveredNotifications { notifications in
        let identifiers = notifications.compactMap { notification -> String? in
          let info = notification.request.content.userInfo
          // Local notifications have plugin IDs and are cleared by Dart.
          guard let type = info["notification_type"] as? String,
            info["session_id"] as? String == sessionId,
            (kind == "approval") == (type == "approval_request")
          else { return nil }
          if kind == "approval", let requestId = requestId {
            guard let raw = info["payload_json"] as? String,
              let data = raw.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let session = payload["session"] as? [String: Any],
              let approval = session["pending_approval"] as? [String: Any],
              approval["request_id"] as? String == requestId
            else { return nil }
          }
          return notification.request.identifier
        }
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
        DispatchQueue.main.async { result(nil) }
      }
    }
  }
}
