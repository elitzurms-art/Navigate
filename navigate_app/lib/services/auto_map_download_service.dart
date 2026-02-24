import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import '../core/map_config.dart';
import '../core/utils/geometry_utils.dart';
import '../data/repositories/boundary_repository.dart';
import '../data/repositories/navigation_repository.dart';
import '../domain/entities/navigation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'tile_cache_service.dart';
import 'map_download_notification_service.dart';
import 'background_location_service.dart';

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
  interrupted, // הורדה הופסקה — תמשיך אוטומטית
}

/// הורדת מפות אוטומטית כשניווט עובר למצב למידה — singleton
/// משתמש ב-foreground service כדי שההורדה תמשיך גם כשהמסך כבוי
class AutoMapDownloadService with WidgetsBindingObserver {
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

  /// שמירת ניווטים להמשך הורדה אחרי חזרה מרקע
  final _navigationCache = <String, Navigation>{};

  /// completer פעיל לכל ניווט — לביטול נקי
  final _activeCompleters = <String, Completer<void>>{};

  /// מונה epoch למניעת race conditions בין הורדות ישנות לחדשות
  final _downloadEpoch = <String, int>{};

  bool _lifecycleRegistered = false;

  /// callback להודעות UI (SnackBar) — מוגדר ע"י המסך הפעיל
  void Function(String message, {bool isError})? onStatusMessage;

  // ─── Prompt / Approval tracking ───

  /// ניווטים שכבר הוצג להם דיאלוג הורדה (מפתח = navId או navId_systemcheck)
  final _promptedKeys = <String>{};

  /// ניווטים שהמשתמש אישר הורדה
  final _approvedNavIds = <String>{};

  /// האם הדיאלוג כבר הוצג עבור מפתח זה
  bool hasBeenPrompted(String key) => _promptedKeys.contains(key);

  /// סימון שהדיאלוג הוצג
  void markPrompted(String key) => _promptedKeys.add(key);

  /// סימון שהמשתמש אישר הורדה
  void markApproved(String navId) => _approvedNavIds.add(navId);

  /// האם המשתמש אישר הורדה
  bool isApproved(String navId) => _approvedNavIds.contains(navId);

  /// אחוז אחרון שדווח ל-notification (throttling)
  int _lastNotifiedPercent = -1;

  final _notificationService = MapDownloadNotificationService();

  // ─── Foreground service — שומר את התהליך חי ברקע ───

  /// האם אנחנו הפעלנו את ה-foreground service (ולא ה-GPS tracking)
  bool _ownsForegroundService = false;

  /// הפעלת foreground service אם לא רץ — כדי שההורדה תמשיך עם מסך כבוי/אפליקציה ברקע
  /// אם GPS tracking כבר רץ (BackgroundLocationService) — פשוט נרכב על השירות הקיים
  Future<void> _ensureForegroundService() async {
    // אם GPS foreground service כבר רץ — לא צריך להפעיל, התהליך כבר חי
    if (BackgroundLocationService().isRunning) return;

    try {
      final result = await FlutterForegroundTask.startService(
        notificationTitle: 'מוריד מפות אופליין',
        notificationText: 'ההורדה מתבצעת ברקע...',
        callback: _mapDownloadServiceCallback,
      );
      if (result is ServiceRequestSuccess) {
        _ownsForegroundService = true;
        print('DEBUG AutoMapDownload: started foreground service for download');
      }
    } catch (e) {
      print('DEBUG AutoMapDownload: failed to start foreground service: $e');
    }
  }

  /// עצירת foreground service רק אם אנחנו הפעלנו אותו (לא GPS tracking)
  Future<void> _releaseForegroundService() async {
    if (_ownsForegroundService) {
      try {
        await FlutterForegroundTask.stopService();
      } catch (_) {}
      _ownsForegroundService = false;
      print('DEBUG AutoMapDownload: stopped foreground service after download');
    }
  }

  // ─── Lifecycle observer ───

  void _ensureLifecycleObserver() {
    if (!_lifecycleRegistered) {
      WidgetsBinding.instance.addObserver(this);
      _lifecycleRegistered = true;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _onAppPaused();
    } else if (state == AppLifecycleState.resumed) {
      _onAppResumed();
    }
  }

  /// כשהאפליקציה עוברת לרקע — ההורדה ממשיכה בזכות ה-foreground service
  void _onAppPaused() {
    if (_activeDownloads.isNotEmpty) {
      print('DEBUG AutoMapDownload: app paused — download continues via foreground service');
    }
  }

