import 'dart:io';
// import 'package:sms_advanced/sms_advanced.dart'; // זמנית מושבת

/// שירות שליחת SMS (Android בלבד)
/// NOTE: SMS זמנית מושבת - דורש חבילת sms_advanced שלא תואמת ל-Gradle החדש
class SmsService {
  // final SmsSender _smsSender = SmsSender();

  /// שליחת SMS
  ///
  /// [phoneNumber] - מספר טלפון נמען
  /// [message] - תוכן ההודעה
  ///
  /// מחזיר true אם ההודעה נשלחה בהצלחה
  Future<bool> sendSms({
    required String phoneNumber,
    required String message,
  }) async {
    // TODO: להוסיף חזרה כש-sms_advanced יתעדכן או למצוא אלטרנטיבה
    throw UnsupportedError('שליחת SMS זמנית לא זמינה - צריך מכשיר אמיתי עם חבילת SMS');

    // בדיקה שזה Android
    // if (!Platform.isAndroid) {
    //   throw UnsupportedError('שליחת SMS נתמכת רק ב-Android');
    // }

    // try {
    //   final SmsMessage smsMessage = SmsMessage(
    //     phoneNumber,
    //     message,
    //   );

    //   await _smsSender.sendSms(smsMessage);
    //   return true;
    // } catch (e) {
    //   return false;
    // }
  }

  /// שליחת SMS למספר נמענים
  Future<Map<String, bool>> sendBulkSms({
    required List<String> phoneNumbers,
    required String message,
  }) async {
    final results = <String, bool>{};

    for (final phoneNumber in phoneNumbers) {
      try {
        final success = await sendSms(
          phoneNumber: phoneNumber,
          message: message,
        );
        results[phoneNumber] = success;
      } catch (e) {
        results[phoneNumber] = false;
      }
    }

    return results;
  }

  /// שליחת הודעת חירום לרשימת מפקדים
  Future<void> sendEmergencySms({
    required List<String> commanderPhones,
    required String navigatorName,
    required String coordinates,
  }) async {
    final message = '''
🚨 חירום!

מנווט: $navigatorName
נ.צ. אחרונה: $coordinates

דורש סיוע מיידי
''';

    await sendBulkSms(
      phoneNumbers: commanderPhones,
      message: message,
    );
  }

  /// שליחת הודעת "ברבור" (מנווט אבוד)
  Future<void> sendLostNavigatorSms({
    required List<String> commanderPhones,
    required String navigatorName,
    required String coordinates,
  }) async {
    final message = '''
ℹ️ מנווט מבקש עזרה

מנווט: $navigatorName
נ.צ. אחרונה: $coordinates

המנווט מבקש הדרכה
''';

    await sendBulkSms(
      phoneNumbers: commanderPhones,
      message: message,
    );
  }

  /// פורמט מספר טלפון ישראלי
  ///
  /// הופך מספר כמו 0501234567 ל-+972501234567
  static String formatIsraeliPhoneNumber(String phoneNumber) {
    // הסרת רווחים ומקפים
    phoneNumber = phoneNumber.replaceAll(RegExp(r'[\s-]'), '');

    // אם מתחיל ב-0, להחליף ל-+972
    if (phoneNumber.startsWith('0')) {
      return '+972${phoneNumber.substring(1)}';
    }

    // אם לא מתחיל ב-+, להוסיף +972
    if (!phoneNumber.startsWith('+')) {
      return '+972$phoneNumber';
    }

    return phoneNumber;
  }

  /// בדיקת תקינות מספר טלפון ישראלי
  static bool isValidIsraeliPhone(String phoneNumber) {
    // הסרת רווחים ומקפים
    phoneNumber = phoneNumber.replaceAll(RegExp(r'[\s-]'), '');

    // פורמטים תקינים:
    // 0501234567 (10 ספרות)
    // +972501234567 (12 ספרות עם +972)
    final regex = RegExp(r'^(0\d{9}|\+972\d{9})$');
    return regex.hasMatch(phoneNumber);
  }
}
