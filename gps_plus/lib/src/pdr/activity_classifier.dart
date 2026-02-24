import 'dart:collection';

/// Recognized activity types for PDR pipeline.
///
/// Named `PdrActivityType` to avoid conflict with `ActivityType` from
/// the `geolocator_apple` package (re-exported via `geolocator`).
enum PdrActivityType {
  /// No movement detected (ZUPT / standing still).
  standing,

  /// Normal walking pace (1.5–2.5 steps/sec).
  walking,

  /// Running pace (>2.5 steps/sec).
  running,
}

/// Sensor-based activity classifier — no Google Play Services dependency.
///
/// Classifies the user's current activity from step cadence and
/// accelerometer magnitude.  Runs entirely in Dart using data already
/// flowing through the PDR pipeline.
///
/// **Algorithm**
/// 1. Step cadence (steps/sec) from a sliding window of recent step timestamps.
/// 2. Accelerometer magnitude variance from a sliding window of recent samples.
/// 3. If no steps for [_standingTimeout] → [PdrActivityType.standing].
/// 4. If cadence > [_runningCadenceThreshold] **or** accel variance >
///    [_runningAccelVariance] → [PdrActivityType.running].
/// 5. Otherwise → [PdrActivityType.walking].
class ActivityClassifier {
  // ── Cadence thresholds ──────────────────────────────────────────
  /// Minimum cadence (steps/sec) to be considered running.
  static const double _runningCadenceThreshold = 2.5;

  /// Number of recent step timestamps to keep for cadence calculation.
  static const int _stepWindowSize = 10;

  // ── Accel thresholds ────────────────────────────────────────────
  /// Accel magnitude variance above which the user is likely running.
  static const double _runningAccelVariance = 8.0;

  /// Sliding window size for accel magnitude samples.
  static const int _accelWindowSize = 100;

  // ── Standing detection ──────────────────────────────────────────
  /// Duration without steps before classifying as standing.
  static const Duration _standingTimeout = Duration(seconds: 3);

  // ── Internal state ─────────────────────────────────────────────
  final Queue<DateTime> _stepTimestamps = Queue<DateTime>();
  final List<double> _accelMagnitudes = [];
  double _accelVariance = 0.0;
  DateTime? _lastStepTime;
  PdrActivityType _currentActivity = PdrActivityType.standing;

  /// The most recent classification result.
  PdrActivityType get currentActivity => _currentActivity;

  /// Current step cadence in steps per second (0 if unknown).
  double get cadence => _computeCadence();

  /// Current accelerometer magnitude variance.
  double get accelVariance => _accelVariance;

  // ── Public API ──────────────────────────────────────────────────

  /// Feed an accelerometer sample (m/s²).
  ///
  /// Call this for every accelerometer event.
  void onAccel(double x, double y, double z) {
    final mag = x * x + y * y + z * z; // squared magnitude (avoid sqrt)
    _accelMagnitudes.add(mag);
    if (_accelMagnitudes.length > _accelWindowSize) {
      _accelMagnitudes.removeAt(0);
    }
    _updateAccelVariance();
  }

  /// Notify the classifier that a step was detected.
  ///
  /// Call this on every native step event.
  void onStep() {
    final now = DateTime.now();
    _lastStepTime = now;
    _stepTimestamps.addLast(now);
    while (_stepTimestamps.length > _stepWindowSize) {
      _stepTimestamps.removeFirst();
    }
    _classify();
  }

  /// Re-classify without a new event (e.g. on a timer tick).
  ///
  /// Useful to transition to [PdrActivityType.standing] after inactivity.
  void tick() {
    _classify();
  }

  /// Clear all state.
  void reset() {
    _stepTimestamps.clear();
    _accelMagnitudes.clear();
    _accelVariance = 0.0;
    _lastStepTime = null;
    _currentActivity = PdrActivityType.standing;
  }

  // ── Private helpers ─────────────────────────────────────────────

  void _classify() {
    // Standing: no recent steps
    if (_lastStepTime == null ||
        DateTime.now().difference(_lastStepTime!) > _standingTimeout) {
      _currentActivity = PdrActivityType.standing;
      return;
    }

    final cad = _computeCadence();

    // Running: high cadence OR high accel variance
    if (cad >= _runningCadenceThreshold || _accelVariance >= _runningAccelVariance) {
      _currentActivity = PdrActivityType.running;
      return;
    }

    _currentActivity = PdrActivityType.walking;
  }

  double _computeCadence() {
    if (_stepTimestamps.length < 2) return 0.0;

    final span =
        _stepTimestamps.last.difference(_stepTimestamps.first).inMilliseconds /
            1000.0;
    if (span <= 0) return 0.0;

    // (steps - 1) intervals over the span
    return (_stepTimestamps.length - 1) / span;
  }

  void _updateAccelVariance() {
    if (_accelMagnitudes.length < 2) {
      _accelVariance = 0.0;
      return;
    }
    double sum = 0.0;
    for (final v in _accelMagnitudes) {
      sum += v;
    }
    final mean = sum / _accelMagnitudes.length;

    double sumSq = 0.0;
    for (final v in _accelMagnitudes) {
      final d = v - mean;
      sumSq += d * d;
    }
    _accelVariance = sumSq / _accelMagnitudes.length;
  }
}
