import 'dart:math';

import 'package:polybool/polybool.dart' as pb;

import '../../domain/entities/coordinate.dart';

/// פעולות פוליגון מבוססות polybool — union, intersection, corridor
class PolygonOperations {
  /// רדיוס כדור הארץ במטרים
  static const double _earthRadiusMeters = 6371000.0;

  // ---------------------------------------------------------------------------
  // Internal helpers — polybool conversion
  // ---------------------------------------------------------------------------

  /// המרת List<Coordinate> ל-polybool region (List<Coordinate> של polybool)
  static List<pb.Coordinate> _toPolyBoolRegion(List<Coordinate> coords) {
    return coords.map((c) => pb.Coordinate(c.lng, c.lat)).toList();
  }

  /// המרת polybool region ל-List<Coordinate>
  static List<Coordinate> _fromPolyBoolRegion(List<pb.Coordinate> region) {
    return region
        .map((c) => Coordinate(lat: c.y, lng: c.x, utm: ''))
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// איחוד (union) של מספר פוליגונים.
  /// מחזיר רשימת פוליגוני תוצאה:
  ///   - פוליגון אחד אם כולם חופפים (union הצליח)
  ///   - מספר פוליגונים אם חלקם לא חופפים (MultiPolygon)
  /// מחזיר רשימה ריקה אם הקלט ריק או לא חוקי.
  static List<List<Coordinate>> unionPolygons(List<List<Coordinate>> polygons) {
    if (polygons.isEmpty) return [];

    // סינון פוליגונים עם פחות מ-3 נקודות
    final valid = polygons.where((p) => p.length >= 3).toList();
    if (valid.isEmpty) return [];
    if (valid.length == 1) return [valid.first];

    // Union iteratively: start with first, union each subsequent polygon
    var result = pb.Polygon(regions: [_toPolyBoolRegion(valid.first)]);

    for (int i = 1; i < valid.length; i++) {
      final next = pb.Polygon(regions: [_toPolyBoolRegion(valid[i])]);
      result = result.union(next);
    }

    // המרת תוצאה חזרה
    if (result.regions.isEmpty) return [];
    return result.regions
        .where((r) => r.length >= 3)
        .map((r) => _fromPolyBoolRegion(r))
        .toList();
  }

  /// בדיקה אם שני פוליגונים חופפים (יש להם שטח משותף)
  static bool doPolygonsOverlap(List<Coordinate> a, List<Coordinate> b) {
    if (a.length < 3 || b.length < 3) return false;

    final polyA = pb.Polygon(regions: [_toPolyBoolRegion(a)]);
    final polyB = pb.Polygon(regions: [_toPolyBoolRegion(b)]);

    final intersection = polyA.intersect(polyB);
    return intersection.regions.isNotEmpty;
  }

  /// מציאת הנקודות הקרובות ביותר בין שני פוליגונים (לציור מסדרון)
  /// בודק את כל זוגות הקודקודים + הטלות על צלעות.
  static ({Coordinate a, Coordinate b}) findClosestPoints(
    List<Coordinate> polyA,
    List<Coordinate> polyB,
  ) {
    if (polyA.isEmpty || polyB.isEmpty) {
      throw ArgumentError('הפוליגונים חייבים להכיל לפחות נקודה אחת');
    }

    double minDist = double.infinity;
    Coordinate bestA = polyA.first;
    Coordinate bestB = polyB.first;

    // בדיקת כל זוגות הקודקודים
    for (final pa in polyA) {
      for (final pb in polyB) {
        final d = _haversineDistance(pa, pb);
        if (d < minDist) {
          minDist = d;
          bestA = pa;
          bestB = pb;
        }
      }
    }

    // בדיקת הטלת קודקודי A על צלעות B
    for (final pa in polyA) {
      for (int i = 0; i < polyB.length; i++) {
        final j = (i + 1) % polyB.length;
        final projected = _projectPointOnSegment(pa, polyB[i], polyB[j]);
        final d = _haversineDistance(pa, projected);
        if (d < minDist) {
          minDist = d;
          bestA = pa;
          bestB = projected;
        }
      }
    }

    // בדיקת הטלת קודקודי B על צלעות A
    for (final pbi in polyB) {
      for (int i = 0; i < polyA.length; i++) {
        final j = (i + 1) % polyA.length;
        final projected = _projectPointOnSegment(pbi, polyA[i], polyA[j]);
        final d = _haversineDistance(pbi, projected);
        if (d < minDist) {
          minDist = d;
          bestA = projected;
          bestB = pbi;
        }
      }
    }

    return (a: bestA, b: bestB);
  }

  /// יצירת מסדרון (פוליגון מלבני) בין שתי נקודות ברוחב נתון.
  /// כולל buffer של 5 מטר מכל צד.
  /// [lengthExtensionMeters] — הארכת המסדרון מעבר לנקודות (מכל צד), ברירת מחדל 0.
  static List<Coordinate> createCorridor(
    Coordinate from,
    Coordinate to,
    double widthMeters, {
    double lengthExtensionMeters = 0,
  }) {
    // כיוון מ-from ל-to
    final bearing = _bearingBetween(from, to);
    final reverseBearing = (bearing + 180) % 360;

    // הארכת נקודות ההתחלה והסוף אם יש extension
    final effectiveFrom = lengthExtensionMeters > 0
        ? _offsetPoint(from, reverseBearing, lengthExtensionMeters)
        : from;
    final effectiveTo = lengthExtensionMeters > 0
        ? _offsetPoint(to, bearing, lengthExtensionMeters)
        : to;

    // כיוונים ניצבים (±90°)
    final perpLeft = (bearing + 90) % 360;
    final perpRight = (bearing - 90 + 360) % 360;

    // מרחק הזזה — חצי רוחב + 5 מטר buffer
    final offset = widthMeters / 2 + 5;

    // 4 פינות המסדרון
    final corner1 = _offsetPoint(effectiveFrom, perpLeft, offset);
    final corner2 = _offsetPoint(effectiveFrom, perpRight, offset);
    final corner3 = _offsetPoint(effectiveTo, perpRight, offset);
    final corner4 = _offsetPoint(effectiveTo, perpLeft, offset);

    return [corner1, corner2, corner3, corner4];
  }

  /// הרחבה (buffer) של פוליגון במרחק נתון במטרים.
  /// מימוש פשוט: הזזת כל קודקוד החוצה לאורך הנורמל של הזווית.
  static List<Coordinate> bufferPolygon(
    List<Coordinate> polygon,
    double distanceMeters,
  ) {
    if (polygon.length < 3) return polygon;
    if (distanceMeters == 0) return List.from(polygon);

    final result = <Coordinate>[];
    final n = polygon.length;

    for (int i = 0; i < n; i++) {
      final prev = polygon[(i - 1 + n) % n];
      final curr = polygon[i];
      final next = polygon[(i + 1) % n];

      // חישוב כיוון ממוצע של שתי הצלעות (bisector)
      final bearingIn = _bearingBetween(prev, curr);
      final bearingOut = _bearingBetween(curr, next);

      // כיוון הנורמל — ממוצע + 90° (כלפי חוץ)
      double avgBearing = (bearingIn + bearingOut) / 2;
      // תיקון כיוון ליניארי כשהזווית עוברת את 360°
      if ((bearingOut - bearingIn).abs() > 180) {
        avgBearing = (avgBearing + 180) % 360;
      }
      final normalBearing = (avgBearing + 90) % 360;

      // הזזת הקודקוד
      result.add(_offsetPoint(curr, normalBearing, distanceMeters));
    }

    return result;
  }

  /// מציאת 2 הקודקודים הקרובים ביותר מ-polyA לפוליגון polyB.
  /// לכל קודקוד ב-polyA מחשב מרחק מינימלי לקודקודי/צלעות polyB,
  /// ומחזיר את 2 הקרובים ביותר (ממוינים מהקרוב לרחוק).
  static List<Coordinate> findTwoClosestPoints(
    List<Coordinate> polyA,
    List<Coordinate> polyB,
  ) {
    if (polyA.isEmpty || polyB.isEmpty) {
      throw ArgumentError('הפוליגונים חייבים להכיל לפחות נקודה אחת');
    }
    if (polyA.length < 2) return List.from(polyA);

    // לכל קודקוד ב-polyA — מרחק מינימלי ל-polyB
    final distances = <({Coordinate point, double dist})>[];

    for (final pa in polyA) {
      double minDist = double.infinity;

      // מרחק לקודקודי B
      for (final pb in polyB) {
        final d = _haversineDistance(pa, pb);
        if (d < minDist) minDist = d;
      }

      // מרחק להטלות על צלעות B
      for (int i = 0; i < polyB.length; i++) {
        final j = (i + 1) % polyB.length;
        final projected = _projectPointOnSegment(pa, polyB[i], polyB[j]);
        final d = _haversineDistance(pa, projected);
        if (d < minDist) minDist = d;
      }

      distances.add((point: pa, dist: minDist));
    }

    // מיון לפי מרחק עולה
    distances.sort((a, b) => a.dist.compareTo(b.dist));

    // החזרת 2 הקרובים ביותר
    return distances.take(2).map((e) => e.point).toList();
  }

  /// יצירת פוליגון מורחב מ-4 נקודות פינה (מרובע).
  /// מקבל את 4 הפינות ומרחיב ב-buffer לחפיפה אמינה.
  static List<Coordinate> createPolygonFromPoints(
    List<Coordinate> points,
    double widthMeters,
  ) {
    if (points.length < 3) return points;
    return bufferPolygon(points, widthMeters);
  }

  /// מרחק במטרים בין שתי קואורדינטות (Haversine)
  static double distanceBetween(Coordinate a, Coordinate b) =>
      _haversineDistance(a, b);

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// חישוב נקודה חדשה בכיוון (bearing) ומרחק נתון (Haversine forward)
  static Coordinate _offsetPoint(
    Coordinate from,
    double bearingDeg,
    double distanceMeters,
  ) {
    final lat1 = _toRadians(from.lat);
    final lng1 = _toRadians(from.lng);
    final brng = _toRadians(bearingDeg);
    final d = distanceMeters / _earthRadiusMeters; // angular distance

    final lat2 = asin(
      sin(lat1) * cos(d) + cos(lat1) * sin(d) * cos(brng),
    );
    final lng2 = lng1 +
        atan2(
          sin(brng) * sin(d) * cos(lat1),
          cos(d) - sin(lat1) * sin(lat2),
        );

    return Coordinate(
      lat: _toDegrees(lat2),
      lng: _toDegrees(lng2),
      utm: '',
    );
  }

  /// חישוב מרחק בין שתי קואורדינטות במטרים (Haversine)
  static double _haversineDistance(Coordinate from, Coordinate to) {
    final dLat = _toRadians(to.lat - from.lat);
    final dLng = _toRadians(to.lng - from.lng);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(from.lat)) *
            cos(_toRadians(to.lat)) *
            sin(dLng / 2) *
            sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return _earthRadiusMeters * c;
  }

