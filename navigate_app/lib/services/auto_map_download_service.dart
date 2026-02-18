import 'dart:async';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import '../core/map_config.dart';
import '../core/utils/geometry_utils.dart';
import '../data/repositories/boundary_repository.dart';
import '../data/repositories/navigation_repository.dart';
import '../domain/entities/navigation.dart';
import 'tile_cache_service.dart';

/// תוצאת ניסיון הורדה
enum AutoDownloadResult {
  started,
  alreadyDone,
  noBoundary,
  boundaryNotSynced,
}

/// סטטוס הורדה לניווט
enum MapDownloadStatus {
  notStarted,
  downloading,
  completed,
  failed,
}

/// הורדת מפות אוטומטית כשניווט עובר למצב למידה — singleton
class AutoMapDownloadService {
  static final AutoMapDownloadService _instance =
      AutoMapDownloadService._internal();
  factory AutoMapDownloadService() => _instance;
  AutoMapDownloadService._internal();

  final _triggeredNavIds = <String>{};
  final _activeDownloads = <String, StreamSubscription>{};

  /// סטטוס הורדה לכל ניווט
  final _downloadStatus = <String, MapDownloadStatus>{};

  /// אחוז התקדמות (0.0 - 1.0)
  final _downloadProgress = <String, double>{};

  /// ניווטים שממתינים לגבול — boundaryId → set של navigation IDs
  final _pendingBoundaryNavs = <String, Set<String>>{};

  /// callback להודעות UI (SnackBar) — מוגדר ע"י המסך הפעיל
  void Function(String message, {bool isError})? onStatusMessage;

  /// קבלת סטטוס הורדה לניווט
  MapDownloadStatus getStatus(String navigationId) {
    return _downloadStatus[navigationId] ?? MapDownloadStatus.notStarted;
  }

  /// קבלת אחוז התקדמות (0.0-1.0)
  double getProgress(String navigationId) {
    return _downloadProgress[navigationId] ?? 0.0;
  }

  /// האם ההורדה פעילה כרגע
  bool isDownloading(String navigationId) {
    return _activeDownloads.containsKey(navigationId);
  }

