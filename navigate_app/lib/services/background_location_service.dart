import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// שירות foreground service להמשך מעקב GPS ברקע.
/// מפעיל notification קבוע שמחזיק את תהליך האפליקציה חי —
/// כך שה-Timer + Geolocator ב-GPSTrackingService ממשיכים לעבוד.
class BackgroundLocationService {
  static final BackgroundLocationService _instance =
      BackgroundLocationService._();
  factory BackgroundLocationService() => _instance;
  BackgroundLocationService._();

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  /// אתחול — קוראים פעם אחת ב-main.dart
  void init() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'gps_tracking_channel',
        channelName: 'מעקב GPS',
        channelDescription: 'מעקב GPS בזמן ניווט פעיל',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  /// הפעלת foreground service — קוראים ב-_startGpsTracking
  Future<void> start() async {
    if (_isRunning) return;

    final result = await FlutterForegroundTask.startService(
      notificationTitle: 'ניווט פעיל',
      notificationText: 'מעקב GPS פועל ברקע',
      callback: _startCallback,
    );

    if (result is ServiceRequestSuccess) {
      _isRunning = true;
      print('BackgroundLocationService: foreground service started');
    } else {
      print('BackgroundLocationService: failed to start — $result');
    }
  }

  /// עצירת foreground service — קוראים ב-_stopGpsTracking / סיום ניווט
  Future<void> stop() async {
    if (!_isRunning) return;

    final result = await FlutterForegroundTask.stopService();
    if (result is ServiceRequestSuccess) {
      _isRunning = false;
      print('BackgroundLocationService: foreground service stopped');
    } else {
      print('BackgroundLocationService: failed to stop — $result');
    }
  }
}

// TaskHandler מינימלי — לא צריך לעשות כלום, רק לשמור את ה-service חי
@pragma('vm:entry-point')
void _startCallback() {
  FlutterForegroundTask.setTaskHandler(_MinimalTaskHandler());
}

class _MinimalTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {}
}
