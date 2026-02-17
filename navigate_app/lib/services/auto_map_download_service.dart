import 'dart:async';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import '../core/map_config.dart';
import '../core/utils/geometry_utils.dart';
import '../data/repositories/boundary_repository.dart';
import '../domain/entities/navigation.dart';
import 'tile_cache_service.dart';

/// הורדת מפות אוטומטית כשניווט עובר למצב למידה — singleton
class AutoMapDownloadService {
  static final AutoMapDownloadService _instance =
      AutoMapDownloadService._internal();
  factory AutoMapDownloadService() => _instance;
  AutoMapDownloadService._internal();

  final _triggeredNavIds = <String>{};
  final _activeDownloads = <String, StreamSubscription>{};

  /// הפעלת הורדה עבור ניווט — מדלג אם כבר הופעל
  Future<void> triggerDownload(Navigation navigation) async {
    if (_triggeredNavIds.contains(navigation.id)) return;
    _triggeredNavIds.add(navigation.id);

    final boundaryId = navigation.boundaryLayerId;
    if (boundaryId == null || boundaryId.isEmpty) {
      print('DEBUG AutoMapDownload: no boundary for nav ${navigation.id}');
      return;
    }

    try {
      final boundary = await BoundaryRepository().getById(boundaryId);
      if (boundary == null || boundary.coordinates.isEmpty) {
        print('DEBUG AutoMapDownload: boundary $boundaryId not found or empty');
        return;
      }

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

      print('DEBUG AutoMapDownload: starting download for nav ${navigation.id}');

      for (final (mapType, minZoom, maxZoom) in mapTypes) {
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
            if (progress.percentageProgress % 25 < 1) {
              print(
                  'DEBUG AutoMapDownload: $label ${progress.percentageProgress.toStringAsFixed(0)}%');
            }
          },
          onDone: () {
            print('DEBUG AutoMapDownload: $label done');
            completer.complete();
          },
          onError: (e) {
            print('DEBUG AutoMapDownload: $label error: $e');
            completer.complete();
          },
        );

        _activeDownloads[navigation.id] = sub;
        await completer.future;
      }

      _activeDownloads.remove(navigation.id);
      print('DEBUG AutoMapDownload: all downloads complete for nav ${navigation.id}');
    } catch (e) {
      print('DEBUG AutoMapDownload: error: $e');
      _activeDownloads.remove(navigation.id);
    }
  }

  /// ביטול הורדה פעילה
  void cancelDownload(String navigationId) {
    _activeDownloads[navigationId]?.cancel();
    _activeDownloads.remove(navigationId);
    _triggeredNavIds.remove(navigationId);
  }
}
