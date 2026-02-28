# App Store Submission Checklist

## תיקונים שבוצעו
- [x] הוספת `NSMicrophoneUsageDescription` ל-Info.plist (iOS)
- [x] עדכון iOS deployment target ל-16.0
- [x] יצירת `PrivacyInfo.xcprivacy` (Privacy Manifest)
- [x] הגנה על `ensureDeveloperUser` — רק ב-debug mode

## תיקונים נדרשים לפני העלאה לחנות

### קריטי (חנות תדחה)
- [x] הגדרת release signing (keystore) ל-Android — upload.jks + key.properties + build.gradle
- [ ] הוספת Privacy Policy URL — נדרש ל-Google Play ו-App Store
- [ ] הסרת/הגנה על 587 פקודות `print()` — להחליף ב-`kDebugMode` guard או logging service

### חשוב (עלול לגרום לדחייה)
- [ ] הגדרת Proguard/R8 ל-Android release — code obfuscation + minification
- [ ] בדיקת מדיניות Device Admin (wipe-data, disable-camera) — Google Play מקפיד
- [ ] תיקון `createdBy: ''` ב-boundary_repository.dart (TODO פתוח)

### המלצות (לא חוסם)
- [ ] הוספת `network_security_config.xml` — חסימת cleartext traffic
- [ ] הוספת Firebase Crashlytics — דיווח שגיאות בהקפה
- [ ] הוספת `FlutterError.onError` handler גלובלי
- [ ] הגדרת Firebase App Check — הגנה מפני שימוש לא מורשה
- [ ] תיקון Firebase config ל-macOS (placeholder values)

### SMS
- [ ] אימות SMS בפועל (SEND_SMS permission כבר מוצהר) — ייכנס בהמשך
