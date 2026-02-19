import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import '../../../domain/entities/navigation.dart' as domain;
import '../../../domain/entities/checkpoint.dart';
import '../../../domain/entities/checkpoint_punch.dart';
import '../../../domain/entities/navigation_settings.dart';
import '../../../domain/entities/coordinate.dart';
import '../../../domain/entities/boundary.dart';
import '../../../domain/entities/navigator_personal_status.dart';
import '../../../data/repositories/checkpoint_repository.dart';
import '../../../data/repositories/checkpoint_punch_repository.dart';
import '../../../data/repositories/boundary_repository.dart';
import '../../../data/repositories/navigation_repository.dart';
import '../../../data/repositories/navigation_track_repository.dart';
import '../../../data/repositories/navigator_alert_repository.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/geometry_utils.dart';
import '../../../services/gps_service.dart';
import '../../../services/gps_tracking_service.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/repositories/navigation_tree_repository.dart';
import '../../../services/auth_service.dart';
import '../../../domain/entities/user.dart' as app_user;
import '../../../services/voice_service.dart';
import '../../widgets/voice_messages_panel.dart';
import '../../widgets/map_with_selector.dart';
import '../../../data/repositories/extension_request_repository.dart';
import '../../../domain/entities/extension_request.dart';
import '../../widgets/map_controls.dart';
import '../../widgets/fullscreen_map_screen.dart';

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
  final BoundaryRepository _boundaryRepo = BoundaryRepository();
  final NavigationRepository _navRepo = NavigationRepository();
  final NavigationTrackRepository _trackRepo = NavigationTrackRepository();
  final NavigatorAlertRepository _alertRepo = NavigatorAlertRepository();
  final CheckpointPunchRepository _punchRepo = CheckpointPunchRepository();
  final MapController _mapController = MapController();

  late TabController _tabController;
  Timer? _refreshTimer;
  Timer? _stalenessTimer;
  Timer? _tracksPollTimer;
  Timer? _punchesPollTimer;
  StreamSubscription<QuerySnapshot>? _tracksListener;
  StreamSubscription<QuerySnapshot>? _systemStatusListener;
  StreamSubscription<List<NavigatorAlert>>? _alertsListener;
  StreamSubscription<List<CheckpointPunch>>? _punchesListener;

  List<Checkpoint> _checkpoints = [];
  Boundary? _boundary;
  bool _isLoading = false;

  // התראות בזמן אמת
  List<NavigatorAlert> _activeAlerts = [];
  bool _showAlerts = true;

  // מנווטים נבחרים לתצוגה
  Map<String, bool> _selectedNavigators = {};

  // מיקומים בזמן אמת
  Map<String, NavigatorLiveData> _navigatorData = {};

  // שכבות
  bool _showNZ = true;
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
  final Map<String, int?> _navigatorGpsIntervalOverride = {};

  // Voice (PTT)
  VoiceService? _voiceService;

  // בקשות הארכה
  final ExtensionRequestRepository _extensionRepo = ExtensionRequestRepository();
  StreamSubscription<List<ExtensionRequest>>? _extensionListener;
  List<ExtensionRequest> _extensionRequests = [];
  final Set<String> _shownExtensionPopups = {}; // מניעת popup כפול
  Timer? _extensionSnoozeTimer;

  // כפיית מקור מיקום גלובלי
  String _globalForcePositionSource = 'auto';

  // מרכוז מפה
  CenteringMode _centeringMode = CenteringMode.off;
  String? _centeredNavigatorId; // null = מרכוז עצמי
  Timer? _centeringTimer;
  StreamSubscription? _mapGestureSubscription;

  // הדגשה חד-פעמית (מרכז פעם אחת)
  String? _oneTimeCenteredNavigatorId;
  StreamSubscription? _oneTimeGestureSubscription;

  // שמות משתמשים (מנווטים + מפקדים)
  Map<String, String> _userNames = {};
  app_user.User? _currentUser;

  // מיקום עצמי של המפקד
  LatLng? _selfPosition;
  Timer? _selfGpsTimer;

  // מפקדים אחרים
  Map<String, _CommanderLocation> _otherCommanders = {};
  Timer? _commanderPublishTimer;
  StreamSubscription? _commanderStatusListener;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadData();
    _initializeNavigators();
    _startTrackListener();
    _startSystemStatusListener();
    _startAlertsListener();
    _startPunchesListener();
    _startTracksPolling();
    _startPunchesPolling();
    _startExtensionRequestListener();
    // רענון תקופתי כל 15 שניות
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _refreshNavigatorStatuses();
    });
    // רענון מראה סמנים כל 30 שניות — מעבר ירוק→אפור→נעלם
    _stalenessTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _stalenessTimer?.cancel();
    _tracksPollTimer?.cancel();
    _punchesPollTimer?.cancel();
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
    _tabController.dispose();
    _voiceService?.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final checkpoints = await _checkpointRepo.getByArea(widget.navigation.areaId);

      Boundary? boundary;
      if (widget.navigation.boundaryLayerId != null) {
        boundary = await _boundaryRepo.getById(widget.navigation.boundaryLayerId!);
      }

      setState(() {
        _checkpoints = checkpoints;
        _boundary = boundary;
        _isLoading = false;
      });

      if (boundary != null && boundary.coordinates.isNotEmpty) {
        final center = GeometryUtils.getPolygonCenter(boundary.coordinates);
        _mapController.move(LatLng(center.lat, center.lng), 13.0);
      }

      // קריאת forcePositionSource גלובלי מ-Firestore
      try {
        final navDoc = await FirebaseFirestore.instance
            .collection(AppConstants.navigationsCollection)
            .doc(widget.navigation.id)
            .get();
        final navData = navDoc.data();
        if (navData != null && navData['forcePositionSource'] is String) {
          setState(() {
            _globalForcePositionSource = navData['forcePositionSource'] as String;
          });
        }
      } catch (_) {}
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
    _commanderStatusListener = FirebaseFirestore.instance
        .collection(AppConstants.navigationsCollection)
        .doc(widget.navigation.id)
        .collection('commander_status')
        .snapshots()
        .listen((snapshot) => _updateCommanderLocations(snapshot));

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
    try {
      await FirebaseFirestore.instance
          .collection(AppConstants.navigationsCollection)
          .doc(widget.navigation.id)
          .collection('commander_status')
          .doc(_currentUser!.uid)
          .set({
        'userId': _currentUser!.uid,
        'name': _currentUser!.fullName,
        'latitude': _selfPosition!.latitude,
        'longitude': _selfPosition!.longitude,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  void _updateCommanderLocations(QuerySnapshot snapshot) {
    if (!mounted) return;
    final updated = <String, _CommanderLocation>{};
    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) continue;
      final uid = data['userId'] as String? ?? doc.id;
      if (uid == _currentUser?.uid) continue;
      final lat = (data['latitude'] as num?)?.toDouble();
      final lng = (data['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      DateTime? lastUpdate;
      final ts = data['updatedAt'];
      if (ts is Timestamp) lastUpdate = ts.toDate();
      updated[uid] = _CommanderLocation(
        userId: uid,
        name: data['name'] as String? ?? _userNames[uid] ?? uid,
        position: LatLng(lat, lng),
        lastUpdate: lastUpdate ?? DateTime.now(),
      );
    }
    setState(() => _otherCommanders = updated);
  }

  // ===========================================================================
  // Firestore Listener — נתונים בזמן אמת ממכשירי מנווטים
  // ===========================================================================

  void _startTrackListener() {
    _tracksListener = FirebaseFirestore.instance
        .collection(AppConstants.navigationTracksCollection)
        .where('navigationId', isEqualTo: widget.navigation.id)
        .snapshots()
        .listen(
      (snapshot) {
        _updateNavigatorDataFromFirestore(snapshot);
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
    _systemStatusListener = FirebaseFirestore.instance
        .collection(AppConstants.navigationsCollection)
        .doc(widget.navigation.id)
        .collection('system_status')
        .snapshots()
        .listen(
      (snapshot) {
        _updateNavigatorDataFromSystemStatus(snapshot);
      },
      onError: (e) {
        print('DEBUG NavigationManagement: system_status listener error: $e');
      },
    );
  }

  void _updateNavigatorDataFromSystemStatus(QuerySnapshot snapshot) {
    if (!mounted) return;

    setState(() {
      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final navigatorId = data['navigatorId'] as String? ?? doc.id;

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
        final batteryRaw = data['batteryLevel'];
        if (batteryRaw is int) {
          liveData.batteryLevel = batteryRaw;
        } else if (batteryRaw is num) {
          liveData.batteryLevel = batteryRaw.toInt();
        }

        // עדכון הרשאות מיקרופון וטלפון
        liveData.hasMicrophonePermission = data['hasMicrophonePermission'] as bool? ?? false;
        liveData.hasPhonePermission = data['hasPhonePermission'] as bool? ?? false;

        final latitude = (data['latitude'] as num?)?.toDouble();
        final longitude = (data['longitude'] as num?)?.toDouble();

        // עדכון מיקום — רק אם יש מיקום תקין
        if (latitude == null || longitude == null) continue;
        if (latitude == 0.0 && longitude == 0.0) continue;

        // עדכון מיקום מ-system_status — רק אם אין נתונים או ה-timestamp חדש יותר
        DateTime? statusTime;
        final updatedAtRaw = data['updatedAt'];
        if (updatedAtRaw is Timestamp) {
          statusTime = updatedAtRaw.toDate();
        } else if (updatedAtRaw is String) {
          statusTime = DateTime.tryParse(updatedAtRaw);
        }

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
        // ויברציה כשמגיעה התראה חדשה
        if (newAlerts.isNotEmpty) {
          HapticFeedback.heavyImpact();
        }
        // חלון קופץ להתראות חירום ותקינות חדשות
        for (final alert in newAlerts) {
          if (alert.type == AlertType.emergency ||
              alert.type == AlertType.healthCheckExpired) {
            _showAlertDialog(alert);
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

  // ===========================================================================
  // Polling Fallback — שאילתת Firestore ישירה כל 10 שניות
  // (עוקף את בעיית ה-threading של snapshots ב-Windows)
  // ===========================================================================

  void _startTracksPolling() {
    _pollTracks();
    _tracksPollTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _pollTracks(),
    );
  }

  Future<void> _pollTracks() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection(AppConstants.navigationTracksCollection)
          .where('navigationId', isEqualTo: widget.navigation.id)
          .get();

      if (!mounted) return;
      _updateNavigatorDataFromFirestore(snapshot);
    } catch (e) {
      print('DEBUG NavigationManagement: tracks poll error: $e');
    }
  }

  void _startPunchesPolling() {
    _pollPunches();
    _punchesPollTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _pollPunches(),
    );
  }

  Future<void> _pollPunches() async {
    try {
      final punches = await _punchRepo.getByNavigationFromFirestore(
        widget.navigation.id,
      );

      if (!mounted) return;
      setState(() {
        final punchMap = <String, List<CheckpointPunch>>{};
        for (final punch in punches) {
          punchMap.putIfAbsent(punch.navigatorId, () => []).add(punch);
        }
        for (final entry in _navigatorData.entries) {
          final navPunches = punchMap[entry.key] ?? [];
          // עדכון רק אם יש נתונים חדשים (לא לדרוס ברשימה ריקה)
          if (navPunches.isNotEmpty || entry.value.punches.isEmpty) {
            entry.value.punches = navPunches;
          }
        }
      });
    } catch (e) {
      print('DEBUG NavigationManagement: punches poll error: $e');
    }
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

  void _updateNavigatorDataFromFirestore(QuerySnapshot snapshot) {
    if (!mounted) return;

    setState(() {
      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final navigatorId = data['navigatorUserId'] as String?;
        if (navigatorId == null) continue;

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

        // קריאת isDisqualified מה-track doc
        liveData.isDisqualified = data['isDisqualified'] as bool? ?? false;

        // cache trackId + קריאת דריסות מפה (רק אם הוגדר ב-Firestore — אחרת נשאר default מהגדרות הניווט)
        _navigatorTrackIds[navigatorId] = doc.id;
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
        if (data.containsKey('overrideGpsIntervalSeconds')) {
          _navigatorGpsIntervalOverride[navigatorId] = data['overrideGpsIntervalSeconds'] as int?;
        }

        // קריאת forcePositionSource מה-track doc
        final trackForceSource = data['forcePositionSource'] as String?;
        liveData.isForceCell = (trackForceSource == 'cellTower') ||
            (trackForceSource == null && _globalForcePositionSource == 'cellTower');
      }
    });
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
      // שאילתת Firestore — מציאת ה-track הפעיל
      final snapshot = await FirebaseFirestore.instance
          .collection(AppConstants.navigationTracksCollection)
          .where('navigationId', isEqualTo: widget.navigation.id)
          .where('navigatorUserId', isEqualTo: navigatorId)
          .where('isActive', isEqualTo: true)
          .get();

      final now = DateTime.now();

      if (snapshot.docs.isEmpty) {
        // אין track פעיל — מנסה לחפש בלי isActive filter (אולי השדה חסר)
        final allTracks = await FirebaseFirestore.instance
            .collection(AppConstants.navigationTracksCollection)
            .where('navigationId', isEqualTo: widget.navigation.id)
            .where('navigatorUserId', isEqualTo: navigatorId)
            .get();

        for (final doc in allTracks.docs) {
          final trackData = doc.data();
          if (trackData['endedAt'] == null) {
            // track ללא endedAt — מסמן כמסיים
            await doc.reference.update({
              'isActive': false,
              'endedAt': now.toIso8601String(),
            });
            try { await _trackRepo.endNavigation(doc.id); } catch (_) {}
          }
        }
      } else {
        for (final doc in snapshot.docs) {
          // עדכון Firestore: isActive=false + endedAt
          await doc.reference.update({
            'isActive': false,
            'endedAt': now.toIso8601String(),
          });

          // עדכון מקומי ב-Drift
          try {
            await _trackRepo.endNavigation(doc.id);
          } catch (_) {
            // ייתכן שה-track לא קיים מקומית אצל המפקד
          }
        }
      }

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
        content: Text('להחזיר את $navigatorId למסך התחלת ניווט?\n\nהמסלול הקודם יישמר במערכת.'),
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
      // מחיקת track מ-Drift + Firestore
      await _trackRepo.deleteByNavigator(widget.navigation.id, navigatorId);

      // עדכון updatedAt בניווט (trigger ל-rebuild במנווט)
      try {
        await FirebaseFirestore.instance
            .collection('navigations')
            .doc(widget.navigation.id)
            .update({'updatedAt': FieldValue.serverTimestamp()});
      } catch (_) {}

      // עדכון UI מקומי
      if (mounted) {
        setState(() {
          final data = _navigatorData[navigatorId];
          if (data != null) {
            data.personalStatus = NavigatorPersonalStatus.waiting;
            data.trackPoints = [];
            data.currentPosition = null;
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
      // מחיקת track מ-Drift + Firestore
      await _trackRepo.deleteByNavigator(widget.navigation.id, navigatorId);

      // מחיקת דקירות מ-SharedPreferences + Firestore
      await _punchRepo.deleteByNavigator(widget.navigation.id, navigatorId);

      // עדכון updatedAt בניווט (trigger ל-rebuild במנווט)
      try {
        await FirebaseFirestore.instance
            .collection('navigations')
            .doc(widget.navigation.id)
            .update({'updatedAt': FieldValue.serverTimestamp()});
      } catch (_) {}

      // עדכון UI מקומי
      if (mounted) {
        setState(() {
          final data = _navigatorData[navigatorId];
          if (data != null) {
            data.personalStatus = NavigatorPersonalStatus.waiting;
            data.trackPoints = [];
            data.punches = [];
            data.currentPosition = null;
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
      // מציאת track ID מ-Firestore
      final snapshot = await FirebaseFirestore.instance
          .collection(AppConstants.navigationTracksCollection)
          .where('navigationId', isEqualTo: widget.navigation.id)
          .where('navigatorUserId', isEqualTo: navigatorId)
          .get();

      if (snapshot.docs.isEmpty) {
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

      final trackId = snapshot.docs.first.id;
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
          case 'reset':
            _resetNavigatorNavigation(navigatorId);
            break;
          case 'force_cell':
            _toggleNavigatorForceCell(navigatorId);
            break;
          case 'undo_disqualify':
            _undoDisqualification(navigatorId);
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
        // התחלת ניווט — waiting או finished
        if (status == NavigatorPersonalStatus.waiting ||
            status == NavigatorPersonalStatus.finished)
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
        // כפיית אנטנות — active/noReception
        if (status == NavigatorPersonalStatus.active ||
            status == NavigatorPersonalStatus.noReception)
          PopupMenuItem(
            value: 'force_cell',
            child: Row(
              children: [
                Icon(
                  data.isForceCell ? Icons.gps_fixed : Icons.cell_tower,
                  color: data.isForceCell ? Colors.green : Colors.orange,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  data.isForceCell ? 'ביטול כפיית אנטנות' : 'כפה אנטנות',
                  style: TextStyle(
                    color: data.isForceCell ? Colors.green : Colors.orange,
                  ),
                ),
              ],
            ),
          ),
        // אפס ניווט — active/finished/noReception
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
      ],
    );
  }

  // ===========================================================================
  // Force Position Source — כפיית מקור מיקום
  // ===========================================================================

  Future<void> _toggleGlobalForcePositionSource() async {
    final newSource = _globalForcePositionSource == 'cellTower' ? 'auto' : 'cellTower';

    try {
      await FirebaseFirestore.instance
          .collection(AppConstants.navigationsCollection)
          .doc(widget.navigation.id)
          .update({'forcePositionSource': newSource});

      setState(() => _globalForcePositionSource = newSource);

      // עדכון כל המנווטים הפעילים
      if (newSource == 'cellTower') {
        for (final entry in _navigatorData.entries) {
          if (entry.value.personalStatus == NavigatorPersonalStatus.active ||
              entry.value.personalStatus == NavigatorPersonalStatus.noReception) {
            entry.value.isForceCell = true;
          }
        }
      } else {
        // חזרה ל-auto — רק מי שאין לו override אישי
        for (final entry in _navigatorData.entries) {
          entry.value.isForceCell = false;
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(newSource == 'cellTower'
                ? 'כפיית מיקום אנטנות הופעלה לכל המנווטים'
                : 'מיקום אנטנות כפוי בוטל — חזרה לאוטומטי'),
            backgroundColor: newSource == 'cellTower' ? Colors.orange : Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בעדכון מצב מיקום: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _toggleNavigatorForceCell(String navigatorId) async {
    final data = _navigatorData[navigatorId];
    if (data == null) return;

    final newSource = data.isForceCell ? 'auto' : 'cellTower';

    try {
      // מציאת track פעיל של המנווט
      final snapshot = await FirebaseFirestore.instance
          .collection(AppConstants.navigationTracksCollection)
          .where('navigationId', isEqualTo: widget.navigation.id)
          .where('navigatorUserId', isEqualTo: navigatorId)
          .where('isActive', isEqualTo: true)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('לא נמצא track פעיל למנווט'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      await snapshot.docs.first.reference.update({
        'forcePositionSource': newSource,
      });

      setState(() {
        data.isForceCell = newSource == 'cellTower';
      });

      if (mounted) {
        final name = _userNames[navigatorId] ?? navigatorId;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(newSource == 'cellTower'
                ? 'כפיית אנטנות הופעלה ל-$name'
                : 'כפיית אנטנות בוטלה ל-$name'),
            backgroundColor: newSource == 'cellTower' ? Colors.orange : Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בעדכון מצב מיקום: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _finishAllNavigation() async {
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

    try {
      // הצגת loading
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('עוצר את כל המנווטים...'),
            duration: Duration(seconds: 2),
          ),
        );
      }

      // שאילתת Firestore — כל ה-tracks הפעילים של הניווט הזה
      final snapshot = await FirebaseFirestore.instance
          .collection(AppConstants.navigationTracksCollection)
          .where('navigationId', isEqualTo: widget.navigation.id)
          .where('isActive', isEqualTo: true)
          .get();

      final now = DateTime.now();

      // עצירת כל track פעיל
      for (final doc in snapshot.docs) {
        await doc.reference.update({
          'isActive': false,
          'endedAt': now.toIso8601String(),
        });

        // עדכון מקומי ב-Drift
        try {
          await _trackRepo.endNavigation(doc.id);
        } catch (_) {
          // ייתכן שה-track לא קיים מקומית אצל המפקד
        }
      }

      // עדכון UI — כל המנווטים לסטטוס "הסתיים"
      if (mounted) {
        setState(() {
          for (final entry in _navigatorData.entries) {
            entry.value.personalStatus = NavigatorPersonalStatus.finished;
          }
        });
      }

      // עדכון סטטוס ניווט — ישירות לתחקור (ללא שלב אישור נפרד)
      final updatedNavigation = widget.navigation.copyWith(
        status: 'review',
        activeStartTime: null,
        updatedAt: now,
      );
      await _navRepo.update(updatedNavigation);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('הניווט הסתיים - מעבר לתחקור'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
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

  List<_CheckpointArrival> _getCheckpointArrivals(NavigatorLiveData data) {
    final route = widget.navigation.routes[data.navigatorId];
    if (route == null) return [];

    return route.checkpointIds.map((cpId) {
      final checkpoint = _checkpoints.where((c) => c.id == cpId).firstOrNull;
      if (checkpoint == null) return null;

      final punch = data.punches
          .where((p) => p.checkpointId == cpId && !p.isDeleted)
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
          navigatorA: a.key,
          navigatorB: b.key,
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
                isLabelVisible: _activeAlerts.isNotEmpty,
                label: Text(
                  '${_activeAlerts.length}',
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
          IconButton(
            icon: Icon(
              _globalForcePositionSource == 'cellTower'
                  ? Icons.cell_tower
                  : Icons.gps_fixed,
              color: _globalForcePositionSource == 'cellTower'
                  ? Colors.orange
                  : Colors.white,
            ),
            tooltip: _globalForcePositionSource == 'cellTower'
                ? 'מצב אנטנות כפוי — לחץ לביטול'
                : 'כפה מיקום אנטנות לכל המנווטים',
            onPressed: _toggleGlobalForcePositionSource,
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
                    return VoiceMessagesPanel(
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
                    if (_globalForcePositionSource == 'cellTower')
                      _mapLegendItem('אנטנות כפוי', Colors.orange),
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
                            Text(data.navigatorId),
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
              if (_showGG && _boundary != null && _boundary!.coordinates.isNotEmpty)
                PolygonLayer(
                  polygons: [
                    Polygon(
                      points: _boundary!.coordinates
                          .map((coord) => LatLng(coord.lat, coord.lng))
                          .toList(),
                      color: Colors.black.withOpacity(0.2 * _ggOpacity),
                      borderColor: Colors.black,
                      borderStrokeWidth: 2,
                    ),
                  ],
                ),

              // נקודות ציון — עם סימון התחלה/סיום/ביניים
              if (_showNZ)
                MarkerLayer(
                  markers: _checkpoints.where((cp) => !cp.isPolygon && cp.coordinates != null).map((cp) {
                    // זיהוי סוג נקודה: התחלה / סיום / ביניים
                    final startIds = <String>{};
                    final endIds = <String>{};
                    final waypointIds = <String>{};
                    for (final route in widget.navigation.routes.values) {
                      if (route.startPointId != null) startIds.add(route.startPointId!);
                      if (route.endPointId != null) endIds.add(route.endPointId!);
                      waypointIds.addAll(route.waypointIds);
                    }
                    for (final wp in widget.navigation.waypointSettings.waypoints) {
                      waypointIds.add(wp.checkpointId);
                    }

                    final isStart = startIds.contains(cp.id) || cp.isStart;
                    final isEnd = endIds.contains(cp.id) || cp.isEnd;
                    final isWaypoint = waypointIds.contains(cp.id);

                    Color cpColor;
                    String letter;
                    if (isStart) {
                      cpColor = const Color(0xFF4CAF50); // ירוק — התחלה
                      letter = 'H';
                    } else if (isEnd) {
                      cpColor = const Color(0xFFF44336); // אדום — סיום
                      letter = 'S';
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
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.place,
                            color: cpColor.withValues(alpha: _nzOpacity),
                            size: 32,
                          ),
                          Text(
                            '${cp.sequenceNumber}$letter',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: cpColor,
                            ),
                          ),
                        ],
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
                      layers: [
                        if (_showGG && _boundary != null && _boundary!.coordinates.isNotEmpty)
                          PolygonLayer(
                            polygons: [
                              Polygon(
                                points: _boundary!.coordinates.map((coord) => LatLng(coord.lat, coord.lng)).toList(),
                                color: Colors.black.withOpacity(0.2 * _ggOpacity),
                                borderColor: Colors.black,
                                borderStrokeWidth: 2,
                              ),
                            ],
                          ),
                        if (_showNZ)
                          MarkerLayer(
                            markers: _checkpoints.where((cp) => !cp.isPolygon && cp.coordinates != null).map((cp) {
                              // זיהוי סוג נקודה: התחלה / סיום / ביניים
                              final startIds = <String>{};
                              final endIds = <String>{};
                              final waypointIds = <String>{};
                              for (final route in widget.navigation.routes.values) {
                                if (route.startPointId != null) startIds.add(route.startPointId!);
                                if (route.endPointId != null) endIds.add(route.endPointId!);
                                waypointIds.addAll(route.waypointIds);
                              }
                              for (final wp in widget.navigation.waypointSettings.waypoints) {
                                waypointIds.add(wp.checkpointId);
                              }

                              final isStart = startIds.contains(cp.id) || cp.isStart;
                              final isEnd = endIds.contains(cp.id) || cp.isEnd;
                              final isWaypoint = waypointIds.contains(cp.id);

                              Color cpColor;
                              String letter;
                              if (isStart) {
                                cpColor = const Color(0xFF4CAF50); // ירוק — התחלה
                                letter = 'H';
                              } else if (isEnd) {
                                cpColor = const Color(0xFFF44336); // אדום — סיום
                                letter = 'S';
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
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.place,
                                      color: cpColor.withValues(alpha: _nzOpacity),
                                      size: 32,
                                    ),
                                    Text(
                                      '${cp.sequenceNumber}$letter',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: cpColor,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        if (_showTracks) ..._buildNavigatorTracks(),
                        if (_showPunches) ..._buildPunchMarkers(),
                        ..._buildNavigatorMarkers(),
                        ..._buildSelfMarker(),
                        ..._buildCommanderMarkers(),
                        if (_showAlerts) ..._buildAlertMarkers(),
                      ],
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

        // כרטיסי מנווטים
        ..._navigatorData.entries.map((entry) {
          final navigatorId = entry.key;
          final data = entry.value;
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
                          child: Text(
                            navigatorId,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                        ),
                        if (data.isDisqualified)
                          Container(
                            margin: const EdgeInsets.only(left: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('נפסל',
                                style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                        if (data.isForceCell)
                          const Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Icon(Icons.cell_tower, color: Colors.orange, size: 18),
                          ),
                        if (data.hasActiveAlert)
                          const Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Icon(Icons.warning, color: Colors.red, size: 18),
                          ),
                        _buildNavigatorActionsMenu(navigatorId, data),
                      ],
                    ),
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
                            _formatDuration(data.elapsedTime),
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
        }),
      ],
    );
  }

  List<Widget> _buildNavigatorTracks() {
    List<Widget> tracks = [];

    for (final entry in _navigatorData.entries) {
      final navigatorId = entry.key;
      final data = entry.value;

      if (!(_selectedNavigators[navigatorId] ?? false)) continue;
      if (data.trackPoints.isEmpty) continue;

      // מנווט מוצג אם _showTracks (גלובלי) או _showNavigatorTrack (פר-מנווט) דלוקים
      final showGlobal = _showTracks;
      final showPerNavigator = _showNavigatorTrack[navigatorId] ?? false;
      if (!showGlobal && !showPerNavigator) continue;

      final points = data.trackPoints
          .map((tp) => LatLng(tp.coordinate.lat, tp.coordinate.lng))
          .toList();

      tracks.add(
        PolylineLayer(
          polylines: [
            Polyline(
              points: points,
              strokeWidth: 3,
              color: _getTrackColor(data.personalStatus).withValues(alpha: _tracksOpacity),
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

  List<Widget> _buildPunchMarkers() {
    List<Widget> markers = [];

    for (final entry in _navigatorData.entries) {
      final navigatorId = entry.key;
      final data = entry.value;

      if (!(_selectedNavigators[navigatorId] ?? false)) continue;

      final activePunches = data.punches.where((p) => !p.isDeleted).toList();
      final navName = _userNames[navigatorId] ?? navigatorId;
      final punchMarkers = <Marker>[];
      for (int i = 0; i < activePunches.length; i++) {
        final punch = activePunches[i];
        Color color;
        if (punch.isApproved) {
          color = Colors.green;
        } else if (punch.isRejected) {
          color = Colors.red;
        } else {
          color = Colors.orange;
        }

        punchMarkers.add(Marker(
          point: LatLng(punch.punchLocation.lat, punch.punchLocation.lng),
          width: 90,
          height: 45,
          child: Opacity(
            opacity: _punchesOpacity,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.flag, color: color, size: 22),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    '${i + 1}-$navName',
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
          child: markerOpacity < 1.0
              ? Opacity(opacity: markerOpacity, child: markerChild)
              : markerChild,
        ),
      );
    }

    return markers.isNotEmpty ? [MarkerLayer(markers: markers)] : [];
  }

  Color _getNavigatorStatusColor(NavigatorLiveData data) {
    if (data.hasActiveAlert) return Colors.red;
    if (data.isForceCell) return Colors.orange;
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
                                Text(navigatorId, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
                        return SwitchListTile(
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

                      // 6.5 תדירות GPS
                      const Divider(height: 16),
                      const Text('תדירות GPS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 4),
                      () {
                        final defaultInterval = widget.navigation.gpsUpdateIntervalSeconds;
                        final currentValue = _navigatorGpsIntervalOverride[navigatorId] ?? defaultInterval;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('$currentValue שניות', style: const TextStyle(fontSize: 13)),
                            Text('ברירת מחדל: $defaultInterval שניות',
                                style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                            Slider(
                              value: currentValue.toDouble(),
                              min: 1,
                              max: 120,
                              divisions: 119,
                              label: '$currentValue',
                              onChanged: (v) {
                                setState(() {
                                  final intVal = v.round();
                                  _navigatorGpsIntervalOverride[navigatorId] =
                                      intVal == defaultInterval ? null : intVal;
                                });
                                setSheetState(() {});
                              },
                              onChangeEnd: (v) {
                                final intVal = v.round();
                                final override = intVal == defaultInterval ? null : intVal;
                                _navigatorGpsIntervalOverride[navigatorId] = override;
                                final trackId = _navigatorTrackIds[navigatorId];
                                if (trackId != null) {
                                  FirebaseFirestore.instance
                                      .collection(AppConstants.navigationTracksCollection)
                                      .doc(trackId)
                                      .update({'overrideGpsIntervalSeconds': override});
                                }
                              },
                            ),
                            if (_navigatorGpsIntervalOverride[navigatorId] != null)
                              Align(
                                alignment: AlignmentDirectional.centerEnd,
                                child: TextButton.icon(
                                  icon: const Icon(Icons.restart_alt, size: 16),
                                  label: const Text('חזרה לברירת מחדל', style: TextStyle(fontSize: 12)),
                                  onPressed: () {
                                    setState(() => _navigatorGpsIntervalOverride[navigatorId] = null);
                                    setSheetState(() {});
                                    final trackId = _navigatorTrackIds[navigatorId];
                                    if (trackId != null) {
                                      FirebaseFirestore.instance
                                          .collection(AppConstants.navigationTracksCollection)
                                          .doc(trackId)
                                          .update({'overrideGpsIntervalSeconds': null});
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
                      _detailRow('זמן ניווט', _formatDuration(liveData.elapsedTime)),
                      _detailRow('נקודות GPS', '${liveData.trackPoints.length}'),
                      if (liveData.lastUpdate != null)
                        _detailRow('עדכון אחרון', '${_formatTimeSince(liveData.timeSinceLastUpdate)} לפני'),
                      if (route != null)
                        _detailRow('אורך ציר מתוכנן', '${route.routeLengthKm.toStringAsFixed(1)} ק"מ'),

                      // זמני משימה
                      if (route != null && widget.navigation.timeCalculationSettings.enabled) ...[
                        () {
                          final totalMinutes = GeometryUtils.calculateNavigationTimeMinutes(
                            routeLengthKm: route.routeLengthKm,
                            settings: widget.navigation.timeCalculationSettings,
                          );
                          final activeStart = widget.navigation.activeStartTime;
                          if (totalMinutes > 0 && activeStart != null) {
                            final missionEnd = activeStart.add(Duration(minutes: totalMinutes));
                            final safetyEnd = missionEnd.add(const Duration(hours: 1));
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

    // fallback: חיפוש track ב-Firestore אם אין cache
    if (trackId == null) {
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection(AppConstants.navigationTracksCollection)
            .where('navigationId', isEqualTo: widget.navigation.id)
            .where('navigatorUserId', isEqualTo: navigatorId)
            .limit(1)
            .get();
        if (snapshot.docs.isNotEmpty) {
          trackId = snapshot.docs.first.id;
          _navigatorTrackIds[navigatorId] = trackId;
        }
      } catch (_) {}
    }

    if (trackId == null) return;

    await _trackRepo.updateMapOverrides(
      trackId,
      allowOpenMap: _navigatorOverrideAllowOpenMap[navigatorId] ?? false,
      showSelfLocation: _navigatorOverrideShowSelfLocation[navigatorId] ?? false,
      showRouteOnMap: _navigatorOverrideShowRouteOnMap[navigatorId] ?? false,
    );
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
    final extensionCount = _extensionRequests.where((r) => r.status == ExtensionRequestStatus.pending).length;

    return GestureDetector(
      onTap: () {
        // הצג את ההתראה הראשונה שלא טופלה
        final urgent = _activeAlerts.where(
          (a) => a.type == AlertType.emergency || a.type == AlertType.healthCheckExpired,
        ).toList();
        if (urgent.isNotEmpty) {
          _showAlertDialog(urgent.first);
        } else if (extensionCount > 0) {
          _tabController.animateTo(3); // טאב התראות
        }
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: emergencyCount > 0 ? Colors.red : (extensionCount > 0 ? Colors.purple : Colors.orange),
        child: Row(
          children: [
            Icon(
              emergencyCount > 0 ? Icons.emergency : (extensionCount > 0 ? Icons.timer : Icons.timer_off),
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                [
                  if (emergencyCount > 0) '$emergencyCount חירום',
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

    if (filteredAlerts.isEmpty && pendingExtensions.isEmpty) {
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
          if (filteredAlerts.isNotEmpty) const Divider(height: 24),
        ],
        // התראות רגילות
        ...filteredAlerts.map((alert) => _buildAlertCard(alert)),
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
    }
  }

  // ===========================================================================
  // Extension Requests — בקשות הארכה
  // ===========================================================================

  void _startExtensionRequestListener() {
    if (!widget.navigation.timeCalculationSettings.allowExtensionRequests) return;
    _extensionListener = _extensionRepo
        .watchByNavigation(widget.navigation.id)
        .listen((requests) {
      if (!mounted) return;
      setState(() => _extensionRequests = requests);
      // popup אוטומטי לבקשות חדשות
      for (final req in requests) {
        if (req.status == ExtensionRequestStatus.pending &&
            !_shownExtensionPopups.contains(req.id)) {
          _shownExtensionPopups.add(req.id);
          _showExtensionPopup(req);
        }
      }
    });
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
  bool isForceCell; // כפיית מקור מיקום אנטנות ע"י מפקד
  bool isDisqualified; // מנווט נפסל (פריצת אבטחה)
  LatLng? currentPosition;
  List<TrackPoint> trackPoints;
  List<CheckpointPunch> punches;
  DateTime? lastUpdate;
  int? batteryLevel; // 0-100%, null = לא ידוע
  bool hasMicrophonePermission;
  bool hasPhonePermission;

  NavigatorLiveData({
    required this.navigatorId,
    required this.personalStatus,
    this.hasActiveAlert = false,
    this.isGpsPlusFix = false,
    this.isForceCell = false,
    this.isDisqualified = false,
    this.currentPosition,
    required this.trackPoints,
    required this.punches,
    this.lastUpdate,
    this.batteryLevel,
    this.hasMicrophonePermission = false,
    this.hasPhonePermission = false,
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

/// מיקום מפקד אחר על המפה
class _CommanderLocation {
  final String userId;
  final String name;
  LatLng position;
  DateTime lastUpdate;

  _CommanderLocation({
    required this.userId,
    required this.name,
    required this.position,
    required this.lastUpdate,
  });
}
