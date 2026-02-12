/// קבועים גלובליים של האפליקציה
class AppConstants {
  // App Info
  static const String appName = 'Navigate';
  static const String appVersion = '1.0.0';

  // =========================================================================
  // Firebase Collections -- Top-level
  // =========================================================================
  static const String usersCollection = 'users';
  static const String unitsCollection = 'units';
  static const String areasCollection = 'areas';
  static const String navigatorTreesCollection = 'navigator_trees';
  static const String navigationsCollection = 'navigations';
  static const String navigationTracksCollection = 'navigation_tracks';
  static const String navigationApprovalCollection = 'navigation_approval';
  static const String syncMetadataCollection = 'sync_metadata';

  // =========================================================================
  // Global layer collections (under /areas/{areaId}/ OR flat top-level)
  // =========================================================================
  // Flat top-level (legacy, still used by SyncManager pull)
  static const String layersNzCollection = 'layers_nz';
  static const String layersNbCollection = 'layers_nb';
  static const String layersGgCollection = 'layers_gg';
  static const String layersBaCollection = 'layers_ba';

  // Area-scoped subcollection names
  static const String areaLayersNzSubcollection = 'layers_nz';
  static const String areaLayersNbSubcollection = 'layers_nb';
  static const String areaLayersGgSubcollection = 'layers_gg';
  static const String areaLayersBaSubcollection = 'layers_ba';

  // =========================================================================
  // Unit subcollections -- /units/{unitId}/members/{userId}
  // =========================================================================
  static const String unitMembersSubcollection = 'members';

  // =========================================================================
  // Navigation tree subcollections
  // /navigation_trees/{treeId}/frameworks/{frameworkId}
  // /navigation_trees/{treeId}/frameworks/{fId}/sub_frameworks/{sfId}
  // =========================================================================
  static const String treeFrameworksSubcollection = 'frameworks';
  static const String treeSubFrameworksSubcollection = 'sub_frameworks';

  // =========================================================================
  // Per-navigation subcollections (under /navigations/{navId}/)
  // =========================================================================
  static const String navLayersNzSubcollection = 'nav_layers_nz';
  static const String navLayersNbSubcollection = 'nav_layers_nb';
  static const String navLayersGgSubcollection = 'nav_layers_gg';
  static const String navLayersBaSubcollection = 'nav_layers_ba';
  static const String navRoutesSubcollection = 'routes';
  static const String navTracksSubcollection = 'tracks';
  static const String navPunchesSubcollection = 'punches';
  static const String navAlertsSubcollection = 'alerts';
  static const String navViolationsSubcollection = 'violations';
  static const String navScoresSubcollection = 'scores';

  // =========================================================================
  // Helper methods for building Firestore paths
  // =========================================================================

  /// /units/{unitId}/members
  static String unitMembersPath(String unitId) =>
      '$unitsCollection/$unitId/$unitMembersSubcollection';

  /// /areas/{areaId}/layers_nz
  static String areaLayersNzPath(String areaId) =>
      '$areasCollection/$areaId/$areaLayersNzSubcollection';

  /// /areas/{areaId}/layers_nb
  static String areaLayersNbPath(String areaId) =>
      '$areasCollection/$areaId/$areaLayersNbSubcollection';

  /// /areas/{areaId}/layers_gg
  static String areaLayersGgPath(String areaId) =>
      '$areasCollection/$areaId/$areaLayersGgSubcollection';

  /// /areas/{areaId}/layers_ba
  static String areaLayersBaPath(String areaId) =>
      '$areasCollection/$areaId/$areaLayersBaSubcollection';

  /// /navigation_trees/{treeId}/frameworks
  static String treeFrameworksPath(String treeId) =>
      '$navigatorTreesCollection/$treeId/$treeFrameworksSubcollection';

  /// /navigations/{navId}/nav_layers_nz
  static String navLayersNzPath(String navId) =>
      '$navigationsCollection/$navId/$navLayersNzSubcollection';

