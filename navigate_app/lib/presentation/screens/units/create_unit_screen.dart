import 'package:flutter/material.dart';
import '../../../domain/entities/unit.dart';
import '../../../domain/entities/navigation_tree.dart';
import '../../../data/repositories/unit_repository.dart';
import '../../../data/repositories/navigation_tree_repository.dart';
import '../../../services/auth_service.dart';

/// מסך יצירת/עריכת יחידה
class CreateUnitScreen extends StatefulWidget {
  final Unit? unit; // null = יחידה חדשה
  final String? parentUnitId; // יחידת אב ליצירת יחידת משנה

  const CreateUnitScreen({super.key, this.unit, this.parentUnitId});

  @override
  State<CreateUnitScreen> createState() => _CreateUnitScreenState();
}

class _CreateUnitScreenState extends State<CreateUnitScreen> {
  final _formKey = GlobalKey<FormState>();
  final UnitRepository _repository = UnitRepository();
  final AuthService _authService = AuthService();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  String _selectedType = 'company';
  bool _isSaving = false;
  bool _isLoading = false;

  // כשיוצרים יחידת משנה — הסוג נקבע אוטומטית לפי ההורה
  bool _typeLockedByParent = false;
  int? _childLevel; // הרמה שנגזרת מההורה

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
    } else if (widget.parentUnitId != null) {
      _isLoading = true;
      _resolveChildType();
    }
  }

  /// טוען את יחידת האב וקובע את סוג היחידה החדשה — רמה אחת למטה
  Future<void> _resolveChildType() async {
    try {
      final parent = await _repository.getById(widget.parentUnitId!);
      if (parent == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final parentLevel = parent.level ?? FrameworkLevel.fromUnitType(parent.type);
      if (parentLevel == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final nextLevel = FrameworkLevel.getNextLevelBelow(parentLevel);
      if (nextLevel == null) {
        // אין רמה מתחת (מחלקה = הכי נמוכה) — לא אמור לקרות
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('לא ניתן ליצור יחידת משנה מתחת למחלקה'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // המרת רמה לסוג יחידה
      String childType;
      switch (nextLevel) {
        case FrameworkLevel.brigade:
          childType = 'brigade';
          break;
        case FrameworkLevel.battalion:
          childType = 'battalion';
          break;
        case FrameworkLevel.company:
          childType = 'company';
          break;
        case FrameworkLevel.platoon:
          childType = 'platoon';
          break;
        default:
          childType = 'company';
      }

      if (mounted) {
        setState(() {
          _selectedType = childType;
          _typeLockedByParent = true;
          _childLevel = nextLevel;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final currentUser = await _authService.getCurrentUser();
      if (currentUser == null) {
        throw Exception('משתמש לא מחובר');
      }

      final now = DateTime.now();
      final unitId = widget.unit?.id ?? now.millisecondsSinceEpoch.toString();

      final unit = Unit(
        id: unitId,
        name: _nameController.text,
        description: _descriptionController.text,
        type: _selectedType,
        parentUnitId: widget.unit?.parentUnitId ?? widget.parentUnitId,
        managerIds: widget.unit?.managerIds ?? [],
        createdBy: widget.unit?.createdBy ?? currentUser.uid,
        createdAt: widget.unit?.createdAt ?? now,
        updatedAt: now,
        isClassified: widget.unit?.isClassified ?? false,
        level: widget.unit?.level ?? _childLevel,
      );

      if (widget.unit == null) {
        await _repository.create(unit);

        // יצירת עץ ניווט אוטומטי עם תתי-מסגרות קבועות
        final treeId = 'tree_$unitId';
        final unitName = _nameController.text;
        final tree = NavigationTree(
          id: treeId,
          name: 'עץ מבנה - $unitName',
          subFrameworks: [
            SubFramework(
              id: '${treeId}_cmd_mgmt',
              name: 'מפקדים ומנהלת - $unitName',
              userIds: const [],
              isFixed: true,
              unitId: unitId,
            ),
            SubFramework(
              id: '${treeId}_soldiers',
              name: 'חיילים - $unitName',
              userIds: const [],
              isFixed: true,
              unitId: unitId,
            ),
          ],
          createdBy: currentUser.uid,
          createdAt: now,
          updatedAt: now,
          unitId: unitId,
        );
        await NavigationTreeRepository().create(tree);
      } else {
        await _repository.update(unit);
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
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('יחידה חדשה'),
          backgroundColor: Theme.of(context).primaryColor,
          foregroundColor: Colors.white,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

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
            // רמה — מוצג רק כשנקבע אוטומטית מההורה
            if (_typeLockedByParent && _childLevel != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.layers, size: 18, color: Colors.blue[700]),
                    const SizedBox(width: 8),
                    Text(
                      'רמה: ${FrameworkLevel.getName(_childLevel!)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[700],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // שם
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'שם היחידה',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.military_tech),
              ),
              autofocus: widget.unit == null,
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

            // סוג יחידה — נעול כשנקבע מההורה, חופשי בעריכה / יצירת יחידת שורש
            if (_typeLockedByParent)
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'סוג יחידה',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.category),
                ),
                child: Text(_getTypeName(_selectedType)),
              )
            else
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
