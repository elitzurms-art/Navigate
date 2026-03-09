import Flutter
import UIKit
import CoreLocation
import CallKit

@main
@objc class AppDelegate: FlutterAppDelegate, CXCallObserverDelegate {
  private var securityChannel: FlutterMethodChannel?
  private var isNavigationActive = false
  private var callObserver: CXCallObserver?

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

      // DND — לא זמין ב-iOS, מחזיר ערכי ברירת מחדל
      case "hasDNDPermission":
        result(true) // iOS לא תומך — נחשב כמאושר

      case "isDNDEnabled":
        result(false)

      case "enableDND":
        result(false)

      case "disableDND":
        result(false)

      // Call Monitoring — CallKit
      case "startCallMonitoring":
        self.startCallMonitoring()
        result(true)

      case "stopCallMonitoring":
        self.stopCallMonitoring()
        result(true)

      case "checkAntiTampering":
        let tamperingResult: [String: Bool] = [
          "debugger": self.isDebuggerAttached(),
          "jailbreak": self.isJailbroken(),
          "timeAnomaly": self.hasSystemTimeAnomaly(),
        ]
        result(tamperingResult)

      case "checkForegroundState":
        let isActive = UIApplication.shared.applicationState == .active
        result(isActive)

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

    // willResignActive — fires on Control Center, Notification Center, Siri, app switch
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(appWillResignActive),
      name: UIApplication.willResignActiveNotification,
      object: nil
    )

    // didBecomeActive — app returned to foreground
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(appDidBecomeActive),
      name: UIApplication.didBecomeActiveNotification,
      object: nil
    )

    // Guided Access status change
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(guidedAccessChanged),
      name: UIAccessibility.guidedAccessStatusDidChangeNotification,
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

  // ========== Call Monitoring (CallKit) ==========

  private func startCallMonitoring() {
    stopCallMonitoring()
    callObserver = CXCallObserver()
    callObserver?.setDelegate(self, queue: nil)
  }

  private func stopCallMonitoring() {
    callObserver?.setDelegate(nil, queue: nil)
    callObserver = nil
  }

  /// CXCallObserverDelegate — זיהוי מענה לשיחת טלפון
  func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
    if call.hasConnected && !call.hasEnded {
      // שיחה נענתה (OFFHOOK)
      securityChannel?.invokeMethod("onCallAnswered", arguments: nil)
    }
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

  // ========== Resign Active / Become Active ==========

  @objc private func appWillResignActive() {
    if isNavigationActive {
      print("⚠️ iOS: האפליקציה יצאה ממצב פעיל (resignActive)")
      securityChannel?.invokeMethod("onAppResignedActive", arguments: nil)
    }
  }

  @objc private func appDidBecomeActive() {
    if isNavigationActive {
      print("✅ iOS: האפליקציה חזרה למצב פעיל (becameActive)")
      securityChannel?.invokeMethod("onAppBecameActive", arguments: nil)
    }
  }

  @objc private func guidedAccessChanged() {
    if isNavigationActive && !isGuidedAccessEnabled() {
      print("🚨 iOS: Guided Access בוטל במהלך ניווט")
      securityChannel?.invokeMethod("onGuidedAccessExit", arguments: nil)
    }
  }

  // ========== Anti-Tampering Checks ==========

  /// בדיקה אם debugger מחובר — sysctl P_TRACED flag
  private func isDebuggerAttached() -> Bool {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
    let result = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
    if result != 0 { return false }
    return (info.kp_proc.p_flag & P_TRACED) != 0
  }

  /// בדיקת jailbreak — קיום קבצים חשודים בלבד (בטוח ל-App Store)
  private func isJailbroken() -> Bool {
    let suspiciousPaths = [
      "/Applications/Cydia.app",
      "/usr/sbin/sshd",
      "/etc/apt",
      "/private/var/lib/apt/",
      "/var/lib/cydia",
    ]
    for path in suspiciousPaths {
      if FileManager.default.fileExists(atPath: path) {
        return true
      }
    }
    return false
  }

  /// בדיקת חריגת שעון מערכת — השוואת systemUptime delta מול Date delta
  private var lastUptimeCheck: TimeInterval = 0
  private var lastDateCheck: Date = Date()

  private func hasSystemTimeAnomaly() -> Bool {
    let currentUptime = ProcessInfo.processInfo.systemUptime
    let currentDate = Date()

    if lastUptimeCheck == 0 {
      // בדיקה ראשונה — אתחול baseline
      lastUptimeCheck = currentUptime
      lastDateCheck = currentDate
      return false
    }

    let uptimeDelta = currentUptime - lastUptimeCheck
    let dateDelta = currentDate.timeIntervalSince(lastDateCheck)
    let drift = abs(dateDelta - uptimeDelta)

    // עדכון baseline
    lastUptimeCheck = currentUptime
    lastDateCheck = currentDate

    // סף 30 שניות — מונע false positives מתיקוני NTP
    return drift > 30
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
    stopCallMonitoring()
  }
}
