import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart';
import '../../core/constants/app_constants.dart';
import '../../domain/entities/navigation.dart' as domain;
import '../../domain/entities/navigation_settings.dart' as domain;
import '../datasources/local/app_database.dart';
import '../sync/sync_manager.dart';

/// Navigation repository -- local DB CRUD + Firestore subcollection helpers
///
/// Firestore structure:
///   /navigations/{navId}                              -- navigation document
///   /navigations/{navId}/nav_layers_nz/{id}           -- per-nav NZ checkpoints
///   /navigations/{navId}/nav_layers_nb/{id}           -- per-nav NB safety points
///   /navigations/{navId}/nav_layers_gg/{id}           -- per-nav GG boundaries
///   /navigations/{navId}/nav_layers_ba/{id}           -- per-nav BA clusters
///   /navigations/{navId}/routes/{navigatorId}         -- assigned routes
///   /navigations/{navId}/tracks/{trackId}             -- GPS tracks
///   /navigations/{navId}/punches/{punchId}            -- checkpoint punches
///   /navigations/{navId}/alerts/{alertId}             -- emergency alerts
///   /navigations/{navId}/violations/{violationId}     -- security violations
///   /navigations/{navId}/scores/{navigatorId}         -- scoring
class NavigationRepository {
  final AppDatabase _db = AppDatabase();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final SyncManager _syncManager = SyncManager();

  /// קבלת כל הניווטים
  Future<List<domain.Navigation>> getAll() async {
    try {
      print('DEBUG: Loading navigations from local database');
      final navigations = await _db.select(_db.navigations).get();
      print('DEBUG: Found ${navigations.length} navigations');
      return navigations.map((n) => _toDomain(n)).toList();
    } catch (e) {
      print('DEBUG: Error loading navigations: $e');
      rethrow;
    }
  }

  /// קבלת ניווט לפי ID
  Future<domain.Navigation?> getById(String id) async {
    try {
      final navigation = await (_db.select(_db.navigations)
            ..where((n) => n.id.equals(id)))
          .getSingleOrNull();
      return navigation != null ? _toDomain(navigation) : null;
    } catch (e) {
      rethrow;
    }
  }

  /// יצירת ניווט חדש
  Future<domain.Navigation> create(domain.Navigation navigation) async {
    try {
      print('DEBUG: Creating navigation: ${navigation.name}');

      // שמירה מקומית
      await _db.into(_db.navigations).insert(
            NavigationsCompanion.insert(
              id: navigation.id,
              name: navigation.name,
              status: navigation.status,
              createdBy: navigation.createdBy,
              treeId: navigation.treeId,
              areaId: navigation.areaId,
              frameworkId: Value(navigation.selectedUnitId),
              selectedSubFrameworkIdsJson: Value(navigation.selectedSubFrameworkIds.isNotEmpty
                  ? jsonEncode(navigation.selectedSubFrameworkIds)
                  : null),
              selectedParticipantIdsJson: Value(navigation.selectedParticipantIds.isNotEmpty
                  ? jsonEncode(navigation.selectedParticipantIds)
                  : null),
              layerNzId: navigation.layerNzId,
              layerNbId: navigation.layerNbId,
              layerGgId: navigation.layerGgId,
              layerBaId: Value(navigation.layerBaId),
              distributionMethod: navigation.distributionMethod,
              navigationType: Value(navigation.navigationType),
              executionOrder: Value(navigation.executionOrder),
              boundaryLayerId: Value(navigation.boundaryLayerId),
              routeLengthJson: Value(navigation.routeLengthKm != null
                  ? jsonEncode(navigation.routeLengthKm!.toMap())
                  : null),
              distributeNow: Value(navigation.distributeNow),
              safetyTimeJson: Value(navigation.safetyTime != null
                  ? jsonEncode(navigation.safetyTime!.toMap())
                  : null),
              learningSettingsJson: jsonEncode(navigation.learningSettings.toMap()),
              verificationSettingsJson: jsonEncode(navigation.verificationSettings.toMap()),
              allowOpenMap: Value(navigation.allowOpenMap),
              showSelfLocation: Value(navigation.showSelfLocation),
              showRouteOnMap: Value(navigation.showRouteOnMap),
              alertsJson: jsonEncode(navigation.alerts.toMap()),
              reviewSettingsJson: Value(jsonEncode(navigation.reviewSettings.toMap())),
              displaySettingsJson: jsonEncode(navigation.displaySettings.toMap()),
              routesJson: jsonEncode(navigation.routes.map((k, v) => MapEntry(k, v.toMap()))),
              routesStage: Value(navigation.routesStage),
              routesDistributed: Value(navigation.routesDistributed),
              trainingStartTime: Value(navigation.trainingStartTime),
              systemCheckStartTime: Value(navigation.systemCheckStartTime),
              activeStartTime: Value(navigation.activeStartTime),
              gpsUpdateIntervalSeconds: navigation.gpsUpdateIntervalSeconds,
              permissionsJson: jsonEncode(navigation.permissions.toMap()),
              createdAt: navigation.createdAt,
              updatedAt: navigation.updatedAt,
            ),
          );

      print('DEBUG: Navigation saved locally');

      // הוספה לתור סנכרון
      await _syncManager.queueOperation(
        collection: AppConstants.navigationsCollection,
        documentId: navigation.id,
        operation: 'create',
        data: navigation.toMap(),
        priority: SyncPriority.high,
      );

      print('DEBUG: Navigation queued for sync');

      return navigation;
    } catch (e) {
      print('DEBUG: Error creating navigation: $e');
      rethrow;
    }
  }

