import '../../domain/entities/checkpoint.dart';
import '../../domain/entities/narration_entry.dart';
import '../../domain/entities/navigation.dart';
import 'geometry_utils.dart';

/// יצירת סיפור דרך אוטומטי מציר מוקצה
class NarrationGenerator {
  /// יצירת רשימת NarrationEntry מציר ונקודות ציון
  static List<NarrationEntry> generateFromRoute({
    required AssignedRoute route,
    required List<Checkpoint> checkpoints,
    double walkingSpeedKmh = 4.0,
  }) {
    if (route.sequence.isEmpty) return [];

    // מיפוי checkpoint IDs לישויות
    final cpMap = <String, Checkpoint>{};
    for (final cp in checkpoints) {
      cpMap[cp.id] = cp;
    }

    final entries = <NarrationEntry>[];
    double cumulativeKm = 0.0;

    for (int i = 0; i < route.sequence.length; i++) {
      final cpId = route.sequence[i];
      final cp = cpMap[cpId];
      final pointName = cp?.name ?? cpId;

      double segmentDistanceKm = 0.0;
      String bearingStr = '';

      if (i > 0) {
        final prevCpId = route.sequence[i - 1];
        final prevCp = cpMap[prevCpId];

        if (prevCp != null && cp != null) {
          // חישוב מרחק — לפי planned path אם קיים, אחרת קו ישר
          final distMeters = _segmentDistance(route, prevCp, cp, i);
          segmentDistanceKm = distMeters / 1000.0;
          cumulativeKm += segmentDistanceKm;

          // חישוב כיוון
          final bearingDeg = GeometryUtils.bearingBetween(
            prevCp.coordinates,
            cp.coordinates,
          );
          bearingStr = '${bearingDeg.toStringAsFixed(0)}° ${_bearingToHebrew(bearingDeg)}';
        }
      }

      // פעולה ברירת מחדל
      final String action;
      if (i == 0) {
        action = 'התחלה';
      } else if (i == route.sequence.length - 1) {
        action = 'סיום';
      } else {
        action = 'מעבר';
      }

      // תיאור אוטומטי
      String description = '';
      if (i > 0) {
        final prevName = cpMap[route.sequence[i - 1]]?.name ?? route.sequence[i - 1];
        description =
            'מ-$prevName ל-$pointName, כיוון $bearingStr, מרחק ${segmentDistanceKm.toStringAsFixed(2)} ק"מ';
      }

      // זמן הליכה
      final double? walkingTime =
          segmentDistanceKm > 0 ? (segmentDistanceKm / walkingSpeedKmh) * 60.0 : null;

      entries.add(NarrationEntry(
        index: i + 1,
        segmentKm: i == 0 ? '' : segmentDistanceKm.toStringAsFixed(2),
        pointName: pointName,
        cumulativeKm: cumulativeKm.toStringAsFixed(2),
        bearing: bearingStr,
        description: description,
        action: action,
        walkingTimeMin: walkingTime,
        obstacles: '',
      ));
    }

    return entries;
  }

  /// חישוב מרחק מקטע — אם יש planned path, חישוב לפי הנתיב הערוך
  static double _segmentDistance(
    AssignedRoute route,
    Checkpoint from,
    Checkpoint to,
    int currentIndex,
  ) {
    // אם אין planned path — קו ישר
    if (route.plannedPath.isEmpty) {
      return GeometryUtils.distanceBetweenMeters(from.coordinates, to.coordinates);
    }

    // חישוב לפי planned path — מרחק כולל הנתיב בין שתי הנקודות
    // פשטנו: קו ישר (planned path הוא רציף ולא per-segment)
    return GeometryUtils.distanceBetweenMeters(from.coordinates, to.coordinates);
  }

  /// המרת כיוון במעלות לכיוון מילולי בעברית
  static String _bearingToHebrew(double degrees) {
    if (degrees >= 337.5 || degrees < 22.5) return 'צפון';
    if (degrees < 67.5) return 'צפון-מזרח';
    if (degrees < 112.5) return 'מזרח';
    if (degrees < 157.5) return 'דרום-מזרח';
    if (degrees < 202.5) return 'דרום';
    if (degrees < 247.5) return 'דרום-מערב';
    if (degrees < 292.5) return 'מערב';
    return 'צפון-מערב';
  }
}
