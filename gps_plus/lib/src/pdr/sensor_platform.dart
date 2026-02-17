import 'package:flutter/services.dart';

/// Dart wrapper for the native sensor EventChannel and MethodChannel.
///
/// Provides a stream of raw sensor events from Android hardware sensors
/// (step detector, accelerometer, gyroscope, magnetometer).
class SensorPlatform {
  static const MethodChannel _methodChannel = MethodChannel('gps_plus');
  static const EventChannel _eventChannel = EventChannel('gps_plus/sensors');

  Stream<Map<String, dynamic>>? _sensorStream;

  /// Stream of sensor events from the native side.
  ///
  /// Each event is a Map with keys:
  /// - `type`: 'step', 'accel', 'gyro', or 'mag'
  /// - `timestamp`: native timestamp (nanoseconds)
  /// - `x`, `y`, `z`: sensor values (for accel/gyro/mag)
  Stream<Map<String, dynamic>> get sensorStream {
    _sensorStream ??= _eventChannel
        .receiveBroadcastStream()
        .map((event) => Map<String, dynamic>.from(event as Map));
    return _sensorStream!;
  }

  /// Start listening to sensors on the native side.
  Future<void> startSensors() async {
    await _methodChannel.invokeMethod<bool>('startSensors');
  }

  /// Stop listening to sensors on the native side.
  Future<void> stopSensors() async {
    await _methodChannel.invokeMethod<bool>('stopSensors');
  }

  /// Check if the device has the required sensors for PDR.
  Future<bool> hasSensors() async {
    final result = await _methodChannel.invokeMethod<bool>('hasSensors');
    return result ?? false;
  }
}
