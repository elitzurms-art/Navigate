import 'package:flutter_test/flutter_test.dart';
import 'package:navigate_app/domain/entities/boundary.dart';
import 'package:navigate_app/domain/entities/coordinate.dart';

void main() {
  final now = DateTime(2026, 3, 10, 12, 0, 0);

  final coords = const [
    Coordinate(lat: 31.0, lng: 34.0, utm: '600000430000'),
    Coordinate(lat: 31.5, lng: 34.5, utm: '650000450000'),
    Coordinate(lat: 32.0, lng: 35.0, utm: '700000540000'),
  ];

  Boundary _makeBoundary({
    String id = 'b-1',
    String areaId = 'area-1',
    String name = 'גבול גזרה',
    String description = 'תיאור',
    List<Coordinate>? coordinates,
    String color = 'black',
    double strokeWidth = 3.0,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Boundary(
      id: id,
      areaId: areaId,
      name: name,
      description: description,
      coordinates: coordinates ?? coords,
      color: color,
      strokeWidth: strokeWidth,
      createdAt: createdAt ?? now,
      updatedAt: updatedAt ?? now,
    );
  }

  group('Boundary', () {
    // ── 1. toMap / fromMap roundtrip ──
    test('toMap / fromMap roundtrip preserves all fields', () {
      final boundary = _makeBoundary(
        color: 'red',
        strokeWidth: 5.0,
        description: 'גבול מזרחי',
      );
      final map = boundary.toMap();
      final restored = Boundary.fromMap(map);

      expect(restored.id, boundary.id);
      expect(restored.areaId, boundary.areaId);
      expect(restored.name, boundary.name);
      expect(restored.description, boundary.description);
      expect(restored.coordinates.length, boundary.coordinates.length);
      expect(restored.color, boundary.color);
      expect(restored.strokeWidth, boundary.strokeWidth);
      expect(restored.createdAt, boundary.createdAt);
      expect(restored.updatedAt, boundary.updatedAt);
    });

    // ── 2. fromMap defaults ──
    test('fromMap uses defaults for description, color, strokeWidth', () {
      final map = <String, dynamic>{
        'id': 'b-2',
        'areaId': 'area-1',
        'name': 'test',
        // description missing
        'coordinates': [
          {'lat': 31.0, 'lng': 34.0, 'utm': '600000430000'},
        ],
        // color missing
        // strokeWidth missing
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      };
      final boundary = Boundary.fromMap(map);

      expect(boundary.description, '');
      expect(boundary.color, 'black');
      expect(boundary.strokeWidth, 3.0);
    });

    // ── 3. strokeWidth int → double conversion ──
    test('fromMap converts strokeWidth from int to double', () {
      final map = <String, dynamic>{
        'id': 'b-3',
        'areaId': 'area-1',
        'name': 'test',
        'description': '',
        'coordinates': [
          {'lat': 31.0, 'lng': 34.0, 'utm': '600000430000'},
        ],
        'color': 'blue',
        'strokeWidth': 4, // int, not double
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      };
      final boundary = Boundary.fromMap(map);

      expect(boundary.strokeWidth, 4.0);
      expect(boundary.strokeWidth, isA<double>());
    });

    // ── 4. copyWith ──
    test('copyWith creates boundary with updated fields', () {
      final original = _makeBoundary();
      final updated = original.copyWith(
        name: 'גבול חדש',
        color: 'green',
        strokeWidth: 7.5,
      );

      expect(updated.name, 'גבול חדש');
      expect(updated.color, 'green');
      expect(updated.strokeWidth, 7.5);
      // Unchanged fields
      expect(updated.id, original.id);
      expect(updated.areaId, original.areaId);
      expect(updated.coordinates, original.coordinates);
    });

    test('copyWith with no arguments returns equal boundary', () {
      final original = _makeBoundary();
      final copy = original.copyWith();
      expect(copy, equals(original));
    });

    // ── 5. Equatable ──
    test('Equatable: identical boundaries are equal', () {
      final a = _makeBoundary();
      final b = _makeBoundary();
      expect(a, equals(b));
    });

    test('Equatable: boundaries with different ids are not equal', () {
      final a = _makeBoundary(id: 'b-1');
      final b = _makeBoundary(id: 'b-2');
      expect(a, isNot(equals(b)));
    });

    // ── 6. Coordinates list serialization ──
    test('multiple coordinates survive toMap/fromMap', () {
      final boundary = _makeBoundary(coordinates: [
        const Coordinate(lat: 30.0, lng: 33.0, utm: '500000420000'),
        const Coordinate(lat: 30.5, lng: 33.5, utm: '550000430000'),
        const Coordinate(lat: 31.0, lng: 34.0, utm: '600000440000'),
        const Coordinate(lat: 31.5, lng: 34.5, utm: '650000450000'),
      ]);
      final map = boundary.toMap();
      final coordsList = map['coordinates'] as List;
      expect(coordsList.length, 4);

      final restored = Boundary.fromMap(map);
      expect(restored.coordinates.length, 4);
      expect(restored.coordinates[0].lat, 30.0);
      expect(restored.coordinates[3].utm, '650000450000');
    });

    // ── 7. toMap always includes all fields (no conditional) ──
    test('toMap always includes all fields regardless of value', () {
      final boundary = _makeBoundary(
        description: '',
        color: 'black',
        strokeWidth: 3.0,
      );
      final map = boundary.toMap();

      expect(map.containsKey('id'), true);
      expect(map.containsKey('areaId'), true);
      expect(map.containsKey('name'), true);
      expect(map.containsKey('description'), true);
      expect(map.containsKey('coordinates'), true);
      expect(map.containsKey('color'), true);
      expect(map.containsKey('strokeWidth'), true);
      expect(map.containsKey('createdAt'), true);
      expect(map.containsKey('updatedAt'), true);
    });

    // ── 8. strokeWidth null in fromMap falls back to 3.0 ──
    test('fromMap handles null strokeWidth with default 3.0', () {
      final map = <String, dynamic>{
        'id': 'b-4',
        'areaId': 'area-1',
        'name': 'test',
        'coordinates': [
          {'lat': 31.0, 'lng': 34.0, 'utm': '600000430000'},
        ],
        'strokeWidth': null,
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      };
      final boundary = Boundary.fromMap(map);
      expect(boundary.strokeWidth, 3.0);
    });
  });
}
