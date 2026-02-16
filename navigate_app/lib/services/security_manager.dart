import 'dart:async';
import 'package:uuid/uuid.dart';
import '../domain/entities/security_violation.dart';
import '../domain/entities/checkpoint_punch.dart';
import '../domain/entities/coordinate.dart';
import '../data/repositories/security_violation_repository.dart';
import '../data/repositories/navigator_alert_repository.dart';
import 'device_security_service.dart';

/// מנהל אבטחה מרכזי
class SecurityManager {
  final DeviceSecurityService _deviceSecurity = DeviceSecurityService();
  final SecurityViolationRepository _violationRepo = SecurityViolationRepository();
  final NavigatorAlertRepository _alertRepo = NavigatorAlertRepository();
  final Uuid _uuid = const Uuid();

  String? _currentNavigationId;
  String? _currentNavigatorId;
  String? _currentNavigatorName;
  SecuritySettings? _currentSettings;
  StreamController<SecurityViolation>? _violationStream;

  /// Debounce: זמן אחרון שכל סוג חריגה נרשם
  final Map<ViolationType, DateTime> _lastViolationTime = {};

  /// Cooldown: זמן אחרון ששלחנו alert למפקד
  DateTime? _lastAlertSentTime;

  /// callback לפסילת מנווט כשמתרחשת חריגה קריטית
  Function(ViolationType)? onCriticalViolation;

  /// האם בוצע ניטור כרגע
  bool get isMonitoring => _currentNavigationId != null;

  /// Stream של חריגות
  Stream<SecurityViolation> get violationStream =>
      _violationStream?.stream ?? const Stream.empty();

  /// התחלת ניטור אבטחה לניווט
  Future<bool> startNavigationSecurity({
    required String navigationId,
    required String navigatorId,
    required SecuritySettings settings,
    String? navigatorName,
  }) async {
    print('🔒 מתחיל ניטור אבטחה לניווט $navigationId');

    _currentNavigationId = navigationId;
    _currentNavigatorId = navigatorId;
    _currentNavigatorName = navigatorName;
    _currentSettings = settings;
    _violationStream = StreamController<SecurityViolation>.broadcast();

    // קבלת רמת האבטחה
    final securityLevel = await _deviceSecurity.getSecurityLevel();
    print('🛡️ רמת אבטחה: ${securityLevel.displayName}');

    bool success = false;

    switch (securityLevel) {
      case SecurityLevel.lockTask:
        // Android BYOD - Lock Task
        if (settings.lockTaskEnabled) {
          success = await _deviceSecurity.enableLockTask();
        }
        break;

      case SecurityLevel.kioskMode:
        // Android חברה - Kiosk Mode מלא
        success = await _deviceSecurity.enableKioskMode();
        break;

      case SecurityLevel.guidedAccess:
        // iOS - בדיקה שהופעל
        if (settings.requireGuidedAccess) {
          success = await _deviceSecurity.isGuidedAccessEnabled();
          if (!success) {
            print('⚠️ iOS: Guided Access לא מופעל!');
          }
        }
        break;

      case SecurityLevel.none:
        // Desktop - אין נעילה
        success = true;
        break;
    }

    if (success) {
      // התחלת ניטור אירועים
      _deviceSecurity.startMonitoring(
        onViolation: (type) => _handleViolation(type),
      );
      print('✓ ניטור אבטחה פעיל');
    }

    return success;
  }

  /// עצירת ניטור אבטחה
  Future<void> stopNavigationSecurity({bool normalEnd = true}) async {
    if (!isMonitoring) return;

    print('🔓 מפסיק ניטור אבטחה');

    // עצירת ניטור אירועים
    _deviceSecurity.stopMonitoring();

    if (!normalEnd) {
      // סיום חריג - רישום
      await _logViolation(
        ViolationType.appClosed,
        ViolationSeverity.high,
        'ניווט הסתיים באופן חריג',
      );
    }

    // ניקוי
    _currentNavigationId = null;
    _currentNavigatorId = null;
    _currentNavigatorName = null;
    _currentSettings = null;
    onCriticalViolation = null;
    _lastViolationTime.clear();
    _lastAlertSentTime = null;
    await _violationStream?.close();
    _violationStream = null;

    print('✓ ניטור אבטחה הופסק');
  }

