import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../domain/entities/unit.dart';
import '../../../data/repositories/unit_repository.dart';
import '../../../data/sync/sync_manager.dart';
import 'create_unit_screen.dart';
import 'unit_members_screen.dart';

class _UnitWithDepth {
  final Unit unit;
  final int depth;
  const _UnitWithDepth(this.unit, this.depth);
}

/// מסך רשימת יחידות היררכי (למפתח בלבד)
class UnitsListScreen extends StatefulWidget {
  const UnitsListScreen({super.key});

  @override
  State<UnitsListScreen> createState() => _UnitsListScreenState();
}

class _UnitsListScreenState extends State<UnitsListScreen> {
  final UnitRepository _repository = UnitRepository();
  List<_UnitWithDepth> _hierarchicalUnits = [];
  bool _isLoading = true;
  StreamSubscription<String>? _syncSubscription;

  @override
  void initState() {
    super.initState();
    _loadUnits();
    // האזנה לשינויי סנכרון — רענון אוטומטי כשיחידות מתעדכנות
    _syncSubscription = SyncManager().onDataChanged.listen((collection) {
      if (collection == AppConstants.unitsCollection && mounted) {
        _loadUnits();
      }
    });
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    super.dispose();
  }

  List<_UnitWithDepth> _buildHierarchy(List<Unit> allUnits) {
    final result = <_UnitWithDepth>[];
    final childrenMap = <String?, List<Unit>>{};

    for (final unit in allUnits) {
      childrenMap.putIfAbsent(unit.parentUnitId, () => []).add(unit);
    }

    // Sort children by name at each level
    for (final list in childrenMap.values) {
      list.sort((a, b) => a.name.compareTo(b.name));
    }

    void addRecursive(String? parentId, int depth) {
      final children = childrenMap[parentId];
      if (children == null) return;
      for (final unit in children) {
        result.add(_UnitWithDepth(unit, depth));
        addRecursive(unit.id, depth + 1);
      }
    }

    addRecursive(null, 0);
    return result;
  }

  Future<void> _loadUnits() async {
    setState(() => _isLoading = true);
    try {
      final allUnits = await _repository.getAll();
      setState(() {
        _hierarchicalUnits = _buildHierarchy(allUnits);
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
          'פעולה זו תמחק את היחידה, יחידות המשנה שלה, '
          'עצי ניווט, ניווטים, ותאפס את המשתמשים המשויכים.',
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
        await _repository.deleteWithCascade(unit.id);

        _loadUnits();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('היחידה נמחקה בהצלחה'),
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
          : _hierarchicalUnits.isEmpty
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
                  itemCount: _hierarchicalUnits.length,
                  itemBuilder: (context, index) {
                    final item = _hierarchicalUnits[index];
                    final unit = item.unit;
                    final depth = item.depth;
                    return Padding(
                      padding: EdgeInsets.only(right: depth * 24.0),
                      child: Card(
                        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.purple.withOpacity(0.2 - depth * 0.04),
                            radius: 20 - depth * 1.5,
                            child: Icon(
                              unit.getIcon(),
                              color: Colors.purple.withOpacity(1.0 - depth * 0.15),
                              size: 24 - depth * 2.0,
                            ),
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
                                builder: (context) => UnitMembersScreen(unit: unit),
                              ),
                            );
                            if (result == true) _loadUnits();
                          },
                        ),
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
