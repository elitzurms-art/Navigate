import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'dart:io';

part 'app_database.g.dart';

/// טבלת משתמשים
class Users extends Table {
  TextColumn get uid => text()();
  TextColumn get firstName => text().withDefault(const Constant(''))();
  TextColumn get lastName => text().withDefault(const Constant(''))();
  TextColumn get personalNumber => text().withDefault(const Constant(''))();
  TextColumn get fullName => text()();
  TextColumn get username => text()();
  TextColumn get phoneNumber => text()();
  BoolColumn get phoneVerified => boolean()();
  TextColumn get role => text()();
  TextColumn get email => text().withDefault(const Constant(''))();
  BoolColumn get emailVerified => boolean().withDefault(const Constant(false))();
  TextColumn get frameworkId => text().nullable()();
  TextColumn get unitId => text().nullable()();
  TextColumn get fcmToken => text().nullable()();
  TextColumn get firebaseUid => text().nullable()();
  BoolColumn get isApproved => boolean().withDefault(const Constant(false))();
  TextColumn get approvalStatus => text().nullable()();
  DateTimeColumn get soloQuizPassedAt => dateTime().nullable()();
  IntColumn get soloQuizScore => integer().nullable()();
  DateTimeColumn get commanderQuizPassedAt => dateTime().nullable()();
  IntColumn get commanderQuizScore => integer().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {uid};
}

/// טבלת יחידות
class Units extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get description => text()();
  TextColumn get type => text()(); // 'brigade', 'battalion', 'company', 'platoon'
  TextColumn get parentUnitId => text().nullable()();
  TextColumn get managerIdsJson => text()(); // JSON של מזהי מנהלים
  TextColumn get createdBy => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get isClassified => boolean().withDefault(const Constant(false))();
  IntColumn get level => integer().nullable()(); // רמת היחידה (1=אוגדה .. 5=מחלקה)
  BoolColumn get isNavigators => boolean().withDefault(const Constant(false))(); // יחידת מנווטים
  BoolColumn get isGeneral => boolean().withDefault(const Constant(false))(); // יחידה כללית
  TextColumn get checklistsJson => text().nullable()(); // JSON צ'קליסטים

  @override
  Set<Column> get primaryKey => {id};
}

/// טבלת שטחים
class Areas extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get description => text()();
  TextColumn get createdBy => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// טבלת נקודות ציון (NZ) - תומכת בנקודה ופוליגון
class Checkpoints extends Table {
  TextColumn get id => text()();
  TextColumn get areaId => text()();
  TextColumn get name => text()();
  TextColumn get description => text()();
  TextColumn get type => text()();
  TextColumn get color => text()();
  TextColumn get boundaryId => text().nullable()(); // גבול גזרה שהנקודה שייכת אליו
  TextColumn get geometryType => text().withDefault(const Constant('point'))(); // 'point' או 'polygon'
  RealColumn get lat => real()();
  RealColumn get lng => real()();
  TextColumn get utm => text()();
  TextColumn get coordinatesJson => text().nullable()(); // לפוליגון בלבד - JSON של רשימת נקודות
  IntColumn get sequenceNumber => integer()();
  TextColumn get createdBy => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// טבלת נקודות תורפה בטיחותיות (נת"ב)
class SafetyPoints extends Table {
  TextColumn get id => text()();
  TextColumn get areaId => text()();
  TextColumn get name => text()();
  TextColumn get description => text()();
  TextColumn get type => text().withDefault(const Constant('point'))(); // 'point' או 'polygon'
  RealColumn get lat => real().nullable()(); // לנקודה בלבד
  RealColumn get lng => real().nullable()(); // לנקודה בלבד
  TextColumn get utm => text().nullable()(); // לנקודה בלבד
  TextColumn get coordinatesJson => text().nullable()(); // לפוליגון בלבד - JSON של רשימת נקודות
  IntColumn get sequenceNumber => integer()();
  TextColumn get severity => text()();
  TextColumn get createdBy => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// טבלת גבולות גזרה (GG)
class Boundaries extends Table {
  TextColumn get id => text()();
  TextColumn get areaId => text()();
  TextColumn get name => text()();
  TextColumn get description => text()();
  TextColumn get coordinatesJson => text()(); // JSON של קואורדינטות הפוליגון
  TextColumn get color => text()();
  RealColumn get strokeWidth => real()();
  TextColumn get createdBy => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// טבלת ביצי איזור (BA)
class Clusters extends Table {
  TextColumn get id => text()();
  TextColumn get areaId => text()();
  TextColumn get name => text()();
  TextColumn get description => text()();
  TextColumn get coordinatesJson => text()(); // JSON של קואורדינטות הפוליגון
  TextColumn get color => text()();
  RealColumn get strokeWidth => real()();
  RealColumn get fillOpacity => real()();
  TextColumn get createdBy => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// טבלת עצי מנווטים
/// טבלת עצי ניווט
class NavigationTrees extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get frameworksJson => text()(); // JSON של מסגרות ותתי-מסגרות
  TextColumn get createdBy => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get frameworkId => text().nullable()();   // מזהה מסגרת
  TextColumn get treeType => text().nullable()();      // 'single' / 'pairs_secured'
  TextColumn get sourceTreeId => text().nullable()();  // מזהה עץ מקורי (שכפול)
  TextColumn get unitId => text().nullable()();        // מזהה יחידה

