import 'dart:math';

import '../models/cell_tower_info.dart';

/// Converts RSSI signal strength to estimated distance using
/// the log-distance path loss model.
///
/// Formula: distance = 10 ^ ((txPower - rssi) / (10 * n))
///
/// Where:
///  - txPower: transmit power of the tower in dBm
///  - rssi: received signal strength in dBm
///  - n: path loss exponent (environment-dependent)
class PathLossModel {
  /// Optional fixed path loss exponent override (for tests).
  /// When null, the exponent is chosen adaptively based on tower density.
  final double? pathLossExponentOverride;

  const PathLossModel({double? pathLossExponent})
      : pathLossExponentOverride = pathLossExponent;

  /// Default transmit power (dBm) for each cell type.
  static double txPowerForType(CellType type) {
    switch (type) {
      case CellType.gsm:
        return 43.0;
      case CellType.cdma:
        return 43.0;
      case CellType.umts:
        return 43.0;
      case CellType.lte:
        return 46.0;
      case CellType.nr:
        return 49.0;
    }
  }

  /// Estimates distance in meters from a cell tower based on RSSI.
  ///
  /// [visibleTowerCount] is used as an environment hint to adaptively choose
  /// the path loss exponent when no fixed override is set:
  /// - 5+ towers → 3.8 (dense urban)
  /// - 3-4 towers → 3.0 (suburban)
  /// - 1-2 towers → 2.5 (rural / open terrain)
  ///
  /// Returns the estimated distance, clamped to a minimum of 10m
  /// and a maximum of 50km to avoid unrealistic values.
  double estimateDistance({
    required int rssi,
    required CellType cellType,
    double? txPower,
    int visibleTowerCount = 3,
  }) {
    final tx = txPower ?? txPowerForType(cellType);
    final rssiDouble = rssi.toDouble();

    // Clamp RSSI to reasonable range
    final clampedRssi = rssiDouble.clamp(-140.0, -20.0);

    // Adaptive path loss exponent based on tower density
    final n = pathLossExponentOverride ?? _adaptiveExponent(visibleTowerCount);

    final exponent = (tx - clampedRssi) / (10.0 * n);
    final distance = pow(10.0, exponent).toDouble();

    // Clamp to realistic range
    return distance.clamp(10.0, 50000.0);
  }

  /// Choose path loss exponent based on visible tower count as environment proxy.
  static double _adaptiveExponent(int visibleTowerCount) {
    if (visibleTowerCount >= 5) return 3.8;   // dense urban
    if (visibleTowerCount >= 3) return 3.0;   // suburban
    return 2.5;                                // rural / open
  }
}
