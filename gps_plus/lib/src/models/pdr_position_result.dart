import 'package:latlong2/latlong.dart';

/// Result of a PDR (Pedestrian Dead Reckoning) position calculation.
class PdrPositionResult {
  final double lat;
  final double lon;

  /// Estimated accuracy in meters — degrades as steps accumulate from anchor.
  final double accuracyMeters;

  /// Number of steps taken since last anchor (GPS fix).
  final int stepCount;

  /// Current heading in degrees (0-360, north = 0).
  final double headingDegrees;

  final DateTime timestamp;

  /// Position source: 'pdr' for PDR only, 'pdrCellHybrid' for PDR+Cell weighted average.
  final String source;

  const PdrPositionResult({
    required this.lat,
    required this.lon,
    required this.accuracyMeters,
    required this.stepCount,
    required this.headingDegrees,
    required this.timestamp,
    required this.source,
  });

  LatLng get latLng => LatLng(lat, lon);

  PdrPositionResult copyWith({
    double? lat,
    double? lon,
    double? accuracyMeters,
    int? stepCount,
    double? headingDegrees,
    DateTime? timestamp,
    String? source,
  }) {
    return PdrPositionResult(
      lat: lat ?? this.lat,
      lon: lon ?? this.lon,
      accuracyMeters: accuracyMeters ?? this.accuracyMeters,
      stepCount: stepCount ?? this.stepCount,
      headingDegrees: headingDegrees ?? this.headingDegrees,
      timestamp: timestamp ?? this.timestamp,
      source: source ?? this.source,
    );
  }

  @override
  String toString() =>
      'PdrPositionResult(lat: $lat, lon: $lon, accuracy: ${accuracyMeters.toStringAsFixed(1)}m, '
      'steps: $stepCount, heading: ${headingDegrees.toStringAsFixed(0)}, source: $source)';
}
