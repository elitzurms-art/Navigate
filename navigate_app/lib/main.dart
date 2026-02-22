import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'services/session_service.dart';
import 'services/elevation_service.dart';
import 'services/tile_cache_service.dart';
import 'core/map_config.dart';
import 'data/repositories/navigation_tree_repository.dart';
import 'data/repositories/user_repository.dart';
import 'data/sync/sync_manager.dart';
import 'services/notification_service.dart';
import 'services/background_location_service.dart';
import 'domain/entities/hat_type.dart';
import 'presentation/screens/auth/login_screen.dart';
import 'presentation/screens/auth/register_screen.dart';
import 'presentation/screens/main_mode_selection_screen.dart';
import 'presentation/screens/home/home_screen.dart';
import 'presentation/screens/home/navigator_home_screen.dart';
import 'presentation/screens/onboarding/choose_unit_screen.dart';
import 'presentation/screens/onboarding/waiting_for_approval_screen.dart';
import 'data/repositories/unit_repository.dart';
import 'services/auth_mapping_service.dart';
import 'data/repositories/solo_quiz_repository.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    // Firebase already initialized (happens during hot reload)
    if (!e.toString().contains('duplicate-app')) {
      rethrow;
    }
  }

  // כיבוי persistence של Firestore — אין צורך (Drift משמש כ-offline DB)
  // persistence יכול לגרום ל-cache מיושן שמפריע ל-reconciliation בסנכרון
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: false,
  );

  // אתחול cache אריחי מפה (חייב לפני MapConfig)
  await TileCacheService().initialize();

  // אתחול שירות גובה אופליין
  await ElevationService().initialize();

  // אתחול קונפיגורציית מפה
  await MapConfig().init();

  // יצירת משתמש מפתח
  final authService = AuthService();
  await authService.ensureDeveloperUser();

  // ניקוי חד-פעמי: מחיקת עצי ניווט ישנים ללא unitId על מסגרות
  await _migrateDeleteOldTrees();

  // מחיקת משתמשים ללא שם
  await _deleteNamelessUsers();

  // אם יש משתמש מחובר מקומית אבל אין אימות Firebase — כניסה אנונימית
  // כדי לאפשר גישה ל-Firestore (הכללים דורשים isAuthenticated)
  await _ensureFirebaseAuth();

  // זריעת שאלות מבחן בדד (אם חסרות) — רק עבור developer/admin
  await _seedSoloQuizIfNeeded();

  // התחלת סנכרון עם Firebase
  final syncManager = SyncManager();
  await syncManager.start();

  // אתחול foreground service למעקב GPS ברקע
  BackgroundLocationService().init();

  // אתחול שירות התראות push
  final notificationService = NotificationService();
  await notificationService.initialize(
    userId: (await SharedPreferences.getInstance()).getString('logged_in_uid'),
  );

  // בקשת הרשאות חסרות בהפעלה
  await _requestMissingPermissions();

  runApp(const NavigateApp());
}

/// אם יש משתמש שמור מקומית אבל אין Firebase Auth — כניסה אנונימית
/// מאפשר ל-SyncManager לגשת ל-Firestore (הכללים דורשים request.auth != null)
Future<void> _ensureFirebaseAuth() async {
  if (FirebaseAuth.instance.currentUser != null) return;

  final prefs = await SharedPreferences.getInstance();
  final loggedInUid = prefs.getString('logged_in_uid');
  if (loggedInUid == null || loggedInUid.isEmpty) return;

  try {
    final credential = await FirebaseAuth.instance.signInAnonymously();
    final firebaseUid = credential.user?.uid;
    print('DEBUG: Signed in anonymously for Firestore access (user=$loggedInUid, firebaseUid=$firebaseUid)');

    // עדכון auth_mapping כדי ש-Firestore Security Rules יוכלו לזהות את המשתמש
    if (firebaseUid != null) {
      final userRepo = UserRepository();
      final user = await userRepo.getUser(loggedInUid);
      if (user != null) {
        await AuthMappingService().updateAuthMapping(firebaseUid, user);
        // עדכון firebaseUid על המשתמש המקומי
        if (user.firebaseUid != firebaseUid) {
          await userRepo.saveUserLocally(user.copyWith(firebaseUid: firebaseUid), queueSync: false);
        }
      }
    }
  } catch (e) {
    print('DEBUG: Anonymous sign-in failed: $e');
  }
}

/// בקשת כל ההרשאות הנדרשות שעדיין לא אושרו
Future<void> _requestMissingPermissions() async {
  final permissions = [
    Permission.notification,
    Permission.location,
    Permission.locationAlways,
    Permission.microphone,
    Permission.phone,
    Permission.sms,
  ];

  for (final permission in permissions) {
    final status = await permission.status;
    if (!status.isGranted && !status.isPermanentlyDenied) {
      final result = await permission.request();
      print('DEBUG: Permission ${permission.toString()} → ${result.name}');
    }
  }
}

/// ניקוי חד-פעמי — מחיקת עצי ניווט שהמסגרות שלהם חסרות unitId
Future<void> _migrateDeleteOldTrees() async {
  const migrationKey = 'migration_unitId_on_frameworks_done';
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(migrationKey) == true) return;

  try {
    final treeRepo = NavigationTreeRepository();
    final trees = await treeRepo.getAll();
    int deleted = 0;
    for (final tree in trees) {
      // אם לעץ אין unitId — עץ ישן, למחוק
      final hasUnitId = tree.unitId != null && tree.unitId!.isNotEmpty;
      if (!hasUnitId) {
        await treeRepo.delete(tree.id);
        deleted++;
      }
    }
    // ניקוי session שמור
    await SessionService().clearSession();
    await prefs.setBool(migrationKey, true);
    print('DEBUG migration: deleted $deleted old trees without unitId');
  } catch (e) {
    print('DEBUG migration error: $e');
  }
}

