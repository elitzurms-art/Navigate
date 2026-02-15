import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../domain/entities/navigation.dart' as domain;
import '../../../domain/entities/navigation_tree.dart';
import '../../../domain/entities/user.dart';
import '../../../data/repositories/navigation_repository.dart';
import '../../../data/repositories/navigation_tree_repository.dart';
import '../../../data/repositories/navigation_track_repository.dart';
import '../../../data/repositories/checkpoint_punch_repository.dart';
import '../../../data/repositories/navigator_alert_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/repositories/area_repository.dart';
import '../../../data/repositories/unit_repository.dart';
import '../../../core/constants/app_constants.dart';
import '../../../services/auth_service.dart';
import '../../../services/session_service.dart';
import 'create_navigation_screen.dart';
import 'training_mode_screen.dart';
import 'system_check_screen.dart';
import 'routes_verification_screen.dart';
import 'routes_setup_screen.dart';
import 'approval_screen.dart';
import 'investigation_screen.dart';
import 'waiting_screen.dart';
import 'navigator_planning_screen.dart';
import 'data_loading_screen.dart';
import 'navigation_preparation_screen.dart';
import 'data_export_screen.dart';
import 'navigation_management_screen.dart';


/// צומת לקיבוץ ניווטים לפי עץ
class _TreeGroupNode {
  final NavigationTree tree;
  final List<domain.Navigation> navigations;

  const _TreeGroupNode({
    required this.tree,
    required this.navigations,
  });
}

/// מסך רשימת ניווטים
class NavigationsListScreen extends StatefulWidget {
  const NavigationsListScreen({super.key});

  @override
  State<NavigationsListScreen> createState() => _NavigationsListScreenState();
}

