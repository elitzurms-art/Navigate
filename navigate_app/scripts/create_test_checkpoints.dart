import 'dart:io';
import 'dart:math';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import '../lib/domain/entities/checkpoint.dart' as domain;
import '../lib/domain/entities/coordinate.dart';
import '../lib/data/datasources/local/app_database.dart';
import '../lib/data/repositories/checkpoint_repository.dart';
import '../lib/data/repositories/area_repository.dart';
import '../lib/data/repositories/boundary_repository.dart';

/// סקריפט ליצירת 20 נקודות ציון לבדיקה
void main() async {
  print('מתחיל יצירת נקודות ציון...');

  final areaRepo = AreaRepository();
  final boundaryRepo = BoundaryRepository();
  final checkpointRepo = CheckpointRepository();

  // מציאת האזור "שטח אש 208"
  print('מחפש אזור "שטח אש 208"...');
  final areas = await areaRepo.getAll();
  final area = areas.firstWhere(
    (a) => a.name.contains('208') || a.name.contains('אש'),
    orElse: () {
      print('לא נמצא אזור "שטח אש 208". אזורים זמינים:');
      for (final a in areas) {
        print('  - ${a.name} (${a.id})');
      }
      exit(1);
    },
  );

  print('נמצא אזור: ${area.name} (${area.id})');

  // מציאת הגבול של האזור
  print('מחפש גבול גזרה...');
  final boundaries = await boundaryRepo.getByArea(area.id);

  if (boundaries.isEmpty) {
    print('לא נמצא גבול גזרה לאזור זה. יוצר נקודות בקואורדינטות ברירת מחדל.');
    // נשתמש בקואורדינטות מרכז ישראל כברירת מחדל
    await _createCheckpointsInDefaultArea(checkpointRepo, area.id);
  } else {
    final boundary = boundaries.first;
    print('נמצא גבול: ${boundary.name}');
    print('מספר נקודות בגבול: ${boundary.coordinates.length}');

    // יצירת 20 נקודות בתוך הגבול
    await _createCheckpointsInBoundary(checkpointRepo, area.id, boundary.coordinates);
  }

  print('✓ הושלמה יצירת נקודות הציון בהצלחה!');
}

/// יצירת נקודות בתוך גבול נתון
Future<void> _createCheckpointsInBoundary(
  CheckpointRepository repo,
  String areaId,
  List<Coordinate> boundaryCoords,
) async {
  // חישוב bounding box של הגבול
  double minLat = boundaryCoords.first.lat;
  double maxLat = boundaryCoords.first.lat;
  double minLng = boundaryCoords.first.lng;
  double maxLng = boundaryCoords.first.lng;

  for (final coord in boundaryCoords) {
    if (coord.lat < minLat) minLat = coord.lat;
    if (coord.lat > maxLat) maxLat = coord.lat;
    if (coord.lng < minLng) minLng = coord.lng;
    if (coord.lng > maxLng) maxLng = coord.lng;
  }

  print('Bounding box: lat ${minLat.toStringAsFixed(6)} - ${maxLat.toStringAsFixed(6)}');
  print('              lng ${minLng.toStringAsFixed(6)} - ${maxLng.toStringAsFixed(6)}');

  final random = Random();
  final colors = ['blue', 'green'];
  final types = ['checkpoint', 'mandatory_passage'];
  int created = 0;

  // ניסיון ליצור 20 נקודות (עד 100 ניסיונות)
  for (int attempt = 0; attempt < 100 && created < 20; attempt++) {
    // יצירת נקודה אקראית בתוך ה-bounding box
    final lat = minLat + random.nextDouble() * (maxLat - minLat);
    final lng = minLng + random.nextDouble() * (maxLng - minLng);

    // בדיקה אם הנקודה בתוך הפוליגון
    if (_isPointInPolygon(lat, lng, boundaryCoords)) {
      final checkpoint = domain.Checkpoint(
        id: DateTime.now().millisecondsSinceEpoch.toString() + '_$created',
        areaId: areaId,
        name: 'נ.צ ${created + 1}',
        description: 'נקודת ציון ${created + 1} - נוצרה אוטומטית',
        type: types[random.nextInt(types.length)],
        color: colors[random.nextInt(colors.length)],
        coordinates: Coordinate(
          lat: lat,
          lng: lng,
          utm: _convertToUTM(lat, lng),
        ),
        sequenceNumber: created + 1,
        createdAt: DateTime.now(),
      );

      await repo.add(checkpoint);
      created++;
      print('✓ נוצרה נקודה ${created}/20: ${checkpoint.name} (${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)})');
    }
  }

  if (created < 20) {
    print('⚠ נוצרו רק $created נקודות מתוך 20 (הגבול קטן מדי)');
  }
}

/// יצירת נקודות באזור ברירת מחדל (סביבות תל אביב)
Future<void> _createCheckpointsInDefaultArea(
  CheckpointRepository repo,
  String areaId,
) async {
  final random = Random();
  final colors = ['blue', 'green'];
  final types = ['checkpoint', 'mandatory_passage'];

  // מרכז: תל אביב (32.0853, 34.7818)
  const centerLat = 32.0853;
  const centerLng = 34.7818;
  const radius = 0.02; // כ-2 ק"מ

  for (int i = 0; i < 20; i++) {
    final angle = random.nextDouble() * 2 * pi;
    final distance = random.nextDouble() * radius;

    final lat = centerLat + distance * cos(angle);
    final lng = centerLng + distance * sin(angle);

    final checkpoint = domain.Checkpoint(
      id: DateTime.now().millisecondsSinceEpoch.toString() + '_$i',
      areaId: areaId,
      name: 'נ.צ ${i + 1}',
      description: 'נקודת ציון ${i + 1} - נוצרה אוטומטית',
      type: types[random.nextInt(types.length)],
      color: colors[random.nextInt(colors.length)],
      coordinates: Coordinate(
        lat: lat,
        lng: lng,
        utm: _convertToUTM(lat, lng),
      ),
      sequenceNumber: i + 1,
      createdAt: DateTime.now(),
    );

    await repo.add(checkpoint);
    print('✓ נוצרה נקודה ${i + 1}/20: ${checkpoint.name}');
  }
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

/// המרה פשוטה ל-UTM (מדומה - לא המרה אמיתית)
String _convertToUTM(double lat, double lng) {
  // המרה פשוטה למחרוזת UTM (לא אמיתית, רק למטרות הדגמה)
  final zone = ((lng + 180) / 6).floor() + 1;
  final northing = (lat * 110000).toInt();
  final easting = ((lng - (zone * 6 - 183)) * 100000).toInt();
  return '36R ${easting.abs()} ${northing.abs()}';
}
