import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:battery_plus/battery_plus.dart';
import '../../../../domain/entities/navigation.dart' as domain;
import '../../../../domain/entities/checkpoint_punch.dart';
import '../../../../domain/entities/coordinate.dart';
import '../../../../domain/entities/user.dart';
import '../../../../domain/entities/navigator_personal_status.dart';
import '../../../../data/repositories/navigation_track_repository.dart';
import '../../../../data/repositories/checkpoint_punch_repository.dart';
import '../../../../data/repositories/checkpoint_repository.dart';
import '../../../../data/repositories/navigator_alert_repository.dart';
import '../../../../data/datasources/local/app_database.dart' hide User;
import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/geometry_utils.dart';
import '../../../../domain/entities/checkpoint.dart' as domain_cp;
import '../../../../services/gps_service.dart';
import '../../../../services/gps_tracking_service.dart';
import '../../../../services/health_check_service.dart';
import '../../../../services/security_manager.dart';
import '../../../../services/device_security_service.dart';
import '../../../../services/alert_monitoring_service.dart';
import '../../../../domain/entities/security_violation.dart';
import '../../../widgets/unlock_dialog.dart';
import 'package:latlong2/latlong.dart';
import '../../../../data/repositories/boundary_repository.dart';
import 'manual_position_pin_screen.dart';

/// תצוגת ניווט פעיל למנווט — 3 מצבים: ממתין / פעיל / סיים
class ActiveView extends StatefulWidget {
  final domain.Navigation navigation;
  final User currentUser;
  final ValueChanged<domain.Navigation> onNavigationUpdated;
  final void Function(bool allowOpenMap, bool showSelfLocation, bool showRouteOnMap)? onMapPermissionsChanged;

  const ActiveView({
    super.key,
    required this.navigation,
    required this.currentUser,
    required this.onNavigationUpdated,
    this.onMapPermissionsChanged,
  });

  @override
  State<ActiveView> createState() => _ActiveViewState();
}

class _ActiveViewState extends State<ActiveView> with WidgetsBindingObserver {
  final SecurityManager _securityManager = SecurityManager();
  final GpsService _gpsService = GpsService();
  final NavigatorAlertRepository _alertRepo = NavigatorAlertRepository();
  final NavigationTrackRepository _trackRepo = NavigationTrackRepository();
  final CheckpointPunchRepository _punchRepo = CheckpointPunchRepository();
  final CheckpointRepository _checkpointRepo = CheckpointRepository();
  final BoundaryRepository _boundaryRepo = BoundaryRepository();

  NavigatorPersonalStatus _personalStatus = NavigatorPersonalStatus.waiting;
  NavigationTrack? _track;
  bool _isLoading = true;

  int _punchCount = 0;
  bool _securityActive = false;
  bool _isDisqualified = false;
  DateTime? _securityStartTime; // grace period — התעלמות מ-Lock Task exit מיד אחרי הפעלה
  List<domain_cp.Checkpoint> _routeCheckpoints = [];

  // דריסות מפה פר-מנווט (מהמפקד)
  bool _overrideAllowOpenMap = false;
  bool _overrideShowSelfLocation = false;
  bool _overrideShowRouteOnMap = false;

  // דקירת מיקום ידני
  bool _allowManualPosition = false;
  bool _manualPositionUsed = false;
  bool _manualPinPending = false;

  // GPS tracking
  final GPSTrackingService _gpsTracker = GPSTrackingService();
  Timer? _trackSaveTimer;
  bool _isSavingTrack = false;
  int _trackPointCount = 0;

  // GPS source tracking
  PositionSource _gpsSource = PositionSource.none;
  Timer? _gpsCheckTimer;
  LatLng? _boundaryCenter;
  bool _gpsBlocked = false;

  // דיווח סטטוס ל-system_status (כדי שהמפקד יראה בבדיקת מערכות)
  Timer? _statusReportTimer;
  final Battery _battery = Battery();
  int _batteryLevel = -1; // -1 = לא זמין

  // Health check
  HealthCheckService? _healthCheckService;

  // Alert monitoring
  AlertMonitoringService? _alertMonitoringService;

  // באנר התראה למנווט
  NavigatorAlert? _currentAlertBanner;
  Timer? _alertBannerTimer;

  // Firestore real-time listener — זיהוי מיידי של עצירה/איפוס מרחוק
  StreamSubscription<DocumentSnapshot>? _trackDocListener;

  // טיימר זמן שחלף
  Timer? _elapsedTimer;
  Duration _elapsed = Duration.zero;
  DateTime? _startTime;

  // נתוני סיכום סיום
  double _actualDistanceKm = 0;
  List<NavigatorAlert> _navigatorAlerts = [];

