import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'gps_plus_platform_interface.dart';

/// Method channel implementation of [GpsPlusPlatform].
class MethodChannelGpsPlus extends GpsPlusPlatform {
  @visibleForTesting
  final methodChannel = const MethodChannel('gps_plus');

  @override
  Future<List<Map<String, dynamic>>> getCellTowers() async {
    final result = await methodChannel.invokeListMethod<Map>('getCellTowers');
    if (result == null) return [];

    return result
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }
}