  /// כשהאפליקציה חוזרת — אם ההורדה הופסקה (OS הרג), ננסה לחדש
  void _onAppResumed() {
    if (_activeDownloads.isNotEmpty) {
      // עדיין רץ — הכל טוב
      return;
    }

    // בדיקה אם יש הורדות שהופסקו (OS הרג את ה-service)
    Future.delayed(const Duration(seconds: 2), () {
      final toResume = _navigationCache.entries
          .where((e) =>
              _downloadStatus[e.key] == MapDownloadStatus.interrupted &&
              !_activeDownloads.containsKey(e.key))
          .map((e) => e.value)
          .toList();

      if (toResume.isEmpty) return;

      print('DEBUG AutoMapDownload: app resumed — resuming ${toResume.length} interrupted downloads');
      for (final nav in toResume) {
        onStatusMessage?.call('ממשיך הורדת מפות אופליין...');
        final pct = ((_downloadProgress[nav.id] ?? 0.0) * 100).round();
        _notificationService.showProgress(pct, 100);
        triggerDownload(nav);
      }
    });
  }

  // ─── Public API ───

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

  /// הפעלת הורדה עבור ניווט — מדלג אם כבר הושלם בהצלחה
  Future<AutoDownloadResult> triggerDownload(Navigation navigation) async {
    if (_triggeredNavIds.contains(navigation.id)) {
      return AutoDownloadResult.alreadyDone;
    }

    // מניעת הורדות מקבילות לאותו ניווט
    if (_activeDownloads.containsKey(navigation.id)) {
      return AutoDownloadResult.alreadyDone;
    }

    final boundaryId = navigation.boundaryLayerId;
    if (boundaryId == null || boundaryId.isEmpty) {
      print('DEBUG AutoMapDownload: no boundary for nav ${navigation.id}');
      return AutoDownloadResult.noBoundary;
    }

    _ensureLifecycleObserver();
    _navigationCache[navigation.id] = navigation;

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

      // הפעלת foreground service כדי שההורדה תמשיך ברקע
      await _ensureForegroundService();

      // לא מוסיפים ל-_triggeredNavIds עד שההורדה באמת מושלמת
      _downloadStatus[navigation.id] = MapDownloadStatus.downloading;
      _downloadProgress[navigation.id] ??= 0.0;
      // ניקוי מרשימת הממתינים
      _pendingBoundaryNavs[boundaryId]?.remove(navigation.id);

      // שמירת epoch נוכחי לזיהוי ביטולים
      final myEpoch = _downloadEpoch[navigation.id] ?? 0;

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

      final isResume = (_downloadProgress[navigation.id] ?? 0.0) > 0.01;
      if (!isResume) {
        print('DEBUG AutoMapDownload: starting download for nav ${navigation.id}');
        onStatusMessage?.call('מוריד מפות אופליין (~$totalTiles אריחים)...');
      } else {
        print('DEBUG AutoMapDownload: resuming download for nav ${navigation.id}');
      }

      // הצגת notification — ממשיך מהאחוז השמור אם זה resume
      final savedProgress = _downloadProgress[navigation.id] ?? 0.0;
      final initialPct = isResume ? (savedProgress * 100).round() : 0;
      _lastNotifiedPercent = initialPct;
      _notificationService.showProgress(initialPct, 100);

      // אתחול מונה אריחים — ב-resume, אריחים שכבר ב-cache ידולגו מהר ע"י FMTC
      // אבל ה-notification מתחיל מהאחוז השמור כדי שלא יקפוץ ל-0%
      int completedTiles = isResume ? (savedProgress * totalTiles).round() : 0;
      bool wasInterrupted = false;

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
        _activeCompleters[navigation.id] = completer;
        double lastPercent = 0;

        final sub = tileCache
            .downloadRegion(
              bounds: bounds,
              mapType: mapType,
              minZoom: minZoom,
              maxZoom: maxZoom,
            )
            .listen(
          (progress) {
            lastPercent = progress.percentageProgress;
            // עדכון התקדמות כוללת
            final currentTiles = completedTiles +
                (progress.percentageProgress / 100 * tileCount).round();
            _downloadProgress[navigation.id] =
                totalTiles > 0 ? currentTiles / totalTiles : 0.0;

            // עדכון notification כל ~2% שינוי
            final pct = ((_downloadProgress[navigation.id] ?? 0.0) * 100).round();
            if ((pct - _lastNotifiedPercent).abs() >= 2) {
              _lastNotifiedPercent = pct;
              _notificationService.showProgress(pct, 100);
            }

            if (progress.percentageProgress % 25 < 1) {
              print(
                  'DEBUG AutoMapDownload: $label ${progress.percentageProgress.toStringAsFixed(0)}%');
            }
          },
          onDone: () {
            if (lastPercent >= 99.0) {
              completedTiles += tileCount;
              print('DEBUG AutoMapDownload: $label done');
            } else {
              print('DEBUG AutoMapDownload: $label stream ended at ${lastPercent.toStringAsFixed(0)}% — interrupted');
              wasInterrupted = true;
            }
            if (!completer.isCompleted) completer.complete();
          },
          onError: (e) {
            print('DEBUG AutoMapDownload: $label error: $e');
            wasInterrupted = true;
            if (!completer.isCompleted) completer.complete();
          },
        );

        _activeDownloads[navigation.id] = sub;
        await completer.future;
        _activeCompleters.remove(navigation.id);

        // בדיקה אם ה-epoch השתנה (ביטול ידני)
        if ((_downloadEpoch[navigation.id] ?? 0) != myEpoch) {
          print('DEBUG AutoMapDownload: epoch changed — aborting stale download run');
          await _releaseForegroundService();
          return AutoDownloadResult.started;
        }

        // בדיקה אם סומן כ-interrupted
        if (_downloadStatus[navigation.id] == MapDownloadStatus.interrupted) {
          wasInterrupted = true;
        }

        if (wasInterrupted) {
          print('DEBUG AutoMapDownload: download interrupted — will resume when possible');
          break;
        }
      }

