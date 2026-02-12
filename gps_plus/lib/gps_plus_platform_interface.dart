import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'gps_plus_method_channel.dart';

abstract class GpsPlusPlatform extends PlatformInterface {
  GpsPlusPlatform() : super(token: _token);

  static final Object _token = Object();

  static GpsPlusPlatform _instance = MethodChannelGpsPlus();

  static GpsPlusPlatform get instance => _instance;

  static set instance(GpsPlusPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Returns a list of visible cell towers as maps.
  /// Each map contains: cid, lac, mcc, mnc, rssi, type.
  Future<List<Map<String, dynamic>>> getCellTowers() {
    throw UnimplementedError('getCellTowers() has not been implemented.');
  }
}