  /// הפעלת הורדה עבור ניווט — מדלג אם כבר הופעל בהצלחה
  Future<AutoDownloadResult> triggerDownload(Navigation navigation) async {
    if (_triggeredNavIds.contains(navigation.id)) {
      return AutoDownloadResult.alreadyDone;
    }

    final boundaryId = navigation.boundaryLayerId;
    if (boundaryId == null || boundaryId.isEmpty) {
      print('DEBUG AutoMapDownload: no boundary for nav ${navigation.id}');
      return AutoDownloadResult.noBoundary;
    }

    try {
      final boundary = await BoundaryRepository().getById(boundaryId);
      if (boundary == null || boundary.coordinates.isEmpty) {
        print(
            'DEBUG AutoMapDownload: boundary $boundaryId not found or empty — will retry when synced');
        // רישום לretry כשהגבול יסונכרן
        _pendingBoundaryNavs
            .putIfAbsent(boundaryId, () => {})
            .add(navigation.id);
        return AutoDownloadResult.boundaryNotSynced;
      }

      // סימון רק אחרי שהגבול נמצא — כדי לאפשר retry
      _triggeredNavIds.add(navigation.id);
      _downloadStatus[navigation.id] = MapDownloadStatus.downloading;
      _downloadProgress[navigation.id] = 0.0;
      // ניקוי מרשימת הממתינים
      _pendingBoundaryNavs[boundaryId]?.remove(navigation.id);

      // חישוב bounding box עם padding
      final bbox = GeometryUtils.getBoundingBox(boundary.coordinates);
      const padding = 0.01; // ~1km padding
      final bounds = LatLngBounds(
        LatLng(bbox.minLat - padding, bbox.minLng - padding),
        LatLng(bbox.maxLat + padding, bbox.maxLng + padding),
      );

      final tileCache = TileCacheService();
      final mapTypes = [
        (MapType.standard, 12, 19),
        (MapType.topographic, 12, 17),
        (MapType.satellite, 12, 19),
      ];

      final totalTiles = mapTypes.fold<int>(
        0,
        (sum, t) => sum + tileCache.countTiles(
          bounds: bounds,
          minZoom: t.$2,
          maxZoom: t.$3,
        ),
      );

      print('DEBUG AutoMapDownload: starting download for nav ${navigation.id}');
      onStatusMessage?.call('מוריד מפות אופליין (~$totalTiles אריחים)...');

      int completedTiles = 0;

      for (int i = 0; i < mapTypes.length; i++) {
        final (mapType, minZoom, maxZoom) = mapTypes[i];
        final label = MapConfig().label(mapType);
        final tileCount = tileCache.countTiles(
          bounds: bounds,
          minZoom: minZoom,
          maxZoom: maxZoom,
        );
        print('DEBUG AutoMapDownload: $label — $tileCount tiles (z$minZoom-$maxZoom)');

        final completer = Completer<void>();
        final sub = tileCache
            .downloadRegion(
              bounds: bounds,
              mapType: mapType,
              minZoom: minZoom,
              maxZoom: maxZoom,
            )
            .listen(
          (progress) {
            // עדכון התקדמות כוללת
            final currentTiles = completedTiles +
                (progress.percentageProgress / 100 * tileCount).round();
            _downloadProgress[navigation.id] =
                totalTiles > 0 ? currentTiles / totalTiles : 0.0;
            if (progress.percentageProgress % 25 < 1) {
              print(
                  'DEBUG AutoMapDownload: $label ${progress.percentageProgress.toStringAsFixed(0)}%');
            }
          },
          onDone: () {
            completedTiles += tileCount;
            print('DEBUG AutoMapDownload: $label done');
            completer.complete();
          },
          onError: (e) {
            completedTiles += tileCount;
            print('DEBUG AutoMapDownload: $label error: $e');
            completer.complete();
          },
        );

        _activeDownloads[navigation.id] = sub;
        await completer.future;
      }

      _activeDownloads.remove(navigation.id);
      _downloadStatus[navigation.id] = MapDownloadStatus.completed;
      _downloadProgress[navigation.id] = 1.0;
      print('DEBUG AutoMapDownload: all downloads complete for nav ${navigation.id}');
      onStatusMessage?.call('הורדת מפות אופליין הושלמה');
      return AutoDownloadResult.started;
    } catch (e) {
      print('DEBUG AutoMapDownload: error: $e — will retry later');
      _activeDownloads.remove(navigation.id);
      _triggeredNavIds.remove(navigation.id);
      _downloadStatus[navigation.id] = MapDownloadStatus.failed;
      onStatusMessage?.call('שגיאה בהורדת מפות — ינסה שוב', isError: true);
      return AutoDownloadResult.started;
    }
  }

  /// איפוס סטטוס כדי לאפשר הורדה ידנית מחדש
  void resetForManualDownload(String navigationId) {
    _triggeredNavIds.remove(navigationId);
    _downloadStatus.remove(navigationId);
    _downloadProgress.remove(navigationId);
  }

  /// נקרא כשגבול סונכרן מ-Firestore — בודק אם יש ניווטים שממתינים לו
  Future<void> onBoundarySynced(String boundaryId) async {
    final pendingNavIds = _pendingBoundaryNavs.remove(boundaryId);
    if (pendingNavIds == null || pendingNavIds.isEmpty) return;

    print('DEBUG AutoMapDownload: boundary $boundaryId synced — retrying ${pendingNavIds.length} pending navs');

    final navRepo = NavigationRepository();
    for (final navId in pendingNavIds) {
      final nav = await navRepo.getById(navId);
      final retryStatuses = {'learning', 'system_check', 'waiting'};
      if (nav != null && retryStatuses.contains(nav.status)) {
        triggerDownload(nav);
      }
    }
  }

  /// ביטול הורדה פעילה
  void cancelDownload(String navigationId) {
    _activeDownloads[navigationId]?.cancel();
    _activeDownloads.remove(navigationId);
    _triggeredNavIds.remove(navigationId);
    _downloadStatus[navigationId] = MapDownloadStatus.failed;
  }
}
