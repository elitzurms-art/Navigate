import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:gps_plus/gps_plus.dart';
import 'package:latlong2/latlong.dart';
import '../domain/entities/coordinate.dart';
import 'elevation_service.dart';
import 'gps_service.dart';
import 'position_kalman_filter.dart';

enum GpsJammingState { normal, jammed, recovering }

/// שירות מעקב GPS
class GPSTrackingService {
  Timer? _trackingTimer;
  StreamController<Position>? _positionStream;
  StreamSubscription<Position>? _geolocatorStreamSub;
  List<TrackPoint> _trackPoints = [];
  final GpsService _gpsService = GpsService();
  final ElevationService _elevationService = ElevationService();
  final PositionKalmanFilter _kalmanFilter = PositionKalmanFilter();

  bool _isTracking = false;
  bool get isTracking => _isTracking;

  /// נעילת concurrency — מונע קריאות getCurrentPosition מקבילות
  bool _isRecording = false;

  int _intervalSeconds = 30;
  LatLng? _boundaryCenter;
  bool _gpsSpoofingDetectionEnabled = true;
  double _gpsSpoofingMaxDistanceMeters = 50000.0;
  int get intervalSeconds => _intervalSeconds;

  // --- Anti-Drift (ZUPT) ---
  int _stepsSinceLastRecord = 0;
  DateTime? _lastStepTime;
  StreamSubscription<PdrPositionResult>? _pdrStepSubscription;
  static const Duration _stationaryTimeout = Duration(seconds: 5);
  static const double _driftThresholdMeters = 8.0;

  // --- Gap-Fill (PDR during GPS loss) ---
  DateTime? _lastGpsFixTime;
  Timer? _gapDetectionTimer;
  bool _isGapFilling = false;
  StreamSubscription<PdrPositionResult>? _gapFillSubscription;
  static const Duration _gapThreshold = Duration(seconds: 3);

  // --- Jamming State Machine ---
  GpsJammingState _jammingState = GpsJammingState.normal;
  GpsJammingState get jammingState => _jammingState;
  int _consecutiveBadGpsFixes = 0;
  int _consecutiveGoodGpsFixes = 0;
  DateTime? _manualCooldownEnd;
  double? _lastRawGpsLat;
  double? _lastRawGpsLng;
  DateTime? _lastRawGpsTimestamp;

  static const double _jammingAccuracyThreshold = 25.0;
  static const double _maxSpeedMps = 41.67; // 150 km/h
  static const double _recoveryAccuracyThreshold = 20.0;
  static const int _requiredBadFixes = 3;
  static const int _requiredGoodFixes = 3;
  static const Duration _manualCooldownDuration = Duration(minutes: 5);

  bool get isManualCooldownActive =>
      _manualCooldownEnd != null && DateTime.now().isBefore(_manualCooldownEnd!);
  int get recoveryProgress => _consecutiveGoodGpsFixes;

  /// מקור מיקום כפוי — 'auto' (ברירת מחדל), 'cellTower', 'gps', 'pdr'
  String _forcePositionSource = 'auto';
  String get forcePositionSource => _forcePositionSource;
  set forcePositionSource(String value) {
    _forcePositionSource = value;
    print('DEBUG GPSTrackingService: forcePositionSource set to: $value');
  }

  /// מקורות מיקום מותרים (מוגדר per-navigation)
  List<String> _enabledSources = const ['gps', 'cellTower', 'pdr', 'pdrCellHybrid'];

  /// getter למקורות מיקום מותרים (לשימוש בדריסה מרחוק)
  List<String> get enabledSources => List.unmodifiable(_enabledSources);

  /// עדכון מקורות מיקום מותרים בזמן אמת (דריסה ע"י מפקד)
  void updateEnabledSources(List<String> newSources) {
    if (!_isTracking) return;

    final gpsWasEnabled = _enabledSources.contains('gps');
    _enabledSources = newSources;
    final gpsNowEnabled = newSources.contains('gps');
    print('DEBUG GPSTrackingService: enabledSources updated to: $newSources');

    // GPS status didn't change — no mechanism restart needed
    if (gpsWasEnabled == gpsNowEnabled) return;

    // GPS status changed — restart tracking mechanism
    _trackingTimer?.cancel();
    _trackingTimer = null;
    _geolocatorStreamSub?.cancel();
    _geolocatorStreamSub = null;
    _exitGapFillMode();
    _gapDetectionTimer?.cancel();
    _gapDetectionTimer = null;

    if (_forcePositionSource == 'cellTower' || _forcePositionSource == 'pdr') {
      _trackingTimer = Timer.periodic(
        Duration(seconds: _intervalSeconds), (timer) => _recordCurrentPosition());
      return;
    }

    if (gpsNowEnabled && _intervalSeconds <= 5) {
      // GPS re-enabled + short interval → stream mode
      _startPositionStream();
      _lastGpsFixTime = DateTime.now();
      _startGapDetectionTimer();
    } else {
      // GPS disabled OR long interval → timer mode with fallbacks
      _trackingTimer = Timer.periodic(
        Duration(seconds: _intervalSeconds), (timer) => _recordCurrentPosition());
    }
  }

  /// Whether the tracker is currently in a GPS gap (PDR gap-fill active).
  bool get isInGpsGap => _isGapFilling;

  /// Stream של מיקומים
  Stream<Position> get positionStream =>
      _positionStream?.stream ?? const Stream.empty();

  /// נקודות המסלול שנאספו
  List<TrackPoint> get trackPoints => List.unmodifiable(_trackPoints);

