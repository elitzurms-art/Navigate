# Navigate App - CLAUDE.md

אפליקציית Flutter לניהול וביצוע ניווטים צבאיים. כוללת מפות, GPS, ניהול משתתפים, מסלולים, תחקור וציונים.

---

## טכנולוגיות

| טכנולוגיה | גרסה | תפקיד |
|---|---|---|
| Flutter | SDK >=3.0.0 | UI Framework |
| Dart | >=3.0.0 <4.0.0 | שפת תכנות |
| Firebase Auth | ^6.1.4 | אימות (טלפון + אנונימי) |
| Cloud Firestore | ^6.1.2 | מסד נתונים מרוחק |
| Firebase Storage | ^13.0.6 | אחסון קבצים |
| Drift | ^2.14.1 | SQLite ORM (מקומי) |
| flutter_map | ^6.1.0 | מפות (OpenStreetMap) |
| provider | ^6.1.1 | State Management |
| connectivity_plus | ^5.0.2 | מעקב רשת |
| geolocator | ^11.0.0 | GPS |
| gps_plus | local (../gps_plus) | חבילת GPS מקומית |

---

## ארכיטקטורה - Clean Architecture

```
lib/
├── core/                  # קבועים, theme, utils
│   ├── constants/app_constants.dart    # קבועים גלובליים (roles, statuses, types)
│   ├── theme/app_theme.dart            # Material 3 + Rubik font
│   ├── utils/geometry_utils.dart       # חישובי גאומטריה
│   ├── utils/utm_converter.dart        # המרת UTM↔LatLng
│   └── map_config.dart                 # הגדרת שרתי מפות
│
├── domain/entities/       # ישויות עסקיות (18 קבצים)
│   ├── user.dart                  # משתמש
│   ├── unit.dart                  # יחידה (כולל שדות Framework לשעבר)
│   ├── navigation.dart            # ניווט (~400 שורות)
│   ├── navigation_tree.dart       # עץ ניווט + SubFramework
│   ├── navigation_settings.dart   # הגדרות ניווט (~600 שורות)
│   ├── hat_type.dart              # כובעים/תפקידים (HatType, HatInfo, UnitHats)
│   ├── area.dart                  # שטח
│   ├── checkpoint.dart            # נ"צ
│   ├── boundary.dart              # ג"ג (גבול גזרה)
│   ├── cluster.dart               # ב"א (באזור)
│   ├── safety_point.dart          # נ"ב (נקודת בטיחות)
│   ├── nav_layer.dart             # שכבת ניווט
│   ├── coordinate.dart            # קואורדינטה
│   ├── checkpoint_punch.dart      # הגעה לנ"צ
│   ├── navigation_score.dart      # ציון ניווט
│   ├── security_violation.dart    # הפרת אבטחה
│   ├── navigator_tree.dart        # עץ מנווטים (legacy)
│   └── user_role.dart             # תפקיד משתמש
│
├── data/                  # שכבת נתונים
│   ├── datasources/
│   │   ├── local/app_database.dart     # Drift schema (17 טבלאות, גרסה 17)
│   │   └── remote/firebase_service.dart # Firebase data source
│   ├── repositories/              # 14 repositories
│   │   ├── user_repository.dart
│   │   ├── unit_repository.dart          # cascade delete ליחידות ילדים
│   │   ├── navigation_repository.dart
│   │   ├── navigation_tree_repository.dart  # ← הפעיל
│   │   ├── navigator_tree_repository.dart   # ← legacy, stubbed
│   │   ├── area_repository.dart
│   │   ├── checkpoint_repository.dart
│   │   ├── boundary_repository.dart
│   │   ├── cluster_repository.dart
│   │   ├── safety_point_repository.dart
│   │   ├── nav_layer_repository.dart
│   │   ├── checkpoint_punch_repository.dart
│   │   ├── navigator_alert_repository.dart
│   │   └── security_violation_repository.dart
│   └── sync/sync_manager.dart     # סנכרון דו-כיווני Drift↔Firestore
│
├── services/              # שירותים (12 קבצים)
│   ├── auth_service.dart              # התחברות, הרשמה, SMS, Anonymous Auth
│   ├── session_service.dart           # ניהול session + סריקת כובעים
│   ├── navigation_data_loader.dart    # טעינת נתוני ניווט (גדול!)
│   ├── routes_distribution_service.dart # חלוקת מסלולים
│   ├── navigation_layer_copy_service.dart # העתקת שכבות
│   ├── scoring_service.dart           # חישוב ציונים
│   ├── gps_service.dart               # הרשאות GPS
│   ├── gps_tracking_service.dart      # מעקב GPS רקע
│   ├── device_security_service.dart   # אבטחת מכשיר
│   ├── framework_excel_service.dart   # ייצוא Excel
│   ├── security_manager.dart          # ניהול אבטחה
│   └── sms_service.dart               # שליחת SMS
│
├── presentation/          # שכבת UI
│   ├── screens/
│   │   ├── auth/           # 6 מסכי אימות
│   │   ├── home/           # מסך בית + navigator views (6)
│   │   ├── navigations/    # 19 מסכי ניווט (הזרם הראשי!)
│   │   ├── navigation_trees/  # 4 מסכי עצים (פעילים)
│   │   ├── layers/         # 15 מסכי שכבות (נ"צ, ג"ג, נ"ב, ב"א)
│   │   ├── areas/          # 3 מסכי שטחות
│   │   ├── units/          # 2 מסכי יחידות
│   │   ├── trees/          # 3 מסכי עצים (legacy - לא בזרם!)
│   │   ├── navigation/     # legacy subdirs (לא בזרם!)
│   │   ├── settings/       # הגדרות
│   │   ├── dashboard/      # דשבורד
│   │   ├── training/       # למידה + אימון
│   │   └── security/       # הוראות Guided Access
│   └── widgets/            # 4 widgets משותפים
│
├── main.dart              # נקודת כניסה (279 שורות)
├── main_simple.dart       # כניסה מופשטת (חלופית)
└── firebase_options.dart  # Firebase config לכל הפלטפורמות
```

