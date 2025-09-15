import Flutter
import UIKit
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    if let apiKey = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String,
       !apiKey.isEmpty {
      GMSServices.provideAPIKey(apiKey)
    } else {
      #if DEBUG
      assertionFailure("Missing GMSApiKey in Info.plist")
      #else
      print("⚠️ Missing GMSApiKey in Info.plist")
      #endif
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
