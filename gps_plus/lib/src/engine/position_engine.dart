import 'package:latlong2/latlong.dart';

import '../models/cell_position_result.dart';
import '../models/cell_tower_info.dart';
import '../models/tower_location.dart';
import 'path_loss_model.dart';
import 'trilateration.dart';
import 'weighted_centroid.dart';

/// Orchestrates position calculation by selecting the best algorithm
/// based on the number of available towers.
///
/// - 3+ towers with known positions → trilateration
/// - 1-2 towers → weighted centroid
/// - 0 towers → null (no fix)
class PositionEngine {
  final PathLossModel _pathLossModel;
  final Trilateration _trilateration;
  final WeightedCentroid _weightedCentroid;

  PositionEngine({
    PathLossModel? pathLossModel,
    Trilateration? trilateration,
    WeightedCentroid? weightedCentroid,
  })  : _pathLossModel = pathLossModel ?? const PathLossModel(),
        _trilateration = trilateration ?? const Trilateration(),
        _weightedCentroid = weightedCentroid ?? const WeightedCentroid();

  /// Calculates position from visible towers and their known locations.
  ///
  /// [towers] - Visible cell towers with signal strength.
  /// [locations] - Corresponding known tower positions from the database.
  ///
  /// Each entry in [towers] must have a corresponding entry in [locations]
  /// at the same index.
  CellPositionResult? calculate({
    required List<CellTowerInfo> towers,
    required List<TowerLocation> locations,
  }) {
    if (towers.isEmpty || towers.length != locations.length) {
      return null;
    }

    // Estimate distances from RSSI
    final distances = <double>[];
    final towerPositions = <LatLng>[];
    final ranges = <int>[];

    for (var i = 0; i < towers.length; i++) {
      final distance = _pathLossModel.estimateDistance(
        rssi: towers[i].rssi,
        cellType: towers[i].type,
      );
      distances.add(distance);
      towerPositions.add(LatLng(locations[i].lat, locations[i].lon));
      ranges.add(locations[i].range);
    }

    if (towers.length >= 3) {
      // Use trilateration for 3+ towers
      final result = _trilateration.calculate(
        towers: towerPositions,
        distances: distances,
      );

      if (result != null) {
        return CellPositionResult(
          lat: result.position.latitude,
          lon: result.position.longitude,
          accuracyMeters: result.accuracyMeters,
          towerCount: towers.length,
          algorithm: PositionAlgorithm.trilateration,
          towersUsed: towers,
          timestamp: DateTime.now(),
        );
      }

      // Fall through to weighted centroid if trilateration fails
      // (e.g., collinear towers)
    }

    // Use weighted centroid for 1-2 towers or trilateration fallback
    final result = _weightedCentroid.calculate(
      towers: towerPositions,
      distances: distances,
      ranges: ranges,
    );

    if (result == null) return null;

    return CellPositionResult(
      lat: result.position.latitude,
      lon: result.position.longitude,
      accuracyMeters: result.accuracyMeters,
      towerCount: towers.length,
      algorithm: PositionAlgorithm.weightedCentroid,
      towersUsed: towers,
      timestamp: DateTime.now(),
    );
  }
}