  @override
  Set<Column> get primaryKey => {id};
}

/// טבלת ניווטים
class Navigations extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get status => text()();
  TextColumn get createdBy => text()();
  TextColumn get treeId => text()();
  TextColumn get areaId => text()();
  TextColumn get frameworkId => text().nullable()();
  TextColumn get selectedSubFrameworkIdsJson => text().nullable()(); // JSON
  TextColumn get selectedParticipantIdsJson => text().nullable()(); // JSON
  TextColumn get layerNzId => text()();
  TextColumn get layerNbId => text()();
  TextColumn get layerGgId => text()();
  TextColumn get layerBaId => text().nullable()();
  TextColumn get distributionMethod => text()();
  TextColumn get navigationType => text().nullable()();
  TextColumn get executionOrder => text().nullable()();
  TextColumn get boundaryLayerId => text().nullable()();
  TextColumn get routeLengthJson => text().nullable()(); // JSON של טווח מרחק
  TextColumn get startPoint => text().nullable()(); // נקודת התחלה משותפת
  TextColumn get endPoint => text().nullable()(); // נקודת סיום משותפת
  IntColumn get checkpointsPerNavigator => integer().nullable()(); // נקודות למנווט
  TextColumn get waypointSettingsJson => text().nullable()(); // JSON נקודות ביניים
  TextColumn get scoringCriterion => text().nullable()(); // קריטריון חלוקה
  BoolColumn get distributeNow => boolean().withDefault(const Constant(false))();
  TextColumn get safetyTimeJson => text().nullable()(); // JSON של זמן בטיחות
  TextColumn get learningSettingsJson => text()(); // JSON של הגדרות למידה
  TextColumn get verificationSettingsJson => text()(); // JSON של הגדרות אימות
  BoolColumn get allowOpenMap => boolean().withDefault(const Constant(false))();
  BoolColumn get showSelfLocation => boolean().withDefault(const Constant(false))();
  BoolColumn get showRouteOnMap => boolean().withDefault(const Constant(false))();
  TextColumn get alertsJson => text()(); // JSON של התראות
  TextColumn get displaySettingsJson => text()(); // JSON של הגדרות תצוגה
  TextColumn get routesJson => text()(); // JSON של מסלולים מוקצים
  TextColumn get routesStage => text().nullable()(); // שלב תהליך הצירים
  BoolColumn get routesDistributed => boolean().withDefault(const Constant(false))(); // האם חולקו צירים
  IntColumn get gpsUpdateIntervalSeconds => integer()();
  TextColumn get enabledPositionSourcesJson => text().withDefault(const Constant('["gps","cellTower","pdr","pdrCellHybrid"]'))();
  BoolColumn get allowManualPosition => boolean().withDefault(const Constant(false))();
  BoolColumn get gpsSpoofingDetectionEnabled => boolean().withDefault(const Constant(true))();
  IntColumn get gpsSpoofingMaxDistanceKm => integer().withDefault(const Constant(50))();
  TextColumn get reviewSettingsJson => text().withDefault(const Constant('{"showScoresAfterApproval":true}'))();
  TextColumn get timeCalculationSettingsJson => text().withDefault(const Constant('{"enabled":true,"isHeavyLoad":false,"isNightNavigation":false,"isSummer":true}'))();
  TextColumn get communicationSettingsJson => text().withDefault(const Constant('{"walkieTalkieEnabled":false}'))();
  TextColumn get variablesSheetJson => text().nullable()();
  TextColumn get forceCompositionJson => text().nullable()();
  IntColumn get starLearningMinutes => integer().nullable()();
  IntColumn get starNavigatingMinutes => integer().nullable()();
  BoolColumn get starAutoMode => boolean().withDefault(const Constant(false))();
  TextColumn get clusterSettingsJson => text().nullable()(); // JSON הגדרות אשכולות
  TextColumn get parachuteSettingsJson => text().nullable()(); // JSON הגדרות צנחנים
  TextColumn get permissionsJson => text()();
  DateTimeColumn get trainingStartTime => dateTime().nullable()();
  DateTimeColumn get systemCheckStartTime => dateTime().nullable()();
  DateTimeColumn get activeStartTime => dateTime().nullable()();
  TextColumn get checklistCompletionJson => text().nullable()(); // JSON מילוי צ'קליסטים
  DateTimeColumn get deletedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// טבלת מסלולי GPS (track points)
class NavigationTracks extends Table {
  TextColumn get id => text()();
  TextColumn get navigationId => text()();
  TextColumn get navigatorUserId => text()();
  TextColumn get trackPointsJson => text()(); // JSON של נקודות מסלול
  TextColumn get stabbingsJson => text()(); // JSON של דקירות
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  BoolColumn get isActive => boolean()();
  BoolColumn get isDisqualified => boolean()();
  BoolColumn get overrideAllowOpenMap => boolean().withDefault(const Constant(false))();
  BoolColumn get overrideShowSelfLocation => boolean().withDefault(const Constant(false))();
  BoolColumn get overrideShowRouteOnMap => boolean().withDefault(const Constant(false))();
  BoolColumn get overrideAllowManualPosition => boolean().withDefault(const Constant(false))();
  BoolColumn get overrideWalkieTalkieEnabled => boolean().withDefault(const Constant(false))();
  TextColumn get overrideEnabledPositionSourcesJson => text().nullable()();
  BoolColumn get manualPositionUsed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get manualPositionUsedAt => dateTime().nullable()();
  BoolColumn get isGroupSecondary => boolean().withDefault(const Constant(false))();
  IntColumn get starCurrentPointIndex => integer().nullable()();
  DateTimeColumn get starLearningEndTime => dateTime().nullable()();
  DateTimeColumn get starNavigatingEndTime => dateTime().nullable()();
  BoolColumn get starReturnedToCenter => boolean().withDefault(const Constant(false))();
  BoolColumn get overrideRevealEnabled => boolean().nullable()(); // nullable: null=nav default, true=force open, false=force closed

