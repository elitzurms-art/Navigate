import 'package:flutter/material.dart';
import '../../../domain/entities/navigation_tree.dart';
import '../../../domain/entities/user.dart' as app_user;
import '../../../data/repositories/navigation_tree_repository.dart';
import '../../../services/auth_service.dart';
import '../../../services/session_service.dart';
import 'create_navigation_tree_screen.dart';
import 'all_trees_screen.dart';

/// מסך רשימת עצי ניווט
class NavigationTreesListScreen extends StatefulWidget {
  const NavigationTreesListScreen({super.key});

  @override
  State<NavigationTreesListScreen> createState() => _NavigationTreesListScreenState();
}

class _NavigationTreesListScreenState extends State<NavigationTreesListScreen> with WidgetsBindingObserver {
  final NavigationTreeRepository _repository = NavigationTreeRepository();
  final AuthService _authService = AuthService();
  List<NavigationTree> _myTrees = [];
  app_user.User? _currentUser;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final user = await _authService.getCurrentUser();
      _currentUser = user;

      // שימוש ב-unitId מ-session (אם קיים), אחרת מ-user
      final session = await SessionService().getSavedSession();
      final unitId = session?.unitId ?? user?.unitId;

      List<NavigationTree> trees;
      if (unitId != null && unitId.isNotEmpty) {
        trees = await _repository.getByUnitId(unitId);
      } else {
        trees = await _repository.getAll();
      }

      // סינון: הצגת עצי ניווט בלבד (עם treeType), לא עצי מבנה
      trees = trees.where((t) => t.treeType != null).toList();

      setState(() {
        _myTrees = trees;
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

  Future<void> _deleteTree(NavigationTree tree) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('מחיקת עץ ניווט'),
        content: Text('האם למחוק את "${tree.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('מחק', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('מוחק...'),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      try {
        await _repository.delete(tree.id);

        if (mounted) {
          Navigator.pop(context);
        }

        _loadData();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('עץ ניווט נמחק')),
          );
        }
      } catch (e) {
        if (mounted) {
          Navigator.pop(context);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('שגיאה במחיקה: $e')),
          );
        }
      }
    }
  }

  String _getTreeTypeText(String? type) {
    switch (type) {
      case 'single':
        return 'בודד';
      case 'pairs_secured':
        return 'זוגות-מאובטח';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('עצי ניווט'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // כפתור "עצי מבנה נוספים"
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => AllTreesScreen(
                              currentUser: _currentUser,
                            ),
                          ),
                        );
                        if (result == true) {
                          _loadData();
                        }
                      },
                      icon: const Icon(Icons.folder_shared),
                      label: const Text('עצי מבנה נוספים'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ),
                const Divider(),
                // כותרת "עצי הניווט שלי"
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      Icon(Icons.account_tree, color: Theme.of(context).primaryColor, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'עצי הניווט שלי',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).primaryColor,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${_myTrees.length}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                // רשימת עצים
                Expanded(
                  child: _myTrees.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.account_tree, size: 100, color: Colors.grey[300]),
                              const SizedBox(height: 20),
                              Text(
                                'אין עצי ניווט',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(color: Colors.grey[600]),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'לחץ על + להוספת עץ ניווט',
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
                          itemCount: _myTrees.length,
                          itemBuilder: (context, index) {
                            final tree = _myTrees[index];
                            final subFrameworksCount = tree.subFrameworks.length;
                            final totalNavigators = tree.subFrameworks
                                .fold<int>(0, (sum, sub) => sum + sub.userIds.length);
                            final typeText = _getTreeTypeText(tree.treeType);

                            return Card(
                              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor:
                                      Theme.of(context).primaryColor.withOpacity(0.2),
                                  child: Icon(
                                    Icons.account_tree,
                                    color: Theme.of(context).primaryColor,
                                  ),
                                ),
                                title: Text(tree.name),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '$subFrameworksCount מסגרות מנווטים • $totalNavigators מנווטים',
                                      style: TextStyle(color: Colors.grey[600]),
                                    ),
                                    if (typeText.isNotEmpty)
                                      Container(
                                        margin: const EdgeInsets.only(top: 4),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.blue[50],
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          typeText,
                                          style: TextStyle(
                                              fontSize: 11, color: Colors.blue[700]),
                                        ),
                                      ),
                                    if (tree.sourceTreeId != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          'עותק משוכפל',
                                          style: TextStyle(
                                              fontSize: 11, color: Colors.orange[700]),
                                        ),
                                      ),
                                  ],
                                ),
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
                                  onSelected: (value) async {
                                    if (value == 'edit') {
                                      final result = await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              CreateNavigationTreeScreen(tree: tree),
                                        ),
                                      );
                                      if (result == true) {
                                        _loadData();
                                      }
                                    } else if (value == 'delete') {
                                      _deleteTree(tree);
                                    }
                                  },
                                ),
                                onTap: () async {
                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          CreateNavigationTreeScreen(tree: tree),
                                    ),
                                  );
                                  if (result == true) {
                                    _loadData();
                                  }
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CreateNavigationTreeScreen(
                currentUser: _currentUser,
              ),
            ),
          );
          if (result == true) {
            _loadData();
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
