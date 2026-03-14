import 'dart:async';
import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import '../../../domain/entities/navigation.dart' as domain;
import '../../../domain/entities/checkpoint.dart';
import '../../../domain/entities/checkpoint_punch.dart';
import '../../../domain/entities/navigation_settings.dart';
import '../../../domain/entities/coordinate.dart';
import '../../../domain/entities/nav_layer.dart';
import '../../../domain/entities/navigator_personal_status.dart';
import '../../../domain/entities/navigation_doc_snapshot.dart';
import '../../../domain/entities/navigator_status.dart';
import '../../../domain/entities/commander_location.dart';
import '../../../data/repositories/checkpoint_repository.dart';
import '../../../data/repositories/checkpoint_punch_repository.dart';
import '../../../data/repositories/nav_layer_repository.dart';
import '../../../data/repositories/navigation_repository.dart';
import '../../../data/repositories/navigation_track_repository.dart';
import '../../../data/repositories/navigator_alert_repository.dart';
import '../../../data/repositories/system_status_repository.dart';
import '../../../data/repositories/commander_status_repository.dart';
import '../../../data/repositories/emergency_broadcast_repository.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/sync/sync_manager.dart';
import '../../../core/constants/hospitals_data.dart';
import '../../../core/utils/geometry_utils.dart';
import '../../../core/utils/utm_converter.dart';
import '../../../services/gps_service.dart';
import '../../../services/gps_tracking_service.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/repositories/navigation_tree_repository.dart';
import '../../../domain/entities/navigation_tree.dart' as tree_domain;
import '../../../services/auth_service.dart';
import '../../../domain/entities/user.dart' as app_user;
import '../../../services/voice_service.dart';
import '../../widgets/voice_messages_panel.dart';
import '../../widgets/map_with_selector.dart';
import '../../../data/repositories/extension_request_repository.dart';
import '../../../domain/entities/extension_request.dart';
import '../../widgets/map_controls.dart';
import '../../../core/map_config.dart';
import '../../widgets/fullscreen_map_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../services/alert_sound_service.dart';
import '../../widgets/alert_volume_control.dart';
import '../../../core/utils/permission_utils.dart';

/// מצב הצגת נקודות ציון
enum _NzDisplayMode { selectedNavigators, participatingOnly, allCheckpoints }

/// מסך ניהול ניווט פעיל (למפקד)
class NavigationManagementScreen extends StatefulWidget {
  final domain.Navigation navigation;

  const NavigationManagementScreen({
    super.key,
    required this.navigation,
  });

  @override
  State<NavigationManagementScreen> createState() => _NavigationManagementScreenState();
}

