import 'package:flutter/material.dart';
import '../../../domain/entities/navigation_tree.dart';
import '../../../domain/entities/unit.dart' as domain_unit;
import '../../../domain/entities/user.dart' as app_user;
import '../../../data/repositories/navigation_tree_repository.dart';
import '../../../data/repositories/unit_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../core/constants/app_constants.dart';

/// מסך ניהול מסגרות ומסגרות משנה (למנהל מערכת יחידתי)
class ManageFrameworksScreen extends StatefulWidget {
  final NavigationTree tree;

  const ManageFrameworksScreen({super.key, required this.tree});

  @override
  State<ManageFrameworksScreen> createState() => _ManageFrameworksScreenState();
}

class _ManageFrameworksScreenState extends State<ManageFrameworksScreen> {
  final NavigationTreeRepository _treeRepository = NavigationTreeRepository();
  final UserRepository _userRepository = UserRepository();
  final UnitRepository _unitRepository = UnitRepository();

  late NavigationTree _tree;
  domain_unit.Unit? _unit;
  List<app_user.User> _allUsers = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _tree = widget.tree;
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    try {
      final users = await _userRepository.getAll();
      domain_unit.Unit? unit;
      if (_tree.unitId != null) {
        unit = await _unitRepository.getById(_tree.unitId!);
      }
      if (mounted) {
        setState(() {
          _allUsers = users;
          _unit = unit;
        });
      }
    } catch (e) {
      print('DEBUG: Error loading users: $e');
    }
  }

  Future<void> _refreshTree() async {
    try {
      final updated = await _treeRepository.getById(_tree.id);
      domain_unit.Unit? unit;
      if (_tree.unitId != null) {
        unit = await _unitRepository.getById(_tree.unitId!);
      }
      if (updated != null && mounted) {
        setState(() {
          _tree = updated;
          if (unit != null) _unit = unit;
        });
      }
    } catch (e) {
      print('DEBUG: Error refreshing tree: $e');
    }
  }

  Future<void> _saveTree(NavigationTree updatedTree) async {
    setState(() => _isLoading = true);
    try {
      await _treeRepository.update(updatedTree);
      setState(() {
        _tree = updatedTree;
        _isLoading = false;
      });
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

  /// מחזיר את שם התצוגה של משתמש לפי UID
  String _getUserDisplayName(String userId) {
    // אם מדובר בהזנה ידנית - מחזיר את השם ללא הקידומת
    if (userId.startsWith('manual_')) {
      return userId.substring(7); // מסיר את 'manual_'
    }
    final matches = _allUsers.where((u) => u.uid == userId).toList();
    if (matches.isNotEmpty) {
      return matches.first.fullName;
    }
    return userId;
  }

  /// בודק אם המשתמש הוא מנהל מערכת (admin או unit_admin)
  bool _isAdminRole(app_user.User user) {
    return user.role == AppConstants.roleAdmin ||
        user.role == AppConstants.roleUnitAdmin ||
        user.role == AppConstants.roleDeveloper;
  }

  /// מחזיר שם תצוגה לתפקיד
  String _getRoleDisplayName(String role) {
    switch (role) {
      case AppConstants.roleAdmin:
        return 'מנהל מערכת';
      case AppConstants.roleUnitAdmin:
        return 'מנהל יחידה';
      case AppConstants.roleDeveloper:
        return 'מפתח';
      case AppConstants.roleCommander:
        return 'מפקד';
      case AppConstants.roleNavigator:
        return 'מנווט';
      default:
        return role;
    }
  }

  /// ווידג'ט מתג בין מצב בחירה למצב הזנה ידנית
  Widget _buildEntryModeToggle({
    required bool isManualMode,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(false),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: !isManualMode ? Colors.blue : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.list,
                      size: 16,
                      color: !isManualMode ? Colors.white : Colors.grey[600],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'בחר מרשימה',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color:
                            !isManualMode ? Colors.white : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(true),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isManualMode ? Colors.blue : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.edit,
                      size: 16,
                      color: isManualMode ? Colors.white : Colors.grey[600],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'הזנה ידנית',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color:
                            isManualMode ? Colors.white : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// הוספת יחידת בת (מסגרת משנה)
  Future<void> _addChildUnit() async {
    if (_unit == null || _unit!.level == null) return;

    final nextLevel = FrameworkLevel.getNextLevelBelow(_unit!.level!);
    if (nextLevel == null) return;

    final levelName = FrameworkLevel.getName(nextLevel);
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('$levelName חדש/ה'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: 'שם ה$levelName',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.label),
                    ),
                    autofocus: true,
                    onChanged: (_) => setDialogState(() {}),
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
                child: const Text('צור'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true || nameController.text.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final unitName = nameController.text;

      // המרת רמה לסוג יחידה
      String unitType;
      switch (nextLevel) {
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

      final now = DateTime.now();
      final newUnit = domain_unit.Unit(
        id: timestamp,
        name: unitName,
        description: descriptionController.text,
        type: unitType,
        parentUnitId: _unit!.id,
        managerIds: _unit!.managerIds,
        createdBy: _unit!.managerIds.isNotEmpty ? _unit!.managerIds.first : '',
        createdAt: now,
        updatedAt: now,
        level: nextLevel,
      );

      await _unitRepository.create(newUnit);

      // יצירת תתי-מסגרות אוטומטיות
      final initialSubFrameworks = <SubFramework>[
        SubFramework(
          id: '${timestamp}_cmd_mgmt',
          name: 'מפקדים ומנהלת - $unitName',
          userIds: const [],
          isFixed: true,
          unitId: timestamp,
        ),
        if (nextLevel >= FrameworkLevel.platoon)
          SubFramework(
            id: '${timestamp}_soldiers',
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
        createdBy: newUnit.createdBy,
        createdAt: now,
        updatedAt: now,
        unitId: timestamp,
      );

      await _treeRepository.create(tree);

      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$levelName "$unitName" נוצר/ה בהצלחה'),
            backgroundColor: Colors.green,
          ),
        );
      }
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

  /// הוספת תת-מסגרת (SubFramework) לעץ
  Future<void> _addSubFramework() async {
    final nameController = TextEditingController();
    String? navigatorType;
    final bool unitIsNavigators = _unit?.isNavigators ?? false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('תת-מסגרת חדשה ב"${_tree.name}"'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'שם תת-המסגרת',
                      border: OutlineInputBorder(),
                      hintText: 'לדוגמה: מחלקה 1',
                    ),
                    autofocus: true,
                  ),
                  if (unitIsNavigators) ...[
                    const SizedBox(height: 16),
                    const Text('סוג מנווטים:',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'single', label: Text('בודד')),
                        ButtonSegment(value: 'pairs', label: Text('זוגות')),
                        ButtonSegment(
                            value: 'secured', label: Text('מאובטח')),
                      ],
                      selected: {navigatorType ?? 'single'},
                      onSelectionChanged: (selected) {
                        setDialogState(() {
                          navigatorType = selected.first;
                        });
                      },
                    ),
                  ],
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
                child: const Text('הוסף'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true || nameController.text.isEmpty) {
      return;
    }

    final newId = DateTime.now().millisecondsSinceEpoch.toString();
    final newSubFramework = SubFramework(
      id: newId,
      name: nameController.text,
      userIds: const [],
      navigatorType: unitIsNavigators
          ? (navigatorType ?? 'single')
          : null,
      unitId: _tree.unitId,
    );

    final updatedSubFrameworks = [
      ..._tree.subFrameworks,
      newSubFramework,
    ];

    final updatedTree = _tree.copyWith(
      subFrameworks: updatedSubFrameworks,
      updatedAt: DateTime.now(),
    );

    await _saveTree(updatedTree);
  }

  /// מחיקת תת-מסגרת
  Future<void> _deleteSubFramework(SubFramework subFramework) async {
    if (subFramework.isFixed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('לא ניתן למחוק תת-מסגרת קבועה'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('מחיקת תת-מסגרת'),
        content: Text('האם למחוק את "${subFramework.name}"?'),
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

    final updatedSubFrameworks = _tree.subFrameworks
        .where((sf) => sf.id != subFramework.id)
        .toList();

    final updatedTree = _tree.copyWith(
      subFrameworks: updatedSubFrameworks,
      updatedAt: DateTime.now(),
    );

    await _saveTree(updatedTree);
  }

  /// עריכת מנהלי מערכת של היחידה (Unit.managerIds)
  Future<void> _editUnitAdmins() async {
    if (_unit == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('לא נמצאה יחידה משויכת לעץ'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    List<String> currentAdmins = List.from(_unit!.managerIds);

    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('מנהלי מערכת - ${_unit!.name}'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'חובה לפחות מנהל מערכת אחד',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),

                // רשימת מנהלים נוכחיים
                if (currentAdmins.isNotEmpty)
                  Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: currentAdmins.length,
                      itemBuilder: (context, index) {
                        final adminId = currentAdmins[index];
                        final displayName =
                            _getUserDisplayName(adminId);
                        return ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.admin_panel_settings),
                          ),
                          title: Text(displayName),
                          subtitle: Text(adminId,
                              style: const TextStyle(fontSize: 11)),
                          trailing: currentAdmins.length > 1
                              ? IconButton(
                                  icon: const Icon(Icons.remove_circle,
                                      color: Colors.red),
                                  onPressed: () {
                                    setDialogState(() {
                                      currentAdmins.removeAt(index);
                                    });
                                  },
                                )
                              : const Icon(Icons.lock,
                                  color: Colors.grey),
                        );
                      },
                    ),
                  ),

                const SizedBox(height: 12),

                // כפתור הוספת מנהל
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final selectedId = await _showAdminUserPicker(
                        context,
                        currentAdmins,
                      );
                      if (selectedId != null) {
                        setDialogState(() {
                          currentAdmins.add(selectedId);
                        });
                      }
                    },
                    icon: const Icon(Icons.person_add),
                    label: const Text('הוסף מנהל'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ביטול'),
            ),
            ElevatedButton(
              onPressed: currentAdmins.isNotEmpty
                  ? () => Navigator.pop(context, currentAdmins)
                  : null,
              child: const Text('שמור'),
            ),
          ],
        ),
      ),
    );

    if (result == null || result.isEmpty) return;

    try {
      final updatedUnit = _unit!.copyWith(
        managerIds: result,
        updatedAt: DateTime.now(),
      );
      await _unitRepository.update(updatedUnit);
      setState(() {
        _unit = updatedUnit;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('מנהלי המערכת עודכנו בהצלחה'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בעדכון מנהלים: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// דיאלוג לבחירת מנהל מערכת - מציג רק משתמשים עם תפקיד מנהל
  Future<String?> _showAdminUserPicker(
      BuildContext parentContext, List<String> excludeIds) async {
    final searchController = TextEditingController();
    final manualIdController = TextEditingController();
    bool isManualMode = false;

    return showDialog<String>(
      context: parentContext,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          // סינון משתמשים עם תפקיד מנהל בלבד
          final adminUsers = _allUsers.where((user) {
            if (excludeIds.contains(user.uid)) return false;
            if (!_isAdminRole(user)) return false;
            if (searchController.text.isEmpty) return true;
            return user.fullName
                    .toLowerCase()
                    .contains(searchController.text.toLowerCase()) ||
                user.personalNumber
                    .toLowerCase()
                    .contains(searchController.text.toLowerCase());
          }).toList();

          return AlertDialog(
            title: const Text('בחר מנהל מערכת'),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: Column(
                children: [
                  // מתג בין בחירה מרשימה להזנה ידנית
                  _buildEntryModeToggle(
                    isManualMode: isManualMode,
                    onChanged: (value) =>
                        setDialogState(() => isManualMode = value),
                  ),
                  const SizedBox(height: 8),

                  if (!isManualMode) ...[
                    // חיפוש
                    TextField(
                      controller: searchController,
                      decoration: const InputDecoration(
                        labelText: 'חיפוש מנהל מערכת',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.search),
                        isDense: true,
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 8),
                    // הודעה שמוצגים רק מנהלים
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline,
                              size: 14, color: Colors.orange[700]),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'מוצגים רק משתמשים עם תפקיד מנהל',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.orange[700]),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    // רשימת משתמשים
                    Expanded(
                      child: adminUsers.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.person_off,
                                      size: 48, color: Colors.grey[400]),
                                  const SizedBox(height: 8),
                                  Text(
                                    'לא נמצאו מנהלי מערכת',
                                    style:
                                        TextStyle(color: Colors.grey[600]),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'עבור להזנה ידנית להוספת מנהל',
                                    style: TextStyle(
                                        color: Colors.grey[500],
                                        fontSize: 12),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              itemCount: adminUsers.length,
                              itemBuilder: (context, index) {
                                final user = adminUsers[index];
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor:
                                        Colors.orange.withOpacity(0.1),
                                    child: Text(
                                      user.fullName.isNotEmpty
                                          ? user.fullName[0]
                                          : '?',
                                      style: TextStyle(
                                          color: Colors.orange[700]),
                                    ),
                                  ),
                                  title: Text(user.fullName),
                                  subtitle: Text(
                                    '${user.personalNumber} | ${_getRoleDisplayName(user.role)}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  onTap: () =>
                                      Navigator.pop(context, user.uid),
                                );
                              },
                            ),
                    ),
                  ] else ...[
                    // הזנה ידנית של UID
                    const SizedBox(height: 8),
                    Expanded(
                      child: Column(
                        children: [
                          TextField(
                            controller: manualIdController,
                            decoration: const InputDecoration(
                              labelText: 'הזן מזהה (UID) של המנהל',
                              border: OutlineInputBorder(),
                              helperText:
                                  'למשתמש שעדיין לא רשום במערכת',
                              prefixIcon: Icon(Icons.badge),
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: manualIdController
                                      .text.isNotEmpty
                                  ? () => Navigator.pop(
                                      context, manualIdController.text)
                                  : null,
                              icon: const Icon(Icons.check),
                              label: const Text('אשר'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('ביטול'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// דיאלוג לבחירת משתמש (כלל המשתמשים) או הזנה ידנית
  Future<String?> _showUserPicker(
      BuildContext parentContext, List<String> excludeIds) async {
    final searchController = TextEditingController();
    final manualNameController = TextEditingController();
    bool isManualMode = false;

    return showDialog<String>(
      context: parentContext,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final filteredUsers = _allUsers.where((user) {
            if (excludeIds.contains(user.uid)) return false;
            if (searchController.text.isEmpty) return true;
            return user.fullName
                    .toLowerCase()
                    .contains(searchController.text.toLowerCase()) ||
                user.personalNumber
                    .toLowerCase()
                    .contains(searchController.text.toLowerCase());
          }).toList();

          return AlertDialog(
            title: const Text('הוסף משתמש'),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: Column(
                children: [
                  // מתג בין בחירה מרשימה להזנה ידנית
                  _buildEntryModeToggle(
                    isManualMode: isManualMode,
                    onChanged: (value) =>
                        setDialogState(() => isManualMode = value),
                  ),
                  const SizedBox(height: 8),

                  if (!isManualMode) ...[
                    // מצב בחירה מרשימה
                    TextField(
                      controller: searchController,
                      decoration: const InputDecoration(
                        labelText: 'חיפוש משתמש',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.search),
                        isDense: true,
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: filteredUsers.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.person_off,
                                      size: 48, color: Colors.grey[400]),
                                  const SizedBox(height: 8),
                                  Text(
                                    'לא נמצאו משתמשים',
                                    style:
                                        TextStyle(color: Colors.grey[600]),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'עבור להזנה ידנית להוספת שם',
                                    style: TextStyle(
                                        color: Colors.grey[500],
                                        fontSize: 12),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              itemCount: filteredUsers.length,
                              itemBuilder: (context, index) {
                                final user = filteredUsers[index];
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor:
                                        Colors.blue.withOpacity(0.1),
                                    child: Text(
                                      user.fullName.isNotEmpty
                                          ? user.fullName[0]
                                          : '?',
                                      style:
                                          TextStyle(color: Colors.blue[700]),
                                    ),
                                  ),
                                  title: Text(user.fullName),
                                  subtitle: Text(
                                    '${user.personalNumber} | ${_getRoleDisplayName(user.role)}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  trailing: Icon(
                                    Icons.add_circle_outline,
                                    color: Colors.green[600],
                                    size: 20,
                                  ),
                                  onTap: () =>
                                      Navigator.pop(context, user.uid),
                                );
                              },
                            ),
                    ),
                  ] else ...[
                    // מצב הזנה ידנית
                    const SizedBox(height: 8),
                    Expanded(
                      child: Column(
                        children: [
                          TextField(
                            controller: manualNameController,
                            decoration: const InputDecoration(
                              labelText: 'הזן שם מלא',
                              border: OutlineInputBorder(),
                              helperText:
                                  'למשתמש שעדיין לא רשום במערכת - ישויך בהמשך',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.amber[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.amber[200]!),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline,
                                    size: 16, color: Colors.amber[800]),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'המשתמש יתווסף כשם זמני. '
                                    'ניתן יהיה לשייך אותו למשתמש רשום בהמשך.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.amber[900],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: manualNameController
                                      .text.isNotEmpty
                                  ? () {
                                      final manualId =
                                          'manual_${manualNameController.text}';
                                      Navigator.pop(context, manualId);
                                    }
                                  : null,
                              icon: const Icon(Icons.check),
                              label: const Text('הוסף'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('ביטול'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// ניהול משתמשים בתת-מסגרת - עם בחירה מרשימה או הזנה ידנית
  Future<void> _manageSubFrameworkUsers(SubFramework subFramework) async {
    List<String> currentUsers = List.from(subFramework.userIds);

    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('משתמשים - ${subFramework.name}'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // רשימת משתמשים
                if (currentUsers.isNotEmpty)
                  Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: currentUsers.length,
                      itemBuilder: (context, index) {
                        final userId = currentUsers[index];
                        final displayName =
                            _getUserDisplayName(userId);
                        final isManualEntry =
                            userId.startsWith('manual_');
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isManualEntry
                                ? Colors.amber.withOpacity(0.2)
                                : Colors.blue.withOpacity(0.1),
                            radius: 16,
                            child: Icon(
                              isManualEntry
                                  ? Icons.person_outline
                                  : Icons.person,
                              size: 18,
                              color: isManualEntry
                                  ? Colors.amber[700]
                                  : Colors.blue[700],
                            ),
                          ),
                          title: Text(displayName),
                          subtitle: isManualEntry
                              ? Text(
                                  'הזנה ידנית - ממתין לשיוך',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.amber[700],
                                  ),
                                )
                              : null,
                          trailing: IconButton(
                            icon: const Icon(Icons.remove_circle,
                                color: Colors.red),
                            onPressed: () {
                              setDialogState(() {
                                currentUsers.removeAt(index);
                              });
                            },
                          ),
                        );
                      },
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'אין משתמשים בתת-מסגרת זו',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ),

                const SizedBox(height: 12),

                // כפתור הוספת משתמש
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final selectedId = await _showUserPicker(
                        context,
                        currentUsers,
                      );
                      if (selectedId != null &&
                          !currentUsers.contains(selectedId)) {
                        setDialogState(() {
                          currentUsers.add(selectedId);
                        });
                      }
                    },
                    icon: const Icon(Icons.person_add),
                    label: const Text('הוסף משתמש'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ביטול'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, currentUsers),
              child: const Text('שמור'),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;

    final updatedSubFramework = subFramework.copyWith(userIds: result);
    final updatedSubFrameworks = _tree.subFrameworks.map((sf) {
      return sf.id == subFramework.id ? updatedSubFramework : sf;
    }).toList();

    final updatedTree = _tree.copyWith(
      subFrameworks: updatedSubFrameworks,
      updatedAt: DateTime.now(),
    );

    await _saveTree(updatedTree);
  }

  @override
  Widget build(BuildContext context) {
    final subFrameworks = _tree.subFrameworks;

    return Scaffold(
      appBar: AppBar(
        title: Text('ניהול מסגרות - ${_tree.name}'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshTree,
            tooltip: 'רענן',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
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
                            'ניהול תתי-מסגרות ומנהלי מערכת.\n'
                            'ניתן להוסיף משתמשים מרשימה או להזין שמות ידנית.',
                            style: TextStyle(
                                fontSize: 12, color: Colors.blue[900]),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // מנהלי מערכת של היחידה
                _buildAdminsSection(),

                // כפתור יצירת מסגרת משנה (יחידת בת)
                if (_unit != null &&
                    _unit!.level != null &&
                    FrameworkLevel.getNextLevelBelow(_unit!.level!) != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _addChildUnit,
                        icon: const Icon(Icons.add_business),
                        label: Text(
                          'הוספת ${FrameworkLevel.getName(FrameworkLevel.getNextLevelBelow(_unit!.level!)!)}',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ),

                const Divider(height: 24),

                // סיכום
                Row(
                  children: [
                    const Text(
                      'תתי-מסגרות',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    Chip(
                      label: Text('${subFrameworks.length} תתי-מסגרות'),
                      backgroundColor: Colors.blue[100],
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // רשימת תתי-מסגרות
                if (subFrameworks.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text('אין תתי-מסגרות',
                        style: TextStyle(color: Colors.grey[500])),
                  )
                else
                  ...subFrameworks.map((sub) {
                    return _buildSubFrameworkItem(sub);
                  }),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addSubFramework(),
        icon: const Icon(Icons.add),
        label: const Text('תת-מסגרת חדשה'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildAdminsSection() {
    final managerIds = _unit?.managerIds ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.admin_panel_settings,
                size: 18, color: Colors.orange[700]),
            const SizedBox(width: 8),
            const Text(
              'מנהלי מערכת:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _editUnitAdmins,
              icon: const Icon(Icons.edit, size: 16),
              label: const Text('ערוך', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (managerIds.isEmpty)
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red[200]!),
            ),
            child: Row(
              children: [
                Icon(Icons.warning, size: 16, color: Colors.red[700]),
                const SizedBox(width: 8),
                Text(
                  'אין מנהל מערכת מוגדר!',
                  style: TextStyle(color: Colors.red[700], fontSize: 12),
                ),
              ],
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: managerIds.map((adminId) {
              final displayName =
                  _getUserDisplayName(adminId);
              return Chip(
                avatar: CircleAvatar(
                  backgroundColor: Colors.orange[100],
                  radius: 12,
                  child: Icon(Icons.person,
                      size: 14, color: Colors.orange[800]),
                ),
                label: Text(displayName,
                    style: const TextStyle(fontSize: 12)),
                backgroundColor: Colors.orange[50],
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildSubFrameworkItem(SubFramework subFramework) {
    final int userCount = subFramework.userIds.length;
    final int manualCount =
        subFramework.userIds.where((id) => id.startsWith('manual_')).length;
    final int registeredCount = userCount - manualCount;
    final bool unitIsNavigators = _unit?.isNavigators ?? false;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: Colors.grey[50],
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          backgroundColor: Colors.blue.withOpacity(0.1),
          radius: 16,
          child: Text(
            '$userCount',
            style: TextStyle(
              color: Colors.blue[700],
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Row(
          children: [
            Text(subFramework.name),
            if (subFramework.isFixed)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(Icons.lock, size: 14, color: Colors.grey[500]),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '$registeredCount רשומים',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
                if (manualCount > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.amber[100],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '$manualCount ידניים',
                      style: TextStyle(
                          fontSize: 10, color: Colors.amber[800]),
                    ),
                  ),
                ],
              ],
            ),
            if (unitIsNavigators &&
                subFramework.navigatorType != null) ...[
              Text(
                _getNavigatorTypeText(subFramework.navigatorType!),
                style:
                    TextStyle(fontSize: 11, color: Colors.blue[700]),
              ),
            ],
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.people, size: 20),
              onPressed: () =>
                  _manageSubFrameworkUsers(subFramework),
              tooltip: 'נהל משתמשים',
            ),
            if (!subFramework.isFixed)
              IconButton(
                icon:
                    const Icon(Icons.delete, size: 20, color: Colors.red),
                onPressed: () =>
                    _deleteSubFramework(subFramework),
                tooltip: 'מחק',
              ),
          ],
        ),
      ),
    );
  }

  String _getNavigatorTypeText(String type) {
    switch (type) {
      case 'single':
        return 'בודד';
      case 'pairs':
        return 'זוגות';
      case 'secured':
        return 'מאובטח';
      default:
        return type;
    }
  }
}