  /// התחלת מעקב GPS
  Future<bool> startTracking({
    int intervalSeconds = 5,
    LatLng? boundaryCenter,
    String forcePositionSource = 'auto',
    List<String> enabledPositionSources = const ['gps', 'cellTower', 'pdr', 'pdrCellHybrid'],
    bool gpsSpoofingDetectionEnabled = true,
    int gpsSpoofingMaxDistanceKm = 50,
  }) async {
    if (_isTracking) {
      print('GPS Tracking כבר פעיל');
      return false;
    }

    _intervalSeconds = intervalSeconds;
    _boundaryCenter = boundaryCenter;
    _forcePositionSource = forcePositionSource;
    _enabledSources = enabledPositionSources;
    _gpsSpoofingDetectionEnabled = gpsSpoofingDetectionEnabled;
    _gpsSpoofingMaxDistanceMeters = gpsSpoofingMaxDistanceKm * 1000.0;

    // Initialize PDR only for short intervals (≤10s) — above that, PDR
    // wastes battery on unreliable dead-reckoning calculations.
    if (_forcePositionSource != 'cellTower' && _intervalSeconds <= 10) {
      await _gpsService.initPdr();
    }

    // כפיית אנטנות — לא צריך הרשאות GPS
    if (_forcePositionSource == 'cellTower') {
      _positionStream = StreamController<Position>.broadcast();
      _trackPoints = [];
      _kalmanFilter.reset();
      _isTracking = true;

      // נקודה ראשונה מאנטנות
      try {
        final cellPos = await _gpsService.getCurrentPosition(
          boundaryCenter: _boundaryCenter,
          forceSource: 'cellTower',
        );
        if (cellPos != null) {
          _recordPointFromLatLng(cellPos.latitude, cellPos.longitude, -1,
            positionSource: 'cellTower');
          print('GPS Tracking התחיל - מיקום ראשוני (cellTower forced): ${cellPos.latitude}, ${cellPos.longitude}');
        }
      } catch (e) {
        print('שגיאה בקבלת מיקום ראשוני (cell): $e');
      }

      _trackingTimer = Timer.periodic(
        Duration(seconds: _intervalSeconds),
        (timer) => _recordCurrentPosition(),
      );

      print('GPS Tracking פעיל (cell forced) - רישום כל $_intervalSeconds שניות');
      return true;
    }

    // כפיית PDR+Cell hybrid
    if (_forcePositionSource == 'pdr') {
      _positionStream = StreamController<Position>.broadcast();
      _trackPoints = [];
      _kalmanFilter.reset();
      _isTracking = true;

      try {
        final pdrPos = await _gpsService.getCurrentPosition(
          boundaryCenter: _boundaryCenter,
          forceSource: 'pdr',
        );
        if (pdrPos != null) {
          final source = _gpsService.lastPositionSource;
          _recordPointFromLatLng(pdrPos.latitude, pdrPos.longitude, -1,
            positionSource: source.name);
          print('GPS Tracking התחיל - מיקום ראשוני (PDR): ${pdrPos.latitude}, ${pdrPos.longitude}');
        }
      } catch (e) {
        print('שגיאה בקבלת מיקום ראשוני (PDR): $e');
      }

      _trackingTimer = Timer.periodic(
        Duration(seconds: _intervalSeconds),
        (timer) => _recordCurrentPosition(),
      );

      print('GPS Tracking פעיל (PDR forced) - רישום כל $_intervalSeconds שניות');
      return true;
    }

    // בדיקת הרשאות GPS — אם אין, ממשיך עם fallback אנטנות
    bool gpsAvailable = false;
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission != LocationPermission.denied &&
          permission != LocationPermission.deniedForever) {
        gpsAvailable = await Geolocator.isLocationServiceEnabled();
      }
    } catch (_) {}

    if (!gpsAvailable && _forcePositionSource == 'gps') {
      print('GPS לא זמין ומצב כפוי GPS — לא ניתן להתחיל');
      return false;
    }

    if (!gpsAvailable) {
      print('GPS לא זמין — ממשיך עם fallback PDR+Cell');
    }

    _positionStream = StreamController<Position>.broadcast();
    _trackPoints = [];
    _kalmanFilter.reset();
    _isTracking = true;

    // רישום נקודה ראשונה
    try {
      if (gpsAvailable) {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10),
        );

        // Set PDR anchor on good GPS fix (ZUPT-aware threshold)
        final anchorThreshold = _gpsService.isPdrStationary ? 40.0 : 20.0;
        if (position.accuracy < anchorThreshold) {
          _gpsService.setPdrAnchor(position.latitude, position.longitude, heading: position.heading);
        }

        // אם הדיוק נמוך, נסה fallback דרך GPS Plus
        if (position.accuracy > 30 && _forcePositionSource != 'gps') {
          final cellPos = await _gpsService.getCurrentPosition(
            boundaryCenter: _boundaryCenter,
            forceSource: _forcePositionSource,
          );
          if (cellPos != null &&
              (_gpsService.lastPositionSource == PositionSource.cellTower ||
               _gpsService.lastPositionSource == PositionSource.pdr ||
               _gpsService.lastPositionSource == PositionSource.pdrCellHybrid)) {
            _recordPointFromLatLng(
              cellPos.latitude,
              cellPos.longitude,
              position.accuracy,
              positionSource: _gpsService.lastPositionSource.name,
            );
            print('GPS Tracking התחיל - מיקום ראשוני (${_gpsService.lastPositionSource.name}): ${cellPos.latitude}, ${cellPos.longitude}');
          } else {
            _recordPoint(position, positionSource: 'gps');
            print('GPS Tracking התחיל - מיקום ראשוני: ${position.latitude}, ${position.longitude}');
          }
        } else {
          _recordPoint(position, positionSource: 'gps');
          print('GPS Tracking התחיל - מיקום ראשוני: ${position.latitude}, ${position.longitude}');
        }
      } else {
        // GPS לא זמין — נסה PDR hybrid / אנטנות
        final cellPos = await _gpsService.getCurrentPosition(
          boundaryCenter: _boundaryCenter,
          forceSource: _forcePositionSource,
        );
        if (cellPos != null) {
          _recordPointFromLatLng(
            cellPos.latitude,
            cellPos.longitude,
            -1,
            positionSource: _gpsService.lastPositionSource.name,
          );
          print('GPS Tracking התחיל - מיקום ראשוני (fallback): ${cellPos.latitude}, ${cellPos.longitude}');
        } else {
          print('GPS Tracking התחיל ללא מיקום ראשוני');
        }
      }
    } catch (e) {
      print('שגיאה בקבלת מיקום ראשוני: $e');
      // נסה fallback
      try {
        final cellPos = await _gpsService.getCurrentPosition(
          boundaryCenter: _boundaryCenter,
          forceSource: _forcePositionSource,
        );
        if (cellPos != null) {
          _recordPointFromLatLng(cellPos.latitude, cellPos.longitude, -1,
            positionSource: _gpsService.lastPositionSource.name);
          print('מיקום ראשוני מ-fallback: ${cellPos.latitude}, ${cellPos.longitude}');
        }
      } catch (_) {}
    }

    // אסטרטגיית דגימה: stream לאינטרוולים קצרים, timer לאינטרוולים ארוכים
    if (_intervalSeconds <= 5 && gpsAvailable) {
      // שימוש ב-Position Stream — GPS נשאר דלוק ברציפות, דגימה מהירה
      _startPositionStream();
      print('GPS Tracking פעיל (stream mode) - רישום כל $_intervalSeconds שניות');
    } else {
      // Timer-based polling — לאינטרוולים ארוכים
      _trackingTimer = Timer.periodic(
        Duration(seconds: _intervalSeconds),
        (timer) => _recordCurrentPosition(),
      );
      print('GPS Tracking פעיל (timer mode) - רישום כל $_intervalSeconds שניות');
    }

    // Anti-Drift: subscribe to PDR step stream for step counting
    // (only when PDR is active — short intervals)
    if (_intervalSeconds <= 10) {
      _startStepSubscription();
    }

    // Gap-Fill: start gap detection (stream mode only — timer mode uses existing fallback)
    if (_intervalSeconds <= 5 && gpsAvailable) {
      _lastGpsFixTime = DateTime.now();
      _startGapDetectionTimer();
    }

    return true;
  }

  /// מצב stream — GPS רציף לאינטרוולים קצרים (≤5 שניות)
  void _startPositionStream() {
    _geolocatorStreamSub?.cancel();
    DateTime? _lastRecordTime;

    _geolocatorStreamSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
      ),
    ).listen(
      (position) {
        final now = DateTime.now();
        // מסנן לפי interval שהוגדר — stream יכול לשלוח בתדירות גבוהה יותר
        if (_lastRecordTime != null &&
            now.difference(_lastRecordTime!).inMilliseconds < (_intervalSeconds * 800)) {
          return; // מוקדם מדי — דלג
        }
        _lastRecordTime = now;

        // Guard: if GPS was disabled after stream started, skip recording
        if (!_isSourceAllowed('gps')) return;

        // Jamming state machine evaluation
        final shouldUseGps = _processJammingStateMachine(position);
        if (!shouldUseGps) return; // jammed/recovering/cooldown — gap-fill provides positions

        // GPS good — update PDR anchor + record
        final anchorThreshold = _gpsService.isPdrStationary ? 40.0 : 20.0;
        if (position.accuracy < anchorThreshold) {
          _gpsService.setPdrAnchor(position.latitude, position.longitude, heading: position.heading);
        }

        _recordPoint(position, positionSource: 'gps');
        _positionStream?.add(position);
      },
      onError: (e) {
        print('GPS stream error: $e');
      },
    );
  }

  /// עדכון אינטרוול דגימה בזמן אמת (ללא איפוס נקודות)
  void updateInterval(int newIntervalSeconds) {
    if (newIntervalSeconds == _intervalSeconds || !_isTracking) return;

    print('DEBUG GPSTrackingService: updateInterval $_intervalSeconds -> $newIntervalSeconds');
    _intervalSeconds = newIntervalSeconds;

    // ביטול מנגנון דגימה קיים
    _trackingTimer?.cancel();
    _trackingTimer = null;
    _geolocatorStreamSub?.cancel();
    _geolocatorStreamSub = null;

    // Cancel gap detection (will restart if switching to stream mode)
    _exitGapFillMode();
    _gapDetectionTimer?.cancel();
    _gapDetectionTimer = null;

    // הפעלה מחדש — cellTower/pdr תמיד timer, אחרת לפי סף 5 שניות
    if (_forcePositionSource == 'cellTower' || _forcePositionSource == 'pdr') {
      _trackingTimer = Timer.periodic(
        Duration(seconds: _intervalSeconds),
        (timer) => _recordCurrentPosition(),
      );
      print('GPS Tracking interval updated (timer mode, forced $_forcePositionSource) - כל $_intervalSeconds שניות');
    } else if (_intervalSeconds <= 5) {
      _startPositionStream();
      _lastGpsFixTime = DateTime.now();
      _startGapDetectionTimer();
      print('GPS Tracking interval updated (stream mode) - כל $_intervalSeconds שניות');
    } else {
      _trackingTimer = Timer.periodic(
        Duration(seconds: _intervalSeconds),
        (timer) => _recordCurrentPosition(),
      );
      print('GPS Tracking interval updated (timer mode) - כל $_intervalSeconds שניות');
    }
  }

  /// עצירת מעקב GPS
  Future<void> stopTracking() async {
    if (!_isTracking) return;

    _trackingTimer?.cancel();
    _trackingTimer = null;

    await _geolocatorStreamSub?.cancel();
    _geolocatorStreamSub = null;

    // Cancel anti-drift step subscription
    await _pdrStepSubscription?.cancel();
    _pdrStepSubscription = null;

    // Cancel gap-fill
    _exitGapFillMode();
    _gapDetectionTimer?.cancel();
    _gapDetectionTimer = null;

    await _positionStream?.close();
    _positionStream = null;

    // Stop PDR
    _gpsService.stopPdr();

    // Reset jamming state
    _jammingState = GpsJammingState.normal;
    _consecutiveBadGpsFixes = 0;
    _consecutiveGoodGpsFixes = 0;
    _manualCooldownEnd = null;
    _lastRawGpsLat = null;
    _lastRawGpsLng = null;
    _lastRawGpsTimestamp = null;

    _isTracking = false;

    print('GPS Tracking הופסק - נרשמו ${_trackPoints.length} נקודות');
  }

  // ===========================================================================
  // Anti-Drift (ZUPT) — step counting + stationary detection
  // ===========================================================================

  /// Subscribe to PDR step stream for step counting (anti-drift).
  /// If PDR is not available (iOS, no sensors), this is a no-op.
  void _startStepSubscription() {
    final pdrStream = _gpsService.pdrPositionStream;
    if (pdrStream == null) {
      print('DEBUG GPSTrackingService: PDR not available — anti-drift disabled');
      return;
    }

    _pdrStepSubscription = pdrStream.listen((_) {
      _stepsSinceLastRecord++;
      _lastStepTime = DateTime.now();
    });
    print('DEBUG GPSTrackingService: step subscription active — anti-drift enabled');
  }

  /// Check if the user is stationary (no steps for >5 seconds).
  bool get _isStationary {
    if (_lastStepTime == null) return true;
    return DateTime.now().difference(_lastStepTime!) > _stationaryTimeout;
  }

  /// Check if a GPS displacement should be rejected as drift.
  /// Returns true if the user is stationary and the displacement exceeds threshold.
  bool _shouldRejectAsDrift(double newLat, double newLng) {
    // Stream mode (≤5s interval) — let Kalman filter handle smoothing
    if (_intervalSeconds <= 5) return false;
    if (!_isStationary) return false;
    if (_trackPoints.isEmpty) return false;
    if (_stepsSinceLastRecord > 0) return false;

    final lastPoint = _trackPoints.last;
    final displacement = Geolocator.distanceBetween(
      lastPoint.coordinate.lat, lastPoint.coordinate.lng,
      newLat, newLng,
    );

    if (displacement > _driftThresholdMeters) {
      print('ZUPT: stationary — skipping GPS drift '
          '(${displacement.toStringAsFixed(1)}m displacement, 0 steps)');
      return true;
    }
    return false;
  }

  /// Check if GPS displacement is anomalously large relative to steps taken.
  /// Returns true if the displacement far exceeds what walking could produce.
  bool _isVelocityAnomalous(double newLat, double newLng) {
    if (_trackPoints.isEmpty) return false;
    if (_stepsSinceLastRecord <= 0) return false; // handled by drift check
    if (_lastStepTime == null) return false;       // no PDR data

    final lastPoint = _trackPoints.last;
    final dt = DateTime.now().difference(lastPoint.timestamp).inSeconds;
    if (dt > 30) return false; // long interval — step data unreliable

    final gpsDisplacement = Geolocator.distanceBetween(
      lastPoint.coordinate.lat, lastPoint.coordinate.lng,
      newLat, newLng,
    );

    // Max expected distance: steps × max step length (1.2m) × safety margin (2.0)
    final maxExpectedDistance = _stepsSinceLastRecord * 1.2 * 2.0;

    // Reject if GPS displacement is >5× expected walking distance
    if (gpsDisplacement > maxExpectedDistance && gpsDisplacement > 10.0 &&
        gpsDisplacement / maxExpectedDistance > 5.0) {
      print('VELOCITY CHECK: anomalous GPS displacement '
          '${gpsDisplacement.toStringAsFixed(0)}m vs '
          '${maxExpectedDistance.toStringAsFixed(0)}m expected '
          '($_stepsSinceLastRecord steps × 1.2m × 2.0)');
      return true;
    }
    return false;
  }

  /// General sanity check: reject positions that imply physically impossible speed.
  bool _isJumpAnomalous(double newLat, double newLng) {
    if (_trackPoints.isEmpty) return false;

    final lastPoint = _trackPoints.last;
    final dtSeconds = DateTime.now().difference(lastPoint.timestamp).inSeconds;
    if (dtSeconds <= 0) return false;

    final displacement = Geolocator.distanceBetween(
      lastPoint.coordinate.lat, lastPoint.coordinate.lng,
      newLat, newLng,
    );

    // Only flag large absolute jumps (>500m) to avoid false positives on GPS jitter
    if (displacement <= 500) return false;

    // Reject if implied speed > 150 km/h (41.67 m/s)
    final impliedSpeedMps = displacement / dtSeconds;
    if (impliedSpeedMps > 41.67) {
      print('JUMP CHECK: rejecting position — '
          '${displacement.toStringAsFixed(0)}m in ${dtSeconds}s = '
          '${(impliedSpeedMps * 3.6).toStringAsFixed(0)} km/h');
      return true;
    }
    return false;
  }

  /// Sliding window trajectory consistency check.
  /// Removes outlier points that create two impossible segments
  /// but whose removal restores a plausible path.
  void _pruneWindowOutliers() {
    const double maxSpeedMps = 41.67; // 150 km/h
    const double minJumpDistance = 800; // meters
    const int windowSize = 5;

    if (_trackPoints.length < windowSize) return;

    final start = _trackPoints.length - windowSize;
    final window = _trackPoints.sublist(start);

    int? indexToRemove;

    for (int i = 1; i < window.length - 1; i++) {
      final prev = window[i - 1];
      final current = window[i];
      final next = window[i + 1];

      final d1 = Geolocator.distanceBetween(
        prev.coordinate.lat, prev.coordinate.lng,
        current.coordinate.lat, current.coordinate.lng,
      );
      final d2 = Geolocator.distanceBetween(
        current.coordinate.lat, current.coordinate.lng,
        next.coordinate.lat, next.coordinate.lng,
      );
      final dDirect = Geolocator.distanceBetween(
        prev.coordinate.lat, prev.coordinate.lng,
        next.coordinate.lat, next.coordinate.lng,
      );

      final dt1 = current.timestamp.difference(prev.timestamp).inSeconds.abs();
      final dt2 = next.timestamp.difference(current.timestamp).inSeconds.abs();
      final dtDirect = next.timestamp.difference(prev.timestamp).inSeconds.abs();

      if (dt1 <= 0 || dt2 <= 0 || dtDirect <= 0) continue;

      final speed1 = d1 / dt1;
      final speed2 = d2 / dt2;
      final speedDirect = dDirect / dtDirect;

      final leg1Impossible = speed1 > maxSpeedMps && d1 > minJumpDistance;
      final leg2Impossible = speed2 > maxSpeedMps && d2 > minJumpDistance;
      final directPlausible = speedDirect < maxSpeedMps && dDirect < 300;

      if (leg1Impossible && leg2Impossible && directPlausible) {
        indexToRemove = start + i;
        break;
      }
    }

    if (indexToRemove != null) {
      final removed = _trackPoints[indexToRemove];
      print('WINDOW OUTLIER: removing point $indexToRemove '
          '[${removed.positionSource}] at '
          '${removed.coordinate.lat}, ${removed.coordinate.lng}');
      _trackPoints.removeAt(indexToRemove);
    }
  }

  // ===========================================================================
  // Jamming State Machine — detection, recovery, manual cooldown
  // ===========================================================================

  /// Evaluate a single GPS fix quality for jamming detection/recovery.
  /// [forRecovery] uses the stricter threshold (20m vs 50m).
  bool _isGpsFixGood(Position position, {bool forRecovery = false}) {
    final accuracyThreshold = forRecovery
        ? _recoveryAccuracyThreshold
        : _jammingAccuracyThreshold;

    // Accuracy check
    if (position.accuracy > accuracyThreshold) return false;

    // Speed check between consecutive raw GPS fixes
    if (_lastRawGpsLat != null && _lastRawGpsTimestamp != null) {
      final dt = DateTime.now().difference(_lastRawGpsTimestamp!).inMilliseconds / 1000.0;
      if (dt > 0.5) {
        final dist = Geolocator.distanceBetween(
          _lastRawGpsLat!, _lastRawGpsLng!,
          position.latitude, position.longitude,
        );
        final speed = dist / dt;
        if (speed > _maxSpeedMps) return false;
      }
    }

    // Boundary spoof check (configurable per-navigation)
    if (_gpsSpoofingDetectionEnabled && _boundaryCenter != null) {
      final dist = Geolocator.distanceBetween(
        position.latitude, position.longitude,
        _boundaryCenter!.latitude, _boundaryCenter!.longitude,
      );
      if (dist > _gpsSpoofingMaxDistanceMeters) return false;
    }

    return true;
  }

  /// Process GPS fix through jamming state machine.
  /// Returns true if the GPS fix should be used (normal operation).
  bool _processJammingStateMachine(Position position) {
    // Track raw GPS for speed calculation
    _lastRawGpsLat = position.latitude;
    _lastRawGpsLng = position.longitude;
    _lastRawGpsTimestamp = DateTime.now();

    // Manual cooldown — suppress all GPS
    if (isManualCooldownActive) {
      print('JAMMING: manual cooldown active — ignoring GPS');
      return false;
    }

    switch (_jammingState) {
      case GpsJammingState.normal:
        if (_isGpsFixGood(position)) {
          _consecutiveBadGpsFixes = 0;
          return true;
        } else {
          _consecutiveBadGpsFixes++;
          print('JAMMING: bad GPS fix #$_consecutiveBadGpsFixes/$_requiredBadFixes '
              '(accuracy=${position.accuracy.toStringAsFixed(1)}m)');
          if (_consecutiveBadGpsFixes >= _requiredBadFixes) {
            _jammingState = GpsJammingState.jammed;
            _consecutiveBadGpsFixes = 0;
            _enterJammedMode();
          }
          return false;
        }

      case GpsJammingState.jammed:
        if (_isGpsFixGood(position, forRecovery: true)) {
          _jammingState = GpsJammingState.recovering;
          _consecutiveGoodGpsFixes = 1;
          print('JAMMING: first good fix during jamming — entering recovery (1/$_requiredGoodFixes)');
          return false; // not yet trusted
        }
        return false;

      case GpsJammingState.recovering:
        if (_isGpsFixGood(position, forRecovery: true)) {
          _consecutiveGoodGpsFixes++;
          print('JAMMING: good fix during recovery ($_consecutiveGoodGpsFixes/$_requiredGoodFixes)');
          if (_consecutiveGoodGpsFixes >= _requiredGoodFixes) {
            _jammingState = GpsJammingState.normal;
            _consecutiveGoodGpsFixes = 0;
            _exitJammedMode();
            print('JAMMING: recovery complete — returning to normal');
            return true;
          }
          return false;
        } else {
          // Bad fix during recovery — back to jammed
          _jammingState = GpsJammingState.jammed;
          _consecutiveGoodGpsFixes = 0;
          print('JAMMING: bad fix during recovery — back to jammed');
          return false;
        }
    }
  }

  /// Enter jammed mode — activate PDR gap-fill.
  void _enterJammedMode() {
    print('JAMMING: entering jammed mode — activating PDR fallback');
    if (!_isGapFilling) {
      _enterGapFillMode();
    }
  }

  /// Exit jammed mode — deactivate gap-fill, reset GPS timing.
  void _exitJammedMode() {
    print('JAMMING: exiting jammed mode — deactivating PDR fallback');
    _exitGapFillMode();
    _lastGpsFixTime = DateTime.now(); // prevent gap timer re-trigger
  }

  // ===========================================================================
  // Gap-Fill — PDR positions during GPS signal loss
  // ===========================================================================

  /// Start gap detection timer (stream mode only).
  void _startGapDetectionTimer() {
    _gapDetectionTimer?.cancel();
    _gapDetectionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_lastGpsFixTime == null) return;
      if (_isGapFilling) return;
      if (DateTime.now().difference(_lastGpsFixTime!) > _gapThreshold) {
        _enterGapFillMode();
      }
    });
  }

  /// Enter gap-fill mode: subscribe to PDR stream and emit positions.
  void _enterGapFillMode() {
    if (_isGapFilling) return;
    // Don't gap-fill with PDR if PDR is disabled
    if (!_enabledSources.contains('pdr') && !_enabledSources.contains('pdrCellHybrid')) return;
    final pdrStream = _gpsService.pdrPositionStream;
    if (pdrStream == null) return; // PDR not available — can't gap-fill

    _isGapFilling = true;
    print('GPS gap detected — entering PDR gap-fill mode');

    _gapFillSubscription = pdrStream.listen((pdrPos) {
      _recordGapFillPoint(pdrPos);
    });
  }

  /// Exit gap-fill mode (GPS returned).
  void _exitGapFillMode() {
    if (!_isGapFilling) return;
    _isGapFilling = false;
    _gapFillSubscription?.cancel();
    _gapFillSubscription = null;
    print('GPS returned — exiting PDR gap-fill mode');
  }

  /// Record a PDR position during gap-fill (bypasses Kalman filter).
  void _recordGapFillPoint(PdrPositionResult pdrPos) {
    final point = TrackPoint(
      coordinate: Coordinate(
        lat: pdrPos.lat,
        lng: pdrPos.lon,
        utm: _convertToUTM(pdrPos.lat, pdrPos.lon),
      ),
      timestamp: DateTime.now(),
      accuracy: pdrPos.accuracyMeters,
      heading: pdrPos.headingDegrees,
      positionSource: 'pdr_gap_fill',
    );

    _trackPoints.add(point);
    print('רישום נקודה ${_trackPoints.length}: ${point.coordinate.lat}, '
        '${point.coordinate.lng} [pdr_gap_fill]');

    // Emit on position stream so map updates in real-time
    _positionStream?.add(Position(
      latitude: pdrPos.lat,
      longitude: pdrPos.lon,
      timestamp: DateTime.now(),
      accuracy: pdrPos.accuracyMeters,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: pdrPos.headingDegrees,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    ));

    _enrichWithDemElevation(_trackPoints.length - 1, pdrPos.lat, pdrPos.lon);
  }

  // ===========================================================================

  /// רישום מיקום נוכחי
  Future<void> _recordCurrentPosition() async {
    // מניעת קריאות מקבילות — אם הקריאה הקודמת עדיין רצה, דלג
    if (_isRecording) {
      print('DEBUG GPS: skipping _recordCurrentPosition — previous call still running');
      return;
    }
    _isRecording = true;
    try {
      await _recordCurrentPositionInner();
    } finally {
      _isRecording = false;
    }
  }

  Future<void> _recordCurrentPositionInner() async {
    // כפיית אנטנות — דלג על כל בדיקות ה-GPS
    if (_forcePositionSource == 'cellTower') {
      try {
        final cellPos = await _gpsService.getCurrentPosition(
          boundaryCenter: _boundaryCenter,
          forceSource: 'cellTower',
        );
        if (cellPos != null) {
          _recordPointFromLatLng(cellPos.latitude, cellPos.longitude, -1,
            positionSource: 'cellTower');
        }
      } catch (e) {
        print('fallback אנטנות (forced) נכשל: $e');
      }
      return;
    }

    // כפיית PDR+Cell hybrid
    if (_forcePositionSource == 'pdr') {
      try {
        final pdrPos = await _gpsService.getCurrentPosition(
          boundaryCenter: _boundaryCenter,
          forceSource: 'pdr',
        );
        if (pdrPos != null) {
          _recordPointFromLatLng(pdrPos.latitude, pdrPos.longitude, -1,
            positionSource: _gpsService.lastPositionSource.name);
        }
      } catch (e) {
        print('PDR fallback (forced) נכשל: $e');
      }
      return;
    }

    // If GPS source disabled — skip GPS acquisition, use fallback directly
    if (!_isSourceAllowed('gps')) {
      if (!_hasAllowedFallback()) return;
      try {
        final fallbackPos = await _gpsService.getCurrentPosition(
          boundaryCenter: _boundaryCenter,
        );
        if (fallbackPos != null &&
            _isSourceAllowed(_gpsService.lastPositionSource.name)) {
          _recordPointFromLatLng(
            fallbackPos.latitude, fallbackPos.longitude, -1,
            positionSource: _gpsService.lastPositionSource.name,
          );
        }
      } catch (e) {
        print('fallback (GPS disabled) failed: $e');
      }
      return;
    }

    // בדיקה מהירה: אם GPS לא זמין, ישר ל-fallback
    bool gpsAvailable = true;
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        gpsAvailable = false;
      } else {
        gpsAvailable = await Geolocator.isLocationServiceEnabled();
      }
    } catch (_) {
      gpsAvailable = false;
    }

    if (!gpsAvailable) {
      if (_forcePositionSource == 'gps') return; // GPS כפוי אבל לא זמין
      // בדיקה אם יש מקור חלופי מותר
      final hasFallback = _enabledSources.contains('cellTower') ||
          _enabledSources.contains('pdr') ||
          _enabledSources.contains('pdrCellHybrid');
      if (!hasFallback) return;
      try {
        final cellPos = await _gpsService.getCurrentPosition(
          boundaryCenter: _boundaryCenter,
          forceSource: _forcePositionSource,
        );
        if (cellPos != null &&
            _isSourceAllowed(_gpsService.lastPositionSource.name)) {
          _recordPointFromLatLng(
            cellPos.latitude,
            cellPos.longitude,
            -1,
            positionSource: _gpsService.lastPositionSource.name,
          );
        }
      } catch (e) {
        print('fallback נכשל: $e');
      }
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      // Jamming state machine evaluation (timer mode)
      final shouldUseGps = _processJammingStateMachine(position);
      if (!shouldUseGps) {
        if (_forcePositionSource == 'gps') return;
        if (!_hasAllowedFallback()) return;
        // Use PDR/Cell fallback
        final fallbackPos = await _gpsService.getCurrentPosition(boundaryCenter: _boundaryCenter);
        if (fallbackPos != null &&
            _gpsService.lastPositionSource != PositionSource.gps &&
            _isSourceAllowed(_gpsService.lastPositionSource.name)) {
          _recordPointFromLatLng(fallbackPos.latitude, fallbackPos.longitude, -1,
              positionSource: _gpsService.lastPositionSource.name);
        }
        return;
      }

      // כפיית GPS — אין fallback
      if (_forcePositionSource == 'gps') {
        // Update PDR anchor on good fix (ZUPT-aware)
        final anchorThreshold = _gpsService.isPdrStationary ? 40.0 : 20.0;
        if (position.accuracy < anchorThreshold) {
          _gpsService.setPdrAnchor(position.latitude, position.longitude, heading: position.heading);
        }
        _recordPoint(position, positionSource: 'gps');
        _positionStream?.add(position);
        return;
      }

      // Update PDR anchor on good GPS fix (ZUPT-aware)
      final anchorThreshold = _gpsService.isPdrStationary ? 40.0 : 20.0;
      if (position.accuracy < anchorThreshold) {
        _gpsService.setPdrAnchor(position.latitude, position.longitude, heading: position.heading);
      }

      // בדיקת GPS חסום/מזויף — מרחק ממרכז הג"ג (configurable per-navigation)
      if (_gpsSpoofingDetectionEnabled && _boundaryCenter != null) {
        final dist = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          _boundaryCenter!.latitude,
          _boundaryCenter!.longitude,
        );
        if (dist > _gpsSpoofingMaxDistanceMeters && _hasAllowedFallback()) {
          // GPS likely spoofed — try PDR hybrid / cell towers
          final cellPos = await _gpsService.getCurrentPosition(boundaryCenter: _boundaryCenter);
          if (cellPos != null &&
              _gpsService.lastPositionSource != PositionSource.gps &&
              _isSourceAllowed(_gpsService.lastPositionSource.name)) {
            _recordPointFromLatLng(
              cellPos.latitude,
              cellPos.longitude,
              position.accuracy,
              positionSource: _gpsService.lastPositionSource.name,
            );
            _positionStream?.add(position);
            return;
          }
        }
      }

      // אם הדיוק נמוך (> 50 מטר), נסה fallback (רק אם יש מקור חלופי מותר)
      if (position.accuracy > 30 && _hasAllowedFallback()) {
        final cellPos = await _gpsService.getCurrentPosition(boundaryCenter: _boundaryCenter);
        if (cellPos != null &&
            _gpsService.lastPositionSource != PositionSource.gps &&
            _isSourceAllowed(_gpsService.lastPositionSource.name)) {
          _recordPointFromLatLng(
            cellPos.latitude,
            cellPos.longitude,
            position.accuracy,
            positionSource: _gpsService.lastPositionSource.name,
          );
          _positionStream?.add(position);
          return;
        }
      }

      // Guard: skip GPS recording if source disabled by commander
      if (!_isSourceAllowed('gps')) {
        if (_hasAllowedFallback()) {
          try {
            final fallbackPos = await _gpsService.getCurrentPosition(boundaryCenter: _boundaryCenter);
            if (fallbackPos != null &&
                _gpsService.lastPositionSource != PositionSource.gps &&
                _isSourceAllowed(_gpsService.lastPositionSource.name)) {
              _recordPointFromLatLng(fallbackPos.latitude, fallbackPos.longitude, -1,
                  positionSource: _gpsService.lastPositionSource.name);
            }
          } catch (_) {}
        }
        return;
      }

      _recordPoint(position, positionSource: 'gps');
      _positionStream?.add(position);
    } catch (e) {
      // GPS failed completely — try fallback
      if (_forcePositionSource == 'gps') return;
      if (!_hasAllowedFallback()) return;
      print('שגיאה ברישום מיקום: $e — מנסה fallback');
      try {
        final cellPos = await _gpsService.getCurrentPosition(boundaryCenter: _boundaryCenter);
        if (cellPos != null &&
            _isSourceAllowed(_gpsService.lastPositionSource.name)) {
          _recordPointFromLatLng(
            cellPos.latitude,
            cellPos.longitude,
            -1,
            positionSource: _gpsService.lastPositionSource.name,
          );
        }
      } catch (_) {
        print('גם fallback נכשל');
      }
    }
  }

  /// בדיקה אם מקור מיקום מותר
  bool _isSourceAllowed(String source) {
    // GPS תמיד מותר (אלא אם הוסר במפורש)
    if (source == 'gps') return _enabledSources.contains('gps');
    if (source == 'cellTower') return _enabledSources.contains('cellTower');
    if (source == 'pdr') return _enabledSources.contains('pdr');
    if (source == 'pdrCellHybrid') return _enabledSources.contains('pdrCellHybrid');
    return true; // מקור לא ידוע — מאפשר
  }

  /// בדיקה אם יש fallback מותר כלשהו
  bool _hasAllowedFallback() {
    return _enabledSources.contains('cellTower') ||
        _enabledSources.contains('pdr') ||
        _enabledSources.contains('pdrCellHybrid');
  }

  /// רישום נקודה מ-Position (Geolocator) — מסונן דרך Kalman filter
  void _recordPoint(Position position, {String positionSource = 'gps'}) {
    // Anti-Drift: reject GPS drift when stationary
    if (positionSource == 'gps' &&
        _shouldRejectAsDrift(position.latitude, position.longitude)) {
      return;
    }

    // Step-GPS cross-validation: reject anomalous velocity
    if (positionSource == 'gps' &&
        _isVelocityAnomalous(position.latitude, position.longitude)) {
      return;
    }

    // General jump sanity check: reject physically impossible displacements
    if (_isJumpAnomalous(position.latitude, position.longitude)) {
      return;
    }

    // Update Kalman filter motion state (ZUPT)
    _kalmanFilter.setMotionState(isStationary: _isStationary);

    final filtered = _kalmanFilter.update(
      lat: position.latitude,
      lng: position.longitude,
      accuracy: position.accuracy,
      timestamp: DateTime.now(),
    );

    final point = TrackPoint(
      coordinate: Coordinate(
        lat: filtered.lat,
        lng: filtered.lng,
        utm: _convertToUTM(filtered.lat, filtered.lng),
      ),
      timestamp: DateTime.now(),
      accuracy: filtered.accuracy,
      altitude: position.altitude,
      speed: position.speed,
      heading: position.heading,
      positionSource: positionSource,
    );

    _trackPoints.add(point);
    _pruneWindowOutliers();
    print('רישום נקודה ${_trackPoints.length}: ${point.coordinate.lat}, ${point.coordinate.lng} [$positionSource]');

    // Reset step counter after recording
    _stepsSinceLastRecord = 0;

    // Update GPS fix time + exit gap-fill mode
    if (positionSource == 'gps') {
      _lastGpsFixTime = DateTime.now();
      _exitGapFillMode();
    }

    // שאילתת גובה DEM ברקע — מדויק יותר מ-GPS altitude
    _enrichWithDemElevation(_trackPoints.length - 1, filtered.lat, filtered.lng);
  }

  /// רישום נקודה מ-LatLng (GPS Plus fallback) — מסונן דרך Kalman filter
  void _recordPointFromLatLng(
    double lat,
    double lng,
    double accuracy, {
    String positionSource = 'cellTower',
  }) {
    // General jump sanity check
    if (_isJumpAnomalous(lat, lng)) {
      return;
    }

    // Update Kalman filter motion state (ZUPT)
    _kalmanFilter.setMotionState(isStationary: _isStationary);

    final effectiveAccuracy = accuracy < 0 ? 500.0 : accuracy;
    final filtered = _kalmanFilter.update(
      lat: lat,
      lng: lng,
      accuracy: effectiveAccuracy,
      timestamp: DateTime.now(),
    );

    final point = TrackPoint(
      coordinate: Coordinate(
        lat: filtered.lat,
        lng: filtered.lng,
        utm: _convertToUTM(filtered.lat, filtered.lng),
      ),
      timestamp: DateTime.now(),
      accuracy: filtered.accuracy,
      positionSource: positionSource,
    );

    _trackPoints.add(point);
    _pruneWindowOutliers();
    print('רישום נקודה ${_trackPoints.length}: ${point.coordinate.lat}, ${point.coordinate.lng} [$positionSource]');

    // Reset step counter after recording
    _stepsSinceLastRecord = 0;

    // שאילתת גובה DEM ברקע
    _enrichWithDemElevation(_trackPoints.length - 1, filtered.lat, filtered.lng);
  }

  /// העשרת נקודה בגובה DEM — fire-and-forget
  void _enrichWithDemElevation(int index, double lat, double lng) {
    _elevationService.getElevation(lat, lng).then((elev) {
      if (elev != null && index < _trackPoints.length) {
        final old = _trackPoints[index];
        _trackPoints[index] = TrackPoint(
          coordinate: old.coordinate,
          timestamp: old.timestamp,
          accuracy: old.accuracy,
          altitude: elev.toDouble(),
          speed: old.speed,
          heading: old.heading,
          positionSource: old.positionSource,
        );
      }
    }).catchError((_) {});
  }

  /// רישום מיקום ידני (דקירה במפה) — עוקף Kalman filter + מאפס אותו
  void recordManualPosition(double lat, double lng) {
    // 1. Record point (bypasses Kalman, as before)
    final point = TrackPoint(
      coordinate: Coordinate(lat: lat, lng: lng, utm: _convertToUTM(lat, lng)),
      timestamp: DateTime.now(),
      accuracy: -1,
      positionSource: 'manual',
    );
    _trackPoints.add(point);
    _pruneWindowOutliers();
    print('רישום נקודה ידנית ${_trackPoints.length}: $lat, $lng [manual]');
    _enrichWithDemElevation(_trackPoints.length - 1, lat, lng);

    // 2. Reset Kalman filter at manual position
    _kalmanFilter.forcePosition(lat, lng);

    // 3. Reset PDR anchor
    _gpsService.setPdrAnchor(lat, lng);

    // 4. Start 5-minute GPS cooldown
    _manualCooldownEnd = DateTime.now().add(_manualCooldownDuration);
    print('JAMMING: manual position set — GPS cooldown until $_manualCooldownEnd');

    // 5. Reset step state
    _stepsSinceLastRecord = 0;
    _lastStepTime = null;
  }

  /// המרה ל-UTM (פשוט)
  String _convertToUTM(double lat, double lng) {
    const zone = 36;
    final easting = (500000 + ((lng - 33) * 111320 * (lat * 3.14159 / 180))).toInt();
    final northing = (lat * 110540).toInt();
    return '36R $easting $northing';
  }

  /// חישוב מרחק כולל של המסלול
  double getTotalDistance() {
    if (_trackPoints.length < 2) return 0;

    double total = 0;
    for (int i = 0; i < _trackPoints.length - 1; i++) {
      final dist = Geolocator.distanceBetween(
        _trackPoints[i].coordinate.lat,
        _trackPoints[i].coordinate.lng,
        _trackPoints[i + 1].coordinate.lat,
        _trackPoints[i + 1].coordinate.lng,
      );
      // Skip segments implying impossible speed (>150 km/h)
      final dtSeconds = _trackPoints[i + 1].timestamp
          .difference(_trackPoints[i].timestamp)
          .inSeconds
          .abs();
      if (dtSeconds > 0 && dist / dtSeconds > 41.67) continue;
      total += dist;
    }
    return total / 1000; // המרה למטרים לק"מ
  }

  /// חישוב מהירות ממוצעת
  double getAverageSpeed() {
    if (_trackPoints.isEmpty) return 0;

    final speedsWithValue = _trackPoints
        .where((p) => p.speed != null && p.speed! > 0)
        .map((p) => p.speed!)
        .toList();

    if (speedsWithValue.isEmpty) return 0;

    return speedsWithValue.reduce((a, b) => a + b) / speedsWithValue.length;
  }

  /// ייצוא ל-GPX
  String exportToGPX({required String name}) {
    final buffer = StringBuffer();

    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln('<gpx version="1.1" creator="Navigate App">');
    buffer.writeln('  <trk>');
    buffer.writeln('    <name>$name</name>');
    buffer.writeln('    <trkseg>');

    for (final point in _trackPoints) {
      buffer.writeln('      <trkpt lat="${point.coordinate.lat}" lon="${point.coordinate.lng}">');
      if (point.altitude != null) {
        buffer.writeln('        <ele>${point.altitude}</ele>');
      }
      buffer.writeln('        <time>${point.timestamp.toIso8601String()}</time>');
      buffer.writeln('      </trkpt>');
    }

    buffer.writeln('    </trkseg>');
    buffer.writeln('  </trk>');
    buffer.writeln('</gpx>');

    return buffer.toString();
  }

  /// ניקוי נתונים
  void clear() {
    _trackPoints.clear();
    _kalmanFilter.reset();
    _stepsSinceLastRecord = 0;
    _lastStepTime = null;
    _lastGpsFixTime = null;
    _jammingState = GpsJammingState.normal;
    _consecutiveBadGpsFixes = 0;
    _consecutiveGoodGpsFixes = 0;
    _manualCooldownEnd = null;
    _lastRawGpsLat = null;
    _lastRawGpsLng = null;
    _lastRawGpsTimestamp = null;
  }
}

