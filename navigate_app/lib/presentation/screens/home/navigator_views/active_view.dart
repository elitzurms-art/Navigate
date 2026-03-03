import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../../../domain/entities/navigation.dart' as domain;
import '../../../../domain/entities/checkpoint_punch.dart';
import '../../../../domain/entities/coordinate.dart';
import '../../../../domain/entities/user.dart';
import '../../../../domain/entities/navigator_personal_status.dart';
import '../../../../data/repositories/navigation_repository.dart';
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
import '../../../../services/background_location_service.dart';
import '../../../../domain/entities/security_violation.dart';
import '../../../widgets/unlock_dialog.dart';
import 'package:latlong2/latlong.dart';
import '../../../../data/repositories/boundary_repository.dart';
import 'package:permission_handler/permission_handler.dart';
import 'manual_position_pin_screen.dart';
import '../../../../services/voice_service.dart';
import '../../../widgets/push_to_talk_button.dart';
import '../../../../data/repositories/voice_message_repository.dart';
import '../../../../domain/entities/voice_message.dart';
import '../../../../data/repositories/extension_request_repository.dart';
import '../../../../domain/entities/extension_request.dart';

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
  bool _isStarting = false;

  int _punchCount = 0;
  bool _securityActive = false;
  bool _isDisqualified = false;
  String? _disqualificationReason;
  DateTime? _securityStartTime; // grace period — התעלמות מ-Lock Task exit מיד אחרי הפעלה
  List<domain_cp.Checkpoint> _routeCheckpoints = [];

  // קבוצה (צמד/חוליה) — משני לא מפעיל GPS ולא דוקר
  bool _isGroupSecondary = false;

  // מאבטח — מנווט second_half ממתין ל-first_half לסיים
  bool _isGuardSecondHalf = false;
  bool _guardPartnerFinished = false;
  StreamSubscription<QuerySnapshot>? _guardPartnerListener;

  // דריסות מפה פר-מנווט (מהמפקד)
  bool _overrideAllowOpenMap = false;
  bool _overrideShowSelfLocation = false;
  bool _overrideShowRouteOnMap = false;

  // דקירת מיקום ידני — GPS-cycle: כל מחזור GPS→אובדן מאפשר דקירה חדשה
  bool _allowManualPosition = false;
  bool _manualPositionUsed = false;       // נוצל במחזור הנוכחי
  bool _manualPinPending = false;
  bool _hadGpsFix = false;                // היה GPS תקין בשלב כלשהו

  // GPS tracking
  final GPSTrackingService _gpsTracker = GPSTrackingService();
  Timer? _trackSaveTimer;
  Timer? _firestoreSyncTimer; // סנכרון ל-Firestore כל 2 דקות (נפרד משמירה ל-Drift)
  bool _isSavingTrack = false;
  bool _isSyncingToFirestore = false;
  int _lastSyncedPointCount = 0; // מספר נקודות בסנכרון האחרון — לזיהוי שינויים

  // GPS source tracking
  PositionSource _gpsSource = PositionSource.none;
  Timer? _gpsCheckTimer;
  LatLng? _boundaryCenter;
  bool _gpsBlocked = false;
  GpsJammingState _jammingState = GpsJammingState.normal;

  // דיווח סטטוס ל-system_status (כדי שהמפקד יראה בבדיקת מערכות)
  Timer? _statusReportTimer;
  final Battery _battery = Battery();
  int _batteryLevel = -1; // -1 = לא זמין
  Map<String, dynamic>? _lastStatusData; // מטמון לזיהוי שינויים — חוסך כתיבות Firestore

  // Health check
  HealthCheckService? _healthCheckService;

  // Alert monitoring
  AlertMonitoringService? _alertMonitoringService;

  // באנר התראה למנווט + צפצוף חזק (alarm channel — עובד גם ב-DND)
  NavigatorAlert? _currentAlertBanner;
  Timer? _alertBannerTimer;
  late final AudioPlayer _alertPlayer;

  // Voice (PTT)
  VoiceService? _voiceService;
  bool? _overrideWalkieTalkieEnabled;
  int _pttUnreadCount = 0;
  StreamSubscription<List<VoiceMessage>>? _pttMessagesSub;
  final Set<String> _seenPttMessageIds = {};
  bool _pttInitialLoad = true;

  // בקשות הארכה
  final ExtensionRequestRepository _extensionRepo = ExtensionRequestRepository();
  StreamSubscription<List<ExtensionRequest>>? _extensionListener;
  ExtensionRequest? _activeExtensionRequest; // הבקשה האחרונה (pending/approved/rejected)
  int _totalApprovedExtensionMinutes = 0;

  // נוהל ברבור
  bool _barburActive = false;
  NavigatorAlert? _activeBarburAlert;
  StreamSubscription<NavigatorAlert?>? _barburAlertListener;

  // Firestore real-time listener — זיהוי מיידי של עצירה/איפוס מרחוק
  StreamSubscription<DocumentSnapshot>? _trackDocListener;
  bool _trackJustCreated = false; // grace flag — track נוצר מקומית, טרם סונכרן ל-Firestore

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
    _alertPlayer = AudioPlayer();
    _alertPlayer.setAudioContext(AudioContext(
      android: AudioContextAndroid(
        usageType: AndroidUsageType.alarm,
        contentType: AndroidContentType.sonification,
        audioFocus: AndroidAudioFocus.gainTransient,
      ),
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.playback,
        options: {AVAudioSessionOptions.duckOthers},
      ),
    ));
    _allowManualPosition = widget.navigation.allowManualPosition;
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
    // עדכון הגדרות התראות בזמן אמת
    if (oldWidget.navigation.alerts != widget.navigation.alerts) {
      _alertMonitoringService?.updateAlertConfig(widget.navigation.alerts);
    }
    // הפעלת listener בקשות הארכה אם הופעל בזמן אמת ע"י המפקד
    if (!oldWidget.navigation.timeCalculationSettings.allowExtensionRequests &&
        widget.navigation.timeCalculationSettings.allowExtensionRequests) {
      _startExtensionListener();
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
    _firestoreSyncTimer?.cancel();
    _statusReportTimer?.cancel();
    _healthCheckService?.dispose();
    _alertMonitoringService?.dispose();
    _alertBannerTimer?.cancel();
    _gpsTracker.stopTracking();
    BackgroundLocationService().stop(); // safety net
    _gpsService.dispose();
    _voiceService?.dispose();
    _pttMessagesSub?.cancel();
    _alertPlayer.dispose();
    _extensionListener?.cancel();
    _barburAlertListener?.cancel();
    _guardPartnerListener?.cancel();
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
        _isGroupSecondary = effectiveTrack?.isGroupSecondary ?? false;

        // מאבטח — זיהוי second_half + בדיקת סיום partner
        final myRoute = _nav.routes[widget.currentUser.uid];
        _isGuardSecondHalf = _nav.forceComposition.isGuard &&
            myRoute?.segmentType == 'second_half';

        if (_isGuardSecondHalf && status == NavigatorPersonalStatus.waiting) {
          // בדיקה ראשונית אם ה-partner כבר סיים
          await _checkGuardPartnerStatus();
          // התחלת listener ל-track של ה-partner
          _startGuardPartnerListener();
          // נעילת טלפון בזמן המתנה (לפני תחילת ניווט)
          _startSecurity();
        }

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
          // GPS-cycle: on reload, don't use DB manualPositionUsed as permanent block
          // Reset — _checkGpsSource will detect GPS state and allow manual pin if needed
          _manualPositionUsed = false;
          _hadGpsFix = false;
          _startElapsedTimer();
          _startSecurity();
          // GPS + שירותים — רק לנציג (לא למשני בצמד/חוליה)
          // מאבטח: שני המנווטים primary — כל אחד בחצי שלו
          if (!_isGroupSecondary || _nav.forceComposition.isGuard) {
            _startGpsTracking();
            _startGpsSourceCheck();
            _startHealthCheck();
            _startAlertMonitoring();
            _startTrackDocListener();
            _startExtensionListener();
            _startPttListener();
            _checkExistingBarburAlert();
          }
          _startStatusReporting();
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
          print('DEBUG ActiveView: onLockTaskExit in grace period — ignoring');
          return;  // Don't call enableLockTask() — it would show the dialog again
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

  // ===========================================================================
  // מאבטח — המתנה ל-first_half partner
  // ===========================================================================

  /// בדיקה חד-פעמית אם ה-partner (first_half) כבר סיים
  Future<void> _checkGuardPartnerStatus() async {
    final partnerId = _getGuardFirstHalfPartnerId();
    if (partnerId == null) return;

    try {
      final snap = await FirebaseFirestore.instance
          .collection(AppConstants.navigationTracksCollection)
          .where('navigationId', isEqualTo: _nav.id)
          .where('navigatorUserId', isEqualTo: partnerId)
          .get();
      if (snap.docs.isNotEmpty) {
        final data = snap.docs.first.data();
        final isActive = data['isActive'] as bool? ?? true;
        if (!isActive && mounted) {
          _guardPartnerFinished = true;
        }
      }
    } catch (_) {}
  }

  /// listener ל-track של ה-first_half partner — מעדכן כש-partner מסיים
  void _startGuardPartnerListener() {
    final partnerId = _getGuardFirstHalfPartnerId();
    if (partnerId == null) return;

    _guardPartnerListener?.cancel();
    _guardPartnerListener = FirebaseFirestore.instance
        .collection(AppConstants.navigationTracksCollection)
        .where('navigationId', isEqualTo: _nav.id)
        .where('navigatorUserId', isEqualTo: partnerId)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      if (snap.docs.isNotEmpty) {
        final data = snap.docs.first.data();
        final isActive = data['isActive'] as bool? ?? true;
        if (!isActive && !_guardPartnerFinished) {
          setState(() => _guardPartnerFinished = true);
        }
      }
    });
  }

  /// מציאת מנווט ה-first_half ב-guard
  String? _getGuardFirstHalfPartnerId() {
    try {
      return _nav.routes.entries
          .firstWhere((e) => e.value.segmentType == 'first_half')
          .key;
    } catch (_) {
      return null;
    }
  }

  /// פסילת מנווט — סיום ניווט + סימון ב-track + שליחת התראה למפקד
  /// מיפוי סוג חריגה לסיבת פסילה קריאה
  String _getDisqualificationReason(ViolationType type) {
    switch (type) {
      case ViolationType.phoneCallAnswered:
        return 'מענה לשיחה בזמן ניווט';
      case ViolationType.exitLockTask:
      case ViolationType.exitGuidedAccess:
        return 'יציאה מנעילה בזמן ניווט';
      case ViolationType.appClosed:
      case ViolationType.appBackgrounded:
        return 'התנתקות משתמש בזמן ניווט';
      default:
        return 'פריצת אבטחה בזמן ניווט';
    }
  }

  Future<void> _handleDisqualification(ViolationType type) async {
    if (_isDisqualified || _track == null) return;

    // סימון מיידי — מונע race condition עם _saveTrackPoints שרץ במקביל
    // (ללא setState כדי שה-safety net ב-_saveTrackPoints יראה את הערך הנכון מיד)
    _isDisqualified = true;
    _disqualificationReason = _getDisqualificationReason(type);

    try {
      // עצירת GPS + שמירת נקודות אחרונות לפני סיום
      await _stopGpsTracking();

      // עצירת שירותי ניטור
      _alertMonitoringService?.stop();
      _healthCheckService?.dispose();
      _gpsCheckTimer?.cancel();
      _statusReportTimer?.cancel();
      _elapsedTimer?.cancel();

      // סיום הניווט (isActive=false, endedAt=now)
      await _trackRepo.endNavigation(_track!.id);

      // סימון isDisqualified=true ב-track (Drift + Firestore)
      await _trackRepo.disqualifyNavigator(_track!.id, reason: _disqualificationReason);

      // פסילה קבוצתית — רק צמד/חוליה (לא מאבטח — שם כל מנווט עצמאי)
      final route = _nav.routes[widget.currentUser.uid];
      final groupId = route?.groupId;
      if (groupId != null && _nav.forceComposition.isGroupedPairOrSquad) {
        final groupMembers = _nav.routes.entries
            .where((e) => e.value.groupId == groupId && e.key != widget.currentUser.uid)
            .map((e) => e.key);
        for (final memberId in groupMembers) {
          await _trackRepo.disqualifyByNavigator(memberId, _nav.id,
              reason: 'פסילה קבוצתית — ${_disqualificationReason}');
        }
      }

      // כתיבה ישירה ל-Firestore — לא דרך queue
      try {
        final updatedTrack = await _trackRepo.getById(_track!.id);
        await FirebaseFirestore.instance
            .collection(AppConstants.navigationTracksCollection)
            .doc(_track!.id)
            .set({
          'id': updatedTrack.id,
          'navigationId': updatedTrack.navigationId,
          'navigatorUserId': updatedTrack.navigatorUserId,
          'trackPointsJson': updatedTrack.trackPointsJson,
          'stabbingsJson': updatedTrack.stabbingsJson,
          'startedAt': updatedTrack.startedAt.toUtc().toIso8601String(),
          'endedAt': updatedTrack.endedAt?.toUtc().toIso8601String(),
          'isActive': updatedTrack.isActive,
          'isDisqualified': updatedTrack.isDisqualified,
          'disqualificationReason': _disqualificationReason,
          'manualPositionUsed': updatedTrack.manualPositionUsed,
          'manualPositionUsedAt': updatedTrack.manualPositionUsedAt?.toUtc().toIso8601String(),
          'isGroupSecondary': updatedTrack.isGroupSecondary,
        }, SetOptions(merge: true));
      } catch (_) {}

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
      setState(() {
        _personalStatus = NavigatorPersonalStatus.finished;
      });
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

        await _handleDisqualification(ViolationType.exitLockTask);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_disqualificationReason ?? 'הניווט נפסל'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
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

    // GPS-cycle manual position: detect GPS transitions
    final bool isGoodGps = source == PositionSource.gps && lastPoint.accuracy >= 0 && lastPoint.accuracy < 100;
    if (isGoodGps) {
      if (!_hadGpsFix || _manualPositionUsed) {
        // GPS returned — reset manual position for next GPS-loss cycle
        _hadGpsFix = true;
        _manualPositionUsed = false;
      }
    } else if (_hadGpsFix && source != PositionSource.gps && _allowManualPosition && !_manualPositionUsed && !_manualPinPending) {
      // GPS lost after having it — auto-trigger manual pin if allowed
      final age = DateTime.now().difference(lastPoint.timestamp);
      if (age.inSeconds > 60) {
        _checkAndTriggerManualPin();
      }
    }

    setState(() {
      _gpsSource = source;
      _jammingState = _gpsTracker.jammingState;
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

      // מיקום אחרון מה-tracker
      final points = _gpsTracker.trackPoints;
      final lastPoint = points.isNotEmpty ? points.last : null;

      // בדיקת הרשאות מיקרופון וטלפון
      final micStatus = await Permission.microphone.status;
      final phoneStatus = await Permission.phone.status;

      // בדיקת DND (Android בלבד)
      final hasDnd = Platform.isAndroid
          ? await DeviceSecurityService().hasDNDPermission()
          : true;

      // בניית נתוני סטטוס להשוואה (ללא שדות שמשתנים תמיד כמו updatedAt)
      final compareData = <String, dynamic>{
        'isConnected': lastPoint != null || _gpsSource != PositionSource.none,
        'batteryLevel': _batteryLevel >= 0 ? _batteryLevel : null,
        'hasGPS': _gpsSource == PositionSource.gps,
        'gpsAccuracy': (lastPoint?.accuracy ?? -1).round(), // עיגול למניעת שינויים זעירים
        'receptionLevel': _estimateReceptionLevel(),
        'positionSource': _gpsSource.name,
        'hasMicrophonePermission': micStatus.isGranted,
        'hasPhonePermission': phoneStatus.isGranted,
        'hasDNDPermission': hasDnd,
        'gpsJammingState': _gpsTracker.jammingState.name,
        'latitude': lastPoint?.coordinate.lat,
        'longitude': lastPoint?.coordinate.lng,
      };

      // השוואה למטמון — דילוג על כתיבה אם לא השתנה כלום
      if (_lastStatusData != null && _statusDataUnchanged(compareData, _lastStatusData!)) {
        return;
      }
      _lastStatusData = compareData;

      final docRef = FirebaseFirestore.instance
          .collection(AppConstants.navigationsCollection)
          .doc(_nav.id)
          .collection('system_status')
          .doc(uid);

      final data = <String, dynamic>{
        'navigatorId': uid,
        'navigatorName': widget.currentUser.fullName,
        ...compareData,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (lastPoint != null) {
        data['positionUpdatedAt'] = FieldValue.serverTimestamp();
      }
      // הסרת lat/lng מ-data (כבר ב-compareData) ושמירה רק אם יש מיקום
      data.remove('latitude');
      data.remove('longitude');
      if (lastPoint != null) {
        data['latitude'] = lastPoint.coordinate.lat;
        data['longitude'] = lastPoint.coordinate.lng;
      }

      await docRef.set(data, SetOptions(merge: true));
    } catch (e) {
      print('DEBUG ActiveView: system_status report failed: $e');
    }
  }

  /// השוואת נתוני סטטוס — true אם זהים (אין צורך בכתיבה)
  bool _statusDataUnchanged(Map<String, dynamic> current, Map<String, dynamic> previous) {
    for (final key in current.keys) {
      if (current[key] != previous[key]) return false;
    }
    return current.length == previous.length;
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
  /// [force] = true כשהמנווט לוחץ ידנית על הרנאב — דלג על בדיקת מיקום אחרון
  Future<void> _checkAndTriggerManualPin({bool force = false}) async {
    if (_manualPositionUsed || !_allowManualPosition || _manualPinPending) return;
    if (_personalStatus != NavigatorPersonalStatus.active) return;

    // שלב א — בדיקה אם יש מיקום אחרון טוב (רק באוטומטי, לא בלחיצה ידנית)
    if (!force) {
      final points = _gpsTracker.trackPoints;
      if (points.isNotEmpty) {
        final lastPoint = points.last;
        final age = DateTime.now().difference(lastPoint.timestamp);
        if (age.inMinutes < 5 && lastPoint.accuracy >= 0 && lastPoint.accuracy < 100) {
          return;
        }
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
      await _saveTrackPointsLocal();
      await _syncTrackToFirestore(); // סנכרון מיידי — מיקום ידני חשוב למפקד
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('מיקום ידני נרשם בהצלחה'), backgroundColor: Colors.deepPurple),
      );
    }
    if (mounted) setState(() {});
  }

  Future<void> _startGpsTracking() async {
    // הפעלת foreground service — מחזיק את האפליקציה חיה ברקע
    await BackgroundLocationService().start();

    final interval = _nav.gpsUpdateIntervalSeconds;
    final started = await _gpsTracker.startTracking(
      intervalSeconds: interval,
      boundaryCenter: _boundaryCenter,
      enabledPositionSources: _nav.enabledPositionSources,
      gpsSpoofingDetectionEnabled: _nav.gpsSpoofingDetectionEnabled,
      gpsSpoofingMaxDistanceKm: _nav.gpsSpoofingMaxDistanceKm,
    );
    if (!started) {
      print('DEBUG ActiveView: GPS tracking failed to start');
      return;
    }

    // שמירה תקופתית ל-Drift — מינימום 10 שניות גם אם interval קצר יותר
    final saveInterval = interval < 10 ? 10 : (interval < 30 ? interval : 30);
    _trackSaveTimer = Timer.periodic(
      Duration(seconds: saveInterval),
      (_) => _saveTrackPointsLocal(),
    );

    // סנכרון ל-Firestore כל 2 דקות (נפרד משמירה ל-Drift — חיסכון בכתיבות)
    _firestoreSyncTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => _syncTrackToFirestore(),
    );
  }

  /// שמירה מקומית ל-Drift בלבד — מהירה, ללא Firestore (crash recovery)
  Future<void> _saveTrackPointsLocal() async {
    if (_track == null) return;
    if (_isSavingTrack) return;
    _isSavingTrack = true;

    try {
      final points = _gpsTracker.trackPoints;
      if (points.isNotEmpty) {
        await _trackRepo.updateTrackPoints(_track!.id, points);
      }
    } catch (e) {
      print('DEBUG ActiveView: local track save error: $e');
    } finally {
      _isSavingTrack = false;
    }
  }

  /// סנכרון ל-Firestore — רק כשיש נקודות חדשות מאז הסנכרון האחרון
  Future<void> _syncTrackToFirestore() async {
    if (_track == null) return;
    if (_isSyncingToFirestore) return;
    _isSyncingToFirestore = true;

    try {
      // בדיקת עצירה מרחוק BEFORE sync — כדי שלא לדרוס isActive=false של המפקד
      final stopped = await _checkRemoteStop();
      if (stopped) return;

      final currentPointCount = _gpsTracker.trackPoints.length;

      // דילוג על סנכרון אם אין נקודות חדשות — system_status כבר מדווח סטטוס פעיל
      if (currentPointCount == _lastSyncedPointCount && currentPointCount > 0) {
        return;
      }

      // שמירה מקומית קודם (אם לא נשמרה עדיין)
      final points = _gpsTracker.trackPoints;
      if (points.isNotEmpty) {
        await _trackRepo.updateTrackPoints(_track!.id, points);
      }

      var updatedTrack = await _trackRepo.getById(_track!.id);
      // safety net: UI state הוא ה-source of truth לפסילה — מונע דריסת ביטול פסילה
      if (updatedTrack.isDisqualified != _isDisqualified) {
        updatedTrack = updatedTrack.copyWith(isDisqualified: _isDisqualified);
      }
      await _trackRepo.syncTrackToFirestore(updatedTrack);
      _lastSyncedPointCount = currentPointCount;
    } catch (e) {
      print('DEBUG ActiveView: Firestore track sync error: $e');
    } finally {
      _isSyncingToFirestore = false;
    }
  }

  Future<void> _stopGpsTracking() async {
    _trackSaveTimer?.cancel();
    _trackSaveTimer = null;
    _firestoreSyncTimer?.cancel();
    _firestoreSyncTimer = null;

    // שמירה סופית לפני עצירה — Drift + Firestore (גם אם remote stop)
    if (_track != null) {
      final points = _gpsTracker.trackPoints;
      if (points.isNotEmpty) {
        try {
          await _trackRepo.updateTrackPoints(_track!.id, points);
        } catch (_) {}
      }
      // סנכרון סופי ל-Firestore — ודא שכל הנקודות מגיעות למפקד
      try {
        var updatedTrack = await _trackRepo.getById(_track!.id);
        if (updatedTrack.isDisqualified != _isDisqualified) {
          updatedTrack = updatedTrack.copyWith(isDisqualified: _isDisqualified);
        }
        await _trackRepo.syncTrackToFirestore(updatedTrack);
      } catch (_) {}
    }

    await _gpsTracker.stopTracking();

    // עצירת foreground service
    await BackgroundLocationService().stop();
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
        if (_trackJustCreated) {
          // track נוצר מקומית וטרם סונכרן ל-Firestore — לא מדובר במחיקת מפקד
          return;
        }
        // המפקד מחק את ה-track — איפוס (תמיד, גם אחרי סיום)
        _performRemoteReset();
        return;
      }
      // Doc exists — track סונכרן בהצלחה
      _trackJustCreated = false;

      final data = snapshot.data();
      print('DEBUG ActiveView: track doc snapshot — overrideWalkieTalkieEnabled=${data?['overrideWalkieTalkieEnabled']}, personalStatus=$_personalStatus');
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

      // זיהוי המשך ניווט — מנווט שסיים והמפקד חידש אותו
      final isActive = data['isActive'] as bool? ?? true;
      if (_personalStatus == NavigatorPersonalStatus.finished && isActive) {
        _performRemoteResume();
        return;
      }

      // שאר הלוגיקה רלוונטית רק במצב פעיל
      if (_personalStatus != NavigatorPersonalStatus.active) return;

      if (!isActive) {
        // המפקד עצר את הניווט
        _performRemoteStop();
        return;
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
        // עדכון Drift מקומי — מונע מ-_saveTrackPoints לדרוס את ההגדרות
        if (_track != null) {
          try {
            await _trackRepo.updateMapOverridesLocal(
              _track!.id,
              allowOpenMap: newAllowOpenMap,
              showSelfLocation: newShowSelfLocation,
              showRouteOnMap: newShowRouteOnMap,
            );
          } catch (_) {}
        }
        widget.onMapPermissionsChanged?.call(
          newAllowOpenMap, newShowSelfLocation, newShowRouteOnMap,
        );
      }

      // קריאת דריסת דקירת מיקום ידני
      final newAllowManual = data['overrideAllowManualPosition'] as bool? ?? false;
      // עדכון Drift מקומי — מונע דריסה ב-_saveTrackPoints
      if (_track != null && newAllowManual != (_track!.overrideAllowManualPosition)) {
        try {
          await _trackRepo.updateManualPositionOverrideLocal(
            _track!.id,
            allowManualPosition: newAllowManual,
          );
        } catch (_) {}
      }
      final globalAllow = widget.navigation.allowManualPosition;
      final effectiveAllow = globalAllow || newAllowManual;
      final wasDisabled = !_allowManualPosition;
      if (effectiveAllow && wasDisabled) {
        _manualPositionUsed = false;
      }
      _allowManualPosition = effectiveAllow;
      // הפעלת בדיקה רק במעבר מכבוי לדלוק — לא בכל snapshot
      if (effectiveAllow && wasDisabled && !_manualPositionUsed && !_manualPinPending) {
        _checkAndTriggerManualPin();
      }

    // קריאת דריסת ווקי טוקי
    final newWalkieTalkieEnabled = data['overrideWalkieTalkieEnabled'] as bool?;
    if (newWalkieTalkieEnabled != _overrideWalkieTalkieEnabled) {
      print('DEBUG ActiveView: walkieTalkie override changed: $_overrideWalkieTalkieEnabled → $newWalkieTalkieEnabled (nav default=${widget.navigation.communicationSettings.walkieTalkieEnabled})');
      _overrideWalkieTalkieEnabled = newWalkieTalkieEnabled;
      // עדכון Drift מקומי — מונע דריסה ב-_saveTrackPoints (בדומה לדריסות מפה)
      if (_track != null && newWalkieTalkieEnabled != null) {
        try {
          await _trackRepo.updateWalkieTalkieOverrideLocal(
            _track!.id,
            enabled: newWalkieTalkieEnabled,
          );
        } catch (_) {}
      }
      if (mounted) setState(() {});
    }

    // קריאת דריסת תדירות GPS
    final overrideGpsInterval = data['overrideGpsIntervalSeconds'] as int?;
    final effectiveInterval = overrideGpsInterval ?? _nav.gpsUpdateIntervalSeconds;
    if (effectiveInterval != _gpsTracker.intervalSeconds) {
      print('DEBUG ActiveView: GPS interval override changed to $effectiveInterval (override=$overrideGpsInterval, default=${_nav.gpsUpdateIntervalSeconds})');
      _gpsTracker.updateInterval(effectiveInterval);
      // עדכון timer שמירה ל-Drift בהתאם
      _trackSaveTimer?.cancel();
      final saveInterval = effectiveInterval < 10 ? 10 : (effectiveInterval < 30 ? effectiveInterval : 30);
      _trackSaveTimer = Timer.periodic(
        Duration(seconds: saveInterval),
        (_) => _saveTrackPointsLocal(),
      );
    }

    // קריאת דריסת אמצעי מיקום
    final overrideSources = data['overrideEnabledPositionSources'];
    final List<String> effectiveSources;
    if (overrideSources is List && overrideSources.isNotEmpty) {
      effectiveSources = overrideSources.cast<String>();
    } else {
      effectiveSources = _nav.enabledPositionSources;
    }
    if (!listEquals(effectiveSources, _gpsTracker.enabledSources)) {
      print('DEBUG ActiveView: position sources override changed to $effectiveSources');
      _gpsTracker.updateEnabledSources(effectiveSources);
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

    } catch (e) {
      print('DEBUG ActiveView: remote stop check error: $e');
    }
    return false;
  }

  Future<void> _performRemoteStop() async {
    // עצירת GPS tracking + foreground service
    _trackSaveTimer?.cancel();
    _trackSaveTimer = null;
    await _gpsTracker.stopTracking();
    await BackgroundLocationService().stop();

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

  /// המשך ניווט מרחוק — המפקד חידש את ה-track, המנווט ממשיך מאיפה שנעצר
  Future<void> _performRemoteResume() async {
    if (_track == null) return;

    // עדכון Drift מקומי
    try {
      await _trackRepo.resumeNavigation(_track!.id);
    } catch (_) {}

    // חזרה למצב פעיל
    _startTime = _track!.startedAt;
    _elapsed = DateTime.now().difference(_startTime!);
    _manualPositionUsed = false;
    _hadGpsFix = false;

    if (mounted) {
      setState(() {
        _personalStatus = NavigatorPersonalStatus.active;
        _isLoading = false;
      });

      // הפעלת שירותים — כמו נתיב "already active on reload"
      _startElapsedTimer();
      _startSecurity();
      if (!_isGroupSecondary) {
        _startGpsTracking();
        _startGpsSourceCheck();
        _startHealthCheck();
        _startAlertMonitoring();
        _startExtensionListener();
        _startPttListener();
        _checkExistingBarburAlert();
      }
      _startStatusReporting();

      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('הניווט ממשיך'),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 5),
        ),
      );
    }
  }

  /// איפוס ניווט מרחוק — המפקד מחק את ה-track, המנווט חוזר למצב ממתין נקי
  Future<void> _performRemoteReset() async {
    // עצירת listener מיידית — למנוע קריאות כפולות
    _stopTrackDocListener();

    // עצירת GPS tracking + foreground service
    _trackSaveTimer?.cancel();
    _trackSaveTimer = null;
    await _gpsTracker.stopTracking();
    await BackgroundLocationService().stop();

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
          if (mounted) {
            setState(() {});
            if (isAlarming) {
              _playAlertFeedback(); // alarm channel + רטט ×3
            }
          }
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
      _playAlertFeedback();
    }

    // באנר נעלם אחרי 8 שניות
    _alertBannerTimer = Timer(const Duration(seconds: 8), () {
      if (mounted) {
        setState(() => _currentAlertBanner = null);
      }
    });
  }

  /// צפצוף חזק + רטט — 3 פעימות (alarm channel עוקף DND)
  Future<void> _playAlertFeedback() async {
    for (int i = 0; i < 3; i++) {
      HapticFeedback.heavyImpact();
      try {
        await _alertPlayer.stop();
        await _alertPlayer.play(AssetSource('sounds/alert_beep.wav'));
      } catch (_) {
        // fallback — אם הקובץ לא נטען
        SystemSound.play(SystemSoundType.alert);
      }
      if (i < 2) {
        await Future.delayed(const Duration(milliseconds: 400));
      }
    }
  }

  // ===========================================================================
  // Actions — start / end navigation
  // ===========================================================================

  /// בקשת כל ההרשאות החסרות באופן אוטומטי
  Future<void> _requestAllMissingPermissions() async {
    final permissions = [
      Permission.notification,
      Permission.location,
      Permission.locationAlways,
      Permission.microphone,
      Permission.phone,
      Permission.sms,
      Permission.activityRecognition,
    ];

    for (final permission in permissions) {
      final status = await permission.status;
      if (!status.isGranted && !status.isPermanentlyDenied) {
        await permission.request();
      }
    }
  }

  Future<void> _startNavigation() async {
    if (_isStarting) return;
    _isStarting = true;
    setState(() => _isLoading = true);
    try {
      // 0. בדיקת נציג קבוצתי (צמד/חוליה — לא מאבטח)
      final route = _nav.routes[widget.currentUser.uid];
      final groupId = route?.groupId;
      final composition = _nav.forceComposition;
      // מאבטח = שני ניווטי בדד רצופים, לא צמד/חוליה — אין נציג/משני
      final isGrouped = composition.isGroupedPairOrSquad && groupId != null;

      bool isRepresentative = true; // ברירת מחדל: solo → נציג

      if (isGrouped) {
        final existingRep = composition.getActiveRepresentative(groupId);
        if (existingRep != null && existingRep != widget.currentUser.uid) {
          // כבר יש נציג אחר — מנווט משני
          isRepresentative = false;
        } else if (existingRep == null) {
          // אין נציג — שאל
          final confirmed = await _showActiveRepresentativeDialog();
          if (confirmed) {
            await _claimActiveRepresentative(groupId);
            isRepresentative = true;
          } else {
            isRepresentative = false;
          }
        }
        // else: existingRep == me → isRepresentative = true
      }

      _isGroupSecondary = !isRepresentative;

      // 1. בקשת כל ההרשאות החסרות לפני תחילת ניווט
      await _requestAllMissingPermissions();

      // 2. יצירת track — הפעולה המרכזית
      final track = await _trackRepo.startNavigation(
        navigatorUserId: widget.currentUser.uid,
        navigationId: _nav.id,
        isGroupSecondary: _isGroupSecondary,
      );
      _startTime = track.startedAt;
      _track = track;

      // 2.5. עדכון סטטוס הניווט ל-active (אם עדיין waiting)
      if (_nav.status == 'waiting') {
        final updatedNav = _nav.copyWith(
          status: 'active',
          activeStartTime: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await NavigationRepository().update(updatedNav);
      }

      // 3. הפעלת אבטחה (Lock Task + DND + ניטור שיחות) — תמיד, גם למשני
      await _startSecurity();

      // 4. מעבר למצב active מיידית — שירותים לא-קריטיים ברקע
      _trackJustCreated = true; // grace: track עדיין לא ב-Firestore
      setState(() {
        _personalStatus = NavigatorPersonalStatus.active;
        _elapsed = Duration.zero;
        _isLoading = false;
      });
      _startElapsedTimer();

      // 5. סנכרון ל-Firestore — fire and forget
      _trackRepo.syncTrackToFirestore(track).catchError((e) {
        print('DEBUG ActiveView: sync error (non-blocking): $e');
      });

      // 6. GPS + שמירת נקודה ראשונה — רק לנציג (לא למשני בצמד/חוליה)
      // מאבטח: שני המנווטים primary — כל אחד בחצי שלו
      if (!_isGroupSecondary || _nav.forceComposition.isGuard) {
        _startGpsTracking().then((_) {
          _saveTrackPointsLocal();
          _syncTrackToFirestore(); // סנכרון ראשוני ל-Firestore
        }).catchError((e) {
          print('DEBUG ActiveView: GPS start error: $e');
        });
      }

      // 7. שירותים נלווים — רק לנציג (מאבטח: שניהם primary)
      if (!_isGroupSecondary || _nav.forceComposition.isGuard) {
        _startGpsSourceCheck();
        _startHealthCheck();
        _startAlertMonitoring();
        _startTrackDocListener();
        _startExtensionListener();
        _startPttListener();
      }
      // דיווח סטטוס — תמיד
      _startStatusReporting();

      // דקירת מיקום ידני — מופעל רק בשני מקרים:
      // 1. אחרי איבוד GPS של 60+ שניות (ב-_checkGpsSource)
      // 2. לחיצה ידנית של המנווט על הבאנר
    } catch (e) {
      // מגיע לכאן רק אם הרשאות, יצירת track, או אבטחה נכשלו
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בהתחלת ניווט: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      _isStarting = false;
    }
  }

  /// דיאלוג בחירת נציג ניווט פעיל
  Future<bool> _showActiveRepresentativeDialog() async {
    final type = _nav.forceComposition.type;
    final label = type == 'pair' ? 'צמד' : (type == 'squad' ? 'חוליה' : 'קבוצה');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('נציג ה$label'),
        content: Text('האם אתה נציג ה$label בניווט?\n'
            'הנציג מנווט עם GPS ודקירות. חברים אחרים רצים עם אבטחה בלבד.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('לא, אני משני')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('כן, אני הנציג')),
        ],
      ),
    );
    return confirmed ?? false;
  }

  /// תביעת נציגות ניווט פעיל
  Future<void> _claimActiveRepresentative(String groupId) async {
    final updatedReps = Map<String, String>.from(
      _nav.forceComposition.activeRepresentatives,
    );
    updatedReps[groupId] = widget.currentUser.uid;
    final updatedNav = _nav.copyWith(
      forceComposition: _nav.forceComposition.copyWith(
        activeRepresentatives: updatedReps,
      ),
      updatedAt: DateTime.now(),
    );
    await NavigationRepository().update(updatedNav);
    widget.onNavigationUpdated(updatedNav);
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

    // עדיפות למיקום Kalman מסונן מהמעקב הפעיל — מדויק יותר מ-GPS גולמי
    Coordinate currentCoord;
    if (_gpsTracker.isTracking && _gpsTracker.trackPoints.isNotEmpty) {
      final lastFiltered = _gpsTracker.trackPoints.last;
      currentCoord = lastFiltered.coordinate;
    } else {
      // fallback — מעקב לא פעיל, שימוש ב-GPS ישיר
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
      currentCoord = Coordinate(
        lat: posResult.position.latitude,
        lng: posResult.position.longitude,
        utm: '',
      );
    }

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
          const SnackBar(
            content: Text('בוצעה דקירת נקודה במפה'),
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

    // מיקום — לא חוסם את השליחה אם נכשל
    Coordinate location = const Coordinate(lat: 0, lng: 0, utm: '');
    try {
      final position = await _gpsService.getCurrentPosition();
      if (position != null) {
        location = Coordinate(
          lat: position.latitude,
          lng: position.longitude,
          utm: '',
        );
      }
    } catch (_) {}

    try {
      final alert = NavigatorAlert(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        navigationId: _nav.id,
        navigatorId: widget.currentUser.uid,
        navigatorName: widget.currentUser.fullName,
        type: AlertType.healthReport,
        location: location,
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
    if (_barburActive) {
      // נוהל ברבור כבר פעיל — הצע לסיים
      _barburResolved();
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.report_problem, color: Colors.orange, size: 28),
            SizedBox(width: 8),
            Text('נוהל ברבור'),
          ],
        ),
        content: const Text('האם אתה אבוד ורוצה להפעיל נוהל ברבור?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ביטול'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _sendBarburAlert();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('הפעל נוהל ברבור'),
          ),
        ],
      ),
    );
  }

  Future<void> _sendBarburAlert() async {
    try {
      final position = await _gpsService.getCurrentPosition();
      final alert = NavigatorAlert(
        id: 'barbur-${widget.currentUser.uid}-${DateTime.now().millisecondsSinceEpoch}',
        navigationId: _nav.id,
        navigatorId: widget.currentUser.uid,
        type: AlertType.barbur,
        location: Coordinate(
          lat: position?.latitude ?? 0,
          lng: position?.longitude ?? 0,
          utm: '',
        ),
        timestamp: DateTime.now(),
        navigatorName: widget.currentUser.fullName,
        barburChecklist: {
          'returnToAxis': false,
          'goToHighPoint': false,
          'openMap': false,
          'showLocation': false,
        },
      );
      await _alertRepo.create(alert);

      if (mounted) {
        setState(() {
          _barburActive = true;
          _activeBarburAlert = alert;
        });
        _startBarburAlertListener(alert.id);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('נוהל ברבור הופעל — המפקד קיבל התראה'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בהפעלת נוהל ברבור: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _barburResolved() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 28),
            SizedBox(width: 8),
            Text('סיום נוהל ברבור'),
          ],
        ),
        content: const Text('האם הסתדרת ורוצה לסיים את נוהל ברבור?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('המשך נוהל'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _resolveBarburAlert();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('הסתדרתי'),
          ),
        ],
      ),
    );
  }

  Future<void> _resolveBarburAlert() async {
    if (_activeBarburAlert == null) return;
    try {
      // סגירת ההתראה
      await _alertRepo.resolve(_nav.id, _activeBarburAlert!.id, widget.currentUser.uid);

      // ביטול דריסות מפה שנפתחו במסגרת הנוהל
      if (_track != null) {
        await _trackRepo.updateMapOverrides(
          _track!.id,
          allowOpenMap: false,
          showSelfLocation: false,
          showRouteOnMap: false,
        );
      }

      if (mounted) {
        setState(() {
          _overrideAllowOpenMap = false;
          _overrideShowSelfLocation = false;
          _overrideShowRouteOnMap = false;
          _barburActive = false;
          _activeBarburAlert = null;
        });
        _barburAlertListener?.cancel();
        widget.onMapPermissionsChanged?.call(false, false, false);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('נוהל ברבור הסתיים'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בסיום נוהל ברבור: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _startBarburAlertListener(String alertId) {
    _barburAlertListener?.cancel();
    _barburAlertListener = _alertRepo
        .watchAlert(_nav.id, alertId)
        .listen((alert) {
      if (!mounted) return;
      if (alert == null || !alert.isActive) {
        // ההתראה נסגרה (ע"י המפקד או בוטלה)
        setState(() {
          _barburActive = false;
          _activeBarburAlert = null;
        });
        _barburAlertListener?.cancel();
        return;
      }
      // עדכון הצ'קליסט בזמן אמת
      setState(() => _activeBarburAlert = alert);
    });
  }

  Future<void> _checkExistingBarburAlert() async {
    try {
      final existing = await _alertRepo.getActiveBarburAlert(_nav.id, widget.currentUser.uid);
      if (existing != null && mounted) {
        setState(() {
          _barburActive = true;
          _activeBarburAlert = existing;
        });
        _startBarburAlertListener(existing.id);
      }
    } catch (e) {
      print('DEBUG ActiveView: error checking existing barbur alert: $e');
    }
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

    // PopScope — מניעת חזרה בזמן ניווט פעיל או המתנת מאבטח (שכבת הגנה נוספת)
    final isGuardWaiting = _isGuardSecondHalf && !_guardPartnerFinished && _securityActive;
    if ((_personalStatus == NavigatorPersonalStatus.active && _securityActive) || isGuardWaiting) {
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
    // מאבטח second_half — ממתין ל-first_half partner לסיים
    if (_isGuardSecondHalf && !_guardPartnerFinished) {
      return _buildGuardWaitingView();
    }

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
  // מאבטח — מסך המתנה ל-second_half (ה-partner עדיין מנווט)
  // ---------------------------------------------------------------------------

  Widget _buildGuardWaitingView() {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _securityActive) _showUnlockDialog();
      },
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.hourglass_top,
                size: 80,
                color: Colors.orange[300],
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
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange[300]!),
                ),
                child: Column(
                  children: [
                    Icon(Icons.people, color: Colors.orange[700], size: 32),
                    const SizedBox(height: 8),
                    Text(
                      'תמתין שהמנווט הראשון יסיים',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange[800],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'הטלפון נעול. כאשר המנווט הראשון יסיים — תוכל להתחיל את הניווט שלך.',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[700],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              const CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // מצב "פעיל" — סטטוס + גריד + כפתור סיום
  // ---------------------------------------------------------------------------

  Widget _buildActiveView() {
    final hasPtt = _overrideWalkieTalkieEnabled ?? widget.navigation.communicationSettings.walkieTalkieEnabled;
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
            // Safety time banner (shows when < 15 min remain)
            _buildSafetyTimeBanner(),
            // Jamming state banner
            _buildJammingBanner(),
            // GPS accuracy banner
            _buildGpsAccuracyBanner(),
            // Disqualification banner
            if (_isDisqualified)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: Colors.red,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.block, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '${_disqualificationReason ?? 'הניווט נפסל'} — ציון 0',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            // באנר נוהל ברבור
            if (_barburActive && _activeBarburAlert != null)
              _buildBarburBanner(),
            // באנר דקירת מיקום ידני
            if (_allowManualPosition && !_manualPositionUsed && !_manualPinPending &&
                (_jammingState != GpsJammingState.normal ||
                 (_gpsSource != PositionSource.gps &&
                  (_hadGpsFix ||
                   (_startTime != null && DateTime.now().difference(_startTime!).inSeconds > 30)))))
              GestureDetector(
                onTap: () => _checkAndTriggerManualPin(force: true),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: Colors.deepPurple.withValues(alpha: 0.15),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.push_pin, size: 16, color: Colors.deepPurple),
                      SizedBox(width: 8),
                      Text(
                        'לחץ לדקירת מיקום עצמי',
                        style: TextStyle(fontSize: 13, color: Colors.deepPurple, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            if (_manualPositionUsed)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                color: Colors.deepPurple.withValues(alpha: 0.1),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.push_pin, size: 14, color: Colors.deepPurple),
                    SizedBox(width: 6),
                    Text(
                      'מיקום ידני נרשם — יתאפס בחזרת GPS',
                      style: TextStyle(fontSize: 12, color: Colors.deepPurple),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            // 2×2 grid — fixed height, no centering gaps
            SizedBox(
              height: 260,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Column(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildActionCard(
                              title: 'דקירת נ.צ',
                              icon: Icons.location_on,
                              color: Colors.blue,
                              onTap: _punchCheckpoint,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildActionCard(
                              title: 'דיווח תקינות',
                              icon: Icons.check_circle_outline,
                              color: Colors.green,
                              onTap: _reportStatus,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildActionCard(
                              title: 'מצב חירום',
                              icon: Icons.warning_amber,
                              color: Colors.red,
                              onTap: _emergencyAlert,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildActionCard(
                              title: _barburActive ? 'הסתדרתי' : 'ברבור',
                              icon: _barburActive ? Icons.check_circle : Icons.report_problem,
                              color: _barburActive ? Colors.green : Colors.orange,
                              onTap: _barburReport,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // כפתור בקשת הארכה
            _buildExtensionButton(),
            // כפתור סיום ניווט
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
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
            // ווקי טוקי — כפתור PTT בלבד, ממורכז
            if (hasPtt)
              Builder(builder: (context) {
                _voiceService ??= VoiceService();
                return PushToTalkButton(
                  enabled: true,
                  voiceService: _voiceService!,
                  onRecordingComplete: _onPttRecordingComplete,
                  onRecordingCanceled: () {},
                );
              }),
            const SizedBox(height: 8),
          ],
    );
  }

  Widget _buildJammingBanner() {
    if (_gpsTracker.isManualCooldownActive) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: Colors.deepPurple,
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.pin_drop, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text(
              'מיקום ידני — GPS מושהה',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ],
        ),
      );
    }
    if (_jammingState == GpsJammingState.jammed) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: Colors.red,
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text(
              'שיבוש GPS מזוהה — ניווט לפי PDR',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ],
        ),
      );
    }
    if (_jammingState == GpsJammingState.recovering) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: Colors.orange,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.autorenew, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(
              'GPS מתאושש (${_gpsTracker.recoveryProgress}/3)',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
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
    final showCountdown = _route != null && _nav.timeCalculationSettings.enabled;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      color: Theme.of(context).primaryColor.withOpacity(0.1),
      child: Row(
        children: [
          _buildTimerChip(),
          const Spacer(),
          _buildPunchBadge(),
          const SizedBox(width: 8),
          if (showCountdown) ...[
            _buildCountdownChip(),
            const SizedBox(width: 8),
          ],
          _buildGpsChip(),
        ],
      ),
    );
  }

  Widget _buildTimerChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer, size: 16, color: Colors.green[700]),
          const SizedBox(width: 3),
          Text(
            _formatDuration(_elapsed),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.green[700],
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPunchBadge() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$_punchCount',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.grey[700],
          ),
        ),
        const SizedBox(width: 4),
        Icon(Icons.location_on, size: 18, color: Colors.grey[700]),
      ],
    );
  }

  Widget _buildCountdownChip() {
    final missionMinutes = GeometryUtils.getEffectiveTimeMinutes(
      route: _route!,
      settings: _nav.timeCalculationSettings,
      extensionMinutes: _totalApprovedExtensionMinutes,
    );
    final remainingSeconds = (missionMinutes * 60) - _elapsed.inSeconds;
    final isOvertime = remainingSeconds <= 0;
    final abs = remainingSeconds.abs();
    final h = abs ~/ 3600;
    final m = (abs % 3600) ~/ 60;
    final s = abs % 60;
    final timeStr = h > 0
        ? '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
        : '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    final color = isOvertime ? Colors.red : Colors.blue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.flag, size: 16, color: color[700]),
          const SizedBox(width: 3),
          Text(
            isOvertime ? '+$timeStr' : timeStr,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              color: color[700],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSafetyTimeBanner() {
    if (_nav.activeStartTime == null) return const SizedBox.shrink();
    final safetyTime = GeometryUtils.calculateSafetyTime(
      activeStartTime: _nav.activeStartTime!,
      routes: _nav.routes,
      settings: _nav.timeCalculationSettings,
      extensionMinutes: _totalApprovedExtensionMinutes,
    );
    if (safetyTime == null) return const SizedBox.shrink();
    final now = DateTime.now();
    final minutesLeft = safetyTime.difference(now).inMinutes;
    // Show only when less than 15 minutes remain
    if (minutesLeft > 15) return const SizedBox.shrink();
    final isOverdue = now.isAfter(safetyTime);
    final safetyStr = '${safetyTime.hour.toString().padLeft(2, '0')}:${safetyTime.minute.toString().padLeft(2, '0')}';
    final color = isOverdue ? Colors.red : Colors.orange;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shield, size: 16, color: color[700]),
          const SizedBox(width: 6),
          Text(
            isOverdue ? 'חריגה משעת בטיחות ($safetyStr)' : 'שעת בטיחות: $safetyStr',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color[700],
            ),
          ),
        ],
      ),
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
                    '${_disqualificationReason ?? 'פריצת אבטחה'} — ציון 0',
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

    if (_jammingState == GpsJammingState.jammed) {
      icon = Icons.gps_off;
      label = 'שיבוש GPS';
      color = Colors.red;
    } else if (_jammingState == GpsJammingState.recovering) {
      icon = Icons.gps_not_fixed;
      label = 'GPS מתאושש';
      color = Colors.orange;
    } else if (_gpsTracker.isManualCooldownActive) {
      icon = Icons.pin_drop;
      label = 'ידני';
      color = Colors.deepPurple;
    } else if (_gpsBlocked) {
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


  Widget _buildBarburBanner() {
    final checklist = _activeBarburAlert!.barburChecklist ?? {};
    final steps = [
      ('returnToAxis', 'א) חזרה בציר לנקודה מוכרת'),
      ('goToHighPoint', 'ב) עלייה למקום גבוה'),
      ('openMap', 'ג) פתיחת מפה'),
      ('showLocation', 'ד) הצגת מיקום'),
    ];
    final completedCount = checklist.values.where((v) => v).length;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.report_problem, color: Colors.orange, size: 22),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'נוהל ברבור פעיל',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.orange,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$completedCount/4',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...steps.map((step) {
            final done = checklist[step.$1] ?? false;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(
                    done ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: done ? Colors.green : Colors.grey,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      step.$2,
                      style: TextStyle(
                        fontSize: 13,
                        color: done ? Colors.green[800] : Colors.grey[700],
                        decoration: done ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildActionCard({
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.black, width: 1.5),
          ),
          child: LayoutBuilder(builder: (context, constraints) {
            final iconSize = (constraints.maxHeight * 0.4).clamp(24.0, 40.0);
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: iconSize, color: color),
                const SizedBox(height: 6),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  // ===========================================================================
  // Extension Request — בקשת הארכה
  // ===========================================================================

  Future<void> _onPttRecordingComplete(String filePath, double duration) async {
    try {
      final repo = VoiceMessageRepository();
      await repo.sendMessage(
        navigationId: widget.navigation.id,
        filePath: filePath,
        duration: duration,
        senderId: widget.currentUser.uid,
        senderName: widget.currentUser.fullName,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בשליחת הודעה: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _startPttListener() {
    final hasPtt = _overrideWalkieTalkieEnabled ?? widget.navigation.communicationSettings.walkieTalkieEnabled;
    if (!hasPtt) return;
    _pttMessagesSub?.cancel();
    _voiceService ??= VoiceService();
    int pttInitialCount = 0;
    final repo = VoiceMessageRepository();
    _pttMessagesSub = repo
        .watchMessages(widget.navigation.id, currentUserId: widget.currentUser.uid)
        .listen((messages) {
      if (!mounted) return;

      if (_pttInitialLoad) {
        // טעינה ראשונה — סימון כ"נראו" בלי השמעה
        _seenPttMessageIds.addAll(messages.map((m) => m.id));
        pttInitialCount = messages.length;
        _pttInitialLoad = false;
      } else {
        // הודעות חדשות מאחרים — הכנסה לתור השמעה (מהישנה לחדשה)
        for (final msg in messages.reversed) {
          if (!_seenPttMessageIds.contains(msg.id) &&
              msg.senderId != widget.currentUser.uid) {
            _voiceService!.enqueueMessage(msg.audioUrl, msg.id);
          }
          _seenPttMessageIds.add(msg.id);
        }
      }

      final newUnread = (messages.length - pttInitialCount).clamp(0, 999);
      if (newUnread != _pttUnreadCount) {
        setState(() => _pttUnreadCount = newUnread);
      }
    });
  }

  void _startExtensionListener() {
    if (!_nav.timeCalculationSettings.allowExtensionRequests) return;
    _extensionListener?.cancel();
    _extensionListener = _extensionRepo
        .watchByNavigator(_nav.id, widget.currentUser.uid)
        .listen((requests) {
      if (!mounted) return;
      int totalApproved = 0;
      ExtensionRequest? active;
      for (final req in requests) {
        if (req.status == ExtensionRequestStatus.approved) {
          totalApproved += req.approvedMinutes ?? 0;
        }
        // הבקשה האחרונה (לפי createdAt — descending)
        if (active == null) active = req;
      }

      // זיהוי מעבר מ-pending ל-approved/rejected — הצגת התראה למנווט
      final prev = _activeExtensionRequest;
      if (prev != null &&
          active != null &&
          prev.id == active.id &&
          prev.status == ExtensionRequestStatus.pending &&
          active.status != ExtensionRequestStatus.pending) {
        _showExtensionResponseNotification(active);
      }

      setState(() {
        _activeExtensionRequest = active;
        _totalApprovedExtensionMinutes = totalApproved;
      });
    }, onError: (e) {
      print('[ExtensionListener] שגיאה: $e');
    });
  }

  /// התראה למנווט כשהמפקד מגיב לבקשת הארכה
  void _showExtensionResponseNotification(ExtensionRequest req) {
    if (!mounted) return;
    final isApproved = req.status == ExtensionRequestStatus.approved;
    final minutes = req.approvedMinutes ?? req.requestedMinutes;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          isApproved ? Icons.check_circle : Icons.cancel,
          color: isApproved ? Colors.green : Colors.red,
          size: 48,
        ),
        title: Text(
          isApproved ? 'בקשת הארכה אושרה' : 'בקשת הארכה נדחתה',
          style: TextStyle(
            color: isApproved ? Colors.green : Colors.red,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          isApproved
              ? 'אושרו $minutes דקות הארכה.\nהזמן התווסף אוטומטית.'
              : 'המפקד דחה את בקשת ההארכה.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isApproved ? Colors.green : Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('הבנתי'),
            ),
          ),
        ],
      ),
    );
  }

  /// האם חלון הבקשה פתוח (כל הניווט, או בטווח זמן מוגדר)
  bool _isExtensionWindowOpen() {
    final settings = _nav.timeCalculationSettings;
    if (!settings.allowExtensionRequests) return false;
    if (settings.extensionWindowType == 'all') return true;

    // timed — חלון מוגדר לפני סיום הניווט
    if (_route == null || _nav.activeStartTime == null) return false;
    final windowMinutes = settings.extensionWindowMinutes ?? 0;
    if (windowMinutes <= 0) return false;

    final missionMinutes = GeometryUtils.getEffectiveTimeMinutes(
      route: _route!,
      settings: settings,
      extensionMinutes: _totalApprovedExtensionMinutes,
    );
    final expectedEnd = _nav.activeStartTime!.add(Duration(minutes: missionMinutes));
    final windowStart = expectedEnd.subtract(Duration(minutes: windowMinutes));
    return DateTime.now().isAfter(windowStart);
  }

  /// האם ניתן לשלוח בקשה חדשה
  bool _canRequestExtension() {
    if (!_isExtensionWindowOpen()) return false;
    final req = _activeExtensionRequest;
    if (req == null) return true;
    if (req.status == ExtensionRequestStatus.pending) return false;
    // אחרי אישור — אפשר לבקש שוב אחרי 10 דקות
    if (req.status == ExtensionRequestStatus.approved && req.respondedAt != null) {
      return DateTime.now().difference(req.respondedAt!).inMinutes >= 10;
    }
    // אחרי דחייה — אפשר לבקש שוב אחרי 10 דקות
    if (req.status == ExtensionRequestStatus.rejected && req.respondedAt != null) {
      return DateTime.now().difference(req.respondedAt!).inMinutes >= 10;
    }
    return true;
  }

  Widget _buildExtensionButton() {
    final settings = _nav.timeCalculationSettings;
    if (!settings.allowExtensionRequests || !settings.enabled) {
      return const SizedBox.shrink();
    }

    final req = _activeExtensionRequest;

    Color bgColor;
    String label;
    bool enabled;
    IconData icon = Icons.timer;

    if (req != null && req.status == ExtensionRequestStatus.pending) {
      bgColor = Colors.amber;
      label = 'ממתין לתשובת מפקד';
      enabled = false;
      icon = Icons.hourglass_top;
    } else if (req != null &&
        req.status == ExtensionRequestStatus.approved &&
        req.respondedAt != null &&
        DateTime.now().difference(req.respondedAt!).inMinutes < 10) {
      bgColor = Colors.green;
      label = 'הארכה מאושרת — ${req.approvedMinutes ?? 0} דק\'';
      enabled = false;
      icon = Icons.check_circle;
    } else if (req != null &&
        req.status == ExtensionRequestStatus.rejected &&
        req.respondedAt != null &&
        DateTime.now().difference(req.respondedAt!).inMinutes < 10) {
      bgColor = Colors.red;
      label = 'הבקשה נדחתה';
      enabled = false;
      icon = Icons.cancel;
    } else if (_canRequestExtension()) {
      bgColor = Colors.purple;
      label = 'בקשת הארכה';
      enabled = true;
    } else {
      // חלון לא פתוח
      bgColor = Colors.grey;
      label = 'בקשת הארכה';
      enabled = false;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton.icon(
          onPressed: enabled ? _showExtensionRequestDialog : null,
          icon: Icon(icon),
          label: Text(
            label,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: bgColor,
            foregroundColor: Colors.white,
            disabledBackgroundColor: bgColor.withOpacity(0.5),
            disabledForegroundColor: Colors.white70,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }

  void _showExtensionRequestDialog() {
    int selectedMinutes = 30;
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.timer, color: Colors.purple),
                SizedBox(width: 8),
                Text('בקשת הארכה'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('כמה דקות הארכה לבקש?'),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: selectedMinutes > 5
                          ? () => setDialogState(() => selectedMinutes -= 5)
                          : null,
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.purple.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$selectedMinutes דק\'',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.purple,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: selectedMinutes < 120
                          ? () => setDialogState(() => selectedMinutes += 5)
                          : null,
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Slider(
                  value: selectedMinutes.toDouble(),
                  min: 5,
                  max: 120,
                  divisions: 23,
                  label: '$selectedMinutes דק\'',
                  activeColor: Colors.purple,
                  onChanged: (v) => setDialogState(() => selectedMinutes = v.round()),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('ביטול'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _submitExtensionRequest(selectedMinutes);
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
                child: const Text('שלח בקשה', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        });
      },
    );
  }

  Future<void> _submitExtensionRequest(int minutes) async {
    try {
      final request = ExtensionRequest(
        id: '',
        navigationId: _nav.id,
        navigatorId: widget.currentUser.uid,
        navigatorName: widget.currentUser.fullName,
        requestedMinutes: minutes,
        createdAt: DateTime.now(),
      );
      final created = await _extensionRepo.create(request);
      // עדכון מקומי מיידי — כדי שהכפתור ישתנה מיד לצהוב
      if (mounted) {
        setState(() => _activeExtensionRequest = created);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('בקשת הארכה נשלחה למפקד'),
            backgroundColor: Colors.purple,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בשליחת בקשה: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