  /// עדכון ניווט
  Future<domain.Navigation> update(domain.Navigation navigation) async {
    try {
      print('DEBUG: Updating navigation: ${navigation.name}');

      // עדכון מקומי
      await (_db.update(_db.navigations)..where((n) => n.id.equals(navigation.id)))
          .write(
        NavigationsCompanion(
          name: Value(navigation.name),
          status: Value(navigation.status),
          frameworkId: Value(navigation.selectedUnitId),
          selectedSubFrameworkIdsJson: Value(navigation.selectedSubFrameworkIds.isNotEmpty
              ? jsonEncode(navigation.selectedSubFrameworkIds)
              : null),
          selectedParticipantIdsJson: Value(navigation.selectedParticipantIds.isNotEmpty
              ? jsonEncode(navigation.selectedParticipantIds)
              : null),
          navigationType: Value(navigation.navigationType),
          executionOrder: Value(navigation.executionOrder),
          boundaryLayerId: Value(navigation.boundaryLayerId),
          routeLengthJson: Value(navigation.routeLengthKm != null
              ? jsonEncode(navigation.routeLengthKm!.toMap())
              : null),
          distributeNow: Value(navigation.distributeNow),
          safetyTimeJson: Value(navigation.safetyTime != null
              ? jsonEncode(navigation.safetyTime!.toMap())
              : null),
          learningSettingsJson: Value(jsonEncode(navigation.learningSettings.toMap())),
          verificationSettingsJson: Value(jsonEncode(navigation.verificationSettings.toMap())),
          allowOpenMap: Value(navigation.allowOpenMap),
          showSelfLocation: Value(navigation.showSelfLocation),
          showRouteOnMap: Value(navigation.showRouteOnMap),
          alertsJson: Value(jsonEncode(navigation.alerts.toMap())),
          reviewSettingsJson: Value(jsonEncode(navigation.reviewSettings.toMap())),
          displaySettingsJson: Value(jsonEncode(navigation.displaySettings.toMap())),
          routesJson: Value(jsonEncode(navigation.routes.map((k, v) => MapEntry(k, v.toMap())))),
          routesStage: Value(navigation.routesStage),
          routesDistributed: Value(navigation.routesDistributed),
          trainingStartTime: Value(navigation.trainingStartTime),
          systemCheckStartTime: Value(navigation.systemCheckStartTime),
          activeStartTime: Value(navigation.activeStartTime),
          permissionsJson: Value(jsonEncode(navigation.permissions.toMap())),
          updatedAt: Value(navigation.updatedAt),
        ),
      );

      print('DEBUG: Navigation updated locally');

      // הוספה לתור סנכרון
      await _syncManager.queueOperation(
        collection: AppConstants.navigationsCollection,
        documentId: navigation.id,
        operation: 'update',
        data: navigation.toMap(),
        priority: SyncPriority.high,
      );

      return navigation;
    } catch (e) {
      print('DEBUG: Error updating navigation: $e');
      rethrow;
    }
  }