  @override
  Set<Column> get primaryKey => {id};
}

/// טבלת נקודות ציון לניווט ספציפי (NZ per-navigation) - תומכת בנקודה ופוליגון
class NavCheckpoints extends Table {
  TextColumn get id => text()();
  TextColumn get navigationId => text()();
  TextColumn get sourceId => text()(); // מזהה נקודת הציון המקורית
  TextColumn get areaId => text()();
  TextColumn get name => text()();
  TextColumn get description => text()();
  TextColumn get type => text()();
  TextColumn get color => text()();
  TextColumn get geometryType => text().withDefault(const Constant('point'))(); // 'point' או 'polygon'
  RealColumn get lat => real()();
  RealColumn get lng => real()();
  TextColumn get utm => text()();
  TextColumn get coordinatesJson => text().nullable()(); // לפוליגון בלבד
  IntColumn get sequenceNumber => integer()();
  TextColumn get labelsJson => text().withDefault(const Constant('[]'))();
  TextColumn get createdBy => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// טבלת נקודות תורפה בטיחותיות לניווט ספציפי (NB per-navigation)
class NavSafetyPoints extends Table {
  TextColumn get id => text()();
  TextColumn get navigationId => text()();
  TextColumn get sourceId => text()();
  TextColumn get areaId => text()();
  TextColumn get name => text()();
  TextColumn get description => text()();
  TextColumn get type => text().withDefault(const Constant('point'))();
  RealColumn get lat => real().nullable()();
  RealColumn get lng => real().nullable()();
  TextColumn get utm => text().nullable()();
  TextColumn get coordinatesJson => text().nullable()(); // לפוליגון בלבד
  IntColumn get sequenceNumber => integer()();
  TextColumn get severity => text()();
  TextColumn get createdBy => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// טבלת גבולות גזרה לניווט ספציפי (GG per-navigation)
class NavBoundaries extends Table {
  TextColumn get id => text()();
  TextColumn get navigationId => text()();
  TextColumn get sourceId => text()();
  TextColumn get areaId => text()();
  TextColumn get name => text()();
  TextColumn get description => text()();
  TextColumn get coordinatesJson => text()();
  TextColumn get color => text()();
  RealColumn get strokeWidth => real()();
  TextColumn get createdBy => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// טבלת ביצי איזור לניווט ספציפי (BA per-navigation)
class NavClusters extends Table {
  TextColumn get id => text()();
  TextColumn get navigationId => text()();
  TextColumn get sourceId => text()();
  TextColumn get areaId => text()();
  TextColumn get name => text()();
  TextColumn get description => text()();
  TextColumn get coordinatesJson => text()();
  TextColumn get color => text()();
  RealColumn get strokeWidth => real()();
  RealColumn get fillOpacity => real()();
  TextColumn get createdBy => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// טבלת תור סנכרון
class SyncQueue extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get collectionName => text()();
  TextColumn get operation => text()(); // 'create', 'update', 'delete'
  TextColumn get recordId => text()();
  TextColumn get dataJson => text()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  IntColumn get priority => integer().withDefault(const Constant(0))(); // 0=normal, 1=high, 2=realtime
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  TextColumn get errorMessage => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  BoolColumn get synced => boolean().withDefault(const Constant(false))();
  DateTimeColumn get syncedAt => dateTime().nullable()();
}

/// טבלת קונפליקטים הממתינים לפתרון
class ConflictQueue extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get collectionName => text()();
  TextColumn get recordId => text()();
  TextColumn get localDataJson => text()(); // הגרסה המקומית
  TextColumn get serverDataJson => text()(); // הגרסה מהשרת
  IntColumn get localVersion => integer()();
  IntColumn get serverVersion => integer()();
  TextColumn get resolution => text().nullable()(); // null=pending, 'local', 'server', 'merged'
  TextColumn get resolvedDataJson => text().nullable()(); // הנתונים אחרי מיזוג ידני
  DateTimeColumn get detectedAt => dateTime()();
  DateTimeColumn get resolvedAt => dateTime().nullable()();
}

/// טבלת מטא-דאטה לסנכרון (מעקב אחרי lastPullAt לכל קולקשן)
class SyncMetadata extends Table {
  TextColumn get collectionName => text()();
  DateTimeColumn get lastPullAt => dateTime()();
  DateTimeColumn get lastPushAt => dateTime().nullable()();
  IntColumn get pullCount => integer().withDefault(const Constant(0))();
  IntColumn get pushCount => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {collectionName};
}

/// מסד נתונים מקומי
@DriftDatabase(tables: [
  Users,
  Units,
  Areas,
  Checkpoints,
  SafetyPoints,
  Boundaries,
  Clusters,
  NavigationTrees,
  Navigations,
  NavigationTracks,
  NavCheckpoints,
  NavSafetyPoints,
  NavBoundaries,
  NavClusters,
  SyncQueue,
  ConflictQueue,
  SyncMetadata,
])
class AppDatabase extends _$AppDatabase {
  // Singleton pattern
  static AppDatabase? _instance;

