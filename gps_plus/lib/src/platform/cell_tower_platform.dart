import '../../gps_plus_platform_interface.dart';
import '../models/cell_tower_info.dart';

/// Dart-side interface to the platform channel for retrieving cell tower info.
class CellTowerPlatform {
  /// Retrieves the list of currently visible cell towers from the native platform.
  Future<List<CellTowerInfo>> getCellTowers() async {
    final maps = await GpsPlusPlatform.instance.getCellTowers();

    return maps.map((m) => CellTowerInfo.fromMap(m)).toList();
  }
}