  /// מחיקת ניווט
  Future<void> delete(String id) async {
    try {
      print('DEBUG: Deleting navigation: $id');

      // מחיקה מקומית
      await (_db.delete(_db.navigations)..where((n) => n.id.equals(id))).go();

      print('DEBUG: Navigation deleted locally');

      // הוספה לתור סנכרון — עדיפות גבוהה למחיקות
      await _syncManager.queueOperation(
        collection: AppConstants.navigationsCollection,
        documentId: id,
        operation: 'delete',
        data: {'id': id},
        priority: SyncPriority.high,
      );
    } catch (e) {
      print('DEBUG: Error deleting navigation: $e');
      rethrow;
    }
  }

  /// קבלת ניווטים לפי treeId
  Future<List<domain.Navigation>> getByTreeId(String treeId) async {
    try {
      final rows = await (_db.select(_db.navigations)
            ..where((n) => n.treeId.equals(treeId)))
          .get();
      return rows.map((r) => _toDomain(r)).toList();
    } catch (e) {
      print('DEBUG: Error loading navigations by treeId: $e');
      return [];
    }
  }

  /// המרה מטבלת DB לישות דומיין
  /// JSON string → Map, או null אם הנתון הוא List/invalid
  Map<String, dynamic>? _parseJsonAsMap(String json) {
    final decoded = jsonDecode(json);
    if (decoded is Map<String, dynamic>) return decoded;
    return null;
  }

  Map<String, domain.AssignedRoute> _parseRoutes(String routesJson) {
    final decoded = jsonDecode(routesJson);
    if (decoded is Map<String, dynamic>) {
      return decoded.map(
        (k, v) => MapEntry(k, domain.AssignedRoute.fromMap(v as Map<String, dynamic>)),
      );
    }
    return {};
  }