  AppDatabase._internal() : super(_openConnection());

  factory AppDatabase() {
    _instance ??= AppDatabase._internal();
    return _instance!;
  }

  @override
  int get schemaVersion => 42;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        if (from == 1 && to >= 2) {
          // הוספת טבלאות שכבות חדשות
          await m.createTable(safetyPoints);
          await m.createTable(boundaries);
          await m.createTable(clusters);
        }
        if (from <= 2 && to >= 3) {
          // עדכון מבנה טבלת עצי ניווט
          await m.deleteTable('navigator_trees');
          await m.createTable(navigationTrees);
        }
        if (from <= 3 && to >= 4) {
          // עדכון טבלת ניווטים - הוספת שדות חדשים
          await m.addColumn(navigations, navigations.boundaryLayerId);
          await m.addColumn(navigations, navigations.routeLengthJson);
          await m.addColumn(navigations, navigations.distributeNow);
          await m.addColumn(navigations, navigations.safetyTimeJson);
          await m.addColumn(navigations, navigations.learningSettingsJson);
          await m.addColumn(navigations, navigations.verificationSettingsJson);
          await m.addColumn(navigations, navigations.allowOpenMap);
          await m.addColumn(navigations, navigations.showSelfLocation);
          await m.addColumn(navigations, navigations.alertsJson);
          await m.addColumn(navigations, navigations.displaySettingsJson);
        }
        if (from <= 4 && to >= 5) {
          // עדכון טבלת נקודות תורפה בטיחותיות - תמיכה בפוליגון
          await m.addColumn(safetyPoints, safetyPoints.type);
          await m.addColumn(safetyPoints, safetyPoints.coordinatesJson);
          // הפיכת lat, lng, utm ל-nullable (לא ניתן לשנות קולונות קיימות ב-Drift)
          // רשומות קיימות יישארו עם ערכים
        }
        if (from <= 5 && to >= 6) {
          // הוספת שדות לניהול תהליך חלוקת צירים
          await m.addColumn(navigations, navigations.routesStage);
          await m.addColumn(navigations, navigations.routesDistributed);
        }
        if (from <= 6 && to >= 7) {
          // הוספת טבלת יחידות ושדות משתמש חדשים
          await m.createTable(units);
          await m.addColumn(users, users.frameworkId);
          await m.addColumn(users, users.unitId);
        }
        if (from <= 7 && to >= 8) {
          // הוספת טבלאות שכבות לניווט ספציפי (per-navigation layers)
          await m.createTable(navCheckpoints);
          await m.createTable(navSafetyPoints);
          await m.createTable(navBoundaries);
          await m.createTable(navClusters);
        }
        if (from <= 8 && to >= 9) {
          // שיפור תור סנכרון: הוספת שדות version, priority, retryCount, errorMessage
          await m.addColumn(syncQueue, syncQueue.version);
          await m.addColumn(syncQueue, syncQueue.priority);
          await m.addColumn(syncQueue, syncQueue.retryCount);
          await m.addColumn(syncQueue, syncQueue.errorMessage);
          // הוספת טבלת קונפליקטים
          await m.createTable(conflictQueue);
          // הוספת טבלת מטא-דאטה סנכרון
          await m.createTable(syncMetadata);
        }
        if (from <= 9 && to >= 10) {
          // הוספת שדות משתמש חדשים: שם פרטי, שם משפחה, מספר אישי
          await m.addColumn(users, users.firstName);
          await m.addColumn(users, users.lastName);
          await m.addColumn(users, users.personalNumber);
        }
        if (from <= 10 && to >= 11) {
          // התאמת עצי ניווט למערכת מסגרות + יחידה מסווגת
          await m.addColumn(navigationTrees, navigationTrees.frameworkId);
          await m.addColumn(navigationTrees, navigationTrees.treeType);
          await m.addColumn(navigationTrees, navigationTrees.sourceTreeId);
          await m.addColumn(navigationTrees, navigationTrees.unitId);
          await m.addColumn(units, units.isClassified);
        }
        if (from <= 11 && to >= 12) {
          // הוספת שדות מייל למשתמשים + מיגרציית משתמש מפתח
          await m.addColumn(users, users.email);
          await m.addColumn(users, users.emailVerified);
          // מיגרציית משתמש מפתח מ-uid ישן ל-personalNumber
          await customStatement(
            "UPDATE users SET uid = '6868383', first_name = 'משה', last_name = 'אליצור', "
            "personal_number = '6868383', phone_number = '0556625578', full_name = 'משה אליצור' "
            "WHERE uid = 'dev_moshe_elitzur'"
          );
        }
        if (from <= 12 && to >= 13) {
          // הוספת שדות בחירת מסגרת ומשתתפים לטבלת ניווטים
          await m.addColumn(navigations, navigations.frameworkId);
          await m.addColumn(navigations, navigations.selectedSubFrameworkIdsJson);
          await m.addColumn(navigations, navigations.selectedParticipantIdsJson);
        }
        if (from <= 13 && to >= 14) {
          // הוספת שדות זמני שלבים לניווט
          await m.addColumn(navigations, navigations.trainingStartTime);
          await m.addColumn(navigations, navigations.systemCheckStartTime);
          await m.addColumn(navigations, navigations.activeStartTime);
        }
        if (from <= 14 && to >= 15) {
          // הוספת הגדרות תחקיר
          await m.addColumn(navigations, navigations.reviewSettingsJson);
        }
        if (from <= 15 && to >= 16) {
          // הוספת הצגת ציר ניווט על המפה
          await m.addColumn(navigations, navigations.showRouteOnMap);
        }
        if (from <= 16 && to >= 17) {
          // מיזוג Framework לתוך Unit: הוספת שדות level, isNavigators, isGeneral
          await m.addColumn(units, units.level);
          await m.addColumn(units, units.isNavigators);
          await m.addColumn(units, units.isGeneral);
        }
        if (from <= 17 && to >= 18) {
          // תמיכה בפוליגון עבור נקודות ציון (NZ)
          await m.addColumn(checkpoints, checkpoints.geometryType);
          await m.addColumn(checkpoints, checkpoints.coordinatesJson);
          await m.addColumn(navCheckpoints, navCheckpoints.geometryType);
          await m.addColumn(navCheckpoints, navCheckpoints.coordinatesJson);
        }
        if (from <= 18 && to >= 19) {
          // תיקון: הפיכת lat, lng, utm ל-nullable בטבלת safety_points
          // SQLite לא תומך ב-ALTER COLUMN, לכן יוצרים מחדש את הטבלה
          await customStatement('DROP TABLE IF EXISTS safety_points_new');
          await customStatement('''
            CREATE TABLE safety_points_new (
              id TEXT NOT NULL,
              area_id TEXT NOT NULL,
              name TEXT NOT NULL,
              description TEXT NOT NULL,
              type TEXT NOT NULL DEFAULT 'point',
              lat REAL,
              lng REAL,
              utm TEXT,
              coordinates_json TEXT,
              sequence_number INTEGER NOT NULL,
              severity TEXT NOT NULL,
              created_by TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              PRIMARY KEY (id)
            )
          ''');
          await customStatement('''
            INSERT INTO safety_points_new (id, area_id, name, description, type, lat, lng, utm, coordinates_json, sequence_number, severity, created_by, created_at, updated_at)
            SELECT id, area_id, name, description, type, lat, lng, utm, coordinates_json, sequence_number, severity, created_by, created_at, updated_at FROM safety_points
          ''');
          await customStatement('DROP TABLE safety_points');
          await customStatement('ALTER TABLE safety_points_new RENAME TO safety_points');
        }
        // Helper: safe addColumn — ignores "duplicate column" errors
        Future<void> safeAddColumn(TableInfo table, GeneratedColumn column) async {
          try {
            await m.addColumn(table, column);
          } on SqliteException catch (e) {
            if (!e.toString().contains('duplicate column')) rethrow;
          }
        }

