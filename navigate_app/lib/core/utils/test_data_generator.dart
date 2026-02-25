import 'dart:math';
import '../../domain/entities/checkpoint.dart';
import '../../domain/entities/coordinate.dart';
import '../../data/repositories/checkpoint_repository.dart';

/// מחלקת עזר ליצירת נתוני בדיקה
class TestDataGenerator {
  final CheckpointRepository _checkpointRepo = CheckpointRepository();

  /// חישוב מספרים סידוריים פנויים (ממלא פערים ואז ממשיך)
  List<int> _getAvailableNumbers(Set<int> existingNumbers, int count) {
    final available = <int>[];
    final maxExisting = existingNumbers.isEmpty ? 0 : existingNumbers.reduce(max);

    // סריקת פערים 1..maxExisting
    for (int n = 1; n <= maxExisting && available.length < count; n++) {
      if (!existingNumbers.contains(n)) {
        available.add(n);
      }
    }
    // המשך אחרי המקסימום
    int next = maxExisting + 1;
    while (available.length < count) {
      available.add(next++);
    }
    return available;
  }

  /// יצירת נקודות ציון אקראיות בתוך גבול נתון
  Future<void> createCheckpointsInBoundary({
    required String areaId,
    required int count,
    required List<Coordinate> boundaryCoordinates,
  }) async {
    print('מתחיל יצירת $count נקודות ציון...');

    // טעינת נקודות קיימות לחישוב מספרים פנויים
    final existing = await _checkpointRepo.getByArea(areaId);
    final existingNumbers = existing.map((c) => c.sequenceNumber).toSet();
    final availableNumbers = _getAvailableNumbers(existingNumbers, count);

    // חישוב bounding box של הגבול
    double minLat = boundaryCoordinates.first.lat;
    double maxLat = boundaryCoordinates.first.lat;
    double minLng = boundaryCoordinates.first.lng;
    double maxLng = boundaryCoordinates.first.lng;

    for (final coord in boundaryCoordinates) {
      if (coord.lat < minLat) minLat = coord.lat;
      if (coord.lat > maxLat) maxLat = coord.lat;
      if (coord.lng < minLng) minLng = coord.lng;
      if (coord.lng > maxLng) maxLng = coord.lng;
    }

    print('Bounding box: lat $minLat - $maxLat, lng $minLng - $maxLng');

    final random = Random();
    final types = ['checkpoint', 'mandatory_passage'];
    int created = 0;

    // ניסיון ליצור נקודות (עד פי 10 ניסיונות)
    for (int attempt = 0; attempt < count * 10 && created < count; attempt++) {
      // יצירת נקודה אקראית בתוך ה-bounding box
      final lat = minLat + random.nextDouble() * (maxLat - minLat);
      final lng = minLng + random.nextDouble() * (maxLng - minLng);

      // בדיקה אם הנקודה בתוך הפוליגון
      if (_isPointInPolygon(lat, lng, boundaryCoordinates)) {
        final seqNum = availableNumbers[created];
        final type = types[random.nextInt(types.length)];
        final checkpoint = Checkpoint(
          id: '${DateTime.now().millisecondsSinceEpoch}_$created',
          areaId: areaId,
          name: '',
          description: '',
          type: type,
          color: Checkpoint.colorForType(type),
          coordinates: Coordinate(
            lat: lat,
            lng: lng,
            utm: _convertToUTM(lat, lng),
          ),
          sequenceNumber: seqNum,
          createdBy: '',
          createdAt: DateTime.now(),
        );

        await _checkpointRepo.create(checkpoint);
        created++;
        print('✓ נוצרה נקודה $created/$count: #$seqNum');
      }
    }

    if (created < count) {
      print('⚠ נוצרו רק $created נקודות מתוך $count');
    } else {
      print('✓ הושלמה יצירת $count נקודות ציון בהצלחה!');
    }
  }

  /// יצירת נקודות ציון באזור ברירת מחדל (סביבות נקודה מרכזית)
  Future<void> createCheckpointsInArea({
    required String areaId,
    required int count,
    required double centerLat,
    required double centerLng,
    double radiusKm = 2.0,
  }) async {
    print('מתחיל יצירת $count נקודות ציון סביב ($centerLat, $centerLng)...');

    // טעינת נקודות קיימות לחישוב מספרים פנויים
    final existing = await _checkpointRepo.getByArea(areaId);
    final existingNumbers = existing.map((c) => c.sequenceNumber).toSet();
    final availableNumbers = _getAvailableNumbers(existingNumbers, count);

    final random = Random();
    final types = ['checkpoint', 'mandatory_passage'];

    // המרת רדיוס ק"מ למעלות (קירוב גס)
    final radiusDegrees = radiusKm / 111.0;

    for (int i = 0; i < count; i++) {
      final angle = random.nextDouble() * 2 * pi;
      final distance = random.nextDouble() * radiusDegrees;

      final lat = centerLat + distance * cos(angle);
      final lng = centerLng + distance * sin(angle);

      final seqNum = availableNumbers[i];
      final type = types[random.nextInt(types.length)];
      final checkpoint = Checkpoint(
        id: '${DateTime.now().millisecondsSinceEpoch}_$i',
        areaId: areaId,
        name: '',
        description: '',
        type: type,
        color: Checkpoint.colorForType(type),
        coordinates: Coordinate(
          lat: lat,
          lng: lng,
          utm: _convertToUTM(lat, lng),
        ),
        sequenceNumber: seqNum,
        createdBy: '',
        createdAt: DateTime.now(),
      );

      await _checkpointRepo.create(checkpoint);
      print('✓ נוצרה נקודה ${i + 1}/$count: #$seqNum');
    }

    print('✓ הושלמה יצירת $count נקודות ציון בהצלחה!');
  }

  /// בדיקה אם נקודה נמצאת בתוך פוליגון (Ray casting algorithm)
  bool _isPointInPolygon(double lat, double lng, List<Coordinate> polygon) {
    int intersections = 0;

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

  /// המרה פשוטה ל-UTM (מדומה)
  String _convertToUTM(double lat, double lng) {
    final zone = ((lng + 180) / 6).floor() + 1;
    final northing = (lat * 110000).toInt();
    final easting = ((lng - (zone * 6 - 183)) * 100000).toInt();
    return '36R ${easting.abs()} ${northing.abs()}';
  }
}