/// מחיקת משתמשים ללא שם מה-DB המקומי
Future<void> _deleteNamelessUsers() async {
  try {
    final userRepo = UserRepository();
    final users = await userRepo.getAll();
    int deleted = 0;
    for (final user in users) {
      if (user.firstName.trim().isEmpty && user.lastName.trim().isEmpty) {
        await userRepo.deleteUser(user.uid);
        deleted++;
        print('DEBUG: Deleted nameless user ${user.uid}');
      }
    }
    if (deleted > 0) {
      print('DEBUG: _deleteNamelessUsers removed $deleted users');
    }
  } catch (e) {
    print('DEBUG: _deleteNamelessUsers error: $e');
  }
}

/// זריעת שאלות מבחן בדד ל-Firestore — פעם אחת, רק כש-developer/admin מחובר
Future<void> _seedSoloQuizIfNeeded() async {
  try {
    if (FirebaseAuth.instance.currentUser == null) return;

    final prefs = await SharedPreferences.getInstance();
    final loggedInUid = prefs.getString('logged_in_uid');
    if (loggedInUid == null) return;

    final user = await UserRepository().getUser(loggedInUid);
    if (user == null) return;
    if (user.role != 'developer') return;

    final quizRepo = SoloQuizRepository();
    final questions = await quizRepo.getQuestions();
    if (questions.isNotEmpty) return;

    await quizRepo.seedDefaultQuestions();
    print('DEBUG: Seeded solo quiz questions (${user.role})');
  } catch (e) {
    print('DEBUG: _seedSoloQuizIfNeeded error: $e');
  }
}

class NavigateApp extends StatelessWidget {
  const NavigateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Navigate',
      debugShowCheckedModeBanner: false,

      // RTL Support for Hebrew
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('he', ''), // Hebrew
        Locale('en', ''), // English
      ],
      locale: const Locale('he', ''), // Default to Hebrew

      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,

        // Hebrew font support
        fontFamily: 'Rubik',
      ),

      // Routes
      routes: {
        '/': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
        '/mode-selection': (context) => const MainModeSelectionScreen(),
        '/home': (context) => const HomeRouter(),
      },
      initialRoute: '/',
    );
  }
}

/// מסך ניתוב - בוחר בין מסך בית רגיל למנווט לפי תפקיד המשתמש
class HomeRouter extends StatefulWidget {
  const HomeRouter({super.key});

  @override
  State<HomeRouter> createState() => _HomeRouterState();
}

class _HomeRouterState extends State<HomeRouter> {
  final AuthService _authService = AuthService();
  final SessionService _sessionService = SessionService();

  @override
  void initState() {
    super.initState();
    _checkUserRole();
  }

  void _navigateTo(Widget screen) {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  Future<void> _checkUserRole() async {
    try {
      print('DEBUG HomeRouter: starting _checkUserRole');

      // 1. בדיקת session שמור
      final savedSession = await _sessionService.getSavedSession();
      print('DEBUG HomeRouter: savedSession=${savedSession?.type}');
      if (savedSession != null) {
        _navigateTo(savedSession.type == HatType.navigator
            ? const NavigatorHomeScreen()
            : const HomeScreen());
        return;
      }

      // 2. המתנה לסנכרון ראשוני — הנתונים (עצים, יחידות) חייבים להיות ב-DB המקומי
      print('DEBUG HomeRouter: waiting for initial sync...');
      await SyncManager().waitForInitialSync();
      print('DEBUG HomeRouter: initial sync done');

      // 3. קבלת משתמש נוכחי
      final user = await _authService.getCurrentUser();
      print('DEBUG HomeRouter: user=${user?.uid}, role=${user?.role}');
      if (user == null) {
        _navigateTo(const HomeScreen());
        return;
      }

      // 3.5. בדיקת onboarding — מנווטים חדשים חייבים לבחור יחידה ולהמתין לאישור
      if (!user.bypassesOnboarding) {
        if (user.needsUnitSelection) {
          print('DEBUG HomeRouter: user needs unit selection → ChooseUnitScreen');
          _navigateTo(const ChooseUnitScreen());
          return;
        }
        if (user.isAwaitingApproval) {
          // קבלת שם היחידה לתצוגה
          String unitName = '';
          try {
            final unit = await UnitRepository().getById(user.unitId!);
            unitName = unit?.name ?? '';
          } catch (_) {}
          print('DEBUG HomeRouter: user awaiting approval → WaitingForApprovalScreen');
          _navigateTo(WaitingForApprovalScreen(unitName: unitName));
          return;
        }
      }

      // 4. קבלת כובע יחיד
      final hat = await _sessionService.getUserHat(user.uid);
      print('DEBUG HomeRouter: hat=${hat?.typeName}');

      if (hat == null) {
        // משתמש ללא כובע — admin/developer → מסך ניהול, אחרת → מסך מנווט
        final isAdmin = user.role == 'admin' ||
            user.role == 'developer' ||
            user.role == 'unit_admin';
        _navigateTo(isAdmin
            ? const HomeScreen()
            : const NavigatorHomeScreen());
      } else {
        await _sessionService.saveSession(hat);
        _navigateTo(hat.type == HatType.navigator
            ? const NavigatorHomeScreen()
            : const HomeScreen());
      }
    } catch (e, stackTrace) {
      print('DEBUG HomeRouter: ERROR: $e');
      print('DEBUG HomeRouter: $stackTrace');
      _navigateTo(const NavigatorHomeScreen());
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.navigation,
              size: 100,
              color: Colors.blue,
            ),
            const SizedBox(height: 20),
            Text(
              'Navigate',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 40),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
