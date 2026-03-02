import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../core/map_config.dart';
import '../domain/entities/map_download_record.dart';

/// שירות cache אריחי מפה — singleton
/// מבוסס על FMTC (flutter_map_tile_caching) עם ObjectBox backend
class TileCacheService {
  static final TileCacheService _instance = TileCacheService._internal();
  factory TileCacheService() => _instance;
  TileCacheService._internal();

  static const _storeName = 'navigate_cache';
  static const _recordsKey = 'map_download_records';
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

  // ─── Download records ───
  List<MapDownloadRecord> _records = [];
  List<MapDownloadRecord> get records => List.unmodifiable(_records);
  String? _activeRegionRecordId;
  final Map<String, String> _israelRecordIds = {}; // mapType.name → recordId

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
      await _loadRecords();
      // סימון הורדות שנקטעו כ-failed
      _markStaleDownloadsAsFailed();
      print('DEBUG TileCacheService: initialized successfully');
    } catch (e) {
      print('DEBUG TileCacheService: init error: $e');
    }
  }

  // ─── Records persistence ───

  Future<void> _loadRecords() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_recordsKey);
      if (json != null) {
        final list = jsonDecode(json) as List;
        _records = list
            .map((e) => MapDownloadRecord.fromMap(e as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      print('DEBUG TileCacheService: load records error: $e');
    }
  }

  Future<void> _saveRecords() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_records.map((r) => r.toMap()).toList());
      await prefs.setString(_recordsKey, json);
    } catch (e) {
      print('DEBUG TileCacheService: save records error: $e');
    }
  }

  void _markStaleDownloadsAsFailed() {
    bool changed = false;
    _records = _records.map((r) {
      if (r.status == 'downloading') {
        changed = true;
        return r.copyWith(status: 'failed');
      }
      return r;
    }).toList();
    if (changed) _saveRecords();
  }

  void _updateRecord(String id, MapDownloadRecord Function(MapDownloadRecord) updater) {
    final idx = _records.indexWhere((r) => r.id == id);
    if (idx == -1) return;
    _records[idx] = updater(_records[idx]);
    _saveRecords();
    _notifyStateChanged();
  }

  /// הסרת רשומת הורדה
  void removeRecord(String id) {
    _records.removeWhere((r) => r.id == id);
    _saveRecords();
    _notifyStateChanged();
  }

  static String _boundsToJson(LatLngBounds bounds) {
    return jsonEncode({
      'south': bounds.south,
      'west': bounds.west,
      'north': bounds.north,
      'east': bounds.east,
    });
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
    String boundaryName = '',
    String? existingRecordId,
  }) {
    if (isRegionDownloading) return;

    regionDownloadedTiles = 0;
    regionTotalTiles = countTiles(bounds: bounds, minZoom: minZoom, maxZoom: maxZoom);
    regionFailedTiles = 0;
    isRegionDownloading = true;

    // יצירת/עדכון רשומה
    if (existingRecordId != null) {
      _activeRegionRecordId = existingRecordId;
      _updateRecord(existingRecordId, (r) => r.copyWith(
        status: 'downloading',
        downloadedTiles: 0,
        failedTiles: 0,
      ));
    } else {
      final record = MapDownloadRecord(
        id: const Uuid().v4(),
        boundaryName: boundaryName,
        mapType: mapType.name,
        minZoom: minZoom,
        maxZoom: maxZoom,
        status: 'downloading',
        totalTiles: regionTotalTiles,
        downloadedTiles: 0,
        failedTiles: 0,
        createdAt: DateTime.now().toIso8601String(),
        boundsJson: _boundsToJson(bounds),
      );
      _records.add(record);
      _activeRegionRecordId = record.id;
      _saveRecords();
    }

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

        // עדכון רשומה
        if (_activeRegionRecordId != null) {
          final idx = _records.indexWhere((r) => r.id == _activeRegionRecordId);
          if (idx != -1) {
            _records[idx] = _records[idx].copyWith(
              downloadedTiles: regionDownloadedTiles,
              totalTiles: regionTotalTiles,
              failedTiles: regionFailedTiles,
            );
          }
        }

        if (progress.isComplete) {
          isRegionDownloading = false;
          _regionSub = null;
          if (_activeRegionRecordId != null) {
            _updateRecord(_activeRegionRecordId!, (r) => r.copyWith(
              status: 'completed',
              downloadedTiles: regionDownloadedTiles,
              totalTiles: regionTotalTiles,
              failedTiles: regionFailedTiles,
            ));
            _activeRegionRecordId = null;
          }
        }
        _notifyStateChanged();
      },
      onError: (error) {
        print('DEBUG TileCacheService: region download error: $error');
        isRegionDownloading = false;
        _regionSub = null;
        if (_activeRegionRecordId != null) {
          _updateRecord(_activeRegionRecordId!, (r) => r.copyWith(
            status: 'failed',
            downloadedTiles: regionDownloadedTiles,
            failedTiles: regionFailedTiles,
          ));
          _activeRegionRecordId = null;
        }
        _notifyStateChanged();
      },
      onDone: () {
        if (isRegionDownloading) {
          // onDone ללא isComplete — נכשל או בוטל
          isRegionDownloading = false;
          _regionSub = null;
          if (_activeRegionRecordId != null) {
            _updateRecord(_activeRegionRecordId!, (r) => r.copyWith(
              status: 'failed',
              downloadedTiles: regionDownloadedTiles,
              failedTiles: regionFailedTiles,
            ));
            _activeRegionRecordId = null;
          }
          _notifyStateChanged();
        }
      },
    );
  }

  /// ביטול הורדת אזור
  void cancelRegionDownload() {
    _regionSub?.cancel();
    _regionSub = null;
    isRegionDownloading = false;
    if (_activeRegionRecordId != null) {
      _updateRecord(_activeRegionRecordId!, (r) => r.copyWith(
        status: 'failed',
        downloadedTiles: regionDownloadedTiles,
        failedTiles: regionFailedTiles,
      ));
      _activeRegionRecordId = null;
    }
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
    final boundsJson = _boundsToJson(bounds);

    // חישוב סך אריחים + יצירת רשומות
    int total = 0;
    _israelRecordIds.clear();
    for (final type in MapType.values) {
      final maxZ = maxZoom.clamp(0, mapConfig.maxZoom(type).toInt());
      final typeTiles = countTiles(bounds: bounds, minZoom: minZoom, maxZoom: maxZ);
      total += typeTiles;

      final record = MapDownloadRecord(
        id: const Uuid().v4(),
        boundaryName: 'ישראל',
        mapType: type.name,
        minZoom: minZoom,
        maxZoom: maxZ,
        status: 'downloading',
        totalTiles: typeTiles,
        downloadedTiles: 0,
        failedTiles: 0,
        createdAt: DateTime.now().toIso8601String(),
        boundsJson: boundsJson,
      );
      _records.add(record);
      _israelRecordIds[type.name] = record.id;
    }
    await _saveRecords();

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

      final recordId = _israelRecordIds[type.name];

      final completer = Completer<void>();
      _israelSub = downloadRegion(
        bounds: bounds,
        mapType: type,
        minZoom: minZoom,
        maxZoom: maxZ,
      ).listen(
        (progress) {
          final typeDownloaded = progress.cachedTiles + progress.skippedTiles;
          israelDownloadedTiles = cumulativeDownloaded + typeDownloaded;
          israelFailedTiles = cumulativeFailed + progress.failedTiles;

          // עדכון רשומת הסוג הנוכחי
          if (recordId != null) {
            final idx = _records.indexWhere((r) => r.id == recordId);
            if (idx != -1) {
              _records[idx] = _records[idx].copyWith(
                downloadedTiles: typeDownloaded,
                failedTiles: progress.failedTiles,
              );
            }
          }

          if (progress.isComplete && !completer.isCompleted) {
            cumulativeDownloaded += typeDownloaded;
            cumulativeFailed += progress.failedTiles;
            israelTypesCompleted++;
            if (recordId != null) {
              _updateRecord(recordId, (r) => r.copyWith(
                status: 'completed',
                downloadedTiles: typeDownloaded,
                failedTiles: progress.failedTiles,
              ));
            }
            completer.complete();
          }
          _notifyStateChanged();
        },
        onError: (error) {
          print('DEBUG TileCacheService: Israel download error ($type): $error');
          if (recordId != null) {
            _updateRecord(recordId, (r) => r.copyWith(status: 'failed'));
          }
          if (!completer.isCompleted) completer.complete();
        },
        onDone: () {
          if (!completer.isCompleted) {
            // onDone ללא complete — נכשל
            if (recordId != null) {
              _updateRecord(recordId, (r) =>
                r.status == 'downloading' ? r.copyWith(status: 'failed') : r);
            }
            completer.complete();
          }
        },
      );

      await completer.future;
    }

    // סימון סוגים שלא הורדו (בגלל ביטול) כ-failed
    if (_israelCancelled) {
      for (final entry in _israelRecordIds.entries) {
        final idx = _records.indexWhere((r) => r.id == entry.value);
        if (idx != -1 && _records[idx].status == 'downloading') {
          _records[idx] = _records[idx].copyWith(status: 'failed');
        }
      }
      _saveRecords();
    }

    isIsraelDownloading = false;
    _israelSub = null;
    _israelRecordIds.clear();
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

  /// חידוש הורדה שנכשלה
  void resumeDownload(MapDownloadRecord record) {
    if (isRegionDownloading || isIsraelDownloading) return;

    final boundsMap = record.boundsMap;
    final bounds = LatLngBounds(
      LatLng(boundsMap['south']!, boundsMap['west']!),
      LatLng(boundsMap['north']!, boundsMap['east']!),
    );
    final mapType = MapType.values.firstWhere(
      (t) => t.name == record.mapType,
      orElse: () => MapType.standard,
    );

    startRegionDownload(
      bounds: bounds,
      mapType: mapType,
      minZoom: record.minZoom,
      maxZoom: record.maxZoom,
      boundaryName: record.boundaryName,
      existingRecordId: record.id,
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

  /// ניקוי כל ה-cache + רשומות
  Future<void> clearCache() async {
    if (!_initialized) return;
    try {
      await FMTCStore(_storeName).manage.reset();
      _records.clear();
      await _saveRecords();
      _notifyStateChanged();
      print('DEBUG TileCacheService: cache cleared');
    } catch (e) {
      print('DEBUG TileCacheService: clear error: $e');
    }
  }
}
