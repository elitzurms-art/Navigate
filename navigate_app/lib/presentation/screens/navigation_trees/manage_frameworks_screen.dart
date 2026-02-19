import 'dart:async';
import 'package:flutter/material.dart';
import '../../../domain/entities/navigation_tree.dart';
import '../../../domain/entities/unit.dart' as domain_unit;
import '../../../domain/entities/user.dart' as app_user;
import '../../../data/repositories/navigation_tree_repository.dart';
import '../../../data/repositories/unit_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/sync/sync_manager.dart';
import '../../../core/constants/app_constants.dart';
import '../../../domain/entities/hat_type.dart';
import '../../../services/session_service.dart';

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
  StreamSubscription<String>? _syncSubscription;
  HatInfo? _currentHat;
  Map<String, List<app_user.User>> _subFrameworkUsersMap = {};

  @override
  void initState() {
    super.initState();
    _tree = widget.tree;
    _loadUsers();
    // האזנה לשינויי סנכרון — רענון אוטומטי כשמשתמשים מתעדכנים
    _syncSubscription = SyncManager().onDataChanged.listen((collection) {
      if (collection == AppConstants.usersCollection && mounted) {
        _loadUsers();
      }
    });
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    try {
      final users = await _userRepository.getAll();
      domain_unit.Unit? unit;
      if (_tree.unitId != null) {
        unit = await _unitRepository.getById(_tree.unitId!);
      }
      final session = await SessionService().getSavedSession();
      if (mounted) {
        setState(() {
          _allUsers = users;
          _unit = unit;
          _currentHat = session;
        });
        _loadSubFrameworkUsers();
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
        _loadSubFrameworkUsers();
      }
    } catch (e) {
      print('DEBUG: Error refreshing tree: $e');
    }
  }

  void _loadSubFrameworkUsers() {
    final map = <String, List<app_user.User>>{};
    for (final sf in _tree.subFrameworks) {
      final unitId = sf.unitId ?? _tree.unitId;
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
    }
    _subFrameworkUsersMap = map;
  }

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
      await _userRepository.removeUserFromUnit(user.uid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${user.fullName} הוסר מהיחידה'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      await _loadUsers();
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
    String? selectedAdminId;
    String? selectedAdminName;

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
                  const SizedBox(height: 16),
                  // בחירת מנהל ליחידה החדשה
                  const Text(
                    'מנהל היחידה:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (selectedAdminId != null)
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green[200]!),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle,
                              size: 18, color: Colors.green[700]),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              selectedAdminName ?? selectedAdminId!,
                              style: TextStyle(color: Colors.green[900]),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.close,
                                size: 18, color: Colors.grey[600]),
                            onPressed: () {
                              setDialogState(() {
                                selectedAdminId = null;
                                selectedAdminName = null;
                              });
                            },
                          ),
                        ],
                      ),
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final adminId = await _showAdminUserPicker(
                            context,
                            [], // אין להחריג אף אחד
                          );
                          if (adminId != null) {
                            final user = _allUsers
                                .where((u) => u.uid == adminId)
                                .toList();
                            setDialogState(() {
                              selectedAdminId = adminId;
                              selectedAdminName = user.isNotEmpty
                                  ? user.first.fullName
                                  : adminId;
                            });
                          }
                        },
                        icon: const Icon(Icons.person_add),
                        label: const Text('בחר מנהל'),
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

      // מנהלי היחידה: המנהל שנבחר, או מנהלי היחידה הנוכחית כברירת מחדל
      final managerIds = selectedAdminId != null
          ? [selectedAdminId!]
          : List<String>.from(_unit!.managerIds);

      final now = DateTime.now();
      final newUnit = domain_unit.Unit(
        id: timestamp,
        name: unitName,
        description: descriptionController.text,
        type: unitType,
        parentUnitId: _unit!.id,
        managerIds: managerIds,
        createdBy: managerIds.isNotEmpty ? managerIds.first : '',
        createdAt: now,
        updatedAt: now,
        level: nextLevel,
      );

      await _unitRepository.create(newUnit);

      // יצירת תתי-מסגרות אוטומטיות — תמיד מפקדים + חיילים
      final initialSubFrameworks = <SubFramework>[
        SubFramework(
          id: '${timestamp}_cmd_mgmt',
          name: 'מפקדים ומנהלת - $unitName',
          userIds: const [],
          isFixed: true,
          unitId: timestamp,
        ),
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
                        filterUnitId: _unit!.id,
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

  /// בדיקה אם המשתמש הוא מפקד (commander/unit_admin/admin/developer)
  bool _isCommanderRole(app_user.User user) {
    return user.role == AppConstants.roleAdmin ||
        user.role == AppConstants.roleUnitAdmin ||
        user.role == AppConstants.roleDeveloper ||
        user.role == AppConstants.roleCommander;
  }

  /// דיאלוג לבחירת מנהל מערכת - מציג רק מפקדים מאושרים שלא מנהלים יחידה אחרת
  Future<String?> _showAdminUserPicker(
      BuildContext parentContext, List<String> excludeIds, {String? filterUnitId}) async {
    final searchController = TextEditingController();
    final manualIdController = TextEditingController();
    bool isManualMode = false;

    return showDialog<String>(
      context: parentContext,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          // סינון: רק מפקדים מאושרים שלא ברשימת ההחרגות
          final adminUsers = _allUsers.where((user) {
            if (excludeIds.contains(user.uid)) return false;
            if (!_isCommanderRole(user)) return false;
            if (!user.isApproved) return false;
            if (filterUnitId != null && user.unitId != filterUnitId) return false;
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
                        labelText: 'חיפוש מפקד',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.search),
                        isDense: true,
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 8),
                    // הודעה שמוצגים רק מפקדים מאושרים
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
                              'מוצגים רק מפקדים מאושרים',
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
                                    'לא נמצאו מפקדים מאושרים',
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
                                  onTap: () async {
                                    // בדיקה שהמשתמש לא מנהל יחידה אחרת
                                    final isManaging = await _unitRepository
                                        .isUserManagingAnyUnit(user.uid);
                                    if (isManaging) {
                                      if (parentContext.mounted) {
                                        ScaffoldMessenger.of(parentContext)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(
                                                '${user.fullName} כבר מנהל יחידה אחרת'),
                                            backgroundColor: Colors.red,
                                          ),
                                        );
                                      }
                                      return;
                                    }
                                    if (context.mounted) {
                                      Navigator.pop(context, user.uid);
                                    }
                                  },
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
                                  ? () async {
                                      final uid = manualIdController.text;
                                      // בדיקה שהמשתמש לא מנהל יחידה אחרת
                                      final isManaging = await _unitRepository
                                          .isUserManagingAnyUnit(uid);
                                      if (isManaging) {
                                        if (parentContext.mounted) {
                                          ScaffoldMessenger.of(parentContext)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                  'משתמש $uid כבר מנהל יחידה אחרת'),
                                              backgroundColor: Colors.red,
                                            ),
                                          );
                                        }
                                        return;
                                      }
                                      if (context.mounted) {
                                        Navigator.pop(context, uid);
                                      }
                                    }
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
                            'משתמשים משויכים אוטומטית לפי תפקידם.',
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
                if (_currentHat?.type == HatType.admin &&
                    _unit != null &&
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
            if (_currentHat?.type == HatType.admin)
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

  /// בדיקה אם תת-מסגרת היא מסוג "חיילים" (מנווטים)
  bool _isSoldiersSubFramework(SubFramework subFramework) {
    return subFramework.id.endsWith('_soldiers') ||
        subFramework.name.contains('חיילים');
  }

  /// ספירת משתמשים המשויכים אוטומטית לתת-מסגרת לפי תפקיד ויחידה
  int _countUsersForSubFramework(SubFramework subFramework) {
    final unitId = subFramework.unitId ?? _tree.unitId;
    if (_isSoldiersSubFramework(subFramework)) {
      // חיילים: מנווטים מאושרים ביחידה
      return _allUsers.where((u) =>
          u.role == AppConstants.roleNavigator &&
          u.unitId == unitId &&
          u.isApproved).length;
    } else {
      // מפקדים ומנהלת: מפקדים מאושרים ביחידה
      return _allUsers.where((u) =>
          _isCommanderRole(u) &&
          u.unitId == unitId &&
          u.isApproved).length;
    }
  }

  Widget _buildSubFrameworkItem(SubFramework subFramework) {
    final int userCount = _countUsersForSubFramework(subFramework);
    final bool unitIsNavigators = _unit?.isNavigators ?? false;
    final users = _subFrameworkUsersMap[subFramework.id] ?? [];
    final isCommandersSf = !_isSoldiersSubFramework(subFramework);

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: Colors.grey[50],
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: isCommandersSf
              ? Colors.orange.withOpacity(0.1)
              : Colors.blue.withOpacity(0.1),
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
            Flexible(child: Text(subFramework.name)),
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
            Text(
              isCommandersSf
                  ? '$userCount מפקדים מאושרים'
                  : '$userCount חיילים מאושרים',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
            if (unitIsNavigators && subFramework.navigatorType != null)
              Text(
                _getNavigatorTypeText(subFramework.navigatorType!),
                style: TextStyle(fontSize: 11, color: Colors.blue[700]),
              ),
          ],
        ),
        children: [
          if (users.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'אין משתמשים משויכים',
                style: TextStyle(color: Colors.grey[500], fontSize: 13),
              ),
            )
          else
            ...users.map((user) => ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 14,
                backgroundColor: isCommandersSf
                    ? Colors.orange[50]
                    : Colors.blue[50],
                child: Text(
                  user.fullName.isNotEmpty ? user.fullName[0] : '?',
                  style: TextStyle(
                    fontSize: 11,
                    color: isCommandersSf ? Colors.orange[700] : Colors.blue[700],
                  ),
                ),
              ),
              title: Text(user.fullName, style: const TextStyle(fontSize: 13)),
              subtitle: Text(
                '${user.personalNumber} | ${_getRoleDisplayName(user.role)}',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
              trailing: IconButton(
                icon: Icon(Icons.person_remove, size: 18, color: Colors.red[400]),
                tooltip: 'הסר מהיחידה',
                onPressed: () => _removeUserFromUnit(user),
              ),
            )),
        ],
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
