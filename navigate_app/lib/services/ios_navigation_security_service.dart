import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../domain/entities/navigation_security_session.dart';
import 'device_security_service.dart';

/// שירות אבטחת ניווט ל-iOS — heartbeat, anti-tampering, session logging
///
/// מופעל רק כאשר `Platform.isIOS` — אפס השפעה על Android/Windows.
class IosNavigationSecurityService {
  final DeviceSecurityService _deviceSecurity = DeviceSecurityService();

  Timer? _heartbeatTimer;
  Timer? _antiTamperTimer;
  Timer? _flushTimer;

  NavigationSecuritySession? _session;
  final List<NavigationSecurityEvent> _pendingEvents = [];

  /// adaptive heartbeat — מצב רגיל (3s) / מצב איטי (10s)
  bool _adaptiveSlowMode = false;
  int _lifecycleEventCount = 0;

  /// מעקב אחרי יציאה מחזית — לחישוב interruptionDuration
  DateTime? _lastResignedActiveTime;

  /// דגל overlay — תצוגת באנר "ניווט פעיל — Guided Access"
  bool get showSecurityOverlay => _session != null;

  String? _navigationId;
  String? _navigatorId;

  /// התחלת סשן אבטחה
  Future<void> startSession(
    String navigationId,
    String navigatorId,
    bool guidedAccessConfirmed,
  ) async {
    if (!Platform.isIOS) return;

    _navigationId = navigationId;
    _navigatorId = navigatorId;

    _session = NavigationSecuritySession(
      navigationId: navigationId,
      navigatorId: navigatorId,
      startTime: DateTime.now(),
      guidedAccessConfirmed: guidedAccessConfirmed,
    );

    // אירוע התחלה
    logEvent(SecurityEventType.navigationStarted);
    if (guidedAccessConfirmed) {
      logEvent(SecurityEventType.guidedAccessConfirmed);
    }

    // heartbeat — מתחיל ב-3 שניות (מצב רגיל)
    _startHeartbeat(const Duration(seconds: 3));

    // anti-tampering — בדיקה ראשונית + כל 60 שניות
    await _runAntiTamperingCheck();
    _antiTamperTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _runAntiTamperingCheck(),
    );

