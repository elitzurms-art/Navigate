import 'dart:async';

import '../models/pdr_position_result.dart';
import 'pdr_engine.dart';
import 'sensor_platform.dart';

/// PDR (Pedestrian Dead Reckoning) service — manages sensor lifecycle and position stream.
///
/// Usage:
/// ```dart
/// final pdr = PdrService();
/// if (await pdr.isAvailable) {
///   await pdr.start();
///   pdr.setAnchor(lat, lon);
///   pdr.positionStream.listen((pos) => print(pos));
/// }
/// ```
class PdrService {
  final SensorPlatform _sensorPlatform = SensorPlatform();
  final PdrEngine _engine = PdrEngine();

  StreamSubscription<Map<String, dynamic>>? _sensorSubscription;
  final StreamController<PdrPositionResult> _positionController =
      StreamController<PdrPositionResult>.broadcast();

  bool _running = false;

  /// Whether the PDR service is currently running.
  bool get isRunning => _running;

  /// Whether the device has the required sensors for PDR.
  Future<bool> get isAvailable => _sensorPlatform.hasSensors();

  /// Stream of PDR position updates (emitted on each step).
  Stream<PdrPositionResult> get positionStream => _positionController.stream;

  /// Current PDR position, or null if not tracking or no anchor.
  PdrPositionResult? get currentPosition => _engine.currentPosition;

  /// Number of steps since last anchor.
  int get stepCount => _engine.stepCount;

  /// Current heading in degrees.
  double get headingDegrees => _engine.headingDegrees;

  /// Start the PDR service — registers sensors and begins listening.
  Future<void> start() async {
    if (_running) return;

    await _sensorPlatform.startSensors();

    _sensorSubscription = _sensorPlatform.sensorStream.listen(_onSensorEvent);
    _running = true;
    print('DEBUG PdrService: started');
  }

  /// Stop the PDR service — unregisters sensors and stops listening.
  void stop() {
    if (!_running) return;

    _sensorSubscription?.cancel();
    _sensorSubscription = null;
    _sensorPlatform.stopSensors();
    _running = false;
    print('DEBUG PdrService: stopped');
  }

  /// Set the anchor (reference) position from a GPS fix.
  ///
  /// This resets the step count and drift. Call this whenever you get
  /// a good GPS fix (accuracy < 20m) to keep PDR accurate.
  void setAnchor(double lat, double lon, {double? heading}) {
    _engine.setAnchor(lat, lon, heading: heading);
    print('DEBUG PdrService: anchor set at $lat, $lon (steps reset)');
  }

  /// Full reset — clears anchor, steps, heading.
  void reset() {
    _engine.reset();
  }

  /// Dispose the service — stops and closes stream.
  void dispose() {
    stop();
    _positionController.close();
  }

  /// Handle a sensor event from the native side.
  void _onSensorEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    if (type == null) return;

    switch (type) {
      case 'step':
        _engine.onStep();
        // Emit position on each step
        final pos = _engine.currentPosition;
        if (pos != null && !_positionController.isClosed) {
          _positionController.add(pos);
        }
      case 'gyro':
        final x = (event['x'] as num).toDouble();
        final y = (event['y'] as num).toDouble();
        final z = (event['z'] as num).toDouble();
        final timestamp = (event['timestamp'] as num).toInt();
        _engine.onGyro(x, y, z, timestamp);
      case 'mag':
        final x = (event['x'] as num).toDouble();
        final y = (event['y'] as num).toDouble();
        final z = (event['z'] as num).toDouble();
        _engine.onMag(x, y, z);
      case 'accel':
        // Reserved for future Weinberg step length estimation
        break;
    }
  }
}
