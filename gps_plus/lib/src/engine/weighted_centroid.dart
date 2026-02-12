import 'package:latlong2/latlong.dart';

/// Weighted centroid algorithm for position estimation when fewer than
/// 3 towers are available.
///
/// Uses inverse-square distance weighting to compute a weighted average
/// of tower positions.
class WeightedCentroid {
  const WeightedCentroid();

  /// Calculates a weighted centroid position from tower locations and distances.
  ///
  /// [towers] - List of known tower positions.
  /// [distances] - Corresponding estimated distances in meters.
  /// [ranges] - Known range of each tower in meters (from DB).
  ///
  /// Returns the estimated position, or null if no towers are provided.
  WeightedCentroidResult? calculate({
    required List<LatLng> towers,
    required List<double> distances,
    required List<int> ranges,
  }) {
    if (towers.isEmpty || towers.length != distances.length) {
      return null;
    }

    double totalWeight = 0;
    double weightedLat = 0;
    double weightedLon = 0;
    double weightedRange = 0;

    for (var i = 0; i < towers.length; i++) {
      // Weight = 1 / distance^2 (inverse square law)
      // Use a minimum distance of 100m to prevent division issues
      final dist = distances[i].clamp(100.0, double.infinity);
      final weight = 1.0 / (dist * dist);

      weightedLat += towers[i].latitude * weight;
      weightedLon += towers[i].longitude * weight;
      weightedRange += ranges[i] * weight;
      totalWeight += weight;
    }

    if (totalWeight == 0) return null;

    final lat = weightedLat / totalWeight;
    final lon = weightedLon / totalWeight;
    final accuracy = weightedRange / totalWeight;

    return WeightedCentroidResult(
      position: LatLng(lat, lon),
      accuracyMeters: accuracy,
    );
  }
}

/// Result from weighted centroid calculation.
class WeightedCentroidResult {
  final LatLng position;
  final double accuracyMeters;

  const WeightedCentroidResult({
    required this.position,
    required this.accuracyMeters,
  });
}
