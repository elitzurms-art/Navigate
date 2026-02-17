import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:gps_plus/gps_plus.dart';

/// מקור מיקום אחרון
enum PositionSource { gps, cellTower, none }

/// שירות GPS ומיקום — עם fallback לאנטנות סלולריות דרך gps_plus
class GpsService {
  StreamSubscription<Position>? _positionSubscription;

  /// מקור המיקום האחרון שהתקבל
  PositionSource _lastPositionSource = PositionSource.none;
  PositionSource get lastPositionSource => _lastPositionSource;

  // Cell tower fallback
  CellLocationService? _cellService;
  bool _cellInitialized = false;

  /// סף דיוק (במטרים) — מתחתיו GPS מספיק טוב, מעליו מנסה fallback
  static const double _accuracyThreshold = 50.0;

  /// OpenCellID API key (free tier)
  static const String _openCellIdApiKey = 'pk.2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d';

  /// סף מרחק ממרכז הג"ג — מעל 50 ק"מ = GPS חסום/מזויף
  static const double _maxDistanceFromBoundary = 50000.0; // 50 km in meters

  /// אתחול שירות אנטנות (נקרא פעם אחת, lazy)
  Future<void> _ensureCellServiceInitialized() async {
    if (_cellInitialized) return;
    try {
      _cellService = CellLocationService();
      await _cellService!.initialize();
      _cellInitialized = true;
      // Verify tower data is available (bundled asset should already be copied)
      ensureTowerData();
    } catch (e) {
      print('DEBUG GpsService: cell service init failed: $e');
      _cellService = null;
    }
  }

  /// בדיקה שיש נתוני אנטנות — asset מובנה צריך להספיק, מציג אזהרה אם חסר
  Future<void> ensureTowerData() async {
    try {
      await _ensureCellServiceInitialized();
      if (_cellService == null) return;

      final count = await _cellService!.towerCount(mcc: 425);
      if (count > 0) {
        print('DEBUG GpsService: tower data exists ($count towers for MCC 425)');
      } else {
        print('WARNING GpsService: no tower data for MCC 425 — bundled asset may have failed to copy');
      }
    } catch (e) {
      print('DEBUG GpsService: ensureTowerData failed: $e');
    }
  }

