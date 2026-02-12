import 'package:flutter_test/flutter_test.dart';
import 'package:gps_plus/gps_plus.dart';

void main() {
  group('PathLossModel', () {
    const model = PathLossModel();

    test('returns reasonable distance for strong GSM signal', () {
      final distance = model.estimateDistance(
        rssi: -60,
        cellType: CellType.gsm,
      );
      // Strong signal = close to tower
      expect(distance, greaterThan(10));
      expect(distance, lessThan(5000));
    });

    test('returns larger distance for weak GSM signal', () {
      final distanceStrong = model.estimateDistance(
        rssi: -60,
        cellType: CellType.gsm,
      );
      final distanceWeak = model.estimateDistance(
        rssi: -100,
        cellType: CellType.gsm,
      );
      expect(distanceWeak, greaterThan(distanceStrong));
    });

    test('LTE has higher txPower than GSM', () {
      // Same RSSI but LTE has higher txPower, so distance is larger
      final gsmDist = model.estimateDistance(
        rssi: -80,
        cellType: CellType.gsm,
      );
      final lteDist = model.estimateDistance(
        rssi: -80,
        cellType: CellType.lte,
      );
      expect(lteDist, greaterThan(gsmDist));
    });

    test('5G NR has highest txPower', () {
      final lteDist = model.estimateDistance(
        rssi: -80,
        cellType: CellType.lte,
      );
      final nrDist = model.estimateDistance(
        rssi: -80,
        cellType: CellType.nr,
      );
      expect(nrDist, greaterThan(lteDist));
    });

    test('clamps distance to minimum 10m', () {
      final distance = model.estimateDistance(
        rssi: -20, // unrealistically strong
        cellType: CellType.gsm,
      );
      expect(distance, greaterThanOrEqualTo(10.0));
    });

    test('clamps distance to maximum 50km', () {
      final distance = model.estimateDistance(
        rssi: -140, // extremely weak
        cellType: CellType.gsm,
      );
      expect(distance, lessThanOrEqualTo(50000.0));
    });

    test('custom txPower overrides default', () {
      final defaultDist = model.estimateDistance(
        rssi: -80,
        cellType: CellType.gsm,
      );
      final customDist = model.estimateDistance(
        rssi: -80,
        cellType: CellType.gsm,
        txPower: 50.0,
      );
      expect(customDist, greaterThan(defaultDist));
    });

    test('different path loss exponents affect distance', () {
      const ruralModel = PathLossModel(pathLossExponent: 2.0);
      const urbanModel = PathLossModel(pathLossExponent: 4.0);

      final ruralDist = ruralModel.estimateDistance(
        rssi: -80,
        cellType: CellType.gsm,
      );
      final urbanDist = urbanModel.estimateDistance(
        rssi: -80,
        cellType: CellType.gsm,
      );

      // Lower path loss exponent = larger estimated distance
      expect(ruralDist, greaterThan(urbanDist));
    });

    test('txPowerForType returns expected values', () {
      expect(PathLossModel.txPowerForType(CellType.gsm), 43.0);
      expect(PathLossModel.txPowerForType(CellType.lte), 46.0);
      expect(PathLossModel.txPowerForType(CellType.nr), 49.0);
    });
  });
}