  domain.Navigation get _nav => widget.navigation;
  domain.AssignedRoute? get _route => _nav.routes[widget.currentUser.uid];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadTrackState();
  }

  @override
  void didUpdateWidget(covariant ActiveView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // עדכון הגדרות מהמפקד בזמן אמת (ללא הריסת state וניתוק נעילה)
    if (oldWidget.navigation.allowOpenMap != widget.navigation.allowOpenMap ||
        oldWidget.navigation.showSelfLocation != widget.navigation.showSelfLocation ||
        oldWidget.navigation.showRouteOnMap != widget.navigation.showRouteOnMap) {
      widget.onMapPermissionsChanged?.call(
        widget.navigation.allowOpenMap || _overrideAllowOpenMap,
        widget.navigation.showSelfLocation || _overrideShowSelfLocation,
        widget.navigation.showRouteOnMap || _overrideShowRouteOnMap,
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopSecurity();
    _stopTrackDocListener();
    _gpsCheckTimer?.cancel();
    _elapsedTimer?.cancel();
    _trackSaveTimer?.cancel();
    _statusReportTimer?.cancel();
    _healthCheckService?.dispose();
    _alertMonitoringService?.dispose();
    _alertBannerTimer?.cancel();
    _gpsTracker.stopTracking();
    _gpsService.dispose();
    super.dispose();
  }

  // ===========================================================================
  // State loading
  // ===========================================================================

  Future<void> _loadTrackState() async {
    await _computeBoundaryCenter();
    await _loadRouteCheckpoints();
    try {
      final track = await _trackRepo.getByNavigatorAndNavigation(
        widget.currentUser.uid,
        _nav.id,
      );

      final punches = await _punchRepo.getByNavigator(widget.currentUser.uid);
      final navPunches = punches.where((p) => p.navigationId == _nav.id).toList();

      NavigatorPersonalStatus status;
      NavigationTrack? effectiveTrack = track;
      if (track == null) {
        status = NavigatorPersonalStatus.waiting;
      } else {
        status = NavigatorPersonalStatus.deriveFromTrack(
          hasTrack: true,
          isActive: track.isActive,
          endedAt: track.endedAt,
        );
      }

      // Safety net: זיהוי track ישן מהפעלה קודמת ומחיקתו.
      // מקרה 1: track מראה "סיים" אבל הניווט פעיל/ממתין.
      // מקרה 2: track מראה "פעיל" אבל activeStartTime של הניווט חדש יותר — הניווט הופעל מחדש.
      // מקרה 3: track שנפסל — אם המפקד מחק אותו מ-Firestore (איפוס), לנקות מקומית.
      final navStatus = _nav.status;
      final bool trackDisqualified = effectiveTrack?.isDisqualified ?? false;
      bool isStaleTrack = false;

      // track שנפסל — בדיקת Firestore: אם המפקד איפס (מחק את ה-track), לנקות מקומית
      if (trackDisqualified && effectiveTrack != null) {
        try {
          final firestoreDoc = await FirebaseFirestore.instance
              .collection(AppConstants.navigationTracksCollection)
              .doc(effectiveTrack.id)
              .get();
          if (!firestoreDoc.exists) {
            // המפקד מחק — איפוס מקומי
            isStaleTrack = true;
          }
        } catch (_) {
          // אין רשת — נשאיר את המצב הנוכחי
        }
      }

      if (!trackDisqualified) {
        if (status == NavigatorPersonalStatus.finished &&
            (navStatus == 'active' || navStatus == 'waiting')) {
          isStaleTrack = true;
        }
        if (effectiveTrack != null &&
            _nav.activeStartTime != null &&
            effectiveTrack.startedAt.isBefore(_nav.activeStartTime!)) {
          isStaleTrack = true;
        }
      }
      if (isStaleTrack) {
        if (effectiveTrack != null) {
          await _trackRepo.deleteByNavigation(_nav.id);
          await _punchRepo.deleteByNavigation(_nav.id);
          effectiveTrack = null;
        }
        status = NavigatorPersonalStatus.waiting;
      }

      if (mounted) {
        setState(() {
          _track = effectiveTrack;
          _personalStatus = status;
          _punchCount = navPunches.length;
          _isDisqualified = effectiveTrack?.isDisqualified ?? false;
          _isLoading = false;
        });

        // אם המנווט כבר פעיל (חזר למסך) — להמשיך טיימר + שירותים
        if (status == NavigatorPersonalStatus.active && track != null) {
          _startTime = track.startedAt;
          _elapsed = DateTime.now().difference(track.startedAt);
          _startElapsedTimer();
          _startSecurity();
          _startGpsTracking();
          _startGpsSourceCheck();
          _startStatusReporting();
          _startHealthCheck();
          _startAlertMonitoring();
          _startTrackDocListener();
        }

        // אם סיים — לחשב זמן כולל + listener לביטול פסילה
        if (status == NavigatorPersonalStatus.finished && track != null) {
          _startTime = track.startedAt;
          _elapsed = (track.endedAt ?? DateTime.now()).difference(track.startedAt);
          // listener ל-track — כדי לזהות ביטול פסילה או איפוס ע"י מפקד
          _startTrackDocListener();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _computeBoundaryCenter() async {
    try {
      final boundaryLayerId = _nav.boundaryLayerId;
      if (boundaryLayerId == null || boundaryLayerId.isEmpty) return;

      final boundary = await _boundaryRepo.getById(boundaryLayerId);
      if (boundary == null || boundary.coordinates.isEmpty) return;

      // Compute centroid of boundary polygon
      double latSum = 0;
      double lngSum = 0;
      for (final coord in boundary.coordinates) {
        latSum += coord.lat;
        lngSum += coord.lng;
      }
      _boundaryCenter = LatLng(
        latSum / boundary.coordinates.length,
        lngSum / boundary.coordinates.length,
      );
      print('DEBUG ActiveView: boundary center = ${_boundaryCenter!.latitude}, ${_boundaryCenter!.longitude}');
    } catch (e) {
      print('DEBUG ActiveView: failed to compute boundary center: $e');
    }
  }

  Future<void> _loadRouteCheckpoints() async {
    try {
      final route = _route;
      if (route == null) return;

      final allCheckpoints = await _checkpointRepo.getByArea(_nav.areaId);
      final routeCpIds = route.checkpointIds.toSet();
      _routeCheckpoints = allCheckpoints
          .where((cp) => routeCpIds.contains(cp.id) && !cp.isPolygon && cp.coordinates != null)
          .toList();
      print('DEBUG ActiveView: loaded ${_routeCheckpoints.length} route checkpoints');
    } catch (e) {
      print('DEBUG ActiveView: failed to load checkpoints: $e');
    }
  }

  // ===========================================================================
  // Timer
  // ===========================================================================

  void _startElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_startTime != null && mounted) {
        setState(() {
          _elapsed = DateTime.now().difference(_startTime!);
        });
      }
    });
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  // ===========================================================================
  // Security
  // ===========================================================================

  Future<void> _startSecurity() async {
    if (_securityActive) return;

    // רישום callback לפסילה על חריגה קריטית (iOS Guided Access exit וכו')
    _securityManager.onCriticalViolation = (type) async {
      if (type == ViolationType.exitLockTask) {
        // בדיקה אם Lock Task באמת כבוי — אירועים ישנים/מיותרים נפוצים
        final stillLocked = await DeviceSecurityService().isInLockTaskMode();
        if (stillLocked) {
          print('DEBUG ActiveView: Ignoring onLockTaskExit — Lock Task still active');
          return;
        }
        // grace period קצר (6 שניות) — מונע false positive מיד אחרי startLockTask()
        if (_securityStartTime != null &&
            DateTime.now().difference(_securityStartTime!).inSeconds < 6) {
          print('DEBUG ActiveView: onLockTaskExit in grace period — re-enabling silently');
          await DeviceSecurityService().enableLockTask();
          return;
        }
        // מחוץ ל-grace period — הפעלה מחדש + פסילה
        print('🚨 ActiveView: Lock Task exit detected — re-enabling + disqualifying');
        await DeviceSecurityService().enableLockTask();
      }
      _handleDisqualification(type);
    };

    final success = await _securityManager.startNavigationSecurity(
      navigationId: _nav.id,
      navigatorId: widget.currentUser.uid,
      settings: _nav.securitySettings,
      navigatorName: widget.currentUser.fullName,
    );

    if (mounted) {
      setState(() => _securityActive = success);
      if (success) _securityStartTime = DateTime.now();
    }

    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('לא ניתן להפעיל נעילת אבטחה'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _stopSecurity() async {
    if (!_securityActive) return;
    await _securityManager.stopNavigationSecurity(normalEnd: true);
    _securityActive = false;
  }

  /// פסילת מנווט — סימון ב-track + שליחת התראה למפקד
  Future<void> _handleDisqualification(ViolationType type) async {
    if (_isDisqualified || _track == null) return;

    // סימון מיידי — מונע race condition עם _saveTrackPoints שרץ במקביל
    // (ללא setState כדי שה-safety net ב-_saveTrackPoints יראה את הערך הנכון מיד)
    _isDisqualified = true;

    try {
      // סימון isDisqualified=true ב-track (Drift + Firestore)
      await _trackRepo.disqualifyNavigator(_track!.id);

      // שליחת התראה למפקד
      await _securityManager.sendDisqualificationAlert(
        navigationId: _nav.id,
        navigatorId: widget.currentUser.uid,
        navigatorName: widget.currentUser.fullName,
      );
    } catch (e) {
      print('DEBUG ActiveView: disqualification error: $e');
    }

    if (mounted) {
      setState(() {}); // רענון UI — _isDisqualified כבר true
      HapticFeedback.heavyImpact();
    }
  }

  /// הצגת דיאלוג ביטול נעילה
  Future<void> _showUnlockDialog() async {
    final securityLevel = await _securityManager.getSecurityLevel();
    if (!mounted) return;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => UnlockDialog(
        correctCode: _nav.securitySettings.unlockCode ?? '',
        securityLevel: securityLevel,
        onDisqualificationConfirmed: () =>
            _handleDisqualification(ViolationType.exitLockTask),
      ),
    );

    if (result == true) {
      await _stopSecurity();
    }
  }

  // ===========================================================================
  // Lifecycle — זיהוי יציאה מ-Lock Task
  // ===========================================================================

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _securityActive &&
        !_isDisqualified) {
      _checkLockTaskIntegrity();
    }
  }

  /// בדיקת שלמות Lock Task — אם היינו במצב נעילה ויצאנו ממנו, פסילה
  Future<void> _checkLockTaskIntegrity() async {
    try {
      // בדיקה רלוונטית רק כש-Lock Task/Kiosk פעיל (Android בלבד)
      final securityLevel = await _securityManager.getSecurityLevel();
      if (securityLevel != SecurityLevel.lockTask &&
          securityLevel != SecurityLevel.kioskMode) {
        return;
      }

      // grace period קצר (6 שניות) — מונע false positive מיד אחרי startLockTask()
      if (_securityStartTime != null &&
          DateTime.now().difference(_securityStartTime!).inSeconds < 6) {
        print('DEBUG ActiveView: Lock Task check skipped — grace period (${DateTime.now().difference(_securityStartTime!).inSeconds}s)');
        return;
      }

      final deviceSecurity = DeviceSecurityService();
      final inLockTask = await deviceSecurity.isInLockTaskMode();

      // אם אבטחה פעילה אבל Lock Task כבוי — הפעלה מחדש + פסילה
      if (!inLockTask && _securityActive && !_isDisqualified) {
        print('🚨 ActiveView: Lock Task exit detected on resume — re-enabling + disqualifying');
        await deviceSecurity.enableLockTask();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('זוהתה יציאה מנעילת אבטחה — הניווט נפסל'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 5),
            ),
          );
        }

        await _handleDisqualification(ViolationType.exitLockTask);
      }
    } catch (e) {
      print('DEBUG ActiveView: lock task integrity check error: $e');
    }
  }

  // ===========================================================================
  // GPS Source Check
  // ===========================================================================

  void _startGpsSourceCheck() {
    _checkGpsSource();
    _gpsCheckTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _checkGpsSource();
    });
  }

  void _checkGpsSource() {
    if (!mounted) return;

    // קריאת מקור GPS מנקודת המעקב האחרונה — ללא קריאת GPS נפרדת שמתחרה עם ה-Tracker
    final points = _gpsTracker.trackPoints;
    if (points.isEmpty) {
      setState(() {
        _gpsSource = PositionSource.none;
        _gpsBlocked = false;
      });
      return;
    }

    final lastPoint = points.last;
    final source = PositionSource.values.firstWhere(
      (s) => s.name == lastPoint.positionSource,
      orElse: () => PositionSource.none,
    );

    setState(() {
      _gpsSource = source;
      // If we have a boundary and GPS source is not GPS, it might be blocked
      _gpsBlocked = _boundaryCenter != null &&
          source != PositionSource.gps &&
          source != PositionSource.none;
    });
  }

  // ===========================================================================
  // System Status Reporting — דיווח ל-Firestore כדי שמפקד יראה בבדיקת מערכות
  // ===========================================================================

  void _startStatusReporting() {
    _reportStatusToFirestore();
    _statusReportTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _reportStatusToFirestore(),
    );
  }

  Future<void> _reportStatusToFirestore() async {
    final uid = widget.currentUser.uid;
    try {
      // עדכון סוללה
      try {
        _batteryLevel = await _battery.batteryLevel;
        // עדכון AlertMonitoringService לבדיקת סף סוללה
        if (_batteryLevel > 0) {
          _alertMonitoringService?.updateBatteryLevel(_batteryLevel);
        }
      } catch (_) {
        _batteryLevel = -1;
      }

      final docRef = FirebaseFirestore.instance
          .collection(AppConstants.navigationsCollection)
          .doc(_nav.id)
          .collection('system_status')
          .doc(uid);

      // מיקום אחרון מה-tracker
      final points = _gpsTracker.trackPoints;
      final lastPoint = points.isNotEmpty ? points.last : null;

      final data = <String, dynamic>{
        'navigatorId': uid,
        'isConnected': lastPoint != null || _gpsSource != PositionSource.none,
        'batteryLevel': _batteryLevel >= 0 ? _batteryLevel : null,
        'hasGPS': _gpsSource == PositionSource.gps,
        'gpsAccuracy': lastPoint?.accuracy ?? -1,
        'receptionLevel': _estimateReceptionLevel(),
        'positionSource': _gpsSource.name,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (lastPoint != null) {
        data['latitude'] = lastPoint.coordinate.lat;
        data['longitude'] = lastPoint.coordinate.lng;
        data['positionUpdatedAt'] = FieldValue.serverTimestamp();
      }

      await docRef.set(data, SetOptions(merge: true));
    } catch (e) {
      print('DEBUG ActiveView: system_status report failed: $e');
    }
  }

  int _estimateReceptionLevel() {
    final points = _gpsTracker.trackPoints;
    if (points.isEmpty) return 0;
    final accuracy = points.last.accuracy;
    if (accuracy < 0) return 0;
    if (accuracy <= 10) return 4;
    if (accuracy <= 30) return 3;
    if (accuracy <= 50) return 2;
    if (accuracy <= 100) return 1;
    return 0;
  }

  // ===========================================================================
  // GPS Tracking — שמירה תקופתית ל-DB + סנכרון
  // ===========================================================================

  /// בדיקה והפעלת דקירת מיקום ידני
  Future<void> _checkAndTriggerManualPin() async {
    if (_manualPositionUsed || !_allowManualPosition || _manualPinPending) return;
    if (_personalStatus != NavigatorPersonalStatus.active) return;

    // שלב א — בדיקה אם יש מיקום אחרון טוב
    final points = _gpsTracker.trackPoints;
    if (points.isNotEmpty) {
      final lastPoint = points.last;
      final age = DateTime.now().difference(lastPoint.timestamp);
      if (age.inMinutes < 5 && lastPoint.accuracy >= 0 && lastPoint.accuracy < 100) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ממשיך מהמקום האחרון'), backgroundColor: Colors.green),
          );
        }
        return;
      }
    }

    // שלב ב — פתיחת מפת דקירה
    _manualPinPending = true;
    if (mounted) setState(() {});

    final LatLng? pinnedLocation = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(builder: (_) => const ManualPositionPinScreen()),
    );

    _manualPinPending = false;

    if (pinnedLocation != null && mounted) {
      _gpsTracker.recordManualPosition(pinnedLocation.latitude, pinnedLocation.longitude);
      _manualPositionUsed = true;
      if (_track != null) {
        await _trackRepo.markManualPositionUsed(_track!.id);
      }
      await _saveTrackPoints();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('מיקום ידני נרשם בהצלחה'), backgroundColor: Colors.deepPurple),
      );
    }
    if (mounted) setState(() {});
  }

  Future<void> _startGpsTracking() async {
    final interval = _nav.gpsUpdateIntervalSeconds;
    final started = await _gpsTracker.startTracking(
      intervalSeconds: interval,
      boundaryCenter: _boundaryCenter,
      enabledPositionSources: _nav.enabledPositionSources,
    );
    if (!started) {
      print('DEBUG ActiveView: GPS tracking failed to start');
      return;
    }

    // שמירה תקופתית ל-Drift — מינימום 10 שניות גם אם interval קצר יותר
    final saveInterval = interval < 10 ? 10 : (interval < 30 ? interval : 30);
    _trackSaveTimer = Timer.periodic(
      Duration(seconds: saveInterval),
      (_) => _saveTrackPoints(),
    );
  }

  Future<void> _saveTrackPoints() async {
    if (_track == null) return;
    // מניעת שמירות מקבילות
    if (_isSavingTrack) return;
    _isSavingTrack = true;

    final points = _gpsTracker.trackPoints;

    try {
      // בדיקת עצירה מרחוק BEFORE sync — כדי שלא לדרוס isActive=false של המפקד
      final stopped = await _checkRemoteStop();
      if (stopped) return; // הניווט נעצר — לא לסנכרן חזרה

      // עדכון נקודות ב-Drift (רק אם יש)
      if (points.isNotEmpty) {
        await _trackRepo.updateTrackPoints(_track!.id, points);
      }

      // סנכרון ל-Firestore — גם ללא נקודות, כדי שהמפקד יראה סטטוס פעיל
      var updatedTrack = await _trackRepo.getById(_track!.id);
      // safety net: UI state הוא ה-source of truth לפסילה — מונע דריסת ביטול פסילה
      if (updatedTrack.isDisqualified != _isDisqualified) {
        updatedTrack = updatedTrack.copyWith(isDisqualified: _isDisqualified);
      }
      await _trackRepo.syncTrackToFirestore(updatedTrack);

      if (mounted && points.isNotEmpty) {
        setState(() => _trackPointCount = points.length);
      }

      // בדיקת דקירת מיקום ידני תקופתית
      if (_allowManualPosition && !_manualPositionUsed && !_manualPinPending) {
        final pts = _gpsTracker.trackPoints;
        if (pts.isEmpty || DateTime.now().difference(pts.last.timestamp).inMinutes > 5) {
          _checkAndTriggerManualPin();
        }
      }
    } catch (e) {
      print('DEBUG ActiveView: track save error: $e');
    } finally {
      _isSavingTrack = false;
    }
  }

  Future<void> _stopGpsTracking() async {
    _trackSaveTimer?.cancel();
    _trackSaveTimer = null;

    // שמירה סופית לפני עצירה
    await _saveTrackPoints();

    await _gpsTracker.stopTracking();
  }

  // ===========================================================================
  // Remote Stop — זיהוי מיידי של עצירה/איפוס מרחוק ע"י מפקד
  // ===========================================================================

  /// התחלת האזנה בזמן אמת למסמך ה-track ב-Firestore
  void _startTrackDocListener() {
    if (_track == null) return;
    _trackDocListener?.cancel();

    _trackDocListener = FirebaseFirestore.instance
        .collection(AppConstants.navigationTracksCollection)
        .doc(_track!.id)
        .snapshots()
        .listen((snapshot) async {
      if (!mounted) return;

      if (!snapshot.exists) {
        // המפקד מחק את ה-track — איפוס (תמיד, גם אחרי סיום)
        _performRemoteReset();
        return;
      }

      final data = snapshot.data();
      if (data == null) return;

      // בדיקת ביטול פסילה — רלוונטי בכל מצב (פעיל או סיים)
      final remoteDisqualified = data['isDisqualified'] as bool? ?? false;
      if (_isDisqualified && !remoteDisqualified) {
        // המפקד ביטל את הפסילה — עדכון Drift מקומי כדי שסנכרון הבא לא ידרוס
        if (_track != null) {
          try {
            await _trackRepo.undoDisqualification(_track!.id);
          } catch (_) {}
        }
        // הפעלה מחדש של Lock Task אם אבטחה פעילה (הנעילה כבר נפלה כשנפסל)
        if (_securityActive) {
          try {
            final reEnabled = await DeviceSecurityService().enableLockTask();
            if (reEnabled) {
              _securityStartTime = DateTime.now(); // grace period חדש
              print('✓ ActiveView: Lock Task re-enabled after undo disqualification');
            }
          } catch (_) {}
        }
        setState(() => _isDisqualified = false);
        HapticFeedback.mediumImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('הפסילה בוטלה על ידי המפקד'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 5),
          ),
        );
      }

      // שאר הלוגיקה רלוונטית רק במצב פעיל
      if (_personalStatus != NavigatorPersonalStatus.active) return;

      final isActive = data['isActive'] as bool? ?? true;
      if (!isActive) {
        // המפקד עצר את הניווט
        _performRemoteStop();
        return;
      }

      // קריאת forcePositionSource מהמסמך
      final trackSource = data['forcePositionSource'] as String?;
      if (trackSource != null && trackSource != 'auto' &&
          _gpsTracker.forcePositionSource != trackSource) {
        _gpsTracker.forcePositionSource = trackSource;
        print('DEBUG ActiveView: forcePositionSource changed to: $trackSource (realtime)');
      }

      // קריאת דריסות מפה פר-מנווט
      final newAllowOpenMap = data['overrideAllowOpenMap'] as bool? ?? false;
      final newShowSelfLocation = data['overrideShowSelfLocation'] as bool? ?? false;
      final newShowRouteOnMap = data['overrideShowRouteOnMap'] as bool? ?? false;
      if (newAllowOpenMap != _overrideAllowOpenMap ||
          newShowSelfLocation != _overrideShowSelfLocation ||
          newShowRouteOnMap != _overrideShowRouteOnMap) {
        _overrideAllowOpenMap = newAllowOpenMap;
        _overrideShowSelfLocation = newShowSelfLocation;
        _overrideShowRouteOnMap = newShowRouteOnMap;
        widget.onMapPermissionsChanged?.call(
          newAllowOpenMap, newShowSelfLocation, newShowRouteOnMap,
        );
      }

      // קריאת דריסת דקירת מיקום ידני
      final newAllowManual = data['overrideAllowManualPosition'] as bool? ?? false;
      final globalAllow = widget.navigation.allowManualPosition;
      final effectiveAllow = globalAllow || newAllowManual;
      if (effectiveAllow && !_allowManualPosition) {
        _manualPositionUsed = false;
      }
      _allowManualPosition = effectiveAllow;
      if (_allowManualPosition && !_manualPositionUsed && !_manualPinPending) {
        _checkAndTriggerManualPin();
      }
    }, onError: (e) {
      print('DEBUG ActiveView: track doc listener error: $e');
    });
  }

  void _stopTrackDocListener() {
    _trackDocListener?.cancel();
    _trackDocListener = null;
  }

  /// בדיקת עצירה מרחוק + קריאת forcePositionSource. מחזיר true אם הניווט נעצר.
  Future<bool> _checkRemoteStop() async {
    if (_track == null || _personalStatus != NavigatorPersonalStatus.active) return false;

    try {
      final doc = await FirebaseFirestore.instance
          .collection(AppConstants.navigationTracksCollection)
          .doc(_track!.id)
          .get();

      if (!doc.exists) {
        // המפקד מחק את ה-track (איפוס — חזרה למצב ממתין)
        await _performRemoteReset();
        return true;
      }

      final data = doc.data();
      if (data == null) return false;

      final isActive = data['isActive'] as bool? ?? true;
      if (!isActive) {
        // המפקד עצר את הניווט מרחוק
        await _performRemoteStop();
        return true;
      }

      // קריאת forcePositionSource — individual (track) > global (navigation)
      String effectiveSource = 'auto';
      final trackSource = data['forcePositionSource'] as String?;
      if (trackSource != null && trackSource != 'auto') {
        effectiveSource = trackSource;
      } else {
        // נסה לקרוא מהניווט (global)
        try {
          final navDoc = await FirebaseFirestore.instance
              .collection(AppConstants.navigationsCollection)
              .doc(_nav.id)
              .get();
          final navData = navDoc.data();
          if (navData != null) {
            final globalSource = navData['forcePositionSource'] as String?;
            if (globalSource != null && globalSource != 'auto') {
              effectiveSource = globalSource;
            }
          }
        } catch (_) {}
      }

      // החלת מקור מיקום כפוי על ה-tracker
      if (_gpsTracker.forcePositionSource != effectiveSource) {
        _gpsTracker.forcePositionSource = effectiveSource;
        print('DEBUG ActiveView: forcePositionSource changed to: $effectiveSource');
      }
    } catch (e) {
      print('DEBUG ActiveView: remote stop check error: $e');
    }
    return false;
  }

  Future<void> _performRemoteStop() async {
    // עצירת GPS tracking
    _trackSaveTimer?.cancel();
    _trackSaveTimer = null;
    await _gpsTracker.stopTracking();

    // עצירת שירותים
    _alertMonitoringService?.stop();
    _healthCheckService?.dispose();
    _gpsCheckTimer?.cancel();
    _statusReportTimer?.cancel();
    _elapsedTimer?.cancel();
    await _stopSecurity();

    // עדכון DB מקומי
    if (_track != null) {
      try {
        await _trackRepo.endNavigation(_track!.id);
      } catch (_) {}
    }

    final endTime = DateTime.now();
    _elapsed = endTime.difference(_startTime ?? endTime);

    if (mounted) {
      setState(() {
        _personalStatus = NavigatorPersonalStatus.finished;
        _isLoading = false;
      });

      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('הניווט הופסק על ידי המפקד'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 5),
        ),
      );
    }
  }

  /// איפוס ניווט מרחוק — המפקד מחק את ה-track, המנווט חוזר למצב ממתין נקי
  Future<void> _performRemoteReset() async {
    // עצירת listener מיידית — למנוע קריאות כפולות
    _stopTrackDocListener();

    // עצירת GPS tracking
    _trackSaveTimer?.cancel();
    _trackSaveTimer = null;
    await _gpsTracker.stopTracking();

    // עצירת שירותים
    _alertMonitoringService?.stop();
    _alertMonitoringService = null;
    _healthCheckService?.dispose();
    _healthCheckService = null;
    _gpsCheckTimer?.cancel();
    _statusReportTimer?.cancel();
    _elapsedTimer?.cancel();
    _alertBannerTimer?.cancel();
    await _stopSecurity();

    // מחיקת נתונים מקומיים — track + דקירות
    try {
      await _trackRepo.deleteByNavigation(_nav.id);
    } catch (_) {}
    try {
      await _punchRepo.deleteByNavigation(_nav.id);
    } catch (_) {}

    if (mounted) {
      setState(() {
        _personalStatus = NavigatorPersonalStatus.waiting;
        _track = null;
        _isDisqualified = false;
        _punchCount = 0;
        _trackPointCount = 0;
        _elapsed = Duration.zero;
        _startTime = null;
        _gpsSource = PositionSource.none;
        _gpsBlocked = false;
        _currentAlertBanner = null;
        _navigatorAlerts = [];
        _actualDistanceKm = 0;
        _isLoading = false;
      });

      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('הניווט אופס על ידי המפקד — ניתן להתחיל מחדש'),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 5),
        ),
      );
    }
  }

  // ===========================================================================
  // Health Check
  // ===========================================================================

  void _startHealthCheck() {
    final alerts = _nav.alerts;
    if (alerts.healthCheckEnabled) {
      _healthCheckService = HealthCheckService(
        intervalMinutes: alerts.healthCheckIntervalMinutes,
        navigatorId: widget.currentUser.uid,
        navigationId: _nav.id,
        navigatorName: widget.currentUser.fullName,
        alertRepository: _alertRepo,
        onAlarmStateChanged: (isAlarming, message) {
          if (mounted) setState(() {});
        },
      );
      _healthCheckService!.start();
    }
  }

  // ===========================================================================
  // Alert Monitoring
  // ===========================================================================

  void _startAlertMonitoring() {
    final route = _route;
    _alertMonitoringService = AlertMonitoringService(
      navigationId: _nav.id,
      navigatorId: widget.currentUser.uid,
      navigatorName: widget.currentUser.fullName,
      alertsConfig: _nav.alerts,
      gpsTracker: _gpsTracker,
      alertRepository: _alertRepo,
      areaId: _nav.areaId,
      boundaryLayerId: _nav.boundaryLayerId,
      plannedPath: route?.plannedPath ?? const [],
      onAlert: _onNavigatorAlert,
    );
    _alertMonitoringService!.start();
  }

  /// callback מ-AlertMonitoringService — מציג באנר התראה למנווט
  void _onNavigatorAlert(NavigatorAlert alert) {
    // סינון — רק התראות רלוונטיות למנווט
    const relevantTypes = {AlertType.safetyPoint, AlertType.boundary, AlertType.battery};
    if (!relevantTypes.contains(alert.type)) return;

    _alertBannerTimer?.cancel();
    if (mounted) {
      setState(() => _currentAlertBanner = alert);
      HapticFeedback.heavyImpact();
    }

    // באנר נעלם אחרי 8 שניות
    _alertBannerTimer = Timer(const Duration(seconds: 8), () {
      if (mounted) {
        setState(() => _currentAlertBanner = null);
      }
    });
  }

  // ===========================================================================
  // Actions — start / end navigation
  // ===========================================================================

  Future<void> _startNavigation() async {
    setState(() => _isLoading = true);
    try {
      final track = await _trackRepo.startNavigation(
        navigatorUserId: widget.currentUser.uid,
        navigationId: _nav.id,
      );

      _startTime = track.startedAt;

      // הפעלת שירותים
      await _startSecurity();

      // שמירת ה-track ב-state לפני GPS כדי ש-_saveTrackPoints יוכל לגשת אליו
      _track = track;

      // סנכרון מיידי ל-Firestore — כדי שהמפקד יראה את המנווט כ"פעיל" גם ללא GPS
      await _trackRepo.syncTrackToFirestore(track);

      await _startGpsTracking();

      // שמירה מיידית של הנקודה הראשונה (אם יש) ל-Drift + סנכרון ל-Firestore
      await _saveTrackPoints();

      _startGpsSourceCheck();
      _startStatusReporting();
      _startHealthCheck();
      _startAlertMonitoring();
      _startTrackDocListener();

      // דקירת מיקום ידני — בדיקה אחרי 3 שניות
      if (widget.navigation.allowManualPosition || _allowManualPosition) {
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted && _gpsTracker.trackPoints.isEmpty) {
            _checkAndTriggerManualPin();
          }
        });
      }

      setState(() {
        _track = track;
        _personalStatus = NavigatorPersonalStatus.active;
        _elapsed = Duration.zero;
        _isLoading = false;
      });

      _startElapsedTimer();
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בהתחלת ניווט: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _endNavigation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('סיום ניווט'),
        content: const Text('האם לסיים את הניווט? לא ניתן לחזור אחורה.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ביטול'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('סיום ניווט', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true || _track == null) return;

    setState(() => _isLoading = true);
    try {
      // עצירת GPS tracking + שמירה סופית
      await _stopGpsTracking();

      await _trackRepo.endNavigation(_track!.id);

      // סנכרון סופי אחרי סיום (לא חוסם שחרור נעילה)
      try {
        final finalTrack = await _trackRepo.getById(_track!.id);

        // חישוב מרחק בפועל מנקודות שנשמרו ב-DB (אמין יותר מהזיכרון)
        try {
          if (finalTrack.trackPointsJson.isNotEmpty) {
            final points = (jsonDecode(finalTrack.trackPointsJson) as List)
                .map((m) => TrackPoint.fromMap(m as Map<String, dynamic>))
                .toList();
            final coords = points
                .map((tp) => Coordinate(lat: tp.coordinate.lat, lng: tp.coordinate.lng, utm: ''))
                .toList();
            _actualDistanceKm = GeometryUtils.calculatePathLengthKm(coords);
          }
        } catch (_) {
          _actualDistanceKm = _gpsTracker.getTotalDistance(); // fallback
        }
        await _trackRepo.syncTrackToFirestore(finalTrack);
      } catch (e) {
        print('DEBUG ActiveView: sync on end failed (non-critical): $e');
      }

      final endTime = DateTime.now();
      _elapsed = endTime.difference(_startTime ?? endTime);

      // טעינת התראות שהיו למנווט
      try {
        _navigatorAlerts = await _alertRepo.getByNavigator(_nav.id, widget.currentUser.uid);
      } catch (_) {}

      setState(() {
        _personalStatus = NavigatorPersonalStatus.finished;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בסיום ניווט: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      // שחרור נעילה + עצירת שירותים — תמיד, גם אם הסנכרון נכשל
      _alertMonitoringService?.stop();
      _gpsCheckTimer?.cancel();
      _statusReportTimer?.cancel();
      _elapsedTimer?.cancel();
      _healthCheckService?.dispose();
      await _stopSecurity();
    }
  }

  // ===========================================================================
  // Actions — punch, report, emergency, barbur
  // ===========================================================================

  Future<void> _punchCheckpoint() async {
    if (_routeCheckpoints.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('אין נקודות ציון בציר'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // קבלת מיקום GPS נוכחי
    final posResult = await _gpsService.getCurrentPositionWithAccuracy(
      boundaryCenter: _boundaryCenter,
    );
    if (posResult == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('לא ניתן לקבל מיקום GPS'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final currentCoord = Coordinate(
      lat: posResult.position.latitude,
      lng: posResult.position.longitude,
      utm: '',
    );

    // מציאת הנקודה הקרובה ביותר מציר המנווט
    domain_cp.Checkpoint? nearestCp;
    double nearestDistance = double.infinity;

    for (final cp in _routeCheckpoints) {
      final dist = GeometryUtils.distanceBetweenMeters(
        currentCoord,
        cp.coordinates!,
      );
      if (dist < nearestDistance) {
        nearestDistance = dist;
        nearestCp = cp;
      }
    }

    if (nearestCp == null) return;

    // יצירת דקירה
    final now = DateTime.now();
    final punch = CheckpointPunch(
      id: '${widget.currentUser.uid}-${_punchCount + 1}',
      navigationId: _nav.id,
      navigatorId: widget.currentUser.uid,
      checkpointId: nearestCp.id,
      punchLocation: currentCoord,
      punchTime: now,
      distanceFromCheckpoint: nearestDistance,
    );

    try {
      await _punchRepo.create(punch);
      print('DEBUG ActiveView: punch created for checkpoint ${nearestCp.name}, distance=${nearestDistance.toStringAsFixed(0)}m');

      if (mounted) {
        setState(() => _punchCount++);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'דקירה ${widget.currentUser.uid}-${_punchCount}: ${nearestCp.name} (${nearestDistance.toStringAsFixed(0)} מ\')',
            ),
            backgroundColor: Colors.blue,
          ),
        );
      }
    } catch (e) {
      print('DEBUG ActiveView: punch error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בדקירה: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _reportStatus() async {
    _healthCheckService?.reportHealthy();

    try {
      final position = await _gpsService.getCurrentPosition();
      final alert = NavigatorAlert(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        navigationId: _nav.id,
        navigatorId: widget.currentUser.uid,
        type: AlertType.healthReport,
        location: Coordinate(
          lat: position?.latitude ?? 0,
          lng: position?.longitude ?? 0,
          utm: '',
        ),
        timestamp: DateTime.now(),
      );
      await _alertRepo.create(alert);
    } catch (e) {
      print('DEBUG ActiveView: health report failed: $e');
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('דיווח תקינות נשלח'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _emergencyAlert() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('מצב חירום'),
        content: const Text('האם לשלוח התראת חירום למפקד?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ביטול'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _sendEmergencyAlert();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('שלח', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _sendEmergencyAlert() async {
    try {
      final position = await _gpsService.getCurrentPosition();
      final alert = NavigatorAlert(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        navigationId: _nav.id,
        navigatorId: widget.currentUser.uid,
        type: AlertType.emergency,
        location: Coordinate(
          lat: position?.latitude ?? 0,
          lng: position?.longitude ?? 0,
          utm: '',
        ),
        timestamp: DateTime.now(),
        navigatorName: widget.currentUser.fullName,
      );
      await _alertRepo.create(alert);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('התראת חירום נשלחה'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בשליחת התראה: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _barburReport() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('דיווח ברבור'),
        content: const Text('פיצ\'ר בפיתוח — דיווח ברבור'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('סגור'),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // Build
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    Widget content;
    switch (_personalStatus) {
      case NavigatorPersonalStatus.waiting:
        content = _buildWaitingView();
      case NavigatorPersonalStatus.active:
      case NavigatorPersonalStatus.noReception:
        content = _buildActiveView();
      case NavigatorPersonalStatus.finished:
        content = _buildFinishedView();
    }

    // PopScope — מניעת חזרה בזמן ניווט פעיל (שכבת הגנה נוספת)
    if (_personalStatus == NavigatorPersonalStatus.active && _securityActive) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _showUnlockDialog();
        },
        child: content,
      );
    }

    return content;
  }

  // ---------------------------------------------------------------------------
  // מצב "ממתין" — כפתור התחלת ניווט
  // ---------------------------------------------------------------------------

  Widget _buildWaitingView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.navigation,
              size: 80,
              color: Colors.green[300],
            ),
            const SizedBox(height: 24),
            Text(
              'ניווט ${_nav.name}',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'לחץ על הכפתור כדי להתחיל',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: 220,
              height: 60,
              child: ElevatedButton.icon(
                onPressed: _startNavigation,
                icon: const Icon(Icons.play_arrow, size: 32),
                label: const Text(
                  'התחלת ניווט',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // מצב "פעיל" — סטטוס + גריד + כפתור סיום
  // ---------------------------------------------------------------------------

  Widget _buildActiveView() {
    return Column(
      children: [
        // Health check alarm banner
        if (_healthCheckService != null && _healthCheckService!.isAlarming)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.red,
            child: Row(
              children: [
                const Icon(Icons.warning, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _healthCheckService!.alarmMessage,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        // Alert banner (נת"ב, ג"ג, סוללה)
        if (_currentAlertBanner != null)
          _buildAlertBanner(_currentAlertBanner!),
        // Status bar with elapsed timer
        _buildActiveStatusBar(),
        // GPS accuracy banner
        _buildGpsAccuracyBanner(),
        // Disqualification banner
        if (_isDisqualified)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Colors.red,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.block, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text(
                  'הניווט נפסל — ציון 0',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        // Security indicator
        if (_securityActive && !_isDisqualified)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: Colors.green.withOpacity(0.15),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock, size: 14, color: Colors.green[700]),
                const SizedBox(width: 6),
                Text(
                  'אבטחה פעילה',
                  style: TextStyle(fontSize: 12, color: Colors.green[700], fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: _showUnlockDialog,
                  child: Text(
                    'ביטול נעילה',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.red[700],
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
        // 2×2 grid
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: GridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              children: [
                _buildActionCard(
                  title: 'דקירת נ.צ',
                  icon: Icons.location_on,
                  color: Colors.blue,
                  onTap: _punchCheckpoint,
                ),
                _buildActionCard(
                  title: 'דיווח תקינות',
                  icon: Icons.check_circle_outline,
                  color: Colors.green,
                  onTap: _reportStatus,
                ),
                _buildActionCard(
                  title: 'מצב חירום',
                  icon: Icons.warning_amber,
                  color: Colors.red,
                  onTap: _emergencyAlert,
                ),
                _buildActionCard(
                  title: 'ברבור',
                  icon: Icons.report_problem,
                  color: Colors.orange,
                  onTap: _barburReport,
                ),
              ],
            ),
          ),
        ),
        // כפתור בקשת הארכה (בפיתוח)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: null,
              icon: const Icon(Icons.timer),
              label: const Text(
                'בקשת הארכה — בפיתוח',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.purple.withOpacity(0.5),
                disabledForegroundColor: Colors.white70,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ),
        // כפתור סיום ניווט — 1.5 ס"מ לפחות מעל קצה העמוד
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _endNavigation,
              icon: const Icon(Icons.stop),
              label: const Text(
                'סיום ניווט',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 95),
      ],
    );
  }

  Widget _buildGpsAccuracyBanner() {
    final points = _gpsTracker.trackPoints;
    if (points.isEmpty) return const SizedBox.shrink();
    final accuracy = points.last.accuracy;
    if (accuracy < 0) return const SizedBox.shrink();

    Color bannerColor;
    IconData bannerIcon;
    if (accuracy <= 10) {
      bannerColor = Colors.green;
      bannerIcon = Icons.gps_fixed;
    } else if (accuracy <= 50) {
      bannerColor = Colors.orange;
      bannerIcon = Icons.gps_not_fixed;
    } else {
      bannerColor = Colors.red;
      bannerIcon = Icons.gps_off;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: bannerColor.withOpacity(0.15),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(bannerIcon, size: 16, color: bannerColor),
          const SizedBox(width: 6),
          Text(
            'דיוק: ${accuracy.toStringAsFixed(0)} מטר',
            style: TextStyle(fontSize: 13, color: bannerColor, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveStatusBar() {
    final route = _route;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
      color: Theme.of(context).primaryColor.withOpacity(0.1),
      child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(
        children: [
          // שעון זמן שחלף
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.timer, size: 18, color: Colors.green[700]),
                const SizedBox(width: 4),
                Text(
                  _formatDuration(_elapsed),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.green[700],
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _statusChip(
            icon: Icons.route,
            label: route != null
                ? '${route.routeLengthKm.toStringAsFixed(1)} ק"מ'
                : '-',
          ),
          const SizedBox(width: 12),
          _statusChip(
            icon: Icons.location_on,
            label: '$_punchCount דקירות',
          ),
          if (_trackPointCount > 0) ...[
            const SizedBox(width: 12),
            _statusChip(
              icon: Icons.timeline,
              label: '$_trackPointCount נק׳',
            ),
          ],
          const SizedBox(width: 12),
          _buildGpsChip(),
        ],
      )),
    );
  }

  Widget _buildAlertBanner(NavigatorAlert alert) {
    Color bgColor;
    IconData icon;
    switch (alert.type) {
      case AlertType.safetyPoint:
        bgColor = Colors.orange;
        icon = Icons.warning_amber;
      case AlertType.boundary:
        bgColor = Colors.red;
        icon = Icons.dangerous;
      case AlertType.battery:
        bgColor = Colors.amber.shade700;
        icon = Icons.battery_alert;
      default:
        bgColor = Colors.orange;
        icon = Icons.notifications_active;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: bgColor,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white, size: 22),
          const SizedBox(width: 10),
          Text(
            alert.type.displayName,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // מצב "סיים" — תצוגת סיכום
  // ---------------------------------------------------------------------------

  Widget _buildFinishedView() {
    final route = _route;

    // קיבוץ התראות לפי סוג
    final alertCounts = <AlertType, int>{};
    for (final alert in _navigatorAlerts) {
      alertCounts[alert.type] = (alertCounts[alert.type] ?? 0) + 1;
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _isDisqualified ? Icons.block : Icons.check_circle,
                size: 80,
                color: _isDisqualified ? Colors.red[400] : Colors.green[400],
              ),
              const SizedBox(height: 24),
              Text(
                _isDisqualified ? 'הניווט נפסל' : 'הניווט הסתיים',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: _isDisqualified ? Colors.red : null,
                ),
              ),
              if (_isDisqualified) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red[300]!),
                  ),
                  child: Text(
                    'פריצת אבטחה — ציון 0',
                    style: TextStyle(
                      color: Colors.red[900],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 32),
              _summaryRow(
                icon: Icons.timer,
                label: 'זמן כולל',
                value: _formatDuration(_elapsed),
              ),
              const Divider(),
              _summaryRow(
                icon: Icons.location_on,
                label: 'דקירות',
                value: '$_punchCount',
              ),
              if (route != null) ...[
                const Divider(),
                _summaryRow(
                  icon: Icons.route,
                  label: 'מסלול מתוכנן',
                  value: '${route.routeLengthKm.toStringAsFixed(1)} ק"מ',
                ),
              ],
              const Divider(),
              _summaryRow(
                icon: Icons.straighten,
                label: 'מסלול בפועל',
                value: '${_actualDistanceKm.toStringAsFixed(1)} ק"מ',
              ),
              const Divider(),
              const SizedBox(height: 16),
              // סקציית התראות
              if (alertCounts.isEmpty)
                Row(
                  children: [
                    Icon(Icons.notifications_none, size: 28, color: Colors.grey[400]),
                    const SizedBox(width: 12),
                    Text(
                      'לא היו התראות',
                      style: TextStyle(fontSize: 16, color: Colors.grey[400]),
                    ),
                  ],
                )
              else ...[
                Row(
                  children: [
                    Icon(Icons.warning_amber, size: 28, color: Colors.orange[700]),
                    const SizedBox(width: 12),
                    Text(
                      'התראות (${_navigatorAlerts.length}):',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange[700],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...alertCounts.entries.map((entry) => Padding(
                  padding: const EdgeInsets.only(right: 40, bottom: 4),
                  child: Row(
                    children: [
                      Text(entry.key.emoji, style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 8),
                      Text(
                        entry.key.displayName,
                        style: const TextStyle(fontSize: 14),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '×${entry.value}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                )),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryRow({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 28, color: valueColor ?? Colors.grey[600]),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // Shared widgets
  // ===========================================================================

  Widget _buildGpsChip() {
    IconData icon;
    String label;
    Color color;
    IconData? secondIcon;

    if (_gpsBlocked) {
      icon = Icons.gps_off;
      label = 'GPS חסום';
      color = Colors.red;
    } else {
      switch (_gpsSource) {
        case PositionSource.gps:
          icon = Icons.gps_fixed;
          label = 'GPS';
          color = Colors.green;
        case PositionSource.cellTower:
          icon = Icons.cell_tower;
          label = 'אנטנות';
          color = Colors.orange;
        case PositionSource.pdr:
          icon = Icons.directions_walk;
          label = 'PDR';
          color = Colors.orange;
        case PositionSource.pdrCellHybrid:
          icon = Icons.directions_walk;
          secondIcon = Icons.cell_tower;
          label = 'PDR+Cell';
          color = Colors.orange;
        case PositionSource.none:
          icon = Icons.gps_off;
          label = 'אין מיקום';
          color = Colors.red;
      }
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        if (secondIcon != null) ...[
          const SizedBox(width: 2),
          Icon(secondIcon, size: 14, color: color),
        ],
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _statusChip({required IconData icon, required String label}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.grey[700]),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
      ],
    );
  }

  Widget _buildActionCard({
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.3), width: 2),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 48, color: color),
              const SizedBox(height: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
