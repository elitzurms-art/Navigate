import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';
import 'package:url_launcher/url_launcher.dart';

/// סוג עדכון
enum UpdateType { none, recommended, forced }

/// מידע על עדכון זמין
class UpdateInfo {
  final UpdateType type;
  final String storeUrl;
  final String title;
  final String message;

  const UpdateInfo._({
    required this.type,
    this.storeUrl = '',
    this.title = '',
    this.message = '',
  });

  static const none = UpdateInfo._(type: UpdateType.none);

  factory UpdateInfo.recommended({
    required String storeUrl,
    required String title,
    required String message,
  }) =>
      UpdateInfo._(
        type: UpdateType.recommended,
        storeUrl: storeUrl,
        title: title,
        message: message,
      );

  factory UpdateInfo.forced({
    required String storeUrl,
    required String title,
    required String message,
  }) =>
      UpdateInfo._(
        type: UpdateType.forced,
        storeUrl: storeUrl,
        title: title,
        message: message,
      );
}

/// שירות בדיקת עדכונים — singleton
/// משתמש ב-Firebase Remote Config לבדוק גרסה מינימלית וגרסה אחרונה
class AppUpdateService {
  static final AppUpdateService _instance = AppUpdateService._internal();
  factory AppUpdateService() => _instance;
  AppUpdateService._internal();

  final FirebaseRemoteConfig _remoteConfig = FirebaseRemoteConfig.instance;
  final ShorebirdUpdater _shorebirdUpdater = ShorebirdUpdater();
  static const _dismissedKey = 'app_update_dismissed_at';

  bool _initialized = false;