/// נקודה במסלול
class TrackPoint {
  final Coordinate coordinate;
  final DateTime timestamp;
  final double accuracy;
  final double? altitude;
  final double? speed;
  final double? heading;
  final String positionSource;

  TrackPoint({
    required this.coordinate,
    required this.timestamp,
    required this.accuracy,
    this.altitude,
    this.speed,
    this.heading,
    this.positionSource = 'gps',
  });

  Map<String, dynamic> toMap() {
    return {
      'lat': coordinate.lat,
      'lng': coordinate.lng,
      'utm': coordinate.utm,
      'timestamp': timestamp.toIso8601String(),
      'accuracy': accuracy,
      if (altitude != null) 'altitude': altitude,
      if (speed != null) 'speed': speed,
      if (heading != null) 'heading': heading,
      'positionSource': positionSource,
    };
  }

  factory TrackPoint.fromMap(Map<String, dynamic> map) {
    return TrackPoint(
      coordinate: Coordinate(
        lat: map['lat'] as double,
        lng: map['lng'] as double,
        utm: map['utm'] as String,
      ),
      timestamp: DateTime.parse(map['timestamp'] as String),
      accuracy: map['accuracy'] as double,
      altitude: map['altitude'] as double?,
      speed: map['speed'] as double?,
      heading: map['heading'] as double?,
      positionSource: map['positionSource'] as String? ?? 'gps',
    );
  }
}