---

## מסד נתונים (Drift)

- **סכמה**: גרסה 17
- **17 טבלאות**: Users, Units, Areas, Checkpoints, SafetyPoints, Boundaries, Clusters, NavigationTrees, Navigations, NavigationTracks, NavCheckpoints, NavSafetyPoints, NavBoundaries, NavClusters, NavProfiles, ועוד
- **שם הטבלה**: `NavigationTrees` (לא `NavigatorTrees`!) — accessor: `navigationTrees`
- **Generated class**: `NavigationTree` (יחיד) מטבלה `NavigationTrees`
- **הגדרות כ-JSON**: learningSettingsJson, verificationSettingsJson, alertsJson, displaySettingsJson, reviewSettingsJson

### מיגרציות אחרונות
| גרסה | שינוי |
|---|---|
| 13 | securitySettingsJson |
| 14 | training/systemCheck/activeStartTime |
| 15 | reviewSettingsJson |
| 16 | showRouteOnMap |
| 17 | Unit: level, isNavigators, isGeneral (מיזוג Framework→Unit) |

### אחרי שינוי סכמה
```bash
dart run build_runner build --delete-conflicting-outputs
```

---

## Firebase

- **פרויקט**: `navigate-native` (319417384412)
- **אימות**: Phone Auth + Anonymous Auth (לגישת Firestore)
- **Collections**: users, units, areas, navigator_trees, navigations, navigation_tracks, navigation_approval, sync_metadata
- **Subcollections תחת areas**: layers_nz (נ"צ), layers_nb (נ"ב), layers_gg (ג"ג), layers_ba (ב"א)
- **קבצי הגדרות**: `firebase.json`, `firestore.rules`, `firestore.indexes.json`

---

## ישויות - כללי הקוד

כל הישויות מממשות `Equatable` וכוללות:
- `toMap()` — סריאליזציה ל-Map
- `fromMap()` — דה-סריאליזציה מ-Map
- `copyWith()` — עדכון immutable

### User
- `uid` = מספר אישי (7 ספרות) — **זה ה-ID**
- `personalNumber` הוא getter שמחזיר `uid`
- `fullName` — computed getter מ-firstName + lastName
- **אין** `username` או `frameworkId` (הוסרו בגרסה 12)
- **יש** `email` + `emailVerified` (נוספו בגרסה 12)

### Unit (כולל Framework לשעבר)
- Framework **הוסר לחלוטין** ונבלע ב-Unit
- שדות חדשים: `level` (int?), `isNavigators` (bool), `isGeneral` (bool)
- `UnitRepository.delete()` מבצע cascade: מחיקת יחידות ילדים + עצים + ניווטים

### NavigationTree
- מאחסן `subFrameworks` (List\<SubFramework\>) ישירות — **אין** רשימת frameworks
- `SubFramework` כולל `unitId` לקישור ליחידה
- `fromMap()` כולל backward compat: קורא key `frameworks` ישן ומשטח
- **Firestore**: תתי-מסגרות נשמרות כ-array בשדה `subFrameworks` בתוך מסמך עץ ב-collection `navigator_trees`
- **Drift**: תתי-מסגרות נשמרות כ-JSON string בעמודה `frameworksJson` בטבלת `NavigationTrees`

