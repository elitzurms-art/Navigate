import 'dart:math';

/// Weinberg step length estimator.
///
/// Buffers accelerometer magnitude between step events and estimates
/// step length using: `stepLength = K * (aMax - aMin)^(1/4)`
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
  static const double _maxStepLength = 1.2;

  /// Default step length when insufficient data.
  static const double defaultStepLength = 0.7;

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
  /// Returns [defaultStepLength] if fewer than [_minSamples] samples.
  double onStep() {
    if (_accelMagnitudes.length < _minSamples) {
      _accelMagnitudes.clear();
      return defaultStepLength;
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

    final stepLength = _k * pow(diff, 0.25);
    return stepLength.clamp(_minStepLength, _maxStepLength);
  }

  /// Clear all buffered data.
  void reset() {
    _accelMagnitudes.clear();
  }
}
