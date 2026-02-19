import 'package:flutter/material.dart';
import '../../../domain/entities/navigation_tree.dart';
import '../../../domain/entities/user.dart' as app_user;
import '../../../data/repositories/navigation_tree_repository.dart';
import '../../../services/auth_service.dart';
import '../../../services/session_service.dart';

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

  late List<SubFramework> _subFrameworks;
  bool _isSaving = false;
  String _selectedTreeType = 'single'; // 'single' / 'pairs_secured'
  bool _isLoadingStructure = false;

  @override
  void initState() {
    super.initState();
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

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
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
    final isFixedGroup = subFramework.isFixed;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.grey[50],
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.blue.withOpacity(0.1),
          radius: 16,
          child: Icon(
            isFixedGroup ? Icons.admin_panel_settings : Icons.group,
            size: 18,
            color: Colors.blue[700],
          ),
        ),
        title: Text(subFramework.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'משויך אוטומטית לפי תפקיד',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
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
        trailing: subFramework.navigatorType != null
            ? IconButton(
                icon: const Icon(Icons.settings, size: 20),
                onPressed: () => _changeNavigatorType(index),
                tooltip: 'סוג מנווטים',
              )
            : null,
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