  domain.Navigation _toDomain(Navigation data) {
    return domain.Navigation(
      id: data.id,
      name: data.name,
      status: data.status,
      createdBy: data.createdBy,
      treeId: data.treeId,
      areaId: data.areaId,
      selectedUnitId: data.frameworkId,
      selectedSubFrameworkIds: data.selectedSubFrameworkIdsJson != null
          ? List<String>.from(jsonDecode(data.selectedSubFrameworkIdsJson!) as List)
          : const [],
      selectedParticipantIds: data.selectedParticipantIdsJson != null
          ? List<String>.from(jsonDecode(data.selectedParticipantIdsJson!) as List)
          : const [],
      layerNzId: data.layerNzId,
      layerNbId: data.layerNbId,
      layerGgId: data.layerGgId,
      layerBaId: data.layerBaId,
      distributionMethod: data.distributionMethod,
      navigationType: data.navigationType,
      executionOrder: data.executionOrder,
      boundaryLayerId: data.boundaryLayerId,
      routeLengthKm: data.routeLengthJson != null
          ? domain.RouteLengthRange.fromMap(
              jsonDecode(data.routeLengthJson!) as Map<String, dynamic>,
            )
          : null,
      checkpointsPerNavigator: null,
      startPoint: null,
      endPoint: null,
      distributeNow: data.distributeNow,
      safetyTime: data.safetyTimeJson != null
          ? domain.SafetyTimeSettings.fromMap(
              jsonDecode(data.safetyTimeJson!) as Map<String, dynamic>,
            )
          : null,
      learningSettings: _parseJsonAsMap(data.learningSettingsJson) != null
          ? domain.LearningSettings.fromMap(_parseJsonAsMap(data.learningSettingsJson)!)
          : domain.LearningSettings(),
      verificationSettings: _parseJsonAsMap(data.verificationSettingsJson) != null
          ? domain.VerificationSettings.fromMap(_parseJsonAsMap(data.verificationSettingsJson)!)
          : const domain.VerificationSettings(autoVerification: false),
      allowOpenMap: data.allowOpenMap,
      showSelfLocation: data.showSelfLocation,
      showRouteOnMap: data.showRouteOnMap,
      alerts: _parseJsonAsMap(data.alertsJson) != null
          ? domain.NavigationAlerts.fromMap(_parseJsonAsMap(data.alertsJson)!)
          : const domain.NavigationAlerts(enabled: false),
      reviewSettings: _parseJsonAsMap(data.reviewSettingsJson) != null
          ? domain.ReviewSettings.fromMap(_parseJsonAsMap(data.reviewSettingsJson)!)
          : domain.ReviewSettings(),
      displaySettings: _parseJsonAsMap(data.displaySettingsJson) != null
          ? domain.DisplaySettings.fromMap(_parseJsonAsMap(data.displaySettingsJson)!)
          : domain.DisplaySettings(),
      routes: _parseRoutes(data.routesJson),
      routesStage: data.routesStage,
      routesDistributed: data.routesDistributed,
      trainingStartTime: data.trainingStartTime,
      systemCheckStartTime: data.systemCheckStartTime,
      activeStartTime: data.activeStartTime,
      gpsUpdateIntervalSeconds: data.gpsUpdateIntervalSeconds,
      permissions: _parseJsonAsMap(data.permissionsJson) != null
          ? domain.NavigationPermissions.fromMap(_parseJsonAsMap(data.permissionsJson)!)
          : const domain.NavigationPermissions(managers: [], viewers: []),
      createdAt: data.createdAt,
      updatedAt: data.updatedAt,
    );
  }

  // ===========================================================================
  // Navigation-scoped subcollection helpers (Firestore)
  // ===========================================================================
  //
  // These methods write directly through the sync queue using subcollection
  // paths.  The SyncManager._executeFirestoreOperation already handles
  // arbitrary collection paths (including subcollections such as
  // "navigations/{navId}/tracks").

  // ----------------------------- Tracks ------------------------------------

  /// Queue a GPS track document for push to /navigations/{navId}/tracks/{trackId}
  Future<void> pushTrack({
    required String navigationId,
    required String trackId,
    required Map<String, dynamic> trackData,
  }) async {
    try {
      await _syncManager.queueOperation(
        collection: AppConstants.navTracksPath(navigationId),
        documentId: trackId,
        operation: 'create',
        data: trackData,
        priority: SyncPriority.normal,
      );
      print('DEBUG: Track $trackId queued for navigation $navigationId');
    } catch (e) {
      print('DEBUG: Error queuing track: $e');
      rethrow;
    }
  }

  /// Update an existing track document
  Future<void> updateTrack({
    required String navigationId,
    required String trackId,
    required Map<String, dynamic> trackData,
  }) async {
    try {
      await _syncManager.queueOperation(
        collection: AppConstants.navTracksPath(navigationId),
        documentId: trackId,
        operation: 'update',
        data: trackData,
      );
    } catch (e) {
      print('DEBUG: Error queuing track update: $e');
      rethrow;
    }
  }

