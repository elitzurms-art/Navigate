import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../domain/entities/checkpoint_punch.dart';
import '../domain/entities/coordinate.dart';
import '../domain/entities/navigation_settings.dart';
import '../domain/entities/safety_point.dart';
import '../core/utils/geometry_utils.dart';
import '../core/constants/app_constants.dart';
import '../data/repositories/navigator_alert_repository.dart';
import '../data/repositories/boundary_repository.dart';
import '../data/repositories/safety_point_repository.dart';
import 'gps_tracking_service.dart';
import 'package:geolocator/geolocator.dart';

/// שירות מוניטור התראות אוטומטי — מאזין ל-GPS ויוצר התראות בזמן אמת
class AlertMonitoringService {
  final String navigationId;
  final String navigatorId;
  final String navigatorName;
  final NavigationAlerts alertsConfig;
  final GPSTrackingService gpsTracker;
  final NavigatorAlertRepository alertRepository;
  final String? areaId;
  final String? boundaryLayerId;
  final List<Coordinate> plannedPath;

  // Repositories for loading geo data
  final BoundaryRepository _boundaryRepo = BoundaryRepository();
  final SafetyPointRepository _safetyPointRepo = SafetyPointRepository();

  // Loaded geo data
  List<Coordinate>? _boundaryPolygon;
  List<SafetyPoint> _safetyPoints = [];

  // Cooldown tracking
  final Map<AlertType, DateTime> _lastAlertTime = {};

  // No-movement tracking
  DateTime _lastSignificantMovementTime = DateTime.now();
  Coordinate? _lastMovementCoordinate;
  Timer? _noMovementTimer;

  // Proximity tracking (קרבת מנווטים)
  Timer? _proximityPollTimer;
  final Map<String, _OtherNavigatorPosition> _otherPositions = {};

  // GPS stream subscription
  StreamSubscription<Position>? _positionSubscription;

  // Previous track point for speed fallback
  TrackPoint? _previousTrackPoint;

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  static const Map<AlertType, Duration> _defaultCooldowns = {
    AlertType.speed: Duration(minutes: 3),
    AlertType.noMovement: Duration(minutes: 10),
    AlertType.boundary: Duration(minutes: 5),
    AlertType.routeDeviation: Duration(minutes: 5),
    AlertType.safetyPoint: Duration(minutes: 5),
    AlertType.proximity: Duration(minutes: 5), // fallback, overridden by proximityMinTime
    AlertType.battery: Duration(minutes: 15),
  };

  /// סף דיוק GPS — מעל 50 מטר, מדלגים על בדיקות (מניעת false positives)
  static const double _accuracyThreshold = 50.0;

  /// מרחק מינימלי (מטרים) שנחשב "תנועה משמעותית"
  static const double _movementThreshold = 10.0;

  /// Callback — נקרא בכל פעם שנוצרת התראה חדשה (לתצוגה בצד המנווט)
  final void Function(NavigatorAlert alert)? onAlert;

  AlertMonitoringService({
    required this.navigationId,
    required this.navigatorId,
    required this.navigatorName,
    required this.alertsConfig,
    required this.gpsTracker,
    required this.alertRepository,
    this.areaId,
    this.boundaryLayerId,
    this.plannedPath = const [],
    this.onAlert,
  });

  /// התחלת מוניטור — טוען נתוני גאומטריה ומאזין ל-GPS
  Future<void> start() async {
    if (_isRunning) return;
    if (!alertsConfig.enabled) {
      print('DEBUG AlertMonitoring: alerts disabled, not starting');
      return;
    }

    _isRunning = true;
    _lastSignificantMovementTime = DateTime.now();

    // טעינת נתוני גאומטריה
    await _loadGeoData();

    // האזנה ל-GPS stream
    _positionSubscription = gpsTracker.positionStream.listen(_onNewPosition);

    // טיימר בדיקת חוסר תנועה — כל דקה
    if (alertsConfig.noMovementAlertEnabled && alertsConfig.noMovementMinutes != null) {
      _noMovementTimer = Timer.periodic(
        const Duration(minutes: 1),
        (_) => _checkNoMovement(),
      );
    }

    // הפעלת polling קרבת מנווטים
    if (alertsConfig.navigatorProximityAlertEnabled) {
      _startProximityPolling();
    }

    print('DEBUG AlertMonitoring: started for navigator $navigatorId');
  }

