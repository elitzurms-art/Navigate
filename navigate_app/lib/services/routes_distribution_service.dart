import 'dart:math';
import '../domain/entities/navigation.dart' as domain;
import '../domain/entities/checkpoint.dart';
import '../domain/entities/navigation_tree.dart';
import '../domain/entities/coordinate.dart';
import '../domain/entities/boundary.dart';
import '../core/utils/geometry_utils.dart';

/// שירות לחלוקה אוטומטית של צירים
class RoutesDistributionService {
  /// חלוקה אוטומטית של צירים לפי הגדרות
  Future<Map<String, domain.AssignedRoute>> distributeAutomatically({
    required domain.Navigation navigation,
    required NavigationTree tree,
    required List<Checkpoint> checkpoints,
    Boundary? boundary,
    String? startPointId,
    String? endPointId,
    required String executionOrder,
    required int checkpointsPerNavigator,
    required double minRouteLength,
    required double maxRouteLength,
  }) async {
    print('Starting automatic distribution...');
    print('Checkpoints: ${checkpoints.length}');
    print('Checkpoints per navigator: $checkpointsPerNavigator');

    // מציאת משתתפים: עדיפות לבחירה ידנית מהניווט
    List<String> navigators = [];

    if (navigation.selectedParticipantIds.isNotEmpty) {
      // 1. משתתפים שנבחרו ידנית
      navigators = List.from(navigation.selectedParticipantIds);
      print('Using ${navigators.length} manually selected participants');
    } else if (navigation.selectedSubFrameworkIds.isNotEmpty) {
      // 2. כל המשתמשים מתתי-המסגרות שנבחרו
      for (final sf in tree.subFrameworks) {
        if (navigation.selectedSubFrameworkIds.contains(sf.id)) {
          navigators.addAll(sf.userIds);
        }
      }
      print('Using ${navigators.length} participants from ${navigation.selectedSubFrameworkIds.length} selected sub-frameworks');
    } else {
      // 3. fallback — כל המנווטים מתתי-מסגרות שאינן קבועות (לא מפקדים/מנהלת/מבקרים)
      for (final sf in tree.subFrameworks) {
        if (!sf.isFixed) {
          navigators.addAll(sf.userIds);
        }
      }
      print('Using ${navigators.length} navigators from non-fixed sub-frameworks (fallback)');
    }

    print('Total navigators: ${navigators.length}');

    if (navigators.isEmpty) {
      throw Exception('לא נמצאו משתתפים - יש לבחור תתי-מסגרות עם משתמשים');
    }

    if (checkpoints.isEmpty) {
      throw Exception('לא נמצאו נקודות ציון');
    }

    // סינון נקודות לפי גבול גזרה (אם קיים)
    List<Checkpoint> availableCheckpoints = checkpoints;

    print('Boundary: ${boundary != null ? "קיים (${boundary.name})" : "לא קיים"}');
    if (boundary != null) {
      print('Boundary coordinates: ${boundary.coordinates.length} נקודות');
    }

    if (boundary != null && boundary.coordinates.isNotEmpty) {
      print('סינון נקודות לפי גבול "${boundary.name}"...');
      final beforeFilter = availableCheckpoints.length;

      availableCheckpoints = GeometryUtils.filterPointsInPolygon(
        points: checkpoints,
        getCoordinate: (checkpoint) => checkpoint.coordinates,
        polygon: boundary.coordinates,
      );

      print('נקודות לפני סינון: $beforeFilter, אחרי סינון: ${availableCheckpoints.length}');

      // הצגת דוגמאות של נקודות שסוננו
      if (availableCheckpoints.isNotEmpty) {
        print('דוגמה לנקודה שנבחרה: ${availableCheckpoints.first.name} (${availableCheckpoints.first.coordinates.lat}, ${availableCheckpoints.first.coordinates.lng})');
      }

      // בדיקה אם יש נקודות שנשארו בחוץ
      final filtered = checkpoints.where((cp) => !availableCheckpoints.contains(cp)).toList();
      if (filtered.isNotEmpty) {
        print('דוגמה לנקודה שסוננה: ${filtered.first.name} (${filtered.first.coordinates.lat}, ${filtered.first.coordinates.lng})');
      }
    } else {
      print('⚠️ אזהרה: לא מבוצע סינון לפי גבול! כל הנקודות זמינות.');
    }

    // חישוב נקודות שזמינות בפועל (בניכוי התחלה/סיום שאינן מחולקות)
    int excludedCount = 0;
    if (startPointId != null) excludedCount++;
    if (endPointId != null && endPointId != startPointId) excludedCount++;
    final effectiveAvailable = availableCheckpoints.length - excludedCount;

    if (effectiveAvailable < navigators.length * checkpointsPerNavigator) {
      throw Exception(
        'אין מספיק נקודות: $effectiveAvailable נקודות זמינות לחלוקה, '
        'נדרשות ${navigators.length * checkpointsPerNavigator} נקודות '
        '(${navigators.length} מנווטים × $checkpointsPerNavigator נקודות)'
      );
    }

    // חלוקת הנקודות
    Map<String, domain.AssignedRoute> routes = {};
    Set<String> usedCheckpointIds = {};

    // נקודת התחלה לחישוב קירוב (מרכז הגבול או כל הנקודות)
    Coordinate referencePoint;
    if (boundary != null && boundary.coordinates.isNotEmpty) {
      referencePoint = GeometryUtils.getPolygonCenter(boundary.coordinates);
    } else {
      referencePoint = GeometryUtils.getPolygonCenter(
        availableCheckpoints.map((cp) => cp.coordinates).toList(),
      );
    }

    // מציאת נקודות התחלה וסיום אם הוגדרו
    Checkpoint? startCheckpoint;
    Checkpoint? endCheckpoint;

    if (startPointId != null) {
      startCheckpoint = availableCheckpoints.firstWhere(
        (cp) => cp.id == startPointId,
        orElse: () => availableCheckpoints.first,
      );
    }

    if (endPointId != null) {
      endCheckpoint = availableCheckpoints.firstWhere(
        (cp) => cp.id == endPointId,
        orElse: () => availableCheckpoints.last,
      );
    }

    for (int i = 0; i < navigators.length; i++) {
      final navigatorId = navigators[i];
      print('\n🎯 מחלק צירים למנווט ${i + 1}/${navigators.length}');

      // בחירת נקודות למנווט
      List<Checkpoint> selectedCheckpoints = [];
      Coordinate currentPosition = referencePoint;

      // שלב 1: התחלה מנקודת ההתחלה אם הוגדרה
      if (startCheckpoint != null) {
        currentPosition = startCheckpoint.coordinates;
      }

      // שלב 2: בחירת בדיוק checkpointsPerNavigator נקודות
      final availableCandidates = availableCheckpoints
          .where((cp) =>
              !usedCheckpointIds.contains(cp.id) &&
              cp.id != startPointId &&
              cp.id != endPointId)
          .toList();

      if (availableCandidates.length < checkpointsPerNavigator) {
        print('⚠️ לא מספיק נקודות זמינות למנווט ${i + 1} (${availableCandidates.length} < $checkpointsPerNavigator)');
        throw Exception(
          'לא מספיק נקודות למנווט ${i + 1}/${navigators.length}: '
          '${availableCandidates.length} נקודות זמינות, נדרשות $checkpointsPerNavigator'
        );
      }

      // אסטרטגיה: נבחר נקודות באופן איטרטיבי עד שנמצא שילוב בטווח
      for (int attempt = 0; attempt < 5; attempt++) {
        selectedCheckpoints.clear();

        // קביעת "פקטור פיזור" - מנסים פיזור שונה בכל ניסיון
        final spreadFactor = 0.5 + (attempt * 0.3); // 0.5, 0.8, 1.1, 1.4, 1.7

        // בחירת נקודות
        Coordinate currentPos = currentPosition;
        for (int j = 0; j < checkpointsPerNavigator; j++) {
          final candidates = availableCandidates
              .where((cp) => !selectedCheckpoints.contains(cp))
              .toList();

          if (candidates.isEmpty) break;

          // חישוב מרחק ממוצע שנותר
          final remainingPoints = checkpointsPerNavigator - selectedCheckpoints.length;
          final currentDist = _calculateRouteLength(
            selectedCheckpoints,
            selectedCheckpoints.map((cp) => cp.id).toList(),
            startPointId,
            null, // ללא סיום עדיין
            availableCheckpoints,
          );

          final avgNeeded = remainingPoints > 0
              ? ((minRouteLength + maxRouteLength) / 2 - currentDist) / remainingPoints
              : 0;

          // בחירת נקודה הבאה לפי מרחק מתואם
          final targetDist = avgNeeded * spreadFactor;
          final nextCheckpoint = _findCheckpointByDistance(
            currentPos,
            candidates,
            targetDist.abs(),
          );

          if (nextCheckpoint != null) {
            selectedCheckpoints.add(nextCheckpoint);
            currentPos = nextCheckpoint.coordinates;
          }
        }

        // חישוב מרחק סופי
        final routeLength = _calculateRouteLength(
          selectedCheckpoints,
          selectedCheckpoints.map((cp) => cp.id).toList(),
          startPointId,
          endPointId,
          availableCheckpoints,
        );

        print('ניסיון ${attempt + 1}: ${selectedCheckpoints.length} נקודות, ${routeLength.toStringAsFixed(2)} ק"מ (טווח: $minRouteLength-$maxRouteLength)');

        // בדיקה אם בטווח
        if (routeLength >= minRouteLength && routeLength <= maxRouteLength) {
          print('✓ ציר מושלם בטווח!');
          break;
        }

        // ניסיון אחרון - לוקח מה שיש
        if (attempt == 4) {
          print('⚠️ לא מצאתי ציר אופטימלי, לוקח את הקרוב ביותר');
        }
      }

      // סימון הנקודות כמשומשות
      for (final cp in selectedCheckpoints) {
        usedCheckpointIds.add(cp.id);
      }

      // יצירת רצף (סדר הנקודות)
      List<String> sequence;
      if (executionOrder == 'sequential') {
        // חישוב רצף אופטימלי (TSP פשוט)
        sequence = _calculateOptimalSequence(
          selectedCheckpoints,
          startPointId,
          endPointId,
          availableCheckpoints,
        );
      } else {
        // סדר כלשהו (המנווט יבחר)
        sequence = selectedCheckpoints.map((cp) => cp.id).toList();
      }

      // חישוב אורך ציר
      double routeLength = _calculateRouteLength(
        selectedCheckpoints,
        sequence,
        startPointId,
        endPointId,
        checkpoints,
      );

      // קביעת סטטוס
      String status;
      if (routeLength < minRouteLength) {
        status = 'too_short';
      } else if (routeLength > maxRouteLength) {
        status = 'too_long';
      } else {
        status = 'optimal';
      }

      routes[navigatorId] = domain.AssignedRoute(
        checkpointIds: selectedCheckpoints.map((cp) => cp.id).toList(),
        routeLengthKm: routeLength,
        sequence: sequence,
        startPointId: startPointId,
        endPointId: endPointId,
        status: status,
        isVerified: false,
      );
    }

    print('Distribution complete: ${routes.length} routes created');
    return routes;
  }

