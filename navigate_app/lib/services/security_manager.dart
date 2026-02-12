import 'dart:async';
import 'package:uuid/uuid.dart';
import '../domain/entities/security_violation.dart';
import '../data/repositories/security_violation_repository.dart';
import 'device_security_service.dart';

/// מנהל אבטחה מרכזי
class SecurityManager {
  final DeviceSecurityService _deviceSecurity = DeviceSecurityService();
  final SecurityViolationRepository _violationRepo = SecurityViolationRepository();
  final Uuid _uuid = const Uuid();

  String? _currentNavigationId;
  String? _currentNavigatorId;
  SecuritySettings? _currentSettings;
  StreamController<SecurityViolation>? _violationStream;

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
  }) async {
    print('🔒 מתחיל ניטור אבטחה לניווט $navigationId');

    _currentNavigationId = navigationId;
    _currentNavigatorId = navigatorId;
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

    // ביטול נעילה
    final securityLevel = await _deviceSecurity.getSecurityLevel();

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
    _currentSettings = null;
    await _violationStream?.close();
    _violationStream = null;

    print('✓ ניטור אבטחה הופסק');
  }

  /// טיפול בחריגה
  Future<void> _handleViolation(ViolationType type) async {
    print('🚨 זוהתה חריגה: ${type.displayName}');

    if (!isMonitoring) return;

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

    await _logViolation(type, severity, type.displayName);
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
      print('🚨 התראה: $count חריגות - חרג מהמותר!');
      // TODO: שליחת התראה למפקד
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