  /// Fetch all tracks for a navigation directly from Firestore
  Future<List<Map<String, dynamic>>> fetchTracksFromFirestore(
    String navigationId,
  ) async {
    try {
      final snapshot = await _firestore
          .collection(AppConstants.navigationsCollection)
          .doc(navigationId)
          .collection(AppConstants.navTracksSubcollection)
          .get()
          .timeout(const Duration(seconds: 15));

      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      print('DEBUG: Error fetching tracks from Firestore: $e');
      return [];
    }
  }

  // ----------------------------- Punches -----------------------------------

  /// Queue a checkpoint punch for push to /navigations/{navId}/punches/{punchId}
  Future<void> pushPunch({
    required String navigationId,
    required String punchId,
    required Map<String, dynamic> punchData,
  }) async {
    try {
      await _syncManager.queueOperation(
        collection: AppConstants.navPunchesPath(navigationId),
        documentId: punchId,
        operation: 'create',
        data: punchData,
        priority: SyncPriority.high,
      );
      print('DEBUG: Punch $punchId queued for navigation $navigationId');
    } catch (e) {
      print('DEBUG: Error queuing punch: $e');
      rethrow;
    }
  }

  /// Update a punch (e.g. approval/rejection)
  Future<void> updatePunch({
    required String navigationId,
    required String punchId,
    required Map<String, dynamic> punchData,
  }) async {
    try {
      await _syncManager.queueOperation(
        collection: AppConstants.navPunchesPath(navigationId),
        documentId: punchId,
        operation: 'update',
        data: punchData,
      );
    } catch (e) {
      print('DEBUG: Error queuing punch update: $e');
      rethrow;
    }
  }

  /// Fetch all punches for a navigation directly from Firestore
  Future<List<Map<String, dynamic>>> fetchPunchesFromFirestore(
    String navigationId,
  ) async {
    try {
      final snapshot = await _firestore
          .collection(AppConstants.navigationsCollection)
          .doc(navigationId)
          .collection(AppConstants.navPunchesSubcollection)
          .get()
          .timeout(const Duration(seconds: 15));

      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      print('DEBUG: Error fetching punches from Firestore: $e');
      return [];
    }
  }

  // ----------------------------- Alerts ------------------------------------

  /// Queue an alert for push to /navigations/{navId}/alerts/{alertId}
  Future<void> pushAlert({
    required String navigationId,
    required String alertId,
    required Map<String, dynamic> alertData,
  }) async {
    try {
      await _syncManager.queueOperation(
        collection: AppConstants.navAlertsPath(navigationId),
        documentId: alertId,
        operation: 'create',
        data: alertData,
        priority: SyncPriority.realtime,
      );
      print('DEBUG: Alert $alertId queued for navigation $navigationId');
    } catch (e) {
      print('DEBUG: Error queuing alert: $e');
      rethrow;
    }
  }

  /// Update an alert (e.g. resolve)
  Future<void> updateAlert({
    required String navigationId,
    required String alertId,
    required Map<String, dynamic> alertData,
  }) async {
    try {
      await _syncManager.queueOperation(
        collection: AppConstants.navAlertsPath(navigationId),
        documentId: alertId,
        operation: 'update',
        data: alertData,
        priority: SyncPriority.realtime,
      );
    } catch (e) {
      print('DEBUG: Error queuing alert update: $e');
      rethrow;
    }
  }

  /// Fetch all alerts for a navigation directly from Firestore
  Future<List<Map<String, dynamic>>> fetchAlertsFromFirestore(
    String navigationId,
  ) async {
    try {
      final snapshot = await _firestore
          .collection(AppConstants.navigationsCollection)
          .doc(navigationId)
          .collection(AppConstants.navAlertsSubcollection)
          .get()
          .timeout(const Duration(seconds: 15));

      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      print('DEBUG: Error fetching alerts from Firestore: $e');
      return [];
    }
  }

