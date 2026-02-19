import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../../domain/entities/hat_type.dart';
import '../../../domain/entities/navigation_tree.dart';
import '../../../domain/entities/unit.dart' as app_unit;
import '../../../domain/entities/user.dart' as app_user;
import '../../../data/repositories/navigation_tree_repository.dart';
import '../../../data/repositories/navigation_repository.dart';
import '../../../data/repositories/unit_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/sync/sync_manager.dart';
import '../../../core/constants/app_constants.dart';
import '../../../services/auth_service.dart';
import '../../../services/session_service.dart';
import '../../../services/framework_excel_service.dart';

// TODO: תפקיד מפקד (לפיתוח עתידי)
// - מפקד יכול להיכנס למסכי מנהל מערכת עם הרשאות ספציפיות
// - ההרשאות מוגדרות בעת שיוך המפקד למסגרת
// - ההרשאות כוללות: עריכה / מחיקה / שינוי / הוספה (יוגדר בהמשך)
// - יש להוסיף שדה permissions ל-Framework.adminIds או ליצור מבנה חדש
//   שמאחסן {uid, permissions: [edit, delete, modify, add]}

/// מחלקת עזר לייצוג התאמה של יחידה למשתמש
class _UnitMatch {
  final app_unit.Unit unit;
  final NavigationTree? tree; // העץ המשויך ליחידה (אם קיים)
  final String roleDescription; // "מנהל מערכת" / "משתמש"

  const _UnitMatch({
    required this.unit,
    this.tree,
    required this.roleDescription,
  });
}

/// מסך ניהול מסגרות למנהל מערכת יחידתי
/// מאפשר ליצור/לערוך/למחוק מסגרות ברמה מתחת לרמת המנהל ומטה
class UnitAdminFrameworksScreen extends StatefulWidget {
  const UnitAdminFrameworksScreen({super.key});

  @override
  State<UnitAdminFrameworksScreen> createState() =>
      _UnitAdminFrameworksScreenState();
}

class _UnitAdminFrameworksScreenState extends State<UnitAdminFrameworksScreen> {
  final NavigationTreeRepository _treeRepository = NavigationTreeRepository();
  final AuthService _authService = AuthService();

  app_user.User? _currentUser;
  List<NavigationTree> _allTrees = [];
  List<app_unit.Unit> _allUnits = [];
  app_unit.Unit? _adminUnit; // היחידה של המנהל
  NavigationTree? _adminTree; // העץ המשויך ליחידה של המנהל
  int? _adminLevel; // רמת המנהל
  bool _isLoading = true;
  String? _errorMessage;
  List<_UnitMatch> _allMatches = [];
  String _unitName = ''; // שם היחידה לתצוגה
  String _unitId = ''; // מזהה היחידה
  List<app_user.User> _allUsers = []; // כל המשתמשים לניהול משתמשים
  HatInfo? _currentHat; // כובע נוכחי — admin או commander
  Map<String, List<app_user.User>> _subFrameworkUsersMap = {}; // משתמשים לכל תת-מסגרת
  StreamSubscription<String>? _syncSubscription;

