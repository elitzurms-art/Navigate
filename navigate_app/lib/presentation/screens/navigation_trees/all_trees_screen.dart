import 'package:flutter/material.dart';
import '../../../domain/entities/navigation_tree.dart';
import '../../../domain/entities/unit.dart' as domain_unit;
import '../../../domain/entities/user.dart' as app_user;
import '../../../data/repositories/navigation_tree_repository.dart';
import '../../../data/repositories/unit_repository.dart';

/// מסך "עצי מבנה נוספים" — תצוגת כל עצי הניווט מכל היחידות
class AllTreesScreen extends StatefulWidget {
  final app_user.User? currentUser;

  const AllTreesScreen({super.key, this.currentUser});

  @override
  State<AllTreesScreen> createState() => _AllTreesScreenState();
}

class _AllTreesScreenState extends State<AllTreesScreen> {
  final NavigationTreeRepository _treeRepo = NavigationTreeRepository();
  final UnitRepository _unitRepo = UnitRepository();

  List<NavigationTree> _allTrees = [];
  Map<String, domain_unit.Unit> _unitsMap = {};
  bool _isLoading = false;
  bool _isCloning = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final trees = await _treeRepo.getAll();
      final units = await _unitRepo.getAll();

      final unitsMap = <String, domain_unit.Unit>{};
      for (final unit in units) {
        unitsMap[unit.id] = unit;
      }

      // סינון: מסתיר עצים של יחידות מסווגות (אלא אם זו היחידה שלי)
      final myUnitId = widget.currentUser?.unitId;
      final filteredTrees = trees.where((tree) {
        if (tree.unitId == null) return true;
        final unit = unitsMap[tree.unitId];
        if (unit == null) return true;
        if (unit.isClassified && unit.id != myUnitId) return false;
        return true;
      }).toList();

      setState(() {
        _allTrees = filteredTrees;
        _unitsMap = unitsMap;
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

  Future<void> _cloneTree(NavigationTree tree) async {
    final user = widget.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('אין משתמש מחובר')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('שכפול עץ ניווט'),
        content: Text('לשכפל את "${tree.name}" למסגרת שלי?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ביטול'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('שכפל'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isCloning = true);
    try {
      await _treeRepo.clone(
        tree,
        targetUnitId: user.unitId ?? '',
        createdBy: user.uid,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('עץ "${tree.name}" שוכפל בהצלחה'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true); // חזרה למסך הקודם עם תוצאה
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בשכפול: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCloning = false);
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
    // ארגון עצים לפי יחידות
    final treesByUnit = <String, List<NavigationTree>>{};
    final treesWithoutUnit = <NavigationTree>[];

    for (final tree in _allTrees) {
      if (tree.unitId != null && tree.unitId!.isNotEmpty) {
        treesByUnit.putIfAbsent(tree.unitId!, () => []).add(tree);
      } else {
        treesWithoutUnit.add(tree);
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('עצי מבנה נוספים'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _allTrees.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.folder_off, size: 80, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      Text(
                        'אין עצי ניווט זמינים',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                )
              : Stack(
                  children: [
                    ListView(
                      padding: const EdgeInsets.all(8),
                      children: [
                        // עצים ללא יחידה
                        if (treesWithoutUnit.isNotEmpty) ...[
                          _buildUnitSection(null, treesWithoutUnit),
                        ],
                        // עצים לפי יחידות
                        ...treesByUnit.entries.map((entry) {
                          final unit = _unitsMap[entry.key];
                          return _buildUnitSection(unit, entry.value);
                        }),
                      ],
                    ),
                    if (_isCloning)
                      Container(
                        color: Colors.black26,
                        child: const Center(
                          child: Card(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(),
                                  SizedBox(height: 16),
                                  Text('משכפל עץ...'),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }

  Widget _buildUnitSection(domain_unit.Unit? unit, List<NavigationTree> trees) {
    final myUnitId = widget.currentUser?.unitId;
    final isMyUnit = unit?.id == myUnitId;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: ExpansionTile(
        leading: Icon(
          unit?.getIcon() ?? Icons.folder,
          color: isMyUnit ? Colors.green : Colors.indigo,
        ),
        title: Text(
          unit?.name ?? 'כללי',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isMyUnit ? Colors.green[800] : null,
          ),
        ),
        subtitle: Text(
          '${trees.length} עצי ניווט${isMyUnit ? ' (היחידה שלי)' : ''}',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        initiallyExpanded: true,
        children: trees.map((tree) => _buildTreeItem(tree, isMyUnit)).toList(),
      ),
    );
  }

  Widget _buildTreeItem(NavigationTree tree, bool isMyUnit) {
    final totalNavigators = tree.subFrameworks
        .fold<int>(0, (sum, sub) => sum + sub.userIds.length);
    final typeText = _getTreeTypeText(tree.treeType);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.blue.withOpacity(0.1),
        radius: 18,
        child: Icon(Icons.account_tree, color: Colors.blue[700], size: 20),
      ),
      title: Text(tree.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$totalNavigators מנווטים',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          if (typeText.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                typeText,
                style: TextStyle(fontSize: 10, color: Colors.blue[700]),
              ),
            ),
        ],
      ),
      trailing: isMyUnit
          ? null
          : TextButton.icon(
              onPressed: _isCloning ? null : () => _cloneTree(tree),
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('שכפל אלי', style: TextStyle(fontSize: 12)),
            ),
    );
  }
}
