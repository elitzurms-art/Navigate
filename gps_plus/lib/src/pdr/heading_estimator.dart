import 'dart:math';

/// Estimates heading using a complementary filter combining gyroscope and magnetometer.
///
/// Formula: heading = alpha * (heading + gyro_yaw * dt) + (1 - alpha) * mag_heading
/// where alpha = 0.98 (gyro-dominant, mag corrects drift).
class HeadingEstimator {
  /// Complementary filter weight for gyroscope (0.98 = 98% gyro, 2% mag).
  static const double _alpha = 0.98;

  /// Current heading in radians (0 = north, increases clockwise).
  double _heading = 0.0;

  /// Whether the estimator has been initialized with a heading.
  bool _initialized = false;

  /// Last gyro timestamp in nanoseconds (for dt calculation).
  int? _lastGyroTimestamp;

  /// Current heading in radians.
  double get heading => _heading;

  /// Current heading in degrees (0-360).
  double get headingDegrees {
    double deg = _heading * 180.0 / pi;
    deg = deg % 360.0;
    if (deg < 0) deg += 360.0;
    return deg;
  }

  bool get isInitialized => _initialized;

  /// Update with gyroscope yaw rate.
  ///
  /// [yawRate] is the rotation rate around the Z axis in rad/s.
  /// [timestamp] is the sensor timestamp in nanoseconds.
  void updateGyro(double yawRate, int timestamp) {
    if (_lastGyroTimestamp != null && _initialized) {
      final dt = (timestamp - _lastGyroTimestamp!) / 1e9; // nanoseconds to seconds
      if (dt > 0 && dt < 1.0) {
        // Only apply if dt is reasonable (< 1 second gap)
        _heading = _heading + yawRate * dt;
      }
    }
    _lastGyroTimestamp = timestamp;
  }

  /// Update with magnetometer reading.
  ///
  /// Computes magnetic heading from horizontal components and applies
  /// complementary filter correction.
  void updateMag(double mx, double my, double mz) {
    // Compute magnetic heading from horizontal components
    // atan2(East, North) — for a flat device, mx ~ East, my ~ North
    final magHeading = atan2(mx, my);

    if (!_initialized) {
      _heading = magHeading;
      _initialized = true;
      return;
    }

    // Complementary filter: blend gyro-integrated heading with mag heading
    // Need to handle angle wrapping properly
    final diff = _wrapAngle(magHeading - _heading);
    _heading = _heading + (1 - _alpha) * diff;
    _heading = _wrapAngle(_heading);
  }

  /// Reset the heading estimator.
  void reset([double? initialHeading]) {
    if (initialHeading != null) {
      _heading = initialHeading;
      _initialized = true;
    } else {
      _heading = 0.0;
      _initialized = false;
    }
    _lastGyroTimestamp = null;
  }

  /// Wrap angle to [-pi, pi].
  static double _wrapAngle(double angle) {
    while (angle > pi) {
      angle -= 2 * pi;
    }
    while (angle < -pi) {
      angle += 2 * pi;
    }
    return angle;
  }
}
