import 'dart:math';

import '../models/pdr_position_result.dart';
import 'heading_estimator.dart';

/// Core PDR (Pedestrian Dead Reckoning) engine.
///
/// Processes sensor events (step detection + heading) and computes position
/// relative to a GPS anchor point. Accuracy degrades as steps accumulate.
class PdrEngine {
  final HeadingEstimator _headingEstimator = HeadingEstimator();

  /// Average step length in meters.
  static const double stepLength = 0.7;

  /// Drift rate per step — ~2% of step length.
  static const double _driftPerStep = 0.02;

  // Anchor position (last known GPS fix)
  double? _anchorLat;
  double? _anchorLon;

  // Current estimated position
  double _currentLat = 0.0;
  double _currentLon = 0.0;

  // Step counter since last anchor
  int _stepCount = 0;

  /// Whether a GPS anchor has been set.
  bool get hasAnchor => _anchorLat != null;

  /// Number of steps since last anchor.
  int get stepCount => _stepCount;

  /// Current heading in degrees.
  double get headingDegrees => _headingEstimator.headingDegrees;

  /// Set the anchor (reference) position from a GPS fix.
  ///
  /// Resets step count and drift accumulation.
  void setAnchor(double lat, double lon, {double? heading}) {
    _anchorLat = lat;
    _anchorLon = lon;
    _currentLat = lat;
    _currentLon = lon;
    _stepCount = 0;
    if (heading != null) {
      _headingEstimator.reset(heading * pi / 180.0);
    }
  }

  /// Process a step event — advances position by one step in current heading direction.
  void onStep() {
    if (!hasAnchor) return;
    if (!_headingEstimator.isInitialized) return;

    _stepCount++;

    // Convert heading to displacement in lat/lon
    final headingRad = _headingEstimator.heading;

    // Displacement in meters: north = cos(heading) * step, east = sin(heading) * step
    final dNorth = cos(headingRad) * stepLength;
    final dEast = sin(headingRad) * stepLength;

    // Convert meters to degrees
    // 1 degree latitude ~ 111,320 meters
    // 1 degree longitude ~ 111,320 * cos(latitude) meters
    _currentLat += dNorth / 111320.0;
    _currentLon += dEast / (111320.0 * cos(_currentLat * pi / 180.0));
  }

  /// Process gyroscope event.
  void onGyro(double x, double y, double z, int timestamp) {
    // Z-axis rotation = yaw (heading change for a roughly flat device)
    _headingEstimator.updateGyro(z, timestamp);
  }

  /// Process magnetometer event.
  void onMag(double x, double y, double z) {
    _headingEstimator.updateMag(x, y, z);
  }

  /// Estimated accuracy in meters — increases with step count.
  double get estimatedAccuracy {
    return _stepCount * _driftPerStep * stepLength;
  }

  /// Current PDR position result, or null if no anchor is set.
  PdrPositionResult? get currentPosition {
    if (!hasAnchor) return null;

    return PdrPositionResult(
      lat: _currentLat,
      lon: _currentLon,
      accuracyMeters: estimatedAccuracy.clamp(1.0, 500.0),
      stepCount: _stepCount,
      headingDegrees: _headingEstimator.headingDegrees,
      timestamp: DateTime.now(),
      source: 'pdr',
    );
  }

  /// Full reset — clears anchor, steps, heading.
  void reset() {
    _anchorLat = null;
    _anchorLon = null;
    _currentLat = 0.0;
    _currentLon = 0.0;
    _stepCount = 0;
    _headingEstimator.reset();
  }
}
