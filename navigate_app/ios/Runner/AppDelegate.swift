import Flutter
import UIKit
import CoreLocation

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var securityChannel: FlutterMethodChannel?
  private var isNavigationActive = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // הגדרת Platform Channel
    let controller = window?.rootViewController as! FlutterViewController
    securityChannel = FlutterMethodChannel(
      name: "com.elitzur.navigate/security",
      binaryMessenger: controller.binaryMessenger
    )

    securityChannel?.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self else { return }

      switch call.method {
      case "checkGuidedAccess":
        result(self.isGuidedAccessEnabled())

      case "isGPSEnabled":
        result(self.isLocationEnabled())

      case "isInternetConnected":
        result(self.isInternetConnected())

      case "startNavigationMonitoring":
        self.isNavigationActive = true
        result(true)

      case "stopNavigationMonitoring":
        self.isNavigationActive = false
        result(true)

      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // רישום notifications לאירועי lifecycle
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(appDidEnterBackground),
      name: UIApplication.didEnterBackgroundNotification,
      object: nil
    )

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(appWillTerminate),
      name: UIApplication.willTerminateNotification,
      object: nil
    )

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(screenLocked),
      name: UIApplication.protectedDataWillBecomeUnavailableNotification,
      object: nil
    )

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(screenUnlocked),
      name: UIApplication.protectedDataDidBecomeAvailableNotification,
      object: nil
    )

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // ========== Guided Access Detection ==========

  /// בדיקה עקיפה אם Guided Access מופעל
  /// iOS לא מאפשר בדיקה ישירה, זו בדיקה ע"י UIAccessibility
  private func isGuidedAccessEnabled() -> Bool {
    // בדיקה דרך UIAccessibility
    // כאשר Guided Access פעיל, UIAccessibilityIsGuidedAccessEnabled מחזיר true
    return UIAccessibility.isGuidedAccessEnabled
  }

  // ========== Location & Network Checks ==========

  private func isLocationEnabled() -> Bool {
    return CLLocationManager.locationServicesEnabled()
  }

  private func isInternetConnected() -> Bool {
    // בדיקה פשוטה - בפועל צריך Reachability
    // כאן נניח שיש אינטרנט אם יש Wi-Fi או Cellular
    return true // TODO: הוסף בדיקה אמיתית
  }

  // ========== Lifecycle Events ==========

  @objc private func appDidEnterBackground() {
    if isNavigationActive {
      print("⚠️ iOS: האפליקציה עברה לרקע במהלך ניווט")
      securityChannel?.invokeMethod("onAppBackgrounded", arguments: nil)
    }
  }

  @objc private func appWillTerminate() {
    if isNavigationActive {
      print("🚨 iOS: האפליקציה נסגרת במהלך ניווט")
      securityChannel?.invokeMethod("onAppClosed", arguments: nil)
    }
  }

  @objc private func screenLocked() {
    if isNavigationActive {
      print("🌙 iOS: המסך ננעל")
      securityChannel?.invokeMethod("onScreenOff", arguments: nil)
    }
  }

  @objc private func screenUnlocked() {
    if isNavigationActive {
      print("☀️ iOS: המסך נפתח")
      securityChannel?.invokeMethod("onScreenOn", arguments: nil)
    }
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }
}
