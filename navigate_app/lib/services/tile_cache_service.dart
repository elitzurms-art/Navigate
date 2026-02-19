import 'dart:async';
import 'dart:math' as math;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:latlong2/latlong.dart';
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

  // ─── Broadcast stream for UI state updates ───
  final _stateController = StreamController<void>.broadcast();
  Stream<void> get onStateChanged => _stateController.stream;

  void _notifyStateChanged() {
    if (!_stateController.isClosed) {
      _stateController.add(null);
    }
  }

  // ─── Region download state ───
  bool isRegionDownloading = false;
  int regionDownloadedTiles = 0;
  int regionTotalTiles = 0;
  int regionFailedTiles = 0;
  StreamSubscription<DownloadProgress>? _regionSub;

  // ─── Israel download state ───
  bool isIsraelDownloading = false;
  int israelDownloadedTiles = 0;
  int israelTotalTiles = 0;
  int israelFailedTiles = 0;
  String israelCurrentType = '';
  int israelTypesCompleted = 0;
  StreamSubscription<DownloadProgress>? _israelSub;
  bool _israelCancelled = false;

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

  /// הורדת אריחים לאזור מסוים (low-level — מחזיר stream)
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

  // ─── Managed region download (persists across screen navigation) ───

  /// התחלת הורדת אזור מנוהלת
  void startRegionDownload({
    required LatLngBounds bounds,
    required MapType mapType,
    required int minZoom,
    required int maxZoom,
  }) {
    if (isRegionDownloading) return;

    regionDownloadedTiles = 0;
    regionTotalTiles = countTiles(bounds: bounds, minZoom: minZoom, maxZoom: maxZoom);
    regionFailedTiles = 0;
    isRegionDownloading = true;
    _notifyStateChanged();

    _regionSub = downloadRegion(
      bounds: bounds,
      mapType: mapType,
      minZoom: minZoom,
      maxZoom: maxZoom,
    ).listen(
      (progress) {
        regionDownloadedTiles = progress.cachedTiles + progress.skippedTiles;
        regionTotalTiles = progress.maxTiles;
        regionFailedTiles = progress.failedTiles;
        if (progress.isComplete) {
          isRegionDownloading = false;
          _regionSub = null;
        }
        _notifyStateChanged();
      },
      onError: (error) {
        print('DEBUG TileCacheService: region download error: $error');
        isRegionDownloading = false;
        _regionSub = null;
        _notifyStateChanged();
      },
      onDone: () {
        isRegionDownloading = false;
        _regionSub = null;
        _notifyStateChanged();
      },
    );
  }

  /// ביטול הורדת אזור
  void cancelRegionDownload() {
    _regionSub?.cancel();
    _regionSub = null;
    isRegionDownloading = false;
    _notifyStateChanged();
  }

  // ─── Managed Israel download (persists across screen navigation) ───

  /// התחלת הורדת מפות ישראל מנוהלת
  Future<void> startIsraelDownload({
    required int minZoom,
    required int maxZoom,
  }) async {
    if (isIsraelDownloading) return;

    final mapConfig = MapConfig();
    const b = MapConfig.israelBounds;
    final bounds = LatLngBounds(
      LatLng(b.minLat, b.minLng),
      LatLng(b.maxLat, b.maxLng),
    );

    // חישוב סך אריחים
    int total = 0;
    for (final type in MapType.values) {
      final maxZ = maxZoom.clamp(0, mapConfig.maxZoom(type).toInt());
      total += countTiles(bounds: bounds, minZoom: minZoom, maxZoom: maxZ);
    }

    israelDownloadedTiles = 0;
    israelTotalTiles = total;
    israelFailedTiles = 0;
    israelTypesCompleted = 0;
    isIsraelDownloading = true;
    _israelCancelled = false;
    _notifyStateChanged();

    int cumulativeDownloaded = 0;
    int cumulativeFailed = 0;

    for (final type in MapType.values) {
      if (_israelCancelled) break;

      final maxZ = maxZoom.clamp(0, mapConfig.maxZoom(type).toInt());
      israelCurrentType = mapConfig.label(type);
      _notifyStateChanged();

      final completer = Completer<void>();
      _israelSub = downloadRegion(
        bounds: bounds,
        mapType: type,
        minZoom: minZoom,
        maxZoom: maxZ,
      ).listen(
        (progress) {
          israelDownloadedTiles = cumulativeDownloaded +
              progress.cachedTiles + progress.skippedTiles;
          israelFailedTiles = cumulativeFailed + progress.failedTiles;
          if (progress.isComplete && !completer.isCompleted) {
            cumulativeDownloaded += progress.cachedTiles + progress.skippedTiles;
            cumulativeFailed += progress.failedTiles;
            israelTypesCompleted++;
            completer.complete();
          }
          _notifyStateChanged();
        },
        onError: (error) {
          print('DEBUG TileCacheService: Israel download error ($type): $error');
          if (!completer.isCompleted) completer.complete();
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
      );

      await completer.future;
    }

    isIsraelDownloading = false;
    _israelSub = null;
    _notifyStateChanged();
  }

  /// ביטול הורדת מפות ישראל
  void cancelIsraelDownload() {
    _israelCancelled = true;
    _israelSub?.cancel();
    _israelSub = null;
    isIsraelDownloading = false;
    _notifyStateChanged();
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
