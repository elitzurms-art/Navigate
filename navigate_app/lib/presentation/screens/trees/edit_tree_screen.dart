import 'package:flutter/material.dart';
import '../../../domain/entities/navigator_tree.dart';
import '../../../domain/entities/user.dart';
import '../../../data/repositories/navigator_tree_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../services/auth_service.dart';

/// מסך עריכת עץ מבנה
class EditTreeScreen extends StatefulWidget {
  final NavigatorTree tree;

  const EditTreeScreen({super.key, required this.tree});

  @override
  State<EditTreeScreen> createState() => _EditTreeScreenState();
}

class _EditTreeScreenState extends State<EditTreeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _memberNameController = TextEditingController();

  late String _selectedType;
  List<String> _memberNames = [];
  final _firstPairController = TextEditingController();
  final _secondPairController = TextEditingController();
  bool _isLoadingMembers = true;

  @override
  void initState() {
    super.initState();
    // טעינת נתוני העץ הקיים
    _nameController.text = widget.tree.name;
    _selectedType = widget.tree.type;
    // טעינת חברים קיימים
    _loadExistingMembers();
  }

  Future<void> _loadExistingMembers() async {
    try {
      final userRepo = UserRepository();
      final allUsers = await userRepo.getAll();

      // המרת userIds לשמות
      for (final member in widget.tree.members) {
        // אם זה userId זמני (temp_X), הצג כ"חבר X"
        if (member.userId.startsWith('temp_')) {
          final num = member.userId.replaceAll('temp_', '');
          _memberNames.add('חבר $num');
        } else if (allUsers.isNotEmpty) {
          // נסה למצוא משתמש אמיתי
          try {
            final user = allUsers.firstWhere(
              (u) => u.uid == member.userId,
            );
            _memberNames.add(user.fullName);
          } catch (e) {
            // אם לא נמצא המשתמש, השתמש ב-userId מקוצר
            final shortId = member.userId.length > 8
                ? member.userId.substring(0, 8)
                : member.userId;
            _memberNames.add('משתמש $shortId');
          }
        } else {
          // אין משתמשים במערכת
          final shortId = member.userId.length > 8
              ? member.userId.substring(0, 8)
              : member.userId;
          _memberNames.add('משתמש $shortId');
        }
      }
    } catch (e) {
      // אם נכשל לחלוטין, לפחות נסה להציג משהו
      print('Failed to load members: $e');
      for (int i = 0; i < widget.tree.members.length; i++) {
        _memberNames.add('חבר ${i + 1}');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMembers = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _memberNameController.dispose();
    _firstPairController.dispose();
    _secondPairController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('עריכת עץ מבנה'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _updateTree,
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
                labelText: 'שם העץ',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.account_tree),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'נא להזין שם עץ';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // סוג העץ
            DropdownButtonFormField<String>(
              value: _selectedType,
              decoration: const InputDecoration(
                labelText: 'סוג העץ',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.category),
              ),
              items: const [
                DropdownMenuItem(value: 'single', child: Text('בודדים')),
                DropdownMenuItem(value: 'pairs_group', child: Text('זוגות/קבוצות')),
                DropdownMenuItem(value: 'secured', child: Text('מאובטח')),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedType = value!;
                });
              },
            ),
            const SizedBox(height: 24),

            // כותרת חברים
            Row(
              children: [
                const Icon(Icons.people, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  'מנווטים',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // הזנת מנווטים לפי סוג
            if (_selectedType == 'single' || _selectedType == 'pairs_group')
              Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _memberNameController,
                          decoration: const InputDecoration(
                            labelText: 'שם מנווט',
                            border: OutlineInputBorder(),
                            hintText: 'הזן שם...',
                          ),
                          onSubmitted: (_) => _addSingleMember(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _addSingleMember,
                        icon: const Icon(Icons.add),
                        label: const Text('הוסף'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: _selectUserFromDatabase,
                    icon: const Icon(Icons.person_search),
                    label: const Text('בחר ממשתמשים רשומים'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),

            // הזנת זוגות למאובטח
            if (_selectedType == 'secured')
              Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _firstPairController,
                          decoration: const InputDecoration(
                            labelText: 'מנווט ראשון',
                            border: OutlineInputBorder(),
                            hintText: 'שם...',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.link, color: Colors.blue, size: 32),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _secondPairController,
                          decoration: const InputDecoration(
                            labelText: 'מנווט שני',
                            border: OutlineInputBorder(),
                            hintText: 'שם...',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _addPair,
                          icon: const Icon(Icons.add),
                          label: const Text('הוסף צמד'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _selectPairFromDatabase,
                          icon: const Icon(Icons.person_search),
                          label: const Text('בחר זוג ממשתמשים'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

            const SizedBox(height: 16),

            // רשימת מנווטים
            if (_isLoadingMembers)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_memberNames.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'מנווטים ברשימה (${_memberNames.length})',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Divider(),
                    ..._buildMembersList(),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),

            // כפתור העלאת אקסל (placeholder)
            OutlinedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('העלאת Excel - בקרוב'),
                  ),
                );
              },
              icon: const Icon(Icons.upload_file),
              label: const Text('העלה קובץ Excel'),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildMembersList() {
    if (_selectedType == 'secured') {
      // הצגת זוגות
      List<Widget> widgets = [];
      for (int i = 0; i < _memberNames.length; i += 2) {
        if (i + 1 < _memberNames.length) {
          widgets.add(
            Card(
              color: Colors.blue.shade50,
              child: ListTile(
                leading: const Icon(Icons.link, color: Colors.blue),
                title: Row(
                  children: [
                    Expanded(child: Text(_memberNames[i])),
                    const Icon(Icons.sync_alt, size: 16),
                    Expanded(child: Text(_memberNames[i + 1])),
                  ],
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () {
                    setState(() {
                      _memberNames.removeAt(i + 1);
                      _memberNames.removeAt(i);
                    });
                  },
                ),
              ),
            ),
          );
        }
      }
      return widgets;
    } else {
      // הצגת רשימה רגילה
      return _memberNames.asMap().entries.map((entry) {
        return ListTile(
          leading: CircleAvatar(
            child: Text('${entry.key + 1}'),
          ),
          title: Text(entry.value),
          trailing: IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: () {
              setState(() {
                _memberNames.removeAt(entry.key);
              });
            },
          ),
        );
      }).toList();
    }
  }

  void _addSingleMember() {
    if (_memberNameController.text.isNotEmpty) {
      setState(() {
        _memberNames.add(_memberNameController.text);
        _memberNameController.clear();
      });
    }
  }

  void _addPair() {
    final firstName = _firstPairController.text.trim();
    final secondName = _secondPairController.text.trim();

    if (firstName.isEmpty || secondName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('יש להזין שני שמות לצמד'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _memberNames.add(firstName);
      _memberNames.add(secondName);
      _firstPairController.clear();
      _secondPairController.clear();
    });
  }

  Future<void> _selectUserFromDatabase() async {
    try {
      final userRepo = UserRepository();
      final users = await userRepo.getAll();

      if (users.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('אין משתמשים במערכת'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final selectedUser = await showDialog<User>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('בחר משתמש'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: users.length,
              itemBuilder: (context, index) {
                final user = users[index];
                return ListTile(
                  leading: CircleAvatar(
                    child: Text(user.fullName[0]),
                  ),
                  title: Text(user.fullName),
                  subtitle: Text(user.personalNumber),
                  onTap: () => Navigator.pop(context, user),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ביטול'),
            ),
          ],
        ),
      );

      if (selectedUser != null) {
        setState(() {
          _memberNames.add(selectedUser.fullName);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בטעינת משתמשים: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _selectPairFromDatabase() async {
    try {
      final userRepo = UserRepository();
      final users = await userRepo.getAll();

      if (users.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('אין משתמשים במערכת'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // בחירת משתמש ראשון
      final firstUser = await showDialog<User>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('בחר מנווט ראשון'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: users.length,
              itemBuilder: (context, index) {
                final user = users[index];
                return ListTile(
                  leading: CircleAvatar(
                    child: Text(user.fullName[0]),
                  ),
                  title: Text(user.fullName),
                  subtitle: Text(user.personalNumber),
                  onTap: () => Navigator.pop(context, user),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ביטול'),
            ),
          ],
        ),
      );

      if (firstUser == null) return;

      // בחירת משתמש שני
      final secondUser = await showDialog<User>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('בחר מנווט שני (זוג ל-${firstUser.fullName})'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: users.length,
              itemBuilder: (context, index) {
                final user = users[index];
                final isDisabled = user.uid == firstUser.uid;
                return ListTile(
                  enabled: !isDisabled,
                  leading: CircleAvatar(
                    backgroundColor: isDisabled ? Colors.grey : null,
                    child: Text(user.fullName[0]),
                  ),
                  title: Text(
                    user.fullName,
                    style: TextStyle(
                      color: isDisabled ? Colors.grey : null,
                    ),
                  ),
                  subtitle: Text(
                    isDisabled ? 'כבר נבחר' : user.personalNumber,
                    style: TextStyle(
                      color: isDisabled ? Colors.grey : null,
                    ),
                  ),
                  onTap: isDisabled
                      ? null
                      : () => Navigator.pop(context, user),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ביטול'),
            ),
          ],
        ),
      );

      if (secondUser != null) {
        setState(() {
          _memberNames.add(firstUser.fullName);
          _memberNames.add(secondUser.fullName);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בטעינת משתמשים: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _updateTree() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedType == 'secured' && _memberNames.length % 2 != 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('בניווט מאובטח חייב להיות מספר זוגי של מנווטים'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      final authService = AuthService();
      final currentUser = await authService.getCurrentUser();
      if (currentUser == null) {
        throw Exception('משתמש לא מחובר');
      }

      // המרת שמות לחברים
      final members = _memberNames
          .asMap()
          .entries
          .map((entry) => TreeMember(
                userId: 'temp_${entry.key}', // זמני - בעתיד נקשר למשתמשים אמיתיים
                role: 'navigator',
                subgroup: _selectedType == 'secured' ? (entry.key ~/ 2).toString() : null,
                pairOrder: _selectedType == 'secured' ? (entry.key % 2) + 1 : null,
              ))
          .toList();

      final updatedTree = NavigatorTree(
        id: widget.tree.id,
        name: _nameController.text,
        type: _selectedType,
        members: members,
        createdBy: widget.tree.createdBy,
        permissions: widget.tree.permissions,
      );

      final repository = NavigatorTreeRepository();
      await repository.update(updatedTree);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('העץ עודכן בהצלחה'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בעדכון: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