  @override
  void initState() {
    super.initState();
    _loadData();
    // האזנה לשינויי סנכרון — רענון אוטומטי כשמשתמשים/יחידות/עצים מתעדכנים
    _syncSubscription = SyncManager().onDataChanged.listen((collection) {
      if (mounted && (
          collection == AppConstants.usersCollection ||
          collection == AppConstants.unitsCollection ||
          collection == AppConstants.navigatorTreesCollection)) {
        _loadData();
      }
    });
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // טעינת המשתמש הנוכחי
      final user = await _authService.getCurrentUser();
      if (user == null) {
        setState(() {
          _errorMessage = 'לא מחובר למערכת';
          _isLoading = false;
        });
        return;
      }

      _currentUser = user;

      // טעינת כל העצים, יחידות ומשתמשים
      _allTrees = await _treeRepository.getAll();
      final unitRepo = UnitRepository();
      _allUnits = await unitRepo.getAll();
      _allUsers = await UserRepository().getAll();

      // חיפוש כל היחידות של המשתמש
      _allMatches = await _findAllUnits();

      // בדיקת session — pre-select יחידה מה-session
      final session = await SessionService().getSavedSession();
      _currentHat = session;
      _UnitMatch? sessionMatch;
      if (session != null && session.unitId.isNotEmpty) {
        for (final match in _allMatches) {
          if (match.unit.id == session.unitId) {
            sessionMatch = match;
            break;
          }
        }
      }

      if (_allMatches.isEmpty) {
        _adminUnit = null;
        _adminTree = null;
        _adminLevel = null;
      } else if (sessionMatch != null) {
        // session match — בחירה מ-session
        _adminUnit = sessionMatch.unit;
        _adminTree = sessionMatch.tree;
        _adminLevel = sessionMatch.unit.level;
      } else if (_allMatches.length == 1) {
        // התאמה יחידה — בחירה אוטומטית
        _adminUnit = _allMatches.first.unit;
        _adminTree = _allMatches.first.tree;
        _adminLevel = _allMatches.first.unit.level;
      } else {
        // מספר התאמות — הצגת דיאלוג בחירה
        if (mounted) {
          final selected = await _showUnitSelectionDialog(_allMatches);
          if (selected != null) {
            _adminUnit = selected.unit;
            _adminTree = selected.tree;
            _adminLevel = selected.unit.level;
          } else {
            // ברירת מחדל — בחירת הראשונה
            _adminUnit = _allMatches.first.unit;
            _adminTree = _allMatches.first.tree;
            _adminLevel = _allMatches.first.unit.level;
          }
        }
      }

      // Fallback: אם ליחידה אין level, מנסים לגזור מ-type
      if (_adminUnit != null && _adminLevel == null) {
        _adminLevel = FrameworkLevel.fromUnitType(_adminUnit!.type);
        if (_adminLevel != null) {
          // עדכון היחידה עם הרמה שנגזרה
          final unitRepo = UnitRepository();
          final updatedUnit = _adminUnit!.copyWith(
            level: _adminLevel,
            updatedAt: DateTime.now(),
          );
          await unitRepo.update(updatedUnit);
          _adminUnit = updatedUnit;
          // עדכון ברשימת היחידות המקומית
          final idx = _allUnits.indexWhere((u) => u.id == updatedUnit.id);
          if (idx >= 0) _allUnits[idx] = updatedUnit;
          print('DEBUG FRAMEWORKS: Derived level $_adminLevel from type "${_adminUnit!.type}" for unit "${_adminUnit!.name}"');
        }
      }

      // If we have a unit but no tree, try to find one
      if (_adminUnit != null && _adminTree == null) {
        final treesForUnit = await _treeRepository.getByUnitId(_adminUnit!.id);
        if (treesForUnit.isNotEmpty) {
          _adminTree = treesForUnit.first;
        }
      }

      // טעינת שם יחידה
      _unitId = _adminUnit?.id ?? session?.unitId ?? '';
      _unitName = _adminUnit?.name ?? '';

      // טעינת משתמשים לתתי-מסגרות
      _loadSubFrameworkUsers();

      // DEBUG
      print('DEBUG FRAMEWORKS: user=${_currentUser!.uid}, '
          'matches=${_allMatches.length}, '
          'selected=${_adminUnit?.name}, '
          'level=$_adminLevel, '
          'type=${_adminUnit?.type}, '
          'hasTree=${_adminTree != null}');

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'שגיאה בטעינת נתונים: $e';
        _isLoading = false;
      });
    }
  }

  /// מוצא את כל היחידות שהמשתמש מנהל או חבר בהן
  Future<List<_UnitMatch>> _findAllUnits() async {
    if (_currentUser == null) return [];

    final matches = <_UnitMatch>[];

    for (final unit in _allUnits) {
      // דילוג על יחידות כלליות/מנווטים ללא רמה
      // אלא אם המשתמש הוא מנהל שלהן
      if (unit.level == null &&
          (unit.isGeneral || unit.isNavigators) &&
          !unit.managerIds.contains(_currentUser!.uid)) {
        continue;
      }

      // בדיקה אם כבר נמצא בהתאמות
      if (matches.any((m) => m.unit.id == unit.id)) continue;

      // חיפוש עץ משויך ליחידה
      NavigationTree? unitTree;
      for (final tree in _allTrees) {
        if (tree.unitId == unit.id) {
          unitTree = tree;
          break;
        }
      }

      // בדיקה אם המשתמש הוא מנהל של היחידה
      if (unit.managerIds.contains(_currentUser!.uid)) {
        matches.add(_UnitMatch(
          unit: unit,
          tree: unitTree,
          roleDescription: 'מנהל מערכת',
        ));
        continue;
      }

      // בדיקה אם המשתמש נמצא ב-userIds של אחת מתתי-המסגרות בעץ
      if (unitTree != null) {
        for (final sf in unitTree.subFrameworks) {
          if (sf.userIds.contains(_currentUser!.uid)) {
            matches.add(_UnitMatch(
              unit: unit,
              tree: unitTree,
              roleDescription: 'משתמש',
            ));
            break;
          }
        }
      }
    }

    return matches;
  }

  /// דיאלוג בחירת יחידה כאשר יש יותר מהתאמה אחת
  Future<_UnitMatch?> _showUnitSelectionDialog(
      List<_UnitMatch> matches) async {
    return showDialog<_UnitMatch>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('בחירת יחידה'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: matches.length,
              itemBuilder: (context, index) {
                final match = matches[index];
                final levelName = match.unit.level != null
                    ? FrameworkLevel.getName(match.unit.level!)
                    : '';
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: match.roleDescription == 'מנהל מערכת'
                          ? Colors.teal[100]
                          : Colors.blue[100],
                      child: Icon(
                        match.roleDescription == 'מנהל מערכת'
                            ? Icons.admin_panel_settings
                            : Icons.person,
                        color: match.roleDescription == 'מנהל מערכת'
                            ? Colors.teal[700]
                            : Colors.blue[700],
                      ),
                    ),
                    title: Text(
                      match.unit.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (levelName.isNotEmpty)
                          Text(levelName,
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[600])),
                        Text(
                          match.roleDescription,
                          style: TextStyle(
                            fontSize: 12,
                            color: match.roleDescription == 'מנהל מערכת'
                                ? Colors.teal[700]
                                : Colors.blue[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    onTap: () => Navigator.pop(context, match),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// מחזיר את כל היחידות-בנות של יחידת המנהל
  List<app_unit.Unit> _getChildUnits() {
    if (_adminUnit == null) return [];

    return _allUnits.where((u) {
      return u.parentUnitId == _adminUnit!.id;
    }).toList();
  }

  /// מחזיר יחידות בנות של יחידה מסוימת
  List<app_unit.Unit> _getChildUnitsOf(String parentId) {
    return _allUnits.where((u) {
      return u.parentUnitId == parentId;
    }).toList();
  }

  /// שמירת העץ המעודכן
  Future<void> _saveTree(NavigationTree updatedTree) async {
    setState(() => _isLoading = true);
    try {
      await _treeRepository.update(updatedTree);
      // עדכון העץ המתאים — העץ של המנהל או עץ של יחידת משנה
      if (_adminTree?.id == updatedTree.id) {
        _adminTree = updatedTree;
      }
      final idx = _allTrees.indexWhere((t) => t.id == updatedTree.id);
      if (idx >= 0) {
        _allTrees[idx] = updatedTree;
      }

      setState(() => _isLoading = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('השינויים נשמרו בהצלחה'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בשמירה: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// איפוס יחידות משנה — מוחק רק את היחידות שתחת היחידה של המשתמש
  Future<void> _resetAllFrameworks() async {
    if (_adminUnit == null) {
      // אם אין יחידה משויכת — אין מה לאפס
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('אין יחידות משנה לאיפוס'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    // איסוף כל יחידות המשנה תחת היחידה של המשתמש
    final idsToRemove = <String>{};
    _collectChildIds(_adminUnit!.id, idsToRemove);

    if (idsToRemove.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('אין יחידות משנה לאיפוס'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('איפוס יחידות משנה'),
        content: Text(
            'האם למחוק ${idsToRemove.length} יחידות משנה תחת "${_adminUnit!.name}"?\n'
            'פעולה זו בלתי הפיכה.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('מחק'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      // מחיקת יחידות משנה
      final unitRepo = UnitRepository();
      for (final id in idsToRemove) {
        await unitRepo.delete(id);
      }

      // גם מחיקת עצים משויכים ליחידות שנמחקו
      for (final id in idsToRemove) {
        final trees = await _treeRepository.getByUnitId(id);
        for (final tree in trees) {
          await _treeRepository.delete(tree.id);
        }
      }

      await _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${idsToRemove.length} יחידות משנה נמחקו'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// יצירת יחידת משנה חדשה
  Future<void> _addChildFramework({String? parentId}) async {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();

    // בחירת מנהל מערכת ליחידה — ברירת מחדל: המשתמש הנוכחי
    app_user.User? selectedAdmin = _currentUser;
    String selectedAdminName = _currentUser?.fullName ?? '';

    // חישוב הרמה הבאה מתחת להורה — תמיד רמה אחת למטה (שמירה על היררכיה)
    final effectiveParentId = parentId ?? _adminUnit!.id;
    int? parentLevel;

    if (parentId != null && parentId != _adminUnit!.id) {
      final parentMatches = _allUnits
          .where((u) => u.id == parentId)
          .toList();
      final parentUnit = parentMatches.isNotEmpty ? parentMatches.first : null;
      parentLevel = parentUnit?.level;
    } else {
      parentLevel = _adminLevel;
    }

    if (parentLevel == null) return;

    final targetLevel = FrameworkLevel.getNextLevelBelow(parentLevel);
    if (targetLevel == null) return; // אין רמה זמינה
    final levelName = FrameworkLevel.getName(targetLevel);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('יחידה חדשה — $levelName'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // רמה (קבועה — תמיד הרמה הבאה מתחת להורה)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.layers, size: 18, color: Colors.blue[700]),
                        const SizedBox(width: 8),
                        Text(
                          'רמה: $levelName',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // שם היחידה
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'שם היחידה',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.label),
                    ),
                    autofocus: true,
                  ),
                  const SizedBox(height: 12),

                  // תיאור
                  TextField(
                    controller: descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'תיאור (אופציונלי)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.description),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),

                  // בחירת מנהל מערכת
                  const Text(
                    'מנהל מערכת:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () async {
                      final userRepo = UserRepository();
                      final allUsers = await userRepo.getAll();
                      if (!context.mounted) return;
                      final picked = await showDialog<app_user.User>(
                        context: context,
                        builder: (ctx) =>
                            _AdminSelectionDialog(users: allUsers),
                      );
                      if (picked != null) {
                        setDialogState(() {
                          selectedAdmin = picked;
                          selectedAdminName = picked.fullName;
                        });
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person),
                        suffixIcon: Icon(Icons.arrow_drop_down),
                      ),
                      child: Text(
                        selectedAdminName.isNotEmpty
                            ? selectedAdminName
                            : 'בחר מנהל מערכת',
                        style: TextStyle(
                          color: selectedAdminName.isNotEmpty
                              ? null
                              : Colors.grey[600],
                        ),
                      ),
                    ),
                  ),

                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('ביטול'),
              ),
              ElevatedButton(
                onPressed: nameController.text.isNotEmpty
                    ? () => Navigator.pop(context, true)
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                child: const Text('צור יחידה'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true || nameController.text.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final adminUid = selectedAdmin?.uid ?? _currentUser!.uid;
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final unitName = nameController.text;

      // המרת רמה לסוג יחידה
      String unitType;
      switch (targetLevel) {
        case FrameworkLevel.brigade:
          unitType = 'brigade';
          break;
        case FrameworkLevel.battalion:
          unitType = 'battalion';
          break;
        case FrameworkLevel.company:
          unitType = 'company';
          break;
        case FrameworkLevel.platoon:
          unitType = 'platoon';
          break;
        default:
          unitType = 'company';
      }

      // יצירת יחידה חדשה
      final now = DateTime.now();
      final newUnit = app_unit.Unit(
        id: timestamp,
        name: unitName,
        description: descriptionController.text,
        type: unitType,
        parentUnitId: effectiveParentId,
        managerIds: [adminUid],
        createdBy: _currentUser!.uid,
        createdAt: now,
        updatedAt: now,
        level: targetLevel,
      );

      final unitRepo = UnitRepository();
      await unitRepo.create(newUnit);

      // יצירת תתי-מסגרות אוטומטיות — תמיד שתי תתי-מסגרות
      final treeId = 'tree_$timestamp';
      final initialSubFrameworks = <SubFramework>[
        SubFramework(
          id: '${treeId}_cmd_mgmt',
          name: 'מפקדים ומנהלת - $unitName',
          userIds: const [],
          isFixed: true,
          unitId: timestamp,
        ),
        SubFramework(
          id: '${treeId}_soldiers',
          name: 'חיילים - $unitName',
          userIds: const [],
          isFixed: true,
          unitId: timestamp,
        ),
      ];

      // יצירת עץ ניווט ליחידה החדשה
      final tree = NavigationTree(
        id: 'tree_$timestamp',
        name: 'עץ מבנה - $unitName',
        subFrameworks: initialSubFrameworks,
        createdBy: _currentUser!.uid,
        createdAt: now,
        updatedAt: now,
        unitId: timestamp,
      );

      await _treeRepository.create(tree);

      await _loadData();
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה ביצירת יחידה: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// עריכת יחידה
  Future<void> _editUnit(app_unit.Unit unit) async {
    final nameController = TextEditingController(text: unit.name);
    final descriptionController =
        TextEditingController(text: unit.description);
    final admins = List<String>.from(unit.managerIds);

    // טעינת רשימת כל המשתמשים לבחירת מנהלים
    final userRepo = UserRepository();
    final allUsers = await userRepo.getAll();

    String getAdminName(String uid) {
      final matches = allUsers.where((u) => u.uid == uid);
      return matches.isNotEmpty ? matches.first.fullName : uid;
    }

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('עריכת יחידה - ${unit.name}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'שם היחידה',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.label),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'תיאור (אופציונלי)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.description),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  // ניהול מנהלי מערכת
                  const Text(
                    'מנהלי מערכת:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ...admins.map((adminId) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Icon(Icons.admin_panel_settings,
                              size: 18, color: Colors.orange[700]),
                          const SizedBox(width: 8),
                          Expanded(child: Text(getAdminName(adminId))),
                          if (admins.length > 1)
                            IconButton(
                              icon: const Icon(Icons.remove_circle,
                                  size: 20, color: Colors.red),
                              onPressed: () {
                                setDialogState(() => admins.remove(adminId));
                              },
                            ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 4),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDialog<app_user.User>(
                        context: context,
                        builder: (ctx) =>
                            _AdminSelectionDialog(users: allUsers, filterUnitId: unit.id),
                      );
                      if (picked != null && !admins.contains(picked.uid)) {
                        setDialogState(() => admins.add(picked.uid));
                      }
                    },
                    icon: const Icon(Icons.person_add, size: 18),
                    label: const Text('הוסף מנהל'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('ביטול'),
              ),
              ElevatedButton(
                onPressed: admins.isNotEmpty ? () => Navigator.pop(context, true) : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
                child: const Text('שמור'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true || nameController.text.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final updatedUnit = unit.copyWith(
        name: nameController.text,
        description: descriptionController.text,
        managerIds: admins,
        updatedAt: DateTime.now(),
      );

      final unitRepo = UnitRepository();
      await unitRepo.update(updatedUnit);

      await _loadData();
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בשמירה: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// מחיקת יחידה
  Future<void> _deleteUnit(app_unit.Unit unit) async {
    // בדיקה אם יש יחידות-בנות
    final children = _getChildUnitsOf(unit.id);
    final hasChildren = children.isNotEmpty;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('מחיקת יחידה'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('האם למחוק את היחידה "${unit.name}"?'),
            if (hasChildren) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning, size: 16, color: Colors.orange[700]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'ליחידה זו ${children.length} יחידות משנה שיימחקו גם הן.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange[900],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('מחק'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // מחיקת היחידה וכל יחידות-הבנות שלה (רקורסיבית)
    final idsToRemove = <String>{unit.id};
    _collectChildIds(unit.id, idsToRemove);

    setState(() => _isLoading = true);
    try {
      // Cascade: מחיקת עצי ניווט וניווטים המשויכים ליחידות שנמחקות
      final treeRepo = NavigationTreeRepository();
      final navRepo = NavigationRepository();
      for (final unitId in idsToRemove) {
        final trees = await treeRepo.getByUnitId(unitId);
        for (final tree in trees) {
          final navigations = await navRepo.getByTreeId(tree.id);
          for (final nav in navigations) {
            await navRepo.delete(nav.id);
          }
          await treeRepo.delete(tree.id);
        }
      }

      // מחיקת היחידות עצמן
      final unitRepo = UnitRepository();
      for (final id in idsToRemove) {
        await unitRepo.delete(id);
      }

      await _loadData();
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה במחיקה: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// אוסף את כל ה-IDs של יחידות-בנות רקורסיבית
  void _collectChildIds(String parentId, Set<String> ids) {
    for (final u in _allUnits) {
      if (u.parentUnitId == parentId) {
        ids.add(u.id);
        _collectChildIds(u.id, ids);
      }
    }
  }

  /// בניית נתיב היררכי ליחידה
  String _buildHierarchyPath(app_unit.Unit unit) {
    final path = <String>[unit.name];
    String? parentId = unit.parentUnitId;
    while (parentId != null) {
      final parent = _allUnits
          .where((u) => u.id == parentId)
          .firstOrNull;
      if (parent == null) break;
      path.add(parent.name);
      parentId = parent.parentUnitId;
    }
    return path.reversed.join(' > ');
  }

  /// יצירת עץ ניווט ראשון ליחידה ללא עץ
  Future<void> _createFirstFramework() async {
    if (_currentUser == null) return;

    // טעינת היחידה
    final unitRepo = UnitRepository();
    app_unit.Unit? unit;
    if (_unitId.isNotEmpty) {
      unit = await unitRepo.getById(_unitId);
    }
    if (unit == null) {
      final session = await SessionService().getSavedSession();
      final fallbackId = session?.unitId ?? '';
      if (fallbackId.isNotEmpty) {
        unit = await unitRepo.getById(fallbackId);
      }
    }
    if (unit == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('לא נמצאה יחידה משויכת'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // חישוב רמה מסוג היחידה
    final rootLevel = FrameworkLevel.fromUnitType(unit.type);
    if (rootLevel == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('לא ניתן לקבוע רמה עבור סוג יחידה "${unit.type}"'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final nameController = TextEditingController(text: unit.name);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('יצירת עץ מבנה ראשון'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.layers, size: 18, color: Colors.blue[700]),
                    const SizedBox(width: 8),
                    Text(
                      'רמה: ${FrameworkLevel.getName(rootLevel)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[700],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'שם העץ',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.label),
                ),
                autofocus: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ביטול'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('צור עץ מבנה'),
          ),
        ],
      ),
    );

    if (confirmed != true || nameController.text.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final treeRepo = NavigationTreeRepository();
      final treeId = 'tree_${unit.id}';
      final now = DateTime.now();

      // עדכון רמת היחידה אם חסרה
      if (unit.level == null) {
        final updatedUnit = unit.copyWith(level: rootLevel, updatedAt: now);
        await unitRepo.update(updatedUnit);
      }

      // יצירת תתי-מסגרות קבועות אוטומטיות — תמיד שתי תתי-מסגרות
      final initialSubFrameworks = <SubFramework>[
        SubFramework(
          id: '${unit.id}_cmd_mgmt',
          name: 'מפקדים ומנהלת - ${nameController.text}',
          userIds: const [],
          isFixed: true,
          unitId: unit.id,
        ),
        SubFramework(
          id: '${unit.id}_soldiers',
          name: 'חיילים - ${nameController.text}',
          userIds: const [],
          isFixed: true,
          unitId: unit.id,
        ),
      ];

      final tree = NavigationTree(
        id: treeId,
        name: nameController.text,
        subFrameworks: initialSubFrameworks,
        createdBy: _currentUser!.uid,
        createdAt: now,
        updatedAt: now,
        unitId: unit.id,
      );

      await treeRepo.create(tree);
      print('DEBUG: Created tree for unit "${unit.name}"');

      await _loadData();
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה ביצירת עץ: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// ייצוא יחידה ותתי-מסגרות לאקסל
  Future<void> _exportToExcel(app_unit.Unit unit) async {
    try {
      // מציאת העץ של היחידה
      NavigationTree? unitTree;
      for (final tree in _allTrees) {
        if (tree.unitId == unit.id) {
          unitTree = tree;
          break;
        }
      }

      final subFrameworks = unitTree?.subFrameworks ?? [];
      final filePath = await FrameworkExcelService.exportUnit(
        unit: unit,
        subFrameworks: subFrameworks,
        allUsers: _allUsers,
      );

      if (filePath == null) return; // User cancelled

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('קובץ נשמר: $filePath'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'סגור',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בייצוא: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// ייבוא תתי-מסגרות מאקסל
  Future<void> _importFromExcel(app_unit.Unit unit, NavigationTree tree) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );
      if (result == null || result.files.single.path == null) return;

      setState(() => _isLoading = true);
      final filePath = result.files.single.path!;
      final imported = await FrameworkExcelService.importSubFrameworks(filePath);

      if (imported.isEmpty) {
        setState(() => _isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('הקובץ ריק או בפורמט לא תקין'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // מיזוג תתי-מסגרות מיובאות עם העץ הנוכחי
      var updatedSubs = List<SubFramework>.from(tree.subFrameworks);

      for (final entry in imported.entries) {
        final importedSubs = entry.value;

        for (final importedSub in importedSubs) {
          final existingIndex =
              updatedSubs.indexWhere((s) => s.name == importedSub.name);
          if (existingIndex >= 0) {
            updatedSubs[existingIndex] =
                updatedSubs[existingIndex].copyWith(userIds: importedSub.userIds);
          } else {
            updatedSubs.add(importedSub);
          }
        }
      }

      final updatedTree = tree.copyWith(
        subFrameworks: updatedSubs,
        updatedAt: DateTime.now(),
      );
      await _saveTree(updatedTree);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ייבוא הושלם בהצלחה'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בייבוא: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// ספירת משתמשים לתת-מסגרת לפי תפקיד
  int _countUsersForSubFramework(SubFramework subFramework, String unitId) {
    final isCommandersSf = subFramework.name.contains('מפקדים');
    if (isCommandersSf) {
      // ספירת מפקדים ומנהלים מאושרים ביחידה
      return _allUsers.where((u) =>
          ['commander', 'unit_admin', 'admin', 'developer'].contains(u.role) &&
          u.unitId == unitId &&
          u.isApproved).length;
    } else {
      // ספירת חיילים (navigators) מאושרים ביחידה
      return _allUsers.where((u) =>
          u.role == 'navigator' &&
          u.unitId == unitId &&
          u.isApproved).length;
    }
  }

  /// הסרת משתמש מהיחידה
  Future<void> _removeUserFromUnit(app_user.User user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('הסרת משתמש'),
        content: Text('להסיר את ${user.fullName} מהיחידה?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('הסר'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await UserRepository().removeUserFromUnit(user.uid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${user.fullName} הוסר מהיחידה'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בהסרה: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// טעינת משתמשים לכל תת-מסגרת — מפקדים/חיילים לפי תפקיד ויחידה
  void _loadSubFrameworkUsers() {
    final map = <String, List<app_user.User>>{};
    for (final tree in _allTrees) {
      for (final sf in tree.subFrameworks) {
        final unitId = sf.unitId ?? tree.unitId ?? '';
        if (unitId.isEmpty) continue;
        final isCommandersSf = sf.name.contains('מפקדים');
        if (isCommandersSf) {
          map[sf.id] = _allUsers.where((u) =>
              ['commander', 'unit_admin', 'admin', 'developer'].contains(u.role) &&
              u.unitId == unitId &&
              u.isApproved).toList();
        } else {
          map[sf.id] = _allUsers.where((u) =>
              u.role == 'navigator' &&
              u.unitId == unitId &&
              u.isApproved).toList();
        }
        print('DEBUG SF_USERS: sf="${sf.name}" id="${sf.id}" unitId="$unitId" '
            'users=${map[sf.id]?.length ?? 0}');
      }
    }
    // DEBUG: כל המשתמשים עם isApproved
    final approvedUsers = _allUsers.where((u) => u.isApproved).toList();
    print('DEBUG SF_USERS: total approved=${approvedUsers.length}');
    for (final u in approvedUsers) {
      print('DEBUG SF_USERS: approved user="${u.fullName}" uid=${u.uid} '
          'role=${u.role} unitId=${u.unitId}');
    }
    _subFrameworkUsersMap = map;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_unitName.isNotEmpty
              ? 'ניהול מסגרות - $_unitName'
              : 'ניהול מסגרות'),
          backgroundColor: Theme.of(context).primaryColor,
          foregroundColor: Colors.white,
          actions: [
            // כפתור החלפת יחידה
            IconButton(
              icon: const Icon(Icons.swap_horiz),
              onPressed: () async {
                final matches = await _findAllUnits();
                if (!mounted) return;
                if (matches.length > 1) {
                  final selected = await _showUnitSelectionDialog(matches);
                  if (selected != null && mounted) {
                    setState(() {
                      _adminUnit = selected.unit;
                      _adminTree = selected.tree;
                      _adminLevel = selected.unit.level;
                    });
                  }
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('אין יחידות נוספות'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                }
              },
              tooltip: 'החלף יחידה',
            ),
            // כפתור לאיפוס יחידות — למנהלים בלבד
            if (_currentHat?.type == HatType.admin)
              IconButton(
                icon: const Icon(Icons.delete_sweep),
                onPressed: _resetAllFrameworks,
                tooltip: 'איפוס יחידות',
              ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadData,
              tooltip: 'רענן',
            ),
          ],
        ),
        body: _buildBody(),
        floatingActionButton: _currentHat?.type == HatType.admin &&
                _adminUnit != null &&
                _adminLevel != null &&
                FrameworkLevel.getNextLevelBelow(_adminLevel!) != null
            ? FloatingActionButton.extended(
                onPressed: () => _addChildFramework(),
                icon: const Icon(Icons.add),
                label: Text('יצירת ${FrameworkLevel.getName(FrameworkLevel.getNextLevelBelow(_adminLevel!)!)}'),
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              )
            : null,
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: TextStyle(fontSize: 16, color: Colors.red[700]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('נסה שוב'),
            ),
          ],
        ),
      );
    }

    if (_adminUnit == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.create_new_folder, size: 64, color: Colors.teal[300]),
              const SizedBox(height: 16),
              if (_unitName.isNotEmpty) ...[
                Text(
                  _unitName,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.teal[700],
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Text(
                'אין מסגרת עדיין',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'צור את המסגרת הראשונה ליחידה שלך',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _createFirstFramework,
                icon: const Icon(Icons.add),
                label: const Text('הוסף מסגרת ראשונה'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final childUnits = _getChildUnits();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // כרטיס יחידת המנהל
        _buildAdminUnitCard(),

        const SizedBox(height: 16),

        // הסבר
        Card(
          color: Colors.blue[50],
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue[700]),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _adminLevel != null &&
                            FrameworkLevel.getNextLevelBelow(_adminLevel!) !=
                                null
                        ? 'ניתן ליצור יחידות בכל רמה מ${FrameworkLevel.getName(FrameworkLevel.getLevelsBelow(_adminLevel!).first)} '
                            'עד ${FrameworkLevel.getName(FrameworkLevel.getLevelsBelow(_adminLevel!).last)}. '
                            'כל יחידה נוצרת ברמה שמתחת להורה שלה.'
                        : 'ניתן ליצור יחידות משנה תחת היחידה שלך.',
                    style: TextStyle(fontSize: 12, color: Colors.blue[900]),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // כותרת יחידות משנה
        Row(
          children: [
            const Text(
              'יחידות משנה',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            Chip(
              label: Text('${childUnits.length} יחידות'),
              backgroundColor: Colors.blue[100],
            ),
          ],
        ),

        const SizedBox(height: 12),

        // רשימת יחידות משנה
        if (childUnits.isEmpty &&
            _adminLevel != null &&
            FrameworkLevel.getNextLevelBelow(_adminLevel!) != null)
          Card(
            color: Colors.grey[50],
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(Icons.create_new_folder,
                      size: 48, color: Colors.grey[400]),
                  const SizedBox(height: 12),
                  Text(
                    'אין יחידות משנה עדיין',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'לחץ על הכפתור הירוק למטה ליצירת ${FrameworkLevel.getName(FrameworkLevel.getNextLevelBelow(_adminLevel!)!)}',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ),
          )
        else if (childUnits.isNotEmpty)
          ...childUnits.map((unit) {
            final grandChildren = _getChildUnitsOf(unit.id);
            return _buildUnitCard(unit, grandChildren);
          }),
      ],
    );
  }

  /// כרטיס יחידת המנהל (לקריאה בלבד)
  Widget _buildAdminUnitCard() {
    final treeSubFrameworks = _adminTree?.subFrameworks ?? [];

    return Card(
      elevation: 3,
      color: Colors.teal[50],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.teal[200]!, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.teal[100],
                  child: Icon(Icons.military_tech, color: Colors.teal[700]),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'היחידה שלך',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.teal[700],
                        ),
                      ),
                      Text(
                        _adminUnit!.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_adminLevel != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.teal[100],
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      FrameworkLevel.getName(_adminLevel!),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.teal[800],
                      ),
                    ),
                  ),
              ],
            ),
            if (_adminUnit!.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                _adminUnit!.description,
                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.account_tree,
                    size: 14, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  '${_getChildUnits().length} יחידות משנה',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                // תתי-מסגרות רק ברמת פלוגה (4) ומטה
                if (_adminLevel != null && _adminLevel! >= FrameworkLevel.company) ...[
                  const SizedBox(width: 16),
                  Icon(Icons.subdirectory_arrow_right,
                      size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    '${treeSubFrameworks.length} תתי-מסגרות',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ],
            ),
            // תתי-מסגרות של העץ — ניהול משתמשים
            if (_adminLevel != null &&
                _adminLevel! >= FrameworkLevel.company &&
                treeSubFrameworks.isNotEmpty) ...[
              const Divider(height: 20),
              const Text(
                'תתי-מסגרות:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              ...treeSubFrameworks.map((sub) {
                return _buildSubFrameworkItem(sub, _adminTree!);
              }),
            ],
          ],
        ),
      ),
    );
  }

  /// כרטיס יחידת משנה (ניתן לעריכה/מחיקה)
  Widget _buildUnitCard(
      app_unit.Unit unit, List<app_unit.Unit> grandChildren) {
    final levelName =
        unit.level != null ? FrameworkLevel.getName(unit.level!) : '';

    // מציאת העץ של היחידה
    NavigationTree? unitTree;
    for (final tree in _allTrees) {
      if (tree.unitId == unit.id) {
        unitTree = tree;
        break;
      }
    }
    final unitSubFrameworks = unitTree?.subFrameworks ?? [];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: unit.isNavigators
              ? Colors.green[100]
              : unit.isGeneral
                  ? Colors.purple[100]
                  : Colors.blue[100],
          child: Icon(
            unit.isNavigators
                ? Icons.navigation
                : unit.isGeneral
                    ? Icons.admin_panel_settings
                    : Icons.folder,
            color: unit.isNavigators
                ? Colors.green[700]
                : unit.isGeneral
                    ? Colors.purple[700]
                    : Colors.blue[700],
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                unit.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            if (levelName.isNotEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  levelName,
                  style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _buildHierarchyPath(unit),
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
            if (unit.description.isNotEmpty)
              Text(
                unit.description,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            const SizedBox(height: 4),
            Row(
              children: [
                // תתי-מסגרות רק ברמת פלוגה (4) ומטה
                if (unit.level != null && unit.level! >= FrameworkLevel.company) ...[
                  Icon(Icons.subdirectory_arrow_right,
                      size: 14, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Text(
                    '${unitSubFrameworks.length} תתי-מסגרות',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ],
                if (grandChildren.isNotEmpty) ...[
                  if (unit.level != null && unit.level! >= FrameworkLevel.company)
                    const SizedBox(width: 12),
                  Icon(Icons.account_tree,
                      size: 14, color: Colors.indigo[700]),
                  const SizedBox(width: 4),
                  Text(
                    '${grandChildren.length} יחידות משנה',
                    style: TextStyle(
                        fontSize: 11, color: Colors.indigo[700]),
                  ),
                ],
              ],
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // תתי-מסגרות (SubFrameworks) — רק ברמת פלוגה (4) ומטה
                if (unit.level != null && unit.level! >= FrameworkLevel.company) ...[
                  const Text(
                    'תתי-מסגרות:',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),

                  if (unitSubFrameworks.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text('אין תתי-מסגרות',
                          style: TextStyle(color: Colors.grey[500])),
                    )
                  else if (unitTree != null)
                    ...unitSubFrameworks.map((sub) {
                      return _buildSubFrameworkItem(sub, unitTree!);
                    }),
                ],


                // יחידות משנה (grand-children)
                if (grandChildren.isNotEmpty) ...[
                  const Divider(height: 24),
                  const Text(
                    'יחידות משנה:',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  ...grandChildren.map((child) {
                    final deepChildren = _getChildUnitsOf(child.id);
                    return Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: _buildUnitCard(child, deepChildren),
                    );
                  }),
                ],

                // כפתור הוספת יחידת משנה (למנהלים בלבד)
                if (_currentHat?.type == HatType.admin &&
                    unit.level != null &&
                    FrameworkLevel.getNextLevelBelow(unit.level!) != null) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _addChildFramework(
                      parentId: unit.id,
                    ),
                    icon: const Icon(Icons.create_new_folder, size: 18),
                    label: Text('יצירת ${FrameworkLevel.getName(FrameworkLevel.getNextLevelBelow(unit.level!)!)}'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.indigo,
                    ),
                  ),
                ],

                // כפתורי ייצוא/ייבוא — רמת פלוגה ומטה
                if (unit.level != null &&
                    unit.level! >= FrameworkLevel.company) ...[
                  const Divider(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _exportToExcel(unit),
                          icon: const Icon(Icons.file_download, size: 18),
                          label: const Text('ייצוא לאקסל'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.green[700],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: unitTree != null ? () => _importFromExcel(unit, unitTree!) : null,
                          icon: const Icon(Icons.file_upload, size: 18),
                          label: const Text('ייבוא מאקסל'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.blue[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],

                // כפתורי פעולה — למנהלים בלבד
                if (_currentHat?.type == HatType.admin) ...[
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: () => _editUnit(unit),
                        icon: const Icon(Icons.edit, size: 18),
                        label: const Text('ערוך'),
                        style: TextButton.styleFrom(
                            foregroundColor: Colors.blue),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: () => _deleteUnit(unit),
                        icon: const Icon(Icons.delete, size: 18),
                        label: const Text('מחק'),
                        style: TextButton.styleFrom(
                            foregroundColor: Colors.red),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubFrameworkItem(SubFramework subFramework, NavigationTree tree) {
    // ספירת משתמשים דינמית לפי תפקיד — מבוסס על unitId של העץ
    final unitId = tree.unitId ?? '';
    final userCount = _countUsersForSubFramework(subFramework, unitId);
    final isCommandersSf = subFramework.name.contains('מפקדים');
    final users = _subFrameworkUsersMap[subFramework.id] ?? [];

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: Colors.grey[50],
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: isCommandersSf
              ? Colors.orange.withValues(alpha: 0.1)
              : Colors.blue.withValues(alpha: 0.1),
          radius: 16,
          child: Text(
            '$userCount',
            style: TextStyle(
              color: isCommandersSf ? Colors.orange[700] : Colors.blue[700],
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Row(
          children: [
            Expanded(child: Text(subFramework.name)),
            if (subFramework.isFixed)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(Icons.lock, size: 14, color: Colors.grey[500]),
              ),
          ],
        ),
        subtitle: Text(
          isCommandersSf
              ? '$userCount מפקדים מאושרים'
              : '$userCount חיילים מאושרים',
          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
        ),
        children: [
          if (users.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'אין משתמשים מאושרים',
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
            )
          else
            ...users.map((user) {
              String roleBadge;
              Color badgeColor;
              switch (user.role) {
                case 'admin':
                  roleBadge = 'מנהל';
                  badgeColor = Colors.red;
                  break;
                case 'unit_admin':
                  roleBadge = 'מנהל יחידה';
                  badgeColor = Colors.orange;
                  break;
                case 'commander':
                  roleBadge = 'מפקד';
                  badgeColor = Colors.purple;
                  break;
                case 'developer':
                  roleBadge = 'מפתח';
                  badgeColor = Colors.teal;
                  break;
                default:
                  roleBadge = 'מנווט';
                  badgeColor = Colors.blue;
              }
              return ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor: badgeColor.withValues(alpha: 0.1),
                  child: Text(
                    user.fullName.isNotEmpty ? user.fullName[0] : '?',
                    style: TextStyle(
                      fontSize: 12,
                      color: badgeColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                title: Text(
                  user.fullName,
                  style: const TextStyle(fontSize: 13),
                ),
                subtitle: Row(
                  children: [
                    Text(
                      user.personalNumber,
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        roleBadge,
                        style: TextStyle(
                          fontSize: 10,
                          color: badgeColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.remove_circle_outline,
                      size: 20, color: Colors.red),
                  onPressed: () => _removeUserFromUnit(user),
                  tooltip: 'הסר מהיחידה',
                ),
              );
            }),
        ],
      ),
    );
  }


}

/// דיאלוג בחירת מנהל מערכת למסגרת חדשה
/// מסנן רק משתמשים עם תפקיד מנהלי (commander/unit_admin/admin/developer)
/// שמאושרים (isApproved) ואינם מנהלים יחידה אחרת
class _AdminSelectionDialog extends StatefulWidget {
  final List<app_user.User> users;
  final String? filterUnitId;

  const _AdminSelectionDialog({required this.users, this.filterUnitId});

  @override
  State<_AdminSelectionDialog> createState() => _AdminSelectionDialogState();
}

class _AdminSelectionDialogState extends State<_AdminSelectionDialog> {
  final TextEditingController _searchController = TextEditingController();
  final UnitRepository _unitRepository = UnitRepository();
  List<app_user.User> _eligibleUsers = [];
  List<app_user.User> _filteredUsers = [];
  Map<String, bool> _managingStatus = {};
  bool _isLoading = true;

  static const _adminRoles = ['commander', 'unit_admin', 'admin', 'developer'];

  @override
  void initState() {
    super.initState();
    _loadEligibleUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadEligibleUsers() async {
    // סינון לפי תפקיד מנהלי + isApproved (+ סינון יחידה אם צוין)
    var roleFiltered = widget.users.where((u) =>
        _adminRoles.contains(u.role) && u.isApproved).toList();
    if (widget.filterUnitId != null) {
      roleFiltered = roleFiltered.where((u) =>
          u.unitId == widget.filterUnitId).toList();
    }

    // בדיקה אם כל משתמש כבר מנהל יחידה
    final statusMap = <String, bool>{};
    for (final user in roleFiltered) {
      statusMap[user.uid] = await _unitRepository.isUserManagingAnyUnit(user.uid);
    }

    if (mounted) {
      setState(() {
        _managingStatus = statusMap;
        _eligibleUsers = roleFiltered;
        _filteredUsers = roleFiltered;
        _isLoading = false;
      });
    }
  }

  void _filterUsers(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredUsers = _eligibleUsers;
      } else {
        _filteredUsers = _eligibleUsers
            .where((u) =>
                u.fullName.contains(query) ||
                u.personalNumber.contains(query))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SimpleDialog(
        title: const Text('בחר מנהל מערכת'),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'חיפוש לפי שם',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              autofocus: true,
              onChanged: _filterUsers,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.maxFinite,
            height: 300,
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredUsers.isEmpty
                    ? const Center(
                        child: Text(
                          'לא נמצאו משתמשים מתאימים',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _filteredUsers.length,
                        itemBuilder: (context, index) {
                          final user = _filteredUsers[index];
                          final isManaging = _managingStatus[user.uid] ?? false;
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isManaging
                                  ? Colors.grey[200]
                                  : Colors.indigo[100],
                              child: Text(
                                user.fullName.isNotEmpty
                                    ? user.fullName[0]
                                    : '?',
                                style: TextStyle(
                                  color: isManaging
                                      ? Colors.grey[500]
                                      : Colors.indigo[700],
                                ),
                              ),
                            ),
                            title: Text(
                              user.fullName,
                              style: TextStyle(
                                color: isManaging ? Colors.grey[500] : null,
                              ),
                            ),
                            subtitle: Text(
                              isManaging
                                  ? '${user.role} | ${user.personalNumber} (מנהל יחידה אחרת)'
                                  : '${user.role} | ${user.personalNumber}',
                              style: TextStyle(
                                fontSize: 12,
                                color: isManaging
                                    ? Colors.orange[700]
                                    : Colors.grey[600],
                              ),
                            ),
                            enabled: !isManaging,
                            onTap: isManaging
                                ? null
                                : () => Navigator.pop(context, user),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
