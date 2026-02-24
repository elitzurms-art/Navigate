import 'dart:math';

import 'activity_classifier.dart';

/// Weinberg step length estimator with activity-aware multiplier.
///
/// Buffers accelerometer magnitude between step events and estimates
/// step length using: `stepLength = K * (aMax - aMin)^(1/4)`
///
/// When an [PdrActivityType] is provided to [onStep], a multiplier is
/// applied to better match running stride lengths.
///
/// Reference: Weinberg, H. (2002) "Using the ADXL202 in Pedometer
/// and Personal Navigation Applications"
class StepLengthEstimator {
  /// Weinberg constant K — empirically tuned.
  static const double _k = 0.41;

  /// Minimum samples required for a valid estimate.
  static const int _minSamples = 5;

  /// Clamp bounds for step length (meters).
  static const double _minStepLength = 0.3;
  static const double _maxStepLength = 1.8; // raised for running

  /// Default step length when insufficient data.
  static const double defaultStepLength = 0.7;

  /// Running multiplier — running strides are longer than walking strides.
  static const double _runningMultiplier = 1.4;

  /// Buffer of accelerometer magnitudes between step events.
  final List<double> _accelMagnitudes = [];

  /// Feed an accelerometer sample.
  ///
  /// Call this for every accelerometer event between steps.
  void onAccel(double x, double y, double z) {
    _accelMagnitudes.add(sqrt(x * x + y * y + z * z));
  }

  /// Compute step length from buffered accel data and clear the buffer.
  ///
  /// [activityType] — when [PdrActivityType.running], the Weinberg result is
  /// scaled by [_runningMultiplier] (~×1.4) to account for longer strides.
  /// When [PdrActivityType.standing], returns 0 (ZUPT handles this case).
  ///
  /// Returns [defaultStepLength] if fewer than [_minSamples] samples.
  double onStep({PdrActivityType? activityType}) {
    if (activityType == PdrActivityType.standing) {
      _accelMagnitudes.clear();
      return 0.0;
    }

    if (_accelMagnitudes.length < _minSamples) {
      _accelMagnitudes.clear();
      final base = defaultStepLength;
      return activityType == PdrActivityType.running
          ? (base * _runningMultiplier).clamp(_minStepLength, _maxStepLength)
          : base;
    }

    double aMax = _accelMagnitudes[0];
    double aMin = _accelMagnitudes[0];
    for (final m in _accelMagnitudes) {
      if (m > aMax) aMax = m;
      if (m < aMin) aMin = m;
    }

    _accelMagnitudes.clear();

    final diff = aMax - aMin;
    if (diff <= 0) return defaultStepLength;

    double stepLength = _k * pow(diff, 0.25);

    // Apply running multiplier
    if (activityType == PdrActivityType.running) {
      stepLength *= _runningMultiplier;
    }

    return stepLength.clamp(_minStepLength, _maxStepLength);
  }

  /// Clear all buffered data.
  void reset() {
    _accelMagnitudes.clear();
  }
}
