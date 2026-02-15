import 'dart:math';
import '../../domain/entities/coordinate.dart';

/// פונקציות עזר לגאומטריה
class GeometryUtils {
  /// רדיוס כדור הארץ בקילומטרים
  static const double _earthRadiusKm = 6371.0;

  /// חישוב מרחק בין שתי קואורדינטות במטרים (נוסחת Haversine)
  static double distanceBetweenMeters(Coordinate from, Coordinate to) {
    final dLat = _toRadians(to.lat - from.lat);
    final dLng = _toRadians(to.lng - from.lng);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(from.lat)) *
            cos(_toRadians(to.lat)) *
            sin(dLng / 2) *
            sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return _earthRadiusKm * c * 1000; // המרה למטרים
  }

  /// חישוב כיוון (bearing) בין שתי קואורדינטות (0-360 מעלות, 0=צפון)
  static double bearingBetween(Coordinate from, Coordinate to) {
    final fromLatRad = _toRadians(from.lat);
    final toLatRad = _toRadians(to.lat);
    final dLngRad = _toRadians(to.lng - from.lng);

    final y = sin(dLngRad) * cos(toLatRad);
    final x = cos(fromLatRad) * sin(toLatRad) -
        sin(fromLatRad) * cos(toLatRad) * cos(dLngRad);

    final bearing = atan2(y, x);
    // המרה מרדיאנים למעלות ונרמול ל-0-360
    return (_toDegrees(bearing) + 360) % 360;
  }

  /// מרחק מינימלי (במטרים) מנקודה לקטע קו (segment).
  /// הקרנה אורתוגונלית עם clamp ל-[0,1], fallback לקצוות.
  static double distanceFromPointToSegmentMeters(
    Coordinate point,
    Coordinate segA,
    Coordinate segB,
  ) {
    // אם הקטע הוא נקודה אחת
    final dx = segB.lng - segA.lng;
    final dy = segB.lat - segA.lat;
    if (dx == 0 && dy == 0) {
      return distanceBetweenMeters(point, segA);
    }

    // פרמטר t על הקטע [0,1]
    final t = ((point.lng - segA.lng) * dx + (point.lat - segA.lat) * dy) /
        (dx * dx + dy * dy);
    final clamped = t.clamp(0.0, 1.0);

    final closest = Coordinate(
      lat: segA.lat + clamped * dy,
      lng: segA.lng + clamped * dx,
      utm: '',
    );

    return distanceBetweenMeters(point, closest);
  }

  /// חישוב אורך מסלול בקילומטרים (סכום מרחקים בין נקודות עוקבות)
  static double calculatePathLengthKm(List<Coordinate> path) {
    if (path.length < 2) return 0.0;

    double totalMeters = 0.0;
    for (int i = 0; i < path.length - 1; i++) {
      totalMeters += distanceBetweenMeters(path[i], path[i + 1]);
    }
    return totalMeters / 1000.0;
  }

  /// המרה ממעלות לרדיאנים
  static double _toRadians(double degrees) => degrees * pi / 180;

  /// המרה מרדיאנים למעלות
  static double _toDegrees(double radians) => radians * 180 / pi;

  /// בדיקה אם נקודה נמצאת בתוך פוליגון (Ray casting algorithm)
  static bool isPointInPolygon(Coordinate point, List<Coordinate> polygon) {
    if (polygon.length < 3) return false;

    int intersections = 0;
    final lat = point.lat;
    final lng = point.lng;

    for (int i = 0; i < polygon.length; i++) {
      final j = (i + 1) % polygon.length;
      final p1 = polygon[i];
      final p2 = polygon[j];

      if (((p1.lng > lng) != (p2.lng > lng)) &&
          (lat < (p2.lat - p1.lat) * (lng - p1.lng) / (p2.lng - p1.lng) + p1.lat)) {
        intersections++;
      }
    }

    return intersections % 2 == 1;
  }

  /// סינון רשימת נקודות - רק אלה שבתוך הפוליגון
  static List<T> filterPointsInPolygon<T>({
    required List<T> points,
    required Coordinate Function(T) getCoordinate,
    required List<Coordinate> polygon,
  }) {
    if (polygon.isEmpty) {
      // אם אין גבול, מחזירים הכל
      return points;
    }

    return points.where((point) {
      final coord = getCoordinate(point);
      return isPointInPolygon(coord, polygon);
    }).toList();
  }

  /// חישוב מרכז הפוליגון (centroid)
  static Coordinate getPolygonCenter(List<Coordinate> polygon) {
    if (polygon.isEmpty) {
      return Coordinate(lat: 0, lng: 0, utm: '');
    }

    double sumLat = 0;
    double sumLng = 0;

    for (final coord in polygon) {
      sumLat += coord.lat;
      sumLng += coord.lng;
    }

    return Coordinate(
      lat: sumLat / polygon.length,
      lng: sumLng / polygon.length,
      utm: '',
    );
  }

  /// בדיקה אם פוליגון חותך פוליגון אחר (polygon intersection)
  /// מחזיר true אם יש חפיפה כלשהי בין שני הפוליגונים
  static bool doPolygonsIntersect(
    List<Coordinate> polygon1,
    List<Coordinate> polygon2,
  ) {
    if (polygon1.length < 3 || polygon2.length < 3) return false;

    // בדיקה 1: האם קודקוד כלשהו של פוליגון 1 בתוך פוליגון 2
    for (final point in polygon1) {
      if (isPointInPolygon(point, polygon2)) return true;
    }

    // בדיקה 2: האם קודקוד כלשהו של פוליגון 2 בתוך פוליגון 1
    for (final point in polygon2) {
      if (isPointInPolygon(point, polygon1)) return true;
    }

    // בדיקה 3: האם צלעות חותכות (edge intersection)
    for (int i = 0; i < polygon1.length; i++) {
      final a1 = polygon1[i];
      final a2 = polygon1[(i + 1) % polygon1.length];

      for (int j = 0; j < polygon2.length; j++) {
        final b1 = polygon2[j];
        final b2 = polygon2[(j + 1) % polygon2.length];

        if (_doSegmentsIntersect(a1, a2, b1, b2)) return true;
      }
    }

    return false;
  }

  /// בדיקה אם שני קטעי קו חותכים
  static bool _doSegmentsIntersect(
    Coordinate p1, Coordinate p2,
    Coordinate p3, Coordinate p4,
  ) {
    final d1 = _crossProduct(p3, p4, p1);
    final d2 = _crossProduct(p3, p4, p2);
    final d3 = _crossProduct(p1, p2, p3);
    final d4 = _crossProduct(p1, p2, p4);

    if (((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
        ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))) {
      return true;
    }

    // נקודות על הקו
    if (d1 == 0 && _onSegment(p3, p4, p1)) return true;
    if (d2 == 0 && _onSegment(p3, p4, p2)) return true;
    if (d3 == 0 && _onSegment(p1, p2, p3)) return true;
    if (d4 == 0 && _onSegment(p1, p2, p4)) return true;

    return false;
  }

  /// Cross product helper
  static double _crossProduct(Coordinate a, Coordinate b, Coordinate c) {
    return (b.lat - a.lat) * (c.lng - a.lng) - (b.lng - a.lng) * (c.lat - a.lat);
  }

  /// בדיקה אם נקודה על קטע קו
  static bool _onSegment(Coordinate a, Coordinate b, Coordinate c) {
    return min(a.lat, b.lat) <= c.lat &&
        c.lat <= max(a.lat, b.lat) &&
        min(a.lng, b.lng) <= c.lng &&
        c.lng <= max(a.lng, b.lng);
  }

  /// בדיקה אם קטע קו נכנס לפוליגון או חותך את צלעותיו
  static bool doesSegmentIntersectPolygon(
    Coordinate segA,
    Coordinate segB,
    List<Coordinate> polygon,
  ) {
    if (polygon.length < 3) return false;

    // בדיקה 1: האם נקודת ההתחלה בתוך הפוליגון
    if (isPointInPolygon(segA, polygon)) return true;

    // בדיקה 2: האם צלעות הפוליגון חותכות את הקטע
    for (int i = 0; i < polygon.length; i++) {
      final j = (i + 1) % polygon.length;
      if (_doSegmentsIntersect(segA, segB, polygon[i], polygon[j])) return true;
    }

    return false;
  }

  /// סינון פוליגונים שחותכים פוליגון נתון
  static List<T> filterPolygonsIntersecting<T>({
    required List<T> polygons,
    required List<Coordinate> Function(T) getCoordinates,
    required List<Coordinate> boundary,
  }) {
    if (boundary.isEmpty) return polygons;

    return polygons.where((polygon) {
      final coords = getCoordinates(polygon);
      return doPolygonsIntersect(coords, boundary);
    }).toList();
  }

  /// חישוב bounding box של פוליגון
  static BoundingBox getBoundingBox(List<Coordinate> polygon) {
    if (polygon.isEmpty) {
      return BoundingBox(
        minLat: 0,
        maxLat: 0,
        minLng: 0,
        maxLng: 0,
      );
    }

    double minLat = polygon.first.lat;
    double maxLat = polygon.first.lat;
    double minLng = polygon.first.lng;
    double maxLng = polygon.first.lng;

    for (final coord in polygon) {
      if (coord.lat < minLat) minLat = coord.lat;
      if (coord.lat > maxLat) maxLat = coord.lat;
      if (coord.lng < minLng) minLng = coord.lng;
      if (coord.lng > maxLng) maxLng = coord.lng;
    }

    return BoundingBox(
      minLat: minLat,
      maxLat: maxLat,
      minLng: minLng,
      maxLng: maxLng,
    );
  }
}