  /// חישוב רצף אופטימלי (פתרון מקורב ל-TSP)
  List<String> _calculateOptimalSequence(
    List<Checkpoint> checkpoints,
    String? startPointId,
    String? endPointId,
    List<Checkpoint> allCheckpoints,
  ) {
    if (checkpoints.isEmpty) return [];

    // IMPORTANT: startPoint ו-endPoint הם נקודות נפרדות, לא חלק מ-checkpoints!
    // הרצף הוא רק של הנקודות המחולקות (checkpoints), בלי התחלה וסיום

    if (checkpoints.length == 1) return [checkpoints.first.id];

    // אלגוריתם תאב (Greedy) - מהנקודה הקרובה ביותר
    List<Checkpoint> remaining = List.from(checkpoints);
    List<String> sequence = [];

    // אם יש נקודת התחלה, נתחיל מהנקודה הקרובה אליה
    Checkpoint current;
    if (startPointId != null) {
      final startCp = allCheckpoints.where((cp) => cp.id == startPointId).firstOrNull;
      if (startCp != null) {
        // מוצאים את הנקודה הקרובה ביותר לנקודת ההתחלה
        current = _findNearestCheckpoint(startCp.coordinates, remaining) ?? remaining.first;
      } else {
        current = remaining.first;
      }
    } else {
      current = remaining.first;
    }

    while (remaining.isNotEmpty) {
      // מציאת הנקודה הקרובה ביותר
      Checkpoint? nearest;
      double minDistance = double.infinity;

      for (final cp in remaining) {
        final distance = _calculateDistance(
          current.coordinates,
          cp.coordinates,
        );
        if (distance < minDistance) {
          minDistance = distance;
          nearest = cp;
        }
      }

      if (nearest != null) {
        sequence.add(nearest.id);
        remaining.remove(nearest);
        current = nearest;
      } else {
        break;
      }
    }

    return sequence;
  }