    // flush מחזורי — כל 30 שניות
    _flushTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _flushToFirestore(),
    );

    // flush ראשוני
    await _flushToFirestore();
  }

  /// רישום אירוע אבטחה
  void logEvent(String eventType, {Map<String, dynamic>? context}) {
    if (_session == null) return;

    final event = NavigationSecurityEvent(
      eventType: eventType,
      timestamp: DateTime.now(),
      additionalContext: context,
    );
    _pendingEvents.add(event);

    // flush מיידי על אירועים קריטיים
    final criticalEvents = {
      SecurityEventType.foregroundIntegrityViolation,
      SecurityEventType.securityTamperingDetected,
      SecurityEventType.appResignedActive,
    };
    if (criticalEvents.contains(eventType)) {
      _flushToFirestore();
    }

    // flush כשצוברים 10+ אירועים
    if (_pendingEvents.length >= 10) {
      _flushToFirestore();
    }
  }

  /// אירוע lifecycle התקבל — לצורך adaptive heartbeat
  void onLifecycleEventReceived() {
    _lifecycleEventCount++;
    // אם קיבלנו 3+ lifecycle events → מצב איטי (10s)
    if (!_adaptiveSlowMode && _lifecycleEventCount >= 3) {
      _adaptiveSlowMode = true;
      _startHeartbeat(const Duration(seconds: 10));
    }
  }

  /// רישום יציאה ממצב פעיל — מעקב interruptionDuration
  void onResignedActive() {
    _lastResignedActiveTime = DateTime.now();
    logEvent(SecurityEventType.appResignedActive);
    onLifecycleEventReceived();

    // חזרה למצב מהיר אם יצאנו ממצב פעיל (anomaly)
    if (_adaptiveSlowMode) {
      _adaptiveSlowMode = false;
      _lifecycleEventCount = 0;
      _startHeartbeat(const Duration(seconds: 3));
    }
  }

  /// רישום חזרה למצב פעיל
  void onBecameActive() {
    final context = <String, dynamic>{};
    if (_lastResignedActiveTime != null) {
      final duration = DateTime.now().difference(_lastResignedActiveTime!);
      context['interruptionDurationMs'] = duration.inMilliseconds;
    }
    _lastResignedActiveTime = null;
    logEvent(SecurityEventType.appBecameActive, context: context);
    onLifecycleEventReceived();
  }

  /// סיום סשן אבטחה
  Future<void> endSession() async {
    if (_session == null) return;

    logEvent(SecurityEventType.navigationFinished);

    // flush אחרון עם endTime
    _session = _session!.copyWith(endTime: DateTime.now());
    await _flushToFirestore();

    _heartbeatTimer?.cancel();
    _antiTamperTimer?.cancel();
    _flushTimer?.cancel();
    _heartbeatTimer = null;
    _antiTamperTimer = null;
    _flushTimer = null;
    _session = null;
    _pendingEvents.clear();
    _navigationId = null;
    _navigatorId = null;
    _adaptiveSlowMode = false;
    _lifecycleEventCount = 0;
    _lastResignedActiveTime = null;
  }

  /// שחרור משאבים
  void dispose() {
    _heartbeatTimer?.cancel();
    _antiTamperTimer?.cancel();
    _flushTimer?.cancel();
  }

  // ===========================================================================
  // Private
  // ===========================================================================

  void _startHeartbeat(Duration interval) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(interval, (_) => _heartbeatCheck());
  }

  /// בדיקת heartbeat — cross-validation עם native foreground state
  Future<void> _heartbeatCheck() async {
    if (_session == null) return;

    try {
      final isForeground = await _deviceSecurity.checkForegroundState();
      if (!isForeground) {
        logEvent(SecurityEventType.foregroundIntegrityViolation, context: {
          'reason': 'heartbeat_foreground_mismatch',
        });
      }
    } catch (_) {
      // שגיאת platform channel — לא מדווח כחריגה
    }
  }

  /// בדיקת anti-tampering
  Future<void> _runAntiTamperingCheck() async {
    if (_session == null) return;

    try {
      final result = await _deviceSecurity.checkAntiTampering();
      if (result.isEmpty) return;

      final hasIssue = result.values.any((v) => v == true);
      if (hasIssue) {
        logEvent(SecurityEventType.securityTamperingDetected, context: {
          'debugger': result['debugger'] ?? false,
          'jailbreak': result['jailbreak'] ?? false,
          'timeAnomaly': result['timeAnomaly'] ?? false,
        });
      }
    } catch (_) {
      // שגיאת platform channel — לא מדווח
    }
  }

  /// כתיבת אירועים ל-Firestore — batch write with merge
  Future<void> _flushToFirestore() async {
    if (_navigationId == null || _navigatorId == null) return;
    if (_pendingEvents.isEmpty && _session?.endTime == null) return;

    final eventsToFlush = List<NavigationSecurityEvent>.from(_pendingEvents);
    _pendingEvents.clear();

    try {
      final docRef = FirebaseFirestore.instance
          .collection('navigations')
          .doc(_navigationId!)
          .collection('security_sessions')
          .doc(_navigatorId!);

      final data = <String, dynamic>{
        'navigationId': _navigationId,
        'navigatorId': _navigatorId,
        'startTime': _session!.startTime.toIso8601String(),
        'guidedAccessConfirmed': _session!.guidedAccessConfirmed,
      };

      if (_session?.endTime != null) {
        data['endTime'] = _session!.endTime!.toIso8601String();
      }

      if (eventsToFlush.isNotEmpty) {
        data['events'] = FieldValue.arrayUnion(
          eventsToFlush.map((e) => e.toMap()).toList(),
        );
      }

      data['updatedAt'] = FieldValue.serverTimestamp();

      await docRef.set(data, SetOptions(merge: true));
    } catch (e) {
      // כישלון flush — מחזיר אירועים לתור
      _pendingEvents.insertAll(0, eventsToFlush);
      print('⚠️ IosNavigationSecurityService: flush failed: $e');
    }
  }
}
