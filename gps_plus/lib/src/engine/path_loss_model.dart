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
  /// Path loss exponent. Typical values:
  /// - 2.0: free space / rural
  /// - 2.7-3.5: urban
  /// - 3.0: suburban (default)
  /// - 4.0-6.0: dense urban / indoor
  final double pathLossExponent;

  const PathLossModel({this.pathLossExponent = 3.0});

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
  /// Returns the estimated distance, clamped to a minimum of 10m
  /// and a maximum of 50km to avoid unrealistic values.
  double estimateDistance({
    required int rssi,
    required CellType cellType,
    double? txPower,
  }) {
    final tx = txPower ?? txPowerForType(cellType);
    final rssiDouble = rssi.toDouble();

    // Clamp RSSI to reasonable range
    final clampedRssi = rssiDouble.clamp(-140.0, -20.0);

    final exponent = (tx - clampedRssi) / (10.0 * pathLossExponent);
    final distance = pow(10.0, exponent).toDouble();

    // Clamp to realistic range
    return distance.clamp(10.0, 50000.0);
  }
}