### תתי-מסגרות קבועות (isFixed)
- כל יחידה ברמת פלוגה (4) ומעלה מקבלת תת-מסגרת קבועה: **"מפקדים ומנהלת"**
- יחידה ברמת מחלקה (5) מקבלת גם: **"חיילים"**
- תתי-מסגרות קבועות (`isFixed: true`) **לא ניתנות למחיקה** — כפתור מחיקה מוסתר + בדיקה בקוד
- כל יצירת יחידה/עץ חייבת לכלול תתי-מסגרות קבועות — גם `_addChildFramework()` וגם `_createFirstFramework()`

### כלל הרשאות תתי-מסגרות
- **"אם אתה רואה — אתה יכול לערוך"**: מנהל יחידת-על רואה ויכול לערוך תתי-מסגרות של יחידות משנה
- פונקציות עריכה (`_deleteSubFramework`, `_manageSubFrameworkUsers`, `_importFromExcel`) מקבלות את העץ הרלוונטי כפרמטר — לא תלויות ב-`_adminTree` בלבד

### Navigation
- `selectedUnitId` (שם ישן: `frameworkId`, עמודת DB נשארת `frameworkId` לתאימות)
- סטטוסים: `preparation` → `ready` → `learning` → `system_check` → `waiting` → `active` → `approval` → `review`

---

## תפקידי משתמש (Roles)

| תפקיד | תיאור |
|---|---|
| `navigator` | מנווט (ברירת מחדל) |
| `commander` | מפקד |
| `unit_admin` | מנהל יחידה |
| `developer` | מפתח |
| `admin` | מנהל מערכת |

### כובעים (Hats)
- `HatType`: admin, commander, navigator, management, observer
- `HatInfo`: type + subFrameworkId + treeId + unitId + שמות
- משתמש יכול להחזיק כובעים מרובים → hat_selection_screen

---

## זרימת הניווט

### קבוצות סטטוס ברשימת ניווטים
| קבוצה | סטטוסים |
|---|---|
| הכנות ולמידה | preparation, ready, learning, system_check |
| אימון | waiting, active |
| תחקור | approval, review |

### סדר חלקים במסך יצירה/עריכה
שטח ומשתתפים → נקודות → למידה → ניווט → תחקיר → תצוגה

### הגדרות GPS
- מוגדר **per-navigation** (לא גלובלי) במסך יצירה/עריכה
- slider: 5-120 שניות, ברירת מחדל 30

### גבול גזרה (Boundary)
- שדה חובה — **אין** אפשרות "ללא גבול"

### כניסה ל-system_check
- פתיחת ניווט בסטטוס system_check מדלגת על DataLoadingScreen → ישר ל-SystemCheckScreen

### פעולות מפקד
- מסך Approval/Investigation: bottomNavigationBar עם "חזרה להכנה" + "מחיקת ניווט"
- מסך Training: אייקון מחיקה ב-AppBar
- תוצאת pop `'deleted'` מטופלת ב-navigations_list + navigation_preparation

---

## מסך System Check
- 5 טאבים: מנווטים, אנרגיה, קליטה, מערכת, נתונים
- טאב נתונים משלב NavigationDataLoader (היה בעבר מסך נפרד)
- דורש פרמטר `currentUser`

---

## מסך הגדרות
- כללי: שפה, theme
- מפה: שירות מפות, מפות אופליין
- אודות: גרסה, תנאי שימוש
- **אין** הגדרות GPS (עבר למסך ניווט)
- **אין** יצירת משתמשי בדיקה

---

## סנכרון (SyncManager)

- **אסטרטגיה**: Offline-first — פעולות מקומיות תמיד, סנכרון כשיש רשת
- **כיוונים**: pullOnly, pushOnly, bidirectional, realtime
- Pull: Firestore → Drift (שטחות, יחידות, עצים, ניווטים)
- Push: Drift → Firestore (מעקבים, הגעות, הפרות)
- **סנכרון GPS**: batch כל 2 דקות
- **סנכרון תקופתי**: כל 5 דקות
- **Realtime listeners**: להתראות
- **Retry**: exponential backoff, מקסימום 10 ניסיונות
- **Auth**: בודק `_isAuthenticated` לפני כל סנכרון
- `_didInitialSync` מונע סנכרון ראשוני כפול

