import 'dart:async';
import 'dart:math' as math;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import '../core/map_config.dart';

/// שירות cache אריחי מפה — singleton
/// מבוסס על FMTC (flutter_map_tile_caching) עם ObjectBox backend
class TileCacheService {
  static final TileCacheService _instance = TileCacheService._internal();
  factory TileCacheService() => _instance;
  TileCacheService._internal();

  static const _storeName = 'navigate_cache';
  bool _initialized = false;
  int _nextInstanceId = 0;

  /// אתחול — קריאה חד-פעמית ב-main.dart
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      await FMTCObjectBoxBackend().initialise();
      final store = FMTCStore(_storeName);
      if (!await store.manage.ready) {
        await store.manage.create();
      }
      _initialized = true;
      print('DEBUG TileCacheService: initialized successfully');
    } catch (e) {
      print('DEBUG TileCacheService: init error: $e');
    }
  }

  /// מחזיר TileProvider עם browse caching — cacheFirst
  TileProvider getTileProvider() {
    if (!_initialized) {
      return NetworkTileProvider();
    }
    return FMTCStore(_storeName).getTileProvider(
      settings: FMTCTileProviderSettings(
        behavior: CacheBehavior.cacheFirst,
        cachedValidDuration: const Duration(days: 30),
        setInstance: false,
      ),
    );
  }

  /// הורדת אריחים לאזור מסוים
  Stream<DownloadProgress> downloadRegion({
    required LatLngBounds bounds,
    required MapType mapType,
    required int minZoom,
    required int maxZoom,
  }) {
    if (!_initialized) {
      return const Stream.empty();
    }

    final config = MapConfig();
    final region = RectangleRegion(bounds);
    final downloadable = region.toDownloadable(
      minZoom: minZoom,
      maxZoom: maxZoom,
      options: TileLayer(
        urlTemplate: config.urlTemplate(mapType),
        userAgentPackageName: MapConfig.userAgentPackageName,
      ),
    );

    final instanceId = _nextInstanceId++;
    return FMTCStore(_storeName).download.startForeground(
      region: downloadable,
      parallelThreads: 3,
      skipExistingTiles: true,
      skipSeaTiles: true,
      instanceId: instanceId,
    );
  }

  /// ספירת אריחים צפויה להורדה (חישוב מתמטי לפי slippy map)
  int countTiles({
    required LatLngBounds bounds,
    required int minZoom,
    required int maxZoom,
  }) {
    int total = 0;
    for (int z = minZoom; z <= maxZoom; z++) {
      final n = 1 << z; // 2^z
      final xMin = ((bounds.west + 180) / 360 * n).floor();
      final xMax = ((bounds.east + 180) / 360 * n).floor();
      final yMin = _latToTileY(bounds.north, z);
      final yMax = _latToTileY(bounds.south, z);
      total += (xMax - xMin + 1) * (yMax - yMin + 1);
    }
    return total;
  }

  static int _latToTileY(double lat, int zoom) {
    final n = 1 << zoom;
    final latRad = lat * math.pi / 180;
    return ((1 - math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) /
            2 *
            n)
        .floor();
  }

  /// סטטיסטיקות — מספר אריחים וגודל
  Future<({int tileCount, double sizeMB})> getStoreStats() async {
    if (!_initialized) return (tileCount: 0, sizeMB: 0.0);
    try {
      final stats = await FMTCStore(_storeName).stats.all;
      return (
        tileCount: stats.length,
        sizeMB: stats.size / 1024, // KiB → MiB
      );
    } catch (e) {
      print('DEBUG TileCacheService: stats error: $e');
      return (tileCount: 0, sizeMB: 0.0);
    }
  }

  /// ניקוי כל ה-cache
  Future<void> clearCache() async {
    if (!_initialized) return;
    try {
      await FMTCStore(_storeName).manage.reset();
      print('DEBUG TileCacheService: cache cleared');
    } catch (e) {
      print('DEBUG TileCacheService: clear error: $e');
    }
  }
}