  /// /navigations/{navId}/nav_layers_nb
  static String navLayersNbPath(String navId) =>
      '$navigationsCollection/$navId/$navLayersNbSubcollection';

  /// /navigations/{navId}/nav_layers_gg
  static String navLayersGgPath(String navId) =>
      '$navigationsCollection/$navId/$navLayersGgSubcollection';

  /// /navigations/{navId}/nav_layers_ba
  static String navLayersBaPath(String navId) =>
      '$navigationsCollection/$navId/$navLayersBaSubcollection';

  /// /navigations/{navId}/routes
  static String navRoutesPath(String navId) =>
      '$navigationsCollection/$navId/$navRoutesSubcollection';

  /// /navigations/{navId}/tracks
  static String navTracksPath(String navId) =>
      '$navigationsCollection/$navId/$navTracksSubcollection';

  /// /navigations/{navId}/punches
  static String navPunchesPath(String navId) =>
      '$navigationsCollection/$navId/$navPunchesSubcollection';

  /// /navigations/{navId}/alerts
  static String navAlertsPath(String navId) =>
      '$navigationsCollection/$navId/$navAlertsSubcollection';

  /// /navigations/{navId}/violations
  static String navViolationsPath(String navId) =>
      '$navigationsCollection/$navId/$navViolationsSubcollection';

  /// /navigations/{navId}/scores
  static String navScoresPath(String navId) =>
      '$navigationsCollection/$navId/$navScoresSubcollection';

  // User Roles
  static const String roleAdmin = 'admin';
  static const String roleDeveloper = 'developer';
  static const String roleUnitAdmin = 'unit_admin';
  static const String roleCommander = 'commander';
  static const String roleNavigator = 'navigator';

  // Navigation Status
  static const String navStatusPreparation = 'preparation';
  static const String navStatusReady = 'ready';
  static const String navStatusLearning = 'learning';
  static const String navStatusSystemCheck = 'system_check';
  static const String navStatusWaiting = 'waiting';
  static const String navStatusActive = 'active';
  static const String navStatusApproval = 'approval';
  static const String navStatusReview = 'review';

  // Checkpoint Types
  static const String checkpointTypeNormal = 'checkpoint';
  static const String checkpointTypeMandatory = 'mandatory_passage';
  static const String checkpointTypeStart = 'start';
  static const String checkpointTypeEnd = 'end';

  // Checkpoint Colors
  static const String colorBlue = 'blue';
  static const String colorGreen = 'green';
  static const String colorRed = 'red';
  static const String colorBlack = 'black';

  // Tree Types
  static const String treeTypeSingle = 'single';
  static const String treeTypePairsGroup = 'pairs_group';
  static const String treeTypeSecured = 'secured';

  // Distribution Methods
  static const String distributionManualFull = 'manual_full';
  static const String distributionManualComputerized = 'manual_computerized';
  static const String distributionAutomatic = 'automatic';

  // Navigation Types (for automatic distribution)
  static const String navTypeRegular = 'regular';
  static const String navTypeClusters = 'clusters';
  static const String navTypeEggs = 'eggs';
  static const String navTypeStar = 'star';

  // Execution Order
  static const String executionOrderBySequence = 'by_sequence';
  static const String executionOrderByChoice = 'by_choice';

  // GPS Settings
  static const int defaultGpsUpdateInterval = 30; // seconds
  static const double defaultGpsAccuracyHigh = 10.0; // meters
  static const double defaultGpsAccuracyMedium = 50.0; // meters

  // Route Constraints
  static const int minCheckpointsPerNavigator = 1;
  static const int maxCheckpointsPerNavigator = 10;

  // Local Storage Keys
  static const String keyUserId = 'user_id';
  static const String keyUserRole = 'user_role';
  static const String keyLastSync = 'last_sync';
  static const String keyOfflineMode = 'offline_mode';
}