  /// טיפול בחריגה
  Future<void> _handleViolation(ViolationType type) async {
    print('🚨 זוהתה חריגה: ${type.displayName}');

    if (!isMonitoring) return;

    // סינון לפי הגדרות — אם ההגדרה כבויה, לא מתעדים כלל
    if (_currentSettings != null) {
      if ((type == ViolationType.screenOff || type == ViolationType.screenOn) &&
          !_currentSettings!.alertOnScreenOff) {
        print('🔇 דילוג על חריגת מסך (alertOnScreenOff=false)');
        return;
      }
      if (type == ViolationType.appBackgrounded &&
          !_currentSettings!.alertOnBackground) {
        print('🔇 דילוג על מעבר לרקע (alertOnBackground=false)');
        return;
      }
    }

    // קביעת חומרה
    ViolationSeverity severity;
    switch (type) {
      case ViolationType.exitLockTask:
      case ViolationType.exitGuidedAccess:
      case ViolationType.appClosed:
        severity = ViolationSeverity.critical;
        break;
      case ViolationType.appBackgrounded:
        severity = ViolationSeverity.high;
        break;
      case ViolationType.gpsDisabled:
      case ViolationType.internetDisconnected:
        severity = ViolationSeverity.medium;
        break;
      case ViolationType.screenOff:
      case ViolationType.screenOn:
        severity = ViolationSeverity.low;
        break;
    }

    // Debounce — חריגות קריטיות תמיד מיידיות, אחרות לפי cooldown
    if (severity != ViolationSeverity.critical) {
      final lastTime = _lastViolationTime[type];
      if (lastTime != null) {
        final debounceSeconds = _getDebounceSeconds(type);
        if (DateTime.now().difference(lastTime).inSeconds < debounceSeconds) {
          print('🔇 debounce: דילוג על ${type.displayName} (< ${debounceSeconds}s)');
          return;
        }
      }
    }
    _lastViolationTime[type] = DateTime.now();

    await _logViolation(type, severity, type.displayName);

    // חריגות קריטיות — פסילת מנווט
    if (severity == ViolationSeverity.critical) {
      onCriticalViolation?.call(type);
    }
  }

  /// זמן debounce בשניות לפי סוג חריגה
  int _getDebounceSeconds(ViolationType type) {
    switch (type) {
      case ViolationType.screenOff:
      case ViolationType.screenOn:
        return 300; // 5 דקות
      case ViolationType.appBackgrounded:
        return 60; // דקה
      case ViolationType.gpsDisabled:
      case ViolationType.internetDisconnected:
        return 180; // 3 דקות
      default:
        return 0; // קריטי — ללא debounce
    }
  }

  /// רישום חריגה
  Future<void> _logViolation(
    ViolationType type,
    ViolationSeverity severity,
    String description,
  ) async {
    if (_currentNavigationId == null || _currentNavigatorId == null) return;

    final violation = SecurityViolation(
      id: _uuid.v4(),
      navigationId: _currentNavigationId!,
      navigatorId: _currentNavigatorId!,
      type: type,
      severity: severity,
      description: description,
      timestamp: DateTime.now(),
      metadata: {
        'deviceType': _deviceSecurity.isAndroid ? 'android' : 'ios',
      },
    );

    // שמירה ב-DB
    await _violationRepo.create(violation);

    // שידור ב-Stream
    _violationStream?.add(violation);

    // בדיקת מספר חריגות
    final violations = await _violationRepo.getByNavigation(_currentNavigationId!);
    final count = violations.length;

    if (_currentSettings != null &&
        count >= _currentSettings!.maxViolationsBeforeAlert) {
      // Cooldown — חריגות קריטיות עוקפות, אחרות ב-cooldown של 5 דקות
      final isCritical = severity == ViolationSeverity.critical;
      final shouldSend = isCritical ||
          _lastAlertSentTime == null ||
          DateTime.now().difference(_lastAlertSentTime!).inMinutes >= 5;

      if (shouldSend) {
        print('🚨 התראה: $count חריגות - חרג מהמותר!');
        await _sendSecurityAlert(description);
        _lastAlertSentTime = DateTime.now();
      } else {
        print('🔇 cooldown: דילוג על alert למפקד (< 5 דקות)');
      }
    }
  }

  /// שליחת NavigatorAlert למפקד על פריצת אבטחה
  Future<void> _sendSecurityAlert(String description) async {
    if (_currentNavigationId == null || _currentNavigatorId == null) return;

    try {
      final alert = NavigatorAlert(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        navigationId: _currentNavigationId!,
        navigatorId: _currentNavigatorId!,
        type: AlertType.securityBreach,
        location: const Coordinate(lat: 0, lng: 0, utm: ''),
        timestamp: DateTime.now(),
        navigatorName: _currentNavigatorName,
      );
      await _alertRepo.create(alert);
      print('🔓 התראת פריצת אבטחה נשלחה למפקד');
    } catch (e) {
      print('⚠️ שגיאה בשליחת התראת אבטחה: $e');
    }
  }

  /// שליחת התראת אבטחה חיצונית (לקריאה מ-active_view)
  Future<void> sendDisqualificationAlert({
    required String navigationId,
    required String navigatorId,
    String? navigatorName,
  }) async {
    try {
      final alert = NavigatorAlert(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        navigationId: navigationId,
        navigatorId: navigatorId,
        type: AlertType.securityBreach,
        location: const Coordinate(lat: 0, lng: 0, utm: ''),
        timestamp: DateTime.now(),
        navigatorName: navigatorName,
      );
      await _alertRepo.create(alert);
      print('🔓 התראת פסילה נשלחה למפקד');
    } catch (e) {
      print('⚠️ שגיאה בשליחת התראת פסילה: $e');
    }
  }

  /// בדיקות מערכת לפני התחלת ניווט
  Future<Map<String, bool>> performSystemCheck() async {
    return {
      'gps': await _deviceSecurity.isGPSEnabled(),
      'internet': await _deviceSecurity.isInternetConnected(),
      'guidedAccess': _deviceSecurity.isIOS
          ? await _deviceSecurity.isGuidedAccessEnabled()
          : true,
    };
  }

  /// קבלת רמת אבטחה נוכחית
  Future<SecurityLevel> getSecurityLevel() async {
    return await _deviceSecurity.getSecurityLevel();
  }
}
