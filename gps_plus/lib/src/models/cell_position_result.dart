import 'package:latlong2/latlong.dart';

import 'cell_tower_info.dart';

/// The algorithm used to calculate the position.
enum PositionAlgorithm {
  trilateration,
  weightedCentroid,
}

/// Result of a cell tower-based position calculation.
class CellPositionResult {
  /// Calculated latitude
  final double lat;

  /// Calculated longitude
  final double lon;

  /// Estimated accuracy in meters
  final double accuracyMeters;

  /// Number of towers used in the calculation
  final int towerCount;

  /// Algorithm used for the calculation
  final PositionAlgorithm algorithm;

  /// The cell towers that were used
  final List<CellTowerInfo> towersUsed;

  /// Timestamp of the calculation
  final DateTime timestamp;

  const CellPositionResult({
    required this.lat,
    required this.lon,
    required this.accuracyMeters,
    required this.towerCount,
    required this.algorithm,
    required this.towersUsed,
    required this.timestamp,
  });

  /// Convenience getter for a LatLng object.
  LatLng get latLng => LatLng(lat, lon);

  @override
  String toString() =>
      'CellPositionResult(lat: $lat, lon: $lon, '
      'accuracy: ${accuracyMeters.toStringAsFixed(0)}m, '
      'towers: $towerCount, algorithm: ${algorithm.name})';
}
