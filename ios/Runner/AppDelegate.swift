import Flutter
import UIKit
import flutter_local_notifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // A notification action tapped while the app is not running is handled on
    // a second, headless engine that flutter_local_notifications starts. The
    // plugin asserts this callback exists and then calls it unconditionally
    // (FlutterEngineManager.m, startEngineIfNeeded), so without it every such
    // tap crashes instead of logging the glass or the shot. It has to be set
    // here: didInitializeImplicitFlutterEngine below runs for the main engine
    // only.
    FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
      LiveActivityBridge.register(with: registry)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Dynamic Island / Lock Screen countdown. Hand-registered because it is
    // this app's own channel rather than a pub package, so it is not in
    // GeneratedPluginRegistrant.
    LiveActivityBridge.register(with: engineBridge.pluginRegistry)
  }
}