  /// חישוב כיוון (bearing) בין שתי קואורדינטות (0-360°, 0=צפון)
  static double _bearingBetween(Coordinate from, Coordinate to) {
    final fromLatRad = _toRadians(from.lat);
    final toLatRad = _toRadians(to.lat);
    final dLngRad = _toRadians(to.lng - from.lng);

    final y = sin(dLngRad) * cos(toLatRad);
    final x = cos(fromLatRad) * sin(toLatRad) -
        sin(fromLatRad) * cos(toLatRad) * cos(dLngRad);

    return (_toDegrees(atan2(y, x)) + 360) % 360;
  }

  /// הטלת נקודה על קטע קו — מחזיר את הנקודה הקרובה ביותר על הקטע
  static Coordinate _projectPointOnSegment(
    Coordinate point,
    Coordinate segA,
    Coordinate segB,
  ) {
    final dx = segB.lng - segA.lng;
    final dy = segB.lat - segA.lat;

    // אם הקטע הוא נקודה
    if (dx == 0 && dy == 0) return segA;

    // פרמטר t על הקטע [0,1]
    final t = ((point.lng - segA.lng) * dx + (point.lat - segA.lat) * dy) /
        (dx * dx + dy * dy);
    final clamped = t.clamp(0.0, 1.0);

    return Coordinate(
      lat: segA.lat + clamped * dy,
      lng: segA.lng + clamped * dx,
      utm: '',
    );
  }

  /// המרה ממעלות לרדיאנים
  static double _toRadians(double degrees) => degrees * pi / 180;

  /// המרה מרדיאנים למעלות
  static double _toDegrees(double radians) => radians * 180 / pi;
}
