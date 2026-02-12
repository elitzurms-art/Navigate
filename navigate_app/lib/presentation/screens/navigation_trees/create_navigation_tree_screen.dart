import 'package:flutter/material.dart';
import '../../../domain/entities/navigation_tree.dart';
import '../../../domain/entities/user.dart' as app_user;
import '../../../data/repositories/navigation_tree_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../services/auth_service.dart';
import '../../../services/session_service.dart';
import '../../../core/constants/app_constants.dart';

/// מסך יצירת/עריכת עץ ניווט
class CreateNavigationTreeScreen extends StatefulWidget {
  final NavigationTree? tree;
  final app_user.User? currentUser;

  const CreateNavigationTreeScreen({super.key, this.tree, this.currentUser});

  @override
  State<CreateNavigationTreeScreen> createState() => _CreateNavigationTreeScreenState();
}

class _CreateNavigationTreeScreenState extends State<CreateNavigationTreeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _repository = NavigationTreeRepository();
  final _userRepository = UserRepository();

  late List<SubFramework> _subFrameworks;
  List<app_user.User> _allUsers = [];
  bool _isSaving = false;
  String _selectedTreeType = 'single'; // 'single' / 'pairs_secured'
  bool _isLoadingStructure = false;

  @override
  void initState() {
    super.initState();
    _loadUsers();
    if (widget.tree != null) {
      _nameController.text = widget.tree!.name;
      _subFrameworks = widget.tree!.subFrameworks.map((sf) => sf).toList();
      _selectedTreeType = widget.tree!.treeType ?? 'single';
    } else {
      // עץ חדש - טעינת תתי-מסגרות מעץ המבנה של היחידה
      _subFrameworks = [];
      _isLoadingStructure = true;
      _loadUnitStructureTree();
    }
  }

  /// טוען תתי-מסגרות מעץ הכובע הנוכחי
  Future<void> _loadUnitStructureTree() async {
    try {
      final session = await SessionService().getSavedSession();
      if (session == null || session.treeId.isEmpty) {
        _fallbackToDefault();
        return;
      }

      final tree = await _repository.getById(session.treeId);
      if (tree == null) {
        _fallbackToDefault();
        return;
      }

      // העתקת תתי-מסגרות עם רשימות משתמשים ריקות (לעץ חדש)
      final relevantSubFrameworks = tree.subFrameworks
          .map((sf) => sf.copyWith(userIds: []))
          .toList();

      if (mounted) {
        setState(() {
          _subFrameworks = relevantSubFrameworks;
          _isLoadingStructure = false;
        });
      }
    } catch (e) {
      print('DEBUG: Error loading unit structure tree: $e');
      _fallbackToDefault();
    }
  }

  /// Fallback — רשימת מסגרות ריקה
  void _fallbackToDefault() {
    if (!mounted) return;
    setState(() {
      _subFrameworks = [];
      _isLoadingStructure = false;
    });
  }

  Future<void> _loadUsers() async {
    try {
      final users = await _userRepository.getAll();
      if (mounted) {
        setState(() {
          _allUsers = users;
        });
      }
    } catch (e) {
      print('DEBUG: Error loading users: $e');
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
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
                                      // יוצר מזהה זמני עם קידומת manual_ כדי לזהות שזו הזנה ידנית
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

  void _manageUsers(int subIndex) async {
    final subFramework = _subFrameworks[subIndex];
    final users = List<String>.from(subFramework.userIds);

    await showDialog(
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
                if (users.isNotEmpty)
                  Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: users.length,
                      itemBuilder: (context, index) {
                        final userId = users[index];
                        final displayName = _getUserDisplayName(userId);
                        final isManualEntry = userId.startsWith('manual_');
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
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () {
                              setDialogState(() {
                                users.removeAt(index);
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
                      final selectedId =
                          await _showUserPicker(context, users);
                      if (selectedId != null &&
                          !users.contains(selectedId)) {
                        setDialogState(() {
                          users.add(selectedId);
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
              onPressed: () => Navigator.pop(context, users),
              child: const Text('שמור'),
            ),
          ],
        ),
      ),
    ).then((result) {
      if (result != null) {
        setState(() {
          _subFrameworks[subIndex] = _subFrameworks[subIndex].copyWith(
            userIds: result as List<String>,
          );
        });
      }
    });
  }

  void _changeNavigatorType(int subIndex) async {
    final currentType = _subFrameworks[subIndex].navigatorType;

    final newType = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('סוג מנווטים'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<String>(
              title: const Text('בודד'),
              value: 'single',
              groupValue: currentType,
              onChanged: (value) => Navigator.pop(context, value),
            ),
            RadioListTile<String>(
              title: const Text('זוגות'),
              value: 'pairs',
              groupValue: currentType,
              onChanged: (value) => Navigator.pop(context, value),
            ),
            RadioListTile<String>(
              title: const Text('מאובטח (זוגות מסודרים)'),
              value: 'secured',
              groupValue: currentType,
              onChanged: (value) => Navigator.pop(context, value),
            ),
          ],
        ),
      ),
    );

    if (newType != null) {
      setState(() {
        _subFrameworks[subIndex] = _subFrameworks[subIndex].copyWith(
          navigatorType: newType,
        );
      });
    }
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final authService = AuthService();
      final currentUser = await authService.getCurrentUser();
      if (currentUser == null) {
        throw Exception('משתמש לא מחובר');
      }

      final now = DateTime.now();
      final tree = NavigationTree(
        id: widget.tree?.id ?? now.millisecondsSinceEpoch.toString(),
        name: _nameController.text,
        subFrameworks: _subFrameworks,
        createdBy: widget.tree?.createdBy ?? currentUser.uid,
        createdAt: widget.tree?.createdAt ?? now,
        updatedAt: now,
        treeType: _selectedTreeType,
        sourceTreeId: widget.tree?.sourceTreeId,
        unitId: widget.currentUser?.unitId ?? widget.tree?.unitId,
      );

      // שמירה במאגר נתונים
      if (widget.tree == null) {
        await _repository.create(tree);
      } else {
        await _repository.update(tree);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.tree == null
                  ? 'עץ ניווט נוצר בהצלחה'
                  : 'עץ ניווט עודכן בהצלחה',
            ),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בשמירה: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.tree == null ? 'עץ ניווט חדש' : 'עריכת עץ ניווט'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _save,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // שם העץ
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'שם עץ הניווט',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.account_tree),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'נא להזין שם';
                }
                return null;
              },
            ),

            const SizedBox(height: 16),

            // בחירת סוג עץ
            const Text('סוג עץ:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'single', label: Text('בודד')),
                ButtonSegment(value: 'pairs_secured', label: Text('זוגות-מאובטח')),
              ],
              selected: {_selectedTreeType},
              onSelectionChanged: (selected) {
                setState(() => _selectedTreeType = selected.first);
              },
            ),

            const SizedBox(height: 24),

            // תתי-מסגרות
            if (_isLoadingStructure && widget.tree == null)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              )
            else
              ..._subFrameworks.asMap().entries.map((entry) {
                final index = entry.key;
                final subFramework = entry.value;
                return _buildSubFrameworkCard(index, subFramework);
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildSubFrameworkCard(int index, SubFramework subFramework) {
    // ספירת משתמשים ידניים
    final manualCount =
        subFramework.userIds.where((id) => id.startsWith('manual_')).length;
    final registeredCount = subFramework.userIds.length - manualCount;
    final isFixedGroup = subFramework.isFixed;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.grey[50],
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.blue.withOpacity(0.1),
          radius: 16,
          child: isFixedGroup
              ? Icon(
                  Icons.admin_panel_settings,
                  size: 18,
                  color: Colors.blue[700],
                )
              : Text(
                  '${subFramework.userIds.length}',
                  style: TextStyle(
                    color: Colors.blue[700],
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
        title: Text(subFramework.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '$registeredCount רשומים',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                if (manualCount > 0) ...[
                  const SizedBox(width: 8),
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
                          fontSize: 11, color: Colors.amber[800]),
                    ),
                  ),
                ],
              ],
            ),
            if (subFramework.navigatorType != null) ...[
              const SizedBox(height: 4),
              Text(
                _getNavigatorTypeText(subFramework.navigatorType!),
                style: TextStyle(fontSize: 11, color: Colors.blue[700]),
              ),
            ],
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (subFramework.navigatorType != null)
              IconButton(
                icon: const Icon(Icons.settings, size: 20),
                onPressed: () => _changeNavigatorType(index),
                tooltip: 'סוג מנווטים',
              ),
            IconButton(
              icon: const Icon(Icons.people, size: 20),
              onPressed: () => _manageUsers(index),
              tooltip: 'נהל משתמשים',
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