        if (from <= 19 && to >= 20) {
          await safeAddColumn(users, users.fcmToken);
        }
        if (from <= 20 && to >= 21) {
          await safeAddColumn(navigationTracks, navigationTracks.overrideAllowOpenMap);
          await safeAddColumn(navigationTracks, navigationTracks.overrideShowSelfLocation);
          await safeAddColumn(navigationTracks, navigationTracks.overrideShowRouteOnMap);
        }
        if (from <= 21 && to >= 22) {
          await safeAddColumn(navigations, navigations.enabledPositionSourcesJson);
        }
        if (from <= 22 && to >= 23) {
          await safeAddColumn(navigations, navigations.allowManualPosition);
          await safeAddColumn(navigationTracks, navigationTracks.overrideAllowManualPosition);
          await safeAddColumn(navigationTracks, navigationTracks.manualPositionUsed);
          await safeAddColumn(navigationTracks, navigationTracks.manualPositionUsedAt);
        }
        if (from <= 23 && to >= 24) {
          await safeAddColumn(navigations, navigations.timeCalculationSettingsJson);
        }
        if (from <= 24 && to >= 25) {
          await safeAddColumn(navigations, navigations.communicationSettingsJson);
          await safeAddColumn(navigationTracks, navigationTracks.overrideWalkieTalkieEnabled);
        }
        if (from <= 25 && to >= 26) {
          await safeAddColumn(users, users.isApproved);
          // תאימות לאחור: משתמשים קיימים עם unitId → מאושרים
          await customStatement(
            "UPDATE users SET is_approved = 1 WHERE unit_id IS NOT NULL AND unit_id != ''"
          );
        }
        if (from <= 26 && to >= 27) {
          await safeAddColumn(users, users.firebaseUid);
        }
        if (from <= 27 && to >= 28) {
          await safeAddColumn(users, users.soloQuizPassedAt);
          await safeAddColumn(users, users.soloQuizScore);
        }
        if (from <= 28 && to >= 29) {
          await safeAddColumn(navigations, navigations.startPoint);
          await safeAddColumn(navigations, navigations.endPoint);
          await safeAddColumn(navigations, navigations.checkpointsPerNavigator);
          await safeAddColumn(navigations, navigations.waypointSettingsJson);
          await safeAddColumn(navigations, navigations.scoringCriterion);
        }
        if (from <= 29 && to >= 30) {
          await safeAddColumn(navigations, navigations.variablesSheetJson);
        }
        if (from <= 30 && to >= 31) {
          await safeAddColumn(navigations, navigations.gpsSpoofingDetectionEnabled);
          await safeAddColumn(navigations, navigations.gpsSpoofingMaxDistanceKm);
        }
        if (from <= 31 && to >= 32) {
          await safeAddColumn(navigationTracks, navigationTracks.overrideEnabledPositionSourcesJson);
        }
        if (from <= 32 && to >= 33) {
          await safeAddColumn(navigations, navigations.forceCompositionJson);
        }
        if (from <= 33 && to >= 34) {
          await safeAddColumn(navigationTracks, navigationTracks.isGroupSecondary);
        }
        if (from <= 34 && to >= 35) {
          await safeAddColumn(users, users.approvalStatus);
          await customStatement("""
            UPDATE users SET approval_status =
              CASE
                WHEN is_approved = 1 THEN 'approved'
                WHEN is_approved = 0 AND unit_id IS NOT NULL AND unit_id != '' THEN 'pending'
                ELSE NULL
              END
          """);
        }
        if (from <= 35 && to >= 36) {
          await safeAddColumn(navigations, navigations.deletedAt);
        }
        if (from <= 36 && to >= 37) {
          await safeAddColumn(units, units.checklistsJson);
          await safeAddColumn(navigations, navigations.checklistCompletionJson);
        }
        if (from <= 37 && to >= 38) {
          await safeAddColumn(users, users.commanderQuizPassedAt);
          await safeAddColumn(users, users.commanderQuizScore);
        }
        if (from <= 38 && to >= 39) {
          // Star navigation fields
          await safeAddColumn(navigations, navigations.starLearningMinutes);
          await safeAddColumn(navigations, navigations.starNavigatingMinutes);
          await safeAddColumn(navigations, navigations.starAutoMode);
          await safeAddColumn(navigationTracks, navigationTracks.starCurrentPointIndex);
          await safeAddColumn(navigationTracks, navigationTracks.starLearningEndTime);
          await safeAddColumn(navigationTracks, navigationTracks.starNavigatingEndTime);
          await safeAddColumn(navigationTracks, navigationTracks.starReturnedToCenter);
        }
        if (from <= 39 && to >= 40) {
          // Cluster navigation fields
          await safeAddColumn(navigations, navigations.clusterSettingsJson);
          await safeAddColumn(navigationTracks, navigationTracks.overrideRevealEnabled);
        }
        if (from <= 40 && to >= 41) {
          // Parachute navigation settings
          await safeAddColumn(navigations, navigations.parachuteSettingsJson);
        }
        if (from <= 41 && to >= 42) {
          // Checkpoint boundaryId — ייחודיות מספר סידורי לפי גבול גזרה
          await safeAddColumn(checkpoints, checkpoints.boundaryId);
          // Partial unique index: נקודות עם boundary
          try {
            await customStatement('''
              CREATE UNIQUE INDEX IF NOT EXISTS idx_cp_boundary_seq
                ON checkpoints(area_id, boundary_id, sequence_number)
                WHERE boundary_id IS NOT NULL
            ''');
          } catch (e) {
            print('⚠️ idx_cp_boundary_seq index creation skipped: $e');
          }
          // Partial unique index: נקודות ללא boundary (null group)
          // — may fail if existing data has duplicate (area_id, sequence_number)
          try {
            await customStatement('''
              CREATE UNIQUE INDEX IF NOT EXISTS idx_cp_no_boundary_seq
                ON checkpoints(area_id, sequence_number)
                WHERE boundary_id IS NULL
            ''');
          } catch (e) {
            print('⚠️ idx_cp_no_boundary_seq index creation skipped (duplicate data): $e');
          }
        }
      },
    );
  }

