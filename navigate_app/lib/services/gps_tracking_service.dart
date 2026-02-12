import 'dart:async';
import 'package:geolocator/geolocator.dart';
import '../domain/entities/coordinate.dart';

/// שירות מעקב GPS
class GPSTrackingService {
  Timer? _trackingTimer;
  StreamController<Position>? _positionStream;
  List<TrackPoint> _trackPoints = [];

  bool _isTracking = false;
  bool get isTracking => _isTracking;

  int _intervalSeconds = 30;
  int get intervalSeconds => _intervalSeconds;

  /// Stream של מיקומים
  Stream<Position> get positionStream =>
      _positionStream?.stream ?? const Stream.empty();

  /// נקודות המסלול שנאספו
  List<TrackPoint> get trackPoints => List.unmodifiable(_trackPoints);

  /// התחלת מעקב GPS
  Future<bool> startTracking({int intervalSeconds = 30}) async {
    if (_isTracking) {
      print('⚠️ GPS Tracking כבר פעיל');
      return false;
    }

    _intervalSeconds = intervalSeconds;

    // בדיקת הרשאות
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        print('❌ הרשאות GPS נדחו');
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      print('❌ הרשאות GPS נדחו לצמיתות');
      return false;
    }

    // בדיקה ש-GPS מופעל
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      print('❌ GPS כבוי');
      return false;
    }

    _positionStream = StreamController<Position>.broadcast();
    _trackPoints = [];
    _isTracking = true;

    // רישום נקודה ראשונה
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _recordPoint(position);
      print('📍 GPS Tracking התחיל - מיקום ראשוני: ${position.latitude}, ${position.longitude}');
    } catch (e) {
      print('❌ שגיאה בקבלת מיקום ראשוני: $e');
    }

    // Timer לרישום מיקום כל X שניות
    _trackingTimer = Timer.periodic(
      Duration(seconds: _intervalSeconds),
      (timer) => _recordCurrentPosition(),
    );

    print('✓ GPS Tracking פעיל - רישום כל $_intervalSeconds שניות');
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

    print('🛑 GPS Tracking הופסק - נרשמו ${_trackPoints.length} נקודות');
  }

  /// רישום מיקום נוכחי
  Future<void> _recordCurrentPosition() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _recordPoint(position);
      _positionStream?.add(position);
    } catch (e) {
      print('❌ שגיאה ברישום מיקום: $e');
    }
  }

  /// רישום נקודה
  void _recordPoint(Position position) {
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
    );

    _trackPoints.add(point);
    print('📍 רישום נקודה ${_trackPoints.length}: ${point.coordinate.lat}, ${point.coordinate.lng}');
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

  TrackPoint({
    required this.coordinate,
    required this.timestamp,
    required this.accuracy,
    this.altitude,
    this.speed,
    this.heading,
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
    );
  }
}