  /// חישוב אורך ציר
  double _calculateRouteLength(
    List<Checkpoint> checkpoints,
    List<String> sequence,
    String? startPointId,
    String? endPointId,
    List<Checkpoint> allCheckpoints,
  ) {
    double totalDistance = 0.0;

    // מציאת נקודות התחלה וסיום
    Checkpoint? startPoint;
    Checkpoint? endPoint;

    if (startPointId != null) {
      startPoint = allCheckpoints.firstWhere(
        (cp) => cp.id == startPointId,
        orElse: () => checkpoints.first,
      );
    }

    if (endPointId != null) {
      endPoint = allCheckpoints.firstWhere(
        (cp) => cp.id == endPointId,
        orElse: () => checkpoints.last,
      );
    }

    // מרחק מנקודת התחלה לנקודה הראשונה
    if (startPoint != null && sequence.isNotEmpty) {
      final firstCheckpoint = checkpoints.firstWhere((cp) => cp.id == sequence.first);
      totalDistance += _calculateDistance(
        startPoint.coordinates,
        firstCheckpoint.coordinates,
      );
    }

    // מרחקים בין הנקודות לפי הרצף
    for (int i = 0; i < sequence.length - 1; i++) {
      final from = checkpoints.firstWhere((cp) => cp.id == sequence[i]);
      final to = checkpoints.firstWhere((cp) => cp.id == sequence[i + 1]);
      totalDistance += _calculateDistance(from.coordinates, to.coordinates);
    }

    // מרחק מהנקודה האחרונה לנקודת הסיום
    if (endPoint != null && sequence.isNotEmpty) {
      final lastCheckpoint = checkpoints.firstWhere((cp) => cp.id == sequence.last);
      totalDistance += _calculateDistance(
        lastCheckpoint.coordinates,
        endPoint.coordinates,
      );
    }

    return totalDistance;
  }