  /// מחיקת כל הנתונים (לשימוש ב-logout)
  Future<void> clearAllData() async {
    await transaction(() async {
      for (final table in allTables) {
        await delete(table).go();
      }
    });
  }

  /// קבלת מספר רשומות ממתינות לסנכרון
  Future<int> getPendingSyncCount() async {
    return await (select(syncQueue)
      ..where((tbl) => tbl.synced.equals(false)))
        .get()
        .then((rows) => rows.length);
  }

  /// סימון רשומה כמסונכרנת
  Future<void> markAsSynced(int id) async {
    await (update(syncQueue)..where((tbl) => tbl.id.equals(id)))
        .write(SyncQueueCompanion(
      synced: const Value(true),
      syncedAt: Value(DateTime.now()),
    ));
  }

  /// סימון כל הרשומות הממתינות לסנכרון עבור רשומה מסוימת כמסונכרנות
  Future<int> markPendingSyncItemsForRecordAsSynced(String collection, String recordId) {
    return (update(syncQueue)
      ..where((tbl) => tbl.collectionName.equals(collection) & tbl.recordId.equals(recordId) & tbl.synced.equals(false))
    ).write(SyncQueueCompanion(
      synced: const Value(true),
      syncedAt: Value(DateTime.now()),
    ));
  }