### מלכודות סנכרון (upsert)
- **`_upsertNavigationTree`**: Firestore שולח `subFrameworks` כ-array, Drift מאחסן כ-`frameworksJson` (string). חובה לעשות `jsonEncode` בזמן pull. גם לתמוך ב-`frameworks` (פורמט ישן) ו-`frameworksJson` (string ישיר)
- **`_upsertNavigation`**: חובה לכלול **את כל** שדות הניווט — כולל `frameworkId`, `selectedSubFrameworkIdsJson`, `selectedParticipantIdsJson`, שדות bool (allowOpenMap, showSelfLocation, showRouteOnMap, routesDistributed, distributeNow), `reviewSettingsJson`, שדות זמן (trainingStartTime, systemCheckStartTime, activeStartTime). שדה שלא נכתב מקבל null/default ומוחק נתונים!
- **Firestore Lists → Drift JSON**: שדות כמו `selectedSubFrameworkIds` מגיעים מ-Firestore כ-List אבל Drift מצפה ל-JSON string — צריך fallback עם `jsonEncode`

---

## אימות (Auth Flow)

1. משתמש מזין מספר אישי (7 ספרות) → `LoginScreen`
2. אימות SMS (או email לדסקטופ) → `SmsVerificationScreen`
3. Anonymous Firebase Auth ברקע (לגישת Firestore) → `_ensureFirebaseAuth()` ב-main.dart
4. סריקת כובעים → כובע אחד ישר לניווט, מרובים → `HatSelectionScreen`
5. `HomeRouter` → `NavigatorHomeScreen` (מנווט) או `HomeScreen` (מפקד/מנהל)

---

## Routing (main.dart)

| Route | מסך |
|---|---|
| `/` | LoginScreen |
| `/register` | RegisterScreen |
| `/mode-selection` | MainModeSelectionScreen |
| `/home` | HomeRouter (dynamic) |
| `/unit-admin-frameworks` | UnitAdminFrameworksScreen |

---

## מלכודות ידועות (Gotchas)

### Drift + Firestore Query conflict
```dart
import 'package:drift/drift.dart' hide Query;
```

### firebase_auth + app entities User conflict
```dart
import 'package:firebase_auth/firebase_auth.dart' hide User;
```

### connectivity_plus v5
מחזיר `ConnectivityResult` **יחיד** — לא `List`!

### flutter_map v6.1.0
**אין** `isDotted` על Polyline

### Firestore Timestamps
לא ניתן לעשות `jsonEncode` — להשתמש ב-`_sanitizeForJson()` להמרה ל-ISO strings

### Icons
`Icons.signal_cellular_1_bar` **לא קיים** — להשתמש ב-`Icons.signal_cellular_alt_1_bar`