class _NavigationManagementScreenState extends State<NavigationManagementScreen>
    with SingleTickerProviderStateMixin {
  final CheckpointRepository _checkpointRepo = CheckpointRepository();
  final NavLayerRepository _navLayerRepo = NavLayerRepository();
  final NavigationRepository _navRepo = NavigationRepository();
  final NavigationTrackRepository _trackRepo = NavigationTrackRepository();
  final NavigatorAlertRepository _alertRepo = NavigatorAlertRepository();
  final CheckpointPunchRepository _punchRepo = CheckpointPunchRepository();
  final MapController _mapController = MapController();

  late TabController _tabController;
  Timer? _refreshTimer;
  Timer? _stalenessTimer;
  StreamSubscription<List<Map<String, dynamic>>>? _tracksListener;
  StreamSubscription<Map<String, NavigatorStatus>>? _systemStatusListener;
  StreamSubscription<List<NavigatorAlert>>? _alertsListener;
  StreamSubscription<List<CheckpointPunch>>? _punchesListener;
  StreamSubscription<NavigationDocSnapshot>? _emergencyFlagListener;

  // מצב חירום
  bool _emergencyActive = false;
  bool _isJumpDialogOpen = false;
  int _emergencyMode = 0;
  String? _activeBroadcastId;
  StreamSubscription<Map<String, dynamic>?>? _ackListener;
  List<String> _acknowledgedBy = [];
  Timer? _autoRetryTimer;
  // ביטול
  String? _cancelBroadcastId;
  StreamSubscription<Map<String, dynamic>?>? _cancelAckListener;
  List<String> _cancelAcknowledgedBy = [];
  Timer? _cancelAutoRetryTimer;
  // שידור חירום — דיאלוג למפקדים אחרים
  bool _commanderEmergencyDialogShowing = false;
  bool _commanderRoutineDialogShowing = false;
  bool _wasInCommanderEmergency = false;
  String? _lastShownCommanderBroadcastId;
  AudioPlayer? _commanderEmergencyPlayer;
  Timer? _commanderVibrationTimer;
  bool _iSentEmergencyBroadcast = false;
  bool _iSentCancelBroadcast = false;

  List<Checkpoint> _checkpoints = [];
  List<NavBoundary> _boundaries = [];
  StreamSubscription? _syncListener;
  bool _isLoading = false;
  bool _alreadyClosed = false;

  // התראות בזמן אמת
  List<NavigatorAlert> _activeAlerts = [];
  bool _showAlerts = true;

  // מנווטים נבחרים לתצוגה
  Map<String, bool> _selectedNavigators = {};

  // מיקומים בזמן אמת
  Map<String, NavigatorLiveData> _navigatorData = {};

  // שכבות
  bool _showNZ = true;
  _NzDisplayMode _nzMode = _NzDisplayMode.participatingOnly;
  bool _showGG = true;
  bool _showTracks = true;
  bool _showPunches = true;

  double _nzOpacity = 1.0;
  double _ggOpacity = 0.5;
  double _tracksOpacity = 1.0;
  double _punchesOpacity = 1.0;
  bool _measureMode = false;
  final List<LatLng> _measurePoints = [];

  // פר-מנווט: הצגת מסלול בפועל / ציר מתוכנן
  final Map<String, bool> _showNavigatorTrack = {};
  final Map<String, bool> _showPlannedAxis = {};
  // דריסות התראות פר-מנווט: navigatorId -> { AlertType -> enabled }
  final Map<String, Map<AlertType, bool>> _navigatorAlertOverrides = {};
  // דריסות הגדרות מפה פר-מנווט
  final Map<String, bool> _navigatorOverrideAllowOpenMap = {};
  final Map<String, bool> _navigatorOverrideShowSelfLocation = {};
  final Map<String, bool> _navigatorOverrideShowRouteOnMap = {};
  final Map<String, String> _navigatorTrackIds = {}; // cache trackId per navigator
  final Map<String, bool> _navigatorOverrideWalkieTalkieEnabled = {};
  Map<String, bool?> _navigatorOverrideRevealEnabled = {};
  final Map<String, int?> _navigatorGpsIntervalOverride = {};
  final Map<String, int?> _navigatorGpsSyncIntervalOverride = {};
  final Map<String, List<String>?> _navigatorPositionSourcesOverride = {};

  static const Map<int, String> _gpsSyncIntervalLabels = {
    5: '5 שניות',
    15: '15 שניות',
    30: '30 שניות',
    60: 'דקה',
    120: '2 דקות',
    300: '5 דקות',
    600: '10 דקות',
    1800: '30 דקות',
    3600: 'שעה',
    7200: 'שעתיים',
  };
  // דריסות עוצמות צליל פר-מנווט: navigatorId -> { alertTypeCode -> volume }
  final Map<String, Map<String, double>> _navigatorAlertSoundVolumes = {};

  // Voice (PTT)
  VoiceService? _voiceService;

  // בקשות הארכה
  final ExtensionRequestRepository _extensionRepo = ExtensionRequestRepository();
  StreamSubscription<List<ExtensionRequest>>? _extensionListener;
  List<ExtensionRequest> _extensionRequests = [];
  final Set<String> _shownExtensionPopups = {}; // מניעת popup כפול
  Timer? _extensionSnoozeTimer;

  // שעת בטיחות
  Timer? _safetyTimer;
  bool _safetyWarningShown = false;
  bool _safetyAlertShown = false;

  // מרכוז מפה
  CenteringMode _centeringMode = CenteringMode.off;
  String? _centeredNavigatorId; // null = מרכוז עצמי
  Timer? _centeringTimer;
  StreamSubscription? _mapGestureSubscription;

  // הדגשה חד-פעמית (מרכז פעם אחת)
  String? _oneTimeCenteredNavigatorId;

  // תפריט טקטי (overlay)
  OverlayEntry? _tacticalMenuEntry;
  String? _openTacticalNavigatorId;
  StreamSubscription? _oneTimeGestureSubscription;

  // שמות משתמשים (מנווטים + מפקדים)
  Map<String, String> _userNames = {};
  app_user.User? _currentUser;

  // עץ ניווט — לקיבוץ מנווטים לפי תת-מסגרת
  tree_domain.NavigationTree? _navigationTree;
  // מצב פתוח/נעול של קבוצות בטאב סטטוס
  final Map<String, bool> _navigatorGroupExpanded = {};
  final Map<String, bool> _navigatorGroupLocked = {};

  // ניווט נוכחי (mutable — מתעדכן אחרי כל שמירה)
  late domain.Navigation _currentNavigation;

  // מיקום עצמי של המפקד
  LatLng? _selfPosition;
  Timer? _selfGpsTimer;

  // מפקדים אחרים
  Map<String, CommanderLocation> _otherCommanders = {};
  Timer? _commanderPublishTimer;
  StreamSubscription? _commanderStatusListener;

  @override
  void initState() {
    super.initState();
    _currentNavigation = widget.navigation;
    _tabController = TabController(length: 4, vsync: this);
    _loadData();
    _initializeNavigators();
    _startTrackListener();
    _startSystemStatusListener();
    _startAlertsListener();
    _startPunchesListener();
    _startExtensionRequestListener();
    _startEmergencyFlagListener();
    _initCommanderEmergencyAlarm();
    _startSafetyTimeMonitor();
    _startSyncListener();
    // רענון תקופתי כל 15 שניות
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _refreshNavigatorStatuses();
    });
    // רענון מראה סמנים כל 30 שניות — מעבר ירוק→אפור→נעלם
    _stalenessTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        // סגירת תפריט טקטי אם מנווט נעלם מהנתונים
        if (_tacticalMenuEntry != null && _openTacticalNavigatorId != null &&
            !_navigatorData.containsKey(_openTacticalNavigatorId!)) {
          _removeTacticalMenu();
        }
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _stalenessTimer?.cancel();
    _tracksListener?.cancel();
    _systemStatusListener?.cancel();
    _alertsListener?.cancel();
    _punchesListener?.cancel();
    _centeringTimer?.cancel();
    _mapGestureSubscription?.cancel();
    _oneTimeGestureSubscription?.cancel();
    _selfGpsTimer?.cancel();
    _commanderPublishTimer?.cancel();
    _commanderStatusListener?.cancel();
    _extensionListener?.cancel();
    _extensionSnoozeTimer?.cancel();
    _safetyTimer?.cancel();
    _emergencyFlagListener?.cancel();
    _ackListener?.cancel();
    _autoRetryTimer?.cancel();
    _cancelAckListener?.cancel();
    _cancelAutoRetryTimer?.cancel();
    _commanderVibrationTimer?.cancel();
    _commanderEmergencyPlayer?.dispose();
    _syncListener?.cancel();
    _removeTacticalMenu();
    _tabController.dispose();
    _voiceService?.dispose();
    super.dispose();
  }

  void _startSyncListener() {
    _syncListener = SyncManager().onDataChanged.listen((collection) {
      if (collection == AppConstants.navigationsCollection && mounted) {
        _reloadLayers();
      }
    });
  }

  Future<void> _reloadLayers() async {
    try {
      final boundaries = await _navLayerRepo.getBoundariesByNavigation(
        _currentNavigation.id,
      );
      if (mounted) {
        setState(() => _boundaries = boundaries);
      }
    } catch (_) {}
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // רענון layers ל-Firestore — מבטיח שנתונים מקומיים לא נדרסים ע"י sync עם layers ריקים
      await _navLayerRepo.refreshNavigationLayers(widget.navigation.id);

      final checkpoints = await _checkpointRepo.getByArea(widget.navigation.areaId);

      final boundaries = await _navLayerRepo.getBoundariesByNavigation(widget.navigation.id);

      setState(() {
        _checkpoints = checkpoints;
        _boundaries = boundaries;
        _isLoading = false;
      });

      if (boundaries.isNotEmpty) {
        final points = boundaries.expand((b) => b.allCoordinates).map((c) => LatLng(c.lat, c.lng)).toList();
        if (points.isNotEmpty) {
          _mapController.fitCamera(CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(points),
            padding: const EdgeInsets.all(30),
          ));
        }
      }

    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _initializeNavigators() async {
    // אתחול ראשוני
    final alerts = widget.navigation.alerts;
    for (final navigatorId in widget.navigation.routes.keys) {
      _selectedNavigators[navigatorId] = true;
      _navigatorData[navigatorId] = NavigatorLiveData(
        navigatorId: navigatorId,
        personalStatus: NavigatorPersonalStatus.waiting,
        hasActiveAlert: false,
        currentPosition: null,
        trackPoints: [],
        punches: [],
        lastUpdate: null,
      );
      _showNavigatorTrack[navigatorId] = false;
      _showPlannedAxis[navigatorId] = false;
      // ברירת מחדל מהגדרות הניווט — המפקד יכול לשנות פר-מנווט
      _navigatorOverrideAllowOpenMap[navigatorId] = widget.navigation.allowOpenMap;
      _navigatorOverrideShowSelfLocation[navigatorId] = widget.navigation.showSelfLocation;
      _navigatorOverrideShowRouteOnMap[navigatorId] = widget.navigation.showRouteOnMap;
      _navigatorOverrideWalkieTalkieEnabled[navigatorId] = widget.navigation.communicationSettings.walkieTalkieEnabled;
      _navigatorGpsIntervalOverride[navigatorId] = null; // null = שימוש בברירת מחדל של הניווט
      _navigatorGpsSyncIntervalOverride[navigatorId] = null; // null = שימוש בברירת מחדל של הניווט
      _navigatorPositionSourcesOverride[navigatorId] = null; // null = שימוש בברירת מחדל של הניווט

      // ברירת מחדל טוגלי התראות — כל הסוגים, ברירת מחדל מהגדרות הניווט
      _navigatorAlertOverrides[navigatorId] = {
        AlertType.speed: alerts.speedAlertEnabled,
        AlertType.noMovement: alerts.noMovementAlertEnabled,
        AlertType.boundary: alerts.ggAlertEnabled,
        AlertType.routeDeviation: alerts.routesAlertEnabled,
        AlertType.safetyPoint: alerts.nbAlertEnabled,
        AlertType.proximity: alerts.navigatorProximityAlertEnabled,
        AlertType.battery: alerts.batteryAlertEnabled,
        AlertType.noReception: alerts.noReceptionAlertEnabled,
        AlertType.healthCheckExpired: alerts.healthCheckEnabled,
      };
    }

    // טעינת סטטוסים מה-DB
    await _refreshNavigatorStatuses();

    // טעינת משתמש נוכחי (מפקד)
    _currentUser = await AuthService().getCurrentUser();

    // טעינת שמות מנווטים
    final userRepo = UserRepository();
    for (final navigatorId in widget.navigation.routes.keys) {
      final user = await userRepo.getUser(navigatorId);
      if (user != null) {
        _userNames[navigatorId] = user.fullName.isNotEmpty ? user.fullName : navigatorId;
      }
    }

    // טעינת עץ ניווט לקיבוץ מנווטים לפי תת-מסגרת
    try {
      final treeRepo = NavigationTreeRepository();
      _navigationTree = await treeRepo.getById(widget.navigation.treeId);
    } catch (_) {}

    // טעינת מפקדים — דינמי לפי תפקיד ויחידה
    final commanderUnitId = widget.navigation.selectedUnitId;
    if (commanderUnitId != null) {
      final commanders = await userRepo.getCommandersForUnit(commanderUnitId);
      for (final commander in commanders) {
        if (commander.uid != _currentUser?.uid) {
          _userNames[commander.uid] = commander.fullName.isNotEmpty
              ? commander.fullName
              : commander.uid;
        }
      }
    }

    // מעקב GPS עצמי (כל 10 שניות)
    final initialPos = await GpsService().getCurrentPosition();
    if (initialPos != null && mounted) setState(() => _selfPosition = initialPos);
    _selfGpsTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      final pos = await GpsService().getCurrentPosition();
      if (pos != null && mounted) setState(() => _selfPosition = pos);
    });

    // פרסום מיקום עצמי (כל 15 שניות)
    _commanderPublishTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _publishCommanderLocation(),
    );

    // האזנה למיקומי מפקדים אחרים
    _commanderStatusListener = CommanderStatusRepository()
        .watchCommanderLocations(widget.navigation.id)
        .listen((locations) => _updateCommanderLocations(locations));

    if (mounted) setState(() {});
  }

  Future<void> _refreshNavigatorStatuses() async {
    try {
      final tracks = await _trackRepo.getByNavigation(widget.navigation.id);
      final activeAlerts = await _alertRepo.getActiveByNavigation(widget.navigation.id);
      final punches = await _punchRepo.getByNavigation(widget.navigation.id);

      // מפה של navigatorId → track
      final trackMap = <String, dynamic>{};
      for (final track in tracks) {
        trackMap[track.navigatorUserId] = track;
      }

      // set של מנווטים עם התראות פעילות
      final alertedNavigators = <String>{};
      for (final alert in activeAlerts) {
        alertedNavigators.add(alert.navigatorId);
      }

      // מפה של navigatorId → punches (מקומי)
      final punchMap = <String, List<CheckpointPunch>>{};
      for (final punch in punches) {
        punchMap.putIfAbsent(punch.navigatorId, () => []).add(punch);
      }

      // timeout — מנווט שהיה active נשאר active עד 5× מרווח GPS
      final timeout = Duration(
        seconds: widget.navigation.gpsUpdateIntervalSeconds * 5,
      );

      if (mounted) {
        setState(() {
          for (final navigatorId in _navigatorData.keys) {
            final track = trackMap[navigatorId];
            final hasAlert = alertedNavigators.contains(navigatorId);
            final data = _navigatorData[navigatorId]!;

            // מנווט שסיים — לא לדרוס סטטוס finished
            if (data.personalStatus == NavigatorPersonalStatus.finished) {
              data.hasActiveAlert = hasAlert;
              // עדכון דקירות + isDisqualified בלבד
              final localPunches = punchMap[navigatorId] ?? [];
              if (localPunches.isNotEmpty) {
                data.punches = localPunches;
              }
              // קריאת isDisqualified מ-track מקומי (אם קיים)
              final finishedTrack = trackMap[navigatorId];
              if (finishedTrack != null) {
                data.isDisqualified = finishedTrack.isDisqualified;
              }
              continue;
            }

            NavigatorPersonalStatus status;
            List<TrackPoint> points = [];

            if (track == null) {
              // אין track מקומי — בדוק אם Firestore listener כבר סימן active
              if ((data.personalStatus == NavigatorPersonalStatus.active ||
                   data.personalStatus == NavigatorPersonalStatus.noReception) &&
                  data.lastUpdate != null) {
                if (data.timeSinceLastUpdate < timeout) {
                  // שמור סטטוס active + נקודות Firestore — לא לדרוס
                  status = NavigatorPersonalStatus.active;
                } else {
                  // timeout — מנווט לא דיווח מעל הזמן שהוגדר
                  status = NavigatorPersonalStatus.noReception;
                }
                points = data.trackPoints;
              } else {
                status = NavigatorPersonalStatus.waiting;
              }
            } else {
              status = NavigatorPersonalStatus.deriveFromTrack(
                hasTrack: true,
                isActive: track.isActive,
                endedAt: track.endedAt,
              );

              // פרסור נקודות מסלול מ-JSON
              try {
                final pointsList = jsonDecode(track.trackPointsJson) as List;
                points = pointsList
                    .map((p) => TrackPoint.fromMap(p as Map<String, dynamic>))
                    .toList();
              } catch (_) {}

              // timeout — מנווט פעיל שלא דיווח מעל הזמן שהוגדר
              if (status == NavigatorPersonalStatus.active && points.isNotEmpty) {
                final lastPointTime = points.last.timestamp;
                if (DateTime.now().difference(lastPointTime) > timeout) {
                  status = NavigatorPersonalStatus.noReception;
                }
              }
            }

            data.personalStatus = status;
            data.hasActiveAlert = hasAlert;

            // זמני התחלה/סיום מה-track המקומי (לפני שה-Firestore listener מעדכן)
            if (track != null) {
              data.trackStartedAt = track.startedAt;
              data.trackEndedAt = track.endedAt;
            }

            // עדכון נקודות רק אם יש נתונים חדשים (לא לדרוס Firestore data בריק)
            if (points.isNotEmpty) {
              data.trackPoints = points;
              final last = points.last;
              data.currentPosition = LatLng(last.coordinate.lat, last.coordinate.lng);
              data.lastUpdate = last.timestamp;
              data.isGpsPlusFix = last.positionSource == 'cellTower';
            }

            // עדכון דקירות רק אם יש נתונים מקומיים (לא לדרוס Firestore data בריק)
            final localPunches = punchMap[navigatorId] ?? [];
            if (localPunches.isNotEmpty) {
              data.punches = localPunches;
            }
          }
        });
      }
    } catch (e) {
      // שגיאה ברענון — ממשיכים עם הנתונים הקיימים
    }
  }

  // ===========================================================================
  // מפקדים — פרסום מיקום עצמי + האזנה למפקדים אחרים
  // ===========================================================================

  Future<void> _publishCommanderLocation() async {
    if (_selfPosition == null || _currentUser == null) return;
    CommanderStatusRepository().publishLocation(
      widget.navigation.id,
      _currentUser!.uid,
      {
        'userId': _currentUser!.uid,
        'name': _currentUser!.fullName,
        'latitude': _selfPosition!.latitude,
        'longitude': _selfPosition!.longitude,
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );
  }

  void _updateCommanderLocations(Map<String, CommanderLocation> locations) {
    if (!mounted) return;
    final updated = <String, CommanderLocation>{};
    for (final entry in locations.entries) {
      final uid = entry.key;
      if (uid == _currentUser?.uid) continue;
      final loc = entry.value;
      // עדכון שם מ-cache מקומי אם חסר
      if (loc.name.isEmpty) {
        updated[uid] = CommanderLocation(
          userId: uid,
          name: _userNames[uid] ?? uid,
          position: loc.position,
          lastUpdate: loc.lastUpdate,
        );
      } else {
        updated[uid] = loc;
      }
    }
    setState(() => _otherCommanders = updated);
  }

  // ===========================================================================
  // Firestore Listener — נתונים בזמן אמת ממכשירי מנווטים
  // ===========================================================================

  void _startTrackListener() {
    _tracksListener = _trackRepo
        .watchTracksByNavigation(widget.navigation.id)
        .listen(
      (tracks) {
        _updateNavigatorDataFromFirestore(tracks);
      },
      onError: (e) {
        print('DEBUG NavigationManagement: track listener error: $e');
      },
    );
  }

  // ===========================================================================
  // Firestore Listener — system_status fallback (מיקום מנווטים בבדיקת מערכות)
  // ===========================================================================

  void _startSystemStatusListener() {
    _systemStatusListener = SystemStatusRepository()
        .watchStatuses(widget.navigation.id)
        .listen(
      (statuses) {
        _updateNavigatorDataFromSystemStatus(statuses);
      },
      onError: (e) {
        print('DEBUG NavigationManagement: system_status listener error: $e');
      },
    );
  }

  void _updateNavigatorDataFromSystemStatus(Map<String, NavigatorStatus> statuses) {
    if (!mounted) return;

    setState(() {
      for (final entry in statuses.entries) {
        final navigatorId = entry.key;
        final status = entry.value;

        // אם מנווט חדש שלא ברשימה (מקרה קצה)
        if (!_navigatorData.containsKey(navigatorId)) {
          _selectedNavigators[navigatorId] = true;
          _navigatorData[navigatorId] = NavigatorLiveData(
            navigatorId: navigatorId,
            personalStatus: NavigatorPersonalStatus.waiting,
            trackPoints: [],
            punches: [],
          );
        }

        final liveData = _navigatorData[navigatorId]!;

        // עדכון מצב סוללה
        if (status.batteryLevel >= 0) {
          liveData.batteryLevel = status.batteryLevel;
        }

        // עדכון הרשאות מיקרופון, טלפון ו-DND
        liveData.hasMicrophonePermission = status.hasMicrophonePermission;
        liveData.hasPhonePermission = status.hasPhonePermission;
        liveData.hasDNDPermission = status.hasDNDPermission;

        final latitude = status.latitude;
        final longitude = status.longitude;

        // עדכון מיקום — רק אם יש מיקום תקין
        if (latitude == null || longitude == null) continue;
        if (latitude == 0.0 && longitude == 0.0) continue;

        // עדכון מיקום מ-system_status — רק אם אין נתונים או ה-timestamp חדש יותר
        final statusTime = status.positionUpdatedAt;

        final shouldUpdate = liveData.currentPosition == null ||
            (statusTime != null &&
             (liveData.lastUpdate == null || statusTime.isAfter(liveData.lastUpdate!)));

        if (shouldUpdate) {
          liveData.currentPosition = LatLng(latitude, longitude);
          if (statusTime != null) {
            liveData.lastUpdate = statusTime;
          }
        }
      }
    });
  }

  // ===========================================================================
  // Firestore Listener — התראות בזמן אמת
  // ===========================================================================

  void _startAlertsListener() {
    _alertsListener = _alertRepo
        .watchActiveAlerts(widget.navigation.id)
        .listen(
      (alerts) {
        if (!mounted) return;
        // זיהוי התראות חדשות לפני עדכון הרשימה
        final oldIds = _activeAlerts.map((a) => a.id).toSet();
        final newAlerts = alerts.where((a) => !oldIds.contains(a.id)).toList();

        setState(() {
          _activeAlerts = alerts;
          // עדכון hasActiveAlert בנתוני מנווטים
          final alertedNavigators = <String>{};
          for (final alert in alerts) {
            alertedNavigators.add(alert.navigatorId);
          }
          for (final entry in _navigatorData.entries) {
            entry.value.hasActiveAlert = alertedNavigators.contains(entry.key);
          }
        });
        // ויברציה + צליל כשמגיעה התראה חדשה
        if (newAlerts.isNotEmpty) {
          HapticFeedback.heavyImpact();
          final alertsWithVolumes = newAlerts.map((a) =>
            MapEntry(a.type, _resolveAlertVolume(a.navigatorId, a.type.code))
          ).toList();
          AlertSoundService().playAlerts(alertsWithVolumes);
        }
        // חלון קופץ להתראות חירום, תקינות, וברבור חדשות
        for (final alert in newAlerts) {
          if (alert.type == AlertType.emergency ||
              alert.type == AlertType.healthCheckExpired) {
            _showAlertDialog(alert);
          } else if (alert.type == AlertType.barbur) {
            _showBarburProtocolDialog(alert);
          }
        }
      },
      onError: (e) {
        print('DEBUG NavigationManagement: alerts listener error: $e');
      },
    );
  }

  void _startPunchesListener() {
    _punchesListener = _punchRepo
        .watchPunches(widget.navigation.id)
        .listen(
      (punches) {
        if (!mounted) return;
        setState(() {
          // מפה של navigatorId → punches
          final punchMap = <String, List<CheckpointPunch>>{};
          for (final punch in punches) {
            punchMap.putIfAbsent(punch.navigatorId, () => []).add(punch);
          }
          for (final entry in _navigatorData.entries) {
            entry.value.punches = punchMap[entry.key] ?? [];
          }
        });
      },
      onError: (e) {
        print('DEBUG NavigationManagement: punches listener error: $e');
      },
    );
  }

  Future<void> _resolveAlert(NavigatorAlert alert) async {
    try {
      await _alertRepo.resolve(
        alert.navigationId,
        alert.id,
        'commander',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בסגירת התראה: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ===========================================================================
  // Alert Popup Dialog — חלון קופץ להתראות חירום ותקינות
  // ===========================================================================

  void _showAlertDialog(NavigatorAlert alert) {
    final isEmergency = alert.type == AlertType.emergency;
    final title = isEmergency ? 'התראת חירום!' : 'התראת תקינות';
    final icon = isEmergency ? Icons.emergency : Icons.timer_off;
    final color = isEmergency ? Colors.red : Colors.orange;

    String message;
    if (isEmergency) {
      message = 'מנווט ${alert.navigatorName ?? alert.navigatorId} שלח התראת חירום!';
    } else {
      final overdue = alert.minutesOverdue ?? 0;
      message = 'מנווט ${alert.navigatorName ?? alert.navigatorId} לא דיווח תקינות.\nחלפו $overdue דקות מעבר לזמן שהוגדר.';
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 8),
            Text(title, style: TextStyle(color: color)),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              // מרכז מפה על מיקום המנווט
              if (alert.location.lat != 0 && alert.location.lng != 0) {
                _tabController.animateTo(0); // טאב מפה
                try {
                  _mapController.move(
                    LatLng(alert.location.lat, alert.location.lng),
                    15.0,
                  );
                } catch (_) {}
              }
            },
            icon: const Icon(Icons.map),
            label: const Text('מיקום המנווט'),
          ),
          TextButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              // הזכר שוב עוד 5 דקות
              Future.delayed(const Duration(minutes: 5), () {
                if (mounted) {
                  if (_activeAlerts.any((a) => a.id == alert.id)) {
                    _showAlertDialog(alert);
                  }
                }
              });
            },
            icon: const Icon(Icons.snooze),
            label: const Text('הזכר עוד 5 דק\''),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              await _resolveAlert(alert);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('ההתראה טופלה'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            icon: const Icon(Icons.check_circle),
            label: const Text('בדקתי, תקין'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // Barbur Protocol Dialog — נוהל ברבור
  // ===========================================================================

  void _showBarburProtocolDialog(NavigatorAlert alert) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StreamBuilder<NavigatorAlert?>(
          stream: _alertRepo.watchAlert(alert.navigationId, alert.id),
          initialData: alert,
          builder: (ctx, snapshot) {
            final liveAlert = snapshot.data;
            if (liveAlert == null || !liveAlert.isActive) {
              // ההתראה נסגרה (ע"י המנווט)
              return AlertDialog(
                title: const Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 28),
                    SizedBox(width: 8),
                    Text('נוהל ברבור הסתיים'),
                  ],
                ),
                content: Text('${alert.navigatorName ?? alert.navigatorId} סיים את נוהל ברבור.'),
                actions: [
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('סגור'),
                  ),
                ],
              );
            }

            final checklist = Map<String, bool>.from(liveAlert.barburChecklist ?? {
              'returnToAxis': false,
              'goToHighPoint': false,
              'openMap': false,
              'showLocation': false,
            });
            final navigatorId = liveAlert.navigatorId;
            final completedCount = checklist.values.where((v) => v).length;
            final allDone = completedCount == 4;

            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.report_problem, color: Colors.orange, size: 28),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('נוהל ברבור', style: TextStyle(color: Colors.orange)),
                        Text(
                          liveAlert.navigatorName ?? navigatorId,
                          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: allDone ? Colors.green : Colors.orange,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$completedCount/4',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // שלב א — חזרה בציר
                    CheckboxListTile(
                      title: const Text('א) חזרה בציר הניווט לנקודה מוכרת'),
                      subtitle: const Text('אימות ידני', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      value: checklist['returnToAxis'] ?? false,
                      activeColor: Colors.green,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (v) {
                        checklist['returnToAxis'] = v ?? false;
                        _alertRepo.updateBarburChecklist(alert.navigationId, alert.id, checklist);
                      },
                    ),
                    // שלב ב — עלייה למקום גבוה
                    CheckboxListTile(
                      title: const Text('ב) עלייה למקום גבוה'),
                      subtitle: const Text('אימות ידני', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      value: checklist['goToHighPoint'] ?? false,
                      activeColor: Colors.green,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (v) {
                        checklist['goToHighPoint'] = v ?? false;
                        _alertRepo.updateBarburChecklist(alert.navigationId, alert.id, checklist);
                      },
                    ),
                    // שלב ג — פתיחת מפה
                    CheckboxListTile(
                      title: const Text('ג) פתיחת מפה'),
                      subtitle: Text(
                        checklist['openMap'] == true ? 'מפה פתוחה למנווט' : 'יפתח מפה למנווט',
                        style: TextStyle(
                          fontSize: 11,
                          color: checklist['openMap'] == true ? Colors.green : Colors.grey,
                        ),
                      ),
                      value: checklist['openMap'] ?? false,
                      activeColor: Colors.green,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (v) {
                        checklist['openMap'] = v ?? false;
                        // אם מכבים מפה — גם לכבות מיקום
                        if (!(v ?? false)) {
                          checklist['showLocation'] = false;
                        }
                        _alertRepo.updateBarburChecklist(alert.navigationId, alert.id, checklist);
                        // עדכון דריסות מפה בפועל
                        _navigatorOverrideAllowOpenMap[navigatorId] = v ?? false;
                        if (!(v ?? false)) {
                          _navigatorOverrideShowSelfLocation[navigatorId] = false;
                        }
                        _updateNavigatorMapOverrides(navigatorId);
                        setState(() {});
                      },
                    ),
                    // שלב ד — הצגת מיקום (רק אם מפה פתוחה)
                    CheckboxListTile(
                      title: const Text('ד) הצגת מיקום עצמי'),
                      subtitle: Text(
                        checklist['showLocation'] == true ? 'מיקום מוצג למנווט' : 'יציג מיקום למנווט',
                        style: TextStyle(
                          fontSize: 11,
                          color: checklist['showLocation'] == true ? Colors.green : Colors.grey,
                        ),
                      ),
                      value: checklist['showLocation'] ?? false,
                      activeColor: Colors.green,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (checklist['openMap'] ?? false) ? (v) {
                        checklist['showLocation'] = v ?? false;
                        _alertRepo.updateBarburChecklist(alert.navigationId, alert.id, checklist);
                        // עדכון דריסת מיקום
                        _navigatorOverrideShowSelfLocation[navigatorId] = v ?? false;
                        _updateNavigatorMapOverrides(navigatorId);
                        setState(() {});
                      } : null,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('מזער'),
                ),
                if (allDone)
                  ElevatedButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _finishBarburProtocol(liveAlert);
                    },
                    icon: const Icon(Icons.check_circle),
                    label: const Text('סיום נוהל'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _finishBarburProtocol(NavigatorAlert alert) async {
    final navigatorId = alert.navigatorId;

    // שאלת המשך: האם לסגור את המפה?
    final revertOverrides = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('סיום נוהל ברבור'),
        content: const Text('האם לסגור את המפה והמיקום למנווט?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('השאר פתוח'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            child: const Text('סגור מפה'),
          ),
        ],
      ),
    );

    // סגירת ההתראה
    await _resolveAlert(alert);

    // ביטול דריסות מפה אם נבחר
    if (revertOverrides == true) {
      _navigatorOverrideAllowOpenMap[navigatorId] = false;
      _navigatorOverrideShowSelfLocation[navigatorId] = false;
      _navigatorOverrideShowRouteOnMap[navigatorId] = false;
      await _updateNavigatorMapOverrides(navigatorId);
      if (mounted) setState(() {});
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('נוהל ברבור הסתיים'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  List<Widget> _buildNavigatorBarburSection(String navigatorId) {
    final barburAlert = _activeAlerts.where(
      (a) => a.type == AlertType.barbur && a.navigatorId == navigatorId,
    ).toList();
    if (barburAlert.isEmpty) return [];

    final alert = barburAlert.first;
    final checklist = alert.barburChecklist ?? {};
    final completedCount = checklist.values.where((v) => v).length;

    return [
      const SizedBox(height: 8),
      GestureDetector(
        onTap: () => _showBarburProtocolDialog(alert),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.orange[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.orange),
          ),
          child: Row(
            children: [
              const Icon(Icons.report_problem, color: Colors.orange, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'נוהל ברבור פעיל ($completedCount/4)',
                  style: const TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              const Icon(Icons.open_in_new, color: Colors.orange, size: 16),
            ],
          ),
        ),
      ),
    ];
  }

  void _updateNavigatorDataFromFirestore(List<Map<String, dynamic>> tracks) {
    if (!mounted) return;

    setState(() {
      for (final data in tracks) {
        final navigatorId = data['navigatorUserId'] as String?;
        if (navigatorId == null) continue;
        final docId = data['id'] as String? ?? '';

        // אם מנווט חדש שלא ברשימה (מקרה קצה)
        if (!_navigatorData.containsKey(navigatorId)) {
          _selectedNavigators[navigatorId] = true;
          _navigatorData[navigatorId] = NavigatorLiveData(
            navigatorId: navigatorId,
            personalStatus: NavigatorPersonalStatus.waiting,
            trackPoints: [],
            punches: [],
          );
        }

        final liveData = _navigatorData[navigatorId]!;

        // מנווט שסיים ידנית — לא לדרוס סטטוס finished
        if (liveData.personalStatus == NavigatorPersonalStatus.finished) {
          // עדכון נקודות מסלול + isDisqualified (לא סטטוס)
          final trackPointsRaw = data['trackPointsJson'];
          if (trackPointsRaw != null && trackPointsRaw is String && trackPointsRaw.isNotEmpty) {
            try {
              final pointsList = jsonDecode(trackPointsRaw) as List;
              liveData.trackPoints = pointsList
                  .map((p) => TrackPoint.fromMap(p as Map<String, dynamic>))
                  .toList();
            } catch (_) {}
          }
          liveData.isDisqualified = data['isDisqualified'] as bool? ?? false;
          liveData.disqualificationReason = data['disqualificationReason'] as String?;
          continue;
        }

        // פרסור trackPoints
        final trackPointsRaw = data['trackPointsJson'];
        if (trackPointsRaw != null && trackPointsRaw is String && trackPointsRaw.isNotEmpty) {
          try {
            final pointsList = jsonDecode(trackPointsRaw) as List;
            liveData.trackPoints = pointsList
                .map((p) => TrackPoint.fromMap(p as Map<String, dynamic>))
                .toList();

            // מיקום נוכחי מנקודה אחרונה
            if (liveData.trackPoints.isNotEmpty) {
              final last = liveData.trackPoints.last;
              liveData.currentPosition = LatLng(last.coordinate.lat, last.coordinate.lng);
              liveData.lastUpdate = last.timestamp;
              liveData.isGpsPlusFix = last.positionSource == 'cellTower';
            }
          } catch (e) {
            print('DEBUG NavigationManagement: parse trackPoints error: $e');
          }
        }

        // עדכון סטטוס
        final isActive = data['isActive'] as bool? ?? false;
        final endedAtRaw = data['endedAt'];
        DateTime? endedAt;
        if (endedAtRaw is Timestamp) {
          endedAt = endedAtRaw.toDate();
        } else if (endedAtRaw is String) {
          endedAt = DateTime.tryParse(endedAtRaw);
        }

        liveData.personalStatus = NavigatorPersonalStatus.deriveFromTrack(
          hasTrack: true,
          isActive: isActive,
          endedAt: endedAt,
        );
        liveData.trackEndedAt = endedAt;

        // קריאת isDisqualified + סיבה מה-track doc
        liveData.isDisqualified = data['isDisqualified'] as bool? ?? false;
        liveData.disqualificationReason = data['disqualificationReason'] as String?;

        // cache trackId + קריאת דריסות מפה (רק אם הוגדר ב-Firestore — אחרת נשאר default מהגדרות הניווט)
        _navigatorTrackIds[navigatorId] = docId;
        if (data.containsKey('overrideAllowOpenMap')) {
          _navigatorOverrideAllowOpenMap[navigatorId] = data['overrideAllowOpenMap'] as bool? ?? false;
        }
        if (data.containsKey('overrideShowSelfLocation')) {
          _navigatorOverrideShowSelfLocation[navigatorId] = data['overrideShowSelfLocation'] as bool? ?? false;
        }
        if (data.containsKey('overrideShowRouteOnMap')) {
          _navigatorOverrideShowRouteOnMap[navigatorId] = data['overrideShowRouteOnMap'] as bool? ?? false;
        }
        if (data.containsKey('overrideWalkieTalkieEnabled')) {
          _navigatorOverrideWalkieTalkieEnabled[navigatorId] = data['overrideWalkieTalkieEnabled'] as bool? ?? false;
        }
        if (data.containsKey('overrideRevealEnabled')) {
          _navigatorOverrideRevealEnabled[navigatorId] = data['overrideRevealEnabled'] as bool?;
        }
        if (data.containsKey('overrideGpsIntervalSeconds')) {
          _navigatorGpsIntervalOverride[navigatorId] = data['overrideGpsIntervalSeconds'] as int?;
        }
        if (data.containsKey('overrideGpsSyncIntervalSeconds')) {
          _navigatorGpsSyncIntervalOverride[navigatorId] = (data['overrideGpsSyncIntervalSeconds'] as num?)?.toInt();
        }
        if (data.containsKey('overrideEnabledPositionSources')) {
          final sources = data['overrideEnabledPositionSources'];
          _navigatorPositionSourcesOverride[navigatorId] = sources is List ? sources.cast<String>() : null;
        }
        if (data.containsKey('overrideAlertSoundVolumes') && data['overrideAlertSoundVolumes'] is Map) {
          _navigatorAlertSoundVolumes[navigatorId] = Map<String, double>.from(
            (data['overrideAlertSoundVolumes'] as Map).map(
              (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
            ),
          );
        }

        // זמן התחלה אישי של המנווט
        final startedAtRaw = data['startedAt'];
        if (startedAtRaw is Timestamp) {
          liveData.trackStartedAt = startedAtRaw.toDate();
        } else if (startedAtRaw is String) {
          liveData.trackStartedAt = DateTime.tryParse(startedAtRaw);
        }

        // ניווט כוכב — קריאת שדות star
        if (_currentNavigation.navigationType == 'star') {
          final oldReturned = liveData.starReturnedToCenter;
          liveData.starCurrentPointIndex = (data['starCurrentPointIndex'] as num?)?.toInt();
          final slEnd = data['starLearningEndTime'];
          liveData.starLearningEndTime = slEnd is Timestamp ? slEnd.toDate() : (slEnd is String ? DateTime.tryParse(slEnd) : null);
          final snEnd = data['starNavigatingEndTime'];
          liveData.starNavigatingEndTime = snEnd is Timestamp ? snEnd.toDate() : (snEnd is String ? DateTime.tryParse(snEnd) : null);
          liveData.starReturnedToCenter = data['starReturnedToCenter'] as bool? ?? false;

          // Auto mode: פתיחת נקודה הבאה אוטומטית
          if (_currentNavigation.starAutoMode &&
              liveData.starReturnedToCenter && !oldReturned) {
            final route = _currentNavigation.routes[navigatorId];
            final currentIdx = liveData.starCurrentPointIndex ?? -1;
            final totalPoints = route?.sequence.length ?? 0;
            if (currentIdx >= 0 && currentIdx < totalPoints - 1) {
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted) _openStarPointForNavigator(navigatorId, currentIdx + 1);
              });
            }
          }
        }

      }
    });
  }

  // ===========================================================================
  // ניווט כוכב — פתיחת נקודה, סטטוס, הארכה
  // ===========================================================================

  /// חישוב שלב כוכב למנווט
  StarPhase _computeStarPhaseForNavigator(String navigatorId) {
    final data = _navigatorData[navigatorId];
    if (data == null) return StarPhase.atCenter;
    final route = _currentNavigation.routes[navigatorId];
    final totalPoints = route?.sequence.length ?? 0;
    // בדיקה אם הנקודה הנוכחית הוגעה (punched)
    final idx = data.starCurrentPointIndex;
    bool punched = false;
    if (idx != null && idx >= 0 && route != null && idx < route.sequence.length) {
      final targetCpId = route.sequence[idx];
      punched = data.punches.any((p) => p.checkpointId == targetCpId);
    }
    return computeStarPhase(
      index: idx,
      learningEnd: data.starLearningEndTime,
      navigatingEnd: data.starNavigatingEndTime,
      currentPointPunched: punched,
      returned: data.starReturnedToCenter,
      totalPoints: totalPoints,
      now: DateTime.now(),
    );
  }

  /// טקסט סטטוס כוכב קצר למנווט
  String _starStatusText(String navigatorId) {
    final phase = _computeStarPhaseForNavigator(navigatorId);
    final data = _navigatorData[navigatorId];
    final route = _currentNavigation.routes[navigatorId];
    final totalPoints = route?.sequence.length ?? 0;
    final idx = (data?.starCurrentPointIndex ?? -1) + 1;

    String remaining(DateTime? end) {
      if (end == null) return '';
      final diff = end.difference(DateTime.now());
      if (diff.isNegative) return '0:00';
      return '${diff.inMinutes}:${(diff.inSeconds % 60).toString().padLeft(2, '0')}';
    }

    switch (phase) {
      case StarPhase.atCenter:
        if (idx <= 0) return 'במרכז — ממתין לנקודה ראשונה';
        return 'במרכז — $idx/$totalPoints';
      case StarPhase.learning:
        return 'בלמידה (${remaining(data?.starLearningEndTime)}) — $idx/$totalPoints';
      case StarPhase.navigating:
        final navEnd = data?.starNavigatingEndTime;
        final timeStr = navEnd != null ? ' (${remaining(navEnd)})' : '';
        return 'בניווט$timeStr — $idx/$totalPoints';
      case StarPhase.returning:
        final navEnd = data?.starNavigatingEndTime;
        if (navEnd != null) {
          final diff = navEnd.difference(DateTime.now());
          final abs = diff.abs();
          final m = abs.inMinutes;
          final s = abs.inSeconds % 60;
          final timeStr = '${diff.isNegative ? '+' : ''}$m:${s.toString().padLeft(2, '0')}';
          return 'חוזר למרכז ($timeStr) — $idx/$totalPoints';
        }
        return 'חוזר למרכז — $idx/$totalPoints';
      case StarPhase.timeout:
        return 'זמן נגמר — $idx/$totalPoints';
      case StarPhase.completed:
        return 'סיים $totalPoints/$totalPoints';
    }
  }

  /// צבע שלב כוכב
  Color _starPhaseColor(StarPhase phase) {
    switch (phase) {
      case StarPhase.atCenter: return Colors.grey;
      case StarPhase.learning: return Colors.blue;
      case StarPhase.navigating: return Colors.green;
      case StarPhase.returning: return Colors.orange;
      case StarPhase.timeout: return Colors.red;
      case StarPhase.completed: return Colors.teal;
    }
  }

  /// פתיחת נקודה הבאה למנווט (auto-mode או ידני ללא דיאלוג)
  Future<void> _openStarPointForNavigator(String navigatorId, int pointIndex) async {
    final trackId = _navigatorTrackIds[navigatorId];
    if (trackId == null) return;

    final learningMin = _currentNavigation.starLearningMinutes ?? 5;
    final navigatingMin = _currentNavigation.starNavigatingMinutes ?? 15;
    final now = DateTime.now();
    final learningEnd = now.add(Duration(minutes: learningMin));
    final navigatingEnd = now.add(Duration(minutes: learningMin + navigatingMin));

    await _trackRepo.updateStarState(
      trackId,
      pointIndex: pointIndex,
      learningEndTime: learningEnd,
      navigatingEndTime: navigatingEnd,
      returnedToCenter: false,
      starStartedAt: pointIndex == 0 ? now : null,
    );
  }

  /// פתיחת נקודה הבאה — עם דיאלוג לעריכת זמנים
  Future<void> _showOpenStarPointDialog(String navigatorId) async {
    final data = _navigatorData[navigatorId];
    if (data == null) return;
    final route = _currentNavigation.routes[navigatorId];
    if (route == null) return;
    final totalPoints = route.sequence.length;

    // חישוב אינדקס הבא
    final phase = _computeStarPhaseForNavigator(navigatorId);
    final currentIdx = data.starCurrentPointIndex ?? -1;
    int nextIndex;
    if (phase == StarPhase.atCenter && currentIdx < 0) {
      nextIndex = 0; // נקודה ראשונה
    } else if (phase == StarPhase.atCenter || phase == StarPhase.completed) {
      nextIndex = currentIdx + 1;
    } else {
      // מנווט לא במרכז — אי אפשר לפתוח
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('המנווט עדיין לא חזר למרכז')),
        );
      }
      return;
    }

    if (nextIndex >= totalPoints) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('המנווט סיים את כל הנקודות')),
        );
      }
      return;
    }

    // שם הנקודה הבאה
    final cpId = route.sequence[nextIndex];
    final cp = _checkpoints.where((c) => c.id == cpId).firstOrNull;
    final cpName = cp != null ? 'נ"צ ${cp.sequenceNumber}${cp.name != null ? ' — ${cp.name}' : ''}' : 'נקודה ${nextIndex + 1}';

    final learningCtrl = TextEditingController(text: '${_currentNavigation.starLearningMinutes ?? 5}');
    final navigatingCtrl = TextEditingController(text: '${_currentNavigation.starNavigatingMinutes ?? 15}');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('פתיחת נקודה ${nextIndex + 1}/$totalPoints'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(cpName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            Text('למנווט: ${_userNames[navigatorId] ?? navigatorId}'),
            const SizedBox(height: 16),
            TextFormField(
              controller: learningCtrl,
              decoration: const InputDecoration(
                labelText: 'זמן למידה (דקות)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: navigatingCtrl,
              decoration: const InputDecoration(
                labelText: 'זמן ניווט (דקות)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ביטול')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('פתח נקודה')),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final trackId = _navigatorTrackIds[navigatorId];
    if (trackId == null) return;

    final learningMin = int.tryParse(learningCtrl.text) ?? _currentNavigation.starLearningMinutes ?? 5;
    final navigatingMin = int.tryParse(navigatingCtrl.text) ?? _currentNavigation.starNavigatingMinutes ?? 15;
    final now = DateTime.now();

    await _trackRepo.updateStarState(
      trackId,
      pointIndex: nextIndex,
      learningEndTime: now.add(Duration(minutes: learningMin)),
      navigatingEndTime: now.add(Duration(minutes: learningMin + navigatingMin)),
      returnedToCenter: false,
    );
  }

  /// הארכת זמן ניווט למנווט בכוכב
  Future<void> _showExtendStarTimeDialog(String navigatorId) async {
    final data = _navigatorData[navigatorId];
    if (data == null) return;
    final phase = _computeStarPhaseForNavigator(navigatorId);
    if (phase != StarPhase.timeout && phase != StarPhase.navigating) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('המנווט לא בשלב ניווט או זמן נגמר')),
        );
      }
      return;
    }

    final extendCtrl = TextEditingController(text: '10');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('הארכת זמן ניווט'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('מנווט: ${_userNames[navigatorId] ?? navigatorId}'),
            const SizedBox(height: 12),
            TextFormField(
              controller: extendCtrl,
              decoration: const InputDecoration(
                labelText: 'דקות להוספה',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ביטול')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('הארך')),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final trackId = _navigatorTrackIds[navigatorId];
    if (trackId == null) return;

    final minutes = int.tryParse(extendCtrl.text) ?? 10;
    // הארכה מהעכשיו (לא מהזמן המקורי)
    final newEnd = DateTime.now().add(Duration(minutes: minutes));
    await _trackRepo.updateStarState(trackId, navigatingEndTime: newEnd);
  }

  /// פתיחת נקודה הבאה לכל המנווטים שבמרכז
  Future<void> _openStarPointForAllAtCenter() async {
    int opened = 0;
    for (final entry in _navigatorData.entries) {
      final navigatorId = entry.key;
      final phase = _computeStarPhaseForNavigator(navigatorId);
      if (phase != StarPhase.atCenter) continue;

      final route = _currentNavigation.routes[navigatorId];
      if (route == null) continue;
      final currentIdx = entry.value.starCurrentPointIndex ?? -1;
      final nextIdx = currentIdx < 0 ? 0 : currentIdx + 1;
      if (nextIdx >= route.sequence.length) continue;

      await _openStarPointForNavigator(navigatorId, nextIdx);
      opened++;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('נפתחה נקודה ל-$opened מנווטים')),
      );
    }
  }

  Future<void> _finishNavigatorNavigation(String navigatorId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('עצירה מרחוק'),
        content: Text('האם לסיים את הניווט עבור $navigatorId?\n\nהמנווט יזוהה תוך ~30 שניות.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('עצור'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _trackRepo.stopNavigatorRemote(widget.navigation.id, navigatorId);

      // עדכון UI
      if (mounted) {
        setState(() {
          _navigatorData[navigatorId]?.personalStatus = NavigatorPersonalStatus.finished;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('פקודת עצירה נשלחה ל-$navigatorId'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בעצירה מרחוק: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// התחלת ניווט מחדש — מחיקת track בלבד, מנווט חוזר למסך המתנה
  Future<void> _startNavigatorNavigation(String navigatorId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('התחלת ניווט מחדש'),
        content: Text('להחזיר את $navigatorId למסך התחלת ניווט?\n\nכל הנתונים (מסלול + דקירות) יימחקו.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.green),
            child: const Text('התחל מחדש'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _trackRepo.resetNavigatorRemote(widget.navigation.id, navigatorId);
      await _punchRepo.deleteByNavigator(widget.navigation.id, navigatorId);

      // עדכון UI מקומי
      if (mounted) {
        setState(() {
          final data = _navigatorData[navigatorId];
          if (data != null) {
            data.personalStatus = NavigatorPersonalStatus.waiting;
            data.trackPoints = [];
            data.punches = [];
            data.currentPosition = null;
            data.trackStartedAt = null;
            data.trackEndedAt = null;
            data.resetAt = DateTime.now();
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$navigatorId הוחזר למסך התחלת ניווט'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בהתחלת ניווט מחדש: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// המשך ניווט — חידוש track קיים, מנווט ממשיך מאיפה שנעצר
  Future<void> _resumeNavigatorNavigation(String navigatorId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('המשך ניווט'),
        content: Text('להמשיך את הניווט עבור $navigatorId?\n\nהניווט ימשיך מאיפה שנעצר.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.blue),
            child: const Text('המשך ניווט'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _trackRepo.resumeNavigatorRemote(widget.navigation.id, navigatorId);

      // עדכון UI מקומי
      if (mounted) {
        setState(() {
          final data = _navigatorData[navigatorId];
          if (data != null) {
            data.personalStatus = NavigatorPersonalStatus.active;
            data.trackEndedAt = null;
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$navigatorId ממשיך ניווט'),
            backgroundColor: Colors.blue,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בהמשך ניווט: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// איפוס ניווט — מחיקת track + דקירות, מנווט חוזר למסך המתנה נקי
  Future<void> _resetNavigatorNavigation(String navigatorId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('איפוס ניווט'),
        content: Text(
          'לאפס את הניווט עבור $navigatorId?\n\n'
          '⚠️ כל הנתונים יימחקו: מסלול + דקירות.\n'
          'לא ניתן לשחזר פעולה זו.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            child: const Text('אפס ניווט'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _trackRepo.resetNavigatorRemote(widget.navigation.id, navigatorId);
      await _punchRepo.deleteByNavigator(widget.navigation.id, navigatorId);

      // עדכון UI מקומי
      if (mounted) {
        setState(() {
          final data = _navigatorData[navigatorId];
          if (data != null) {
            data.personalStatus = NavigatorPersonalStatus.waiting;
            data.trackPoints = [];
            data.punches = [];
            data.currentPosition = null;
            data.trackStartedAt = null;
            data.trackEndedAt = null;
            data.isDisqualified = false;
            data.resetAt = DateTime.now();
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('הניווט של $navigatorId אופס — מסלול ודקירות נמחקו'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה באיפוס ניווט: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// ביטול פסילה — שמירת נתונים, מנווט מקבל ציון רגיל
  Future<void> _undoDisqualification(String navigatorId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ביטול פסילה'),
        content: Text(
          'לבטל את פסילת $navigatorId?\n\n'
          'הנתונים יישמרו והמנווט יקבל ציון רגיל.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.green),
            child: const Text('בטל פסילה'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // מציאת track ID
      final trackId = _navigatorTrackIds[navigatorId] ??
          await _trackRepo.findTrackId(widget.navigation.id, navigatorId);

      if (trackId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('לא נמצא track למנווט'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      await _trackRepo.undoDisqualification(trackId);

      if (mounted) {
        setState(() {
          final data = _navigatorData[navigatorId];
          if (data != null) {
            data.isDisqualified = false;
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('הפסילה של $navigatorId בוטלה'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בביטול פסילה: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// תפריט פעולות פר-מנווט (3-dot menu)
  Widget _buildNavigatorActionsMenu(String navigatorId, NavigatorLiveData data, {VoidCallback? onBeforeAction}) {
    final status = data.personalStatus;

    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 22),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      position: PopupMenuPosition.under,
      offset: const Offset(0, 8),
      tooltip: 'פעולות',
      onSelected: (value) {
        onBeforeAction?.call();
        switch (value) {
          case 'stop':
            _finishNavigatorNavigation(navigatorId);
            break;
          case 'start':
            _startNavigatorNavigation(navigatorId);
            break;
          case 'resume':
            _resumeNavigatorNavigation(navigatorId);
            break;
          case 'reset':
            _resetNavigatorNavigation(navigatorId);
            break;
          case 'undo_disqualify':
            _undoDisqualification(navigatorId);
            break;
          case 'star_open':
            _showOpenStarPointDialog(navigatorId);
            break;
          case 'star_extend':
            _showExtendStarTimeDialog(navigatorId);
            break;
        }
      },
      itemBuilder: (context) => [
        // סיום ניווט — רק active/noReception
        if (status == NavigatorPersonalStatus.active ||
            status == NavigatorPersonalStatus.noReception)
          const PopupMenuItem(
            value: 'stop',
            child: Row(
              children: [
                Icon(Icons.stop_circle, color: Colors.red, size: 20),
                SizedBox(width: 8),
                Text('סיום ניווט', style: TextStyle(color: Colors.red)),
              ],
            ),
          ),
        // התחלת ניווט — רק waiting
        if (status == NavigatorPersonalStatus.waiting)
          const PopupMenuItem(
            value: 'start',
            child: Row(
              children: [
                Icon(Icons.play_circle, color: Colors.green, size: 20),
                SizedBox(width: 8),
                Text('התחלת ניווט', style: TextStyle(color: Colors.green)),
              ],
            ),
          ),
        // המשך ניווט — רק finished
        if (status == NavigatorPersonalStatus.finished)
          const PopupMenuItem(
            value: 'resume',
            child: Row(
              children: [
                Icon(Icons.play_circle, color: Colors.blue, size: 20),
                SizedBox(width: 8),
                Text('המשך ניווט', style: TextStyle(color: Colors.blue)),
              ],
            ),
          ),
        // אפס ניווט — רק כשיש נתונים (לא waiting)
        if (status != NavigatorPersonalStatus.waiting)
          const PopupMenuItem(
            value: 'reset',
            child: Row(
              children: [
                Icon(Icons.restart_alt, color: Colors.orange, size: 20),
                SizedBox(width: 8),
                Text('אפס ניווט', style: TextStyle(color: Colors.orange)),
              ],
            ),
          ),
        // ביטול פסילה — רק למנווט שנפסל
        if (data.isDisqualified)
          const PopupMenuItem(
            value: 'undo_disqualify',
            child: Row(
              children: [
                Icon(Icons.undo, color: Colors.green, size: 20),
                SizedBox(width: 8),
                Text('בטל פסילה', style: TextStyle(color: Colors.green)),
              ],
            ),
          ),
        // ניווט כוכב — פתיחת נקודה הבאה
        if (_currentNavigation.navigationType == 'star') ...[
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'star_open',
            child: Row(
              children: [
                Icon(Icons.star, color: Colors.amber, size: 20),
                SizedBox(width: 8),
                Text('פתח נקודה הבאה'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'star_extend',
            child: Row(
              children: [
                Icon(Icons.more_time, color: Colors.blue, size: 20),
                SizedBox(width: 8),
                Text('הארך זמן ניווט'),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _finishAllNavigation() async {
    if (!PermissionUtils.checkManagement(context, _currentUser)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('סיום ניווט כללי'),
        content: const Text(
          'האם לסיים את הניווט עבור כל המנווטים?\n\n'
          'פעולה זו תסיים את הניווט באופן סופי.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.red,
            ),
            child: const Text('סיים ניווט כללי'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    try {
      await _trackRepo.stopAllNavigatorsRemote(widget.navigation.id);

      // מניעת pop כפול — הליסנר על Firestore יזהה 'review' וינסה pop
      _alreadyClosed = true;

      // עדכון סטטוס ניווט — ישירות לתחקור (ללא שלב אישור נפרד)
      final updatedNavigation = widget.navigation.copyWith(
        status: 'review',
        activeStartTime: null,
        updatedAt: DateTime.now(),
      );
      await _navRepo.update(updatedNavigation);

      if (mounted) {
        setState(() => _isLoading = false);
        Navigator.pop(context, true); // חזרה לרשימה עם סימון לרענון
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('הניווט הסתיים - מעבר לתחקור'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בסיום ניווט כללי: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ===========================================================================
  // מרכוז מפה — Centering Logic
  // ===========================================================================

  void _cycleNavigatorCenteringMode(String navigatorId) {
    setState(() {
      if (_centeredNavigatorId == navigatorId) {
        // מחזור: northLocked → rotationByHeading → off
        switch (_centeringMode) {
          case CenteringMode.off:
            _centeringMode = CenteringMode.northLocked;
          case CenteringMode.northLocked:
            _centeringMode = CenteringMode.rotationByHeading;
          case CenteringMode.rotationByHeading:
            _stopCentering();
            return;
        }
      } else {
        // מתחיל מרכוז על מנווט חדש
        _centeredNavigatorId = navigatorId;
        _centeringMode = CenteringMode.northLocked;
      }
    });
    _startCentering();
  }

  void _cycleSelfCenteringMode() {
    setState(() {
      if (_centeredNavigatorId != null) {
        // עובר ממרכוז מנווט למרכוז עצמי
        _centeredNavigatorId = null;
        _centeringMode = CenteringMode.northLocked;
      } else {
        switch (_centeringMode) {
          case CenteringMode.off:
            _centeringMode = CenteringMode.northLocked;
          case CenteringMode.northLocked:
            _centeringMode = CenteringMode.rotationByHeading;
          case CenteringMode.rotationByHeading:
            _stopCentering();
            return;
        }
      }
    });
    _startCentering();
  }

  void _startCentering() {
    _centeringTimer?.cancel();
    _mapGestureSubscription?.cancel();

    // ביצוע ראשוני מיידי
    _performCentering();

    // רענון כל 2 שניות
    _centeringTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _performCentering(),
    );

    // האזנה למגע ידני על המפה — מבטל מרכוז
    _setupGestureDetection();
  }

  void _performCentering() async {
    if (_centeringMode == CenteringMode.off) return;
    if (!mounted) return;

    LatLng? pos;
    double heading = 0;

    if (_centeredNavigatorId != null) {
      // מרכוז על מנווט
      final data = _navigatorData[_centeredNavigatorId];
      if (data == null || data.currentPosition == null) return;
      pos = data.currentPosition;

      // heading מנקודת GPS אחרונה
      if (data.trackPoints.length >= 2) {
        final prev = data.trackPoints[data.trackPoints.length - 2];
        final last = data.trackPoints.last;
        heading = GeometryUtils.bearingBetween(
          prev.coordinate,
          last.coordinate,
        );
      }
    } else {
      // מרכוז עצמי — מיקום GPS של המפקד
      pos = await GpsService().getCurrentPosition();
      // אין heading למפקד (לא זזים) — נשאר 0
    }

    if (pos == null || !mounted) return;

    try {
      final currentZoom = _mapController.camera.zoom;
      switch (_centeringMode) {
        case CenteringMode.northLocked:
          _mapController.moveAndRotate(pos, currentZoom, 0);
        case CenteringMode.rotationByHeading:
          _mapController.moveAndRotate(pos, currentZoom, -heading);
        case CenteringMode.off:
          break;
      }
    } catch (_) {
      _stopCentering();
    }
  }

  void _setupGestureDetection() {
    _mapGestureSubscription?.cancel();
    _mapGestureSubscription = _mapController.mapEventStream.listen((event) {
      // עצירת מעקב רק בגרירה או לחיצה — זום (פינץ', גלגלת, דאבל-טאפ) לא מפסיק
      const stopSources = {
        MapEventSource.dragStart,
        MapEventSource.onDrag,
        MapEventSource.dragEnd,
        MapEventSource.tap,
        MapEventSource.secondaryTap,
        MapEventSource.longPress,
      };
      if (stopSources.contains(event.source)) {
        _stopCentering();
      }
    });
  }

  void _stopCentering() {
    _centeringTimer?.cancel();
    _centeringTimer = null;
    _mapGestureSubscription?.cancel();
    _mapGestureSubscription = null;
    if (mounted) {
      setState(() {
        _centeringMode = CenteringMode.off;
        _centeredNavigatorId = null;
      });
    }
  }

  /// הדגשה חד-פעמית (עיגול כחול) — יורדת כשהמשתמש נוגע במפה
  void _setOneTimeHighlight(String navigatorId) {
    _oneTimeGestureSubscription?.cancel();
    setState(() => _oneTimeCenteredNavigatorId = navigatorId);

    _oneTimeGestureSubscription = _mapController.mapEventStream.listen((event) {
      if (event.source != MapEventSource.mapController &&
          event.source != MapEventSource.nonRotatedSizeChange) {
        _clearOneTimeHighlight();
      }
    });
  }

  void _clearOneTimeHighlight() {
    _oneTimeGestureSubscription?.cancel();
    _oneTimeGestureSubscription = null;
    if (mounted) {
      setState(() => _oneTimeCenteredNavigatorId = null);
    }
  }

  // ===========================================================================
  // Helper methods — חישובים ופורמט
  // ===========================================================================

  /// אוסף מזהי נקודות ציון המשתתפות במסלולים
  Set<String> _collectParticipatingCheckpointIds({bool selectedOnly = false}) {
    final ids = <String>{};
    for (final entry in widget.navigation.routes.entries) {
      if (selectedOnly && _selectedNavigators[entry.key] != true) continue;
      final route = entry.value;
      if (route.startPointId != null) ids.add(route.startPointId!);
      if (route.endPointId != null) ids.add(route.endPointId!);
      if (route.swapPointId != null) ids.add(route.swapPointId!);
      ids.addAll(route.checkpointIds);
      ids.addAll(route.waypointIds);
    }
    // fallback — הגדרות ניווט (לפני חלוקת צירים)
    if (!selectedOnly) {
      if (widget.navigation.startPoint != null) ids.add(widget.navigation.startPoint!);
      if (widget.navigation.endPoint != null) ids.add(widget.navigation.endPoint!);
      if (widget.navigation.waypointSettings.enabled) {
        for (final wp in widget.navigation.waypointSettings.waypoints) {
          ids.add(wp.checkpointId);
        }
      }
    }
    return ids;
  }

  /// מחזיר נקודות ציון מסוננות לפי מצב התצוגה הנבחר
  List<Checkpoint> _getCheckpointsForDisplay() {
    final base = _checkpoints.where((cp) => !cp.isPolygon && cp.coordinates != null).toList();
    switch (_nzMode) {
      case _NzDisplayMode.selectedNavigators:
        final ids = _collectParticipatingCheckpointIds(selectedOnly: true);
        return base.where((cp) => ids.contains(cp.id)).toList();
      case _NzDisplayMode.participatingOnly:
        final ids = _collectParticipatingCheckpointIds();
        return base.where((cp) => ids.contains(cp.id)).toList();
      case _NzDisplayMode.allCheckpoints:
        return base;
    }
  }

  /// בורר מצב הצגת נקודות ציון — 3 chips
  Widget _buildNzModeSelector() {
    const modes = [
      (_NzDisplayMode.selectedNavigators, 'מנווטים נבחרים'),
      (_NzDisplayMode.participatingOnly, 'משתתפות בניווט'),
      (_NzDisplayMode.allCheckpoints, 'כל הנקודות'),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 2,
        children: modes.map((m) => ChoiceChip(
          label: Text(m.$2, style: const TextStyle(fontSize: 10)),
          selected: _nzMode == m.$1,
          onSelected: (_) => setState(() => _nzMode = m.$1),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          labelPadding: const EdgeInsets.symmetric(horizontal: 4),
          padding: EdgeInsets.zero,
        )).toList(),
      ),
    );
  }

  List<_CheckpointArrival> _getCheckpointArrivals(NavigatorLiveData data) {
    final route = widget.navigation.routes[data.navigatorId];
    if (route == null) return [];

    return route.checkpointIds.map((cpId) {
      final checkpoint = _checkpoints.where((c) => c.id == cpId).firstOrNull;
      if (checkpoint == null) return null;

      final punch = data.punches
          .where((p) => p.checkpointId == cpId && p.isActive)
          .firstOrNull;

      return _CheckpointArrival(
        checkpoint: checkpoint,
        punch: punch,
        verificationSettings: widget.navigation.verificationSettings,
      );
    }).whereType<_CheckpointArrival>().toList();
  }

  List<_NavigatorPairDistance> _getInterNavigatorDistances() {
    final activeWithPosition = _navigatorData.entries
        .where((e) =>
            (e.value.personalStatus == NavigatorPersonalStatus.active ||
             e.value.personalStatus == NavigatorPersonalStatus.noReception) &&
            e.value.currentPosition != null)
        .toList();

    final pairs = <_NavigatorPairDistance>[];
    for (int i = 0; i < activeWithPosition.length; i++) {
      for (int j = i + 1; j < activeWithPosition.length; j++) {
        final a = activeWithPosition[i];
        final b = activeWithPosition[j];
        final posA = a.value.currentPosition!;
        final posB = b.value.currentPosition!;

        final dist = GeometryUtils.distanceBetweenMeters(
          Coordinate(lat: posA.latitude, lng: posA.longitude, utm: ''),
          Coordinate(lat: posB.latitude, lng: posB.longitude, utm: ''),
        );

        pairs.add(_NavigatorPairDistance(
          navigatorA: _userNames[a.key] ?? a.key,
          navigatorB: _userNames[b.key] ?? b.key,
          distanceMeters: dist,
        ));
      }
    }

    pairs.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    return pairs;
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  String _formatTimeSince(Duration d) {
    if (d.inMinutes < 1) return 'עכשיו';
    if (d.inMinutes < 60) return '${d.inMinutes} דק\'';
    return '${d.inHours} שע\' ${d.inMinutes % 60} דק\'';
  }

  Widget _summaryChip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.grey[700]),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
      ],
    );
  }

  Widget _statChip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.grey[600]),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
      ],
    );
  }

  /// תווית קבוצה (צמד/חוליה/מאבטח) למנווט
  String? _getGroupLabel(String navigatorId) {
    final route = widget.navigation.routes[navigatorId];
    if (route == null || route.groupId == null) return null;
    final composition = widget.navigation.forceComposition;
    if (!composition.isGrouped) return null;
    final typeLabel = composition.type == 'pair'
        ? 'צמד'
        : (composition.type == 'squad' ? 'חוליה' : (composition.isGuard ? 'מאבטח' : 'קבוצה'));
    final groupIds = widget.navigation.routes.values
        .where((r) => r.groupId != null).map((r) => r.groupId!).toSet().toList()..sort();
    final groupNum = groupIds.indexOf(route.groupId!) + 1;
    return '$typeLabel $groupNum';
  }

  IconData _getStatusIcon(NavigatorLiveData data) {
    switch (data.personalStatus) {
      case NavigatorPersonalStatus.waiting:
        return Icons.hourglass_empty;
      case NavigatorPersonalStatus.active:
        return Icons.navigation;
      case NavigatorPersonalStatus.finished:
        return Icons.check_circle;
      case NavigatorPersonalStatus.noReception:
        return Icons.signal_wifi_off;
    }
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckpointRow(_CheckpointArrival arrival) {
    final cp = arrival.checkpoint;
    final punch = arrival.punch;
    final reached = arrival.reached;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            reached ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 18,
            color: reached ? Colors.green : Colors.grey,
          ),
          const SizedBox(width: 8),
          Text(
            '#${cp.sequenceNumber} ${cp.name}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: reached ? FontWeight.bold : FontWeight.normal,
              color: reached ? Colors.black : Colors.grey[600],
            ),
          ),
          const Spacer(),
          if (punch != null)
            Text(
              '${punch.punchTime.hour.toString().padLeft(2, '0')}:${punch.punchTime.minute.toString().padLeft(2, '0')}',
              style: const TextStyle(fontSize: 12, color: Colors.green),
            )
          else
            Text('---', style: TextStyle(fontSize: 12, color: Colors.grey[400])),
          if (punch?.distanceFromCheckpoint != null) ...[
            const SizedBox(width: 6),
            Text(
              '(${punch!.distanceFromCheckpoint!.toStringAsFixed(0)}מ\')',
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.navigation.name),
            const Text(
              'ניהול ניווט',
              style: TextStyle(fontSize: 14),
            ),
          ],
        ),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          tabs: [
            const Tab(icon: Icon(Icons.map), text: 'מפה'),
            const Tab(icon: Icon(Icons.table_chart), text: 'סטטוס'),
            Tab(
              icon: Badge(
                isLabelVisible: _activeAlerts.isNotEmpty ||
                    _extensionRequests.any((r) => r.status == ExtensionRequestStatus.pending),
                label: Text(
                  '${_activeAlerts.length + _extensionRequests.where((r) => r.status == ExtensionRequestStatus.pending).length}',
                  style: const TextStyle(fontSize: 10),
                ),
                child: const Icon(Icons.notifications),
              ),
              text: 'התראות',
            ),
            const Tab(icon: Icon(Icons.dashboard), text: 'דשבורד'),
          ],
        ),
        actions: [
          // ניווט כוכב — פתיחת נקודה הבאה לכולם
          if (_currentNavigation.navigationType == 'star')
            IconButton(
              icon: const Icon(Icons.star, color: Colors.amber),
              tooltip: 'פתח נקודה הבאה לכל מי שבמרכז',
              onPressed: _openStarPointForAllAtCenter,
            ),
          if (_emergencyActive)
            IconButton(
              icon: const Icon(Icons.crisis_alert, color: Colors.orange),
              tooltip: 'כבה מצב חירום',
              onPressed: _showDeactivateConfirmation,
            ),
          IconButton(
            icon: const Icon(Icons.campaign, color: Colors.red),
            tooltip: 'שידור חירום',
            onPressed: _showEmergencyBroadcastDialog,
          ),
          IconButton(
            icon: const Icon(Icons.local_hospital, color: Colors.red),
            tooltip: 'נווט לבית חולים',
            onPressed: _showNearestHospitalsDialog,
          ),
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'הגדרות ניווט',
            onPressed: _showGlobalSettingsSheet,
          ),
          IconButton(
            icon: const Icon(Icons.my_location),
            tooltip: 'דלג לנ.צ.',
            onPressed: _isJumpDialogOpen ? null : _showJumpToCoordinateDialog,
          ),
          IconButton(
            icon: const Icon(Icons.stop_circle),
            tooltip: 'סיום ניווט כללי',
            onPressed: _finishAllNavigation,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // באנר התראות חירום/תקינות/הארכות
                if (_activeAlerts.any((a) =>
                    a.type == AlertType.emergency ||
                    a.type == AlertType.healthCheckExpired) ||
                    _extensionRequests.any((r) => r.status == ExtensionRequestStatus.pending))
                  _buildAlertsBanner(),
                // פאנל אישורי קבלה — חירום
                if (_emergencyActive && _activeBroadcastId != null)
                  _buildAckPanel(
                    title: 'אישורי קבלת חירום',
                    acknowledgedBy: _acknowledgedBy,
                    color: Colors.red,
                    onResend: () => _resendToUnacknowledged(_activeBroadcastId!),
                  ),
                // פאנל אישורי ביטול
                if (!_emergencyActive && _cancelBroadcastId != null && _cancelAcknowledgedBy.length < _allEmergencyParticipants.length)
                  _buildAckPanel(
                    title: 'אישורי חזרה לשגרה',
                    acknowledgedBy: _cancelAcknowledgedBy,
                    color: Colors.green,
                    onResend: () => _resendCancelToUnacknowledged(_cancelBroadcastId!),
                  ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildMapView(),
                      _buildStatusView(),
                      _buildAlertsView(),
                      _buildDashboardView(),
                    ],
                  ),
                ),
                // ווקי טוקי
                if (widget.navigation.communicationSettings.walkieTalkieEnabled && _currentUser != null)
                  Builder(builder: (context) {
                    _voiceService ??= VoiceService();
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        VoiceMessagesPanel(
                          navigationId: widget.navigation.id,
                          currentUser: _currentUser!,
                          voiceService: _voiceService!,
                          isCommander: true,
                          enabled: true,
                          navigators: _navigatorData.entries
                              .map((e) => NavigatorInfo(
                                    id: e.key,
                                    name: _userNames[e.key] ?? e.key,
                                  ))
                              .toList(),
                        ),
                        SizedBox(height: MediaQuery.of(context).padding.bottom),
                      ],
                    );
                  }),
              ],
            ),
    );
  }

  Widget _buildMapView() {
    return Column(
      children: [
        // בקרת שכבות
        Container(
          padding: const EdgeInsets.all(8),
          color: Colors.grey[100],
          child: Column(
            children: [
              // מקרא סטטוסים
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _mapLegendItem('ממתין', Colors.grey),
                    _mapLegendItem('פעיל', Colors.green),
                    _mapLegendItem('GPS Plus', Colors.yellow.shade700),
                    _mapLegendItem('סיים', Colors.blue),
                    _mapLegendItem('ללא קליטה', Colors.orange),
                    _mapLegendItem('התרעה', Colors.red),
                  ],
                ),
              ),
              // בחירת מנווטים
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _navigatorData.entries.map((entry) {
                    final data = entry.value;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: FilterChip(
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_userNames[data.navigatorId] ?? data.navigatorId),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.circle,
                              size: 12,
                              color: _getNavigatorStatusColor(data),
                            ),
                          ],
                        ),
                        selected: _selectedNavigators[data.navigatorId] ?? false,
                        onSelected: (selected) {
                          setState(() {
                            _selectedNavigators[data.navigatorId] = selected;
                          });
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),

            ],
          ),
        ),

        // מפה
        Expanded(
          child: Stack(
            children: [
              MapWithTypeSelector(
            showTypeSelector: false,
            mapController: _mapController,
            initialMapType: MapConfig.resolveMapType(widget.navigation.displaySettings.defaultMap),
            options: MapOptions(
              initialCenter: widget.navigation.displaySettings.openingLat != null
                  ? LatLng(
                      widget.navigation.displaySettings.openingLat!,
                      widget.navigation.displaySettings.openingLng!,
                    )
                  : const LatLng(32.0853, 34.7818),
              initialZoom: 13.0,
              onTap: (tapPosition, point) {
                if (_measureMode) {
                  setState(() => _measurePoints.add(point));
                }
              },
            ),
            layers: [
              // גבול ג"ג
              if (_showGG && _boundaries.isNotEmpty)
                PolygonLayer(
                  polygons: _boundaries.expand((b) => b.allPolygons.map((poly) =>
                    Polygon(
                      points: poly.map((coord) => LatLng(coord.lat, coord.lng)).toList(),
                      color: Colors.black.withOpacity(0.2 * _ggOpacity),
                      borderColor: Colors.black,
                      borderStrokeWidth: b.strokeWidth,
                    ),
                  )).toList(),
                ),

              // נקודות ציון — עם סימון התחלה/סיום/ביניים
              if (_showNZ)
                MarkerLayer(
                  markers: _getCheckpointsForDisplay().map((cp) {
                    // זיהוי סוג נקודה: התחלה / סיום / ביניים (עם fallback להגדרות ניווט)
                    final startIds = <String>{};
                    final endIds = <String>{};
                    final waypointIds = <String>{};
                    final swapIds = <String>{};
                    for (final route in widget.navigation.routes.values) {
                      if (route.startPointId != null) startIds.add(route.startPointId!);
                      if (route.endPointId != null) endIds.add(route.endPointId!);
                      if (route.swapPointId != null) swapIds.add(route.swapPointId!);
                      waypointIds.addAll(route.waypointIds);
                    }
                    endIds.removeAll(swapIds);
                    // fallback — הגדרות ניווט (לפני חלוקת צירים)
                    if (widget.navigation.startPoint != null) startIds.add(widget.navigation.startPoint!);
                    if (widget.navigation.endPoint != null) endIds.add(widget.navigation.endPoint!);
                    if (widget.navigation.waypointSettings.enabled) {
                      for (final wp in widget.navigation.waypointSettings.waypoints) {
                        waypointIds.add(wp.checkpointId);
                      }
                    }

                    final isStart = startIds.contains(cp.id) || cp.isStart;
                    final isEnd = endIds.contains(cp.id) || cp.isEnd;
                    final isWaypoint = waypointIds.contains(cp.id);
                    final isSwapPoint = swapIds.contains(cp.id);

                    Color cpColor;
                    String letter;
                    if (isSwapPoint) {
                      cpColor = Colors.white;
                      letter = 'S';
                    } else if (isStart) {
                      cpColor = const Color(0xFF4CAF50); // ירוק — התחלה
                      letter = 'H';
                    } else if (isEnd) {
                      cpColor = const Color(0xFFF44336); // אדום — סיום
                      letter = 'F';
                    } else if (isWaypoint) {
                      cpColor = const Color(0xFFFFC107); // צהוב — ביניים
                      letter = 'B';
                    } else {
                      cpColor = Colors.blue;
                      letter = '';
                    }

                    return Marker(
                      point: LatLng(cp.coordinates!.lat, cp.coordinates!.lng),
                      width: 48,
                      height: 48,
                      child: GestureDetector(
                        onTap: () => _showCheckpointAssignees(cp, cpColor, letter),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.place,
                              color: isSwapPoint
                                  ? Colors.grey[700]!.withValues(alpha: _nzOpacity)
                                  : cpColor.withValues(alpha: _nzOpacity),
                              size: 32,
                            ),
                            Text(
                              '${cp.sequenceNumber}$letter',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: isSwapPoint ? Colors.grey[800] : cpColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),

              // מסלולים של מנווטים (גלובלי + פר-מנווט)
              ..._buildNavigatorTracks(),

              // צירים מתוכננים (פר-מנווט)
              ..._buildPlannedAxisLayers(),

              // דקירות
              if (_showPunches) ..._buildPunchMarkers(),

              // מיקומים נוכחיים של מנווטים
              ..._buildNavigatorMarkers(),

              // מיקום עצמי (מפקד)
              ..._buildSelfMarker(),

              // מפקדים אחרים
              ..._buildCommanderMarkers(),

              // התראות על המפה
              if (_showAlerts) ..._buildAlertMarkers(),
              ...MapControls.buildMeasureLayers(_measurePoints),
            ],
          ),
              MapControls(
                mapController: _mapController,
                layers: [
                  MapLayerConfig(
                    id: 'nz',
                    label: 'נקודות ציון',
                    color: Colors.blue,
                    visible: _showNZ,
                    opacity: _nzOpacity,
                    onVisibilityChanged: (v) => setState(() => _showNZ = v),
                    onOpacityChanged: (v) => setState(() => _nzOpacity = v),
                    child: _buildNzModeSelector(),
                  ),
                  MapLayerConfig(
                    id: 'gg',
                    label: 'גבול גזרה',
                    color: Colors.black,
                    visible: _showGG,
                    opacity: _ggOpacity,
                    onVisibilityChanged: (v) => setState(() => _showGG = v),
                    onOpacityChanged: (v) => setState(() => _ggOpacity = v),
                  ),
                  MapLayerConfig(
                    id: 'tracks',
                    label: 'מסלולים',
                    color: Colors.orange,
                    visible: _showTracks,
                    opacity: _tracksOpacity,
                    onVisibilityChanged: (v) => setState(() => _showTracks = v),
                    onOpacityChanged: (v) => setState(() => _tracksOpacity = v),
                  ),
                  MapLayerConfig(
                    id: 'punches',
                    label: 'דקירות',
                    color: Colors.green,
                    visible: _showPunches,
                    opacity: _punchesOpacity,
                    onVisibilityChanged: (v) => setState(() => _showPunches = v),
                    onOpacityChanged: (v) => setState(() => _punchesOpacity = v),
                  ),
                  MapLayerConfig(
                    id: 'alerts',
                    label: 'התראות',
                    color: Colors.red,
                    visible: _showAlerts,
                    opacity: 1.0,
                    onVisibilityChanged: (v) => setState(() => _showAlerts = v),
                    onOpacityChanged: (_) {},
                  ),
                ],
                measureMode: _measureMode,
                onMeasureModeChanged: (v) => setState(() {
                  _measureMode = v;
                  if (!v) _measurePoints.clear();
                }),
                measurePoints: _measurePoints,
                onMeasureClear: () => setState(() => _measurePoints.clear()),
                onMeasureUndo: () => setState(() {
                  if (_measurePoints.isNotEmpty) _measurePoints.removeLast();
                }),
                onFullscreen: () {
                  final camera = _mapController.camera;
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => FullscreenMapScreen(
                      title: 'ניהול ניווט',
                      initialCenter: camera.center,
                      initialZoom: camera.zoom,
                      layerConfigs: [
                        MapLayerConfig(
                          id: 'nz', label: 'נקודות ציון', color: Colors.blue,
                          visible: _showNZ, opacity: _nzOpacity,
                          onVisibilityChanged: (_) {},
                          child: _buildNzModeSelector(),
                        ),
                        MapLayerConfig(
                          id: 'gg', label: 'גבול גזרה', color: Colors.black,
                          visible: _showGG, opacity: _ggOpacity,
                          onVisibilityChanged: (_) {},
                        ),
                        MapLayerConfig(
                          id: 'tracks', label: 'מסלולים', color: Colors.orange,
                          visible: _showTracks, opacity: _tracksOpacity,
                          onVisibilityChanged: (_) {},
                        ),
                        MapLayerConfig(
                          id: 'punches', label: 'דקירות', color: Colors.green,
                          visible: _showPunches, opacity: _punchesOpacity,
                          onVisibilityChanged: (_) {},
                        ),
                        MapLayerConfig(
                          id: 'alerts', label: 'התראות', color: Colors.red,
                          visible: _showAlerts, opacity: 1.0,
                          onVisibilityChanged: (_) {},
                        ),
                      ],
                      layerBuilder: _buildFullscreenMapLayers,
                    ),
                  ));
                },
                onCenterSelf: _cycleSelfCenteringMode,
                centeringMode: _centeredNavigatorId == null ? _centeringMode : CenteringMode.off,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusNavigatorCard(String navigatorId) {
    final data = _navigatorData[navigatorId]!;
    final statusColor = _getNavigatorStatusColor(data);
    final arrivals = _getCheckpointArrivals(data);
    final reachedCount = arrivals.where((a) => a.reached).length;
    final totalCheckpoints = arrivals.length;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: data.hasActiveAlert
            ? const BorderSide(color: Colors.red, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _showEnhancedNavigatorDetails(navigatorId, data),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: icon + name + stop button
              Row(
                children: [
                  Icon(_getStatusIcon(data), color: statusColor, size: 28),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _userNames[navigatorId] ?? navigatorId,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (_getGroupLabel(navigatorId) != null)
                          Text(
                            _getGroupLabel(navigatorId)!,
                            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  if (data.isDisqualified)
                    Container(
                      margin: const EdgeInsets.only(left: 4),
                      constraints: const BoxConstraints(maxWidth: 120),
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        data.disqualificationReason ?? 'נפסל',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  if (data.hasActiveAlert)
                    const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(Icons.warning, color: Colors.red, size: 18),
                    ),
                  _buildNavigatorActionsMenu(navigatorId, data),
                ],
              ),
              // סטטוס כוכב
              if (_currentNavigation.navigationType == 'star') ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.star, size: 14, color: _starPhaseColor(_computeStarPhaseForNavigator(navigatorId))),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        _starStatusText(navigatorId),
                        style: TextStyle(
                          fontSize: 12,
                          color: _starPhaseColor(_computeStarPhaseForNavigator(navigatorId)),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              // Stats row (only if active or finished with track data)
              if (data.trackPoints.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    _statChip(
                      Icons.speed,
                      '${data.currentSpeedKmh.toStringAsFixed(1)} קמ"ש',
                    ),
                    _statChip(
                      Icons.route,
                      '${data.totalDistanceKm.toStringAsFixed(2)} ק"מ',
                    ),
                    _statChip(
                      Icons.timer,
                      _formatDuration(
                        () {
                          // מנווט שעדיין לא התחיל — אפס
                          if (data.trackStartedAt == null) return Duration.zero;
                          final endTime = data.trackEndedAt ?? DateTime.now();
                          final diff = endTime.difference(data.trackStartedAt!);
                          return diff.isNegative ? Duration.zero : diff;
                        }(),
                      ),
                    ),
                    if (totalCheckpoints > 0)
                      _statChip(
                        Icons.flag,
                        '$reachedCount/$totalCheckpoints נ"צ',
                      ),
                  ],
                ),
              ],
              // Last update
              if (data.lastUpdate != null) ...[
                const SizedBox(height: 4),
                Text(
                  'עדכון לפני ${_formatTimeSince(data.timeSinceLastUpdate)}',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavigatorGroup({
    required String groupKey,
    required String title,
    required IconData icon,
    required Color color,
    required List<String> navigatorIds,
    required Widget Function(String) itemBuilder,
  }) {
    final isExpanded = _navigatorGroupExpanded[groupKey] ?? false;
    final isLocked = _navigatorGroupLocked[groupKey] ?? false;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          InkWell(
            borderRadius: isExpanded
                ? const BorderRadius.vertical(top: Radius.circular(12))
                : BorderRadius.circular(12),
            onTap: () {
              if (!isLocked) {
                setState(() {
                  _navigatorGroupExpanded[groupKey] = !isExpanded;
                });
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: color.withOpacity(0.15),
                    radius: 18,
                    child: Icon(icon, color: color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '$title (${navigatorIds.length})',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _navigatorGroupLocked[groupKey] = !isLocked;
                        if (!isLocked) {
                          _navigatorGroupExpanded[groupKey] = true;
                        }
                      });
                    },
                    child: Icon(
                      isLocked ? Icons.lock : Icons.lock_open,
                      size: 20,
                      color: isLocked ? Colors.blue : Colors.grey[400],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.grey[400],
                    size: 24,
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: isExpanded
                ? Padding(
                    padding: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
                    child: Column(
                      children: navigatorIds.map(itemBuilder).toList(),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusView() {
    // ספירות סיכום
    final total = _navigatorData.length;
    final activeCount = _navigatorData.values
        .where((d) => d.personalStatus == NavigatorPersonalStatus.active)
        .length;
    final finishedCount = _navigatorData.values
        .where((d) => d.personalStatus == NavigatorPersonalStatus.finished)
        .length;
    final noReceptionCount = _navigatorData.values
        .where((d) => d.personalStatus == NavigatorPersonalStatus.noReception)
        .length;
    final alertCount = _activeAlerts.length;
    final distances = _getInterNavigatorDistances();

    final allIds = widget.navigation.sortByGroup(_navigatorData.keys).toList();
    final managers = _currentNavigation.permissions.managers.toSet();
    final commanderIds = <String>[];
    final navigatorIds = <String>[];
    for (final id in allIds) {
      if (managers.contains(id)) {
        commanderIds.add(id);
      } else {
        navigatorIds.add(id);
      }
    }
    final selectedSfIds = _currentNavigation.selectedSubFrameworkIds.toSet();
    final tree = _navigationTree;
    final groups = <String, List<String>>{};
    final ungrouped = <String>[];
    if (tree != null) {
      final relevantSfs = tree.subFrameworks.where((sf) => selectedSfIds.contains(sf.id)).toList();
      final assigned = <String>{};
      for (final sf in relevantSfs) {
        final sfNavs = navigatorIds.where((id) => sf.userIds.contains(id)).toList();
        if (sfNavs.isNotEmpty) {
          groups[sf.name] = sfNavs;
          assigned.addAll(sfNavs);
        }
      }
      ungrouped.addAll(navigatorIds.where((id) => !assigned.contains(id)));
    } else {
      ungrouped.addAll(navigatorIds);
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Summary bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).primaryColor.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Wrap(
            spacing: 16,
            runSpacing: 4,
            alignment: WrapAlignment.center,
            children: [
              _summaryChip(Icons.people, '$total מנווטים'),
              _summaryChip(Icons.navigation, '$activeCount פעילים'),
              _summaryChip(Icons.check_circle, '$finishedCount סיימו'),
              if (noReceptionCount > 0)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.signal_wifi_off, size: 16, color: Colors.orange),
                    const SizedBox(width: 4),
                    Text(
                      '$noReceptionCount ללא קליטה',
                      style: const TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              if (alertCount > 0)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.warning, size: 16, color: Colors.red),
                    const SizedBox(width: 4),
                    Text(
                      '$alertCount התראות',
                      style: const TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // מרחקים בין מנווטים
        if (distances.isNotEmpty)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ExpansionTile(
              leading: const Icon(Icons.social_distance, size: 20),
              title: const Text('מרחקים בין מנווטים', style: TextStyle(fontSize: 14)),
              initiallyExpanded: false,
              children: distances.map((pair) {
                final isClose = pair.distanceMeters < 200;
                return ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: Icon(
                    isClose ? Icons.warning : Icons.straighten,
                    size: 18,
                    color: isClose ? Colors.red : Colors.grey,
                  ),
                  title: Text(
                    '${pair.navigatorA} ↔ ${pair.navigatorB}',
                    style: const TextStyle(fontSize: 13),
                  ),
                  trailing: Text(
                    pair.displayDistance,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isClose ? Colors.red : Colors.black87,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

        // מפקדים (ללא קיבוץ)
        ...commanderIds.map((id) => _buildStatusNavigatorCard(id)),

        // כרטיסי מנווטים מקובצים לפי תת-מסגרת
        ...groups.entries.map((entry) => _buildNavigatorGroup(
          groupKey: entry.key,
          title: entry.key,
          icon: Icons.group,
          color: Colors.indigo,
          navigatorIds: entry.value,
          itemBuilder: (id) => _buildStatusNavigatorCard(id),
        )),

        // מנווטים ללא קבוצה
        if (ungrouped.isNotEmpty)
          _buildNavigatorGroup(
            groupKey: '__ungrouped__',
            title: 'ללא תת-מסגרת',
            icon: Icons.person_outline,
            color: Colors.grey,
            navigatorIds: ungrouped,
            itemBuilder: (id) => _buildStatusNavigatorCard(id),
          ),
      ],
    );
  }

  /// בניית שכבות מפה למסך מלא — משתמש בהגדרות visibility/opacity מהמסך המלא
  List<Widget> _buildFullscreenMapLayers(
      Map<String, bool> visibility, Map<String, double> opacity) {
    final showGG = visibility['gg'] ?? true;
    final showNZ = visibility['nz'] ?? true;
    final showTracks = visibility['tracks'] ?? true;
    final showPunches = visibility['punches'] ?? true;
    final showAlerts = visibility['alerts'] ?? true;
    final ggOp = opacity['gg'] ?? _ggOpacity;
    final nzOp = opacity['nz'] ?? _nzOpacity;

    return [
      // גבול ג"ג
      if (showGG && _boundaries.isNotEmpty)
        PolygonLayer(
          polygons: _boundaries.expand((b) => b.allPolygons.map((poly) =>
            Polygon(
              points: poly.map((coord) => LatLng(coord.lat, coord.lng)).toList(),
              color: Colors.black.withOpacity(0.2 * ggOp),
              borderColor: Colors.black,
              borderStrokeWidth: b.strokeWidth,
            ),
          )).toList(),
        ),

      // נקודות ציון
      if (showNZ)
        MarkerLayer(
          markers: _getCheckpointsForDisplay().map((cp) {
            final startIds = <String>{};
            final endIds = <String>{};
            final waypointIds = <String>{};
            final swapIds = <String>{};
            for (final route in widget.navigation.routes.values) {
              if (route.startPointId != null) startIds.add(route.startPointId!);
              if (route.endPointId != null) endIds.add(route.endPointId!);
              if (route.swapPointId != null) swapIds.add(route.swapPointId!);
              waypointIds.addAll(route.waypointIds);
            }
            endIds.removeAll(swapIds);
            for (final wp in widget.navigation.waypointSettings.waypoints) {
              waypointIds.add(wp.checkpointId);
            }

            final isStart = startIds.contains(cp.id) || cp.isStart;
            final isEnd = endIds.contains(cp.id) || cp.isEnd;
            final isWaypoint = waypointIds.contains(cp.id);
            final isSwapPoint = swapIds.contains(cp.id);

            Color cpColor;
            String letter;
            if (isSwapPoint) {
              cpColor = Colors.white;
              letter = 'S';
            } else if (isStart) {
              cpColor = const Color(0xFF4CAF50);
              letter = 'H';
            } else if (isEnd) {
              cpColor = const Color(0xFFF44336);
              letter = 'F';
            } else if (isWaypoint) {
              cpColor = const Color(0xFFFFC107);
              letter = 'B';
            } else {
              cpColor = Colors.blue;
              letter = '';
            }

            return Marker(
              point: LatLng(cp.coordinates!.lat, cp.coordinates!.lng),
              width: 48,
              height: 48,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.place,
                    color: isSwapPoint
                        ? Colors.grey[700]!.withValues(alpha: nzOp)
                        : cpColor.withValues(alpha: nzOp),
                    size: 32,
                  ),
                  Text(
                    '${cp.sequenceNumber}$letter',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isSwapPoint ? Colors.grey[800] : cpColor,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),

      // מסלולים
      if (showTracks)
        ..._buildNavigatorTracks(opacityOverride: opacity['tracks']),

      // צירים מתוכננים
      ..._buildPlannedAxisLayers(),

      // דקירות
      if (showPunches)
        ..._buildPunchMarkers(opacityOverride: opacity['punches']),

      // מיקומים נוכחיים של מנווטים
      ..._buildNavigatorMarkers(),

      // מיקום עצמי (מפקד)
      ..._buildSelfMarker(),

      // מפקדים אחרים
      ..._buildCommanderMarkers(),

      // התראות
      if (showAlerts) ..._buildAlertMarkers(),
    ];
  }

  List<Widget> _buildNavigatorTracks({double? opacityOverride}) {
    List<Widget> tracks = [];
    final tracksOp = opacityOverride ?? _tracksOpacity;

    for (final entry in _navigatorData.entries) {
      final navigatorId = entry.key;
      final data = entry.value;

      if (!(_selectedNavigators[navigatorId] ?? false)) continue;
      if (data.trackPoints.isEmpty) continue;

      // master switch + per-navigator AND
      if (!_showTracks) continue;
      if (!(_showNavigatorTrack[navigatorId] ?? false)) continue;

      final points = data.trackPoints
          .map((tp) => LatLng(tp.coordinate.lat, tp.coordinate.lng))
          .toList();

      tracks.add(
        PolylineLayer(
          polylines: [
            Polyline(
              points: points,
              strokeWidth: 3,
              color: _getTrackColor(data.personalStatus).withValues(alpha: tracksOp),
            ),
          ],
        ),
      );
    }

    return tracks;
  }

  List<Widget> _buildPlannedAxisLayers() {
    List<Widget> layers = [];

    for (final entry in _navigatorData.entries) {
      final navigatorId = entry.key;
      if (!(_showPlannedAxis[navigatorId] ?? false)) continue;

      final route = widget.navigation.routes[navigatorId];
      if (route == null || route.plannedPath.isEmpty) continue;

      final points = route.plannedPath
          .map((c) => LatLng(c.lat, c.lng))
          .toList();

      layers.add(
        PolylineLayer(
          polylines: [
            Polyline(
              points: points,
              strokeWidth: 2.5,
              color: Colors.purple.withValues(alpha: 0.7),
            ),
          ],
        ),
      );
    }

    return layers;
  }

  List<Widget> _buildPunchMarkers({double? opacityOverride}) {
    List<Widget> markers = [];
    final punchesOp = opacityOverride ?? _punchesOpacity;

    for (final entry in _navigatorData.entries) {
      final navigatorId = entry.key;
      final data = entry.value;

      if (!(_selectedNavigators[navigatorId] ?? false)) continue;
      if (!(_showNavigatorTrack[navigatorId] ?? false)) continue;

      final visiblePunches = data.punches.where((p) => !p.isDeleted).toList();
      final navName = _userNames[navigatorId] ?? navigatorId;
      final punchMarkers = <Marker>[];
      for (int i = 0; i < visiblePunches.length; i++) {
        final punch = visiblePunches[i];
        Color color;
        IconData icon;
        if (punch.isSuperseded) {
          color = Colors.grey;
          icon = Icons.flag_outlined;
        } else if (punch.isApproved) {
          color = Colors.green;
          icon = Icons.flag;
        } else if (punch.isRejected) {
          color = Colors.red;
          icon = Icons.flag;
        } else {
          color = Colors.orange;
          icon = Icons.flag;
        }

        punchMarkers.add(Marker(
          point: LatLng(punch.punchLocation.lat, punch.punchLocation.lng),
          width: 90,
          height: 45,
          child: Opacity(
            opacity: punchesOp,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 22),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    () {
                      final cp = _checkpoints.where((c) => c.id == punch.checkpointId).firstOrNull;
                      final seqPart = cp != null ? '${cp.sequenceNumber}-' : '';
                      return '$seqPart$navName (${i + 1})';
                    }(),
                    style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ));
      }

      if (punchMarkers.isNotEmpty) {
        markers.add(MarkerLayer(markers: punchMarkers));
      }
    }

    return markers;
  }

  // ===========================================================================
  // סמני מפקדים על המפה
  // ===========================================================================

  /// סמן מיקום עצמי של המפקד — עיגול שקוף עם גבול כחול + שם
  List<Widget> _buildSelfMarker() {
    if (_selfPosition == null || _currentUser == null) return [];
    return [
      MarkerLayer(markers: [
        Marker(
          point: _selfPosition!,
          width: 70,
          height: 55,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.blue.withValues(alpha: 0.15),
                  border: Border.all(color: Colors.blue, width: 2.5),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _currentUser!.fullName,
                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.blue),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ]),
    ];
  }

  /// סמני מפקדים אחרים — ריבוע שקוף עם גבול כתום + שם
  List<Widget> _buildCommanderMarkers() {
    final markers = _otherCommanders.values.map((cmd) => Marker(
      point: cmd.position,
      width: 70,
      height: 55,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: Colors.orange.withValues(alpha: 0.15),
              border: Border.all(color: Colors.orange, width: 2.5),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              cmd.name,
              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.orange),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    )).toList();
    return markers.isNotEmpty ? [MarkerLayer(markers: markers)] : [];
  }

  List<Widget> _buildNavigatorMarkers() {
    List<Marker> markers = [];

    for (final entry in _navigatorData.entries) {
      final navigatorId = entry.key;
      final data = entry.value;

      if (!(_selectedNavigators[navigatorId] ?? false)) continue;
      if (data.currentPosition == null) continue;

      // === צבע מרקר לפי סטטוס וזמן ===
      Color markerColor;
      double markerOpacity = 1.0;
      final bool isFinished = data.personalStatus == NavigatorPersonalStatus.finished;

      if (isFinished) {
        // מנווט שסיים — תמיד כחול, אף פעם לא נעלם
        markerColor = Colors.blue;
      } else {
        // מנווט פעיל — staleness משפיע על צבע בלבד
        final lastUpdate = data.lastUpdate;
        final elapsed = lastUpdate != null
            ? DateTime.now().difference(lastUpdate)
            : Duration.zero;

        if (elapsed.inMinutes >= 10) {
          markerColor = Colors.grey;
          markerOpacity = 0.6;
        } else if (elapsed.inMinutes >= 2) {
          markerColor = Colors.orange;
        } else {
          markerColor = _getNavigatorStatusColor(data);
        }
      }

      final isCentered = (_centeredNavigatorId == navigatorId && _centeringMode != CenteringMode.off)
          || _oneTimeCenteredNavigatorId == navigatorId;

      Widget markerChild = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: markerColor.withValues(alpha: 0.15),
              border: Border.all(color: markerColor, width: 2.5),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: markerColor, width: 1.5),
            ),
            child: Text(
              _userNames[navigatorId] ?? navigatorId,
              style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );

      // טבעת כחולה זוהרת למנווט נעקב
      if (isCentered) {
        markerChild = Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.blue, width: 3),
            color: Colors.blue.withValues(alpha: 0.1),
          ),
          padding: const EdgeInsets.all(2),
          child: markerChild,
        );
      }

      markers.add(
        Marker(
          point: data.currentPosition!,
          width: isCentered ? 68 : 60,
          height: isCentered ? 68 : 60,
          child: Builder(
            builder: (markerContext) {
              return GestureDetector(
                onSecondaryTapDown: (details) {
                  _showDesktopTacticalMenu(markerContext, details.globalPosition, navigatorId, data);
                },
                onLongPressStart: (details) {
                  HapticFeedback.mediumImpact();
                  _showMobileTacticalSheet(navigatorId, data);
                },
                child: markerOpacity < 1.0
                    ? Opacity(opacity: markerOpacity, child: markerChild)
                    : markerChild,
              );
            },
          ),
        ),
      );
    }

    return markers.isNotEmpty ? [MarkerLayer(markers: markers)] : [];
  }

  Color _getNavigatorStatusColor(NavigatorLiveData data) {
    if (data.hasActiveAlert) return Colors.red;
    switch (data.personalStatus) {
      case NavigatorPersonalStatus.active:
        return data.isGpsPlusFix ? Colors.yellow.shade700 : Colors.green;
      case NavigatorPersonalStatus.finished:
        return Colors.blue;
      case NavigatorPersonalStatus.noReception:
        return Colors.orange;
      case NavigatorPersonalStatus.waiting:
        return Colors.grey;
    }
  }

  Widget _mapLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 10, color: color),
        const SizedBox(width: 3),
        Text(label, style: const TextStyle(fontSize: 10)),
      ],
    );
  }

  Color _getTrackColor(NavigatorPersonalStatus status) {
    switch (status) {
      case NavigatorPersonalStatus.active:
        return Colors.green;
      case NavigatorPersonalStatus.finished:
        return Colors.blue;
      case NavigatorPersonalStatus.noReception:
        return Colors.orange;
      case NavigatorPersonalStatus.waiting:
        return Colors.grey;
    }
  }

  void _showCheckpointAssignees(Checkpoint cp, Color cpColor, String letter) {
    // מצא את כל המנווטים שקיבלו את הנקודה הזאת
    final assignees = <String>[];
    for (final entry in widget.navigation.routes.entries) {
      final navigatorId = entry.key;
      final route = entry.value;
      if (route.checkpointIds.contains(cp.id) ||
          route.startPointId == cp.id ||
          route.endPointId == cp.id) {
        assignees.add(_userNames[navigatorId] ?? navigatorId);
      }
    }
    // גם נקודות ביניים משותפות
    for (final entry in widget.navigation.routes.entries) {
      final navigatorId = entry.key;
      final route = entry.value;
      if (route.waypointIds.contains(cp.id) &&
          !assignees.contains(_userNames[navigatorId] ?? navigatorId)) {
        assignees.add(_userNames[navigatorId] ?? navigatorId);
      }
    }

    final typeName = letter == 'H'
        ? 'נקודת התחלה'
        : letter == 'S'
            ? 'נקודת החלפה'
            : letter == 'F'
                ? 'נקודת סיום'
                : letter == 'B'
                    ? 'נקודת ביניים'
                    : 'נקודה';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.place, color: cpColor, size: 28),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${cp.name.isNotEmpty ? cp.name : 'נ.צ ${cp.sequenceNumber}'} ($typeName)',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (assignees.isEmpty)
              const Text('לא שויכו מנווטים לנקודה זו')
            else ...[
              Text(
                'מנווטים שקיבלו את הנקודה (${assignees.length}):',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...assignees.map((name) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    const Icon(Icons.person, size: 18, color: Colors.blueGrey),
                    const SizedBox(width: 6),
                    Expanded(child: Text(name)),
                  ],
                ),
              )),
            ],
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            const Text('נווט לנקודה:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _navigateToCheckpoint(cp, 'waze'),
                    icon: const Icon(Icons.navigation, size: 18),
                    label: const Text('Waze'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _navigateToCheckpoint(cp, 'google_maps'),
                    icon: const Icon(Icons.map, size: 18),
                    label: const Text('Google Maps'),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('סגור'),
          ),
        ],
      ),
    );
  }

  void _showNearestHospitalsDialog() {
    if (_selfPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('אין מיקום GPS זמין')),
      );
      return;
    }
    final myCoord = Coordinate(
      lat: _selfPosition!.latitude,
      lng: _selfPosition!.longitude,
      utm: '',
    );
    final sorted = List<Hospital>.from(kIsraelHospitals)
      ..sort((a, b) {
        final da = GeometryUtils.distanceBetweenMeters(
          myCoord, Coordinate(lat: a.lat, lng: a.lng, utm: ''));
        final db = GeometryUtils.distanceBetweenMeters(
          myCoord, Coordinate(lat: b.lat, lng: b.lng, utm: ''));
        return da.compareTo(db);
      });
    final top3 = sorted.take(3).toList();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('בתי חולים קרובים'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: top3.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (_, i) {
              final h = top3[i];
              final distMeters = GeometryUtils.distanceBetweenMeters(
                myCoord, Coordinate(lat: h.lat, lng: h.lng, utm: ''));
              final distKm = (distMeters / 1000).toStringAsFixed(1);
              return ListTile(
                leading: Icon(
                  h.isTraumaCenter ? Icons.star : Icons.local_hospital,
                  color: h.isTraumaCenter ? Colors.amber : Colors.red,
                ),
                title: Text(h.name),
                subtitle: Text('${h.classification} · $distKm ק״מ'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showHospitalNavigationOptions(h);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('סגור'),
          ),
        ],
      ),
    );
  }

  void _showJumpToCoordinateDialog() {
    if (_isJumpDialogOpen) return;
    _isJumpDialogOpen = true;

    final eastingController = TextEditingController();
    final northingController = TextEditingController();
    final latController = TextEditingController();
    final lngController = TextEditingController();
    bool isUtmMode = true;
    String? errorText;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('דלג לנקודת ציון'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('UTM')),
                  ButtonSegment(value: false, label: Text('גאוגרפי')),
                ],
                selected: {isUtmMode},
                onSelectionChanged: (v) {
                  setDialogState(() {
                    isUtmMode = v.first;
                    errorText = null;
                    eastingController.clear();
                    northingController.clear();
                    latController.clear();
                    lngController.clear();
                  });
                },
              ),
              const SizedBox(height: 16),
              if (isUtmMode) ...[
                TextField(
                  controller: eastingController,
                  textDirection: TextDirection.ltr,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Easting (6 ספרות)',
                    hintText: '123456',
                  ),
                  maxLength: 6,
                ),
                TextField(
                  controller: northingController,
                  textDirection: TextDirection.ltr,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Northing (6 ספרות)',
                    hintText: '789012',
                  ),
                  maxLength: 6,
                ),
              ] else ...[
                TextField(
                  controller: latController,
                  textDirection: TextDirection.ltr,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'קו רוחב (Latitude)',
                    hintText: '31.7767',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: lngController,
                  textDirection: TextDirection.ltr,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'קו אורך (Longitude)',
                    hintText: '35.2345',
                  ),
                ),
              ],
              if (errorText != null) ...[
                const SizedBox(height: 8),
                Text(errorText!, style: const TextStyle(color: Colors.red, fontSize: 13)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ביטול'),
            ),
            FilledButton(
              onPressed: () {
                LatLng? target;
                if (isUtmMode) {
                  final e = eastingController.text.trim();
                  final n = northingController.text.trim();
                  if (e.length != 6 || n.length != 6 ||
                      !RegExp(r'^\d{6}$').hasMatch(e) ||
                      !RegExp(r'^\d{6}$').hasMatch(n)) {
                    setDialogState(() => errorText = 'יש להזין 6 ספרות בכל שדה');
                    return;
                  }
                  try {
                    target = UtmConverter.utmToLatLng('$e$n');
                  } catch (_) {
                    setDialogState(() => errorText = 'שגיאה בהמרת UTM');
                    return;
                  }
                } else {
                  final lat = double.tryParse(latController.text.trim());
                  final lng = double.tryParse(lngController.text.trim());
                  if (lat == null || lng == null) {
                    setDialogState(() => errorText = 'יש להזין מספרים תקינים');
                    return;
                  }
                  target = LatLng(lat, lng);
                }
                if (target.latitude < 29 || target.latitude > 34 ||
                    target.longitude < 33 || target.longitude > 37) {
                  setDialogState(() => errorText = 'הקואורדינטה מחוץ לתחום ישראל');
                  return;
                }
                Navigator.pop(ctx);
                _tabController.animateTo(0);
                final zoom = _mapController.camera.zoom >= 15
                    ? _mapController.camera.zoom
                    : 15.0;
                Future.delayed(const Duration(milliseconds: 300), () {
                  if (mounted) {
                    _mapController.move(target!, zoom);
                  }
                });
              },
              child: const Text('דלג'),
            ),
          ],
        ),
      ),
    ).then((_) => _isJumpDialogOpen = false);
  }

  void _showHospitalNavigationOptions(Hospital hospital) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('ניווט ל${hospital.name}'),
        content: const Text('בחר אפליקציית ניווט:'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.directions_car),
            label: const Text('Waze'),
            onPressed: () {
              Navigator.pop(ctx);
              _launchHospitalNavigation(hospital, 'waze');
            },
          ),
          TextButton.icon(
            icon: const Icon(Icons.map),
            label: const Text('Google Maps'),
            onPressed: () {
              Navigator.pop(ctx);
              _launchHospitalNavigation(hospital, 'google_maps');
            },
          ),
        ],
      ),
    );
  }

  Future<void> _launchHospitalNavigation(Hospital hospital, String app) async {
    final Uri uri;
    if (app == 'waze') {
      uri = Uri.parse('https://waze.com/ul?ll=${hospital.lat},${hospital.lng}&navigate=yes');
    } else {
      uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${hospital.lat},${hospital.lng}&travelmode=driving');
    }
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('לא ניתן לפתוח ${app == 'waze' ? 'Waze' : 'Google Maps'}')),
        );
      }
    }
  }

  Future<void> _navigateToCheckpoint(Checkpoint cp, String app) async {
    double? lat;
    double? lng;
    if (cp.coordinates != null) {
      lat = cp.coordinates!.lat;
      lng = cp.coordinates!.lng;
    } else if (cp.polygonCoordinates != null && cp.polygonCoordinates!.isNotEmpty) {
      // עבור פוליגון — מרכז הנקודות
      lat = cp.polygonCoordinates!.map((c) => c.lat).reduce((a, b) => a + b) / cp.polygonCoordinates!.length;
      lng = cp.polygonCoordinates!.map((c) => c.lng).reduce((a, b) => a + b) / cp.polygonCoordinates!.length;
    }
    if (lat == null || lng == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('אין קואורדינטות לנקודה זו')),
        );
      }
      return;
    }
    final Uri uri;
    if (app == 'waze') {
      uri = Uri.parse('https://waze.com/ul?ll=$lat,$lng&navigate=yes');
    } else {
      uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');
    }
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('לא ניתן לפתוח ${app == 'waze' ? 'Waze' : 'Google Maps'}')),
        );
      }
    }
  }

  // === תפריט טקטי ===

  void _removeTacticalMenu() {
    _tacticalMenuEntry?.remove();
    _tacticalMenuEntry = null;
    _openTacticalNavigatorId = null;
  }

  Future<void> _navigateToNavigator(LatLng position, String app) async {
    final lat = position.latitude;
    final lng = position.longitude;
    final Uri uri;
    if (app == 'waze') {
      uri = Uri.parse('https://waze.com/ul?ll=$lat,$lng&navigate=yes');
    } else {
      uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');
    }
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('לא ניתן לפתוח ${app == 'waze' ? 'Waze' : 'Google Maps'}')),
        );
      }
    }
  }

  Widget _tacticalHeader(String navigatorId, NavigatorLiveData data) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _getNavigatorStatusColor(data),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _userNames[navigatorId] ?? navigatorId,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tacticalItem({
    required IconData icon,
    required String text,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: Colors.greenAccent.withValues(alpha: 0.1),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: Colors.greenAccent, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildTacticalMenuItems(String navigatorId, NavigatorLiveData data, {required bool dismissOnTap}) {
    void dismiss() {
      if (dismissOnTap) _removeTacticalMenu();
    }

    final trackOn = _showNavigatorTrack[navigatorId] ?? false;

    return [
      _tacticalItem(
        icon: trackOn ? Icons.visibility_off : Icons.visibility,
        text: trackOn ? 'הסתר מסלול בפועל' : 'הצג מסלול בפועל',
        onTap: () {
          dismiss();
          setState(() {
            _showNavigatorTrack[navigatorId] = !trackOn;
          });
        },
      ),
      _tacticalItem(
        icon: Icons.gps_fixed,
        text: 'עקוב',
        onTap: () {
          dismiss();
          _cycleNavigatorCenteringMode(navigatorId);
        },
      ),
      Opacity(
        opacity: data.currentPosition != null ? 1.0 : 0.4,
        child: _tacticalItem(
          icon: Icons.navigation,
          text: 'נווט ב-Waze',
          onTap: data.currentPosition != null
              ? () { dismiss(); _navigateToNavigator(data.currentPosition!, 'waze'); }
              : null,
        ),
      ),
      Opacity(
        opacity: data.currentPosition != null ? 1.0 : 0.4,
        child: _tacticalItem(
          icon: Icons.map,
          text: 'נווט ב-Google Maps',
          onTap: data.currentPosition != null
              ? () { dismiss(); _navigateToNavigator(data.currentPosition!, 'google'); }
              : null,
        ),
      ),
      const Divider(color: Colors.white24, height: 1),
      _tacticalItem(
        icon: Icons.info_outline,
        text: 'פרטי מנווט',
        onTap: () {
          dismiss();
          _showEnhancedNavigatorDetails(navigatorId, data);
        },
      ),
    ];
  }

  void _showDesktopTacticalMenu(BuildContext markerContext, Offset position, String navigatorId, NavigatorLiveData data) {
    _removeTacticalMenu();

    if (!_navigatorData.containsKey(navigatorId)) return;

    _openTacticalNavigatorId = navigatorId;

    const double menuWidth = 220;
    const double menuHeight = 310;
    final screenSize = MediaQuery.of(markerContext).size;
    final left = position.dx.clamp(8.0, screenSize.width - menuWidth - 8.0);
    final top = position.dy.clamp(8.0, screenSize.height - menuHeight - 8.0);

    _tacticalMenuEntry = OverlayEntry(
      builder: (overlayContext) {
        return Stack(
          children: [
            // שכבת רקע שקופה לסגירה בלחיצה
            Positioned.fill(
              child: GestureDetector(
                onTap: _removeTacticalMenu,
                behavior: HitTestBehavior.opaque,
                child: const SizedBox.expand(),
              ),
            ),
            // ESC dismiss
            Positioned.fill(
              child: FocusScope(
                autofocus: true,
                child: Focus(
                  autofocus: true,
                  onKeyEvent: (node, event) {
                    if (event.logicalKey == LogicalKeyboardKey.escape) {
                      _removeTacticalMenu();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: const SizedBox.shrink(),
                ),
              ),
            ),
            // התפריט עצמו
            Positioned(
              left: left,
              top: top,
              child: _AnimatedTacticalContainer(
                child: Container(
                  width: menuWidth,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.5), width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!_navigatorData.containsKey(navigatorId))
                          const SizedBox.shrink()
                        else ...[
                          _tacticalHeader(navigatorId, _navigatorData[navigatorId]!),
                          const Divider(color: Colors.white24, height: 1),
                          ..._buildTacticalMenuItems(navigatorId, _navigatorData[navigatorId]!, dismissOnTap: true),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(markerContext).insert(_tacticalMenuEntry!);
  }

  void _showMobileTacticalSheet(String navigatorId, NavigatorLiveData data) {
    if (!_navigatorData.containsKey(navigatorId)) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1E1E1E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // drag handle
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                if (!_navigatorData.containsKey(navigatorId))
                  const SizedBox.shrink()
                else ...[
                  _tacticalHeader(navigatorId, _navigatorData[navigatorId]!),
                  const Divider(color: Colors.white24, height: 1),
                  ..._buildTacticalMenuItems(navigatorId, _navigatorData[navigatorId]!, dismissOnTap: false).map(
                    (item) {
                      if (item is Opacity || item is Divider) return item;
                      // עטיפת כל פריט כדי לסגור את ה-sheet אחרי לחיצה
                      if (item is Material) {
                        final inkWell = (item.child as InkWell);
                        final originalOnTap = inkWell.onTap;
                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: originalOnTap != null
                                ? () { Navigator.pop(sheetContext); originalOnTap(); }
                                : null,
                            child: inkWell.child,
                          ),
                        );
                      }
                      return item;
                    },
                  ),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showEnhancedNavigatorDetails(String navigatorId, NavigatorLiveData data) {
    final route = widget.navigation.routes[navigatorId];
    final hasPlannedPath = route != null && route.plannedPath.isNotEmpty && route.isApproved;
    Timer? sheetRefreshTimer;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            // רענון אוטומטי כל 2 שניות
            sheetRefreshTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
              if (ctx.mounted) setSheetState(() {});
            });
            final liveData = _navigatorData[navigatorId] ?? data;
            final arrivals = _getCheckpointArrivals(liveData);
            return DraggableScrollableSheet(
              initialChildSize: 0.65,
              minChildSize: 0.3,
              maxChildSize: 0.9,
              expand: false,
              builder: (_, scrollController) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ListView(
                    controller: scrollController,
                    children: [
                      // ידית גרירה
                      Center(
                        child: Container(
                          margin: const EdgeInsets.only(top: 8, bottom: 12),
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),

                      // 1. כותרת
                      Row(
                        children: [
                          Icon(_getStatusIcon(liveData), color: _getNavigatorStatusColor(liveData), size: 28),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_userNames[navigatorId] ?? navigatorId, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                Text(liveData.personalStatus.displayName, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                              ],
                            ),
                          ),
                          if (liveData.hasActiveAlert)
                            const Icon(Icons.warning, color: Colors.red, size: 22),
                          _buildNavigatorActionsMenu(navigatorId, liveData,
                            onBeforeAction: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                      // באנר סיבת פסילה
                      if (liveData.isDisqualified) ...[
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.red[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red[300]!),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.block, color: Colors.red[700], size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  liveData.disqualificationReason ?? 'נפסל',
                                  style: TextStyle(
                                    color: Colors.red[900],
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // באנר ברבור פעיל (אם יש)
                      ..._buildNavigatorBarburSection(navigatorId),

                      // סטטוס כוכב — פירוט בבוטום שיט
                      if (_currentNavigation.navigationType == 'star') ...[
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: _starPhaseColor(_computeStarPhaseForNavigator(navigatorId)).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: _starPhaseColor(_computeStarPhaseForNavigator(navigatorId)).withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.star, color: _starPhaseColor(_computeStarPhaseForNavigator(navigatorId)), size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _starStatusText(navigatorId),
                                  style: TextStyle(
                                    color: _starPhaseColor(_computeStarPhaseForNavigator(navigatorId)),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const Divider(height: 20),

                      // 2. סטטוס מכשיר
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _deviceChip(
                            icon: liveData.isGpsPlusFix ? Icons.cell_tower : Icons.gps_fixed,
                            label: liveData.isGpsPlusFix ? 'GPS Plus' : 'GPS',
                            color: liveData.isGpsPlusFix ? Colors.yellow.shade700 : Colors.green,
                          ),
                          _deviceChip(
                            icon: liveData.personalStatus == NavigatorPersonalStatus.noReception
                                ? Icons.signal_wifi_off
                                : Icons.signal_cellular_alt,
                            label: liveData.personalStatus == NavigatorPersonalStatus.noReception ? 'אין קליטה' : 'קליטה',
                            color: liveData.personalStatus == NavigatorPersonalStatus.noReception ? Colors.red : Colors.green,
                          ),
                          _deviceChip(
                            icon: liveData.batteryLevel != null
                                ? (liveData.batteryLevel! > 50
                                    ? Icons.battery_full
                                    : liveData.batteryLevel! > 20
                                        ? Icons.battery_3_bar
                                        : Icons.battery_alert)
                                : Icons.battery_unknown,
                            label: liveData.batteryLevel != null
                                ? '${liveData.batteryLevel}%'
                                : 'N/A',
                            color: liveData.batteryLevel != null
                                ? (liveData.batteryLevel! > 50
                                    ? Colors.green
                                    : liveData.batteryLevel! > 20
                                        ? Colors.orange
                                        : Colors.red)
                                : Colors.grey,
                          ),
                          _deviceChip(
                            icon: Icons.do_not_disturb_on,
                            label: liveData.hasDNDPermission ? 'DND' : 'אין DND',
                            color: liveData.hasDNDPermission ? Colors.green : Colors.red,
                          ),
                          if (widget.navigation.communicationSettings.walkieTalkieEnabled) ...[
                            _deviceChip(
                              icon: Icons.mic,
                              label: liveData.hasMicrophonePermission ? 'מיקרופון' : 'אין מיקרופון',
                              color: liveData.hasMicrophonePermission ? Colors.green : Colors.red,
                            ),
                            _deviceChip(
                              icon: Icons.phone_android,
                              label: liveData.hasPhonePermission ? 'טלפון' : 'אין הרשאת טלפון',
                              color: liveData.hasPhonePermission ? Colors.green : Colors.red,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),

                      // 3. מרכוז מפה
                      if (liveData.currentPosition != null) ...[
                        const Text('מרכוז מפה', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: Icon(
                                  _centeredNavigatorId == navigatorId && _centeringMode != CenteringMode.off
                                      ? Icons.gps_fixed : Icons.gps_not_fixed,
                                  size: 18,
                                ),
                                label: Text(
                                  _centeredNavigatorId == navigatorId && _centeringMode != CenteringMode.off
                                      ? 'עוקב (${_centeringMode == CenteringMode.northLocked ? 'צפון' : 'כיוון'})'
                                      : 'עקוב',
                                ),
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _tabController.animateTo(0);
                                  // עיכוב — ממתין שה-sheet ייסגר והטאב יעבור לפני מרכוז
                                  Future.delayed(const Duration(milliseconds: 500), () {
                                    if (!mounted) return;
                                    _cycleNavigatorCenteringMode(navigatorId);
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.center_focus_strong, size: 18),
                                label: const Text('מרכז פעם אחת'),
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _tabController.animateTo(0);
                                  // עיכוב — ממתין שה-sheet ייסגר והטאב יעבור לפני ההזזה
                                  Future.delayed(const Duration(milliseconds: 400), () {
                                    if (!mounted) return;
                                    _mapController.move(liveData.currentPosition!, 16.0);
                                    _setOneTimeHighlight(navigatorId);
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 20),
                      ],

                      // 4. תצוגה על המפה
                      const Text('תצוגה על המפה', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 4),
                      SwitchListTile(
                        title: const Text('הצג מסלול בפועל', style: TextStyle(fontSize: 14)),
                        value: _showNavigatorTrack[navigatorId] ?? false,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (v) {
                          setState(() => _showNavigatorTrack[navigatorId] = v);
                          setSheetState(() {});
                        },
                      ),
                      if (hasPlannedPath)
                        SwitchListTile(
                          title: const Text('הצג ציר מתוכנן', style: TextStyle(fontSize: 14)),
                          value: _showPlannedAxis[navigatorId] ?? false,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          onChanged: (v) {
                            setState(() => _showPlannedAxis[navigatorId] = v);
                            setSheetState(() {});
                          },
                        ),

                      // 5. התראות פר-מנווט
                      const Divider(height: 16),
                      const Text('התראות', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 4),
                      ...(_navigatorAlertOverrides[navigatorId]?.entries ?? <MapEntry<AlertType, bool>>[]).map((entry) {
                        final navVolumes = _navigatorAlertSoundVolumes[navigatorId] ?? {};
                        return Row(
                          children: [
                            AlertVolumeControl(
                              volume: navVolumes[entry.key.code] ?? (_currentNavigation?.alerts.volumeForAlert(entry.key.code) ?? 1.0),
                              onVolumeChanged: (v) {
                                setState(() {
                                  _navigatorAlertSoundVolumes.putIfAbsent(navigatorId, () => {});
                                  if (v == (_currentNavigation?.alerts.volumeForAlert(entry.key.code) ?? 1.0)) {
                                    _navigatorAlertSoundVolumes[navigatorId]!.remove(entry.key.code);
                                  } else {
                                    _navigatorAlertSoundVolumes[navigatorId]![entry.key.code] = v;
                                  }
                                  final trackId = _navigatorTrackIds[navigatorId];
                                  if (trackId != null) {
                                    final vols = _navigatorAlertSoundVolumes[navigatorId];
                                    NavigationTrackRepository().updateAlertSoundVolumesOverride(
                                      trackId,
                                      volumes: vols != null && vols.isNotEmpty ? vols : null,
                                    );
                                  }
                                });
                                setSheetState(() {});
                              },
                            ),
                            Expanded(child: SwitchListTile(
                              title: Text(
                                '${entry.key.emoji} ${entry.key.displayName}',
                                style: const TextStyle(fontSize: 13),
                              ),
                              value: entry.value,
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              onChanged: (v) {
                                setState(() {
                                  _navigatorAlertOverrides[navigatorId]![entry.key] = v;
                                });
                                setSheetState(() {});
                              },
                            )),
                          ],
                        );
                      }),
                      // עוצמות צליל לקטגוריות נוספות (ברבור, חירום, הארכה)
                      ...[
                        MapEntry(AlertType.extensionRequest, '📋 בקשות הארכה'),
                        MapEntry(AlertType.barbur, '⚠️ ברבור'),
                        MapEntry(AlertType.emergency, '🚨 חירום'),
                      ].map((e) {
                        final navVolumes = _navigatorAlertSoundVolumes[navigatorId] ?? {};
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              AlertVolumeControl(
                                volume: navVolumes[e.key.code] ?? (_currentNavigation?.alerts.volumeForAlert(e.key.code) ?? 1.0),
                                onVolumeChanged: (v) {
                                  setState(() {
                                    _navigatorAlertSoundVolumes.putIfAbsent(navigatorId, () => {});
                                    if (v == (_currentNavigation?.alerts.volumeForAlert(e.key.code) ?? 1.0)) {
                                      _navigatorAlertSoundVolumes[navigatorId]!.remove(e.key.code);
                                    } else {
                                      _navigatorAlertSoundVolumes[navigatorId]![e.key.code] = v;
                                    }
                                    final trackId = _navigatorTrackIds[navigatorId];
                                    if (trackId != null) {
                                      final vols = _navigatorAlertSoundVolumes[navigatorId];
                                      NavigationTrackRepository().updateAlertSoundVolumesOverride(
                                        trackId,
                                        volumes: vols != null && vols.isNotEmpty ? vols : null,
                                      );
                                    }
                                  });
                                  setSheetState(() {});
                                },
                              ),
                              const SizedBox(width: 4),
                              Text(e.value, style: const TextStyle(fontSize: 13)),
                            ],
                          ),
                        );
                      }),

                      // 6. הגדרות מפה פר-מנווט
                      const Divider(height: 16),
                      const Text('הגדרות מפה למנווט', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 4),
                      SwitchListTile(
                        title: const Text('אפשר ניווט עם מפה פתוחה', style: TextStyle(fontSize: 13)),
                        value: _navigatorOverrideAllowOpenMap[navigatorId] ?? false,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (v) {
                          setState(() {
                            _navigatorOverrideAllowOpenMap[navigatorId] = v;
                            if (!v) {
                              _navigatorOverrideShowSelfLocation[navigatorId] = false;
                              _navigatorOverrideShowRouteOnMap[navigatorId] = false;
                            }
                          });
                          setSheetState(() {});
                          _updateNavigatorMapOverrides(navigatorId);
                        },
                      ),
                      if (_navigatorOverrideAllowOpenMap[navigatorId] ?? false) ...[
                        SwitchListTile(
                          title: const Text('אפשר הצגת מיקום עצמי למנווט', style: TextStyle(fontSize: 13)),
                          value: _navigatorOverrideShowSelfLocation[navigatorId] ?? false,
                          dense: true,
                          contentPadding: const EdgeInsets.only(right: 16),
                          onChanged: (v) {
                            setState(() {
                              _navigatorOverrideShowSelfLocation[navigatorId] = v;
                            });
                            setSheetState(() {});
                            _updateNavigatorMapOverrides(navigatorId);
                          },
                        ),
                      ],
                      const SizedBox(height: 8),
                      SwitchListTile(
                        title: const Text('ווקי טוקי', style: TextStyle(fontSize: 13)),
                        subtitle: const Text('אפשר קשר קולי למנווט', style: TextStyle(fontSize: 11)),
                        value: _navigatorOverrideWalkieTalkieEnabled[navigatorId] ?? false,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (v) {
                          setState(() {
                            _navigatorOverrideWalkieTalkieEnabled[navigatorId] = v;
                          });
                          setSheetState(() {});
                          final trackId = _navigatorTrackIds[navigatorId];
                          if (trackId != null) {
                            NavigationTrackRepository().updateWalkieTalkieOverride(trackId, enabled: v);
                          }
                        },
                      ),
                      if (_currentNavigation != null && _currentNavigation!.usesClusters) ...[
                        const Divider(height: 16),
                        Text('חשיפת נקודות', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 2),
                        Text(
                          _currentNavigation!.clusterSettings.isRevealCurrentlyOpen
                              ? 'חשיפה גלובלית פעילה'
                              : 'חשיפה גלובלית כבויה',
                          style: TextStyle(fontSize: 11,
                              color: _currentNavigation!.clusterSettings.isRevealCurrentlyOpen ? Colors.green : Colors.grey),
                        ),
                        const SizedBox(height: 4),
                        SwitchListTile(
                          title: const Text('חשיפת נקודות', style: TextStyle(fontSize: 13)),
                          subtitle: Text(
                            _navigatorOverrideRevealEnabled[navigatorId] == true
                                ? 'נקודות אמיתיות חשופות'
                                : _navigatorOverrideRevealEnabled[navigatorId] == false
                                    ? 'חשיפה חסומה'
                                    : 'לפי ברירת מחדל',
                            style: const TextStyle(fontSize: 11),
                          ),
                          value: _navigatorOverrideRevealEnabled[navigatorId] ??
                                 _currentNavigation!.clusterSettings.isRevealCurrentlyOpen,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          onChanged: (v) {
                            setState(() {
                              // 3-state: first tap → true, second → null (default), from null → true
                              if (_navigatorOverrideRevealEnabled[navigatorId] == true) {
                                _navigatorOverrideRevealEnabled[navigatorId] = false;
                              } else if (_navigatorOverrideRevealEnabled[navigatorId] == false) {
                                _navigatorOverrideRevealEnabled[navigatorId] = null;
                              } else {
                                _navigatorOverrideRevealEnabled[navigatorId] = true;
                              }
                            });
                            setSheetState(() {});
                            final trackId = _navigatorTrackIds[navigatorId];
                            if (trackId != null) {
                              NavigationTrackRepository().updateRevealOverride(
                                trackId,
                                enabled: _navigatorOverrideRevealEnabled[navigatorId],
                              );
                            }
                          },
                        ),
                      ],

                      // 6.5 אמצעי מיקום
                      const Divider(height: 16),
                      const Text('אמצעי מיקום', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 4),
                      () {
                        final defaultSources = widget.navigation.enabledPositionSources;
                        final overrideSources = _navigatorPositionSourcesOverride[navigatorId];
                        final effectiveSources = overrideSources ?? defaultSources;
                        final isOverridden = overrideSources != null;

                        void toggleSource(String source, bool enabled) {
                          final current = List<String>.from(effectiveSources);
                          if (enabled) {
                            if (!current.contains(source)) current.add(source);
                          } else {
                            // מניעת כיבוי כל המקורות — GPS חייב להישאר
                            if (current.length <= 1) return;
                            current.remove(source);
                          }
                          // אם שווה לברירת המחדל — אין צורך בדריסה
                          final isDefault = listEquals(current..sort(), List<String>.from(defaultSources)..sort());
                          final newOverride = isDefault ? null : current;
                          setState(() => _navigatorPositionSourcesOverride[navigatorId] = newOverride);
                          setSheetState(() {});
                          final trackId = _navigatorTrackIds[navigatorId];
                          if (trackId != null) {
                            NavigationTrackRepository().updatePositionSourcesOverride(trackId, enabledSources: newOverride);
                          }
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (isOverridden)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text('דריסה פעילה — שונה מברירת המחדל',
                                    style: TextStyle(fontSize: 11, color: Colors.orange[700])),
                              ),
                            SwitchListTile(
                              title: const Text('GPS', style: TextStyle(fontSize: 13)),
                              subtitle: const Text('לוויינים', style: TextStyle(fontSize: 11)),
                              value: effectiveSources.contains('gps'),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              onChanged: (v) => toggleSource('gps', v),
                            ),
                            SwitchListTile(
                              title: const Text('אנטנות סלולריות', style: TextStyle(fontSize: 13)),
                              subtitle: const Text('Cell Tower', style: TextStyle(fontSize: 11)),
                              value: effectiveSources.contains('cellTower'),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              onChanged: (v) => toggleSource('cellTower', v),
                            ),
                            SwitchListTile(
                              title: const Text('PDR', style: TextStyle(fontSize: 13)),
                              subtitle: const Text('ניווט מתים — צעדים + תאוצה', style: TextStyle(fontSize: 11)),
                              value: effectiveSources.contains('pdr'),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              onChanged: (v) => toggleSource('pdr', v),
                            ),
                            SwitchListTile(
                              title: const Text('PDR + אנטנות', style: TextStyle(fontSize: 13)),
                              subtitle: const Text('היברידי — שילוב PDR ואנטנות', style: TextStyle(fontSize: 11)),
                              value: effectiveSources.contains('pdrCellHybrid'),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              onChanged: (v) => toggleSource('pdrCellHybrid', v),
                            ),
                            if (isOverridden)
                              Align(
                                alignment: AlignmentDirectional.centerEnd,
                                child: TextButton.icon(
                                  icon: const Icon(Icons.restart_alt, size: 16),
                                  label: const Text('חזרה לברירת מחדל', style: TextStyle(fontSize: 12)),
                                  onPressed: () {
                                    setState(() => _navigatorPositionSourcesOverride[navigatorId] = null);
                                    setSheetState(() {});
                                    final trackId = _navigatorTrackIds[navigatorId];
                                    if (trackId != null) {
                                      NavigationTrackRepository().updatePositionSourcesOverride(trackId, enabledSources: null);
                                    }
                                  },
                                ),
                              ),
                          ],
                        );
                      }(),

                      // 6.6 תדירות סנכרון מיקום (פר-מנווט)
                      const Divider(height: 16),
                      const Text('תדירות סנכרון מיקום', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 4),
                      () {
                        final overrideVal = _navigatorGpsSyncIntervalOverride[navigatorId];
                        final isOverridden = overrideVal != null;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (isOverridden)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text('דריסה פעילה — שונה מברירת המחדל',
                                    style: TextStyle(fontSize: 11, color: Colors.orange[700])),
                              ),
                            DropdownButton<int?>(
                              value: overrideVal,
                              isExpanded: true,
                              items: [
                                const DropdownMenuItem(value: null, child: Text('ברירת מחדל')),
                                ..._gpsSyncIntervalLabels.entries
                                    .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))),
                              ],
                              onChanged: (v) {
                                setState(() => _navigatorGpsSyncIntervalOverride[navigatorId] = v);
                                setSheetState(() {});
                                final trackId = _navigatorTrackIds[navigatorId];
                                if (trackId != null) {
                                  NavigationTrackRepository().updateGpsSyncIntervalOverride(trackId, intervalSeconds: v);
                                }
                              },
                            ),
                            if (isOverridden)
                              Align(
                                alignment: AlignmentDirectional.centerEnd,
                                child: TextButton.icon(
                                  icon: const Icon(Icons.restart_alt, size: 16),
                                  label: const Text('חזרה לברירת מחדל', style: TextStyle(fontSize: 12)),
                                  onPressed: () {
                                    setState(() => _navigatorGpsSyncIntervalOverride[navigatorId] = null);
                                    setSheetState(() {});
                                    final trackId = _navigatorTrackIds[navigatorId];
                                    if (trackId != null) {
                                      NavigationTrackRepository().updateGpsSyncIntervalOverride(trackId, intervalSeconds: null);
                                    }
                                  },
                                ),
                              ),
                          ],
                        );
                      }(),

                      // 7. נתונים חיים
                      const Divider(height: 20),
                      const Text('נתונים חיים', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 6),
                      _detailRow('מהירות נוכחית', '${liveData.currentSpeedKmh.toStringAsFixed(1)} קמ"ש'),
                      _detailRow('מהירות ממוצעת', '${liveData.averageSpeedKmh.toStringAsFixed(1)} קמ"ש'),
                      _detailRow('מרחק שנעבר', '${liveData.totalDistanceKm.toStringAsFixed(2)} ק"מ'),
                      _detailRow('זמן ניווט', _formatDuration(
                        () {
                          // מנווט שעדיין לא התחיל — אפס
                          if (liveData.trackStartedAt == null) return Duration.zero;
                          final endTime = liveData.trackEndedAt ?? DateTime.now();
                          final diff = endTime.difference(liveData.trackStartedAt!);
                          return diff.isNegative ? Duration.zero : diff;
                        }(),
                      )),
                      _detailRow('נקודות GPS', '${liveData.trackPoints.length}'),
                      if (liveData.lastUpdate != null)
                        _detailRow('עדכון אחרון', '${_formatTimeSince(liveData.timeSinceLastUpdate)} לפני'),
                      if (route != null)
                        _detailRow('אורך ציר מתוכנן', '${route.routeLengthKm.toStringAsFixed(1)} ק"מ'),

                      // זמני משימה
                      if (route != null && widget.navigation.timeCalculationSettings.enabled) ...[
                        () {
                          final navigatorExtMinutes = _extensionRequests
                              .where((r) => r.navigatorId == navigatorId && r.status == ExtensionRequestStatus.approved)
                              .fold<int>(0, (sum, r) => sum + (r.approvedMinutes ?? 0));
                          final totalMinutes = GeometryUtils.getEffectiveTimeMinutes(
                            route: route,
                            settings: widget.navigation.timeCalculationSettings,
                            extensionMinutes: navigatorExtMinutes,
                          );
                          final activeStart = widget.navigation.activeStartTime;
                          if (totalMinutes > 0 && activeStart != null) {
                            final missionEnd = activeStart.add(Duration(minutes: totalMinutes));
                            final safetyEnd = activeStart.add(Duration(minutes: totalMinutes + 60));
                            final now = DateTime.now();
                            final remainMinutes = missionEnd.difference(now).inMinutes;
                            final remainStr = remainMinutes >= 0
                                ? '${remainMinutes ~/ 60}:${(remainMinutes % 60).toString().padLeft(2, '0')} שעות'
                                : 'חריגה: +${(-remainMinutes) ~/ 60}:${((-remainMinutes) % 60).toString().padLeft(2, '0')}';
                            return Column(
                              children: [
                                _detailRow('שעת סיום משימה', '${missionEnd.hour.toString().padLeft(2, '0')}:${missionEnd.minute.toString().padLeft(2, '0')}'),
                                _detailRow('זמן משימה נותר', remainStr),
                                _detailRow('שעת בטיחות', '${safetyEnd.hour.toString().padLeft(2, '0')}:${safetyEnd.minute.toString().padLeft(2, '0')}'),
                              ],
                            );
                          }
                          return const SizedBox.shrink();
                        }(),
                      ],

                      // 7. נקודות ציון
                      if (arrivals.isNotEmpty) ...[
                        const Divider(height: 20),
                        const Text('נקודות ציון', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 6),
                        ...arrivals.map(_buildCheckpointRow),
                      ],

                      const SizedBox(height: 24),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    ).then((_) => sheetRefreshTimer?.cancel());
  }

  Future<void> _updateNavigatorMapOverrides(String navigatorId) async {
    String? trackId = _navigatorTrackIds[navigatorId];

    // fallback: חיפוש track דרך repository אם אין cache
    if (trackId == null) {
      trackId = await _trackRepo.findTrackId(widget.navigation.id, navigatorId);
      if (trackId != null) {
        _navigatorTrackIds[navigatorId] = trackId;
      }
    }

    if (trackId == null) return;

    await _trackRepo.updateMapOverrides(
      trackId,
      allowOpenMap: _navigatorOverrideAllowOpenMap[navigatorId] ?? false,
      showSelfLocation: _navigatorOverrideShowSelfLocation[navigatorId] ?? false,
      showRouteOnMap: _navigatorOverrideShowRouteOnMap[navigatorId] ?? false,
    );
  }

  // ===========================================================================
  // Global Settings Sheet
  // ===========================================================================

  void _showGlobalSettingsSheet() {
    if (!PermissionUtils.checkManagement(context, _currentUser)) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scrollController) => _GlobalSettingsContent(
          navigation: _currentNavigation,
          scrollController: scrollController,
          onSettingChanged: (updatedNav, settingName, overrideType) async {
            final saved = await _handleSettingChange(
              settingName: settingName,
              updatedNavigation: updatedNav,
              overrideType: overrideType,
            );
            if (saved) return _currentNavigation;
            return null; // ביטול — החזר null
          },
        ),
      ),
    );
  }

  // ===========================================================================
  // Global Settings — scope dialog + save + clear overrides
  // ===========================================================================

  /// דיאלוג היקף שינוי: ברירת מחדל / כל המנווטים / ביטול
  /// מחזיר 'default', 'all' או null (ביטול)
  Future<String?> _showSettingScopeDialog(String settingName) async {
    return showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'שינוי הגדרה',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '"$settingName"',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'בחר את היקף השינוי:',
                style: TextStyle(color: Colors.white, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              _scopeOptionTile(
                ctx: ctx,
                title: 'ברירת מחדל בלבד',
                subtitle: 'שינוי רק למי שלא הוגדר לו אחרת',
                icon: Icons.person_outline,
                value: 'default',
              ),
              const SizedBox(height: 8),
              _scopeOptionTile(
                ctx: ctx,
                title: 'כל המנווטים',
                subtitle: 'עדכון רוחבי מלא כולל דריסת הגדרה אישית',
                icon: Icons.group,
                value: 'all',
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('ביטול', style: TextStyle(color: Colors.grey)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _scopeOptionTile({
    required BuildContext ctx,
    required String title,
    required String subtitle,
    required IconData icon,
    required String value,
  }) {
    return Material(
      color: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.pop(ctx, value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(icon, color: Colors.white70, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_left, color: Colors.white38),
            ],
          ),
        ),
      ),
    );
  }

  /// שמירת שינוי הגדרה גלובלית
  Future<void> _saveNavigationSetting(domain.Navigation updated) async {
    try {
      await _navRepo.update(updated);
      setState(() => _currentNavigation = updated);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה בשמירת הגדרה: $e')),
        );
      }
    }
  }

  /// ניקוי דריסות פר-מנווט עבור סוג הגדרה
  Future<void> _clearOverridesForSetting(String settingType) async {
    final nav = _currentNavigation;
    for (final navigatorId in nav.routes.keys) {
      String? trackId = _navigatorTrackIds[navigatorId];
      if (trackId == null) {
        trackId = await _trackRepo.findTrackId(nav.id, navigatorId);
        if (trackId != null) {
          _navigatorTrackIds[navigatorId] = trackId;
        }
      }
      if (trackId == null) continue;

      switch (settingType) {
        case 'allowOpenMap':
          _navigatorOverrideAllowOpenMap[navigatorId] = nav.allowOpenMap;
          if (!nav.allowOpenMap) {
            _navigatorOverrideShowSelfLocation[navigatorId] = false;
            _navigatorOverrideShowRouteOnMap[navigatorId] = false;
          }
          await _trackRepo.updateMapOverrides(
            trackId,
            allowOpenMap: nav.allowOpenMap,
            showSelfLocation: _navigatorOverrideShowSelfLocation[navigatorId] ?? nav.showSelfLocation,
            showRouteOnMap: _navigatorOverrideShowRouteOnMap[navigatorId] ?? nav.showRouteOnMap,
          );
          break;
        case 'showSelfLocation':
          _navigatorOverrideShowSelfLocation[navigatorId] = nav.showSelfLocation;
          await _trackRepo.updateMapOverrides(
            trackId,
            allowOpenMap: _navigatorOverrideAllowOpenMap[navigatorId] ?? nav.allowOpenMap,
            showSelfLocation: nav.showSelfLocation,
            showRouteOnMap: _navigatorOverrideShowRouteOnMap[navigatorId] ?? nav.showRouteOnMap,
          );
          break;
        case 'walkieTalkie':
          _navigatorOverrideWalkieTalkieEnabled[navigatorId] = nav.communicationSettings.walkieTalkieEnabled;
          await _trackRepo.updateWalkieTalkieOverride(trackId, enabled: nav.communicationSettings.walkieTalkieEnabled);
          break;
        case 'gpsInterval':
          _navigatorGpsIntervalOverride[navigatorId] = null;
          break;
        case 'gpsSyncInterval':
          _navigatorGpsSyncIntervalOverride[navigatorId] = null;
          await _trackRepo.updateGpsSyncIntervalOverride(trackId, intervalSeconds: null);
          break;
        case 'positionSources':
          _navigatorPositionSourcesOverride[navigatorId] = null;
          await _trackRepo.updatePositionSourcesOverride(trackId, enabledSources: null);
          break;
        case 'clusterReveal':
          _navigatorOverrideRevealEnabled[navigatorId] = null;
          await _trackRepo.updateRevealOverride(trackId, enabled: null);
          break;
        case 'alertToggle':
          // איפוס כל דריסות ההתראות לערכי ברירת מחדל של הניווט
          final alerts = nav.alerts;
          _navigatorAlertOverrides[navigatorId] = {
            AlertType.speed: alerts.speedAlertEnabled,
            AlertType.noMovement: alerts.noMovementAlertEnabled,
            AlertType.boundary: alerts.ggAlertEnabled,
            AlertType.routeDeviation: alerts.routesAlertEnabled,
            AlertType.safetyPoint: alerts.nbAlertEnabled,
            AlertType.proximity: alerts.navigatorProximityAlertEnabled,
            AlertType.battery: alerts.batteryAlertEnabled,
            AlertType.noReception: alerts.noReceptionAlertEnabled,
            AlertType.healthCheckExpired: alerts.healthCheckEnabled,
          };
          break;
        case 'alertSoundVolumes':
          _navigatorAlertSoundVolumes.remove(navigatorId);
          await _trackRepo.updateAlertSoundVolumesOverride(
            trackId,
            volumes: null,
          );
          break;
      }
    }
    if (mounted) setState(() {});
  }

  /// טיפול בשינוי הגדרה: הצגת דיאלוג היקף ← שמירה/ביטול
  Future<bool> _handleSettingChange({
    required String settingName,
    required domain.Navigation updatedNavigation,
    String? overrideType,
  }) async {
    final scope = await _showSettingScopeDialog(settingName);
    if (scope == null) return false; // ביטול

    await _saveNavigationSetting(updatedNavigation);
    if (scope == 'all' && overrideType != null) {
      await _clearOverridesForSetting(overrideType);
    }
    return true;
  }

  Widget _deviceChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  // ===========================================================================
  // Dashboard Tab
  // ===========================================================================

  Widget _buildDashboardView() {
    // ספירות סטטוס
    final waitingCount = _navigatorData.values
        .where((d) => d.personalStatus == NavigatorPersonalStatus.waiting)
        .length;
    final activeCount = _navigatorData.values
        .where((d) => d.personalStatus == NavigatorPersonalStatus.active)
        .length;
    final finishedCount = _navigatorData.values
        .where((d) => d.personalStatus == NavigatorPersonalStatus.finished)
        .length;
    final noReceptionCount = _navigatorData.values
        .where((d) => d.personalStatus == NavigatorPersonalStatus.noReception)
        .length;

    // התקדמות נ"צ
    int totalCheckpoints = 0;
    int reachedCheckpoints = 0;
    for (final data in _navigatorData.values) {
      final arrivals = _getCheckpointArrivals(data);
      totalCheckpoints += arrivals.length;
      reachedCheckpoints += arrivals.where((a) => a.reached).length;
    }
    final progressPercent = totalCheckpoints > 0
        ? (reachedCheckpoints / totalCheckpoints * 100).round()
        : 0;

    // ממוצעים — רק ממנווטים עם נתונים
    final navigatorsWithData = _navigatorData.values
        .where((d) => d.trackPoints.isNotEmpty)
        .toList();

    double avgSpeed = 0;
    double avgDistance = 0;
    Duration avgTime = Duration.zero;
    if (navigatorsWithData.isNotEmpty) {
      avgSpeed = navigatorsWithData
              .map((d) => d.averageSpeedKmh)
              .reduce((a, b) => a + b) /
          navigatorsWithData.length;
      avgDistance = navigatorsWithData
              .map((d) => d.totalDistanceKm)
              .reduce((a, b) => a + b) /
          navigatorsWithData.length;
      final totalMs = navigatorsWithData
          .map((d) => d.elapsedTime.inMilliseconds)
          .reduce((a, b) => a + b);
      avgTime = Duration(milliseconds: totalMs ~/ navigatorsWithData.length);
    }

    // מהיר/איטי
    final sortedBySpeed = navigatorsWithData.toList()
      ..sort((a, b) => b.averageSpeedKmh.compareTo(a.averageSpeedKmh));
    final fastest = sortedBySpeed.isNotEmpty ? sortedBySpeed.first : null;
    final slowest = sortedBySpeed.length > 1 ? sortedBySpeed.last : null;

    // פילוח התראות
    final alertBreakdown = <AlertType, int>{};
    for (final alert in _activeAlerts) {
      alertBreakdown[alert.type] = (alertBreakdown[alert.type] ?? 0) + 1;
    }

    // זמן
    final activeStartTime = widget.navigation.activeStartTime;
    final elapsed = activeStartTime != null
        ? DateTime.now().difference(activeStartTime)
        : null;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // כרטיסי מדדים ראשיים
        Row(
          children: [
            Expanded(child: _dashboardMetricCard(
              icon: Icons.hourglass_empty,
              label: 'ממתינים',
              value: '$waitingCount',
              color: Colors.grey,
            )),
            const SizedBox(width: 8),
            Expanded(child: _dashboardMetricCard(
              icon: Icons.navigation,
              label: 'פעילים',
              value: '$activeCount',
              color: Colors.green,
            )),
            const SizedBox(width: 8),
            Expanded(child: _dashboardMetricCard(
              icon: Icons.check_circle,
              label: 'סיימו',
              value: '$finishedCount',
              color: Colors.blue,
            )),
          ],
        ),
        if (noReceptionCount > 0) ...[
          const SizedBox(height: 8),
          _dashboardMetricCard(
            icon: Icons.signal_wifi_off,
            label: 'ללא קליטה',
            value: '$noReceptionCount',
            color: Colors.orange,
          ),
        ],
        const SizedBox(height: 12),

        // התקדמות נ"צ
        if (totalCheckpoints > 0)
          _dashboardCard(
            title: 'התקדמות',
            icon: Icons.flag,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$reachedCheckpoints/$totalCheckpoints נ"צ ($progressPercent%)',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: totalCheckpoints > 0
                        ? reachedCheckpoints / totalCheckpoints
                        : 0,
                    minHeight: 10,
                    backgroundColor: Colors.grey[200],
                    valueColor: AlwaysStoppedAnimation<Color>(
                      progressPercent >= 80 ? Colors.green : Colors.blue,
                    ),
                  ),
                ),
              ],
            ),
          ),

        // ממוצעים
        if (navigatorsWithData.isNotEmpty)
          _dashboardCard(
            title: 'ממוצעים',
            icon: Icons.analytics,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _miniStat('מהירות', avgSpeed.toStringAsFixed(1), 'קמ"ש'),
                _miniStat('מרחק', avgDistance.toStringAsFixed(2), 'ק"מ'),
                _miniStat('זמן', _formatDuration(avgTime), ''),
              ],
            ),
          ),

        // זמן ניווט
        if (elapsed != null)
          _dashboardCard(
            title: 'זמן',
            icon: Icons.timer,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        '${activeStartTime!.hour.toString().padLeft(2, '0')}:${activeStartTime.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      Text('התחלה', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        _formatDuration(elapsed),
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      Text('נמשך', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    ],
                  ),
                ),
              ],
            ),
          ),

        // שעת בטיחות
        if (activeStartTime != null && _currentNavigation.timeCalculationSettings.enabled && _currentNavigation.routes.isNotEmpty)
          () {
            final safetyTime = _computeSafetyTime();
            if (safetyTime == null) return const SizedBox.shrink();
            final now = DateTime.now();
            final minutesUntilSafety = safetyTime.difference(now).inMinutes;
            final safetyTimeStr = '${safetyTime.hour.toString().padLeft(2, '0')}:${safetyTime.minute.toString().padLeft(2, '0')}';

            // חישוב שעת סיום משימה הארוכה ביותר
            final longestMissionEnd = safetyTime.subtract(const Duration(minutes: 60));
            final missionEndStr = '${longestMissionEnd.hour.toString().padLeft(2, '0')}:${longestMissionEnd.minute.toString().padLeft(2, '0')}';

            final Color safetyColor;
            final String countdownStr;
            if (minutesUntilSafety <= 0) {
              safetyColor = Colors.red;
              final over = -minutesUntilSafety;
              countdownStr = 'חריגה: +${over ~/ 60}:${(over % 60).toString().padLeft(2, '0')}';
            } else if (minutesUntilSafety <= 10) {
              safetyColor = Colors.orange;
              countdownStr = '$minutesUntilSafety דק\'';
            } else {
              safetyColor = Colors.green;
              countdownStr = '${minutesUntilSafety ~/ 60}:${(minutesUntilSafety % 60).toString().padLeft(2, '0')} שעות';
            }

            return _dashboardCard(
              title: 'שעת בטיחות',
              icon: Icons.shield,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          missionEndStr,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text('סיום אחרון', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          safetyTimeStr,
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: safetyColor),
                        ),
                        Text('שעת בטיחות', style: TextStyle(fontSize: 12, color: safetyColor)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          countdownStr,
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: safetyColor),
                        ),
                        Text('נותר', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }(),

        // מהיר/איטי
        if (fastest != null)
          _dashboardCard(
            title: 'ביצועים',
            icon: Icons.speed,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.keyboard_double_arrow_up, color: Colors.green, size: 20),
                        Text(fastest.navigatorId, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Text('${fastest.averageSpeedKmh.toStringAsFixed(1)} קמ"ש', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (slowest != null)
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          const Icon(Icons.keyboard_double_arrow_down, color: Colors.orange, size: 20),
                          Text(slowest.navigatorId, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          Text('${slowest.averageSpeedKmh.toStringAsFixed(1)} קמ"ש', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

        // פילוח התראות
        if (alertBreakdown.isNotEmpty)
          _dashboardCard(
            title: 'התראות',
            icon: Icons.notifications_active,
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: alertBreakdown.entries.map((entry) {
                return Chip(
                  avatar: Text(entry.key.emoji, style: const TextStyle(fontSize: 16)),
                  label: Text(
                    '${entry.key.displayName} ×${entry.value}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  backgroundColor: _getAlertColor(entry.key).withValues(alpha: 0.15),
                  side: BorderSide.none,
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  Widget _dashboardMetricCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }

  Widget _dashboardCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: Colors.grey[700]),
                const SizedBox(width: 6),
                Text(title, style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[700],
                )),
              ],
            ),
            const Divider(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  Widget _miniStat(String label, String value, String unit) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        if (unit.isNotEmpty)
          Text(unit, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }

  // ===========================================================================
  // Alerts Tab
  // ===========================================================================

  /// בדיקה אם התראה צריכה להיות מוצגת לפי דריסות פר-מנווט
  bool _isAlertVisibleByOverride(NavigatorAlert alert) {
    final overrides = _navigatorAlertOverrides[alert.navigatorId];
    if (overrides == null) return true; // אין דריסות — מציגים
    final enabled = overrides[alert.type];
    if (enabled == null) return true; // אין דריסה לסוג הזה — מציגים
    return enabled;
  }

  Widget _buildAlertsBanner() {
    final emergencyCount = _activeAlerts.where((a) => a.type == AlertType.emergency).length;
    final healthCount = _activeAlerts.where((a) => a.type == AlertType.healthCheckExpired).length;
    final barburCount = _activeAlerts.where((a) => a.type == AlertType.barbur).length;
    final extensionCount = _extensionRequests.where((r) => r.status == ExtensionRequestStatus.pending).length;

    return GestureDetector(
      onTap: () {
        // הצג את ההתראה הראשונה שלא טופלה
        final urgent = _activeAlerts.where(
          (a) => a.type == AlertType.emergency || a.type == AlertType.healthCheckExpired,
        ).toList();
        if (urgent.isNotEmpty) {
          _showAlertDialog(urgent.first);
        } else if (barburCount > 0) {
          final barburAlert = _activeAlerts.firstWhere((a) => a.type == AlertType.barbur);
          _showBarburProtocolDialog(barburAlert);
        } else if (extensionCount > 0) {
          _tabController.animateTo(3); // טאב התראות
        }
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: emergencyCount > 0 ? Colors.red : (barburCount > 0 ? Colors.orange : (extensionCount > 0 ? Colors.purple : Colors.orange)),
        child: Row(
          children: [
            Icon(
              emergencyCount > 0 ? Icons.emergency : (barburCount > 0 ? Icons.report_problem : (extensionCount > 0 ? Icons.timer : Icons.timer_off)),
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                [
                  if (emergencyCount > 0) '$emergencyCount חירום',
                  if (barburCount > 0) '$barburCount ברבור',
                  if (healthCount > 0) '$healthCount תקינות',
                  if (extensionCount > 0) '$extensionCount הארכה',
                ].join(' | '),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Icon(Icons.chevron_left, color: Colors.white),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertsView() {
    final filteredAlerts = _activeAlerts.where(_isAlertVisibleByOverride).toList();
    final pendingExtensions = _extensionRequests
        .where((r) => r.status == ExtensionRequestStatus.pending)
        .toList();
    final now = DateTime.now();
    final recentRespondedExtensions = _extensionRequests
        .where((r) =>
            r.status != ExtensionRequestStatus.pending &&
            r.respondedAt != null &&
            now.difference(r.respondedAt!).inMinutes <= 30)
        .toList()
      ..sort((a, b) => (b.respondedAt!).compareTo(a.respondedAt!));

    if (filteredAlerts.isEmpty && pendingExtensions.isEmpty && recentRespondedExtensions.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
            SizedBox(height: 16),
            Text(
              'אין התראות פעילות',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // בקשות הארכה ממתינות
        if (pendingExtensions.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'בקשות הארכה',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.purple,
              ),
            ),
          ),
          ...pendingExtensions.map((req) => _buildExtensionRequestCard(req)),
          if (filteredAlerts.isNotEmpty || recentRespondedExtensions.isNotEmpty)
            const Divider(height: 24),
        ],
        // התראות רגילות
        ...filteredAlerts.map((alert) => _buildAlertCard(alert)),
        // בקשות הארכה שנענו לאחרונה
        if (recentRespondedExtensions.isNotEmpty) ...[
          if (filteredAlerts.isNotEmpty) const Divider(height: 24),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'בקשות שנענו לאחרונה',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
              ),
            ),
          ),
          ...recentRespondedExtensions.map((req) {
            final isApproved = req.status == ExtensionRequestStatus.approved;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              color: isApproved ? Colors.green[50] : Colors.red[50],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: isApproved ? Colors.green : Colors.red,
                  width: 1.5,
                ),
              ),
              child: ListTile(
                leading: Icon(
                  isApproved ? Icons.check_circle : Icons.cancel,
                  color: isApproved ? Colors.green : Colors.red,
                ),
                title: Text(
                  isApproved
                      ? 'אושרה הארכה ל-${req.approvedMinutes ?? req.requestedMinutes} דקות למנווט ${req.navigatorName}'
                      : 'נדחתה בקשת הארכה של ${req.navigatorName}',
                  style: const TextStyle(fontSize: 14),
                ),
                subtitle: Text(
                  '${req.respondedAt!.hour.toString().padLeft(2, '0')}:${req.respondedAt!.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _buildExtensionRequestCard(ExtensionRequest req) {
    final elapsed = DateTime.now().difference(req.createdAt);
    final elapsedText = elapsed.inMinutes < 60
        ? '${elapsed.inMinutes} דק\' '
        : '${elapsed.inHours} שע\' ${elapsed.inMinutes % 60} דק\' ';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Colors.purple, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.purple.withOpacity(0.15),
                  child: const Icon(Icons.timer, color: Colors.purple),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        req.navigatorName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'מבקש ${req.requestedMinutes} דקות הארכה',
                        style: const TextStyle(color: Colors.purple),
                      ),
                      Text(
                        'לפני $elapsedText',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _respondToExtension(req, ExtensionRequestStatus.rejected),
                  icon: const Icon(Icons.close, color: Colors.red, size: 18),
                  label: const Text('דחה', style: TextStyle(color: Colors.red)),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => _showExtensionApproveDialog(req),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('אשר'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertCard(NavigatorAlert alert) {
    // כרטיס מיוחד לברבור
    if (alert.type == AlertType.barbur) {
      return _buildBarburAlertCard(alert);
    }

    final alertColor = _getAlertColor(alert.type);
    final elapsed = DateTime.now().difference(alert.timestamp);
    final elapsedText = elapsed.inMinutes < 60
        ? '${elapsed.inMinutes} דק\' '
        : '${elapsed.inHours} שע\' ${elapsed.inMinutes % 60} דק\' ';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: alertColor, width: 2),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: alertColor.withValues(alpha: 0.15),
          child: Text(
            alert.type.emoji,
            style: const TextStyle(fontSize: 20),
          ),
        ),
        title: Text(
          alert.type.displayName,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: alertColor,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(alert.navigatorName ?? alert.navigatorId),
            Text(
              'לפני $elapsedText',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.check_circle),
          color: Colors.green,
          tooltip: 'סגור התראה',
          onPressed: () => _resolveAlert(alert),
        ),
        onTap: () {
          // מעבר למפה + zoom למיקום ההתראה
          if (alert.location.lat != 0 && alert.location.lng != 0) {
            _tabController.animateTo(0);
            _mapController.move(
              LatLng(alert.location.lat, alert.location.lng),
              15.0,
            );
          }
        },
      ),
    );
  }

  Widget _buildBarburAlertCard(NavigatorAlert alert) {
    final checklist = alert.barburChecklist ?? {};
    final completedCount = checklist.values.where((v) => v).length;
    final elapsed = DateTime.now().difference(alert.timestamp);
    final elapsedText = elapsed.inMinutes < 60
        ? '${elapsed.inMinutes} דק\' '
        : '${elapsed.inHours} שע\' ${elapsed.inMinutes % 60} דק\' ';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Colors.orange, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.orange.withValues(alpha: 0.15),
                  child: const Text('⚠️', style: TextStyle(fontSize: 20)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'נוהל ברבור',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 15),
                      ),
                      Text(alert.navigatorName ?? alert.navigatorId),
                      Text('לפני $elapsedText', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$completedCount/4',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // פס התקדמות
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: completedCount / 4,
                backgroundColor: Colors.orange.withValues(alpha: 0.2),
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.orange),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _showBarburProtocolDialog(alert),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('פתח נוהל'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange,
                    side: const BorderSide(color: Colors.orange),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // Alert Map Markers
  // ===========================================================================

  List<Widget> _buildAlertMarkers() {
    if (_activeAlerts.isEmpty) return [];

    final markers = _activeAlerts
        .where(_isAlertVisibleByOverride)
        .where((a) => a.location.lat != 0 && a.location.lng != 0)
        .map((alert) {
      final color = _getAlertColor(alert.type);
      return Marker(
        point: LatLng(alert.location.lat, alert.location.lng),
        width: 40,
        height: 40,
        child: Container(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.9),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: Center(
            child: Text(
              alert.type.emoji,
              style: const TextStyle(fontSize: 18),
            ),
          ),
        ),
      );
    }).toList();

    return markers.isNotEmpty ? [MarkerLayer(markers: markers)] : [];
  }

  Color _getAlertColor(AlertType type) {
    switch (type) {
      case AlertType.emergency:
        return Colors.red;
      case AlertType.boundary:
      case AlertType.safetyPoint:
        return Colors.orange;
      case AlertType.speed:
      case AlertType.routeDeviation:
        return Colors.amber;
      case AlertType.noMovement:
      case AlertType.noReception:
        return Colors.deepPurple;
      case AlertType.battery:
        return Colors.brown;
      case AlertType.barbur:
        return Colors.orange;
      case AlertType.proximity:
        return Colors.teal;
      case AlertType.healthCheckExpired:
      case AlertType.healthReport:
        return Colors.blue;
      case AlertType.securityBreach:
        return Colors.red;
      case AlertType.extensionRequest:
        return Colors.blue;
    }
  }

  // ===========================================================================
  // Extension Requests — בקשות הארכה
  // ===========================================================================

  /// פענוח עוצמת צליל: דריסה פר-מנווט → ברירת מחדל ניווט → 1.0
  double _resolveAlertVolume(String navigatorId, String alertTypeCode) {
    final perNav = _navigatorAlertSoundVolumes[navigatorId];
    if (perNav != null && perNav.containsKey(alertTypeCode)) {
      return perNav[alertTypeCode]!;
    }
    return _currentNavigation?.alerts.volumeForAlert(alertTypeCode) ?? 1.0;
  }

  void _startExtensionRequestListener() {
    if (!widget.navigation.timeCalculationSettings.allowExtensionRequests) return;
    _extensionListener = _extensionRepo
        .watchByNavigation(widget.navigation.id)
        .listen((requests) {
      if (!mounted) return;
      setState(() => _extensionRequests = requests);
      // בדיקת שעת בטיחות לאחר שינוי הארכות
      _checkSafetyTimeAlerts();
      // popup אוטומטי לבקשות חדשות
      for (final req in requests) {
        if (req.status == ExtensionRequestStatus.pending &&
            !_shownExtensionPopups.contains(req.id)) {
          _shownExtensionPopups.add(req.id);
          final vol = _resolveAlertVolume(req.navigatorId, AlertType.extensionRequest.code);
          AlertSoundService().playAlert(AlertType.extensionRequest, vol);
          _showExtensionPopup(req);
        }
      }
    });
  }

  // =========================================================================
  // Safety Time Monitor (שעת בטיחות)
  // =========================================================================

  DateTime? _computeSafetyTime() {
    final nav = _currentNavigation;
    final activeStart = nav.activeStartTime;
    if (activeStart == null || !nav.timeCalculationSettings.enabled || nav.routes.isEmpty) return null;

    final perNavExt = <String, int>{};
    for (final navigatorId in nav.routes.keys) {
      perNavExt[navigatorId] = _extensionRequests
          .where((r) => r.navigatorId == navigatorId && r.status == ExtensionRequestStatus.approved)
          .fold<int>(0, (sum, r) => sum + (r.approvedMinutes ?? 0));
    }

    return GeometryUtils.calculateSafetyTime(
      activeStartTime: activeStart,
      routes: nav.routes,
      settings: nav.timeCalculationSettings,
      perNavigatorExtensionMinutes: perNavExt,
    );
  }

  void _startSafetyTimeMonitor() {
    // בדיקה ראשונית אחרי השהיה קצרה (המתנה לטעינת נתונים)
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) _checkSafetyTimeAlerts();
    });
    _safetyTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _checkSafetyTimeAlerts();
    });
  }

  void _checkSafetyTimeAlerts() {
    final safetyTime = _computeSafetyTime();
    if (safetyTime == null) return;
    final now = DateTime.now();
    final minutesUntilSafety = safetyTime.difference(now).inMinutes;

    // איפוס דגלים אם שעת הבטיחות התרחקה (הארכה אושרה)
    if (minutesUntilSafety > 10) {
      _safetyWarningShown = false;
      _safetyAlertShown = false;
      return;
    }

    // 10 דקות לפני — התראה שקטה
    if (minutesUntilSafety <= 10 && minutesUntilSafety > 0 && !_safetyWarningShown) {
      _safetyWarningShown = true;
      AlertSoundService().playAlert(AlertType.noMovement, 0.6);
      _showSafetyWarningDialog(safetyTime, minutesUntilSafety);
    }

    // הגעה לשעת בטיחות — סירנה
    if (minutesUntilSafety <= 0 && !_safetyAlertShown) {
      _safetyAlertShown = true;
      AlertSoundService().playAlert(AlertType.emergency, 1.0);
      _showSafetyReachedDialog(safetyTime);
    }
  }

  void _showSafetyWarningDialog(DateTime safetyTime, int minutesLeft) {
    if (!mounted) return;
    final timeStr = '${safetyTime.hour.toString().padLeft(2, '0')}:${safetyTime.minute.toString().padLeft(2, '0')}';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            SizedBox(width: 8),
            Expanded(child: Text('שעת בטיחות מתקרבת', style: TextStyle(color: Colors.orange))),
          ],
        ),
        content: Text(
          'עוד $minutesLeft דקות תגיע שעת הבטיחות ($timeStr).\n'
          'יש לוודא שכל המנווטים במסלול חזרה.',
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('הבנתי'),
          ),
        ],
      ),
    );
  }

  void _showSafetyReachedDialog(DateTime safetyTime) {
    if (!mounted) return;
    final timeStr = '${safetyTime.hour.toString().padLeft(2, '0')}:${safetyTime.minute.toString().padLeft(2, '0')}';
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.crisis_alert, color: Colors.red, size: 28),
            SizedBox(width: 8),
            Expanded(child: Text('שעת בטיחות הגיעה!', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
          ],
        ),
        content: Text(
          'שעת הבטיחות ($timeStr) הגיעה.\n'
          'יש לוודא מיידית שכל המנווטים בטוחים!',
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('הבנתי', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // Emergency Broadcast
  // =========================================================================

  void _startEmergencyFlagListener() {
    _emergencyFlagListener = _navRepo
        .watchNavigationDocSnapshot(widget.navigation.id)
        .listen((snap) {
      if (!mounted || _alreadyClosed) return;

      // Detect external status change — another admin finished the navigation
      final status = snap.navigation?.status;
      const finishedStatuses = {'review', 'approval'};
      if (status != null && finishedStatuses.contains(status)) {
        _alreadyClosed = true;
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('הניווט הסתיים על ידי מפקד אחר'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      final active = snap.emergencyActive;
      final mode = snap.emergencyMode;
      final broadcastId = snap.activeBroadcastId;

      if (active != _emergencyActive || mode != _emergencyMode) {
        setState(() {
          _emergencyActive = active;
          _emergencyMode = mode;
        });

        if (active && broadcastId != null && broadcastId != _activeBroadcastId) {
          _activeBroadcastId = broadcastId;
          _startAckListener(broadcastId);
          _startAutoRetryTimer(broadcastId);

          // שידור חירום — הודעה למפקדים אחרים (שלא הפעילו את השידור)
          if (!_iSentEmergencyBroadcast && broadcastId != _lastShownCommanderBroadcastId) {
            EmergencyBroadcastRepository()
                .getBroadcastDoc(widget.navigation.id, broadcastId)
                .then((data) {
              if (!mounted || _commanderEmergencyDialogShowing) return;
              data ??= {};
              _showCommanderEmergencyDialog(
                message: data['message'] as String? ?? '',
                instructions: data['instructions'] as String? ?? '',
                broadcastId: broadcastId,
              );
            });
          }
          _iSentCancelBroadcast = false;
        } else if (!active) {
          // חזרה לשגרה — הודעה למפקדים אחרים (שלא ביטלו)
          if (_wasInCommanderEmergency && !_iSentCancelBroadcast) {
            _wasInCommanderEmergency = false;
            _showCommanderReturnToRoutineDialog(
              cancelBroadcastId: snap.cancelBroadcastId,
            );
          }
          _iSentEmergencyBroadcast = false;

          _ackListener?.cancel();
          _autoRetryTimer?.cancel();
          _activeBroadcastId = null;
          _acknowledgedBy = [];
        }
      }
    });
  }

  void _showEmergencyBroadcastDialog() {
    // חסימה — אי אפשר להפעיל חירום נוסף כשכבר פעיל
    if (_emergencyActive) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.orange[50],
          icon: const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 48),
          title: const Text('מצב חירום כבר פעיל', style: TextStyle(color: Colors.orange)),
          content: const Text(
            'לא ניתן להפעיל שידור חירום נוסף.\n'
            'יש לבטל את מצב החירום הנוכחי (חזרה לשגרה) לפני הפעלת שידור חדש.',
            textAlign: TextAlign.center,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('הבנתי'),
            ),
          ],
        ),
      );
      return;
    }

    final messageController = TextEditingController();
    final instructionsController = TextEditingController();
    int emergencyMode = 2; // ברירת מחדל: מלא

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: Colors.red[50],
          title: Row(
            children: [
              const Icon(Icons.campaign, color: Colors.red, size: 28),
              const SizedBox(width: 8),
              const Text('שידור חירום', style: TextStyle(color: Colors.red)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: messageController,
                  maxLines: 2,
                  textDirection: TextDirection.rtl,
                  onChanged: (_) => setDialogState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'מה קרה *',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: instructionsController,
                  maxLines: 2,
                  textDirection: TextDirection.rtl,
                  decoration: const InputDecoration(
                    labelText: 'הנחיות (אופציונלי)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                const Text('פתיחת מפה למנווטים:', style: TextStyle(fontWeight: FontWeight.bold)),
                RadioListTile<int>(
                  title: const Text('ללא פתיחת מפה'),
                  value: 0,
                  groupValue: emergencyMode,
                  activeColor: Colors.red,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  onChanged: (v) => setDialogState(() => emergencyMode = v!),
                ),
                RadioListTile<int>(
                  title: const Text('פתח מפה ומיקום עצמי לכולם'),
                  value: 1,
                  groupValue: emergencyMode,
                  activeColor: Colors.red,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  onChanged: (v) => setDialogState(() => emergencyMode = v!),
                ),
                RadioListTile<int>(
                  title: const Text('פתח מפה + מיקום עצמי + מיקומי כל המשתתפים'),
                  value: 2,
                  groupValue: emergencyMode,
                  activeColor: Colors.red,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  onChanged: (v) => setDialogState(() => emergencyMode = v!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('ביטול'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.send),
              label: const Text('שלח שידור'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: messageController.text.trim().isEmpty
                  ? null
                  : () {
                      Navigator.of(ctx).pop();
                      _sendEmergencyBroadcast(
                        messageController.text.trim(),
                        instructionsController.text.trim(),
                        emergencyMode,
                      );
                    },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendEmergencyBroadcast(
    String message,
    String instructions,
    int emergencyMode,
  ) async {
    _iSentEmergencyBroadcast = true;
    try {
      final me = _currentUser?.uid;
      final participants = <String>{
        ...widget.navigation.selectedParticipantIds,
        ...widget.navigation.permissions.managers,
        widget.navigation.createdBy,
      }.where((uid) => uid != me).toList();
      await EmergencyBroadcastRepository().createBroadcast(
        widget.navigation.id,
        message: message,
        instructions: instructions,
        emergencyMode: emergencyMode,
        createdBy: _currentUser?.uid ?? '',
        participants: participants,
      );
    } catch (e) {
      print('DEBUG NavigationManagement: send emergency broadcast error: $e');
    }
  }

  /// ביטול מצב חירום — עם אישור
  void _showDeactivateConfirmation() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ביטול מצב חירום'),
        content: const Text('האם לבטל מצב חירום?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('לא'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _deactivateEmergencyMode();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('כן, חזרה לשגרה'),
          ),
        ],
      ),
    );
  }

  Future<void> _deactivateEmergencyMode() async {
    _iSentCancelBroadcast = true;
    try {
      final me = _currentUser?.uid;
      final participants = <String>{
        ...widget.navigation.selectedParticipantIds,
        ...widget.navigation.permissions.managers,
        widget.navigation.createdBy,
      }.where((uid) => uid != me).toList();

      final cancelDocId = await EmergencyBroadcastRepository().cancelBroadcast(
        widget.navigation.id,
        activeBroadcastId: _activeBroadcastId,
        createdBy: _currentUser?.uid ?? '',
        participants: participants,
      );

      // מעקב אישורי ביטול
      setState(() {
        _cancelBroadcastId = cancelDocId;
        _cancelAcknowledgedBy = [];
      });
      _startCancelAckListener(cancelDocId);
      _startCancelAutoRetryTimer(cancelDocId);

      // ביטול מעקב חירום
      _autoRetryTimer?.cancel();
      _ackListener?.cancel();
    } catch (e) {
      print('DEBUG NavigationManagement: deactivate emergency error: $e');
    }
  }

  // =========================================================================
  // Commander Emergency Dialog (for other commanders)
  // =========================================================================

  void _initCommanderEmergencyAlarm() {
    _commanderEmergencyPlayer = AudioPlayer();
    _commanderEmergencyPlayer!.setAudioContext(AudioContext(
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
  }

  /// דיאלוג חירום למפקדים — כמו של מנווט אבל בלי פתיחת מפה
  void _showCommanderEmergencyDialog({
    required String message,
    required String instructions,
    String? broadcastId,
  }) {
    if (_commanderEmergencyDialogShowing || _commanderRoutineDialogShowing) return;
    _commanderEmergencyDialogShowing = true;
    _wasInCommanderEmergency = true;
    _lastShownCommanderBroadcastId = broadcastId;

    // הפעלת סירנת חירום
    _commanderEmergencyPlayer?.setReleaseMode(ReleaseMode.loop);
    _commanderEmergencyPlayer?.play(AssetSource('sounds/emergency_siren.wav'));

    // רטט כל 2 שניות
    _commanderVibrationTimer?.cancel();
    _commanderVibrationTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      HapticFeedback.heavyImpact();
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: Colors.red[50],
          icon: const Icon(Icons.campaign, color: Colors.red, size: 48),
          title: const Text(
            'שידור חירום',
            style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(message, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              if (instructions.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    border: Border.all(color: Colors.orange),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline, color: Colors.orange, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(instructions, style: const TextStyle(fontSize: 14)),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.check_circle),
                label: const Text('אישור והבנתי'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () {
                  _commanderEmergencyPlayer?.stop();
                  _commanderVibrationTimer?.cancel();
                  _commanderEmergencyDialogShowing = false;
                  Navigator.of(ctx).pop();

                  // כתיבת אישור קבלה
                  if (broadcastId != null && _currentUser != null) {
                    EmergencyBroadcastRepository().acknowledge(
                      widget.navigation.id, broadcastId, _currentUser!.uid);
                  }
                  // מפקדים — אין פתיחת מפה
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// דיאלוג חזרה לשגרה למפקדים — כמו של מנווט אבל בלי סגירת מפה
  void _showCommanderReturnToRoutineDialog({String? cancelBroadcastId}) {
    if (_commanderRoutineDialogShowing) return;

    // סגירת דיאלוג חירום אם עדיין פתוח
    if (_commanderEmergencyDialogShowing) {
      _commanderEmergencyPlayer?.stop();
      _commanderVibrationTimer?.cancel();
      _commanderEmergencyDialogShowing = false;
      Navigator.of(context).pop();
    }

    _commanderRoutineDialogShowing = true;

    // הפעלת סירנה — חזרה לשגרה
    _commanderEmergencyPlayer?.setReleaseMode(ReleaseMode.loop);
    _commanderEmergencyPlayer?.play(AssetSource('sounds/emergency_siren.wav'));

    // רטט כל 2 שניות
    _commanderVibrationTimer?.cancel();
    _commanderVibrationTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      HapticFeedback.heavyImpact();
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: Colors.green[50],
          icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
          title: const Text(
            'חזרה לשגרה',
            style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          content: const Text(
            'חזרה לשגרה — המשך בניווט',
            style: TextStyle(fontSize: 16),
            textAlign: TextAlign.center,
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.check_circle),
                label: const Text('אישור'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () {
                  _commanderEmergencyPlayer?.stop();
                  _commanderVibrationTimer?.cancel();
                  _commanderRoutineDialogShowing = false;
                  Navigator.of(ctx).pop();

                  // כתיבת אישור קבלה לביטול
                  if (cancelBroadcastId != null && _currentUser != null) {
                    EmergencyBroadcastRepository().acknowledge(
                      widget.navigation.id, cancelBroadcastId, _currentUser!.uid);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // Acknowledgment Tracking
  // =========================================================================

  void _startAckListener(String broadcastId) {
    _ackListener?.cancel();
    _ackListener = EmergencyBroadcastRepository()
        .watchBroadcast(widget.navigation.id, broadcastId)
        .listen((data) {
      if (!mounted) return;
      if (data == null) return;
      final acked = List<String>.from(data['acknowledgedBy'] ?? []);
      setState(() => _acknowledgedBy = acked);
    });
  }

  void _startAutoRetryTimer(String broadcastId) {
    _autoRetryTimer?.cancel();
    _autoRetryTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _resendToUnacknowledged(broadcastId);
    });
  }

  Future<void> _resendToUnacknowledged(String broadcastId) async {
    try {
      await EmergencyBroadcastRepository().resendToUnacknowledged(
        widget.navigation.id,
        broadcastId,
      );
    } catch (e) {
      print('DEBUG NavigationManagement: auto-retry error: $e');
    }
  }

  void _startCancelAckListener(String cancelBroadcastId) {
    _cancelAckListener?.cancel();
    _cancelAckListener = EmergencyBroadcastRepository()
        .watchBroadcast(widget.navigation.id, cancelBroadcastId)
        .listen((data) {
      if (!mounted) return;
      if (data == null) return;
      final acked = List<String>.from(data['acknowledgedBy'] ?? []);
      setState(() => _cancelAcknowledgedBy = acked);
    });
  }

  void _startCancelAutoRetryTimer(String cancelBroadcastId) {
    _cancelAutoRetryTimer?.cancel();
    _cancelAutoRetryTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _resendCancelToUnacknowledged(cancelBroadcastId);
    });
  }

  Future<void> _resendCancelToUnacknowledged(String cancelBroadcastId) async {
    try {
      await EmergencyBroadcastRepository().resendCancelToUnacknowledged(
        widget.navigation.id,
        cancelBroadcastId,
      );
    } catch (e) {
      print('DEBUG NavigationManagement: cancel auto-retry error: $e');
    }
  }

  List<String> get _allEmergencyParticipants {
    final me = _currentUser?.uid;
    return <String>{
      ...widget.navigation.selectedParticipantIds,
      ...widget.navigation.permissions.managers,
      widget.navigation.createdBy,
    }.where((uid) => uid != me).toList();
  }

  Widget _buildAckPanel({
    required String title,
    required List<String> acknowledgedBy,
    required Color color,
    required VoidCallback onResend,
  }) {
    final allParticipants = _allEmergencyParticipants;
    final total = allParticipants.length;
    final acked = acknowledgedBy.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: color.withOpacity(0.1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(acked >= total ? Icons.check_circle : Icons.pending, color: color, size: 18),
              const SizedBox(width: 6),
              Text(
                '$title — $acked/$total אישרו קבלה',
                style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13),
              ),
              const Spacer(),
              if (acked < total)
                TextButton.icon(
                  icon: Icon(Icons.send, size: 14, color: color),
                  label: Text('שלח שוב', style: TextStyle(fontSize: 12, color: color)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 28),
                  ),
                  onPressed: onResend,
                ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 2,
            children: allParticipants.map((uid) {
              final ackd = acknowledgedBy.contains(uid);
              final name = _userNames[uid] ?? uid;
              return Chip(
                avatar: Icon(ackd ? Icons.check : Icons.close, size: 14,
                    color: ackd ? Colors.green : Colors.red),
                label: Text(name, style: const TextStyle(fontSize: 11)),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  void _showExtensionPopup(ExtensionRequest req) {
    if (!mounted) return;
    int adjustedMinutes = req.requestedMinutes;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.timer, color: Colors.purple, size: 28),
                const SizedBox(width: 8),
                const Expanded(child: Text('בקשת הארכה', style: TextStyle(color: Colors.purple))),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${req.navigatorName} מבקש ${req.requestedMinutes} דקות הארכה',
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 16),
                const Text('התאם זמן:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: adjustedMinutes > 5
                          ? () => setDialogState(() => adjustedMinutes -= 5)
                          : null,
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.purple.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$adjustedMinutes דק\'',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.purple,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: adjustedMinutes < 120
                          ? () => setDialogState(() => adjustedMinutes += 5)
                          : null,
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
                Slider(
                  value: adjustedMinutes.toDouble(),
                  min: 5,
                  max: 120,
                  divisions: 23,
                  label: '$adjustedMinutes דק\'',
                  activeColor: Colors.purple,
                  onChanged: (v) => setDialogState(() => adjustedMinutes = v.round()),
                ),
              ],
            ),
            actionsAlignment: MainAxisAlignment.spaceBetween,
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  // הזכר עוד 5 דק'
                  _extensionSnoozeTimer?.cancel();
                  _extensionSnoozeTimer = Timer(const Duration(minutes: 5), () {
                    // בדוק שעדיין ממתין
                    final stillPending = _extensionRequests.any(
                        (r) => r.id == req.id && r.status == ExtensionRequestStatus.pending);
                    if (stillPending && mounted) {
                      _shownExtensionPopups.remove(req.id);
                      _showExtensionPopup(req);
                    }
                  });
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('תזכורת תופיע בעוד 5 דקות')),
                    );
                  }
                },
                child: const Text('הזכר עוד 5 דק\''),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _respondToExtension(req, ExtensionRequestStatus.rejected);
                    },
                    icon: const Icon(Icons.close, color: Colors.red, size: 18),
                    label: const Text('דחה', style: TextStyle(color: Colors.red)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _respondToExtension(
                        req,
                        ExtensionRequestStatus.approved,
                        approvedMinutes: adjustedMinutes,
                      );
                    },
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('אשר'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          );
        });
      },
    );
  }

  void _showExtensionApproveDialog(ExtensionRequest req) {
    int adjustedMinutes = req.requestedMinutes;
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('אישור הארכה'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${req.navigatorName} מבקש ${req.requestedMinutes} דקות'),
                const SizedBox(height: 16),
                const Text('התאם זמן:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: adjustedMinutes > 5
                          ? () => setDialogState(() => adjustedMinutes -= 5)
                          : null,
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    Text(
                      '$adjustedMinutes דק\'',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.purple),
                    ),
                    IconButton(
                      onPressed: adjustedMinutes < 120
                          ? () => setDialogState(() => adjustedMinutes += 5)
                          : null,
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
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
                  _respondToExtension(req, ExtensionRequestStatus.approved, approvedMinutes: adjustedMinutes);
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: const Text('אשר', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        });
      },
    );
  }

  Future<void> _respondToExtension(
    ExtensionRequest req,
    ExtensionRequestStatus status, {
    int? approvedMinutes,
  }) async {
    try {
      await _extensionRepo.respond(
        navigationId: widget.navigation.id,
        requestId: req.id,
        status: status,
        approvedMinutes: approvedMinutes,
        respondedBy: _currentUser?.uid ?? '',
      );
      if (mounted) {
        final msg = status == ExtensionRequestStatus.approved
            ? 'הארכה של ${approvedMinutes ?? 0} דקות אושרה ל-${req.navigatorName}'
            : 'בקשת הארכה של ${req.navigatorName} נדחתה';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: status == ExtensionRequestStatus.approved ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}

/// נתונים חיים של מנווט
class NavigatorLiveData {
  final String navigatorId;
  NavigatorPersonalStatus personalStatus;
  bool hasActiveAlert;
  bool isGpsPlusFix;
  bool isDisqualified; // מנווט נפסל (פריצת אבטחה)
  String? disqualificationReason; // סיבת הפסילה
  LatLng? currentPosition;
  List<TrackPoint> trackPoints;
  List<CheckpointPunch> punches;
  DateTime? lastUpdate;
  int? batteryLevel; // 0-100%, null = לא ידוע
  bool hasMicrophonePermission;
  bool hasPhonePermission;
  bool hasDNDPermission;
  DateTime? resetAt; // set when navigator is reset/restarted
  DateTime? trackStartedAt; // זמן התחלה אישי של המנווט (מה-track doc)
  DateTime? trackEndedAt; // זמן סיום אישי של המנווט (מה-track doc)

  // ניווט כוכב
  int? starCurrentPointIndex;
  DateTime? starLearningEndTime;
  DateTime? starNavigatingEndTime;
  bool starReturnedToCenter;

  NavigatorLiveData({
    required this.navigatorId,
    required this.personalStatus,
    this.hasActiveAlert = false,
    this.isGpsPlusFix = false,
    this.isDisqualified = false,
    this.disqualificationReason,
    this.currentPosition,
    required this.trackPoints,
    required this.punches,
    this.lastUpdate,
    this.batteryLevel,
    this.hasMicrophonePermission = false,
    this.hasPhonePermission = false,
    this.hasDNDPermission = false,
    this.resetAt,
    this.trackStartedAt,
    this.trackEndedAt,
    this.starCurrentPointIndex,
    this.starLearningEndTime,
    this.starNavigatingEndTime,
    this.starReturnedToCenter = false,
  });

  /// מרחק כולל שנעבר בק"מ
  double get totalDistanceKm {
    if (trackPoints.length < 2) return 0.0;
    double totalMeters = 0.0;
    for (int i = 0; i < trackPoints.length - 1; i++) {
      totalMeters += GeometryUtils.distanceBetweenMeters(
        trackPoints[i].coordinate,
        trackPoints[i + 1].coordinate,
      );
    }
    return totalMeters / 1000.0;
  }

  /// מהירות נוכחית (קמ"ש)
  double get currentSpeedKmh {
    if (trackPoints.isEmpty) return 0.0;
    final speed = trackPoints.last.speed;
    if (speed == null || speed < 0) return 0.0;
    return speed * 3.6; // m/s → km/h
  }

  /// מהירות ממוצעת (קמ"ש)
  double get averageSpeedKmh {
    if (trackPoints.isEmpty) return 0.0;
    final speeds = trackPoints
        .where((p) => p.speed != null && p.speed! > 0)
        .map((p) => p.speed!)
        .toList();
    if (speeds.isEmpty) return 0.0;
    return (speeds.reduce((a, b) => a + b) / speeds.length) * 3.6;
  }

  /// זמן שחלף מתחילת הניווט
  Duration get elapsedTime {
    if (trackPoints.length < 2) return Duration.zero;
    return trackPoints.last.timestamp.difference(trackPoints.first.timestamp);
  }

  /// זמן מאז עדכון אחרון
  Duration get timeSinceLastUpdate {
    if (lastUpdate == null) return Duration.zero;
    return DateTime.now().difference(lastUpdate!);
  }
}

/// הגעה לנקודת ציון — נ"צ + דקירה (אם הגיע)
class _CheckpointArrival {
  final Checkpoint checkpoint;
  final CheckpointPunch? punch;
  final VerificationSettings verificationSettings;

  _CheckpointArrival({
    required this.checkpoint,
    this.punch,
    required this.verificationSettings,
  });

  bool get reached {
    if (punch == null) return false;
    final dist = punch!.distanceFromCheckpoint;
    if (dist == null) return true; // אין מידע מרחק — נחשב הגעה

    // תמיד בודק לפי כללי המרחק שהוגדרו — גם אם אימות אוטומטי כבוי
    switch (verificationSettings.verificationType) {
      case 'approved_failed':
        final limit = verificationSettings.approvalDistance ?? 100;
        return dist <= limit;
      case 'score_by_distance':
        final ranges = verificationSettings.scoreRanges;
        if (ranges == null || ranges.isEmpty) return true;
        final maxDist = ranges.map((r) => r.maxDistance).reduce((a, b) => a > b ? a : b);
        return dist <= maxDist;
      default:
        // אין סוג אימות מוגדר — fallback למרחק סביר (100 מ')
        return dist <= 100;
    }
  }
}

/// קונטיינר מונפש לתפריט טקטי (fade + scale)
class _AnimatedTacticalContainer extends StatefulWidget {
  final Widget child;

  const _AnimatedTacticalContainer({required this.child});

  @override
  State<_AnimatedTacticalContainer> createState() => _AnimatedTacticalContainerState();
}

class _AnimatedTacticalContainerState extends State<_AnimatedTacticalContainer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _scaleAnimation = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        alignment: Alignment.topRight,
        child: widget.child,
      ),
    );
  }
}

/// מרחק בין זוג מנווטים
class _NavigatorPairDistance {
  final String navigatorA;
  final String navigatorB;
  final double distanceMeters;

  _NavigatorPairDistance({
    required this.navigatorA,
    required this.navigatorB,
    required this.distanceMeters,
  });

  String get displayDistance {
    if (distanceMeters >= 1000) {
      return '${(distanceMeters / 1000).toStringAsFixed(1)} ק"מ';
    }
    return '${distanceMeters.toStringAsFixed(0)} מ\'';
  }
}

// =============================================================================
// Global Settings Content — StatefulWidget inside bottom sheet
// =============================================================================

class _GlobalSettingsContent extends StatefulWidget {
  final domain.Navigation navigation;
  final ScrollController scrollController;
  /// callback: (updatedNav, settingName, overrideType) → saved nav or null if cancelled
  final Future<domain.Navigation?> Function(domain.Navigation, String, String?) onSettingChanged;

  const _GlobalSettingsContent({
    required this.navigation,
    required this.scrollController,
    required this.onSettingChanged,
  });

  @override
  State<_GlobalSettingsContent> createState() => _GlobalSettingsContentState();
}

class _GlobalSettingsContentState extends State<_GlobalSettingsContent> {
  static const Map<int, String> _gpsSyncIntervalLabels = {
    5: '5 שניות',
    15: '15 שניות',
    30: '30 שניות',
    60: 'דקה',
    120: '2 דקות',
    300: '5 דקות',
    600: '10 דקות',
    1800: '30 דקות',
    3600: 'שעה',
    7200: 'שעתיים',
  };

  late domain.Navigation _nav;

  @override
  void initState() {
    super.initState();
    _nav = widget.navigation;
  }

  @override
  void didUpdateWidget(covariant _GlobalSettingsContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.navigation != widget.navigation) {
      _nav = widget.navigation;
    }
  }

  Future<void> _applySetting(domain.Navigation updated, String name, String? overrideType) async {
    final result = await widget.onSettingChanged(updated, name, overrideType);
    if (result != null && mounted) {
      setState(() => _nav = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Handle
        Container(
          margin: const EdgeInsets.only(top: 12, bottom: 8),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.white38,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(
            'הגדרות ניווט',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        const Divider(color: Colors.white24),
        Expanded(
          child: ListView(
            controller: widget.scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            children: [
              _buildMapPermissionsGroup(),
              _buildAlertsGroup(),
              _buildGpsGroup(),
              _buildCommunicationGroup(),
              if (_nav.usesClusters) _buildClusterRevealGroup(),
              if (_nav.navigationType == 'star') _buildStarSettingsGroup(),
              _buildTimeExtensionsGroup(),
              _buildVerificationGroup(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ],
    );
  }

  // ── Group 1: הרשאות מפה ────────────────────────────────────────────────────

  Widget _buildMapPermissionsGroup() {
    return _settingsGroup(
      title: 'הרשאות מפה',
      icon: Icons.map_outlined,
      children: [
        _toggleTile(
          label: 'אפשר ניווט עם מפה פתוחה',
          value: _nav.allowOpenMap,
          onChanged: (v) => _applySetting(
            _nav.copyWith(
              allowOpenMap: v,
              showSelfLocation: v ? _nav.showSelfLocation : false,
              showRouteOnMap: v ? _nav.showRouteOnMap : false,
            ),
            'אפשר ניווט עם מפה פתוחה',
            'allowOpenMap',
          ),
        ),
        if (_nav.allowOpenMap)
          _toggleTile(
            label: 'הצגת מיקום עצמי',
            value: _nav.showSelfLocation,
            onChanged: (v) => _applySetting(
              _nav.copyWith(showSelfLocation: v),
              'הצגת מיקום עצמי',
              'showSelfLocation',
            ),
          ),
        _toggleTile(
          label: 'אפשר דיווח מיקום ידני',
          value: _nav.allowManualPosition,
          onChanged: (v) => _applySetting(
            _nav.copyWith(allowManualPosition: v),
            'אפשר דיווח מיקום ידני',
            null,
          ),
        ),
      ],
    );
  }

  // ── Group 2: התראות ────────────────────────────────────────────────────────

  Widget _buildAlertsGroup() {
    final alerts = _nav.alerts;
    return _settingsGroup(
      title: 'התראות',
      icon: Icons.notifications_outlined,
      children: [
        // טוגלים עם סלידרים + פקדי עוצמה
        _alertToggleWithSlider(
          label: 'מהירות',
          enabled: alerts.speedAlertEnabled,
          onToggle: (v) => _applySetting(
            _nav.copyWith(alerts: alerts.copyWith(speedAlertEnabled: v)),
            'התראת מהירות',
            'alertToggle',
          ),
          volumeControl: _buildAlertVolumeControl(AlertType.speed.code),
          sliderLabel: 'מהירות מקסימלית',
          sliderSuffix: ' קמ"ש',
          value: (alerts.maxSpeed ?? 30).toDouble(),
          min: 10,
          max: 120,
          divisions: 22,
          onSliderChanged: (v) => _applySetting(
            _nav.copyWith(alerts: alerts.copyWith(maxSpeed: v.round())),
            'מהירות מקסימלית',
            null,
          ),
          showSlider: alerts.speedAlertEnabled,
        ),
        _alertToggleWithSlider(
          label: 'ללא תנועה',
          enabled: alerts.noMovementAlertEnabled,
          onToggle: (v) => _applySetting(
            _nav.copyWith(alerts: alerts.copyWith(noMovementAlertEnabled: v)),
            'התראת ללא תנועה',
            'alertToggle',
          ),
          volumeControl: _buildAlertVolumeControl(AlertType.noMovement.code),
          sliderLabel: 'דקות ללא תנועה',
          sliderSuffix: ' דק\'',
          value: (alerts.noMovementMinutes ?? 10).toDouble(),
          min: 1,
          max: 60,
          divisions: 59,
          onSliderChanged: (v) => _applySetting(
            _nav.copyWith(alerts: alerts.copyWith(noMovementMinutes: v.round())),
            'זמן ללא תנועה',
            null,
          ),
          showSlider: alerts.noMovementAlertEnabled,
        ),
        _alertToggleWithSlider(
          label: 'חריגה מג"ג',
          enabled: alerts.ggAlertEnabled,
          onToggle: (v) => _applySetting(
            _nav.copyWith(alerts: alerts.copyWith(ggAlertEnabled: v)),
            'התראת חריגה מג"ג',
            'alertToggle',
          ),
          volumeControl: _buildAlertVolumeControl(AlertType.boundary.code),
          sliderLabel: 'טווח התראה',
          sliderSuffix: ' מ\'',
          value: (alerts.ggAlertRange ?? 50).toDouble(),
          min: 10,
          max: 500,
          divisions: 49,
          onSliderChanged: (v) => _applySetting(
            _nav.copyWith(alerts: alerts.copyWith(ggAlertRange: v.round())),
            'טווח התראת ג"ג',
            null,
          ),
          showSlider: alerts.ggAlertEnabled,
        ),
        _alertToggleWithSlider(
          label: 'סטייה מציר',
          enabled: alerts.routesAlertEnabled,
          onToggle: (v) => _applySetting(
            _nav.copyWith(alerts: alerts.copyWith(routesAlertEnabled: v)),
            'התראת סטייה מציר',
            'alertToggle',
          ),
          volumeControl: _buildAlertVolumeControl(AlertType.routeDeviation.code),
          sliderLabel: 'טווח סטייה',
          sliderSuffix: ' מ\'',
          value: (alerts.routesAlertRange ?? 50).toDouble(),
          min: 10,
          max: 500,
          divisions: 49,
          onSliderChanged: (v) => _applySetting(
            _nav.copyWith(alerts: alerts.copyWith(routesAlertRange: v.round())),
            'טווח סטייה מציר',
            null,
          ),
          showSlider: alerts.routesAlertEnabled,
        ),
        _alertToggleWithSlider(
          label: 'נ"ב',
          enabled: alerts.nbAlertEnabled,
          onToggle: (v) => _applySetting(
            _nav.copyWith(alerts: alerts.copyWith(nbAlertEnabled: v)),
            'התראת נ"ב',
            'alertToggle',
          ),
          volumeControl: _buildAlertVolumeControl(AlertType.safetyPoint.code),
          sliderLabel: 'טווח נ"ב',
          sliderSuffix: ' מ\'',
          value: (alerts.nbAlertRange ?? 50).toDouble(),
          min: 10,
          max: 500,
          divisions: 49,
          onSliderChanged: (v) => _applySetting(
            _nav.copyWith(alerts: alerts.copyWith(nbAlertRange: v.round())),
            'טווח נ"ב',
            null,
          ),
          showSlider: alerts.nbAlertEnabled,
        ),
        _alertToggleWithSlider(
          label: 'קרבה בין מנווטים',
          enabled: alerts.navigatorProximityAlertEnabled,
          onToggle: (v) => _applySetting(
            _nav.copyWith(alerts: alerts.copyWith(navigatorProximityAlertEnabled: v)),
            'התראת קרבה בין מנווטים',
            'alertToggle',
          ),
          volumeControl: _buildAlertVolumeControl(AlertType.proximity.code),
          sliderLabel: 'מרחק קרבה',
          sliderSuffix: ' מ\'',
          value: (alerts.proximityDistance ?? 20).toDouble(),
          min: 5,
          max: 200,
          divisions: 39,
          onSliderChanged: (v) => _applySetting(
            _nav.copyWith(alerts: alerts.copyWith(proximityDistance: v.round())),
            'מרחק קרבה',
            null,
          ),
          showSlider: alerts.navigatorProximityAlertEnabled,
          extraSlider: alerts.navigatorProximityAlertEnabled
              ? _sliderRow(
                  label: 'זמן קרבה',
                  suffix: ' דק\'',
                  value: (alerts.proximityMinTime ?? 5).toDouble(),
                  min: 1,
                  max: 30,
                  divisions: 29,
                  onChanged: (v) => _applySetting(
                    _nav.copyWith(alerts: alerts.copyWith(proximityMinTime: v.round())),
                    'זמן קרבה מינימלי',
                    null,
                  ),
                )
              : null,
        ),
        _alertToggleWithSlider(
          label: 'סוללה',
          enabled: alerts.batteryAlertEnabled,
          onToggle: (v) => _applySetting(
            _nav.copyWith(alerts: alerts.copyWith(batteryAlertEnabled: v)),
            'התראת סוללה',
            'alertToggle',
          ),
          volumeControl: _buildAlertVolumeControl(AlertType.battery.code),
          sliderLabel: 'סף סוללה',
          sliderSuffix: '%',
          value: (alerts.batteryPercentage ?? 20).toDouble(),
          min: 5,
          max: 50,
          divisions: 9,
          onSliderChanged: (v) => _applySetting(
            _nav.copyWith(alerts: alerts.copyWith(batteryPercentage: v.round())),
            'סף סוללה',
            null,
          ),
          showSlider: alerts.batteryAlertEnabled,
        ),
        _alertToggleWithSlider(
          label: 'היעדר קליטה',
          enabled: alerts.noReceptionAlertEnabled,
          onToggle: (v) => _applySetting(
            _nav.copyWith(alerts: alerts.copyWith(noReceptionAlertEnabled: v)),
            'התראת היעדר קליטה',
            'alertToggle',
          ),
          volumeControl: _buildAlertVolumeControl(AlertType.noReception.code),
          sliderLabel: 'זמן ללא קליטה',
          sliderSuffix: ' שנ\'',
          value: (alerts.noReceptionMinTime ?? 60).toDouble(),
          min: 10,
          max: 300,
          divisions: 29,
          onSliderChanged: (v) => _applySetting(
            _nav.copyWith(alerts: alerts.copyWith(noReceptionMinTime: v.round())),
            'זמן ללא קליטה',
            null,
          ),
          showSlider: alerts.noReceptionAlertEnabled,
        ),
        _alertToggleWithSlider(
          label: 'דיווח תקינות',
          enabled: alerts.healthCheckEnabled,
          onToggle: (v) => _applySetting(
            _nav.copyWith(alerts: alerts.copyWith(healthCheckEnabled: v)),
            'דיווח תקינות',
            'alertToggle',
          ),
          volumeControl: _buildAlertVolumeControl(AlertType.healthCheckExpired.code),
          sliderLabel: 'תדירות בדיקה',
          sliderSuffix: ' דק\'',
          value: alerts.healthCheckIntervalMinutes.toDouble(),
          min: 15,
          max: 600,
          divisions: 39,
          onSliderChanged: (v) => _applySetting(
            _nav.copyWith(alerts: alerts.copyWith(healthCheckIntervalMinutes: v.round())),
            'תדירות בדיקת תקינות',
            null,
          ),
          showSlider: alerts.healthCheckEnabled,
        ),
        // קטגוריות צליל נוספות
        const Divider(),
        _buildCategorySoundRow(label: '📋 בקשות הארכה', alertCode: AlertType.extensionRequest.code),
        _buildCategorySoundRow(label: '⚠️ ברבור', alertCode: AlertType.barbur.code),
        _buildCategorySoundRow(label: '🚨 חירום מנווט', alertCode: AlertType.emergency.code),
      ],
    );
  }

  // ── Group 3: GPS ומיקום ────────────────────────────────────────────────────

  Widget _buildGpsGroup() {
    final sources = _nav.enabledPositionSources;
    return _settingsGroup(
      title: 'GPS ומיקום',
      icon: Icons.gps_fixed,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('איכות דגימת מיקום', style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 30, label: Text('חסכוני'), icon: Icon(Icons.battery_saver)),
                    ButtonSegment(value: 5, label: Text('דינמי'), icon: Icon(Icons.speed)),
                    ButtonSegment(value: 1, label: Text('מדויק'), icon: Icon(Icons.gps_fixed)),
                  ],
                  selected: {_nav.gpsUpdateIntervalSeconds <= 2 ? 1 : _nav.gpsUpdateIntervalSeconds <= 10 ? 5 : 30},
                  onSelectionChanged: (Set<int> sel) => _applySetting(
                    _nav.copyWith(gpsUpdateIntervalSeconds: sel.first),
                    'איכות דגימת מיקום',
                    'gpsInterval',
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _nav.gpsUpdateIntervalSeconds <= 2
                    ? 'GPS רציף + PDR — צריכת סוללה גבוהה'
                    : _nav.gpsUpdateIntervalSeconds <= 10
                        ? 'איזון מושלם — דגימה כל 5 שניות'
                        : 'חיסכון סוללה — דגימה כל 30 שניות, ללא PDR',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('תדירות סנכרון מיקום', style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: DropdownButton<int>(
                  value: _gpsSyncIntervalLabels.containsKey(_nav.gpsSyncIntervalSeconds) ? _nav.gpsSyncIntervalSeconds : 30,
                  dropdownColor: const Color(0xFF2E2E2E),
                  style: const TextStyle(color: Colors.white),
                  isExpanded: true,
                  items: _gpsSyncIntervalLabels.entries
                      .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      _applySetting(
                        _nav.copyWith(gpsSyncIntervalSeconds: v),
                        'תדירות סנכרון מיקום',
                        'gpsSyncInterval',
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('מקורות מיקום', style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                children: [
                  _sourceChip('GPS', 'gps', sources),
                  _sourceChip('Cell Tower', 'cellTower', sources),
                  _sourceChip('PDR', 'pdr', sources),
                  _sourceChip('PDR+Cell', 'pdrCellHybrid', sources),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _toggleTile(
          label: 'זיהוי זיוף GPS',
          value: _nav.gpsSpoofingDetectionEnabled,
          onChanged: (v) => _applySetting(
            _nav.copyWith(gpsSpoofingDetectionEnabled: v),
            'זיהוי זיוף GPS',
            null,
          ),
        ),
        if (_nav.gpsSpoofingDetectionEnabled)
          _sliderRow(
            label: 'סף זיוף',
            suffix: ' ק"מ',
            value: _nav.gpsSpoofingMaxDistanceKm.toDouble(),
            min: 1,
            max: 100,
            divisions: 99,
            onChanged: (v) => _applySetting(
              _nav.copyWith(gpsSpoofingMaxDistanceKm: v.round()),
              'סף זיוף GPS',
              null,
            ),
          ),
      ],
    );
  }

  Widget _sourceChip(String label, String source, List<String> enabledSources) {
    final isEnabled = enabledSources.contains(source);
    return FilterChip(
      label: Text(label, style: TextStyle(color: isEnabled ? Colors.white : Colors.white54, fontSize: 12)),
      selected: isEnabled,
      selectedColor: Colors.blue.withValues(alpha: 0.4),
      backgroundColor: Colors.white.withValues(alpha: 0.08),
      checkmarkColor: Colors.white,
      onSelected: (selected) {
        final updated = List<String>.from(enabledSources);
        if (selected) {
          updated.add(source);
        } else {
          if (updated.length > 1) updated.remove(source);
        }
        _applySetting(
          _nav.copyWith(enabledPositionSources: updated),
          'מקורות מיקום',
          'positionSources',
        );
      },
    );
  }

  // ── Group 4: תקשורת ───────────────────────────────────────────────────────

  Widget _buildCommunicationGroup() {
    return _settingsGroup(
      title: 'תקשורת',
      icon: Icons.headset_mic_outlined,
      children: [
        _toggleTile(
          label: 'ווקי טוקי',
          value: _nav.communicationSettings.walkieTalkieEnabled,
          onChanged: (v) => _applySetting(
            _nav.copyWith(communicationSettings: _nav.communicationSettings.copyWith(walkieTalkieEnabled: v)),
            'ווקי טוקי',
            'walkieTalkie',
          ),
        ),
      ],
    );
  }

  // ── Group 4.5: חשיפת אשכולות ─────────────────────────────────────────────

  Widget _buildClusterRevealGroup() {
    final cs = _nav.clusterSettings;
    return _settingsGroup(
      title: 'חשיפת אשכולות',
      icon: Icons.visibility_outlined,
      children: [
        _toggleTile(
          label: 'פתח חשיפת נקודות אמיתיות',
          value: cs.revealOpenManually,
          onChanged: (v) => _applySetting(
            _nav.copyWith(clusterSettings: cs.copyWith(revealOpenManually: v)),
            'חשיפת נקודות אמיתיות',
            'clusterReveal',
          ),
        ),
        if (cs.isRevealCurrentlyOpen && !cs.revealOpenManually)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text('חשיפה פעילה (תזמון אוטומטי)',
                style: TextStyle(color: Colors.green[600], fontSize: 12)),
          ),
      ],
    );
  }

  // ── Group 5: הגדרות כוכב ──────────────────────────────────────────────────

  Widget _buildStarSettingsGroup() {
    return _settingsGroup(
      title: 'הגדרות כוכב',
      icon: Icons.star_outline,
      children: [
        _sliderRow(
          label: 'זמן למידה לנקודה',
          suffix: ' דק\'',
          value: (_nav.starLearningMinutes ?? 5).toDouble(),
          min: 1,
          max: 30,
          divisions: 29,
          onChanged: (v) => _applySetting(
            _nav.copyWith(starLearningMinutes: v.round()),
            'זמן למידה לנקודה',
            null,
          ),
        ),
        _sliderRow(
          label: 'זמן ניווט לנקודה',
          suffix: ' דק\'',
          value: (_nav.starNavigatingMinutes ?? 15).toDouble(),
          min: 1,
          max: 120,
          divisions: 119,
          onChanged: (v) => _applySetting(
            _nav.copyWith(starNavigatingMinutes: v.round()),
            'זמן ניווט לנקודה',
            null,
          ),
        ),
        _toggleTile(
          label: 'מצב אוטומטי',
          value: _nav.starAutoMode,
          onChanged: (v) => _applySetting(
            _nav.copyWith(starAutoMode: v),
            'מצב אוטומטי',
            null,
          ),
        ),
        if (_nav.starAutoMode)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'הנקודה הבאה נפתחת אוטומטית כשהמנווט חוזר למרכז',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
            ),
          ),
      ],
    );
  }

  // ── Group 5: זמנים והארכות ─────────────────────────────────────────────────

  Widget _buildTimeExtensionsGroup() {
    final ts = _nav.timeCalculationSettings;
    return _settingsGroup(
      title: 'זמנים והארכות',
      icon: Icons.timer_outlined,
      children: [
        _toggleTile(
          label: 'אפשר בקשות הארכה',
          value: ts.allowExtensionRequests,
          onChanged: (v) => _applySetting(
            _nav.copyWith(timeCalculationSettings: ts.copyWith(allowExtensionRequests: v)),
            'אפשר בקשות הארכה',
            null,
          ),
        ),
        if (ts.allowExtensionRequests) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('חלון בקשות', style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _windowTypeChip('כל הניווט', 'all', ts.extensionWindowType),
                    const SizedBox(width: 8),
                    _windowTypeChip('זמן מוגדר', 'timed', ts.extensionWindowType),
                  ],
                ),
              ],
            ),
          ),
          if (ts.extensionWindowType == 'timed')
            _sliderRow(
              label: 'דקות לפני סיום',
              suffix: ' דק\'',
              value: (ts.extensionWindowMinutes ?? 30).toDouble(),
              min: 5,
              max: 120,
              divisions: 23,
              onChanged: (v) => _applySetting(
                _nav.copyWith(timeCalculationSettings: ts.copyWith(extensionWindowMinutes: v.round())),
                'דקות לפני סיום',
                null,
              ),
            ),
        ],
      ],
    );
  }

  Widget _windowTypeChip(String label, String type, String currentType) {
    final isSelected = currentType == type;
    return ChoiceChip(
      label: Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.white54, fontSize: 12)),
      selected: isSelected,
      selectedColor: Colors.blue.withValues(alpha: 0.4),
      backgroundColor: Colors.white.withValues(alpha: 0.08),
      onSelected: (selected) {
        if (!selected) return;
        _applySetting(
          _nav.copyWith(timeCalculationSettings: _nav.timeCalculationSettings.copyWith(extensionWindowType: type)),
          'חלון בקשות הארכה',
          null,
        );
      },
    );
  }

  // ── Group 6: אישור נקודות ──────────────────────────────────────────────────

  Widget _buildVerificationGroup() {
    final vs = _nav.verificationSettings;
    return _settingsGroup(
      title: 'אישור נקודות',
      icon: Icons.check_circle_outline,
      children: [
        _toggleTile(
          label: 'אישור אוטומטי',
          value: vs.autoVerification,
          onChanged: (v) => _applySetting(
            _nav.copyWith(verificationSettings: vs.copyWith(autoVerification: v)),
            'אישור אוטומטי',
            null,
          ),
        ),
        if (vs.autoVerification)
          _sliderRow(
            label: 'מרחק אישור',
            suffix: ' מ\'',
            value: (vs.approvalDistance ?? 50).toDouble(),
            min: 5,
            max: 500,
            divisions: 99,
            onChanged: (v) => _applySetting(
              _nav.copyWith(verificationSettings: vs.copyWith(approvalDistance: v.round())),
              'מרחק אישור',
              null,
            ),
          ),
      ],
    );
  }

  // ── Shared Building Blocks ─────────────────────────────────────────────────

  Widget _settingsGroup({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Card(
      color: Colors.white.withValues(alpha: 0.06),
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: Icon(icon, color: Colors.white70, size: 22),
        title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        iconColor: Colors.white54,
        collapsedIconColor: Colors.white38,
        childrenPadding: const EdgeInsets.only(left: 12, right: 12, bottom: 12),
        children: children,
      ),
    );
  }

  Widget _toggleTile({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      title: Text(label, style: const TextStyle(color: Colors.white, fontSize: 14)),
      value: value,
      onChanged: onChanged,
      dense: true,
      activeColor: Colors.blue,
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _sliderRow({
    required String label,
    required String suffix,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
              Text('${value.round()}$suffix', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: Colors.blue,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.15),
              thumbColor: Colors.blue,
              overlayColor: Colors.blue.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChangeEnd: onChanged,
              onChanged: (_) {},
            ),
          ),
        ],
      ),
    );
  }

  Widget _alertToggleWithSlider({
    required String label,
    required bool enabled,
    required ValueChanged<bool> onToggle,
    required String sliderLabel,
    required String sliderSuffix,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onSliderChanged,
    required bool showSlider,
    Widget? extraSlider,
    Widget? volumeControl,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (volumeControl != null) volumeControl,
            Expanded(child: _toggleTile(label: label, value: enabled, onChanged: onToggle)),
          ],
        ),
        if (showSlider)
          _sliderRow(
            label: sliderLabel,
            suffix: sliderSuffix,
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onSliderChanged,
          ),
        if (extraSlider != null) extraSlider,
      ],
    );
  }

  Widget _buildAlertVolumeControl(String alertCode) {
    final volumes = _nav.alerts.alertSoundVolumes ?? {};
    return AlertVolumeControl(
      volume: volumes[alertCode] ?? 1.0,
      onVolumeChanged: (v) {
        final updated = Map<String, double>.from(volumes);
        if (v == 1.0) {
          updated.remove(alertCode);
        } else {
          updated[alertCode] = v;
        }
        _applySetting(
          _nav.copyWith(alerts: _nav.alerts.copyWith(
            alertSoundVolumes: updated.isEmpty ? null : updated,
          )),
          'עוצמת צליל',
          'alertSoundVolumes',
        );
      },
    );
  }

  Widget _buildCategorySoundRow({required String label, required String alertCode}) {
    final volumes = _nav.alerts.alertSoundVolumes ?? {};
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        children: [
          AlertVolumeControl(
            volume: volumes[alertCode] ?? 1.0,
            onVolumeChanged: (v) {
              final updated = Map<String, double>.from(volumes);
              if (v == 1.0) {
                updated.remove(alertCode);
              } else {
                updated[alertCode] = v;
              }
              _applySetting(
                _nav.copyWith(alerts: _nav.alerts.copyWith(
                  alertSoundVolumes: updated.isEmpty ? null : updated,
                )),
                'עוצמת צליל',
                'alertSoundVolumes',
              );
            },
          ),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 13, color: Colors.white)),
        ],
      ),
    );
  }
}
