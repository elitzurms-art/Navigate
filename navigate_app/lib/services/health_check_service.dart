import 'dart:async';
import 'package:flutter/services.dart';
import '../domain/entities/checkpoint_punch.dart';
import '../domain/entities/coordinate.dart';
import '../data/repositories/navigator_alert_repository.dart';

/// שירות בדיקת תקינות מנווטים
///
/// מנהל טיימר שבודק אם המנווט דיווח תקינות בזמן.
/// אם לא דיווח — מפעיל צפצוף חזק כל דקה ומציג banner.
/// כשהמנווט מדווח — מאפס הכל.
class HealthCheckService {
  final int intervalMinutes;
  final String navigatorId;
  final String navigationId;
  final String navigatorName;
  final NavigatorAlertRepository alertRepository;
  final void Function(bool isAlarming, String message)? onAlarmStateChanged;

  Timer? _checkTimer;
  DateTime? _lastReportTime;
  bool _isAlarming = false;
  String _alarmMessage = '';
  bool _alertSent = false;

  bool get isAlarming => _isAlarming;
  String get alarmMessage => _alarmMessage;

  HealthCheckService({
    required this.intervalMinutes,
    required this.navigatorId,
    required this.navigationId,
    required this.navigatorName,
    required this.alertRepository,
    this.onAlarmStateChanged,
  });

  /// הפעלת בדיקת תקינות
  void start() {
    _lastReportTime = DateTime.now();
    _alertSent = false;
    // בדיקה כל דקה
    _checkTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _check();
    });
  }

  /// דיווח תקינות מהמנווט — מאפס טיימר ומפסיק צפצוף
  void reportHealthy() {
    _lastReportTime = DateTime.now();
    _alertSent = false;
    if (_isAlarming) {
      _isAlarming = false;
      _alarmMessage = '';
      onAlarmStateChanged?.call(false, '');
    }
  }

  /// reset מרחוק (מפקד אישר שהמנווט תקין)
  void remoteReset() {
    reportHealthy();
  }

  /// עצירה
  void stop() {
    _checkTimer?.cancel();
    _checkTimer = null;
    _isAlarming = false;
    _alarmMessage = '';
  }

  /// ניקוי משאבים
  void dispose() {
    stop();
  }

  void _check() {
    if (_lastReportTime == null) return;

    final elapsed = DateTime.now().difference(_lastReportTime!);
    final warningThreshold = Duration(minutes: intervalMinutes - 5);
    final expiredThreshold = Duration(minutes: intervalMinutes);

    if (elapsed >= warningThreshold) {
      final minutesLeft = intervalMinutes - elapsed.inMinutes;
      if (minutesLeft > 0) {
        _alarmMessage = 'לא דיווחת תקינות! נותרו $minutesLeft דקות';
      } else {
        final overdue = elapsed.inMinutes - intervalMinutes;
        _alarmMessage = 'לא דיווחת תקינות! עברו $overdue דקות מעבר לזמן';
      }

      if (!_isAlarming) {
        _isAlarming = true;
      }

      // צפצוף כל דקה
      SystemSound.play(SystemSoundType.alert);

      onAlarmStateChanged?.call(true, _alarmMessage);

      // שליחת התראה למפקדים אחרי שעבר הזמן המלא
      if (elapsed >= expiredThreshold && !_alertSent) {
        _alertSent = true;
        _sendHealthCheckExpiredAlert(elapsed.inMinutes - intervalMinutes);
      }
    }
  }

  Future<void> _sendHealthCheckExpiredAlert(int minutesOverdue) async {
    try {
      final alert = NavigatorAlert(
        id: '${DateTime.now().millisecondsSinceEpoch}_health',
        navigationId: navigationId,
        navigatorId: navigatorId,
        type: AlertType.healthCheckExpired,
        location: const Coordinate(lat: 0, lng: 0, utm: ''),
        timestamp: DateTime.now(),
        navigatorName: navigatorName,
        minutesOverdue: minutesOverdue,
      );
      await alertRepository.create(alert);
    } catch (e) {
      print('DEBUG HealthCheckService: failed to send alert: $e');
    }
  }
}
