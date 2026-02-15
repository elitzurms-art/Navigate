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

  /// אתחול שירות אנטנות (נקרא פעם אחת, lazy)
  Future<void> _ensureCellServiceInitialized() async {
    if (_cellInitialized) return;
    try {
      _cellService = CellLocationService();
      await _cellService!.initialize();
      _cellInitialized = true;
    } catch (e) {
      print('DEBUG GpsService: cell service init failed: $e');
      _cellService = null;
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
  Future<LatLng?> getCurrentPosition({
    bool highAccuracy = true,
  }) async {
    try {
      final hasPermission = await checkPermissions();
      if (!hasPermission) {
        // אין הרשאות GPS — נסה אנטנות
        final cellPos = await _getCellPosition();
        if (cellPos != null) {
          _lastPositionSource = PositionSource.cellTower;
          return cellPos;
        }
        _lastPositionSource = PositionSource.none;
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: highAccuracy
            ? LocationAccuracy.high
            : LocationAccuracy.medium,
      );

      // אם הדיוק נמוך, נסה fallback
      if (position.accuracy > _accuracyThreshold) {
        final cellPos = await _getCellPosition();
        if (cellPos != null) {
          print('DEBUG GpsService: GPS accuracy ${position.accuracy.toStringAsFixed(0)}m > threshold, using cell fallback');
          _lastPositionSource = PositionSource.cellTower;
          return cellPos;
        }
      }

      _lastPositionSource = PositionSource.gps;
      return LatLng(position.latitude, position.longitude);
    } catch (e) {
      // GPS נכשל לחלוטין — נסה אנטנות
      print('DEBUG GpsService: GPS failed ($e), trying cell fallback');
      final cellPos = await _getCellPosition();
      if (cellPos != null) {
        _lastPositionSource = PositionSource.cellTower;
        return cellPos;
      }
      _lastPositionSource = PositionSource.none;
      return null;
    }
  }

  /// קבלת מיקום מאנטנות סלולריות
  Future<LatLng?> _getCellPosition() async {
    try {
      await _ensureCellServiceInitialized();
      if (_cellService == null) return null;

      final result = await _cellService!.calculatePosition();
      if (result != null) {
        print('DEBUG GpsService: cell position: ${result.lat}, ${result.lon} ± ${result.accuracyMeters.toStringAsFixed(0)}m (${result.towerCount} towers)');
        return result.latLng;
      }
      return null;
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

  /// הורדת נתוני אנטנות לפי MCC (קוד מדינה)
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
