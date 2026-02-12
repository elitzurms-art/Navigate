import 'dart:async';

import 'database/tower_data_downloader.dart';
import 'database/tower_database.dart';
import 'engine/position_engine.dart';
import 'models/cell_position_result.dart';
import 'models/cell_tower_info.dart';
import 'models/tower_location.dart';
import 'platform/cell_tower_platform.dart';

/// Main service class for cell tower-based positioning.
///
/// Usage:
/// ```dart
/// final service = CellLocationService();
/// await service.initialize();
///
/// final position = await service.calculatePosition();
/// if (position != null) {
///   print('${position.lat}, ${position.lon} ± ${position.accuracyMeters}m');
/// }
/// ```
class CellLocationService {
  final TowerDatabase _database;
  final CellTowerPlatform _platform;
  final PositionEngine _engine;
  late final TowerDataDownloader _downloader;

  bool _initialized = false;

  CellLocationService({
    TowerDatabase? database,
    CellTowerPlatform? platform,
    PositionEngine? engine,
  })  : _database = database ?? TowerDatabase(),
        _platform = platform ?? CellTowerPlatform(),
        _engine = engine ?? PositionEngine() {
    _downloader = TowerDataDownloader(database: _database);
  }

  /// Whether the service has been initialized.
  bool get isInitialized => _initialized;

  /// Initializes the service by opening the tower database.
  Future<void> initialize() async {
    if (_initialized) return;
    await _database.initialize();
    _initialized = true;
  }

  /// Returns the list of currently visible cell towers from the device.
  Future<List<CellTowerInfo>> getVisibleTowers() async {
    return await _platform.getCellTowers();
  }

  /// Calculates the current position based on visible cell towers.
  ///
  /// Returns null if:
  /// - No cell towers are visible
  /// - None of the visible towers are in the local database
  /// - The positioning algorithm fails
  Future<CellPositionResult?> calculatePosition() async {
    _ensureInitialized();

    final towers = await getVisibleTowers();
    if (towers.isEmpty) return null;

    // Look up tower positions in the database
    final lookupResults = await _database.lookupTowers(towers);
    if (lookupResults.isEmpty) return null;

    // Build matched lists (only towers found in DB)
    final matchedTowers = <CellTowerInfo>[];
    final matchedLocations = <TowerLocation>[];

    for (final entry in lookupResults.entries) {
      matchedTowers.add(towers[entry.key]);
      matchedLocations.add(entry.value);
    }

    return _engine.calculate(
      towers: matchedTowers,
      locations: matchedLocations,
    );
  }

  /// Downloads tower data for a specific MCC (country code).
  ///
  /// [apiKey] - Your OpenCellID API key.
  /// [mcc] - Mobile Country Code (e.g., 425 for Israel, 310 for USA).
  Future<int> downloadTowerData({
    required String apiKey,
    required int mcc,
    void Function(int downloaded, int total)? onProgress,
  }) async {
    _ensureInitialized();
    return await _downloader.downloadByMcc(
      apiKey: apiKey,
      mcc: mcc,
      onProgress: onProgress,
    );
  }

  /// Downloads tower data for a geographic area.
  Future<int> downloadTowerDataByArea({
    required String apiKey,
    required double latMin,
    required double lonMin,
    required double latMax,
    required double lonMax,
  }) async {
    _ensureInitialized();
    return await _downloader.downloadByArea(
      apiKey: apiKey,
      latMin: latMin,
      lonMin: lonMin,
      latMax: latMax,
      lonMax: lonMax,
    );
  }

  /// Returns a stream of position updates at the given interval.
  Stream<CellPositionResult> positionStream({
    Duration interval = const Duration(seconds: 5),
  }) {
    late StreamController<CellPositionResult> controller;
    Timer? timer;

    controller = StreamController<CellPositionResult>(
      onListen: () {
        timer = Timer.periodic(interval, (_) async {
          try {
            final position = await calculatePosition();
            if (position != null && !controller.isClosed) {
              controller.add(position);
            }
          } catch (e) {
            if (!controller.isClosed) {
              controller.addError(e);
            }
          }
        });
      },
      onCancel: () {
        timer?.cancel();
        timer = null;
      },
    );

    return controller.stream;
  }

  /// Returns the number of towers in the local database.
  Future<int> towerCount({int? mcc}) async {
    _ensureInitialized();
    return await _database.countTowers(mcc: mcc);
  }

  /// Closes the service and releases resources.
  Future<void> dispose() async {
    _downloader.dispose();
    await _database.close();
    _initialized = false;
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError(
        'CellLocationService not initialized. Call initialize() first.',
      );
    }
  }
}