  /// מחיקת כל הרשומות שלא סונכרנו (לניקוי תור סנכרון ישן בהחלפת משתמש)
  Future<int> purgeAllUnsynced() async {
    return await (delete(syncQueue)
      ..where((tbl) => tbl.synced.equals(false)))
        .go();
  }

  /// קבלת רשומות ממתינות לסנכרון (FIFO - לפי סדר יצירה)
  Future<List<SyncQueueData>> getPendingSyncItems({int? limit}) async {
    final query = select(syncQueue)
      ..where((tbl) => tbl.synced.equals(false))
      ..orderBy([
        (tbl) => OrderingTerm(expression: tbl.priority, mode: OrderingMode.desc),
        (tbl) => OrderingTerm(expression: tbl.createdAt, mode: OrderingMode.asc),
      ]);
    if (limit != null) {
      query.limit(limit);
    }
    return await query.get();
  }

  /// קבלת רשומות ממתינות לסנכרון לפי קולקשן
  Future<List<SyncQueueData>> getPendingSyncItemsByCollection(String collection) async {
    return await (select(syncQueue)
      ..where((tbl) => tbl.synced.equals(false) & tbl.collectionName.equals(collection))
      ..orderBy([
        (tbl) => OrderingTerm(expression: tbl.createdAt, mode: OrderingMode.asc),
      ]))
        .get();
  }