  /// אתחול Remote Config — קריאה חד-פעמית
  Future<void> initialize() async {
    if (_initialized) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;

    try {
      await _remoteConfig.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: kDebugMode
            ? Duration.zero
            : const Duration(hours: 12),
      ));
      await _remoteConfig.setDefaults({
        'latest_version': '1.0.0',
        'min_version': '1.0.0',
        'store_url':
            'https://play.google.com/store/apps/details?id=com.elitzur_software.navigate',
        'ios_store_url': '',
        'update_message': '',
        'force_update_title': '',
        'force_update_message': '',
        'recommended_update_title': '',
        'recommended_update_message': '',
      });
      await _remoteConfig.fetchAndActivate();
      _initialized = true;
    } catch (e) {
      print('DEBUG AppUpdateService: initialize error: $e');
    }
  }

  /// בדיקת עדכון — מחזיר UpdateInfo
  Future<UpdateInfo> checkForUpdate() async {
    if (!Platform.isAndroid && !Platform.isIOS) return UpdateInfo.none;
    if (!_initialized) return UpdateInfo.none;

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      final latestVersion = _remoteConfig.getString('latest_version');
      final minVersion = _remoteConfig.getString('min_version');
      final storeUrl = getStoreUrl();

      // אם אין לינק לחנות — לא מציג dialog
      if (storeUrl.isEmpty) return UpdateInfo.none;

      // עדכון כפוי — גרסה נוכחית מתחת למינימום
      if (_compareVersions(currentVersion, minVersion) < 0) {
        final title = _remoteConfig.getString('force_update_title');
        final message = _remoteConfig.getString('force_update_message');
        return UpdateInfo.forced(
          storeUrl: storeUrl,
          title: title.isNotEmpty ? title : 'נדרש עדכון',
          message: message.isNotEmpty
              ? message
              : 'גרסה חדשה של האפליקציה זמינה.\nיש לעדכן כדי להמשיך להשתמש.',
        );
      }

      // עדכון מומלץ — גרסה נוכחית מתחת לאחרונה
      if (_compareVersions(currentVersion, latestVersion) < 0) {
        // בדיקה אם המשתמש דחה ב-24 שעות האחרונות
        if (await _wasDismissedRecently()) return UpdateInfo.none;

        final title = _remoteConfig.getString('recommended_update_title');
        final message = _remoteConfig.getString('recommended_update_message');
        return UpdateInfo.recommended(
          storeUrl: storeUrl,
          title: title.isNotEmpty ? title : 'עדכון זמין',
          message: message.isNotEmpty
              ? message
              : 'גרסה חדשה של האפליקציה זמינה.\nמומלץ לעדכן לגרסה האחרונה.',
        );
      }

      return UpdateInfo.none;
    } catch (e) {
      print('DEBUG AppUpdateService: checkForUpdate error: $e');
      return UpdateInfo.none;
    }
  }

  /// כתובת חנות לפי פלטפורמה
  String getStoreUrl() {
    if (Platform.isAndroid) return _remoteConfig.getString('store_url');
    if (Platform.isIOS) return _remoteConfig.getString('ios_store_url');
    return '';
  }

  /// פתיחת חנות אפליקציות
  Future<void> openStore(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      print('DEBUG AppUpdateService: openStore error: $e');
    }
  }

  /// שמירת זמן דחיית עדכון מומלץ
  Future<void> saveDismissedTimestamp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_dismissedKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      print('DEBUG AppUpdateService: saveDismissedTimestamp error: $e');
    }
  }

  /// בדיקה אם המשתמש דחה עדכון ב-24 שעות האחרונות
  Future<bool> _wasDismissedRecently() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dismissedAt = prefs.getInt(_dismissedKey);
      if (dismissedAt == null) return false;

      final dismissedTime =
          DateTime.fromMillisecondsSinceEpoch(dismissedAt);
      final hoursSince = DateTime.now().difference(dismissedTime).inHours;
      return hoursSince < 24;
    } catch (_) {
      return false;
    }
  }

  /// השוואת גרסאות: -1 אם a < b, 0 אם שווה, 1 אם a > b
  int _compareVersions(String a, String b) {
    final aParts = a.split('.').map(_safeParse).toList();
    final bParts = b.split('.').map(_safeParse).toList();
    for (int i = 0; i < 3; i++) {
      final aVal = i < aParts.length ? aParts[i] : 0;
      final bVal = i < bParts.length ? bParts[i] : 0;
      if (aVal > bVal) return 1;
      if (aVal < bVal) return -1;
    }
    return 0;
  }

  int _safeParse(String value) => int.tryParse(value) ?? 0;

  // ─── Shorebird OTA ───────────────────────────────────────────

  /// האם האפליקציה רצה בסביבת Shorebird (נבנתה עם shorebird release)
  bool get isShorebirdAvailable => _shorebirdUpdater.isAvailable;

  /// מספר ה-patch הנוכחי (null אם אין patch)
  Future<int?> getCurrentPatchNumber() async {
    if (!isShorebirdAvailable) return null;
    try {
      final patch = await _shorebirdUpdater.readCurrentPatch();
      return patch?.number;
    } catch (e) {
      print('DEBUG AppUpdateService: getCurrentPatchNumber error: $e');
      return null;
    }
  }

  /// בדיקה מלאה: בודק, מוריד אם יש patch חדש, ומחזיר true אם צריך הפעלה מחדש
  Future<bool> checkAndDownloadPatch() async {
    if (!isShorebirdAvailable) return false;
    try {
      final status = await _shorebirdUpdater.checkForUpdate();

      if (status == UpdateStatus.restartRequired) {
        // patch כבר הורד — צריך רק הפעלה מחדש
        print('DEBUG AppUpdateService: Shorebird patch ready — restart needed');
        return true;
      }

      if (status == UpdateStatus.outdated) {
        // patch חדש זמין — הורדה
        print('DEBUG AppUpdateService: New Shorebird patch available, downloading...');
        await _shorebirdUpdater.update();
        print('DEBUG AppUpdateService: Shorebird patch downloaded — restart needed');
        return true;
      }

      return false;
    } on UpdateException catch (e) {
      print('DEBUG AppUpdateService: checkAndDownloadPatch error: $e');
      return false;
    } catch (e) {
      print('DEBUG AppUpdateService: checkAndDownloadPatch error: $e');
      return false;
    }
  }
}
