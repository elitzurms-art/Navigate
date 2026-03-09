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

  /// 4️⃣ DND (נא לא להפריע) — Android בלבד

  /// הפעלת מצב נא לא להפריע
  Future<bool> enableDND() async {
    if (!isAndroid) return false;
    try {
      final result = await _channel.invokeMethod('enableDND');
      print('🔕 DND הופעל: $result');
      return result == true;
    } catch (e) {
      print('❌ שגיאה בהפעלת DND: $e');
      return false;
    }
  }

  /// ביטול מצב נא לא להפריע
  Future<bool> disableDND() async {
    if (!isAndroid) return false;
    try {
      final result = await _channel.invokeMethod('disableDND');
      print('🔔 DND בוטל');
      return result == true;
    } catch (e) {
      print('❌ שגיאה בביטול DND: $e');
      return false;
    }
  }

  /// בדיקה אם DND מופעל כרגע
  Future<bool> isDNDEnabled() async {
    try {
      final result = await _channel.invokeMethod('isDNDEnabled');
      return result == true;
    } catch (e) {
      return false;
    }
  }

  /// בדיקה אם יש הרשאת DND
  Future<bool> hasDNDPermission() async {
    try {
      final result = await _channel.invokeMethod('hasDNDPermission');
      return result == true;
    } catch (e) {
      return false;
    }
  }

  /// פתיחת הגדרות מערכת לאישור DND
  Future<void> requestDNDPermission() async {
    try {
      await _channel.invokeMethod('requestDNDPermission');
    } catch (e) {
      print('❌ שגיאה בפתיחת הגדרות DND: $e');
    }
  }

  /// 4.5 iOS Navigation Monitoring — הגדרת דגל ניווט פעיל ב-native

  /// התחלת ניטור ניווט (iOS) — מפעיל דגל isNavigationActive ב-Swift
  Future<void> startNavigationMonitoring() async {
    if (!isIOS) return;
    try {
      await _channel.invokeMethod('startNavigationMonitoring');
      print('🔒 iOS: ניטור ניווט הופעל');
    } catch (e) {
      print('❌ שגיאה בהפעלת ניטור ניווט iOS: $e');
    }
  }

  /// הפסקת ניטור ניווט (iOS) — מכבה דגל isNavigationActive ב-Swift
  Future<void> stopNavigationMonitoring() async {
    if (!isIOS) return;
    try {
      await _channel.invokeMethod('stopNavigationMonitoring');
      print('🔓 iOS: ניטור ניווט הופסק');
    } catch (e) {
      print('❌ שגיאה בהפסקת ניטור ניווט iOS: $e');
    }
  }

  /// בדיקת חבלה (iOS) — jailbreak, debugger, שעון מערכת
  Future<Map<String, bool>> checkAntiTampering() async {
    if (!isIOS) return {};
    try {
      final result = await _channel.invokeMethod('checkAntiTampering');
      return Map<String, bool>.from(result as Map);
    } catch (e) {
      print('❌ שגיאה בבדיקת anti-tampering: $e');
      return {};
    }
  }

  /// בדיקת מצב חזית (iOS) — האם האפליקציה בחזית
  Future<bool> checkForegroundState() async {
    if (!isIOS) return true;
    try {
      final result = await _channel.invokeMethod('checkForegroundState');
      return result == true;
    } catch (e) {
      return true; // ברירת מחדל — מניח שבחזית
    }
  }

  /// 5️⃣ ניטור שיחות טלפון — Android + iOS

  /// התחלת ניטור שיחות
  Future<void> startCallMonitoring() async {
    try {
      await _channel.invokeMethod('startCallMonitoring');
      print('📞 ניטור שיחות הופעל');
    } catch (e) {
      print('❌ שגיאה בהפעלת ניטור שיחות: $e');
    }
  }

  /// הפסקת ניטור שיחות
  Future<void> stopCallMonitoring() async {
    try {
      await _channel.invokeMethod('stopCallMonitoring');
      print('📞 ניטור שיחות הופסק');
    } catch (e) {
      print('❌ שגיאה בהפסקת ניטור שיחות: $e');
    }
  }

  /// 6️⃣ ניטור חריגות

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
        case 'onCallAnswered':
          onViolation(ViolationType.phoneCallAnswered);
          break;
        case 'onAppResignedActive':
          onViolation(ViolationType.appResignedActive);
          break;
        case 'onAppBecameActive':
          onViolation(ViolationType.appBecameActive);
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
