import 'dart:io' show Platform;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// שירות התראות להורדת מפות אופליין — מציג notification עם progress bar
class MapDownloadNotificationService {
  static final MapDownloadNotificationService _instance =
      MapDownloadNotificationService._internal();
  factory MapDownloadNotificationService() => _instance;
  MapDownloadNotificationService._internal();

  static const _channelId = 'map_download_channel';
  static const _channelName = 'הורדת מפות';
  static const _channelDescription = 'התראות התקדמות הורדת מפות אופליין';
  static const _notificationId = 9001;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    // Notifications are only relevant on mobile platforms
    if (!Platform.isAndroid && !Platform.isIOS) {
      _initialized = true;
      return;
    }

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(initSettings);
    _initialized = true;
  }

  /// הצגת התקדמות הורדה (0-100)
  Future<void> showProgress(int progress, int maxProgress) async {
    if (!_initialized) return;

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.low,
      priority: Priority.low,
      showProgress: true,
      maxProgress: maxProgress,
      progress: progress,
      ongoing: true,
      onlyAlertOnce: true,
      autoCancel: false,
      playSound: false,
      enableVibration: false,
    );

    final details = NotificationDetails(android: androidDetails);

    await _plugin.show(
      _notificationId,
      'מוריד מפות אופליין',
      '$progress%',
      details,
    );
  }

  /// הצגת הודעת סיום הצלחה
  Future<void> showCompleted() async {
    if (!_initialized) return;

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      ongoing: false,
      autoCancel: true,
      playSound: false,
    );

    const details = NotificationDetails(android: androidDetails);

    await _plugin.show(
      _notificationId,
      'הורדת מפות הושלמה',
      'מפות אופליין מוכנות לשימוש',
      details,
    );
  }

  /// הצגת הודעת כישלון
  Future<void> showFailed() async {
    if (!_initialized) return;

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      ongoing: false,
      autoCancel: true,
      playSound: false,
    );

    const details = NotificationDetails(android: androidDetails);

    await _plugin.show(
      _notificationId,
      'הורדת מפות נכשלה',
      'ניתן לנסות שוב מבדיקת מערכות',
      details,
    );
  }

  /// ביטול/הסתרת ההתראה
  Future<void> dismiss() async {
    if (!_initialized) return;
    await _plugin.cancel(_notificationId);
  }
}
