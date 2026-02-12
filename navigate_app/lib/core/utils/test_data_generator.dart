import 'dart:math';
import '../../domain/entities/checkpoint.dart';
import '../../domain/entities/coordinate.dart';
import '../../domain/entities/boundary.dart';
import '../../data/repositories/checkpoint_repository.dart';

/// מחלקת עזר ליצירת נתוני בדיקה
class TestDataGenerator {
  final CheckpointRepository _checkpointRepo = CheckpointRepository();

  /// יצירת נקודות ציון אקראיות בתוך גבול נתון
  Future<void> createCheckpointsInBoundary({
    required String areaId,
    required int count,
    required List<Coordinate> boundaryCoordinates,
  }) async {
    print('מתחיל יצירת $count נקודות ציון...');

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
    final colors = ['blue', 'green'];
    final types = ['checkpoint', 'mandatory_passage'];
    int created = 0;

    // ניסיון ליצור נקודות (עד פי 10 ניסיונות)
    for (int attempt = 0; attempt < count * 10 && created < count; attempt++) {
      // יצירת נקודה אקראית בתוך ה-bounding box
      final lat = minLat + random.nextDouble() * (maxLat - minLat);
      final lng = minLng + random.nextDouble() * (maxLng - minLng);

      // בדיקה אם הנקודה בתוך הפוליגון
      if (_isPointInPolygon(lat, lng, boundaryCoordinates)) {
        final checkpoint = Checkpoint(
          id: '${DateTime.now().millisecondsSinceEpoch}_$created',
          areaId: areaId,
          name: 'נ.צ ${created + 1}',
          description: 'נקודת ציון ${created + 1} - נוצרה אוטומטית לבדיקה',
          type: types[random.nextInt(types.length)],
          color: colors[random.nextInt(colors.length)],
          coordinates: Coordinate(
            lat: lat,
            lng: lng,
            utm: _convertToUTM(lat, lng),
          ),
          sequenceNumber: created + 1,
          createdBy: '',
          createdAt: DateTime.now(),
        );

        await _checkpointRepo.create(checkpoint);
        created++;
        print('✓ נוצרה נקודה $created/$count: ${checkpoint.name}');
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

    final random = Random();
    final colors = ['blue', 'green'];
    final types = ['checkpoint', 'mandatory_passage'];

    // המרת רדיוס ק"מ למעלות (קירוב גס)
    final radiusDegrees = radiusKm / 111.0;

    for (int i = 0; i < count; i++) {
      final angle = random.nextDouble() * 2 * pi;
      final distance = random.nextDouble() * radiusDegrees;

      final lat = centerLat + distance * cos(angle);
      final lng = centerLng + distance * sin(angle);

      final checkpoint = Checkpoint(
        id: '${DateTime.now().millisecondsSinceEpoch}_$i',
        areaId: areaId,
        name: 'נ.צ ${i + 1}',
        description: 'נקודת ציון ${i + 1} - נוצרה אוטומטית לבדיקה',
        type: types[random.nextInt(types.length)],
        color: colors[random.nextInt(colors.length)],
        coordinates: Coordinate(
          lat: lat,
          lng: lng,
          utm: _convertToUTM(lat, lng),
        ),
        sequenceNumber: i + 1,
        createdBy: '',
        createdAt: DateTime.now(),
      );

      await _checkpointRepo.create(checkpoint);
      print('✓ נוצרה נקודה ${i + 1}/20: ${checkpoint.name}');
    }

    print('✓ הושלמה יצירת 20 נקודות ציון בהצלחה!');
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
