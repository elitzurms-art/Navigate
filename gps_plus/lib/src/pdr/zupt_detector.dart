import 'dart:math';

/// Zero-velocity Update (ZUPT) detector.
///
/// Detects stationarity from accelerometer variance and adapts
/// drift rate based on motion state (stationary, straight walking, turning).
class ZuptDetector {
  /// Sliding window size for variance calculation.
  static const int _windowSize = 50;

  /// Variance threshold — below this the user is stationary.
  /// Gravity ~9.81 m/s², walking variance typically > 0.5.
  static const double _stationaryVarianceThreshold = 0.15;

  /// Base drift rate per step (straight walking).
  static const double _baseDrift = 0.02;

  /// Maximum drift rate per step (sharp turns).
  static const double _maxDrift = 0.06;

  /// Heading change rate threshold (rad/s) for turn detection.
  static const double _turnThreshold = 0.3;

  // Sliding window of accel magnitudes
  final List<double> _accelWindow = [];
  double _variance = 0.0;

  // Heading change tracking
  double? _lastHeading;
  int? _lastHeadingTimestamp;
  double _headingChangeRate = 0.0;

  /// Whether the device is currently stationary.
  bool get isStationary => _variance < _stationaryVarianceThreshold;

  /// Whether the user is turning (heading changing rapidly).
  bool get _isTurning => _headingChangeRate.abs() > _turnThreshold;

  /// Feed an accelerometer sample.
  void onAccel(double x, double y, double z) {
    final magnitude = sqrt(x * x + y * y + z * z);

    _accelWindow.add(magnitude);
    if (_accelWindow.length > _windowSize) {
      _accelWindow.removeAt(0);
    }

    _updateVariance();
  }

  /// Track heading changes for turn detection.
  ///
  /// [headingRad] — current heading in radians.
  /// [timestampNanos] — sensor timestamp in nanoseconds.
  void onHeadingUpdate(double headingRad, int timestampNanos) {
    if (_lastHeading != null && _lastHeadingTimestamp != null) {
      final dt = (timestampNanos - _lastHeadingTimestamp!) / 1e9;
      if (dt > 0 && dt < 1.0) {
        var diff = headingRad - _lastHeading!;
        // Wrap to [-pi, pi]
        while (diff > pi) {
          diff -= 2 * pi;
        }
        while (diff < -pi) {
          diff += 2 * pi;
        }
        _headingChangeRate = diff / dt;
      }
    }
    _lastHeading = headingRad;
    _lastHeadingTimestamp = timestampNanos;
  }

  /// Whether the current step should be processed.
  ///
  /// Returns `false` when stationary — suppresses false step detections.
  bool shouldProcessStep() {
    return !isStationary;
  }

  /// Adaptive drift rate per step based on motion state.
  ///
  /// - Stationary: 0.0 (no drift accumulation)
  /// - Straight walking: [_baseDrift] (~0.02)
  /// - Turning: up to [_maxDrift] (~0.06, 3x base)
  double get adaptiveDriftPerStep {
    if (isStationary) return 0.0;

    if (_isTurning) {
      // Scale linearly from baseDrift to maxDrift based on turn rate
      final turnFactor =
          ((_headingChangeRate.abs() - _turnThreshold) / _turnThreshold)
              .clamp(0.0, 1.0);
      return _baseDrift + (_maxDrift - _baseDrift) * turnFactor;
    }

    return _baseDrift;
  }

  /// Clear all state.
  void reset() {
    _accelWindow.clear();
    _variance = 0.0;
    _lastHeading = null;
    _lastHeadingTimestamp = null;
    _headingChangeRate = 0.0;
  }

  /// Compute variance of the sliding window.
  void _updateVariance() {
    if (_accelWindow.length < 2) {
      _variance = 0.0;
      return;
    }

    double sum = 0.0;
    for (final v in _accelWindow) {
      sum += v;
    }
    final mean = sum / _accelWindow.length;

    double sumSqDiff = 0.0;
    for (final v in _accelWindow) {
      final diff = v - mean;
      sumSqDiff += diff * diff;
    }
    _variance = sumSqDiff / _accelWindow.length;
  }
}
