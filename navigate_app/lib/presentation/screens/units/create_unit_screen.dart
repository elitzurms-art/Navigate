import 'package:flutter/material.dart';
import '../../../domain/entities/unit.dart';
import '../../../domain/entities/user.dart' as app_user;
import '../../../data/repositories/unit_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../services/auth_service.dart';

/// מסך יצירת/עריכת יחידה
class CreateUnitScreen extends StatefulWidget {
  final Unit? unit; // null = יחידה חדשה

  const CreateUnitScreen({super.key, this.unit});

  @override
  State<CreateUnitScreen> createState() => _CreateUnitScreenState();
}

class _CreateUnitScreenState extends State<CreateUnitScreen> {
  final _formKey = GlobalKey<FormState>();
  final UnitRepository _repository = UnitRepository();
  final UserRepository _userRepository = UserRepository();
  final AuthService _authService = AuthService();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  String _selectedType = 'company';
  List<String> _managerIds = []; // מנהלי מערכת
  Map<String, String> _managerNames = {}; // uid -> fullName
  bool _isClassified = false;
  bool _isSaving = false;

  final List<String> _unitTypes = [
    'brigade',
    'battalion',
    'company',
    'platoon',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.unit != null) {
      _nameController.text = widget.unit!.name;
      _descriptionController.text = widget.unit!.description;
      _selectedType = widget.unit!.type;
      _managerIds = List.from(widget.unit!.managerIds);
      _isClassified = widget.unit!.isClassified;
      _loadManagerNames();
    }
  }

  /// טוען שמות מנהלים קיימים לתצוגה בצ'יפים
  Future<void> _loadManagerNames() async {
    final allUsers = await _userRepository.getAll();
    final names = <String, String>{};
    for (final user in allUsers) {
      if (_managerIds.contains(user.uid)) {
        names[user.uid] = user.fullName;
      }
    }
    if (mounted) {
      setState(() => _managerNames = names);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  String _getTypeName(String type) {
    switch (type) {
      case 'brigade':
        return 'חטיבה';
      case 'battalion':
        return 'גדוד';
      case 'company':
        return 'פלוגה';
      case 'platoon':
        return 'מחלקה';
      default:
        return type;
    }
  }

  Future<void> _addManager() async {
    final allUsers = await _userRepository.getAll();
    // סינון משתמשים שכבר נבחרו
    final availableUsers =
        allUsers.where((u) => !_managerIds.contains(u.uid)).toList();

    if (!mounted) return;

    final selectedUser = await showDialog<app_user.User>(
      context: context,
      builder: (context) => _UserSelectionDialog(users: availableUsers),
    );

    if (selectedUser != null) {
      setState(() {
        if (!_managerIds.contains(selectedUser.uid)) {
          _managerIds.add(selectedUser.uid);
          _managerNames[selectedUser.uid] = selectedUser.fullName;
        }
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final currentUser = await _authService.getCurrentUser();
      if (currentUser == null) {
        throw Exception('משתמש לא מחובר');
      }

      final now = DateTime.now();
      final unit = Unit(
        id: widget.unit?.id ?? now.millisecondsSinceEpoch.toString(),
        name: _nameController.text,
        description: _descriptionController.text,
        type: _selectedType,
        parentUnitId: widget.unit?.parentUnitId,
        managerIds: _managerIds.isEmpty ? [currentUser.uid] : _managerIds,
        createdBy: widget.unit?.createdBy ?? currentUser.uid,
        createdAt: widget.unit?.createdAt ?? now,
        updatedAt: now,
        isClassified: _isClassified,
      );

      if (widget.unit == null) {
        await _repository.create(unit);
      } else {
        await _repository.update(unit);
      }

      // עדכון unitId ותפקיד לכל מנהלי המערכת של היחידה
      for (final managerId in unit.managerIds) {
        await _userRepository.updateUserUnitId(managerId, unit.id);
      }

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.unit == null ? 'יחידה נוצרה בהצלחה' : 'יחידה עודכנה בהצלחה',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.unit == null ? 'יחידה חדשה' : 'עריכת יחידה'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // שם
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'שם היחידה',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.military_tech),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'נא להזין שם';
                }
                return null;
              },
            ),

            const SizedBox(height: 16),

            // תיאור
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'תיאור',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.description),
              ),
              maxLines: 3,
            ),

            const SizedBox(height: 16),

            // סוג יחידה
            DropdownButtonFormField<String>(
              value: _selectedType,
              decoration: const InputDecoration(
                labelText: 'סוג יחידה',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.category),
              ),
              items: _unitTypes.map((type) {
                return DropdownMenuItem(
                  value: type,
                  child: Text(_getTypeName(type)),
                );
              }).toList(),
              onChanged: (value) {
                setState(() => _selectedType = value!);
              },
            ),

            const SizedBox(height: 16),

            // יחידה מסווגת
            CheckboxListTile(
              title: const Text('יחידה מסווגת'),
              subtitle: Text(
                'לא מוצגת ליחידות אחרות',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              value: _isClassified,
              onChanged: (value) {
                setState(() => _isClassified = value ?? false);
              },
              secondary: Icon(
                Icons.security,
                color: _isClassified ? Colors.red : Colors.grey,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            ),

            const SizedBox(height: 16),

            // מנהלי מערכת (למפתח בלבד)
            Card(
              color: Colors.indigo[50],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'מנהלי מערכת',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'מנהלי מערכת יכולים ליצור מסגרות ולנהל את היחידה',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 12),
                    if (_managerIds.isEmpty)
                      const Text('אין מנהלי מערכת', style: TextStyle(color: Colors.grey))
                    else
                      Wrap(
                        spacing: 8,
                        children: _managerIds.map((id) => Chip(
                              avatar: const CircleAvatar(
                                child: Icon(Icons.person, size: 16),
                              ),
                              label: Text(_managerNames[id] ?? id),
                              onDeleted: () {
                                setState(() {
                                  _managerIds.remove(id);
                                  _managerNames.remove(id);
                                });
                              },
                            )).toList(),
                      ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _addManager,
                      icon: const Icon(Icons.add),
                      label: const Text('הוסף מנהל מערכת'),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 32),

            // כפתור שמירה
            SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _save,
                icon: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save),
                label: Text(_isSaving ? 'שומר...' : 'שמור'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// דיאלוג בחירת משתמש מרשימה עם חיפוש
class _UserSelectionDialog extends StatefulWidget {
  final List<app_user.User> users;

  const _UserSelectionDialog({required this.users});

  @override
  State<_UserSelectionDialog> createState() => _UserSelectionDialogState();
}

class _UserSelectionDialogState extends State<_UserSelectionDialog> {
  final TextEditingController _searchController = TextEditingController();
  List<app_user.User> _filteredUsers = [];

  @override
  void initState() {
    super.initState();
    _filteredUsers = widget.users;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterUsers(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredUsers = widget.users;
      } else {
        _filteredUsers = widget.users
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
            child: _filteredUsers.isEmpty
                ? const Center(
                    child: Text(
                      'לא נמצאו משתמשים',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _filteredUsers.length,
                    itemBuilder: (context, index) {
                      final user = _filteredUsers[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.indigo[100],
                          child: Text(
                            user.fullName.isNotEmpty
                                ? user.fullName[0]
                                : '?',
                            style: TextStyle(color: Colors.indigo[700]),
                          ),
                        ),
                        title: Text(user.fullName),
                        subtitle: Text(
                          '${user.role} | ${user.personalNumber}',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[600]),
                        ),
                        onTap: () => Navigator.pop(context, user),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
