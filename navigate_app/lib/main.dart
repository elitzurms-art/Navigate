import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'services/session_service.dart';
import 'core/map_config.dart';
import 'data/repositories/navigation_tree_repository.dart';
import 'data/repositories/user_repository.dart';
import 'data/sync/sync_manager.dart';
import 'domain/entities/hat_type.dart';
import 'presentation/screens/auth/login_screen.dart';
import 'presentation/screens/auth/register_screen.dart';
import 'presentation/screens/auth/hat_selection_screen.dart';
import 'presentation/screens/main_mode_selection_screen.dart';
import 'presentation/screens/home/home_screen.dart';
import 'presentation/screens/home/navigator_home_screen.dart';
import 'presentation/screens/navigation_trees/unit_admin_frameworks_screen.dart';

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

  // אתחול קונפיגורציית מפה
  await MapConfig().init();

  // יצירת משתמש מפתח ומשתמשי ניסוי
  final authService = AuthService();
  await authService.ensureDeveloperUser();
  await authService.ensureTestUsers();

  // ניקוי חד-פעמי: מחיקת עצי ניווט ישנים ללא unitId על מסגרות
  await _migrateDeleteOldTrees();

  // מחיקת משתמשים ללא שם
  await _deleteNamelessUsers();

  // אם יש משתמש מחובר מקומית אבל אין אימות Firebase — כניסה אנונימית
  // כדי לאפשר גישה ל-Firestore (הכללים דורשים isAuthenticated)
  await _ensureFirebaseAuth();

  // התחלת סנכרון עם Firebase
  final syncManager = SyncManager();
  await syncManager.start();

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
    await FirebaseAuth.instance.signInAnonymously();
    print('DEBUG: Signed in anonymously for Firestore access (user=$loggedInUid)');
  } catch (e) {
    print('DEBUG: Anonymous sign-in failed: $e');
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
        '/unit-admin-frameworks': (context) => const UnitAdminFrameworksScreen(),
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

      // 2. סריקת כובעים
      final user = await _authService.getCurrentUser();
      print('DEBUG HomeRouter: user=${user?.uid}, role=${user?.role}');
      if (user == null) {
        _navigateTo(const HomeScreen());
        return;
      }

      final unitHats = await _sessionService.scanUserHats(user.uid);
      final totalHats = unitHats.fold<int>(0, (sum, u) => sum + u.hats.length);
      print('DEBUG HomeRouter: totalHats=$totalHats, units=${unitHats.length}');
      for (final uh in unitHats) {
        print('DEBUG HomeRouter: unit=${uh.unitName}, hats=${uh.hats.map((h) => h.typeName).toList()}');
      }

      if (totalHats == 0) {
        _navigateTo(const HomeScreen());
      } else if (totalHats == 1) {
        final hat = unitHats.first.hats.first;
        await _sessionService.saveSession(hat);
        _navigateTo(hat.type == HatType.navigator
            ? const NavigatorHomeScreen()
            : const HomeScreen());
      } else {
        _navigateTo(HatSelectionScreen(unitHats: unitHats));
      }
    } catch (e, stackTrace) {
      print('DEBUG HomeRouter: ERROR: $e');
      print('DEBUG HomeRouter: $stackTrace');
      _navigateTo(const HomeScreen());
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
