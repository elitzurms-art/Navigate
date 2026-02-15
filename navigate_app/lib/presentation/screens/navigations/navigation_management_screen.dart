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
import '../../../services/gps_tracking_service.dart';
import '../../widgets/map_with_selector.dart';
import '../../widgets/map_controls.dart';

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
    _tabController.dispose();
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
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _initializeNavigators() async {
    // אתחול ראשוני
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
    }

    // טעינת סטטוסים מה-DB
    await _refreshNavigatorStatuses();
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
              // עדכון דקירות בלבד
              final localPunches = punchMap[navigatorId] ?? [];
              if (localPunches.isNotEmpty) {
                data.punches = localPunches;
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

        final latitude = (data['latitude'] as num?)?.toDouble();
        final longitude = (data['longitude'] as num?)?.toDouble();

        // רק אם יש מיקום תקין
        if (latitude == null || longitude == null) continue;
        if (latitude == 0.0 && longitude == 0.0) continue;

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
        final hadAlerts = _activeAlerts.length;
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
        if (alerts.length > hadAlerts) {
          HapticFeedback.heavyImpact();
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

      // עדכון סטטוס ניווט
      final updatedNavigation = widget.navigation.copyWith(
        status: 'approval',
        activeStartTime: null,
        updatedAt: now,
      );
      await _navRepo.update(updatedNavigation);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('הניווט הסתיים - מעבר למצב אישור'),
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

  void _measureDistance() {
    // מעבר לטאב סטטוס שמציג מרחקים בין מנווטים
    _tabController.animateTo(1);
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

      return _CheckpointArrival(checkpoint: checkpoint, punch: punch);
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
            icon: const Icon(Icons.straighten),
            tooltip: 'מדידת מרחק',
            onPressed: _measureDistance,
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
          : TabBarView(
              controller: _tabController,
              children: [
                _buildMapView(),
                _buildStatusView(),
                _buildAlertsView(),
                _buildDashboardView(),
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
                      color: Colors.blue.withOpacity(0.2 * _ggOpacity),
                      borderColor: Colors.blue,
                      borderStrokeWidth: 2,
                    ),
                  ],
                ),

              // נקודות ציון
              if (_showNZ)
                MarkerLayer(
                  markers: _checkpoints.where((cp) => !cp.isPolygon && cp.coordinates != null).map((cp) {
                    return Marker(
                      point: LatLng(cp.coordinates!.lat, cp.coordinates!.lng),
                      width: 40,
                      height: 46,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.place,
                            color: Colors.blue.withOpacity(_nzOpacity),
                            size: 32,
                          ),
                          Text(
                            '${cp.sequenceNumber}',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),

              // מסלולים של מנווטים
              if (_showTracks) ..._buildNavigatorTracks(),

              // דקירות
              if (_showPunches) ..._buildPunchMarkers(),

              // מיקומים נוכחיים של מנווטים
              ..._buildNavigatorMarkers(),

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
                    color: Colors.blue,
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
                        if (data.hasActiveAlert)
                          const Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Icon(Icons.warning, color: Colors.red, size: 18),
                          ),
                        if (data.personalStatus == NavigatorPersonalStatus.active)
                          IconButton(
                            icon: const Icon(Icons.stop_circle, color: Colors.red, size: 22),
                            onPressed: () => _finishNavigatorNavigation(navigatorId),
                            tooltip: 'עצירה מרחוק',
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
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

  List<Widget> _buildPunchMarkers() {
    List<Widget> markers = [];

    for (final entry in _navigatorData.entries) {
      final navigatorId = entry.key;
      final data = entry.value;

      if (!(_selectedNavigators[navigatorId] ?? false)) continue;

      final punchMarkers = data.punches.where((p) => !p.isDeleted).map((punch) {
        Color color;
        if (punch.isApproved) {
          color = Colors.green;
        } else if (punch.isRejected) {
          color = Colors.red;
        } else {
          color = Colors.orange;
        }

        return Marker(
          point: LatLng(punch.punchLocation.lat, punch.punchLocation.lng),
          width: 30,
          height: 30,
          child: Opacity(
            opacity: _punchesOpacity,
            child: Icon(
              Icons.flag,
              color: color,
              size: 30,
            ),
          ),
        );
      }).toList();

      if (punchMarkers.isNotEmpty) {
        markers.add(MarkerLayer(markers: punchMarkers));
      }
    }

    return markers;
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

      final markerChild = Column(
        children: [
          Icon(
            Icons.person_pin_circle,
            color: markerColor,
            size: 40,
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: markerColor,
                width: 2,
              ),
            ),
            child: Text(
              navigatorId,
              style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      );

      markers.add(
        Marker(
          point: data.currentPosition!,
          width: 60,
          height: 60,
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
    final arrivals = _getCheckpointArrivals(data);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(_getStatusIcon(data), color: _getNavigatorStatusColor(data), size: 28),
            const SizedBox(width: 8),
            Text(navigatorId),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'סטטוס: ${data.personalStatus.displayName}',
                  style: const TextStyle(fontSize: 14),
                ),
                if (data.hasActiveAlert)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      'התראה פעילה!',
                      style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                    ),
                  ),
                const Divider(height: 20),
                // נתונים חיים
                const Text('נתונים חיים', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 6),
                _detailRow('מהירות נוכחית', '${data.currentSpeedKmh.toStringAsFixed(1)} קמ"ש'),
                _detailRow('מהירות ממוצעת', '${data.averageSpeedKmh.toStringAsFixed(1)} קמ"ש'),
                _detailRow('מרחק שנעבר', '${data.totalDistanceKm.toStringAsFixed(2)} ק"מ'),
                _detailRow('זמן ניווט', _formatDuration(data.elapsedTime)),
                _detailRow('נקודות GPS', '${data.trackPoints.length}'),
                if (data.lastUpdate != null)
                  _detailRow('עדכון אחרון', '${_formatTimeSince(data.timeSinceLastUpdate)} לפני'),
                if (route != null) ...[
                  const Divider(height: 16),
                  _detailRow('אורך ציר מתוכנן', '${route.routeLengthKm.toStringAsFixed(1)} ק"מ'),
                ],
                // נקודות ציון
                if (arrivals.isNotEmpty) ...[
                  const Divider(height: 20),
                  const Text('נקודות ציון', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 6),
                  ...arrivals.map(_buildCheckpointRow),
                ],
              ],
            ),
          ),
        ),
        actions: [
          // הצג על המפה
          if (data.currentPosition != null)
            TextButton.icon(
              icon: const Icon(Icons.map, size: 18),
              label: const Text('הצג על המפה'),
              onPressed: () {
                Navigator.pop(ctx);
                _tabController.animateTo(0);
                _mapController.move(data.currentPosition!, 16.0);
              },
            ),
          // עצירה מרחוק
          if (data.personalStatus == NavigatorPersonalStatus.active)
            TextButton.icon(
              icon: const Icon(Icons.stop_circle, size: 18, color: Colors.red),
              label: const Text('עצירה מרחוק', style: TextStyle(color: Colors.red)),
              onPressed: () {
                Navigator.pop(ctx);
                _finishNavigatorNavigation(navigatorId);
              },
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('סגור'),
          ),
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

  Widget _buildAlertsView() {
    if (_activeAlerts.isEmpty) {
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

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _activeAlerts.length,
      itemBuilder: (context, index) {
        final alert = _activeAlerts[index];
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
      },
    );
  }

  // ===========================================================================
  // Alert Map Markers
  // ===========================================================================

  List<Widget> _buildAlertMarkers() {
    if (_activeAlerts.isEmpty) return [];

    final markers = _activeAlerts
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
    }
  }
}

/// נתונים חיים של מנווט
class NavigatorLiveData {
  final String navigatorId;
  NavigatorPersonalStatus personalStatus;
  bool hasActiveAlert;
  bool isGpsPlusFix;
  LatLng? currentPosition;
  List<TrackPoint> trackPoints;
  List<CheckpointPunch> punches;
  DateTime? lastUpdate;

  NavigatorLiveData({
    required this.navigatorId,
    required this.personalStatus,
    this.hasActiveAlert = false,
    this.isGpsPlusFix = false,
    this.currentPosition,
    required this.trackPoints,
    required this.punches,
    this.lastUpdate,
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

  _CheckpointArrival({required this.checkpoint, this.punch});

  bool get reached => punch != null;
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
