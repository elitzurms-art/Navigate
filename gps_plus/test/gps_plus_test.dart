import 'package:flutter_test/flutter_test.dart';
import 'package:gps_plus/gps_plus_platform_interface.dart';
import 'package:gps_plus/gps_plus_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockGpsPlusPlatform
    with MockPlatformInterfaceMixin
    implements GpsPlusPlatform {
  @override
  Future<List<Map<String, dynamic>>> getCellTowers() async {
    return [
      {
        'cid': 12345,
        'lac': 100,
        'mcc': 425,
        'mnc': 1,
        'rssi': -75,
        'type': 'lte',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      }
    ];
  }
}

void main() {
  final GpsPlusPlatform initialPlatform = GpsPlusPlatform.instance;

  test('MethodChannelGpsPlus is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelGpsPlus>());
  });

  test('getCellTowers returns tower data', () async {
    final fakePlatform = MockGpsPlusPlatform();
    GpsPlusPlatform.instance = fakePlatform;

    final towers = await GpsPlusPlatform.instance.getCellTowers();
    expect(towers, hasLength(1));
    expect(towers.first['cid'], 12345);
    expect(towers.first['mcc'], 425);
  });
}
