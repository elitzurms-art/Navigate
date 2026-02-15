import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart' hide Query;
import 'package:firebase_auth/firebase_auth.dart' hide User;

import '../../core/constants/app_constants.dart';
import '../datasources/local/app_database.dart';

/// כיוון סנכרון לפי סוג נתונים
enum SyncDirection {
  pullOnly,      // שרת -> מקומי בלבד
  pushOnly,      // מקומי -> שרת בלבד (tracks, punches, violations)
  bidirectional, // דו-כיווני (units, trees, navigations, nav layers)
  realtime,      // האזנה בזמן אמת (alerts)
}

/// עדיפות סנכרון
class SyncPriority {
  static const int normal = 0;
  static const int high = 1;
  static const int realtime = 2;
}

/// מקסימום ניסיונות חוזרים
const int _maxRetryCount = 10;

/// מנהל סנכרון מלא בין מסד נתונים מקומי ל-Firestore
///
/// תומך ב:
/// - Push sync עם version checking וזיהוי קונפליקטים
/// - Pull sync עם lastPullAt incrementals
/// - Batch sync ל-GPS tracks (כל 2 דקות)
/// - סנכרון תקופתי (כל 5 דקות כשאונליין)
/// - ניטור חיבור (connectivity_plus)
/// - Exponential backoff בניסיונות חוזרים
/// - פתרון קונפליקטים אוטומטי לנתונים בטוחים
class SyncManager {
  // Singleton pattern
  static final SyncManager _instance = SyncManager._internal();
  factory SyncManager() => _instance;
  SyncManager._internal();

  final AppDatabase _db = AppDatabase();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Connectivity _connectivity = Connectivity();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// האם הסנכרון פעיל
  bool _isRunning = false;

  /// האם יש חיבור לאינטרנט
  bool _isOnline = false;

  /// טיימר לסנכרון תקופתי (כל 5 דקות)
  Timer? _periodicSyncTimer;

  /// טיימר ל-batch sync של GPS tracks (כל 2 דקות)
  Timer? _trackBatchTimer;

  /// מנוי לשינויי חיבור
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;

  /// האזנות realtime פעילות
  final Map<String, StreamSubscription<QuerySnapshot>> _realtimeListeners = {};

  /// מנוי לשינויי מצב אימות
  StreamSubscription<dynamic>? _authSubscription;

  /// האם כרגע מבצע סנכרון (למניעת הפעלות מקבילות)
  bool _isSyncing = false;

  /// האם כבר בוצע סנכרון ראשוני (למניעת כפילויות)
  bool _didInitialSync = false;

  /// Completer לסנכרון ראשוני — מאפשר למסכים להמתין לסיום
  Completer<void> _initialSyncCompleter = Completer<void>();

  /// האם הסנכרון הראשוני הושלם
  bool get didInitialSync => _didInitialSync;

  /// המתנה לסיום הסנכרון הראשוני (עם timeout)
  Future<void> waitForInitialSync({Duration timeout = const Duration(seconds: 15)}) async {
    if (_didInitialSync) return;
    try {
      await _initialSyncCompleter.future.timeout(timeout);
    } catch (_) {
      print('SyncManager: waitForInitialSync timed out after ${timeout.inSeconds}s');
    }
  }

  /// האם יש משתמש מאומת ב-Firebase Auth
  bool get _isAuthenticated => _auth.currentUser != null;

  /// מיפוי קולקשנים לכיווני סנכרון
  static final Map<String, SyncDirection> _syncDirections = {
    // Pull-only: Server -> Client
    AppConstants.usersCollection: SyncDirection.bidirectional,
    AppConstants.areasCollection: SyncDirection.bidirectional,
    // Area layers (layers_nz, layers_nb, layers_gg, layers_ba) are subcollections
    // under /areas/{areaId}/ — pulled via _pullAreaLayers(), not as top-level collections.
    // Pushed via area subcollection paths (areas/{areaId}/layers_*) resolved by _isAreaLayerPath().
    // Bidirectional
    AppConstants.unitsCollection: SyncDirection.bidirectional,
    AppConstants.navigatorTreesCollection: SyncDirection.bidirectional,
    AppConstants.navigationsCollection: SyncDirection.bidirectional,
    AppConstants.navLayersNzSubcollection: SyncDirection.bidirectional,
    AppConstants.navLayersNbSubcollection: SyncDirection.bidirectional,
    AppConstants.navLayersGgSubcollection: SyncDirection.bidirectional,
    AppConstants.navLayersBaSubcollection: SyncDirection.bidirectional,
    // Push-only: Client -> Server
    AppConstants.navigationTracksCollection: SyncDirection.pushOnly,
    'punches': SyncDirection.pushOnly,
    'violations': SyncDirection.pushOnly,
    // Realtime (bidirectional)
    'alerts': SyncDirection.realtime,
  };

  /// Check if a collection path is an area layer subcollection
  /// (e.g. "areas/{areaId}/layers_nz")
  static bool _isAreaLayerPath(String path) {
    return path.startsWith('${AppConstants.areasCollection}/') &&
        (path.endsWith('/${AppConstants.areaLayersNzSubcollection}') ||
         path.endsWith('/${AppConstants.areaLayersNbSubcollection}') ||
         path.endsWith('/${AppConstants.areaLayersGgSubcollection}') ||
         path.endsWith('/${AppConstants.areaLayersBaSubcollection}'));
  }

  // ---------------------------------------------------------------------------
  // Lifecycle: start / stop
  // ---------------------------------------------------------------------------

  /// הפעלת מנהל הסנכרון - קורא בעליית האפליקציה
  Future<void> start() async {
    if (_isRunning) return;
    _isRunning = true;

    print('SyncManager: Starting...');

    // בדיקת חיבור ראשונית
    final connectivityResult = await _connectivity.checkConnectivity();
    _isOnline = connectivityResult != ConnectivityResult.none;
    print('SyncManager: Initial connectivity = $_isOnline');

    // האזנה לשינויי חיבור
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _onConnectivityChanged,
    );

    // האזנה לשינויי מצב אימות — סנכרון ראשוני כשהמשתמש מתחבר
    // הערה: authStateChanges יורה מיד עם המצב הנוכחי, אז לא צריך לעשות סנכרון ראשוני כאן
    _didInitialSync = false;
    _authSubscription = _auth.authStateChanges().listen(_onAuthStateChanged);