class _NavigationsListScreenState extends State<NavigationsListScreen> with WidgetsBindingObserver {
  final NavigationRepository _repository = NavigationRepository();
  final UserRepository _userRepository = UserRepository();
  final AreaRepository _areaRepository = AreaRepository();
  final AuthService _authService = AuthService();
  List<domain.Navigation> _navigations = [];
  Map<String, String> _areaNames = {};
  Map<String, NavigationTree> _treesById = {};
  Set<String> _expandedNodes = {};
  bool _isLoading = false;
  User? _currentUser;
  StreamSubscription<List<domain.Navigation>>? _navigationsListener;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadCurrentUser();
    _loadAreaNames();
    _loadNavigations();
    _startNavigationsListener();
  }

  Future<void> _loadCurrentUser() async {
    try {
      final user = await _authService.getCurrentUser();
      if (mounted) {
        setState(() {
          _currentUser = user;
        });
      }
    } catch (e) {
      print('DEBUG: Error loading current user: $e');
    }
  }

  Future<void> _loadAreaNames() async {
    try {
      final areas = await _areaRepository.getAll();
      if (mounted) {
        setState(() {
          _areaNames = {for (final area in areas) area.id: area.name};
        });
      }
    } catch (e) {
      print('DEBUG: Error loading area names: $e');
    }
  }

  @override
  void dispose() {
    _navigationsListener?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadNavigations();
    }
  }

  /// האזנה בזמן אמת לשינויי ניווטים ב-Firestore
  void _startNavigationsListener() {
    _navigationsListener?.cancel();
    _navigationsListener = _repository.watchAllNavigations().listen(
      (firestoreNavigations) async {
        if (!mounted) return;
        // בדיקה אם יש שינוי בסטטוס של אחד הניווטים הקיימים
        bool hasChanges = false;
        for (final fsNav in firestoreNavigations) {
          final existing = _navigations.where((n) => n.id == fsNav.id).firstOrNull;
          if (existing == null) {
            hasChanges = true; // ניווט חדש
            break;
          }
          if (existing.status != fsNav.status || existing.updatedAt != fsNav.updatedAt) {
            hasChanges = true; // סטטוס או נתונים השתנו
            break;
          }
        }
        // בדיקה אם ניווט נמחק
        if (!hasChanges && _navigations.length != firestoreNavigations.length) {
          hasChanges = true;
        }
        if (hasChanges) {
          // עדכון local DB ורענון תצוגה
          for (final nav in firestoreNavigations) {
            await _repository.updateLocalFromFirestore(nav);
          }
          _loadNavigations();
        }
      },
      onError: (e) {
        print('DEBUG: Navigations listener error: $e');
      },
    );
  }

  Future<void> _loadNavigations() async {
    setState(() => _isLoading = true);
    try {
      final allNavigations = await _repository.getAll();
      final treeRepo = NavigationTreeRepository();

      // סינון לפי session — יחידה, מסגרת ותת-מסגרת
      final session = await SessionService().getSavedSession();
      List<domain.Navigation> filteredNavigations = allNavigations;
      List<NavigationTree> trees = [];

      if (session != null && session.unitId.isNotEmpty) {
        // טעינת עצים של היחידה + כל היחידות שמתחתיה
        final unitRepo = UnitRepository();
        final descendantIds = await unitRepo.getDescendantIds(session.unitId);
        final allUnitIds = [session.unitId, ...descendantIds];

        final List<NavigationTree> unitTrees = [];
        for (final uid in allUnitIds) {
          unitTrees.addAll(await treeRepo.getByUnitId(uid));
        }
        trees = unitTrees;
        final treeIds = unitTrees.map((t) => t.id).toSet();
        filteredNavigations = allNavigations
            .where((nav) => treeIds.contains(nav.treeId))
            .toList();

        // סינון לפי תת-מסגרת — מנהל/מפקד רואה רק ניווטים של תת-המסגרת שלו
        if (session.subFrameworkId != null && session.subFrameworkId!.isNotEmpty) {
          filteredNavigations = filteredNavigations.where((nav) {
            // ניווט ללא יחידה — מראים אותו לכולם
            if (nav.selectedUnitId == null || nav.selectedUnitId!.isEmpty) return true;
            // ניווט ללא תת-מסגרות — מראים לכולם באותה יחידה
            if (nav.selectedSubFrameworkIds.isEmpty) return true;
            // ניווט עם תת-מסגרות — מראים רק אם התת-מסגרת של המשתמש כלולה
            return nav.selectedSubFrameworkIds.contains(session.subFrameworkId);
          }).toList();
        }
      } else {
        // ללא session — טעינת כל העצים
        trees = await treeRepo.getAll();
      }

      // בניית מפת עצים לפי ID
      final treesMap = <String, NavigationTree>{};
      for (final tree in trees) {
        treesMap[tree.id] = tree;
      }

      // פתיחה אוטומטית של צמתים ברמה העליונה
      final newExpanded = <String>{..._expandedNodes};
      for (final tree in trees) {
        for (final sectionKey in ['prep', 'train', 'review']) {
          newExpanded.add('${sectionKey}_${tree.id}');
        }
      }

      setState(() {
        _navigations = filteredNavigations;
        _treesById = treesMap;
        _expandedNodes = newExpanded;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה בטעינה: $e')),
        );
      }
    }
  }

  // ======== דיאלוגים ========

  Future<void> _showSpinner(String message) async {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(message),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// דיאלוג אזהרה לחזרה אחורה - מאפס צירים
  Future<bool> _showResetWarning() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.orange, size: 28),
            SizedBox(width: 8),
            Text('אזהרה'),
          ],
        ),
        content: const Text(
          'שינויים אלה ישפיעו על הצירים שנוצרו ויאפסו את הניווט.\n\n'
          'כל הצירים שחולקו יימחקו ותצטרך לחלק מחדש.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('המשך בכל זאת'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  // ======== מחיקה ========

  Future<void> _deleteNavigation(domain.Navigation navigation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.red[700], size: 28),
            const SizedBox(width: 8),
            const Text('מחיקת ניווט'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              navigation.name,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red[200]!),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, color: Colors.red[700], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'פעולה זו בלתי הפיכה!\n'
                      'כל נתוני הניווט (צירים, מסלולים, דקירות, ציונים) יימחקו לצמיתות.',
                      style: TextStyle(
                        color: Colors.red[900],
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('ביטול', style: TextStyle(color: Colors.grey[600])),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('מחק לצמיתות'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _showSpinner('מוחק...');

      try {
        await _repository.delete(navigation.id);
        if (mounted) Navigator.pop(context);
        _loadNavigations();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ניווט נמחק')),
          );
        }
      } catch (e) {
        if (mounted) Navigator.pop(context);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('שגיאה במחיקה: $e')),
          );
        }
      }
    }
  }

  // ======== מעברי סטטוס ========

  /// חזרה לשלב חלוקת נקודות (עם איפוס צירים)
  Future<void> _goBackToDistribution(domain.Navigation navigation) async {
    if (!await _showResetWarning()) return;
    await _showSpinner('מאפס צירים...');

    final updated = navigation.copyWith(
      status: 'preparation',
      routesStage: 'setup',
      routesDistributed: false,
      routes: {},
      updatedAt: DateTime.now(),
    );
    await _repository.update(updated);

    if (mounted) {
      Navigator.pop(context); // סגירת spinner
      _loadNavigations();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('הניווט חזר לשלב חלוקת נקודות - צירים אופסו'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  /// חזרה לשלב וידוא צירים (עם איפוס אישורים)
  Future<void> _goBackToVerification(domain.Navigation navigation) async {
    if (!await _showResetWarning()) return;
    await _showSpinner('מחזיר לוידוא צירים...');

    final updated = navigation.copyWith(
      status: 'preparation',
      routesStage: 'verification',
      updatedAt: DateTime.now(),
    );
    await _repository.update(updated);

    if (mounted) {
      Navigator.pop(context);
      _loadNavigations();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('הניווט חזר לשלב וידוא צירים'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  /// בדיקת התנגשויות מנווטים - האם מנווט כבר משויך לניווט פעיל אחר
  /// מחזיר true אם אין התנגשויות (בטוח להמשיך), false אם יש התנגשויות
  Future<bool> _checkNavigatorConflicts(domain.Navigation navigation) async {
    try {
      // 1. קבלת כל המנווטים בניווט הנוכחי (מפתחות ב-routes)
      final navigatorUids = navigation.routes.keys.toSet();
      if (navigatorUids.isEmpty) return true;

      // 2. קבלת כל הניווטים האחרים בסטטוסים פעילים
      final allNavigations = await _repository.getAll();
      final activeStatuses = {'learning', 'system_check', 'active', 'waiting'};
      final otherActiveNavigations = allNavigations.where((nav) =>
        nav.id != navigation.id && activeStatuses.contains(nav.status)
      ).toList();

      if (otherActiveNavigations.isEmpty) return true;

      // 3. בדיקת התנגשויות
      // מיפוי: uid מנווט -> רשימת שמות ניווטים שהוא משויך אליהם
      final Map<String, List<String>> conflicts = {};

      for (final uid in navigatorUids) {
        for (final otherNav in otherActiveNavigations) {
          if (otherNav.routes.containsKey(uid)) {
            conflicts.putIfAbsent(uid, () => []);
            conflicts[uid]!.add(otherNav.name);
          }
        }
      }

      if (conflicts.isEmpty) return true;

      // 4. ניסיון לפענח שמות מנווטים מ-UserRepository
      final Map<String, String> uidToName = {};
      for (final uid in conflicts.keys) {
        try {
          final user = await _userRepository.getUser(uid);
          if (user != null) {
            uidToName[uid] = user.fullName.isNotEmpty ? user.fullName : user.personalNumber;
          } else {
            uidToName[uid] = uid;
          }
        } catch (_) {
          uidToName[uid] = uid;
        }
      }

      // 5. הצגת דיאלוג אזהרה
      if (!mounted) return false;

      final conflictLines = conflicts.entries.map((entry) {
        final name = uidToName[entry.key] ?? entry.key;
        final navNames = entry.value.join(', ');
        return '$name  -  $navNames';
      }).join('\n');

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.orange, size: 28),
              SizedBox(width: 8),
              Text('התנגשות מנווטים'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'המנווטים הבאים כבר משויכים לניווטים פעילים אחרים:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  conflictLines,
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 12),
                const Text(
                  'האם להמשיך בכל זאת?',
                  style: TextStyle(color: Colors.red),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('ביטול'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('המשך בכל זאת'),
            ),
          ],
        ),
      );

      return confirmed == true;
    } catch (e) {
      print('DEBUG: Error checking navigator conflicts: $e');
      // במקרה של שגיאה, מאפשרים להמשיך
      return true;
    }
  }

  /// העברה למצב למידה
  Future<void> _startTrainingMode(domain.Navigation navigation) async {
    // בדיקה אם יש הגדרות זמנים אוטומטיים
    final hasAutoTiming = navigation.learningSettings.autoLearningTimes;

    if (hasAutoTiming) {
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('מצב למידה לניווט'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('נקבעה הפעלה אוטומטית:'),
              const SizedBox(height: 8),
              Text(
                'תאריך: ${navigation.learningSettings.learningDate?.toString().split(' ')[0] ?? 'לא הוגדר'}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                'שעות: ${navigation.learningSettings.learningStartTime ?? "?"} - ${navigation.learningSettings.learningEndTime ?? "?"}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'edit'),
              child: const Text('ערוך זמנים'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'cancel'),
              child: const Text('ביטול'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'start'),
              style: TextButton.styleFrom(foregroundColor: Colors.green),
              child: const Text('הפעל עכשיו'),
            ),
          ],
        ),
      );

      if (choice == 'edit') {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CreateNavigationScreen(navigation: navigation),
          ),
        );
        if (result == true) _loadNavigations();
        return;
      } else if (choice != 'start') {
        return;
      }

      // בדיקת התנגשויות מנווטים
      if (!await _checkNavigatorConflicts(navigation)) return;
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('מצב למידה לניווט'),
          content: const Text('האם להפעיל מצב למידה לניווט זה?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('ביטול'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.green),
              child: const Text('הפעל'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      // בדיקת התנגשויות מנווטים
      if (!await _checkNavigatorConflicts(navigation)) return;
    }

    await _showSpinner('מעביר למצב למידה...');

    final updatedNavigation = navigation.copyWith(
      status: 'learning',
      trainingStartTime: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await _repository.update(updatedNavigation);

    if (mounted) {
      Navigator.pop(context); // סגירת spinner
      _loadNavigations();

      final isCommander = _currentUser?.hasCommanderPermissions ?? true;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => TrainingModeScreen(
            navigation: updatedNavigation,
            isCommander: isCommander,
          ),
        ),
      ).then((_) {
        _loadNavigations();
      });
    }
  }

  /// השהיית מצב למידה
  Future<void> _pauseTrainingMode(domain.Navigation navigation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('השהיית מצב למידה'),
        content: const Text(
          'האם להשהות את מצב הלמידה?\n\n'
          'הניווט יחזור למצב "מוכן" ותוכל להפעיל אותו שוב מאוחר יותר.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            child: const Text('השהה'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _showSpinner('משהה מצב למידה...');

    final updatedNavigation = navigation.copyWith(
      status: 'ready',
      updatedAt: DateTime.now(),
    );
    await _repository.update(updatedNavigation);

    if (mounted) {
      Navigator.pop(context);
      _loadNavigations();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('מצב למידה הושהה'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  /// סיום מצב למידה
  Future<void> _endTrainingMode(domain.Navigation navigation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('סיום מצב למידה'),
        content: const Text(
          'האם לסיים את מצב הלמידה?\n\n'
          'הניווט יועבר למצב "בדיקת מערכת" לקראת הפעלה אקטיבית.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('סיים'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _showSpinner('מסיים מצב למידה...');

    final updatedNavigation = navigation.copyWith(
      status: 'system_check',
      updatedAt: DateTime.now(),
    );
    await _repository.update(updatedNavigation);

    if (mounted) {
      Navigator.pop(context);
      _loadNavigations();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('מצב למידה הסתיים - הניווט במצב בדיקת מערכת'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  /// העברה לבדיקת מערכות
  Future<void> _startSystemCheck(domain.Navigation navigation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('בדיקת מערכות'),
        content: const Text(
          'האם להתחיל בדיקת מערכות?\n\n'
          'המנווטים יקבלו התראה להיכנס למצב בדיקה ולאשר חיבור GPS ואינטרנט.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.purple),
            child: const Text('התחל בדיקה'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // בדיקת התנגשויות מנווטים
    if (!await _checkNavigatorConflicts(navigation)) return;

    await _showSpinner('מעביר לבדיקת מערכות...');

    final updatedNavigation = navigation.copyWith(
      status: 'system_check',
      systemCheckStartTime: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await _repository.update(updatedNavigation);

    if (mounted) {
      Navigator.pop(context); // סגירת spinner

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SystemCheckScreen(
            navigation: updatedNavigation,
            isCommander: true,
            currentUser: _currentUser,
          ),
        ),
      ).then((_) => _loadNavigations());
    }
  }

  /// חזרה ממצב בדיקת מערכות למוכן
  Future<void> _goBackToReady(domain.Navigation navigation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('חזרה למצב מוכן'),
        content: const Text('האם להחזיר את הניווט למצב "מוכן"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('החזר'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _showSpinner('מחזיר למצב מוכן...');

    final updated = navigation.copyWith(
      status: 'ready',
      updatedAt: DateTime.now(),
    );
    await _repository.update(updated);

    if (mounted) {
      Navigator.pop(context);
      _loadNavigations();
    }
  }

  // ======== פתיחת מסכים ========

  /// פתיחת מסך מתאים לפי סטטוס הניווט
  Future<void> _openNavigationScreen(domain.Navigation navigation) async {
    // מצבים שדורשים טעינת נתונים אופליין לפני כניסה
    final needsDataLoading = [
      'waiting',
      'active',
    ].contains(navigation.status);

    if (needsDataLoading && _currentUser != null) {
      final isCommander = _currentUser!.hasCommanderPermissions;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DataLoadingScreen(
            navigation: navigation,
            currentUser: _currentUser!,
            isCommander: isCommander,
            onLoadingComplete: () {
              Navigator.pop(context);

              Widget nextScreen;
              final isCmd = _currentUser != null && _currentUser!.hasCommanderPermissions;
              switch (navigation.status) {
                case 'waiting':
                  nextScreen = isCmd
                      ? NavigationManagementScreen(navigation: navigation)
                      : WaitingScreen(navigation: navigation);
                  break;
                case 'active':
                  nextScreen = NavigationManagementScreen(navigation: navigation);
                  break;
                default:
                  nextScreen = WaitingScreen(navigation: navigation);
              }

              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => nextScreen),
              ).then((_) => _loadNavigations());
            },
          ),
        ),
      );

      _loadNavigations();
      return;
    }

    Widget screen;

    switch (navigation.status) {
      case 'preparation':
        screen = NavigationPreparationScreen(navigation: navigation);
        break;

      case 'ready':
        screen = NavigationPreparationScreen(navigation: navigation);
        break;

      case 'learning':
        if (_currentUser != null && _currentUser!.hasCommanderPermissions) {
          screen = TrainingModeScreen(
            navigation: navigation,
            isCommander: true,
          );
        } else {
          screen = NavigatorPlanningScreen(navigation: navigation);
        }
        break;

      case 'waiting':
        if (_currentUser != null && _currentUser!.hasCommanderPermissions) {
          screen = NavigationManagementScreen(navigation: navigation);
        } else {
          screen = WaitingScreen(navigation: navigation);
        }
        break;

      case 'system_check':
        final isCommanderSC = _currentUser != null && _currentUser!.hasCommanderPermissions;
        screen = SystemCheckScreen(
          navigation: navigation,
          isCommander: isCommanderSC,
          currentUser: _currentUser,
        );
        break;

      case 'approval':
        final isNavigatorApproval = _currentUser == null || !_currentUser!.hasCommanderPermissions;
        screen = ApprovalScreen(navigation: navigation, isNavigator: isNavigatorApproval);
        break;

      case 'review':
        final isNavigatorReview = _currentUser == null || !_currentUser!.hasCommanderPermissions;
        screen = InvestigationScreen(navigation: navigation, isNavigator: isNavigatorReview);
        break;

      default:
        screen = CreateNavigationScreen(navigation: navigation);
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => screen),
    );

    if (result == true || result == 'deleted') {
      _loadNavigations();
    }
  }

  // ======== בניית עץ מסגרות ========

  /// קיבוץ ניווטים לפי עץ ניווט
  List<_TreeGroupNode> _groupByTree(List<domain.Navigation> navs) {
    final navsByTree = <String, List<domain.Navigation>>{};
    for (final nav in navs) {
      if (nav.treeId.isNotEmpty) {
        navsByTree.putIfAbsent(nav.treeId, () => []).add(nav);
      }
    }

    final nodes = <_TreeGroupNode>[];
    for (final entry in navsByTree.entries) {
      final tree = _treesById[entry.key];
      if (tree != null) {
        nodes.add(_TreeGroupNode(tree: tree, navigations: entry.value));
      }
    }
    return nodes;
  }

  /// ניווטים ללא עץ
  List<domain.Navigation> _getOrphanNavigations(List<domain.Navigation> navs) {
    return navs.where((nav) => nav.treeId.isEmpty || !_treesById.containsKey(nav.treeId)).toList();
  }

  // ======== עזרים לתצוגה ========

  String _getStatusText(String status) {
    switch (status) {
      case 'preparation':
        return 'הכנה';
      case 'ready':
        return 'מוכן';
      case 'learning':
        return 'למידה';
      case 'waiting':
        return 'ממתין';
      case 'system_check':
        return 'בדיקת מערכת';
      case 'active':
        return 'פעיל';
      case 'approval':
        return 'אישור';
      case 'review':
        return 'סקירה';
      default:
        return status;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'preparation':
        return Colors.orange;
      case 'ready':
        return Colors.teal;
      case 'learning':
        return Colors.blue;
      case 'waiting':
        return Colors.cyan;
      case 'system_check':
        return Colors.purple;
      case 'active':
        return Colors.green;
      case 'approval':
        return Colors.amber;
      case 'review':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'preparation':
        return Icons.settings;
      case 'ready':
        return Icons.check_circle_outline;
      case 'learning':
        return Icons.school;
      case 'waiting':
        return Icons.hourglass_empty;
      case 'system_check':
        return Icons.verified_user;
      case 'active':
        return Icons.play_circle_filled;
      case 'approval':
        return Icons.thumb_up;
      case 'review':
        return Icons.rate_review;
      default:
        return Icons.navigation;
    }
  }

  String _getNavigationTypeText(String? type) {
    switch (type) {
      case 'regular':
        return 'רגיל';
      case 'clusters':
        return 'אשכולות';
      case 'star':
        return 'כוכב';
      case 'reverse':
        return 'הפוך';
      case 'parachute':
        return 'מצנח';
      case 'developing':
        return 'מתפתח';
      default:
        return 'רגיל';
    }
  }

  String _getRoutesStageText(String? stage) {
    switch (stage) {
      case 'not_started':
        return 'טרם הוגדר';
      case 'setup':
        return 'חלוקת נקודות';
      case 'verification':
        return 'וידוא צירים';
      case 'editing':
        return 'עריכת צירים';
      case 'ready':
        return 'צירים מוכנים';
      default:
        return 'טרם הוגדר';
    }
  }

  /// בדיקה אם ניתן למחוק ניווט
  bool _canDelete(domain.Navigation navigation) {
    if (navigation.status == 'learning') return false;
    if (navigation.status == 'system_check') return false;
    return true;
  }

  // ======== בניית popup menu לפי סטטוס ========

  List<PopupMenuEntry<String>> _buildPopupMenuItems(domain.Navigation navigation) {
    final items = <PopupMenuEntry<String>>[];
    final stage = navigation.routesStage ?? 'not_started';

    switch (navigation.status) {
      case 'preparation':
        // שלב הכנה - עריכת הגדרות, העברה לאימון, מחיקה
        items.add(const PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.edit, color: Colors.blue),
              SizedBox(width: 8),
              Text('ערוך הגדרות'),
            ],
          ),
        ));
        items.add(const PopupMenuItem(
          value: 'start_training',
          child: Row(
            children: [
              Icon(Icons.play_arrow, color: Colors.green),
              SizedBox(width: 8),
              Text('העבר לאימון'),
            ],
          ),
        ));
        // Export - available after verification
        if (navigation.routesStage == 'ready' ||
            (navigation.routes.isNotEmpty && navigation.routes.values.any((r) => r.isVerified))) {
          items.add(const PopupMenuItem(
            value: 'export_routes',
            child: Row(
              children: [
                Icon(Icons.picture_as_pdf, color: Colors.deepOrange),
                SizedBox(width: 8),
                Text('ייצוא צירים'),
              ],
            ),
          ));
        }
        items.add(const PopupMenuDivider());
        items.add(const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete, color: Colors.red),
              SizedBox(width: 8),
              Text('מחק', style: TextStyle(color: Colors.red)),
            ],
          ),
        ));
        break;

      case 'ready':
        // מוכן - עריכת הגדרות, העברה לאימון, מחיקה
        items.add(const PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.edit, color: Colors.blue),
              SizedBox(width: 8),
              Text('ערוך הגדרות'),
            ],
          ),
        ));
        items.add(const PopupMenuItem(
          value: 'start_training',
          child: Row(
            children: [
              Icon(Icons.play_arrow, color: Colors.green),
              SizedBox(width: 8),
              Text('העבר לאימון'),
            ],
          ),
        ));
        // Export - available after verification
        if (navigation.routesStage == 'ready' ||
            (navigation.routes.isNotEmpty && navigation.routes.values.any((r) => r.isVerified))) {
          items.add(const PopupMenuItem(
            value: 'export_routes',
            child: Row(
              children: [
                Icon(Icons.picture_as_pdf, color: Colors.deepOrange),
                SizedBox(width: 8),
                Text('ייצוא צירים'),
              ],
            ),
          ));
        }
        items.add(const PopupMenuDivider());
        items.add(const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete, color: Colors.red),
              SizedBox(width: 8),
              Text('מחק', style: TextStyle(color: Colors.red)),
            ],
          ),
        ));
        break;

      case 'learning':
        // למידה - השהייה, סיום, בדיקת מערכות
        items.add(const PopupMenuItem(
          value: 'pause_training',
          child: Row(
            children: [
              Icon(Icons.pause_circle, color: Colors.orange),
              SizedBox(width: 8),
              Text('השהה למידה'),
            ],
          ),
        ));
        items.add(const PopupMenuItem(
          value: 'end_training',
          child: Row(
            children: [
              Icon(Icons.stop_circle, color: Colors.red),
              SizedBox(width: 8),
              Text('סיים למידה'),
            ],
          ),
        ));
        items.add(const PopupMenuItem(
          value: 'system_check',
          child: Row(
            children: [
              Icon(Icons.verified_user, color: Colors.purple),
              SizedBox(width: 8),
              Text('בדיקת מערכות'),
            ],
          ),
        ));
        break;

      case 'system_check':
        // בדיקת מערכות - חזרה למוכן
        items.add(const PopupMenuItem(
          value: 'back_to_ready',
          child: Row(
            children: [
              Icon(Icons.undo, color: Colors.orange),
              SizedBox(width: 8),
              Text('חזרה למוכן'),
            ],
          ),
        ));
        break;

      case 'waiting':
        // ממתין — מפקד יכול להתחיל את הניווט
        if (_currentUser != null && _currentUser!.hasCommanderPermissions) {
          items.add(const PopupMenuItem(
            value: 'start_navigation',
            child: Row(
              children: [
                Icon(Icons.play_arrow, color: Colors.green),
                SizedBox(width: 8),
                Text('התחל ניווט'),
              ],
            ),
          ));
        }
        break;

      default:
        break;
    }

    return items;
  }

  /// טיפול בבחירת פעולה מה-popup
  Future<void> _handlePopupAction(String action, domain.Navigation navigation) async {
    switch (action) {
      case 'edit':
        final hasRoutes = navigation.routesDistributed;
        if (hasRoutes) {
          final proceed = await _showResetWarning();
          if (!proceed) return;
        }
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CreateNavigationScreen(navigation: navigation),
          ),
        );
        if (result == true) _loadNavigations();
        break;

      case 'distribute':
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => RoutesSetupScreen(navigation: navigation),
          ),
        );
        if (result == true) _loadNavigations();
        break;

      case 'verify_routes':
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => RoutesVerificationScreen(navigation: navigation),
          ),
        );
        if (result == true) _loadNavigations();
        break;

      case 'start_learning':
        _startTrainingMode(navigation);
        break;

      case 'start_training':
        _startTrainingMode(navigation);
        break;

      case 'system_check':
        _startSystemCheck(navigation);
        break;

      case 'pause_training':
        _pauseTrainingMode(navigation);
        break;

      case 'end_training':
        _endTrainingMode(navigation);
        break;

      case 'back_to_distribution':
        _goBackToDistribution(navigation);
        break;

      case 'back_to_verification':
        _goBackToVerification(navigation);
        break;

      case 'back_to_ready':
        _goBackToReady(navigation);
        break;

      case 'export_routes':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => DataExportScreen(navigation: navigation),
          ),
        );
        break;

      case 'start_navigation':
        _startNavigation(navigation);
        break;

      case 'delete':
        _deleteNavigation(navigation);
        break;
    }
  }

  /// איפוס נתוני מנווטים — tracks, דקירות, התראות — לפני התחלת ניווט פעיל
  Future<void> _resetNavigatorData(String navigationId) async {
    final trackRepo = NavigationTrackRepository();
    final punchRepo = CheckpointPunchRepository();
    final alertRepo = NavigatorAlertRepository();

    // מחיקה מקומית (Drift)
    await trackRepo.deleteByNavigation(navigationId);
    await punchRepo.deleteByNavigation(navigationId);
    await alertRepo.deleteByNavigation(navigationId);

    // מחיקה מ-Firestore — tracks
    try {
      final tracksSnapshot = await FirebaseFirestore.instance
          .collection(AppConstants.navigationTracksCollection)
          .where('navigationId', isEqualTo: navigationId)
          .get();
      for (final doc in tracksSnapshot.docs) {
        await doc.reference.delete();
      }
    } catch (_) {
      // Firestore לא זמין — ימחק בסנכרון הבא
    }
  }

  Future<void> _startNavigation(domain.Navigation navigation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('התחלת ניווט'),
        content: Text('האם להתחיל את הניווט "${navigation.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.green),
            child: const Text('התחל'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      // איפוס סטטוסים אישיים — מחיקת tracks, דקירות והתראות ישנים
      await _resetNavigatorData(navigation.id);

      final updated = navigation.copyWith(
        status: 'active',
        activeStartTime: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await _repository.update(updated);
      _loadNavigations();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('הניווט הופעל בהצלחה'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ======== בניית UI ========

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ניווטים'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadNavigations,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _navigations.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.navigation, size: 100, color: Colors.grey[300]),
                      const SizedBox(height: 20),
                      Text(
                        'אין ניווטים',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'לחץ על + להוספת ניווט',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: Colors.grey[500]),
                      ),
                    ],
                  ),
                )
              : _buildGroupedList(),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const CreateNavigationScreen(),
            ),
          );
          if (result == true) {
            _loadNavigations();
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  static const _preparationStatuses = {'preparation', 'ready', 'learning', 'system_check'};
  static const _trainingStatuses = {'waiting', 'active'};
  static const _reviewStatuses = {'approval', 'review'};

  Widget _buildGroupedList() {
    final prepNavs = _navigations.where((n) => _preparationStatuses.contains(n.status)).toList();
    final trainNavs = _navigations.where((n) => _trainingStatuses.contains(n.status)).toList();
    final reviewNavs = _navigations.where((n) => _reviewStatuses.contains(n.status)).toList();

    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        if (prepNavs.isNotEmpty) ...[
          _buildSectionHeader('הכנות ולמידה', Icons.settings, Colors.blue, prepNavs.length),
          ..._buildTreeGroupSection('prep', prepNavs),
        ],
        if (trainNavs.isNotEmpty) ...[
          _buildSectionHeader('אימון', Icons.play_arrow, Colors.orange, trainNavs.length),
          ..._buildTreeGroupSection('train', trainNavs),
        ],
        if (reviewNavs.isNotEmpty) ...[
          _buildSectionHeader('תחקור', Icons.analytics, Colors.green, reviewNavs.length),
          ..._buildTreeGroupSection('review', reviewNavs),
        ],
      ],
    );
  }

  List<Widget> _buildTreeGroupSection(String sectionKey, List<domain.Navigation> navs) {
    final treeGroups = _groupByTree(navs);
    final orphanNavs = _getOrphanNavigations(navs);

    if (treeGroups.isEmpty && orphanNavs.isEmpty) {
      return navs.map(_buildNavigationCard).toList();
    }
    if (treeGroups.isEmpty) {
      return orphanNavs.map(_buildNavigationCard).toList();
    }

    final widgets = <Widget>[];
    for (final group in treeGroups) {
      widgets.addAll(_buildTreeGroupNode(sectionKey, group));
    }
    for (final nav in orphanNavs) {
      widgets.add(_buildNavigationTreeItem(nav));
    }
    return widgets;
  }

  List<Widget> _buildTreeGroupNode(String sectionKey, _TreeGroupNode group) {
    final nodeKey = '${sectionKey}_${group.tree.id}';
    final isExpanded = _expandedNodes.contains(nodeKey);
    final navCount = group.navigations.length;

    final widgets = <Widget>[];

    // שורת כותרת עץ
    widgets.add(
      InkWell(
        onTap: () {
          setState(() {
            if (isExpanded) {
              _expandedNodes.remove(nodeKey);
            } else {
              _expandedNodes.add(nodeKey);
            }
          });
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              Icon(
                isExpanded ? Icons.expand_more : Icons.chevron_left,
                size: 22,
                color: Colors.grey[600],
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.account_tree,
                size: 20,
                color: Colors.amber[700],
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  group.tree.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$navCount',
                  style: const TextStyle(
                    color: Colors.blue,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (isExpanded) {
      for (final nav in group.navigations) {
        widgets.add(
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 16.0),
            child: _buildNavigationTreeItem(nav),
          ),
        );
      }
    }

    return widgets;
  }

  /// פריט ניווט קומפקטי בתוך עץ מסגרות
  Widget _buildNavigationTreeItem(domain.Navigation navigation) {
    final statusColor = _getStatusColor(navigation.status);
    final routesCount = navigation.routes.length;
    final popupItems = _buildPopupMenuItems(navigation);
    final canDelete = _canDelete(navigation);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: statusColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _openNavigationScreen(navigation),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              // אייקון סטטוס
              Icon(
                _getStatusIcon(navigation.status),
                color: statusColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              // שם ניווט
              Expanded(
                child: Text(
                  navigation.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              // תגית סטטוס
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _getStatusText(navigation.status),
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // מספר צירים
              if (routesCount > 0) ...[
                Icon(Icons.people, size: 14, color: Colors.grey[500]),
                const SizedBox(width: 2),
                Text(
                  '$routesCount',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(width: 4),
              ],
              // כפתור מחיקה
              if (canDelete)
                SizedBox(
                  width: 32,
                  height: 32,
                  child: IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    color: Colors.red[400],
                    padding: EdgeInsets.zero,
                    tooltip: 'מחק ניווט',
                    onPressed: () => _deleteNavigation(navigation),
                  ),
                ),
              // תפריט פעולות
              if (popupItems.isNotEmpty)
                SizedBox(
                  width: 32,
                  height: 32,
                  child: PopupMenuButton<String>(
                    onSelected: (value) => _handlePopupAction(value, navigation),
                    itemBuilder: (context) => popupItems,
                    padding: EdgeInsets.zero,
                    iconSize: 20,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color, int count) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6, right: 4, left: 4),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationCard(domain.Navigation navigation) {
    final statusColor = _getStatusColor(navigation.status);
    final areaName = _areaNames[navigation.areaId] ?? '';
    final routesCount = navigation.routes.length;
    final dateStr = DateFormat('dd/MM/yyyy').format(navigation.createdAt);
    final popupItems = _buildPopupMenuItems(navigation);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: statusColor.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _openNavigationScreen(navigation),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // שורה עליונה - שם + סטטוס + תפריט
              Row(
                children: [
                  // אייקון סטטוס
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _getStatusIcon(navigation.status),
                      color: statusColor,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // שם ניווט
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          navigation.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        // סטטוס + סוג ניווט
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: statusColor.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                _getStatusText(navigation.status),
                                style: TextStyle(
                                  color: statusColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // תפריט פעולות
                  if (popupItems.isNotEmpty)
                    PopupMenuButton<String>(
                      onSelected: (value) => _handlePopupAction(value, navigation),
                      itemBuilder: (context) => popupItems,
                    ),
                ],
              ),
              const SizedBox(height: 10),
              // שורה תחתונה - מידע נוסף
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    _buildInfoChip(
                      Icons.explore,
                      _getNavigationTypeText(navigation.navigationType),
                    ),
                    if (areaName.isNotEmpty)
                      _buildInfoChip(Icons.map, areaName),
                    _buildInfoChip(
                      Icons.people,
                      '$routesCount צירים',
                    ),
                    _buildInfoChip(Icons.calendar_today, dateStr),
                  ],
                ),
              ),
              // שלב צירים - רק בהכנה
              if (navigation.status == 'preparation') ...[
                const SizedBox(height: 6),
                _buildRoutesStageIndicator(navigation),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.grey[600]),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[700],
          ),
        ),
      ],
    );
  }

  /// מחוון שלב צירים (progress indicator)
  Widget _buildRoutesStageIndicator(domain.Navigation navigation) {
    final stage = navigation.routesStage ?? 'not_started';
    final stages = ['not_started', 'setup', 'verification', 'ready'];
    final currentIndex = stages.indexOf(stage == 'editing' ? 'verification' : stage);

    return Row(
      children: [
        Icon(Icons.route, size: 14, color: Colors.grey[500]),
        const SizedBox(width: 6),
        Text(
          'שלב: ${_getRoutesStageText(stage)}',
          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Row(
            children: List.generate(stages.length, (i) {
              final isCompleted = i <= currentIndex;
              final isCurrent = i == currentIndex;
              return Expanded(
                child: Container(
                  height: 4,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    color: isCompleted
                        ? (isCurrent ? Colors.orange : Colors.teal)
                        : Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}