  /// עדכון מספר ניסיונות והודעת שגיאה
  Future<void> updateSyncRetry(int id, int retryCount, String? errorMessage) async {
    await (update(syncQueue)..where((tbl) => tbl.id.equals(id)))
        .write(SyncQueueCompanion(
      retryCount: Value(retryCount),
      errorMessage: Value(errorMessage),
    ));
  }

  /// איפוס ניסיונות חוזרים לפריטים שנתקעו (retryCount >= maxRetries)
  Future<int> resetStuckSyncItems() async {
    return await (update(syncQueue)
          ..where((tbl) => tbl.synced.equals(false) & tbl.retryCount.isBiggerOrEqualValue(10)))
        .write(const SyncQueueCompanion(
      retryCount: Value(0),
      errorMessage: Value(null),
    ));
  }

  /// הוספת רשומה לתור קונפליקטים
  Future<int> insertConflict(ConflictQueueCompanion conflict) async {
    return await into(conflictQueue).insert(conflict);
  }

  /// קבלת קונפליקטים ממתינים
  Future<List<ConflictQueueData>> getPendingConflicts() async {
    return await (select(conflictQueue)
      ..where((tbl) => tbl.resolution.isNull())
      ..orderBy([
        (tbl) => OrderingTerm(expression: tbl.detectedAt, mode: OrderingMode.asc),
      ]))
        .get();
  }

  /// פתרון קונפליקט
  Future<void> resolveConflict(int id, String resolution, String? resolvedDataJson) async {
    await (update(conflictQueue)..where((tbl) => tbl.id.equals(id)))
        .write(ConflictQueueCompanion(
      resolution: Value(resolution),
      resolvedDataJson: Value(resolvedDataJson),
      resolvedAt: Value(DateTime.now()),
    ));
  }

  /// קבלת/עדכון מטא-דאטה סנכרון לקולקשן
  Future<SyncMetadataData?> getSyncMetadata(String collection) async {
    return await (select(syncMetadata)
      ..where((tbl) => tbl.collectionName.equals(collection)))
        .getSingleOrNull();
  }

  /// עדכון lastPullAt לקולקשן
  Future<void> updateLastPullAt(String collection, DateTime timestamp) async {
    await into(syncMetadata).insertOnConflictUpdate(
      SyncMetadataCompanion.insert(
        collectionName: collection,
        lastPullAt: timestamp,
        lastPushAt: Value(null),
        pullCount: const Value(1),
      ),
    );
  }

  /// עדכון lastPushAt לקולקשן
  Future<void> updateLastPushAt(String collection, DateTime timestamp) async {
    final existing = await getSyncMetadata(collection);
    if (existing != null) {
      await (update(syncMetadata)..where((tbl) => tbl.collectionName.equals(collection)))
          .write(SyncMetadataCompanion(
        lastPushAt: Value(timestamp),
        pushCount: Value(existing.pushCount + 1),
      ));
    }
  }

  /// מחיקת רשומות סנכרון שכבר סונכרנו (ניקוי)
  Future<int> cleanSyncedItems({Duration olderThan = const Duration(days: 7)}) async {
    final cutoff = DateTime.now().subtract(olderThan);
    return await (delete(syncQueue)
      ..where((tbl) => tbl.synced.equals(true) & tbl.syncedAt.isSmallerOrEqualValue(cutoff)))
        .go();
  }
}

/// פתיחת חיבור למסד הנתונים
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'navigate_app.sqlite'));
    return NativeDatabase(file);
  });
}
