import Flutter
import UIKit
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    WorkmanagerPlugin.registerPeriodicTask(withIdentifier: "au.monster.tracker.plus.sync", frequency: NSNumber(value: 15 * 60))
    WorkmanagerPlugin.registerPeriodicTask(withIdentifier: "au.monster.tracker.plus.backup", frequency: NSNumber(value: 24 * 60 * 60))
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
