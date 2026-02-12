import 'package:flutter/material.dart';
import '../../../domain/entities/unit.dart';
import '../../../data/repositories/unit_repository.dart';
import '../../../data/repositories/navigation_tree_repository.dart';
import '../../../data/repositories/navigation_repository.dart';
import 'create_unit_screen.dart';

/// מסך רשימת יחידות (למפתח בלבד)
class UnitsListScreen extends StatefulWidget {
  const UnitsListScreen({super.key});

  @override
  State<UnitsListScreen> createState() => _UnitsListScreenState();
}

class _UnitsListScreenState extends State<UnitsListScreen> {
  final UnitRepository _repository = UnitRepository();
  List<Unit> _units = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUnits();
  }

  Future<void> _loadUnits() async {
    setState(() => _isLoading = true);
    try {
      final units = await _repository.getAll();
      setState(() {
        _units = units;
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

  Future<void> _deleteUnit(Unit unit) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('מחיקת יחידה'),
        content: Text(
          'האם למחוק את "${unit.name}"?\n'
          'פעולה זו תמחק גם את כל עצי הניווט והניווטים של היחידה.',
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

    if (confirmed == true) {
      try {
        // Cascade: unit → trees → navigations
        final treeRepo = NavigationTreeRepository();
        final navRepo = NavigationRepository();

        final trees = await treeRepo.getByUnitId(unit.id);
        for (final tree in trees) {
          // מחיקת כל הניווטים של העץ
          final navigations = await navRepo.getByTreeId(tree.id);
          for (final nav in navigations) {
            await navRepo.delete(nav.id);
          }
          // מחיקת העץ עצמו
          await treeRepo.delete(tree.id);
        }

        // מחיקת היחידה
        await _repository.delete(unit.id);

        _loadUnits();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'יחידה נמחקה (${trees.length} עצים)',
              ),
            ),
          );
        }
      } catch (e) {
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('יחידות'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _units.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.military_tech, size: 100, color: Colors.grey[300]),
                      const SizedBox(height: 20),
                      Text(
                        'אין יחידות',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'לחץ על + ליצירת יחידה',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: Colors.grey[500]),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _units.length,
                  itemBuilder: (context, index) {
                    final unit = _units[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.purple.withOpacity(0.2),
                          child: Icon(unit.getIcon(), color: Colors.purple),
                        ),
                        title: Text(unit.name),
                        subtitle: Text(unit.getTypeName()),
                        trailing: PopupMenuButton(
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'edit',
                              child: Row(
                                children: [
                                  Icon(Icons.edit, color: Colors.blue),
                                  SizedBox(width: 8),
                                  Text('ערוך'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Icons.delete, color: Colors.red),
                                  SizedBox(width: 8),
                                  Text('מחק'),
                                ],
                              ),
                            ),
                          ],
                          onSelected: (value) async {
                            if (value == 'edit') {
                              final result = await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => CreateUnitScreen(unit: unit),
                                ),
                              );
                              if (result == true) _loadUnits();
                            } else if (value == 'delete') {
                              _deleteUnit(unit);
                            }
                          },
                        ),
                        onTap: () async {
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => CreateUnitScreen(unit: unit),
                            ),
                          );
                          if (result == true) _loadUnits();
                        },
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const CreateUnitScreen(),
            ),
          );
          if (result == true) _loadUnits();
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