  /// חישוב מרחק בין שתי נקודות (Haversine)
  double _calculateDistance(Coordinate from, Coordinate to) {
    const R = 6371.0; // רדיוס כדור הארץ בק"מ

    final lat1 = from.lat * pi / 180;
    final lat2 = to.lat * pi / 180;
    final deltaLat = (to.lat - from.lat) * pi / 180;
    final deltaLng = (to.lng - from.lng) * pi / 180;

    final a = sin(deltaLat / 2) * sin(deltaLat / 2) +
        cos(lat1) * cos(lat2) * sin(deltaLng / 2) * sin(deltaLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return R * c;
  }

  /// מציאת נקודת הציון הקרובה ביותר לנקודה נתונה
  Checkpoint? _findNearestCheckpoint(Coordinate point, List<Checkpoint> candidates) {
    if (candidates.isEmpty) return null;

    Checkpoint? nearest;
    double minDistance = double.infinity;

    for (final candidate in candidates) {
      final distance = _calculateDistance(point, candidate.coordinates);
      if (distance < minDistance) {
        minDistance = distance;
        nearest = candidate;
      }
    }

    return nearest;
  }

  /// מציאת נקודה במרחק מסוים (קירוב)
  Checkpoint? _findCheckpointByDistance(
    Coordinate point,
    List<Checkpoint> candidates,
    double targetDistance,
  ) {
    if (candidates.isEmpty) return null;

    Checkpoint? best;
    double minDiff = double.infinity;

    for (final candidate in candidates) {
      final distance = _calculateDistance(point, candidate.coordinates);
      final diff = (distance - targetDistance).abs();

      if (diff < minDiff) {
        minDiff = diff;
        best = candidate;
      }
    }

    return best;
  }

  /// בדיקה איזה מרחק יותר קרוב לטווח
  bool _isCloserToRange(double newLength, double oldLength, double min, double max) {
    // אם שניהם בטווח, נבחר את הקצר יותר
    if (newLength >= min && newLength <= max && oldLength >= min && oldLength <= max) {
      return newLength < oldLength;
    }

    // אם רק אחד בטווח, נבחר אותו
    if (newLength >= min && newLength <= max) return true;
    if (oldLength >= min && oldLength <= max) return false;

    // אם שניהם מחוץ לטווח, נבחר את הקרוב יותר
    final newDist = (newLength < min) ? (min - newLength) : (newLength - max);
    final oldDist = (oldLength < min) ? (min - oldLength) : (oldLength - max);
    return newDist < oldDist;
  }
}
