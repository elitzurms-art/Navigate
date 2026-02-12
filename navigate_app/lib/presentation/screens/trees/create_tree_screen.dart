import 'package:flutter/material.dart';
import '../../../domain/entities/navigator_tree.dart';
import '../../../domain/entities/user.dart';
import '../../../data/repositories/navigator_tree_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../services/auth_service.dart';

/// מסך יצירת עץ מבנה
class CreateTreeScreen extends StatefulWidget {
  const CreateTreeScreen({super.key});

  @override
  State<CreateTreeScreen> createState() => _CreateTreeScreenState();
}

class _CreateTreeScreenState extends State<CreateTreeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _memberNameController = TextEditingController();

  String _selectedType = 'single';
  final List<String> _memberNames = [];
  final _firstPairController = TextEditingController();
  final _secondPairController = TextEditingController();

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
        title: const Text('עץ מבנה חדש'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveTree,
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
                const Spacer(),
                TextButton.icon(
                  onPressed: _selectFromUsers,
                  icon: const Icon(Icons.person_search),
                  label: const Text('בחר משתמשים'),
                ),
                TextButton.icon(
                  onPressed: () {
                    // TODO: העלאת קובץ Excel
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('העלאת Excel בפיתוח'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                  },
                  icon: const Icon(Icons.upload_file),
                  label: const Text('העלה Excel'),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // הוספת חבר
            if (_selectedType == 'secured')
              Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.orange.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'בעץ מאובטח יש להזין צמדים (2 מנווטים ביחד)',
                            style: TextStyle(color: Colors.orange.shade900),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _firstPairController,
                          decoration: const InputDecoration(
                            labelText: 'מנווט ראשון',
                            border: OutlineInputBorder(),
                            hintText: 'שם ראשון',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.link, color: Colors.blue),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _secondPairController,
                          decoration: const InputDecoration(
                            labelText: 'מנווט שני',
                            border: OutlineInputBorder(),
                            hintText: 'שם שני',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: _addPair,
                    icon: const Icon(Icons.group_add),
                    label: const Text('הוסף צמד'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 45),
                    ),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _memberNameController,
                      decoration: const InputDecoration(
                        labelText: 'שם מנווט',
                        border: OutlineInputBorder(),
                        hintText: 'הזן שם מלא',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _addMember,
                    icon: const Icon(Icons.add),
                    label: const Text('הוסף'),
                  ),
                ],
              ),
            const SizedBox(height: 16),

            // רשימת חברים
            if (_memberNames.isEmpty)
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Icon(Icons.people_outline, size: 48, color: Colors.grey[400]),
                    const SizedBox(height: 8),
                    Text(
                      'אין מנווטים עדיין',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(8),
                          topRight: Radius.circular(8),
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(
                            'סה"כ: ${_memberNames.length} מנווטים',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _memberNames.clear();
                              });
                            },
                            icon: const Icon(Icons.clear_all, size: 18),
                            label: const Text('נקה הכל'),
                          ),
                        ],
                      ),
                    ),
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _memberNames.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final isSecured = _selectedType == 'secured';
                        final isPairStart = isSecured && index % 2 == 0;
                        final isPairEnd = isSecured && index % 2 == 1;

                        return Container(
                          decoration: BoxDecoration(
                            color: isPairStart ? Colors.blue.shade50 : null,
                            border: isPairStart
                                ? Border(left: BorderSide(color: Colors.blue, width: 3))
                                : isPairEnd
                                    ? Border(left: BorderSide(color: Colors.blue, width: 3))
                                    : null,
                          ),
                          child: ListTile(
                            leading: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircleAvatar(
                                  backgroundColor: isPairStart || isPairEnd
                                      ? Colors.blue
                                      : null,
                                  child: Text('${index + 1}'),
                                ),
                                if (isPairStart || isPairEnd)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 4),
                                    child: Icon(
                                      Icons.link,
                                      size: 16,
                                      color: Colors.blue.shade700,
                                    ),
                                  ),
                              ],
                            ),
                            title: Text(_memberNames[index]),
                            subtitle: isPairStart
                                ? const Text('צמד - ראשון')
                                : isPairEnd
                                    ? const Text('צמד - שני')
                                    : null,
                            trailing: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () {
                                if (isSecured) {
                                  _removePair(index);
                                } else {
                                  setState(() {
                                    _memberNames.removeAt(index);
                                  });
                                }
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _addMember() {
    final name = _memberNameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('נא להזין שם מנווט'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _memberNames.add(name);
      _memberNameController.clear();
    });
  }

  void _addPair() {
    final firstName = _firstPairController.text.trim();
    final secondName = _secondPairController.text.trim();

    if (firstName.isEmpty || secondName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('נא להזין שני שמות לצמד'),
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

  void _removePair(int index) {
    final pairStartIndex = (index ~/ 2) * 2;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('מחיקת צמד'),
        content: Text(
          'האם למחוק את הצמד:\n'
          '${_memberNames[pairStartIndex]} ← → ${_memberNames[pairStartIndex + 1]}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _memberNames.removeAt(pairStartIndex + 1);
                _memberNames.removeAt(pairStartIndex);
              });
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('מחק'),
          ),
        ],
      ),
    );
  }

  Future<void> _selectFromUsers() async {
    try {
      final users = await UserRepository().getAll();

      if (!mounted) return;

      if (_selectedType == 'secured') {
        await _selectPairFromUsers(users);
      } else {
        await _selectSingleFromUsers(users);
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

  Future<void> _selectSingleFromUsers(List<User> users) async {
    final selected = await showDialog<User>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('בחר מנווט'),
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
                subtitle: Text(user.role),
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

    if (selected != null) {
      setState(() {
        _memberNames.add(selected.fullName);
      });
    }
  }

  Future<void> _selectPairFromUsers(List<User> users) async {
    User? firstUser;
    User? secondUser;

    // בחירת ראשון
    firstUser = await showDialog<User>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('בחר מנווט ראשון בצמד'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index];
              return ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.blue,
                  child: Text('1', style: TextStyle(color: Colors.white)),
                ),
                title: Text(user.fullName),
                subtitle: Text(user.role),
                onTap: () => Navigator.pop(context, user),
              );
            },
          ),
        ),
      ),
    );

    if (firstUser == null || !mounted) return;

    // בחירת שני
    secondUser = await showDialog<User>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('בחר מנווט שני בצמד'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.person, color: Colors.blue),
                    const SizedBox(width: 8),
                    Text('נבחר: ${firstUser!.fullName}'),
                    const Spacer(),
                    const Icon(Icons.link, color: Colors.blue),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: users.length,
                  itemBuilder: (context, index) {
                    final user = users[index];
                    final isDisabled = user.uid == firstUser?.uid;

                    return ListTile(
                      enabled: !isDisabled,
                      leading: CircleAvatar(
                        backgroundColor: isDisabled ? Colors.grey : Colors.blue,
                        child: Text(
                          '2',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      title: Text(
                        user.fullName,
                        style: TextStyle(
                          color: isDisabled ? Colors.grey : null,
                        ),
                      ),
                      subtitle: Text(user.role),
                      onTap: isDisabled ? null : () => Navigator.pop(context, user),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (secondUser != null) {
      setState(() {
        _memberNames.add(firstUser!.fullName);
        _memberNames.add(secondUser!.fullName);
      });
    }
  }

  Future<void> _saveTree() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_memberNames.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('יש להוסיף לפחות מנווט אחד'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      final currentUser = await AuthService().getCurrentUser();
      if (currentUser == null) {
        throw Exception('משתמש לא מחובר');
      }

      // יצירת רשימת חברים
      final members = _memberNames
          .asMap()
          .entries
          .map((entry) => TreeMember(
                userId: 'temp_${entry.key}', // זמני
                role: 'navigator',
                subgroup: null,
                pairOrder: _selectedType == 'secured' ? (entry.key % 2) + 1 : null,
              ))
          .toList();

      final newTree = NavigatorTree(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: _nameController.text,
        type: _selectedType,
        members: members,
        createdBy: currentUser.uid,
        permissions: TreePermissions(
          editors: [currentUser.uid],
          viewers: [],
        ),
      );

      await NavigatorTreeRepository().create(newTree);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('העץ נוצר בהצלחה'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה ביצירה: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