  /// Listen for realtime alert changes on an active navigation
  Stream<QuerySnapshot<Map<String, dynamic>>> watchAlertsRealtime(
    String navigationId,
  ) {
    return _firestore
        .collection(AppConstants.navigationsCollection)
        .doc(navigationId)
        .collection(AppConstants.navAlertsSubcollection)
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  // ----------------------------- Violations --------------------------------

  /// Queue a security violation for push to
  /// /navigations/{navId}/violations/{violationId}
  Future<void> pushViolation({
    required String navigationId,
    required String violationId,
    required Map<String, dynamic> violationData,
  }) async {
    try {
      await _syncManager.queueOperation(
        collection: AppConstants.navViolationsPath(navigationId),
        documentId: violationId,
        operation: 'create',
        data: violationData,
        priority: SyncPriority.high,
      );
      print('DEBUG: Violation $violationId queued for navigation $navigationId');
    } catch (e) {
      print('DEBUG: Error queuing violation: $e');
      rethrow;
    }
  }

  /// Fetch all violations for a navigation directly from Firestore
  Future<List<Map<String, dynamic>>> fetchViolationsFromFirestore(
    String navigationId,
  ) async {
    try {
      final snapshot = await _firestore
          .collection(AppConstants.navigationsCollection)
          .doc(navigationId)
          .collection(AppConstants.navViolationsSubcollection)
          .get()
          .timeout(const Duration(seconds: 15));

      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      print('DEBUG: Error fetching violations from Firestore: $e');
      return [];
    }
  }

  // ----------------------------- Scores ------------------------------------

  /// Queue a score document for push to /navigations/{navId}/scores/{navigatorId}
  Future<void> pushScore({
    required String navigationId,
    required String navigatorId,
    required Map<String, dynamic> scoreData,
  }) async {
    try {
      await _syncManager.queueOperation(
        collection: AppConstants.navScoresPath(navigationId),
        documentId: navigatorId,
        operation: 'create',
        data: scoreData,
      );
      print('DEBUG: Score for navigator $navigatorId queued');
    } catch (e) {
      print('DEBUG: Error queuing score: $e');
      rethrow;
    }
  }

  /// Fetch all scores for a navigation directly from Firestore
  Future<List<Map<String, dynamic>>> fetchScoresFromFirestore(
    String navigationId,
  ) async {
    try {
      final snapshot = await _firestore
          .collection(AppConstants.navigationsCollection)
          .doc(navigationId)
          .collection(AppConstants.navScoresSubcollection)
          .get()
          .timeout(const Duration(seconds: 15));

      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['navigatorId'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      print('DEBUG: Error fetching scores from Firestore: $e');
      return [];
    }
  }

  // ----------------------------- Routes ------------------------------------

  /// Queue a route assignment for push to /navigations/{navId}/routes/{navigatorId}
  Future<void> pushRoute({
    required String navigationId,
    required String navigatorId,
    required Map<String, dynamic> routeData,
  }) async {
    try {
      await _syncManager.queueOperation(
        collection: AppConstants.navRoutesPath(navigationId),
        documentId: navigatorId,
        operation: 'create',
        data: routeData,
      );
      print('DEBUG: Route for navigator $navigatorId queued');
    } catch (e) {
      print('DEBUG: Error queuing route: $e');
      rethrow;
    }
  }

  // ----------------------------- Realtime listeners -----------------------

  /// Listen for realtime track updates on an active navigation
  Stream<QuerySnapshot<Map<String, dynamic>>> watchTracksRealtime(
    String navigationId,
  ) {
    return _firestore
        .collection(AppConstants.navigationsCollection)
        .doc(navigationId)
        .collection(AppConstants.navTracksSubcollection)
        .snapshots();
  }

  /// Listen for realtime punch updates on an active navigation
  Stream<QuerySnapshot<Map<String, dynamic>>> watchPunchesRealtime(
    String navigationId,
  ) {
    return _firestore
        .collection(AppConstants.navigationsCollection)
        .doc(navigationId)
        .collection(AppConstants.navPunchesSubcollection)
        .snapshots();
  }

  /// Listen for realtime violation updates on an active navigation
  Stream<QuerySnapshot<Map<String, dynamic>>> watchViolationsRealtime(
    String navigationId,
  ) {
    return _firestore
        .collection(AppConstants.navigationsCollection)
        .doc(navigationId)
        .collection(AppConstants.navViolationsSubcollection)
        .snapshots();
  }

  // ----------------------------- Pull helpers ------------------------------

  /// Pull a single navigation (and optionally its subcollections) from Firestore
  Future<void> syncFromFirestore() async {
    try {
      final snapshot = await _firestore
          .collection(AppConstants.navigationsCollection)
          .get()
          .timeout(const Duration(seconds: 30));

      for (final doc in snapshot.docs) {
        final data = doc.data();
        data['id'] = doc.id;

        final existing = await getById(doc.id);
        if (existing == null) {
          // Insert into local DB (without re-queuing for sync)
          final nav = domain.Navigation.fromMap(data);
          await _db.into(_db.navigations).insert(
                NavigationsCompanion.insert(
                  id: nav.id,
                  name: nav.name,
                  status: nav.status,
                  createdBy: nav.createdBy,
                  treeId: nav.treeId,
                  areaId: nav.areaId,
                  frameworkId: Value(nav.selectedUnitId),
                  selectedSubFrameworkIdsJson: Value(nav.selectedSubFrameworkIds.isNotEmpty
                      ? jsonEncode(nav.selectedSubFrameworkIds)
                      : null),
                  selectedParticipantIdsJson: Value(nav.selectedParticipantIds.isNotEmpty
                      ? jsonEncode(nav.selectedParticipantIds)
                      : null),
                  layerNzId: nav.layerNzId,
                  layerNbId: nav.layerNbId,
                  layerGgId: nav.layerGgId,
                  layerBaId: Value(nav.layerBaId),
                  distributionMethod: nav.distributionMethod,
                  navigationType: Value(nav.navigationType),
                  executionOrder: Value(nav.executionOrder),
                  boundaryLayerId: Value(nav.boundaryLayerId),
                  routeLengthJson: Value(nav.routeLengthKm != null
                      ? jsonEncode(nav.routeLengthKm!.toMap())
                      : null),
                  distributeNow: Value(nav.distributeNow),
                  safetyTimeJson: Value(nav.safetyTime != null
                      ? jsonEncode(nav.safetyTime!.toMap())
                      : null),
                  learningSettingsJson:
                      jsonEncode(nav.learningSettings.toMap()),
                  verificationSettingsJson:
                      jsonEncode(nav.verificationSettings.toMap()),
                  allowOpenMap: Value(nav.allowOpenMap),
                  showSelfLocation: Value(nav.showSelfLocation),
                  alertsJson: jsonEncode(nav.alerts.toMap()),
                  reviewSettingsJson: Value(jsonEncode(nav.reviewSettings.toMap())),
                  displaySettingsJson:
                      jsonEncode(nav.displaySettings.toMap()),
                  routesJson: jsonEncode(
                      nav.routes.map((k, v) => MapEntry(k, v.toMap()))),
                  routesStage: Value(nav.routesStage),
                  routesDistributed: Value(nav.routesDistributed),
                  trainingStartTime: Value(nav.trainingStartTime),
                  systemCheckStartTime: Value(nav.systemCheckStartTime),
                  activeStartTime: Value(nav.activeStartTime),
                  gpsUpdateIntervalSeconds: nav.gpsUpdateIntervalSeconds,
                  permissionsJson: jsonEncode(nav.permissions.toMap()),
                  createdAt: nav.createdAt,
                  updatedAt: nav.updatedAt,
                ),
              );
        }
      }

      print('DEBUG: Synced ${snapshot.docs.length} navigations from Firestore');
    } catch (e) {
      print('DEBUG: Error syncing navigations from Firestore: $e');
    }
  }
}