      _activeDownloads.remove(navigation.id);

      if (wasInterrupted) {
        _downloadStatus[navigation.id] = MapDownloadStatus.interrupted;
        // לא משחרר foreground service — resume ינסה שוב
        return AutoDownloadResult.started;
      }

      // הושלם באמת — כל 3 סוגי המפות סיימו
      _triggeredNavIds.add(navigation.id);
      _downloadStatus[navigation.id] = MapDownloadStatus.completed;
      _downloadProgress[navigation.id] = 1.0;
      _navigationCache.remove(navigation.id);
      _downloadEpoch.remove(navigation.id);
      print('DEBUG AutoMapDownload: all downloads complete for nav ${navigation.id}');
      onStatusMessage?.call('הורדת מפות אופליין הושלמה');
      _notificationService.showCompleted();
      await _releaseForegroundService();
      return AutoDownloadResult.started;
    } catch (e) {
      print('DEBUG AutoMapDownload: error: $e — will retry later');
      _activeDownloads.remove(navigation.id);
      _downloadStatus[navigation.id] = MapDownloadStatus.failed;
      onStatusMessage?.call('שגיאה בהורדת מפות — ינסה שוב', isError: true);
      _notificationService.showFailed();
      await _releaseForegroundService();
      return AutoDownloadResult.started;
    }
  }

  /// איפוס סטטוס כדי לאפשר הורדה ידנית מחדש
  void resetForManualDownload(String navigationId) {
    _triggeredNavIds.remove(navigationId);
    _downloadStatus.remove(navigationId);
    _downloadProgress.remove(navigationId);
    _navigationCache.remove(navigationId);
    _downloadEpoch.remove(navigationId);
  }

  /// נקרא כשגבול סונכרן מ-Firestore — בודק אם יש ניווטים שממתינים לו
  /// רק מפעיל הורדה לניווטים שהמשתמש אישר
  Future<void> onBoundarySynced(String boundaryId) async {
    final pendingNavIds = _pendingBoundaryNavs.remove(boundaryId);
    if (pendingNavIds == null || pendingNavIds.isEmpty) return;

    print('DEBUG AutoMapDownload: boundary $boundaryId synced — retrying ${pendingNavIds.length} pending navs');

    final navRepo = NavigationRepository();
    for (final navId in pendingNavIds) {
      // רק ניווטים שהמשתמש אישר הורדה
      if (!_approvedNavIds.contains(navId)) continue;

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
    _navigationCache.remove(navigationId);
    _downloadEpoch.remove(navigationId);
    final completer = _activeCompleters.remove(navigationId);
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
    _notificationService.dismiss();
    _releaseForegroundService();
  }

  /// שחרור observer — נקרא כשהאפליקציה נסגרת
  void dispose() {
    if (_lifecycleRegistered) {
      WidgetsBinding.instance.removeObserver(this);
      _lifecycleRegistered = false;
    }
  }
}

// TaskHandler מינימלי להורדת מפות — רק שומר את התהליך חי, לא מפעיל GPS
@pragma('vm:entry-point')
void _mapDownloadServiceCallback() {
  FlutterForegroundTask.setTaskHandler(_MapDownloadTaskHandler());
}

class _MapDownloadTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {}
}
