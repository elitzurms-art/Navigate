import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigate_app/domain/entities/checkpoint.dart';
import 'package:navigate_app/domain/entities/coordinate.dart';

void main() {
  final now = DateTime(2026, 3, 10, 12, 0, 0);

  Checkpoint makeCheckpoint({
    String id = 'cp1',
    String areaId = 'area1',
    String? boundaryId,
    String name = 'North Hill',
    String description = 'Rocky summit',
    String type = 'checkpoint',
    String color = 'blue',
    String geometryType = 'point',
    Coordinate? coordinates,
    List<Coordinate>? polygonCoordinates,
    int sequenceNumber = 1,
    List<String> labels = const [],
    String? unitId,
    String? frameworkId,
    bool isPublic = false,
    String createdBy = 'user1',
    DateTime? createdAt,
  }) {
    return Checkpoint(
      id: id,
      areaId: areaId,
      boundaryId: boundaryId,
      name: name,
      description: description,
      type: type,
      color: color,
      geometryType: geometryType,
      coordinates: coordinates,
      polygonCoordinates: polygonCoordinates,
      sequenceNumber: sequenceNumber,
      labels: labels,
      unitId: unitId,
      frameworkId: frameworkId,
      isPublic: isPublic,
      createdBy: createdBy,
      createdAt: createdAt ?? now,
    );
  }

  final sampleCoordinate = const Coordinate(lat: 31.5, lng: 34.75, utm: '123456789012');
  final polygonCoords = const [
    Coordinate(lat: 31.0, lng: 34.0, utm: '111111111111'),
    Coordinate(lat: 31.1, lng: 34.1, utm: '222222222222'),
    Coordinate(lat: 31.2, lng: 34.2, utm: '333333333333'),
  ];

  group('Checkpoint', () {
    // ---- toMap / fromMap roundtrip ----

    group('toMap / fromMap', () {
      test('roundtrip with point geometry preserves all fields', () {
        final cp = makeCheckpoint(
          boundaryId: 'b1',
          coordinates: sampleCoordinate,
          labels: ['A', 'B'],
          unitId: 'u1',
          frameworkId: 'f1',
          isPublic: true,
        );

        final map = cp.toMap();
        final restored = Checkpoint.fromMap(map);

        expect(restored.id, cp.id);
        expect(restored.areaId, cp.areaId);
        expect(restored.boundaryId, 'b1');
        expect(restored.name, cp.name);
        expect(restored.description, cp.description);
        expect(restored.type, cp.type);
        expect(restored.color, cp.color);
        expect(restored.geometryType, 'point');
        expect(restored.coordinates, sampleCoordinate);
        expect(restored.polygonCoordinates, isNull);
        expect(restored.sequenceNumber, cp.sequenceNumber);
        expect(restored.labels, ['A', 'B']);
        expect(restored.createdBy, cp.createdBy);
        expect(restored.createdAt, cp.createdAt);
      });

      test('roundtrip with polygon geometry preserves polygon coordinates', () {
        final cp = makeCheckpoint(
          geometryType: 'polygon',
          polygonCoordinates: polygonCoords,
        );

        final map = cp.toMap();
        final restored = Checkpoint.fromMap(map);

        expect(restored.geometryType, 'polygon');
        expect(restored.polygonCoordinates, isNotNull);
        expect(restored.polygonCoordinates!.length, 3);
        expect(restored.polygonCoordinates![0].lat, 31.0);
        expect(restored.polygonCoordinates![2].utm, '333333333333');
        expect(restored.coordinates, isNull);
      });

      test('fromMap applies defaults for missing optional fields', () {
        final map = {
          'id': 'cp2',
          'areaId': 'area1',
          'name': 'Test',
          'type': 'checkpoint',
          'color': 'blue',
          'sequenceNumber': 5,
          'createdBy': 'user1',
          'createdAt': now.toIso8601String(),
          // description, geometryType, labels all missing
        };

        final cp = Checkpoint.fromMap(map);

        expect(cp.description, '');
        expect(cp.geometryType, 'point');
        expect(cp.labels, isEmpty);
        expect(cp.boundaryId, isNull);
        expect(cp.coordinates, isNull);
        expect(cp.polygonCoordinates, isNull);
      });
    });

    // ---- Conditional fields in toMap ----

    group('toMap conditional fields', () {
      test('omits boundaryId when null', () {
        final map = makeCheckpoint(boundaryId: null).toMap();
        expect(map.containsKey('boundaryId'), isFalse);
      });

      test('includes boundaryId when present', () {
        final map = makeCheckpoint(boundaryId: 'b1').toMap();
        expect(map['boundaryId'], 'b1');
      });

      test('omits coordinates when null', () {
        final map = makeCheckpoint(coordinates: null).toMap();
        expect(map.containsKey('coordinates'), isFalse);
      });

      test('includes coordinates when present', () {
        final map = makeCheckpoint(coordinates: sampleCoordinate).toMap();
        expect(map.containsKey('coordinates'), isTrue);
        expect((map['coordinates'] as Map)['lat'], 31.5);
      });

      test('omits polygonCoordinates when null', () {
        final map = makeCheckpoint(polygonCoordinates: null).toMap();
        expect(map.containsKey('polygonCoordinates'), isFalse);
      });

      test('includes polygonCoordinates when present', () {
        final map = makeCheckpoint(polygonCoordinates: polygonCoords).toMap();
        expect(map.containsKey('polygonCoordinates'), isTrue);
        expect((map['polygonCoordinates'] as List).length, 3);
      });
    });

    // ---- colorForType ----

    group('colorForType', () {
      test('start returns green', () {
        expect(Checkpoint.colorForType('start'), 'green');
      });

      test('end returns red', () {
        expect(Checkpoint.colorForType('end'), 'red');
      });

      test('mandatory_passage returns yellow', () {
        expect(Checkpoint.colorForType('mandatory_passage'), 'yellow');
      });

      test('checkpoint returns blue', () {
        expect(Checkpoint.colorForType('checkpoint'), 'blue');
      });

      test('unknown type returns blue (default)', () {
        expect(Checkpoint.colorForType('something_else'), 'blue');
      });
    });

    // ---- flutterColor / flutterColorForType ----

    group('flutterColor and flutterColorForType', () {
      test('flutterColor maps known color strings', () {
        expect(Checkpoint.flutterColor('blue'), Colors.blue);
        expect(Checkpoint.flutterColor('green'), Colors.green);
        expect(Checkpoint.flutterColor('red'), Colors.red);
        expect(Checkpoint.flutterColor('yellow'), Colors.amber);
      });

      test('flutterColor returns blue for unknown string', () {
        expect(Checkpoint.flutterColor('purple'), Colors.blue);
      });

      test('flutterColorForType composes colorForType with flutterColor', () {
        expect(Checkpoint.flutterColorForType('start'), Colors.green);
        expect(Checkpoint.flutterColorForType('end'), Colors.red);
        expect(Checkpoint.flutterColorForType('mandatory_passage'), Colors.amber);
        expect(Checkpoint.flutterColorForType('checkpoint'), Colors.blue);
      });
    });

    // ---- Boolean getters ----

    group('type getters', () {
      test('isStart is true only for start type', () {
        expect(makeCheckpoint(type: 'start').isStart, isTrue);
        expect(makeCheckpoint(type: 'end').isStart, isFalse);
      });

      test('isEnd is true only for end type', () {
        expect(makeCheckpoint(type: 'end').isEnd, isTrue);
        expect(makeCheckpoint(type: 'checkpoint').isEnd, isFalse);
      });

      test('isMandatory is true only for mandatory_passage type', () {
        expect(makeCheckpoint(type: 'mandatory_passage').isMandatory, isTrue);
        expect(makeCheckpoint(type: 'start').isMandatory, isFalse);
      });

      test('isPolygon reflects geometryType', () {
        expect(makeCheckpoint(geometryType: 'polygon').isPolygon, isTrue);
        expect(makeCheckpoint(geometryType: 'point').isPolygon, isFalse);
      });
    });

    // ---- displayLabel ----

    group('displayLabel', () {
      test('prefers description over name', () {
        final cp = makeCheckpoint(
          sequenceNumber: 3,
          description: 'Rocky summit',
          name: 'North Hill',
        );
        expect(cp.displayLabel, '3 - Rocky summit');
      });

      test('falls back to name when description is empty', () {
        final cp = makeCheckpoint(
          sequenceNumber: 7,
          description: '',
          name: 'South Valley',
        );
        expect(cp.displayLabel, '7 - South Valley');
      });

      test('returns only sequenceNumber when both are empty', () {
        final cp = makeCheckpoint(
          sequenceNumber: 12,
          description: '',
          name: '',
        );
        expect(cp.displayLabel, '12');
      });
    });

    // ---- copyWith ----

    group('copyWith', () {
      test('changes specified fields and preserves the rest', () {
        final original = makeCheckpoint(
          name: 'Original',
          sequenceNumber: 1,
          coordinates: sampleCoordinate,
        );

        final copied = original.copyWith(
          name: 'Changed',
          sequenceNumber: 99,
        );

        expect(copied.name, 'Changed');
        expect(copied.sequenceNumber, 99);
        expect(copied.id, original.id);
        expect(copied.areaId, original.areaId);
        expect(copied.coordinates, sampleCoordinate);
      });

      test('boundaryId nullable pattern: can set to a value', () {
        final cp = makeCheckpoint(boundaryId: null);
        final updated = cp.copyWith(boundaryId: () => 'b_new');
        expect(updated.boundaryId, 'b_new');
      });

      test('boundaryId nullable pattern: can set to null', () {
        final cp = makeCheckpoint(boundaryId: 'b1');
        final updated = cp.copyWith(boundaryId: () => null);
        expect(updated.boundaryId, isNull);
      });

      test('boundaryId preserved when callback not provided', () {
        final cp = makeCheckpoint(boundaryId: 'b1');
        final updated = cp.copyWith(name: 'Other');
        expect(updated.boundaryId, 'b1');
      });
    });

    // ---- Equatable ----

    group('Equatable', () {
      test('two checkpoints with same fields are equal', () {
        final a = makeCheckpoint();
        final b = makeCheckpoint();
        expect(a, equals(b));
      });

      test('checkpoints with different id are not equal', () {
        final a = makeCheckpoint(id: 'cp1');
        final b = makeCheckpoint(id: 'cp2');
        expect(a, isNot(equals(b)));
      });

      test('checkpoints with different type are not equal', () {
        final a = makeCheckpoint(type: 'start');
        final b = makeCheckpoint(type: 'end');
        expect(a, isNot(equals(b)));
      });
    });
  });
}
