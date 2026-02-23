import 'dart:math';

import '../models/pdr_position_result.dart';
import 'heading_estimator.dart';
import 'zupt_detector.dart';

/// Core PDR (Pedestrian Dead Reckoning) engine.
///
/// Processes sensor events (step detection + heading) and computes position
/// relative to a GPS anchor point. Accuracy degrades as steps accumulate.
class PdrEngine {
  final HeadingEstimator _headingEstimator = HeadingEstimator();
  final ZuptDetector _zupt = ZuptDetector();

  /// Default step length in meters (used when Weinberg estimator has insufficient data).
  static const double defaultStepLength = 0.7;

  // Anchor position (last known GPS fix)
  double? _anchorLat;
  double? _anchorLon;

  // Current estimated position
  double _currentLat = 0.0;
  double _currentLon = 0.0;

  // Step counter since last anchor
  int _stepCount = 0;

  // Total distance walked since last anchor (meters)
  double _totalDistance = 0.0;

  /// Whether a GPS anchor has been set.
  bool get hasAnchor => _anchorLat != null;

  /// Number of steps since last anchor.
  int get stepCount => _stepCount;

  /// Current heading in degrees.
  double get headingDegrees => _headingEstimator.headingDegrees;

  /// Whether the device is currently stationary (ZUPT).
  bool get isStationary => _zupt.isStationary;

  /// Set the anchor (reference) position from a GPS fix.
  ///
  /// Resets step count and drift accumulation.
  void setAnchor(double lat, double lon, {double? heading}) {
    _anchorLat = lat;
    _anchorLon = lon;
    _currentLat = lat;
    _currentLon = lon;
    _stepCount = 0;
    _totalDistance = 0.0;
    _zupt.reset();
    if (heading != null) {
      _headingEstimator.reset(heading * pi / 180.0);
    }
  }

  /// Process accelerometer event — feeds ZUPT detector.
  void onAccel(double x, double y, double z) {
    _zupt.onAccel(x, y, z);
  }

  /// Process a step event — advances position by one step in current heading direction.
  ///
  /// [stepLength] — estimated step length in meters (from Weinberg estimator).
  /// Falls back to [defaultStepLength] if not provided.
  void onStep({double? stepLength}) {
    if (!hasAnchor) return;
    if (!_headingEstimator.isInitialized) return;

    // ZUPT: suppress false steps when stationary
    if (!_zupt.shouldProcessStep()) return;

    _stepCount++;

    final effectiveStepLength = stepLength ?? defaultStepLength;
    _totalDistance += effectiveStepLength;

    // Convert heading to displacement in lat/lon
    final headingRad = _headingEstimator.heading;

    // Displacement in meters: north = cos(heading) * step, east = sin(heading) * step
    final dNorth = cos(headingRad) * effectiveStepLength;
    final dEast = sin(headingRad) * effectiveStepLength;

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

    // Feed ZUPT heading tracker for turn detection
    _zupt.onHeadingUpdate(_headingEstimator.heading, timestamp);
  }

  /// Process magnetometer event.
  void onMag(double x, double y, double z) {
    _headingEstimator.updateMag(x, y, z);
  }

  /// Estimated accuracy in meters — increases with distance and drift rate.
  double get estimatedAccuracy {
    return _totalDistance * _zupt.adaptiveDriftPerStep;
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

  /// Full reset — clears anchor, steps, heading, ZUPT.
  void reset() {
    _anchorLat = null;
    _anchorLon = null;
    _currentLat = 0.0;
    _currentLon = 0.0;
    _stepCount = 0;
    _totalDistance = 0.0;
    _headingEstimator.reset();
    _zupt.reset();
  }
}