    // סנכרון תקופתי כל 5 דקות
    _periodicSyncTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _runPeriodicSync(),
    );

    // Batch sync ל-GPS tracks כל 2 דקות
    _trackBatchTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => _pushTracksBatch(),
    );

    if (_isOnline && !_isAuthenticated) {
      print('SyncManager: Online but not authenticated — skipping initial sync. Will sync after login.');
    }
  }

  /// טיפול בשינוי מצב אימות
  void _onAuthStateChanged(dynamic user) {
    if (user != null && _isOnline) {
      if (_didInitialSync) {
        // סנכרון כבר בוצע — כנראה re-auth, לא צריך שוב
        return;
      }
      _didInitialSync = true;
      print('SyncManager: User authenticated — triggering sync.');
      pullAll().then((_) {
        if (!_initialSyncCompleter.isCompleted) {
          _initialSyncCompleter.complete();
        }
        processSyncQueue();
      }).catchError((e) {
        print('SyncManager: Initial pullAll failed: $e');
        if (!_initialSyncCompleter.isCompleted) {
          _initialSyncCompleter.complete(); // השלם גם בשגיאה כדי לא לחסום
        }
      });
    } else if (user == null) {
      _didInitialSync = false;
      _initialSyncCompleter = Completer<void>(); // איפוס ל-login הבא
      print('SyncManager: User signed out — pausing Firestore sync.');
    }
  }

  /// עצירת מנהל הסנכרון
  Future<void> stop() async {
    _isRunning = false;

    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = null;

    _trackBatchTimer?.cancel();
    _trackBatchTimer = null;

    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;

    await _authSubscription?.cancel();
    _authSubscription = null;

    // ביטול כל ה-realtime listeners
    for (final sub in _realtimeListeners.values) {
      await sub.cancel();
    }
    _realtimeListeners.clear();

    print('SyncManager: Stopped.');
  }

  // ---------------------------------------------------------------------------
  // Connectivity handling
  // ---------------------------------------------------------------------------

  /// טיפול בשינוי מצב חיבור
  void _onConnectivityChanged(ConnectivityResult result) {
    final wasOnline = _isOnline;
    _isOnline = result != ConnectivityResult.none;

    print('SyncManager: Connectivity changed. Online=$_isOnline');

    if (!wasOnline && _isOnline && _isAuthenticated) {
      // חזרנו אונליין ומאומתים - בצע סנכרון מלא
      print('SyncManager: Back online - triggering full sync.');
      pullAll().then((_) => processSyncQueue());
    }
  }

  // ---------------------------------------------------------------------------
  // Queue operations (Push path: local write -> queue -> Firestore)
  // ---------------------------------------------------------------------------

  /// הוספת פעולה לתור סנכרון - נקרא מכל repository אחרי כתיבה מקומית
  ///
  /// [collection] - שם הקולקשן ב-Firestore
  /// [documentId] - מזהה המסמך
  /// [operation] - 'create', 'update', 'delete'
  /// [data] - הנתונים (כ-Map)
  /// [version] - מספר גרסה מקומי
  /// [priority] - עדיפות: 0=רגיל, 1=גבוה, 2=realtime
  Future<void> queueOperation({
    required String collection,
    required String documentId,
    required String operation,
    required Map<String, dynamic> data,
    int version = 1,
    int priority = SyncPriority.normal,
  }) async {
    // הוספה לתור סנכרון ב-DB המקומי
    await _db.into(_db.syncQueue).insert(
      SyncQueueCompanion.insert(
        collectionName: collection,
        operation: operation,
        recordId: documentId,
        dataJson: jsonEncode(_sanitizeForJson(data)),
        version: Value(version),
        priority: Value(priority),
        createdAt: DateTime.now(),
      ),
    );

    print('SyncManager: Queued $operation on $collection/$documentId (v$version, priority=$priority)');

    // אם אונליין ועדיפות גבוהה - נסה לסנכרן מיד
    if (_isOnline && priority >= SyncPriority.high) {
      await processSyncQueue();
    }
  }

  // ---------------------------------------------------------------------------
  // Push sync: process queue -> Firestore
  // ---------------------------------------------------------------------------

  /// עיבוד תור הסנכרון - שולח למתין ל-Firestore
  Future<void> processSyncQueue() async {
    if (!_isOnline || _isSyncing || !_isAuthenticated) return;
    _isSyncing = true;

    try {
      final pendingItems = await _db.getPendingSyncItems();
      if (pendingItems.isEmpty) {
        print('SyncManager: No pending items in sync queue.');
        return;
      }

      print('SyncManager: Processing ${pendingItems.length} pending sync items...');

      for (final item in pendingItems) {
        // בדיקה שעדיין אונליין
        if (!_isOnline) {
          print('SyncManager: Lost connectivity, stopping queue processing.');
          break;
        }

        // בדיקת מספר ניסיונות חוזרים
        if (item.retryCount >= _maxRetryCount) {
          print('SyncManager: Item ${item.id} exceeded max retries (${item.retryCount}). Skipping.');
          continue;
        }

        await _processSingleItem(item);
      }
    } catch (e) {
      print('SyncManager: Error processing sync queue: $e');
    } finally {
      _isSyncing = false;
    }
  }

  /// עיבוד פריט בודד מתור הסנכרון
  Future<void> _processSingleItem(SyncQueueData item) async {
    try {
      // Block delete for areas (add-only collection) — layers are deletable by developers
      if (item.operation == 'delete') {
        if (item.collectionName == AppConstants.areasCollection) {
          print('SyncManager: Blocked delete on add-only collection ${item.collectionName}');
          await _db.markAsSynced(item.id);
          return;
        }
      }

      // Resolve direction: area layer subcollection paths are bidirectional
      final direction = _isAreaLayerPath(item.collectionName)
          ? SyncDirection.bidirectional
          : (_syncDirections[item.collectionName] ?? SyncDirection.bidirectional);

      // קולקשנים של pull-only לא נשלחים לשרת
      if (direction == SyncDirection.pullOnly) {
        print('SyncManager: Skipping push for pull-only collection ${item.collectionName}');
        await _db.markAsSynced(item.id);
        return;
      }

      final data = jsonDecode(item.dataJson) as Map<String, dynamic>;

      // מחיקות לא צריכות בדיקת קונפליקט — תמיד לבצע
      if (item.operation != 'delete') {
        // בדיקת קונפליקט גרסאות (רק ל-bidirectional, לא למחיקות)
        if (direction == SyncDirection.bidirectional) {
          final conflictDetected = await _checkVersionConflict(
            collection: item.collectionName,
            documentId: item.recordId,
            localVersion: item.version,
            localData: data,
          );
          if (conflictDetected) {
            // קונפליקט זוהה - הועבר לתור קונפליקטים, מסמנים כמטופל
            await _db.markAsSynced(item.id);
            return;
          }
        }
      }

      // ביצוע הפעולה ב-Firestore (version ייתכן שהוגדל ב-last-write-wins)
      final pushVersion = (data['version'] as int?) ?? item.version;
      await _executeFirestoreOperation(
        collection: item.collectionName,
        documentId: item.recordId,
        operation: item.operation,
        data: data,
        version: pushVersion,
      );

      // הצלחה - סימון כמסונכרן
      await _db.markAsSynced(item.id);
      await _db.updateLastPushAt(item.collectionName, DateTime.now());

      print('SyncManager: Successfully synced ${item.collectionName}/${item.recordId}');
    } catch (e) {
      // כישלון - עדכון מספר ניסיונות והודעת שגיאה
      final newRetryCount = item.retryCount + 1;
      await _db.updateSyncRetry(item.id, newRetryCount, e.toString());

      print('SyncManager: Failed to sync item ${item.id} (retry $newRetryCount): $e');

      // Exponential backoff: delay לפני הפריט הבא
      if (newRetryCount < _maxRetryCount) {
        final backoffMs = _calculateBackoff(newRetryCount);
        print('SyncManager: Will retry in ${backoffMs}ms');
        await Future.delayed(Duration(milliseconds: backoffMs));
      }
    }
  }

  /// בדיקת קונפליקט גרסאות מול השרת
  ///
  /// מחזיר true אם זוהה קונפליקט (והוא הועבר לתור קונפליקטים)
  Future<bool> _checkVersionConflict({
    required String collection,
    required String documentId,
    required int localVersion,
    required Map<String, dynamic> localData,
  }) async {
    try {
      final serverDoc = await _firestore
          .collection(collection)
          .doc(documentId)
          .get()
          .timeout(const Duration(seconds: 10));

      if (!serverDoc.exists) {
        // מסמך לא קיים בשרת - אין קונפליקט (create חדש)
        return false;
      }

      final serverData = serverDoc.data()!;
      final serverVersion = (serverData['version'] as num?)?.toInt() ?? 0;

      // אם גרסת השרת == גרסה מקומית - 1: הכל תקין, push יצליח
      if (serverVersion == localVersion - 1) {
        return false;
      }

      // אם גרסת השרת >= גרסה מקומית: בדיקת קונפליקט
      if (serverVersion >= localVersion) {
        // אם אותה גרסה — בדוק אם הנתונים זהים (כבר מסונכרן)
        if (serverVersion == localVersion &&
            _isDataEquivalent(localData, serverData)) {
          print('SyncManager: Already in sync $collection/$documentId (v$localVersion)');
          return true; // מסומן כמטופל — הקורא ימחק מהתור
        }

        print('SyncManager: CONFLICT detected on $collection/$documentId '
            '(local v$localVersion vs server v$serverVersion)');

        // נסה פתרון אוטומטי לנתונים בטוחים
        final autoResolved = await _tryAutoResolve(
          collection: collection,
          documentId: documentId,
          localData: localData,
          serverData: serverData,
          localVersion: localVersion,
          serverVersion: serverVersion,
        );

        if (!autoResolved) {
          // last-write-wins: דחוף עם גרסה מוגדלת במקום להיתקע בתור קונפליקטים
          print('SyncManager: Resolving with last-write-wins for $collection/$documentId '
              '(bumping to v${serverVersion + 1})');
          localData['version'] = serverVersion + 1;
          return false; // תן ל-push להמשיך עם הגרסה המוגדלת
        }

        return true;
      }

      // גרסת שרת < גרסה מקומית - 1: מצב לא צפוי, ננסה push
      return false;
    } catch (e) {
      // אם לא ניתן לבדוק גרסה (בעיית רשת) - לא קונפליקט, ננסה שוב אחרי
      print('SyncManager: Could not check version for $collection/$documentId: $e');
      rethrow; // יגרום ל-retry ב-_processSingleItem
    }
  }

  /// ביצוע פעולה ב-Firestore
  Future<void> _executeFirestoreOperation({
    required String collection,
    required String documentId,
    required String operation,
    required Map<String, dynamic> data,
    required int version,
  }) async {
    // הוספת/עדכון שדות גרסה ותאריך עדכון
    final enrichedData = Map<String, dynamic>.from(data);
    enrichedData['version'] = version;
    enrichedData['updatedAt'] = FieldValue.serverTimestamp();

    switch (operation) {
      case 'create':
        await _firestore
            .collection(collection)
            .doc(documentId)
            .set(enrichedData)
            .timeout(const Duration(seconds: 10));
        break;
      case 'update':
        await _firestore
            .collection(collection)
            .doc(documentId)
            .set(enrichedData, SetOptions(merge: true))
            .timeout(const Duration(seconds: 10));
        break;
      case 'delete':
        // Soft delete — mark with deletedAt instead of removing the doc,
        // so other devices discover the deletion via incremental pull.
        await _firestore
            .collection(collection)
            .doc(documentId)
            .set({
              'deletedAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true))
            .timeout(const Duration(seconds: 10));
        break;
      default:
        print('SyncManager: Unknown operation: $operation');
    }
  }

  // ---------------------------------------------------------------------------
  // Pull sync: Firestore -> local DB
  // ---------------------------------------------------------------------------

  /// משיכת כל הנתונים מהשרת (incremental - רק שינויים מאז lastPullAt)
  Future<void> pullAll() async {
    if (!_isOnline || !_isAuthenticated) return;

    print('SyncManager: Starting pull sync for all collections...');

    // Pull areas first (top-level collection)
    try {
      await _pullCollection(AppConstants.areasCollection);
    } catch (e) {
      print('SyncManager: Error pulling areas: $e');
    }

    // Pull area layer subcollections (/areas/{areaId}/layers_*)
    try {
      await _pullAreaLayers();
    } catch (e) {
      print('SyncManager: Error pulling area layers: $e');
    }

    // Bidirectional collections
    final bidirectionalCollections = [
      AppConstants.usersCollection,
      AppConstants.unitsCollection,
      AppConstants.navigatorTreesCollection,
      AppConstants.navigationsCollection,
    ];

    for (final collection in bidirectionalCollections) {
      try {
        await _pullCollection(collection);
      } catch (e) {
        print('SyncManager: Error pulling $collection: $e');
      }
    }

    // Reconciliation: זיהוי רשומות שנמחקו מ-Firestore (hard delete)
    await _reconcileDeletedRecords();

    print('SyncManager: Pull sync complete.');
  }

  /// בדיקת רשומות מקומיות מול Firestore — מחיקת רשומות שכבר לא קיימות בשרת
  ///
  /// חשוב: מדלגת על רשומות שיש להן פעולת create/update ממתינה בתור הסנכרון,
  /// כדי למנוע מחיקה של רשומות שנוצרו מקומית אבל עדיין לא הועלו ל-Firestore.
  Future<void> _reconcileDeletedRecords() async {
    final collectionsToReconcile = {
      AppConstants.unitsCollection: () async => (await _db.select(_db.units).get()).map((u) => u.id).toList(),
      AppConstants.navigatorTreesCollection: () async => (await _db.select(_db.navigationTrees).get()).map((t) => t.id).toList(),
      AppConstants.navigationsCollection: () async => (await _db.select(_db.navigations).get()).map((n) => n.id).toList(),
    };

    for (final entry in collectionsToReconcile.entries) {
      final collection = entry.key;
      final getLocalIds = entry.value;

      try {
        final localIds = await getLocalIds();
        if (localIds.isEmpty) continue;

        // שליפת כל הרשומות הממתינות בתור הסנכרון לקולקשן הזה
        // כדי לא למחוק רשומות שעדיין לא הועלו ל-Firestore
        final pendingItems = await _db.getPendingSyncItemsByCollection(collection);
        final pendingCreateOrUpdateIds = pendingItems
            .where((item) => item.operation == 'create' || item.operation == 'update')
            .map((item) => item.recordId)
            .toSet();

        // בדיקה בקבוצות של 10 (מגבלת whereIn של Firestore)
        for (var i = 0; i < localIds.length; i += 10) {
          final batch = localIds.skip(i).take(10).toList();
          final snapshot = await _firestore
              .collection(collection)
              .where(FieldPath.documentId, whereIn: batch)
              .get()
              .timeout(const Duration(seconds: 15));

          final existingIds = snapshot.docs.map((d) => d.id).toSet();
          // בדיקה גם ל-soft-delete
          final activeIds = snapshot.docs
              .where((d) => (d.data())['deletedAt'] == null)
              .map((d) => d.id)
              .toSet();

          for (final localId in batch) {
            // דילוג על רשומות עם create/update ממתין — עדיין לא הועלו לשרת
            if (pendingCreateOrUpdateIds.contains(localId)) {
              print('SyncManager: Reconcile — skipping $collection/$localId (pending sync)');
              continue;
            }

            if (!existingIds.contains(localId) || !activeIds.contains(localId)) {
              await _deleteLocalRecord(collection, localId);
              print('SyncManager: Reconcile — removed orphan $collection/$localId');
            }
          }
        }
      } catch (e) {
        print('SyncManager: Error reconciling $collection: $e');
      }
    }
  }

  /// משיכת שכבות (תת-קולקציות) מכל האזורים
  Future<void> _pullAreaLayers() async {
    // שליפת כל האזורים מה-DB המקומי
    final areas = await _db.select(_db.areas).get();
    if (areas.isEmpty) {
      print('SyncManager: No areas in local DB — skipping layer pull.');
      return;
    }

    print('SyncManager: Pulling layers for ${areas.length} areas...');

    // מיפוי שם תת-קולקציה → פונקציית upsert
    final layerSubcollections = {
      AppConstants.areaLayersNzSubcollection: _upsertCheckpoint,
      AppConstants.areaLayersNbSubcollection: _upsertSafetyPoint,
      AppConstants.areaLayersGgSubcollection: _upsertBoundary,
      AppConstants.areaLayersBaSubcollection: _upsertCluster,
    };

    for (final area in areas) {
      for (final entry in layerSubcollections.entries) {
        final subcollectionName = entry.key;
        final upsertFn = entry.value;
        final path = '${AppConstants.areasCollection}/${area.id}/$subcollectionName';

        try {
          final metadataKey = 'area_layers:${area.id}:$subcollectionName';
          final metadata = await _db.getSyncMetadata(metadataKey);
          final lastPullAt = metadata?.lastPullAt;

          Query query = _firestore.collection(path);
          if (lastPullAt != null) {
            final adjustedPullAt = lastPullAt.subtract(const Duration(seconds: 5));
            query = query.where('updatedAt', isGreaterThan: Timestamp.fromDate(adjustedPullAt));
          }

          final snapshot = await query.get().timeout(const Duration(seconds: 30));

          if (snapshot.docs.isNotEmpty) {
            print('SyncManager: Pulled ${snapshot.docs.length} docs from $path');
            for (final doc in snapshot.docs) {
              final serverData = doc.data() as Map<String, dynamic>;
              serverData['id'] = doc.id;
              serverData['areaId'] = area.id;
              // Soft-delete: if marked as deleted, remove locally
              if (serverData['deletedAt'] != null) {
                await _deleteLayerLocally(subcollectionName, doc.id);
              } else {
                await upsertFn(doc.id, serverData);
              }
            }
          }

          await _db.updateLastPullAt(metadataKey, DateTime.now());
        } catch (e) {
          print('SyncManager: Error pulling $path: $e');
        }
      }
    }

    print('SyncManager: Area layers pull complete.');
  }

  /// משיכת קולקשן בודד מ-Firestore
  Future<void> _pullCollection(String collection) async {
    final metadata = await _db.getSyncMetadata(collection);
    final lastPullAt = metadata?.lastPullAt;

    Query query = _firestore.collection(collection);

    // שאילתה incremental - רק שינויים חדשים
    // מרווח בטיחות של 5 שניות למניעת "בליעת" מסמכים בגלל clock skew
    if (lastPullAt != null) {
      final adjustedPullAt = lastPullAt.subtract(const Duration(seconds: 5));
      query = query.where('updatedAt', isGreaterThan: Timestamp.fromDate(adjustedPullAt));
    }

    final snapshot = await query.get().timeout(const Duration(seconds: 30));

    if (snapshot.docs.isEmpty) {
      print('SyncManager: No new data in $collection since ${lastPullAt ?? "beginning"}');
      return;
    }

    print('SyncManager: Pulled ${snapshot.docs.length} documents from $collection');

    final direction = _syncDirections[collection] ?? SyncDirection.bidirectional;

    for (final doc in snapshot.docs) {
      final serverData = doc.data() as Map<String, dynamic>;
      serverData['id'] = doc.id;

      // Soft-delete מהשרת מנצח תמיד — גם אם יש שינויים מקומיים ממתינים
      if (serverData['deletedAt'] != null) {
        await _deleteLocalRecord(collection, doc.id);
        // ביטול פריטים ממתינים כדי שלא ישחזרו את הרשומה
        final pending = await _db.getPendingSyncItemsByCollection(collection);
        for (final item in pending.where((i) => i.recordId == doc.id)) {
          await _db.markAsSynced(item.id);
        }
        continue;
      }

      if (direction == SyncDirection.pullOnly) {
        // Pull-only: תמיד מקבל מהשרת
        await _upsertLocalFromServer(collection, doc.id, serverData);
      } else {
        // Bidirectional: בדיקה אם יש שינויים מקומיים ממתינים
        final hasPendingLocal = await _hasPendingLocalChanges(collection, doc.id);
        if (hasPendingLocal) {
          // יש שינויים מקומיים ממתינים - בדיקת קונפליקט
          final localData = await _getLocalData(collection, doc.id);
          if (localData != null) {
            final autoResolved = await _tryAutoResolve(
              collection: collection,
              documentId: doc.id,
              localData: localData,
              serverData: serverData,
              localVersion: (localData['version'] as num?)?.toInt() ?? 1,
              serverVersion: (serverData['version'] as num?)?.toInt() ?? 1,
            );

            if (!autoResolved) {
              // הוספה לתור קונפליקטים
              await _db.insertConflict(
                ConflictQueueCompanion.insert(
                  collectionName: collection,
                  recordId: doc.id,
                  localDataJson: jsonEncode(_sanitizeForJson(localData)),
                  serverDataJson: jsonEncode(_sanitizeForJson(serverData)),
                  localVersion: (localData['version'] as num?)?.toInt() ?? 1,
                  serverVersion: (serverData['version'] as num?)?.toInt() ?? 1,
                  detectedAt: DateTime.now(),
                ),
              );
            }
          }
        } else {
          // אין שינויים מקומיים - עדכון מהשרת
          await _upsertLocalFromServer(collection, doc.id, serverData);
        }
      }
    }

    // עדכון lastPullAt
    await _db.updateLastPullAt(collection, DateTime.now());
  }

  /// בדיקה אם יש שינויים מקומיים ממתינים לרשומה
  Future<bool> _hasPendingLocalChanges(String collection, String documentId) async {
    final pending = await _db.getPendingSyncItemsByCollection(collection);
    return pending.any((item) => item.recordId == documentId);
  }

  /// קבלת נתונים מקומיים לרשומה (לבדיקת קונפליקט)
  Future<Map<String, dynamic>?> _getLocalData(String collection, String documentId) async {
    // חיפוש בתור הסנכרון - הנתונים המקומיים האחרונים
    final pending = await _db.getPendingSyncItemsByCollection(collection);
    final localItem = pending.where((item) => item.recordId == documentId).lastOrNull;
    if (localItem != null) {
      return jsonDecode(localItem.dataJson) as Map<String, dynamic>;
    }
    return null;
  }

  /// עדכון/הוספת רשומה מקומית מנתוני השרת
  Future<void> _upsertLocalFromServer(
    String collection,
    String documentId,
    Map<String, dynamic> serverData,
  ) async {
    try {
      // Soft-delete: if the server record is marked as deleted, remove locally
      if (serverData['deletedAt'] != null) {
        await _deleteLocalRecord(collection, documentId);
        return;
      }

      switch (collection) {
        case AppConstants.usersCollection:
          await _upsertUser(documentId, serverData);
          break;
        case AppConstants.areasCollection:
          await _upsertArea(documentId, serverData);
          break;
        case AppConstants.layersNzCollection:
          await _upsertCheckpoint(documentId, serverData);
          break;
        case AppConstants.layersNbCollection:
          await _upsertSafetyPoint(documentId, serverData);
          break;
        case AppConstants.layersGgCollection:
          await _upsertBoundary(documentId, serverData);
          break;
        case AppConstants.layersBaCollection:
          await _upsertCluster(documentId, serverData);
          break;
        case AppConstants.unitsCollection:
          await _upsertUnit(documentId, serverData);
          break;
        case AppConstants.navigatorTreesCollection:
          await _upsertNavigationTree(documentId, serverData);
          break;
        case AppConstants.navigationsCollection:
          await _upsertNavigation(documentId, serverData);
          break;
        default:
          print('SyncManager: No local upsert handler for collection $collection');
      }
    } catch (e) {
      print('SyncManager: Error upserting local record $collection/$documentId: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Local delete helpers (soft-delete from server -> local DB)
  // ---------------------------------------------------------------------------

  /// מחיקת רשומה מקומית כשהשרת סימן אותה כמחוקה (soft-delete)
  Future<void> _deleteLocalRecord(String collection, String documentId) async {
    try {
      switch (collection) {
        case AppConstants.usersCollection:
          await (_db.delete(_db.users)..where((t) => t.uid.equals(documentId))).go();
          break;
        case AppConstants.areasCollection:
          await (_db.delete(_db.areas)..where((t) => t.id.equals(documentId))).go();
          break;
        case AppConstants.unitsCollection:
          await (_db.delete(_db.units)..where((t) => t.id.equals(documentId))).go();
          break;
        case AppConstants.navigatorTreesCollection:
          await (_db.delete(_db.navigationTrees)..where((t) => t.id.equals(documentId))).go();
          break;
        case AppConstants.navigationsCollection:
          await (_db.delete(_db.navigations)..where((t) => t.id.equals(documentId))).go();
          break;
        default:
          print('SyncManager: No local delete handler for collection $collection');
          return;
      }
      print('SyncManager: Soft-delete — removed local $collection/$documentId');
    } catch (e) {
      print('SyncManager: Error deleting local record $collection/$documentId: $e');
    }
  }

  /// מחיקת שכבה מקומית לפי סוג תת-קולקציה
  Future<void> _deleteLayerLocally(String subcollection, String id) async {
    try {
      switch (subcollection) {
        case AppConstants.areaLayersNzSubcollection:
          await (_db.delete(_db.checkpoints)..where((t) => t.id.equals(id))).go();
          break;
        case AppConstants.areaLayersNbSubcollection:
          await (_db.delete(_db.safetyPoints)..where((t) => t.id.equals(id))).go();
          break;
        case AppConstants.areaLayersGgSubcollection:
          await (_db.delete(_db.boundaries)..where((t) => t.id.equals(id))).go();
          break;
        case AppConstants.areaLayersBaSubcollection:
          await (_db.delete(_db.clusters)..where((t) => t.id.equals(id))).go();
          break;
      }
      print('SyncManager: Soft-delete — removed local layer $subcollection/$id');
    } catch (e) {
      print('SyncManager: Error deleting local layer $subcollection/$id: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Local upsert helpers (pull sync -> local DB)
  // ---------------------------------------------------------------------------

  Future<void> _upsertArea(String id, Map<String, dynamic> data) async {
    await _db.into(_db.areas).insertOnConflictUpdate(
      AreasCompanion.insert(
        id: id,
        name: data['name'] as String? ?? '',
        description: data['description'] as String? ?? '',
        createdBy: data['createdBy'] as String? ?? '',
        createdAt: _parseDateTime(data['createdAt']) ?? DateTime.now(),
      ),
    );
  }

  Future<void> _upsertCheckpoint(String id, Map<String, dynamic> data) async {
    // Checkpoint.toMap() שולח coordinates כ-nested object: {lat, lng, utm}
    // אבל Drift מצפה לשדות שטוחים — צריך לחלץ מהמבנה המקונן
    final geometryType = data['geometryType'] as String? ?? 'point';
    final coords = data['coordinates'] as Map<String, dynamic>?;
    final lat = (coords?['lat'] as num?)?.toDouble()
        ?? (data['lat'] as num?)?.toDouble()
        ?? 0.0;
    final lng = (coords?['lng'] as num?)?.toDouble()
        ?? (data['lng'] as num?)?.toDouble()
        ?? 0.0;
    final utm = coords?['utm'] as String?
        ?? data['utm'] as String?
        ?? '';

    // polygonCoordinates מגיע כ-List מ-Firestore, Drift מצפה ל-JSON string
    final polyCoords = data['polygonCoordinates'] as List?;
    final coordinatesJson = polyCoords != null
        ? jsonEncode(polyCoords)
        : data['coordinatesJson'] as String?;

    await _db.into(_db.checkpoints).insertOnConflictUpdate(
      CheckpointsCompanion.insert(
        id: id,
        areaId: data['areaId'] as String? ?? '',
        name: data['name'] as String? ?? '',
        description: data['description'] as String? ?? '',
        type: data['type'] as String? ?? 'checkpoint',
        color: data['color'] as String? ?? 'blue',
        geometryType: Value(geometryType),
        lat: lat,
        lng: lng,
        utm: utm,
        coordinatesJson: Value(coordinatesJson),
        sequenceNumber: (data['sequenceNumber'] as num?)?.toInt() ?? 0,
        createdBy: data['createdBy'] as String? ?? '',
        createdAt: _parseDateTime(data['createdAt']) ?? DateTime.now(),
      ),
    );
  }

  Future<void> _upsertSafetyPoint(String id, Map<String, dynamic> data) async {
    // SafetyPoint.toMap() שולח coordinates כ-nested object (point) או polygonCoordinates כ-array (polygon)
    final coords = data['coordinates'] as Map<String, dynamic>?;
    final lat = (coords?['lat'] as num?)?.toDouble()
        ?? (data['lat'] as num?)?.toDouble();
    final lng = (coords?['lng'] as num?)?.toDouble()
        ?? (data['lng'] as num?)?.toDouble();
    final utm = coords?['utm'] as String?
        ?? data['utm'] as String?;

    // polygonCoordinates מגיע כ-List מ-Firestore, Drift מצפה ל-JSON string
    final polyCoords = data['polygonCoordinates'] as List?;
    final coordinatesJson = polyCoords != null
        ? jsonEncode(polyCoords)
        : data['coordinatesJson'] as String?;

    await _db.into(_db.safetyPoints).insertOnConflictUpdate(
      SafetyPointsCompanion.insert(
        id: id,
        areaId: data['areaId'] as String? ?? '',
        name: data['name'] as String? ?? '',
        description: data['description'] as String? ?? '',
        sequenceNumber: (data['sequenceNumber'] as num?)?.toInt() ?? 0,
        severity: data['severity'] as String? ?? 'low',
        createdBy: data['createdBy'] as String? ?? '',
        createdAt: _parseDateTime(data['createdAt']) ?? DateTime.now(),
        updatedAt: _parseDateTime(data['updatedAt']) ?? DateTime.now(),
        type: Value(data['type'] as String? ?? 'point'),
        lat: Value(lat),
        lng: Value(lng),
        utm: Value(utm),
        coordinatesJson: Value(coordinatesJson),
      ),
    );
  }

  Future<void> _upsertBoundary(String id, Map<String, dynamic> data) async {
    // Boundary.toMap() שולח coordinates כ-List של objects
    // Drift מצפה ל-JSON string בעמודת coordinatesJson
    final coordsList = data['coordinates'] as List?;
    final coordinatesJson = coordsList != null
        ? jsonEncode(coordsList)
        : data['coordinatesJson'] as String? ?? '[]';

    await _db.into(_db.boundaries).insertOnConflictUpdate(
      BoundariesCompanion.insert(
        id: id,
        areaId: data['areaId'] as String? ?? '',
        name: data['name'] as String? ?? '',
        description: data['description'] as String? ?? '',
        coordinatesJson: coordinatesJson,
        color: data['color'] as String? ?? 'black',
        strokeWidth: (data['strokeWidth'] as num?)?.toDouble() ?? 2.0,
        createdBy: data['createdBy'] as String? ?? '',
        createdAt: _parseDateTime(data['createdAt']) ?? DateTime.now(),
        updatedAt: _parseDateTime(data['updatedAt']) ?? DateTime.now(),
      ),
    );
  }

  Future<void> _upsertCluster(String id, Map<String, dynamic> data) async {
    // Cluster.toMap() שולח coordinates כ-List של objects
    // Drift מצפה ל-JSON string בעמודת coordinatesJson
    final coordsList = data['coordinates'] as List?;
    final coordinatesJson = coordsList != null
        ? jsonEncode(coordsList)
        : data['coordinatesJson'] as String? ?? '[]';

    await _db.into(_db.clusters).insertOnConflictUpdate(
      ClustersCompanion.insert(
        id: id,
        areaId: data['areaId'] as String? ?? '',
        name: data['name'] as String? ?? '',
        description: data['description'] as String? ?? '',
        coordinatesJson: coordinatesJson,
        color: data['color'] as String? ?? 'green',
        strokeWidth: (data['strokeWidth'] as num?)?.toDouble() ?? 2.0,
        fillOpacity: (data['fillOpacity'] as num?)?.toDouble() ?? 0.3,
        createdBy: data['createdBy'] as String? ?? '',
        createdAt: _parseDateTime(data['createdAt']) ?? DateTime.now(),
        updatedAt: _parseDateTime(data['updatedAt']) ?? DateTime.now(),
      ),
    );
  }

  Future<void> _upsertUnit(String id, Map<String, dynamic> data) async {
    await _db.into(_db.units).insertOnConflictUpdate(
      UnitsCompanion.insert(
        id: id,
        name: data['name'] as String? ?? '',
        description: data['description'] as String? ?? '',
        type: data['type'] as String? ?? 'company',
        parentUnitId: Value(data['parentUnitId'] as String?),
        managerIdsJson: data['managerIdsJson'] as String? ??
            (data['managerIds'] != null ? jsonEncode(data['managerIds']) : '[]'),
        createdBy: data['createdBy'] as String? ?? '',
        createdAt: _parseDateTime(data['createdAt']) ?? DateTime.now(),
        updatedAt: _parseDateTime(data['updatedAt']) ?? DateTime.now(),
        level: Value((data['level'] as num?)?.toInt()),
        isNavigators: Value(data['isNavigators'] as bool? ?? false),
        isGeneral: Value(data['isGeneral'] as bool? ?? false),
      ),
    );
  }

  Future<void> _upsertNavigationTree(String id, Map<String, dynamic> data) async {
    // Firestore stores subFrameworks as array (from toMap()), but Drift stores as JSON string.
    // Also support old 'frameworks' key for backward compat.
    String frameworksJson;
    if (data['frameworksJson'] is String) {
      frameworksJson = data['frameworksJson'] as String;
    } else if (data['subFrameworks'] != null) {
      frameworksJson = jsonEncode(data['subFrameworks']);
    } else if (data['frameworks'] != null) {
      frameworksJson = jsonEncode(data['frameworks']);
    } else {
      frameworksJson = '[]';
    }

    await _db.into(_db.navigationTrees).insertOnConflictUpdate(
      NavigationTreesCompanion.insert(
        id: id,
        name: data['name'] as String? ?? '',
        frameworksJson: frameworksJson,
        createdBy: data['createdBy'] as String? ?? '',
        createdAt: _parseDateTime(data['createdAt']) ?? DateTime.now(),
        updatedAt: _parseDateTime(data['updatedAt']) ?? DateTime.now(),
        treeType: Value(data['treeType'] as String?),
        sourceTreeId: Value(data['sourceTreeId'] as String?),
        unitId: Value(data['unitId'] as String?),
      ),
    );
  }

  Future<void> _upsertNavigation(String id, Map<String, dynamic> data) async {
    await _db.into(_db.navigations).insertOnConflictUpdate(
      NavigationsCompanion.insert(
        id: id,
        name: data['name'] as String? ?? '',
        status: data['status'] as String? ?? AppConstants.navStatusPreparation,
        createdBy: data['createdBy'] as String? ?? '',
        treeId: data['treeId'] as String? ?? '',
        areaId: data['areaId'] as String? ?? '',
        layerNzId: data['layerNzId'] as String? ?? '',
        layerNbId: data['layerNbId'] as String? ?? '',
        layerGgId: data['layerGgId'] as String? ?? '',
        layerBaId: Value(data['layerBaId'] as String?),
        distributionMethod: data['distributionMethod'] as String? ?? AppConstants.distributionManualFull,
        navigationType: Value(data['navigationType'] as String?),
        executionOrder: Value(data['executionOrder'] as String?),
        boundaryLayerId: Value(data['boundaryLayerId'] as String?),
        routeLengthJson: Value(data['routeLengthJson'] as String? ??
            (data['routeLengthKm'] != null ? jsonEncode(data['routeLengthKm']) : null)),
        safetyTimeJson: Value(data['safetyTimeJson'] as String? ??
            (data['safetyTime'] != null ? jsonEncode(data['safetyTime']) : null)),
        learningSettingsJson: data['learningSettingsJson'] as String? ??
            (data['learningSettings'] != null ? jsonEncode(data['learningSettings']) : '{}'),
        verificationSettingsJson: data['verificationSettingsJson'] as String? ??
            (data['verificationSettings'] != null ? jsonEncode(data['verificationSettings']) : '{}'),
        alertsJson: data['alertsJson'] as String? ??
            (data['alerts'] != null ? jsonEncode(data['alerts']) : '{}'),
        displaySettingsJson: data['displaySettingsJson'] as String? ??
            (data['displaySettings'] != null ? jsonEncode(data['displaySettings']) : '{}'),
        routesJson: data['routesJson'] as String? ??
            (data['routes'] != null ? jsonEncode(data['routes']) : '[]'),
        routesStage: Value(data['routesStage'] as String?),
        gpsUpdateIntervalSeconds: (data['gpsUpdateIntervalSeconds'] as num?)?.toInt() ??
            AppConstants.defaultGpsUpdateInterval,
        permissionsJson: data['permissionsJson'] as String? ??
            (data['permissions'] != null ? jsonEncode(data['permissions']) : '{}'),
        frameworkId: Value(data['frameworkId'] as String? ?? data['selectedUnitId'] as String?),
        selectedSubFrameworkIdsJson: Value(
          data['selectedSubFrameworkIdsJson'] as String? ??
          (data['selectedSubFrameworkIds'] != null ? jsonEncode(data['selectedSubFrameworkIds']) : null)),
        selectedParticipantIdsJson: Value(
          data['selectedParticipantIdsJson'] as String? ??
          (data['selectedParticipantIds'] != null ? jsonEncode(data['selectedParticipantIds']) : null)),
        allowOpenMap: Value(data['allowOpenMap'] as bool? ?? false),
        showSelfLocation: Value(data['showSelfLocation'] as bool? ?? false),
        showRouteOnMap: Value(data['showRouteOnMap'] as bool? ?? false),
        routesDistributed: Value(data['routesDistributed'] as bool? ?? false),
        reviewSettingsJson: Value(data['reviewSettingsJson'] as String? ??
            (data['reviewSettings'] != null ? jsonEncode(data['reviewSettings']) : '{"showScoresAfterApproval":true}')),
        distributeNow: Value(data['distributeNow'] as bool? ?? false),
        trainingStartTime: Value(_parseDateTime(data['trainingStartTime'])),
        systemCheckStartTime: Value(_parseDateTime(data['systemCheckStartTime'])),
        activeStartTime: Value(_parseDateTime(data['activeStartTime'])),
        createdAt: _parseDateTime(data['createdAt']) ?? DateTime.now(),
        updatedAt: _parseDateTime(data['updatedAt']) ?? DateTime.now(),
      ),
    );
  }

  Future<void> _upsertUser(String id, Map<String, dynamic> data) async {
    await _db.into(_db.users).insertOnConflictUpdate(
      UsersCompanion.insert(
        uid: id,
        firstName: Value(data['firstName'] as String? ?? ''),
        lastName: Value(data['lastName'] as String? ?? ''),
        personalNumber: Value(data['personalNumber'] as String? ?? id),
        fullName: data['fullName'] as String? ?? '',
        username: '',
        phoneNumber: data['phoneNumber'] as String? ?? '',
        phoneVerified: data['phoneVerified'] as bool? ?? false,
        email: Value(data['email'] as String? ?? ''),
        emailVerified: Value(data['emailVerified'] as bool? ?? false),
        role: data['role'] as String? ?? 'navigator',
        frameworkId: const Value(null),
        unitId: Value(data['unitId'] as String?),
        fcmToken: Value(data['fcmToken'] as String?),
        createdAt: _parseDateTime(data['createdAt']) ?? DateTime.now(),
        updatedAt: _parseDateTime(data['updatedAt']) ?? DateTime.now(),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Automatic conflict resolution
  // ---------------------------------------------------------------------------

  /// השוואת נתונים תוכניים (מתעלמת משדות metadata כמו version, updatedAt)
  bool _isDataEquivalent(
      Map<String, dynamic> localData, Map<String, dynamic> serverData) {
    const metadataKeys = {
      'version',
      'updatedAt',
      'createdAt',
      'syncedAt',
      'lastModified'
    };

    final localFiltered = Map<String, dynamic>.from(localData)
      ..removeWhere((k, _) => metadataKeys.contains(k));
    final serverFiltered = Map<String, dynamic>.from(serverData)
      ..removeWhere((k, _) => metadataKeys.contains(k));

    // Firestore Timestamp → String normalization
    final localJson = jsonEncode(_sanitizeForJson(localFiltered));
    final serverJson = jsonEncode(_sanitizeForJson(serverFiltered));
    return localJson == serverJson;
  }

  /// ניסיון לפתור קונפליקט אוטומטית (לנתונים בטוחים)
  ///
  /// מחזיר true אם הקונפליקט נפתר אוטומטית.
  Future<bool> _tryAutoResolve({
    required String collection,
    required String documentId,
    required Map<String, dynamic> localData,
    required Map<String, dynamic> serverData,
    required int localVersion,
    required int serverVersion,
  }) async {
    // Track points: Always merge (append, sort by timestamp)
    if (collection == AppConstants.navigationTracksCollection) {
      await _mergeTrackPoints(documentId, localData, serverData);
      return true;
    }

    // Punches: Always keep both (unique IDs)
    if (collection == 'punches') {
      await _mergePunches(documentId, localData, serverData);
      return true;
    }

    // Alerts: Always keep both (append-only)
    if (collection == 'alerts') {
      await _mergeAppendOnly(collection, documentId, localData, serverData);
      return true;
    }

    // Violations: Always keep both (append-only)
    if (collection == 'violations') {
      await _mergeAppendOnly(collection, documentId, localData, serverData);
      return true;
    }

    // סוגי נתונים אחרים (navigations, trees, layers) - דורשים פתרון ידני
    return false;
  }

  /// מיזוג track points - שילוב ומיון לפי timestamp
  Future<void> _mergeTrackPoints(
    String documentId,
    Map<String, dynamic> localData,
    Map<String, dynamic> serverData,
  ) async {
    try {
      final localPoints = _parseJsonList(localData['trackPointsJson']);
      final serverPoints = _parseJsonList(serverData['trackPointsJson']);

      // שילוב כל הנקודות
      final mergedPointsMap = <String, dynamic>{};

      for (final point in serverPoints) {
        final key = _trackPointKey(point);
        mergedPointsMap[key] = point;
      }
      for (final point in localPoints) {
        final key = _trackPointKey(point);
        mergedPointsMap[key] = point; // מקומי מנצח אם כפול
      }

      // מיון לפי timestamp
      final mergedPoints = mergedPointsMap.values.toList();
      mergedPoints.sort((a, b) {
        final aTime = a['timestamp'] ?? a['time'] ?? '';
        final bTime = b['timestamp'] ?? b['time'] ?? '';
        return aTime.toString().compareTo(bTime.toString());
      });

      // עדכון מקומי
      final mergedData = Map<String, dynamic>.from(serverData);
      mergedData['trackPointsJson'] = jsonEncode(mergedPoints);
      mergedData['version'] = (serverData['version'] as num?)?.toInt() ?? 1;

      await _upsertLocalFromServer(
        AppConstants.navigationTracksCollection,
        documentId,
        mergedData,
      );

      // Push merged version to server
      await _executeFirestoreOperation(
        collection: AppConstants.navigationTracksCollection,
        documentId: documentId,
        operation: 'update',
        data: mergedData,
        version: ((serverData['version'] as num?)?.toInt() ?? 0) + 1,
      );

      print('SyncManager: Auto-merged track points for $documentId');
    } catch (e) {
      print('SyncManager: Error auto-merging track points: $e');
    }
  }

  /// מיזוג punches - שמירת שניהם (IDs ייחודיים)
  Future<void> _mergePunches(
    String documentId,
    Map<String, dynamic> localData,
    Map<String, dynamic> serverData,
  ) async {
    try {
      // punches are individual docs with unique IDs - just push the local one
      await _executeFirestoreOperation(
        collection: 'punches',
        documentId: documentId,
        operation: 'create',
        data: localData,
        version: 1,
      );

      print('SyncManager: Auto-resolved punch conflict by keeping both for $documentId');
    } catch (e) {
      print('SyncManager: Error auto-merging punches: $e');
    }
  }

  /// מיזוג נתונים מסוג append-only (alerts, violations)
  Future<void> _mergeAppendOnly(
    String collection,
    String documentId,
    Map<String, dynamic> localData,
    Map<String, dynamic> serverData,
  ) async {
    try {
      // Append-only data: both versions are valid, just push the local one
      await _executeFirestoreOperation(
        collection: collection,
        documentId: documentId,
        operation: 'create',
        data: localData,
        version: 1,
      );

      print('SyncManager: Auto-resolved $collection conflict by keeping both for $documentId');
    } catch (e) {
      print('SyncManager: Error auto-merging $collection: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Batch sync for GPS tracks
  // ---------------------------------------------------------------------------

  /// שליחת batch של GPS tracks ל-Firestore (כל 2 דקות)
  Future<void> _pushTracksBatch() async {
    if (!_isOnline || !_isAuthenticated) return;

    try {
      final trackItems = await _db.getPendingSyncItemsByCollection(
        AppConstants.navigationTracksCollection,
      );

      if (trackItems.isEmpty) return;

      print('SyncManager: Pushing batch of ${trackItems.length} track items...');

      // שימוש ב-Firestore batch write
      final batch = _firestore.batch();
      final processedIds = <int>[];

      for (final item in trackItems) {
        final data = jsonDecode(item.dataJson) as Map<String, dynamic>;
        data['version'] = item.version;
        data['updatedAt'] = FieldValue.serverTimestamp();

        final docRef = _firestore
            .collection(AppConstants.navigationTracksCollection)
            .doc(item.recordId);

        switch (item.operation) {
          case 'create':
            batch.set(docRef, data);
            break;
          case 'update':
            batch.set(docRef, data, SetOptions(merge: true));
            break;
          case 'delete':
            batch.delete(docRef);
            break;
        }

        processedIds.add(item.id);
      }

      // Firestore batch limit is 500 - split if needed
      if (processedIds.length <= 500) {
        await batch.commit().timeout(const Duration(seconds: 30));

        // סימון הכל כמסונכרן
        for (final id in processedIds) {
          await _db.markAsSynced(id);
        }

        print('SyncManager: Successfully batched ${processedIds.length} track items.');
      } else {
        // יותר מ-500 - עבד בחלקים
        print('SyncManager: Track batch too large (${processedIds.length}), processing in chunks...');
        for (var i = 0; i < trackItems.length; i += 500) {
          final chunk = trackItems.skip(i).take(500).toList();
          final chunkBatch = _firestore.batch();

          for (final item in chunk) {
            final data = jsonDecode(item.dataJson) as Map<String, dynamic>;
            data['version'] = item.version;
            data['updatedAt'] = FieldValue.serverTimestamp();

            final docRef = _firestore
                .collection(AppConstants.navigationTracksCollection)
                .doc(item.recordId);

            switch (item.operation) {
              case 'create':
                chunkBatch.set(docRef, data);
                break;
              case 'update':
                chunkBatch.set(docRef, data, SetOptions(merge: true));
                break;
              case 'delete':
                chunkBatch.delete(docRef);
                break;
            }
          }

          await chunkBatch.commit().timeout(const Duration(seconds: 30));

          for (final item in chunk) {
            await _db.markAsSynced(item.id);
          }
        }
      }
    } catch (e) {
      print('SyncManager: Error in track batch sync: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Periodic sync
  // ---------------------------------------------------------------------------

  /// סנכרון תקופתי (כל 5 דקות כשאונליין ומאומת)
  Future<void> _runPeriodicSync() async {
    if (!_isOnline || !_isRunning || !_isAuthenticated) return;

    print('SyncManager: Running periodic sync...');

    try {
      // Pull updates from server
      await pullAll();

      // Push pending local changes
      await processSyncQueue();

      // ניקוי רשומות סנכרון ישנות
      final cleaned = await _db.cleanSyncedItems();
      if (cleaned > 0) {
        print('SyncManager: Cleaned $cleaned old synced items.');
      }
    } catch (e) {
      print('SyncManager: Error in periodic sync: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Realtime listeners (for active navigations)
  // ---------------------------------------------------------------------------

  /// הפעלת listener בזמן אמת לניווט פעיל (alerts)
  ///
  /// [navigationId] - מזהה הניווט הפעיל
  void startRealtimeListener(String navigationId) {
    final listenerId = 'alerts_$navigationId';
    if (_realtimeListeners.containsKey(listenerId)) return;

    print('SyncManager: Starting realtime listener for alerts on navigation $navigationId');

    final subscription = _firestore
        .collection(AppConstants.navigationsCollection)
        .doc(navigationId)
        .collection('alerts')
        .snapshots()
        .listen(
      (snapshot) {
        for (final change in snapshot.docChanges) {
          final data = change.doc.data();
          if (data != null) {
            data['id'] = change.doc.id;
            _handleRealtimeAlert(navigationId, change.type, data);
          }
        }
      },
      onError: (e) {
        print('SyncManager: Realtime listener error for $listenerId: $e');
      },
    );

    _realtimeListeners[listenerId] = subscription;
  }

  /// עצירת listener בזמן אמת
  void stopRealtimeListener(String navigationId) {
    final listenerId = 'alerts_$navigationId';
    _realtimeListeners[listenerId]?.cancel();
    _realtimeListeners.remove(listenerId);
    print('SyncManager: Stopped realtime listener $listenerId');
  }

  /// טיפול באירוע alert בזמן אמת
  void _handleRealtimeAlert(
    String navigationId,
    DocumentChangeType changeType,
    Map<String, dynamic> data,
  ) {
    print('SyncManager: Realtime alert event ($changeType) on navigation $navigationId: ${data['id']}');
    // TODO: עדכון DB מקומי + הודעה ל-UI דרך stream/provider
  }

  // ---------------------------------------------------------------------------
  // Conflict resolution API (for UI)
  // ---------------------------------------------------------------------------

  /// קבלת כל הקונפליקטים הממתינים לפתרון
  Future<List<ConflictQueueData>> getPendingConflicts() async {
    return await _db.getPendingConflicts();
  }

  /// פתרון קונפליקט - שמירת הגרסה המקומית
  Future<void> resolveConflictKeepLocal(int conflictId) async {
    final conflicts = await _db.getPendingConflicts();
    final conflict = conflicts.firstWhere((c) => c.id == conflictId);

    final localData = jsonDecode(conflict.localDataJson) as Map<String, dynamic>;

    // Push local version to server (force)
    await _executeFirestoreOperation(
      collection: conflict.collectionName,
      documentId: conflict.recordId,
      operation: 'update',
      data: localData,
      version: conflict.serverVersion + 1,
    );

    await _db.resolveConflict(conflictId, 'local', null);
    print('SyncManager: Conflict $conflictId resolved - kept local version.');
  }

  /// פתרון קונפליקט - שמירת הגרסה מהשרת
  Future<void> resolveConflictKeepServer(int conflictId) async {
    final conflicts = await _db.getPendingConflicts();
    final conflict = conflicts.firstWhere((c) => c.id == conflictId);

    final serverData = jsonDecode(conflict.serverDataJson) as Map<String, dynamic>;

    // Update local DB with server version
    await _upsertLocalFromServer(
      conflict.collectionName,
      conflict.recordId,
      serverData,
    );

    await _db.resolveConflict(conflictId, 'server', null);
    print('SyncManager: Conflict $conflictId resolved - kept server version.');
  }

  /// פתרון קונפליקט - מיזוג ידני
  Future<void> resolveConflictMerged(
    int conflictId,
    Map<String, dynamic> mergedData,
  ) async {
    final conflicts = await _db.getPendingConflicts();
    final conflict = conflicts.firstWhere((c) => c.id == conflictId);

    // Update local DB
    await _upsertLocalFromServer(
      conflict.collectionName,
      conflict.recordId,
      mergedData,
    );

    // Push merged to server
    await _executeFirestoreOperation(
      collection: conflict.collectionName,
      documentId: conflict.recordId,
      operation: 'update',
      data: mergedData,
      version: conflict.serverVersion + 1,
    );

    await _db.resolveConflict(conflictId, 'merged', jsonEncode(mergedData));
    print('SyncManager: Conflict $conflictId resolved - used merged data.');
  }

  // ---------------------------------------------------------------------------
  // Status & diagnostics
  // ---------------------------------------------------------------------------

  /// האם אונליין
  bool get isOnline => _isOnline;

  /// האם כרגע בסנכרון פעיל
  bool get isSyncing => _isSyncing;

  /// מספר פריטים בתור הסנכרון
  Future<int> getPendingSyncCount() async {
    return await _db.getPendingSyncCount();
  }

  /// מספר קונפליקטים ממתינים
  Future<int> getPendingConflictCount() async {
    final conflicts = await _db.getPendingConflicts();
    return conflicts.length;
  }

  /// קבלת סטטוס סנכרון מפורט
  Future<Map<String, dynamic>> getSyncStatus() async {
    final pendingCount = await getPendingSyncCount();
    final conflictCount = await getPendingConflictCount();

    return {
      'isOnline': _isOnline,
      'isRunning': _isRunning,
      'isSyncing': _isSyncing,
      'pendingSyncCount': pendingCount,
      'pendingConflictCount': conflictCount,
      'realtimeListeners': _realtimeListeners.keys.toList(),
    };
  }

  // ---------------------------------------------------------------------------
  // Utility helpers
  // ---------------------------------------------------------------------------

  /// חישוב exponential backoff (ms)
  int _calculateBackoff(int retryCount) {
    // 1s, 2s, 4s, 8s, 16s, 32s, 60s max
    final baseMs = 1000;
    final maxMs = 60000;
    final backoff = baseMs * (1 << (retryCount - 1));
    return backoff > maxMs ? maxMs : backoff;
  }

  /// פירוק JSON list בטוח
  List<dynamic> _parseJsonList(dynamic value) {
    if (value == null) return [];
    if (value is List) return value;
    if (value is String) {
      try {
        final parsed = jsonDecode(value);
        if (parsed is List) return parsed;
      } catch (_) {}
    }
    return [];
  }

  /// מפתח ייחודי לנקודת track (לזיהוי כפילויות)
  String _trackPointKey(dynamic point) {
    if (point is Map) {
      final lat = point['lat'] ?? point['latitude'] ?? '';
      final lng = point['lng'] ?? point['longitude'] ?? '';
      final time = point['timestamp'] ?? point['time'] ?? '';
      return '$lat,$lng,$time';
    }
    return point.toString();
  }

  /// ניקוי Map מאובייקטי Firestore (Timestamp) לפני jsonEncode
  Map<String, dynamic> _sanitizeForJson(Map<String, dynamic> data) {
    return data.map((key, value) {
      if (value is Timestamp) {
        return MapEntry(key, value.toDate().toIso8601String());
      } else if (value is DateTime) {
        return MapEntry(key, value.toIso8601String());
      } else if (value is Map<String, dynamic>) {
        return MapEntry(key, _sanitizeForJson(value));
      } else if (value is List) {
        return MapEntry(key, value.map((item) {
          if (item is Map<String, dynamic>) return _sanitizeForJson(item);
          if (item is Timestamp) return item.toDate().toIso8601String();
          if (item is DateTime) return item.toIso8601String();
          return item;
        }).toList());
      }
      return MapEntry(key, value);
    });
  }

  /// פירוק DateTime מ-Firestore
  DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is Timestamp) return value.toDate();
    if (value is String) {
      return DateTime.tryParse(value);
    }
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    return null;
  }
}