  /// בדיקת הרשאות מיקום
  Future<bool> checkPermissions() async {
    bool serviceEnabled;
    LocationPermission permission;

    // בדיקה אם שירותי מיקום מופעלים
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    // בדיקת הרשאות
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  /// קבלת מיקום נוכחי — עם fallback לאנטנות
  ///
  /// [forceSource]: 'auto' = ברירת מחדל, 'cellTower' = אנטנות בלבד, 'gps' = GPS בלבד
  Future<LatLng?> getCurrentPosition({
    bool highAccuracy = true,
    LatLng? boundaryCenter,
    String forceSource = 'auto',
  }) async {
    // כפיית אנטנות — דלג על GPS לחלוטין
    if (forceSource == 'cellTower') {
      final cellResult = await _getCellPosition();
      if (cellResult != null) {
        _lastPositionSource = PositionSource.cellTower;
        return cellResult.latLng;
      }
      _lastPositionSource = PositionSource.none;
      return null;
    }

    try {
      final hasPermission = await checkPermissions();
      if (!hasPermission) {
        // אין הרשאות GPS — נסה אנטנות (אלא אם כפוי GPS בלבד)
        if (forceSource == 'gps') {
          _lastPositionSource = PositionSource.none;
          return null;
        }
        print('DEBUG GpsService: no GPS permission, trying cell fallback');
        final cellResult = await _getCellPosition();
        if (cellResult != null) {
          _lastPositionSource = PositionSource.cellTower;
          return cellResult.latLng;
        }
        _lastPositionSource = PositionSource.none;
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: highAccuracy
            ? LocationAccuracy.high
            : LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 10),
      );
      print('DEBUG GpsService: GPS position: ${position.latitude}, ${position.longitude} accuracy=${position.accuracy.toStringAsFixed(0)}m');

      final gpsLatLng = LatLng(position.latitude, position.longitude);

      // כפיית GPS — אין fallback
      if (forceSource == 'gps') {
        _lastPositionSource = PositionSource.gps;
        return gpsLatLng;
      }

      // בדיקת GPS חסום/מזויף — מרחק ממרכז הג"ג
      if (boundaryCenter != null) {
        final distanceFromBoundary = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          boundaryCenter.latitude,
          boundaryCenter.longitude,
        );

        if (distanceFromBoundary > _maxDistanceFromBoundary) {
          print('DEBUG GpsService: GPS likely spoofed/blocked! '
              'Distance from boundary center: ${(distanceFromBoundary / 1000).toStringAsFixed(1)} km');
          final cellResult = await _getCellPosition();
          if (cellResult != null) {
            _lastPositionSource = PositionSource.cellTower;
            return cellResult.latLng;
          }
          // Even if cell fails, still return GPS — better than nothing
          _lastPositionSource = PositionSource.gps;
          return gpsLatLng;
        }
      }

      // אם הדיוק נמוך, נסה fallback
      if (position.accuracy > _accuracyThreshold) {
        final cellResult = await _getCellPosition();
        if (cellResult != null && cellResult.accuracyMeters < position.accuracy) {
          print('DEBUG GpsService: GPS accuracy ${position.accuracy.toStringAsFixed(0)}m > threshold, '
              'cell accuracy ${cellResult.accuracyMeters.toStringAsFixed(0)}m is better — using cell fallback');
          _lastPositionSource = PositionSource.cellTower;
          return cellResult.latLng;
        }
      }

      _lastPositionSource = PositionSource.gps;
      return gpsLatLng;
    } catch (e) {
      // GPS נכשל לחלוטין — נסה אנטנות (אלא אם כפוי GPS בלבד)
      if (forceSource == 'gps') {
        _lastPositionSource = PositionSource.none;
        return null;
      }
      print('DEBUG GpsService: GPS failed ($e), trying cell fallback');
      final cellResult = await _getCellPosition();
      if (cellResult != null) {
        _lastPositionSource = PositionSource.cellTower;
        return cellResult.latLng;
      }
      _lastPositionSource = PositionSource.none;
      return null;
    }
  }

  /// קבלת מיקום עם פרטי דיוק מלאים
  ///
  /// [forceSource]: 'auto' = ברירת מחדל, 'cellTower' = אנטנות בלבד, 'gps' = GPS בלבד
  Future<({LatLng position, double accuracy, PositionSource source})?> getCurrentPositionWithAccuracy({
    bool highAccuracy = true,
    LatLng? boundaryCenter,
    String forceSource = 'auto',
  }) async {
    // כפיית אנטנות
    if (forceSource == 'cellTower') {
      final cellResult = await _getCellPosition();
      if (cellResult != null) {
        return (position: cellResult.latLng, accuracy: cellResult.accuracyMeters, source: PositionSource.cellTower);
      }
      return null;
    }

    try {
      final hasPermission = await checkPermissions();
      if (!hasPermission) {
        if (forceSource == 'gps') return null;
        final cellResult = await _getCellPosition();
        if (cellResult != null) {
          return (position: cellResult.latLng, accuracy: cellResult.accuracyMeters, source: PositionSource.cellTower);
        }
        return null;
      }

      final gpsPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: highAccuracy ? LocationAccuracy.high : LocationAccuracy.medium,
      );

      final gpsLatLng = LatLng(gpsPosition.latitude, gpsPosition.longitude);

      // כפיית GPS — אין fallback
      if (forceSource == 'gps') {
        return (position: gpsLatLng, accuracy: gpsPosition.accuracy, source: PositionSource.gps);
      }

      // בדיקת GPS חסום/מזויף
      if (boundaryCenter != null) {
        final dist = Geolocator.distanceBetween(
          gpsPosition.latitude, gpsPosition.longitude,
          boundaryCenter.latitude, boundaryCenter.longitude,
        );
        if (dist > _maxDistanceFromBoundary) {
          final cellResult = await _getCellPosition();
          if (cellResult != null) {
            return (position: cellResult.latLng, accuracy: cellResult.accuracyMeters, source: PositionSource.cellTower);
          }
          return (position: gpsLatLng, accuracy: gpsPosition.accuracy, source: PositionSource.gps);
        }
      }

      // השוואת דיוק
      if (gpsPosition.accuracy > _accuracyThreshold) {
        final cellResult = await _getCellPosition();
        if (cellResult != null && cellResult.accuracyMeters < gpsPosition.accuracy) {
          return (position: cellResult.latLng, accuracy: cellResult.accuracyMeters, source: PositionSource.cellTower);
        }
      }

      return (position: gpsLatLng, accuracy: gpsPosition.accuracy, source: PositionSource.gps);
    } catch (e) {
      if (forceSource == 'gps') return null;
      final cellResult = await _getCellPosition();
      if (cellResult != null) {
        return (position: cellResult.latLng, accuracy: cellResult.accuracyMeters, source: PositionSource.cellTower);
      }
      return null;
    }
  }

  /// קבלת מיקום מאנטנות סלולריות — מחזיר תוצאה מלאה
  Future<CellPositionResult?> _getCellPosition() async {
    try {
      await _ensureCellServiceInitialized();
      if (_cellService == null) {
        print('DEBUG GpsService: cell service is null after init');
        return null;
      }

      final towerCount = await _cellService!.towerCount();
      print('DEBUG GpsService: cell tower DB has $towerCount towers');

      final result = await _cellService!.calculatePosition();
      if (result != null) {
        print('DEBUG GpsService: cell position: ${result.lat}, ${result.lon} ± ${result.accuracyMeters.toStringAsFixed(0)}m (${result.towerCount} towers)');
      }
      return result;
    } catch (e) {
      print('DEBUG GpsService: cell position failed: $e');
      return null;
    }
  }

  /// מעקב אחר שינויי מיקום
  ///
  /// [onPositionChanged] - callback שיופעל בכל שינוי מיקום
  /// [intervalSeconds] - מרווח זמן בשניות בין עדכונים
  /// [highAccuracy] - דיוק גבוה או בינוני
  Future<void> startLocationTracking({
    required Function(LatLng, double) onPositionChanged,
    int intervalSeconds = 30,
    bool highAccuracy = false,
  }) async {
    final hasPermission = await checkPermissions();
    if (!hasPermission) {
      throw Exception('אין הרשאות מיקום');
    }

    final locationSettings = LocationSettings(
      accuracy: highAccuracy
          ? LocationAccuracy.high
          : LocationAccuracy.medium,
      distanceFilter: 10, // מטרים - מרחק מינימלי לעדכון
      timeLimit: Duration(seconds: intervalSeconds),
    );

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) {
      final latLng = LatLng(position.latitude, position.longitude);
      final accuracy = position.accuracy;
      onPositionChanged(latLng, accuracy);
    });
  }

  /// עצירת מעקב מיקום
  Future<void> stopLocationTracking() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  /// חישוב מרחק בין שתי נקודות (במטרים)
  double calculateDistance(LatLng point1, LatLng point2) {
    return Geolocator.distanceBetween(
      point1.latitude,
      point1.longitude,
      point2.latitude,
      point2.longitude,
    );
  }

  /// בדיקה אם נקודה נמצאת בתוך פוליגון
  bool isPointInPolygon(LatLng point, List<LatLng> polygon) {
    int intersectCount = 0;
    for (int i = 0; i < polygon.length; i++) {
      final vertex1 = polygon[i];
      final vertex2 = polygon[(i + 1) % polygon.length];

      if (_rayCrossesSegment(point, vertex1, vertex2)) {
        intersectCount++;
      }
    }

    return (intersectCount % 2) == 1;
  }

  /// בדיקה אם קרן אופקית מנקודה חוצה קטע
  bool _rayCrossesSegment(LatLng point, LatLng a, LatLng b) {
    final px = point.longitude;
    final py = point.latitude;
    final ax = a.longitude;
    final ay = a.latitude;
    final bx = b.longitude;
    final by = b.latitude;

    if (ay > by) {
      // החלף a ו-b
      final tempX = ax;
      final tempY = ay;
      final ax2 = bx;
      final ay2 = by;
      final bx2 = tempX;
      final by2 = tempY;

      return _rayCrossesSegmentHelper(px, py, ax2, ay2, bx2, by2);
    }

    return _rayCrossesSegmentHelper(px, py, ax, ay, bx, by);
  }

  bool _rayCrossesSegmentHelper(
    double px, double py,
    double ax, double ay,
    double bx, double by,
  ) {
    if (py == ay || py == by) {
      py += 0.00000001;
    }

    if (py < ay || py > by) {
      return false;
    }

    if (px >= (ax > bx ? ax : bx)) {
      return false;
    }

    if (px < (ax < bx ? ax : bx)) {
      return true;
    }

    final red = (ax != bx)
        ? ((by - ay) / (bx - ax))
        : double.infinity;
    final blue = (ax != px)
        ? ((py - ay) / (px - ax))
        : double.infinity;

    return blue >= red;
  }

  /// קבלת רמת הדיוק הנוכחית
  Future<double> getCurrentAccuracy() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      return position.accuracy;
    } catch (e) {
      return -1;
    }
  }

  /// בדיקת זמינות GPS
  Future<bool> isGpsAvailable() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  /// פתיחת הגדרות מיקום
  Future<bool> openLocationSettings() async {
    return await Geolocator.openLocationSettings();
  }

  /// מספר אנטנות במסד הנתונים המקומי
  Future<int> getCellTowerCount({int? mcc}) async {
    try {
      await _ensureCellServiceInitialized();
      if (_cellService == null) return 0;
      return await _cellService!.towerCount(mcc: mcc);
    } catch (_) {
      return 0;
    }
  }

  /// הורדת נתוני אנטנות לפי MCC (קוד מדינה) — לרענון ידני
  Future<int> downloadCellTowerData({
    required String apiKey,
    required int mcc,
    void Function(int downloaded, int total)? onProgress,
  }) async {
    await _ensureCellServiceInitialized();
    if (_cellService == null) {
      throw StateError('Cell location service not available');
    }
    return await _cellService!.downloadTowerData(
      apiKey: apiKey,
      mcc: mcc,
      onProgress: onProgress,
    );
  }

  /// ניקוי משאבים
  Future<void> dispose() async {
    await stopLocationTracking();
    if (_cellService != null) {
      await _cellService!.dispose();
      _cellService = null;
      _cellInitialized = false;
    }
  }
}