/// Bounding box של פוליגון
class BoundingBox {
  final double minLat;
  final double maxLat;
  final double minLng;
  final double maxLng;

  BoundingBox({
    required this.minLat,
    required this.maxLat,
    required this.minLng,
    required this.maxLng,
  });

  /// מרכז ה-bounding box
  Coordinate get center => Coordinate(
        lat: (minLat + maxLat) / 2,
        lng: (minLng + maxLng) / 2,
        utm: '',
      );

  /// רדיוס ה-bounding box בקירוב (במעלות)
  double get radius {
    final latRange = maxLat - minLat;
    final lngRange = maxLng - minLng;
    return (latRange > lngRange ? latRange : lngRange) / 2;
  }
}

/// המרת קואורדינטות ל-UTM
class UTMConverter {
  /// המרת lat/lng ל-UTM (קירוב פשוט לישראל)
  static String convertToUTM(double lat, double lng) {
    // ישראל נמצאת באזור 36N
    const zone = 36;
    const hemisphere = 'R'; // R = Northern hemisphere (0-80°N)

    // חישוב easting ו-northing (קירוב)
    // זה קירוב פשוט - לא מדויק לחלוטין אבל מספיק טוב
    final centralMeridian = (zone - 1) * 6 - 180 + 3; // 33° for zone 36
    final deltaLng = lng - centralMeridian;

    // קירוב פשוט
    final latRadians = lat * pi / 180;
    final easting = (500000 + (deltaLng * 111320 * cos(latRadians))).toInt();
    final northing = (lat * 110540).toInt();

    return '$zone$hemisphere $easting $northing';
  }
}

