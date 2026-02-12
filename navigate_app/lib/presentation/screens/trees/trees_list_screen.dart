import 'package:flutter/material.dart';
import '../../../domain/entities/navigator_tree.dart';
import '../../../data/repositories/navigator_tree_repository.dart';
import '../../../services/auth_service.dart';
import 'create_tree_screen.dart';
import 'edit_tree_screen.dart';

/// מסך עצי מנווטים
class TreesListScreen extends StatefulWidget {
  const TreesListScreen({super.key});

  @override
  State<TreesListScreen> createState() => _TreesListScreenState();
}

class _TreesListScreenState extends State<TreesListScreen> {
  final NavigatorTreeRepository _treeRepository = NavigatorTreeRepository();
  final AuthService _authService = AuthService();
  List<NavigatorTree> _trees = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTrees();
  }

  Future<void> _loadTrees() async {
    setState(() => _isLoading = true);
    try {
      final trees = await _treeRepository.getAll();
      setState(() {
        _trees = trees;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בטעינת עצים: $e'),
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
        title: const Text('עצי מנווטים'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadTrees,
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CreateTreeScreen(),
                ),
              );
              if (result == true) {
                _loadTrees();
              }
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _trees.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.account_tree,
                        size: 100,
                        color: Colors.grey[300],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'אין עצים עדיין',
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  color: Colors.grey[600],
                                ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'לחץ על + להוספת עץ חדש',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.grey[500],
                            ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _trees.length,
                  padding: const EdgeInsets.all(8),
                  itemBuilder: (context, index) {
                    final tree = _trees[index];
                    IconData icon;
                    Color color;

                    switch (tree.type) {
                      case 'single':
                        icon = Icons.person;
                        color = Colors.blue;
                        break;
                      case 'pairs_group':
                        icon = Icons.group;
                        color = Colors.green;
                        break;
                      case 'secured':
                        icon = Icons.security;
                        color = Colors.orange;
                        break;
                      default:
                        icon = Icons.account_tree;
                        color = Colors.grey;
                    }

                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: color.withOpacity(0.2),
                          child: Icon(icon, color: color),
                        ),
                        title: Text(tree.name),
                        subtitle: Text(_getTypeText(tree.type)),
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
                                  Text('מחק',
                                      style: TextStyle(color: Colors.red)),
                                ],
                              ),
                            ),
                          ],
                          onSelected: (value) {
                            if (value == 'edit') {
                              _editTree(tree);
                            } else if (value == 'delete') {
                              _confirmDelete(tree);
                            }
                          },
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  String _getTypeText(String type) {
    switch (type) {
      case 'single':
        return 'בודדים';
      case 'pairs_group':
        return 'זוגות/קבוצות';
      case 'secured':
        return 'מאובטח';
      default:
        return type;
    }
  }

  Future<void> _showCreateTreeDialog() async {
    final nameController = TextEditingController();
    String selectedType = 'single';

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('עץ מבנה חדש'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'שם העץ',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: selectedType,
                decoration: const InputDecoration(
                  labelText: 'סוג',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'single', child: Text('בודדים')),
                  DropdownMenuItem(
                      value: 'pairs_group', child: Text('זוגות/קבוצות')),
                  DropdownMenuItem(value: 'secured', child: Text('מאובטח')),
                ],
                onChanged: (value) {
                  setState(() {
                    selectedType = value!;
                  });
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('ביטול'),
            ),
            TextButton(
              onPressed: () async {
                if (nameController.text.isEmpty) {
                  return;
                }
                Navigator.pop(context, true);
              },
              child: const Text('צור'),
            ),
          ],
        ),
      ),
    );

    if (result == true && nameController.text.isNotEmpty) {
      try {
        final currentUser = await _authService.getCurrentUser();
        if (currentUser == null) return;

        final newTree = NavigatorTree(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: nameController.text,
          type: selectedType,
          members: [],
          createdBy: currentUser.uid,
          permissions: TreePermissions(
            editors: [currentUser.uid],
            viewers: [],
          ),
        );

        await _treeRepository.create(newTree);
        _loadTrees();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('העץ נוצר בהצלחה'),
              backgroundColor: Colors.green,
            ),
          );
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

  Future<void> _editTree(NavigatorTree tree) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditTreeScreen(tree: tree),
      ),
    );
    if (result == true) {
      _loadTrees();
    }
  }

  Future<void> _confirmDelete(NavigatorTree tree) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('מחיקת עץ'),
        content: Text('האם למחוק את העץ "${tree.name}"?'),
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
        await _treeRepository.delete(tree.id);
        _loadTrees();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('העץ נמחק בהצלחה'),
              backgroundColor: Colors.green,
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
}

