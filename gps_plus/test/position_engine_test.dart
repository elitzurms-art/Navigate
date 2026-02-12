import 'package:flutter_test/flutter_test.dart';
import 'package:gps_plus/gps_plus.dart';

void main() {
  group('PositionEngine', () {
    final engine = PositionEngine();

    CellTowerInfo makeTower({
      required int cid,
      required int rssi,
      CellType type = CellType.lte,
    }) {
      return CellTowerInfo(
        cid: cid,
        lac: 100,
        mcc: 425,
        mnc: 1,
        rssi: rssi,
        type: type,
        timestamp: DateTime.now(),
      );
    }

    TowerLocation makeLocation({
      required int cid,
      required double lat,
      required double lon,
      int range = 1000,
    }) {
      return TowerLocation(
        mcc: 425,
        mnc: 1,
        lac: 100,
        cid: cid,
        lat: lat,
        lon: lon,
        range: range,
        type: 'LTE',
      );
    }

    test('returns null with empty inputs', () {
      final result = engine.calculate(towers: [], locations: []);
      expect(result, isNull);
    });

    test('returns null with mismatched list lengths', () {
      final result = engine.calculate(
        towers: [makeTower(cid: 1, rssi: -70)],
        locations: [],
      );
      expect(result, isNull);
    });

    test('uses weighted centroid for 1 tower', () {
      final result = engine.calculate(
        towers: [makeTower(cid: 1, rssi: -70)],
        locations: [makeLocation(cid: 1, lat: 32.08, lon: 34.78)],
      );

      expect(result, isNotNull);
      expect(result!.algorithm, PositionAlgorithm.weightedCentroid);
      expect(result.towerCount, 1);
    });

    test('uses weighted centroid for 2 towers', () {
      final result = engine.calculate(
        towers: [
          makeTower(cid: 1, rssi: -70),
          makeTower(cid: 2, rssi: -80),
        ],
        locations: [
          makeLocation(cid: 1, lat: 32.08, lon: 34.77),
          makeLocation(cid: 2, lat: 32.08, lon: 34.79),
        ],
      );

      expect(result, isNotNull);
      expect(result!.algorithm, PositionAlgorithm.weightedCentroid);
      expect(result.towerCount, 2);
    });

    test('uses trilateration for 3+ towers', () {
      final result = engine.calculate(
        towers: [
          makeTower(cid: 1, rssi: -70),
          makeTower(cid: 2, rssi: -80),
          makeTower(cid: 3, rssi: -75),
        ],
        locations: [
          makeLocation(cid: 1, lat: 32.09, lon: 34.77),
          makeLocation(cid: 2, lat: 32.07, lon: 34.79),
          makeLocation(cid: 3, lat: 32.08, lon: 34.76),
        ],
      );

      expect(result, isNotNull);
      expect(result!.algorithm, PositionAlgorithm.trilateration);
      expect(result.towerCount, 3);
    });

    test('result contains tower info', () {
      final towers = [
        makeTower(cid: 1, rssi: -70),
        makeTower(cid: 2, rssi: -80),
        makeTower(cid: 3, rssi: -75),
      ];
      final locations = [
        makeLocation(cid: 1, lat: 32.09, lon: 34.77),
        makeLocation(cid: 2, lat: 32.07, lon: 34.79),
        makeLocation(cid: 3, lat: 32.08, lon: 34.76),
      ];

      final result = engine.calculate(
        towers: towers,
        locations: locations,
      );

      expect(result, isNotNull);
      expect(result!.towersUsed, hasLength(3));
      expect(result.timestamp, isNotNull);
      expect(result.lat.isFinite, isTrue);
      expect(result.lon.isFinite, isTrue);
      expect(result.accuracyMeters >= 0, isTrue);
    });

    test('stronger signals produce position closer to those towers', () {
      // Two towers, one with much stronger signal
      final result = engine.calculate(
        towers: [
          makeTower(cid: 1, rssi: -50), // Very strong
          makeTower(cid: 2, rssi: -110), // Very weak
        ],
        locations: [
          makeLocation(cid: 1, lat: 32.08, lon: 34.77), // Close tower
          makeLocation(cid: 2, lat: 32.08, lon: 34.79), // Far tower
        ],
      );

      expect(result, isNotNull);
      // Position should be biased toward tower 1 (lon 34.77)
      expect(result!.lon, lessThan(34.78));
    });

    test('latLng convenience getter works', () {
      final result = engine.calculate(
        towers: [makeTower(cid: 1, rssi: -70)],
        locations: [makeLocation(cid: 1, lat: 32.08, lon: 34.78)],
      );

      expect(result, isNotNull);
      final latLng = result!.latLng;
      expect(latLng.latitude, result.lat);
      expect(latLng.longitude, result.lon);
    });
  });
}