### _currentNavigation pattern
במסכים שמשנים ניווט (training_mode_screen וכו'): להשתמש ב-`_currentNavigation` (mutable) ולא ב-`widget.navigation` (immutable). לעדכן אחרי כל שמירה.

---

## עצי ניווט — שני repos

| Repo | סטטוס | שימוש |
|---|---|---|
| `NavigationTreeRepository` | **פעיל** | מסכי navigation_trees/ |
| `NavigatorTreeRepository` | legacy, stubbed | אל תשתמש |

### מסכי עצים
- **פעילים**: `lib/presentation/screens/navigation_trees/` — בזרם הראשי
- **legacy**: `lib/presentation/screens/trees/` — **לא** בזרם הראשי

---

## משתמשי פיתוח (main.dart)

- Developer: uid `6868383`
- Test users: `1111111`, `2222222`, `3333333`, `4444444`

---

## פקודות בנייה

```bash
# בניית קבצי Drift מחוללים
dart run build_runner build --delete-conflicting-outputs

# בדיקת שגיאות
flutter analyze

# הרצה
flutter run
```

---

## הגדרות ברירת מחדל

### LearningSettings
- enabledWithPhones: true
- showNavigationDetails: true
- showRoutes: true
- allowRouteEditing: true
- allowRouteNarration: true

### ReviewSettings
- showScoresAfterApproval: true

---

## סינון תת-מסגרות
כל מנהל/מפקד רואה רק ניווטים של תת-המסגרת שלו ברשימת הניווטים.

---

## עבודה עם agents מקבילים
- agents מרובים **יכולים** לערוך את אותו קובץ (כמו app_database.dart) אם העריכות בחלקים שונים
- תמיד לוודא קבצים משותפים אחרי עבודת agents מקבילית
- להריץ build_runner **אחרי** שכל ה-agents סיימו
- להריץ `flutter analyze` לתפיסת בעיות אינטגרציה

---

## באגים שתוקנו (פברואר 2026)

### 1. סנכרון — מחיקת רשומות מקומיות בטעות (`sync_manager.dart`)
- **בעיה**: `_reconcileDeletedRecords` מחקה יחידות/עצים שנוצרו מקומית אבל עדיין לא הועלו ל-Firestore
- **תיקון**: בדיקת תור הסנכרון לפני מחיקה — דילוג על רשומות עם create/update ממתין

### 2. סנכרון — השחתת קואורדינטות בזמן pull (`sync_manager.dart`)
- **בעיה**: `_upsertCheckpoint` קרא `data['lat']` במקום `data['coordinates']['lat']`
  - `Checkpoint.toMap()` שולח `{coordinates: {lat, lng, utm}}` (מקונן)
  - ה-upsert ציפה לשדות שטוחים → קיבל NULL → ברירת מחדל 0.0
  - **נקודות "נעלמו" מהפוליגון ועברו לקואורדינטה (0,0) — חוף אפריקה**
- **תיקון**: כל 4 פונקציות upsert תוקנו:
  - `_upsertCheckpoint`: חילוץ lat/lng מ-`data['coordinates']` (fallback לשטוח)
  - `_upsertSafetyPoint`: חילוץ מ-`data['coordinates']` + תמיכה ב-`polygonCoordinates` כ-List → JSON
  - `_upsertBoundary`: המרת `data['coordinates']` (List) ל-JSON string
  - `_upsertCluster`: אותו דבר כמו boundary

### 3. חלוקת נקודות — "לא נמצאו נקודות ציון" (`routes_automatic_setup_screen.dart`)
- **בעיה**: המסך טען navCheckpoints מה-DB המקומי, אבל אלה נוצרים רק ב-`copyLayersForNavigation` שרץ **פעם אחת** ביצירת ניווט. אם ההעתקה נכשלה/לא הייתה — הרשימה ריקה
- **תיקון**: fallback — אם navCheckpoints ריק, מנסה להעתיק שכבות מחדש. אם עדיין ריק, טוען ישירות מנקודות השטח

### 4. חלוקת נקודות — validation לא מחשיב נקודות התחלה/סיום (`routes_distribution_service.dart`)
- **בעיה**: הבדיקה `availableCheckpoints.length >= navigators * checkpointsPerNavigator` כללה נקודות התחלה/סיום, אבל בחלוקה בפועל הן מוחרגות
- **תיקון**: חיסור נקודות התחלה/סיום מספירת הנקודות הזמינות

### 5. חלוקת נקודות — דילוג שקט על מנווטים (`routes_distribution_service.dart`)
- **בעיה**: כשאין מספיק נקודות למנווט, `continue` דילג בשקט — המנווט לא קיבל ציר בלי שגיאה
- **תיקון**: זריקת Exception במקום דילוג שקט

### 6. חלוקת נקודות — רצף לא אופטימלי (`routes_distribution_service.dart`)
- **בעיה**: `_calculateOptimalSequence` קיבלה `startPointId` אבל לא השתמשה בו — התחילה מנקודה שרירותית
- **תיקון**: אם יש נקודת התחלה, מוצא את הנקודה הקרובה אליה ומתחיל ממנה

### 7. ניווט — חזרה למסך שגוי אחרי אישור צירים (`routes_setup_screen.dart`)
- **בעיה**: אחרי "אישור וסיום" ב-`RoutesVerificationScreen`, המשתמש חזר ל-`RoutesSetupScreen` (בחירת שיטה) במקום ל-`NavigationPreparationScreen` (צ'קליסט)
- **סיבה**: `RoutesSetupScreen` לא טיפל בתוצאת ה-pop מהמסכים הבנים
- **תיקון**: `RoutesSetupScreen` עושה `await` ל-push ומעביר `true` הלאה ל-preparation

---

## כללים חשובים לסנכרון שכבות

### מבנה נתונים: Entity.toMap() מול Drift
| Entity | toMap() שולח | Drift מצפה |
|---|---|---|
| Checkpoint | `{coordinates: {lat, lng, utm}}` | שדות שטוחים: `lat`, `lng`, `utm` |
| SafetyPoint (point) | `{coordinates: {lat, lng, utm}}` | `lat`, `lng`, `utm` |
| SafetyPoint (polygon) | `{polygonCoordinates: [{...}]}` | `coordinatesJson` (string) |
| Boundary | `{coordinates: [{lat,lng,utm},...]}` | `coordinatesJson` (string) |
| Cluster | `{coordinates: [{lat,lng,utm},...]}` | `coordinatesJson` (string) |

**חוק**: בכל upsert חדש — תמיד לבדוק את ה-toMap() של הישות ולחלץ נתונים מהמבנה המקונן. לעולם לא להניח שהשדות שטוחים.
