import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_plus/gps_plus_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final platform = MethodChannelGpsPlus();
  const channel = MethodChannel('gps_plus');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      channel,
      (MethodCall methodCall) async {
        if (methodCall.method == 'getCellTowers') {
          return [
            {
              'cid': 100,
              'lac': 200,
              'mcc': 425,
              'mnc': 1,
              'rssi': -80,
              'type': 'gsm',
              'timestamp': 1700000000000,
            }
          ];
        }
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('getCellTowers returns parsed tower list', () async {
    final towers = await platform.getCellTowers();
    expect(towers, hasLength(1));
    expect(towers.first['cid'], 100);
    expect(towers.first['mcc'], 425);
  });
}
