import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../domain/entities/coordinate.dart';
import 'gps_service.dart';

/// שירות מעקב GPS
class GPSTrackingService {
  Timer? _trackingTimer;
  StreamController<Position>? _positionStream;
  List<TrackPoint> _trackPoints = [];
  final GpsService _gpsService = GpsService();

  bool _isTracking = false;
  bool get isTracking => _isTracking;

  int _intervalSeconds = 30;
  LatLng? _boundaryCenter;
  int get intervalSeconds => _intervalSeconds;

  /// מקור מיקום כפוי — 'auto' (ברירת מחדל), 'cellTower', 'gps'
  String _forcePositionSource = 'auto';
  String get forcePositionSource => _forcePositionSource;
  set forcePositionSource(String value) {
    _forcePositionSource = value;
    print('DEBUG GPSTrackingService: forcePositionSource set to: $value');
  }

  /// Stream של מיקומים
  Stream<Position> get positionStream =>
      _positionStream?.stream ?? const Stream.empty();

  /// נקודות המסלול שנאספו
  List<TrackPoint> get trackPoints => List.unmodifiable(_trackPoints);

  /// התחלת מעקב GPS
  Future<bool> startTracking({
    int intervalSeconds = 30,
    LatLng? boundaryCenter,
    String forcePositionSource = 'auto',
  }) async {
    if (_isTracking) {
      print('GPS Tracking כבר פעיל');
      return false;
    }

    _intervalSeconds = intervalSeconds;
    _boundaryCenter = boundaryCenter;
    _forcePositionSource = forcePositionSource;

    // כפיית אנטנות — לא צריך הרשאות GPS
    if (_forcePositionSource == 'cellTower') {
      _positionStream = StreamController<Position>.broadcast();
      _trackPoints = [];
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
      print('GPS לא זמין — ממשיך עם fallback אנטנות');
    }

    _positionStream = StreamController<Position>.broadcast();
    _trackPoints = [];
    _isTracking = true;

    // רישום נקודה ראשונה
    try {
      if (gpsAvailable) {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10),
        );

        // אם הדיוק נמוך, נסה fallback דרך GPS Plus (אנטנות סלולריות)
        if (position.accuracy > 50 && _forcePositionSource != 'gps') {
          final cellPos = await _gpsService.getCurrentPosition(
            boundaryCenter: _boundaryCenter,
            forceSource: _forcePositionSource,
          );
          if (cellPos != null &&
              _gpsService.lastPositionSource == PositionSource.cellTower) {
            _recordPointFromLatLng(
              cellPos.latitude,
              cellPos.longitude,
              position.accuracy,
              positionSource: 'cellTower',
            );
            print('GPS Tracking התחיל - מיקום ראשוני (cellTower): ${cellPos.latitude}, ${cellPos.longitude}');
          } else {
            _recordPoint(position, positionSource: 'gps');
            print('GPS Tracking התחיל - מיקום ראשוני: ${position.latitude}, ${position.longitude}');
          }
        } else {
          _recordPoint(position, positionSource: 'gps');
          print('GPS Tracking התחיל - מיקום ראשוני: ${position.latitude}, ${position.longitude}');
        }
      } else {
        // GPS לא זמין — נסה אנטנות
        final cellPos = await _gpsService.getCurrentPosition(
          boundaryCenter: _boundaryCenter,
          forceSource: _forcePositionSource,
        );
        if (cellPos != null) {
          _recordPointFromLatLng(
            cellPos.latitude,
            cellPos.longitude,
            -1,
            positionSource: _gpsService.lastPositionSource == PositionSource.cellTower
                ? 'cellTower'
                : 'gps',
          );
          print('GPS Tracking התחיל - מיקום ראשוני (fallback): ${cellPos.latitude}, ${cellPos.longitude}');
        } else {
          print('GPS Tracking התחיל ללא מיקום ראשוני');
        }
      }
    } catch (e) {
      print('שגיאה בקבלת מיקום ראשוני: $e');
      // נסה fallback אנטנות
      try {
        final cellPos = await _gpsService.getCurrentPosition(
          boundaryCenter: _boundaryCenter,
          forceSource: _forcePositionSource,
        );
        if (cellPos != null) {
          _recordPointFromLatLng(cellPos.latitude, cellPos.longitude, -1,
            positionSource: 'cellTower');
          print('מיקום ראשוני מ-fallback: ${cellPos.latitude}, ${cellPos.longitude}');
        }
      } catch (_) {}
    }

    // Timer לרישום מיקום כל X שניות
    _trackingTimer = Timer.periodic(
      Duration(seconds: _intervalSeconds),
      (timer) => _recordCurrentPosition(),
    );

    print('GPS Tracking פעיל - רישום כל $_intervalSeconds שניות');
    return true;
  }

  /// עצירת מעקב GPS
  Future<void> stopTracking() async {
    if (!_isTracking) return;

    _trackingTimer?.cancel();
    _trackingTimer = null;

    await _positionStream?.close();
    _positionStream = null;

    _isTracking = false;

    print('GPS Tracking הופסק - נרשמו ${_trackPoints.length} נקודות');
  }

  /// רישום מיקום נוכחי
  Future<void> _recordCurrentPosition() async {
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

    // בדיקה מהירה: אם GPS לא זמין, ישר ל-fallback אנטנות
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
      try {
        final cellPos = await _gpsService.getCurrentPosition(
          boundaryCenter: _boundaryCenter,
          forceSource: _forcePositionSource,
        );
        if (cellPos != null) {
          _recordPointFromLatLng(
            cellPos.latitude,
            cellPos.longitude,
            -1,
            positionSource: _gpsService.lastPositionSource == PositionSource.cellTower
                ? 'cellTower'
                : 'gps',
          );
        }
      } catch (e) {
        print('fallback אנטנות נכשל: $e');
      }
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      // כפיית GPS — אין fallback
      if (_forcePositionSource == 'gps') {
        _recordPoint(position, positionSource: 'gps');
        _positionStream?.add(position);
        return;
      }

      // בדיקת GPS חסום/מזויף — מרחק ממרכז הג"ג
      if (_boundaryCenter != null) {
        final dist = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          _boundaryCenter!.latitude,
          _boundaryCenter!.longitude,
        );
        if (dist > 50000) {
          // GPS likely spoofed — try cell towers
          final cellPos = await _gpsService.getCurrentPosition(boundaryCenter: _boundaryCenter);
          if (cellPos != null &&
              _gpsService.lastPositionSource == PositionSource.cellTower) {
            _recordPointFromLatLng(
              cellPos.latitude,
              cellPos.longitude,
              position.accuracy,
              positionSource: 'cellTower',
            );
            _positionStream?.add(position);
            return;
          }
        }
      }

      // אם הדיוק נמוך (> 50 מטר), נסה fallback דרך GPS Plus
      if (position.accuracy > 50) {
        final cellPos = await _gpsService.getCurrentPosition(boundaryCenter: _boundaryCenter);
        if (cellPos != null &&
            _gpsService.lastPositionSource == PositionSource.cellTower) {
          _recordPointFromLatLng(
            cellPos.latitude,
            cellPos.longitude,
            position.accuracy,
            positionSource: 'cellTower',
          );
          _positionStream?.add(position);
          return;
        }
      }

      _recordPoint(position, positionSource: 'gps');
      _positionStream?.add(position);
    } catch (e) {
      // GPS failed completely — try cell tower fallback
      if (_forcePositionSource == 'gps') return;
      print('שגיאה ברישום מיקום: $e — מנסה fallback אנטנות');
      try {
        final cellPos = await _gpsService.getCurrentPosition(boundaryCenter: _boundaryCenter);
        if (cellPos != null) {
          _recordPointFromLatLng(
            cellPos.latitude,
            cellPos.longitude,
            -1,
            positionSource: _gpsService.lastPositionSource == PositionSource.cellTower
                ? 'cellTower'
                : 'gps',
          );
        }
      } catch (_) {
        print('גם fallback אנטנות נכשל');
      }
    }
  }

  /// רישום נקודה מ-Position (Geolocator)
  void _recordPoint(Position position, {String positionSource = 'gps'}) {
    final point = TrackPoint(
      coordinate: Coordinate(
        lat: position.latitude,
        lng: position.longitude,
        utm: _convertToUTM(position.latitude, position.longitude),
      ),
      timestamp: DateTime.now(),
      accuracy: position.accuracy,
      altitude: position.altitude,
      speed: position.speed,
      heading: position.heading,
      positionSource: positionSource,
    );

    _trackPoints.add(point);
    print('רישום נקודה ${_trackPoints.length}: ${point.coordinate.lat}, ${point.coordinate.lng} [$positionSource]');
  }

  /// רישום נקודה מ-LatLng (GPS Plus fallback)
  void _recordPointFromLatLng(
    double lat,
    double lng,
    double accuracy, {
    String positionSource = 'cellTower',
  }) {
    final point = TrackPoint(
      coordinate: Coordinate(
        lat: lat,
        lng: lng,
        utm: _convertToUTM(lat, lng),
      ),
      timestamp: DateTime.now(),
      accuracy: accuracy,
      positionSource: positionSource,
    );

    _trackPoints.add(point);
    print('רישום נקודה ${_trackPoints.length}: ${point.coordinate.lat}, ${point.coordinate.lng} [$positionSource]');
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
      total += Geolocator.distanceBetween(
        _trackPoints[i].coordinate.lat,
        _trackPoints[i].coordinate.lng,
        _trackPoints[i + 1].coordinate.lat,
        _trackPoints[i + 1].coordinate.lng,
      );
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
