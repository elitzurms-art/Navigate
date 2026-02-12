import 'dart:io';
import 'package:flutter/services.dart';
import '../domain/entities/security_violation.dart';

/// שירות ניהול אבטחת מכשיר
class DeviceSecurityService {
  static const MethodChannel _channel = MethodChannel('com.elitzur.navigate/security');

  /// בדיקת סוג מכשיר
  bool get isAndroid => Platform.isAndroid;
  bool get isIOS => Platform.isIOS;

  /// 1️⃣ Android Lock Task Mode

  /// הפעלת Lock Task Mode (Android)
  Future<bool> enableLockTask() async {
    if (!isAndroid) return false;

    try {
      final result = await _channel.invokeMethod('enableLockTask');
      print('🔒 Lock Task Mode הופעל: $result');
      return result == true;
    } catch (e) {
      print('❌ שגיאה בהפעלת Lock Task: $e');
      return false;
    }
  }

  /// ביטול Lock Task Mode (Android)
  Future<bool> disableLockTask(String unlockCode) async {
    if (!isAndroid) return false;

    try {
      final result = await _channel.invokeMethod('disableLockTask', {
        'unlockCode': unlockCode,
      });
      print('🔓 Lock Task Mode בוטל');
      return result == true;
    } catch (e) {
      print('❌ שגיאה בביטול Lock Task: $e');
      return false;
    }
  }

  /// בדיקה אם במצב Lock Task
  Future<bool> isInLockTaskMode() async {
    if (!isAndroid) return false;

    try {
      final result = await _channel.invokeMethod('isInLockTaskMode');
      return result == true;
    } catch (e) {
      return false;
    }
  }

  /// 2️⃣ iOS Guided Access

  /// הצגת הנחיות להפעלת Guided Access (iOS)
  Future<void> showGuidedAccessInstructions() async {
    // זה יוצג ב-UI, לא native
    return;
  }

  /// בדיקה אם Guided Access הופעל (iOS - בדיקה עקיפה)
  Future<bool> isGuidedAccessEnabled() async {
    if (!isIOS) return false;

    try {
      // iOS לא מאפשר בדיקה ישירה
      // נשתמש בבדיקה עקיפה דרך UIAccessibility
      final result = await _channel.invokeMethod('checkGuidedAccess');
      return result == true;
    } catch (e) {
      return false;
    }
  }

  /// 3️⃣ Device Owner (Android חברה)

  /// בדיקה אם האפליקציה היא Device Owner
  Future<bool> isDeviceOwner() async {
    if (!isAndroid) return false;

    try {
      final result = await _channel.invokeMethod('isDeviceOwner');
      return result == true;
    } catch (e) {
      return false;
    }
  }

  /// הפעלת Kiosk Mode מלא (Android Device Owner)
  Future<bool> enableKioskMode() async {
    if (!isAndroid) return false;

    try {
      final result = await _channel.invokeMethod('enableKioskMode');
      print('🔒 Kiosk Mode הופעל');
      return result == true;
    } catch (e) {
      print('❌ שגיאה בהפעלת Kiosk Mode: $e');
      return false;
    }
  }

  /// ביטול Kiosk Mode (דורש קוד מנהל)
  Future<bool> disableKioskMode(String adminCode) async {
    if (!isAndroid) return false;

    try {
      final result = await _channel.invokeMethod('disableKioskMode', {
        'adminCode': adminCode,
      });
      print('🔓 Kiosk Mode בוטל');
      return result == true;
    } catch (e) {
      print('❌ שגיאה בביטול Kiosk Mode: $e');
      return false;
    }
  }

  /// 4️⃣ ניטור חריגות

  /// רישום האזנה לאירועי מערכת
  void startMonitoring({
    required Function(ViolationType type) onViolation,
  }) {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onLockTaskExit':
          onViolation(ViolationType.exitLockTask);
          break;
        case 'onAppBackgrounded':
          onViolation(ViolationType.appBackgrounded);
          break;
        case 'onScreenOff':
          onViolation(ViolationType.screenOff);
          break;
        case 'onScreenOn':
          onViolation(ViolationType.screenOn);
          break;
        case 'onAppClosed':
          onViolation(ViolationType.appClosed);
          break;
        case 'onGuidedAccessExit':
          onViolation(ViolationType.exitGuidedAccess);
          break;
      }
    });
  }

  /// הפסקת ניטור
  void stopMonitoring() {
    _channel.setMethodCallHandler(null);
  }

  /// 5️⃣ פונקציות עזר

  /// בדיקת רמת אבטחה זמינה
  Future<SecurityLevel> getSecurityLevel() async {
    if (isAndroid) {
      final isOwner = await isDeviceOwner();
      if (isOwner) {
        return SecurityLevel.kioskMode; // Android חברה
      } else {
        return SecurityLevel.lockTask; // Android BYOD
      }
    } else if (isIOS) {
      return SecurityLevel.guidedAccess; // iOS
    } else {
      return SecurityLevel.none; // Windows/Desktop
    }
  }

  /// בדיקת GPS
  Future<bool> isGPSEnabled() async {
    try {
      final result = await _channel.invokeMethod('isGPSEnabled');
      return result == true;
    } catch (e) {
      return false;
    }
  }

  /// בדיקת אינטרנט
  Future<bool> isInternetConnected() async {
    try {
      final result = await _channel.invokeMethod('isInternetConnected');
      return result == true;
    } catch (e) {
      return false;
    }
  }
}

/// רמת אבטחה זמינה
enum SecurityLevel {
  none('none', 'אין'),
  guidedAccess('guided_access', 'Guided Access (iOS)'),
  lockTask('lock_task', 'Lock Task (Android BYOD)'),
  kioskMode('kiosk_mode', 'Kiosk Mode (Android חברה)');

  final String code;
  final String displayName;

  const SecurityLevel(this.code, this.displayName);
}