  /// עצירת מוניטור
  void stop() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _noMovementTimer?.cancel();
    _noMovementTimer = null;
    _proximityPollTimer?.cancel();
    _proximityPollTimer = null;
    _isRunning = false;
    print('DEBUG AlertMonitoring: stopped');
  }

  /// ניקוי משאבים
  void dispose() {
    stop();
    _boundaryPolygon = null;
    _safetyPoints = [];
    _otherPositions.clear();
    _lastAlertTime.clear();
  }

  // ===========================================================================
  // Data Loading
  // ===========================================================================

  Future<void> _loadGeoData() async {
    // טעינת גבול גזרה
    if (boundaryLayerId != null) {
      try {
        final boundary = await _boundaryRepo.getById(boundaryLayerId!);
        if (boundary != null) {
          _boundaryPolygon = boundary.coordinates;
          print('DEBUG AlertMonitoring: loaded boundary with ${_boundaryPolygon!.length} points');
        }
      } catch (e) {
        print('DEBUG AlertMonitoring: failed to load boundary: $e');
      }
    }

    // טעינת נתב"ים
    if (areaId != null) {
      try {
        _safetyPoints = await _safetyPointRepo.getByArea(areaId!);
        print('DEBUG AlertMonitoring: loaded ${_safetyPoints.length} safety points');
      } catch (e) {
        print('DEBUG AlertMonitoring: failed to load safety points: $e');
      }
    }
  }

  // ===========================================================================
  // GPS Position Handler
  // ===========================================================================

  void _onNewPosition(Position position) {
    // הגנת דיוק — GPS ירוד = מדלגים
    if (position.accuracy > _accuracyThreshold) {
      print('DEBUG AlertMonitoring: skipping checks, accuracy ${position.accuracy.toStringAsFixed(0)}m > threshold');
      return;
    }

    final trackPoint = TrackPoint(
      coordinate: Coordinate(
        lat: position.latitude,
        lng: position.longitude,
        utm: '',
      ),
      timestamp: DateTime.now(),
      accuracy: position.accuracy,
      speed: position.speed,
    );

    // הרצת בדיקות
    if (alertsConfig.speedAlertEnabled) {
      _checkSpeed(trackPoint);
    }
    if (alertsConfig.ggAlertEnabled) {
      _checkBoundary(trackPoint);
    }
    if (alertsConfig.routesAlertEnabled) {
      _checkRouteDeviation(trackPoint);
    }
    if (alertsConfig.nbAlertEnabled) {
      _checkSafetyPointProximity(trackPoint);
    }
    if (alertsConfig.navigatorProximityAlertEnabled) {
      _checkProximity(trackPoint);
    }

    // עדכון מעקב תנועה
    _updateMovementTracking(trackPoint);

    _previousTrackPoint = trackPoint;
  }

  // ===========================================================================
  // Check: Speed
  // ===========================================================================

  void _checkSpeed(TrackPoint point) {
    final maxSpeed = alertsConfig.maxSpeed;
    if (maxSpeed == null) return;

    double speedKmh = 0;

    // ניסיון ראשון: מהירות מה-GPS
    if (point.speed != null && point.speed! > 0) {
      speedKmh = point.speed! * 3.6; // m/s → km/h
    }
    // fallback: חישוב ממרחק/זמן
    else if (_previousTrackPoint != null) {
      final distance = GeometryUtils.distanceBetweenMeters(
        _previousTrackPoint!.coordinate,
        point.coordinate,
      );
      final timeDiff = point.timestamp.difference(_previousTrackPoint!.timestamp).inSeconds;
      if (timeDiff > 0) {
        speedKmh = (distance / timeDiff) * 3.6;
      }
    }

    if (speedKmh > maxSpeed) {
      print('DEBUG AlertMonitoring: speed alert! ${speedKmh.toStringAsFixed(1)} km/h > $maxSpeed km/h');
      _sendAlert(AlertType.speed, point.coordinate);
    }
  }

  // ===========================================================================
  // Check: Boundary (גבול גזרה)
  // ===========================================================================

  void _checkBoundary(TrackPoint point) {
    if (_boundaryPolygon == null || _boundaryPolygon!.length < 3) return;

    final isInside = GeometryUtils.isPointInPolygon(point.coordinate, _boundaryPolygon!);

    if (!isInside) {
      // מחוץ לגבול — התראה מיידית
      print('DEBUG AlertMonitoring: boundary alert! navigator outside boundary');
      _sendAlert(AlertType.boundary, point.coordinate);
      return;
    }

    // בתוך הגבול — בדיקת קרבה לשוליים
    final alertRange = alertsConfig.ggAlertRange;
    if (alertRange == null) return;

    // חישוב מרחק מינימלי מצלעות הפוליגון
    double minDistance = double.infinity;
    for (int i = 0; i < _boundaryPolygon!.length; i++) {
      final j = (i + 1) % _boundaryPolygon!.length;
      final dist = GeometryUtils.distanceFromPointToSegmentMeters(
        point.coordinate,
        _boundaryPolygon![i],
        _boundaryPolygon![j],
      );
      if (dist < minDistance) {
        minDistance = dist;
      }
    }

    if (minDistance <= alertRange) {
      print('DEBUG AlertMonitoring: boundary proximity alert! ${minDistance.toStringAsFixed(0)}m from edge (threshold: ${alertRange}m)');
      _sendAlert(AlertType.boundary, point.coordinate);
    }
  }

  // ===========================================================================
  // Check: Route Deviation (סטייה מציר)
  // ===========================================================================

  void _checkRouteDeviation(TrackPoint point) {
    if (plannedPath.length < 2) return;

    final alertRange = alertsConfig.routesAlertRange;
    if (alertRange == null) return;

    // חישוב מרחק מינימלי מכל segment בציר המתוכנן
    double minDistance = double.infinity;
    for (int i = 0; i < plannedPath.length - 1; i++) {
      final dist = GeometryUtils.distanceFromPointToSegmentMeters(
        point.coordinate,
        plannedPath[i],
        plannedPath[i + 1],
      );
      if (dist < minDistance) {
        minDistance = dist;
      }
    }

    if (minDistance > alertRange) {
      print('DEBUG AlertMonitoring: route deviation alert! ${minDistance.toStringAsFixed(0)}m from route (threshold: ${alertRange}m)');
      _sendAlert(AlertType.routeDeviation, point.coordinate);
    }
  }

  // ===========================================================================
  // Check: Safety Point Proximity (קרבת נת"ב)
  // ===========================================================================

  void _checkSafetyPointProximity(TrackPoint point) {
    if (_safetyPoints.isEmpty) return;

    final alertRange = alertsConfig.nbAlertRange;
    if (alertRange == null) return;

    for (final sp in _safetyPoints) {
      double distance;

      if (sp.type == 'polygon' && sp.polygonCoordinates != null && sp.polygonCoordinates!.length >= 3) {
        // פוליגון — בדיקה אם בפנים, או מרחק מינימלי מצלעות
        if (GeometryUtils.isPointInPolygon(point.coordinate, sp.polygonCoordinates!)) {
          print('DEBUG AlertMonitoring: safety point alert! inside polygon "${sp.name}"');
          _sendAlert(AlertType.safetyPoint, point.coordinate);
          return;
        }

        // מרחק מינימלי מצלעות הפוליגון
        distance = double.infinity;
        for (int i = 0; i < sp.polygonCoordinates!.length; i++) {
          final j = (i + 1) % sp.polygonCoordinates!.length;
          final dist = GeometryUtils.distanceFromPointToSegmentMeters(
            point.coordinate,
            sp.polygonCoordinates![i],
            sp.polygonCoordinates![j],
          );
          if (dist < distance) {
            distance = dist;
          }
        }
      } else if (sp.coordinates != null) {
        // נקודה בודדת
        distance = GeometryUtils.distanceBetweenMeters(
          point.coordinate,
          sp.coordinates!,
        );
      } else {
        continue;
      }

      if (distance <= alertRange) {
        print('DEBUG AlertMonitoring: safety point proximity alert! ${distance.toStringAsFixed(0)}m from "${sp.name}" (threshold: ${alertRange}m)');
        _sendAlert(AlertType.safetyPoint, point.coordinate);
        return; // התראה אחת מספיקה
      }
    }
  }

  // ===========================================================================
  // Check: No Movement (חוסר תנועה)
  // ===========================================================================

  void _updateMovementTracking(TrackPoint point) {
    if (_lastMovementCoordinate == null) {
      _lastMovementCoordinate = point.coordinate;
      _lastSignificantMovementTime = point.timestamp;
      return;
    }

    final distance = GeometryUtils.distanceBetweenMeters(
      _lastMovementCoordinate!,
      point.coordinate,
    );

    if (distance >= _movementThreshold) {
      _lastMovementCoordinate = point.coordinate;
      _lastSignificantMovementTime = point.timestamp;
    }
  }

  void _checkNoMovement() {
    if (!_isRunning) return;
    if (!alertsConfig.noMovementAlertEnabled) return;

    final noMovementMinutes = alertsConfig.noMovementMinutes;
    if (noMovementMinutes == null) return;

    final elapsed = DateTime.now().difference(_lastSignificantMovementTime);
    if (elapsed.inMinutes >= noMovementMinutes) {
      print('DEBUG AlertMonitoring: no movement alert! ${elapsed.inMinutes} minutes without significant movement');
      final coord = _lastMovementCoordinate ?? Coordinate(lat: 0, lng: 0, utm: '');
      _sendAlert(AlertType.noMovement, coord);
    }
  }

  // ===========================================================================
  // Check: Navigator Proximity (קרבת מנווטים)
  // ===========================================================================

  /// Polling מיקומי מנווטים אחרים מ-Firestore כל 10 שניות
  void _startProximityPolling() {
    // polling מיידי ראשון
    _pollOtherNavigators();
    _proximityPollTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _pollOtherNavigators(),
    );
    print('DEBUG AlertMonitoring: proximity polling started');
  }

  Future<void> _pollOtherNavigators() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection(AppConstants.navigationTracksCollection)
          .where('navigationId', isEqualTo: navigationId)
          .where('isActive', isEqualTo: true)
          .get();

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final uid = data['navigatorUserId'] as String?;
        if (uid == null || uid == navigatorId) continue; // דילוג על עצמי

        final trackPointsJson = data['trackPointsJson'] as String?;
        if (trackPointsJson == null || trackPointsJson.isEmpty) continue;

        try {
          final List<dynamic> points = jsonDecode(trackPointsJson);
          if (points.isEmpty) continue;

          // נקודה אחרונה = מיקום עדכני
          final lastPoint = points.last as Map<String, dynamic>;
          final lat = (lastPoint['lat'] as num?)?.toDouble();
          final lng = (lastPoint['lng'] as num?)?.toDouble();
          final timestampStr = lastPoint['timestamp'] as String?;

          if (lat == null || lng == null) continue;

          _otherPositions[uid] = _OtherNavigatorPosition(
            coordinate: Coordinate(lat: lat, lng: lng, utm: ''),
            timestamp: timestampStr != null
                ? DateTime.tryParse(timestampStr) ?? DateTime.now()
                : DateTime.now(),
          );
        } catch (_) {
          // JSON parse error — skip
        }
      }
    } catch (e) {
      print('DEBUG AlertMonitoring: proximity poll error: $e');
    }
  }

  /// בדיקת קרבה לכל מנווט אחר
  void _checkProximity(TrackPoint point) {
    final proximityDist = alertsConfig.proximityDistance;
    if (proximityDist == null || _otherPositions.isEmpty) return;

    final now = DateTime.now();
    const staleThreshold = Duration(minutes: 5);

    for (final entry in _otherPositions.entries) {
      final other = entry.value;

      // דילוג על מיקומים ישנים מדי (>5 דק')
      if (now.difference(other.timestamp) > staleThreshold) continue;

      final distance = GeometryUtils.distanceBetweenMeters(
        point.coordinate,
        other.coordinate,
      );

      if (distance < proximityDist) {
        print('DEBUG AlertMonitoring: proximity alert! ${distance.toStringAsFixed(0)}m from navigator ${entry.key} (threshold: ${proximityDist}m)');
        _sendAlert(AlertType.proximity, point.coordinate);
        return; // התראה אחת מספיקה
      }
    }
  }

  // ===========================================================================
  // Battery Check
  // ===========================================================================

  /// עדכון רמת סוללה מבחוץ (מ-ActiveView) + בדיקת סף
  void updateBatteryLevel(int level) {
    if (!_isRunning) return;
    if (!alertsConfig.batteryAlertEnabled) return;

    final threshold = alertsConfig.batteryPercentage;
    if (threshold == null) return;

    if (level <= threshold) {
      print('DEBUG AlertMonitoring: battery alert! $level% <= $threshold%');
      final coord = _lastMovementCoordinate ?? Coordinate(lat: 0, lng: 0, utm: '');
      _sendAlert(AlertType.battery, coord);
    }
  }

  // ===========================================================================
  // Stub: No Reception
  // ===========================================================================

  // ignore: unused_element
  void _checkNoReception() {
    // TODO: requires deeper connectivity_plus integration
  }

  // ===========================================================================
  // Alert Sending with Cooldown
  // ===========================================================================

  Future<void> _sendAlert(AlertType type, Coordinate location) async {
    // בדיקת cooldown — proximity משתמש בהגדרת proximityMinTime מהניווט
    final lastTime = _lastAlertTime[type];
    Duration cooldown;
    if (type == AlertType.proximity && alertsConfig.proximityMinTime != null) {
      cooldown = Duration(minutes: alertsConfig.proximityMinTime!);
    } else {
      cooldown = _defaultCooldowns[type] ?? const Duration(minutes: 5);
    }

    if (lastTime != null && DateTime.now().difference(lastTime) < cooldown) {
      print('DEBUG AlertMonitoring: cooldown active for ${type.code}, skipping');
      return;
    }

    _lastAlertTime[type] = DateTime.now();

    final alert = NavigatorAlert(
      id: '${type.code}_${DateTime.now().millisecondsSinceEpoch}',
      navigationId: navigationId,
      navigatorId: navigatorId,
      type: type,
      location: location,
      timestamp: DateTime.now(),
      navigatorName: navigatorName,
    );

    try {
      await alertRepository.create(alert);
      print('DEBUG AlertMonitoring: alert sent — ${type.displayName}');
    } catch (e) {
      print('DEBUG AlertMonitoring: failed to send alert: $e');
    }

    // notify callback (לתצוגת באנר בצד המנווט)
    onAlert?.call(alert);
  }
}

/// מיקום מנווט אחר (לבדיקת קרבה)
class _OtherNavigatorPosition {
  final Coordinate coordinate;
  final DateTime timestamp;

  _OtherNavigatorPosition({
    required this.coordinate,
    required this.timestamp,
  });
}
