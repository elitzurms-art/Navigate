import 'package:flutter/material.dart';
import '../../../domain/entities/area.dart';
import '../../../domain/entities/cluster.dart';
import '../../../data/repositories/cluster_repository.dart';
import '../../../services/auth_service.dart';
import 'create_cluster_screen.dart';
import 'edit_cluster_screen.dart';

/// מסך רשימת ביצי איזור
class ClustersListScreen extends StatefulWidget {
  final Area area;

  const ClustersListScreen({super.key, required this.area});

  @override
  State<ClustersListScreen> createState() => _ClustersListScreenState();
}

class _ClustersListScreenState extends State<ClustersListScreen> with WidgetsBindingObserver {
  final ClusterRepository _repository = ClusterRepository();
  List<Cluster> _clusters = [];
  bool _isLoading = true;

  // Multi-select state (developer only)
  bool _isSelectMode = false;
  final Set<String> _selectedIds = {};
  bool _isDeveloper = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkUserRole();
    _loadClusters();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadClusters();
    }
  }

  Future<void> _checkUserRole() async {
    final user = await AuthService().getCurrentUser();
    if (mounted) {
      setState(() => _isDeveloper = user?.isDeveloper ?? false);
    }
  }

  Future<void> _loadClusters() async {
    setState(() => _isLoading = true);
    try {
      final clusters = await _repository.getByArea(widget.area.id);
      setState(() {
        _clusters = clusters;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה בטעינת ביצות: $e')),
        );
      }
    }
  }

  void _exitSelectMode() {
    setState(() {
      _isSelectMode = false;
      _selectedIds.clear();
    });
  }

  void _selectAll() {
    setState(() {
      _selectedIds.addAll(_clusters.map((c) => c.id));
    });
  }

  Future<void> _deleteSelected() async {
    final count = _selectedIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('מחיקת ביצות איזור'),
        content: Text('האם למחוק $count ביצות איזור?\n\nהמחיקה תסונכרן לכל המכשירים.'),
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
      await _repository.deleteMany(
        _selectedIds.toList(),
        areaId: widget.area.id,
      );
      _exitSelectMode();
      _loadClusters();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('נמחקו $count ביצות איזור')),
        );
      }
    }
  }

  Future<void> _viewCluster(Cluster cluster) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(cluster.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (cluster.description.isNotEmpty) ...[
              const Text('תיאור:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(cluster.description),
              const SizedBox(height: 12),
            ],
            const Text('נקודות:', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('${cluster.coordinates.length} נקודות בפוליגון'),
            const SizedBox(height: 12),
            const Text('סגנון:', style: TextStyle(fontWeight: FontWeight.bold)),
            Row(
              children: [
                Container(
                  width: 40,
                  height: 20,
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(cluster.fillOpacity),
                    border: Border.all(color: Colors.green, width: 2),
                  ),
                ),
                const SizedBox(width: 8),
                Text('שקיפות: ${(cluster.fillOpacity * 100).round()}%'),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('סגור'),
          ),
        ],
      ),
    );
  }

  Future<void> _editCluster(Cluster cluster) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditClusterScreen(
          area: widget.area,
          cluster: cluster,
        ),
      ),
    );
    if (result == true) {
      _loadClusters();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _isSelectMode ? _buildSelectModeAppBar() : AppBar(
        title: Text('ביצי איזור - ${widget.area.name}'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _clusters.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.grid_on, size: 100, color: Colors.grey[300]),
                      const SizedBox(height: 20),
                      Text(
                        'אין ביצות איזור',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'לחץ על + להוספת ביצת איזור',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: Colors.grey[500]),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _clusters.length,
                  itemBuilder: (context, index) {
                    final cluster = _clusters[index];
                    final isSelected = _selectedIds.contains(cluster.id);
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      color: isSelected ? Colors.red.shade50 : null,
                      child: ListTile(
                        leading: _isSelectMode
                            ? Checkbox(
                                value: isSelected,
                                onChanged: (_) {
                                  setState(() {
                                    if (isSelected) {
                                      _selectedIds.remove(cluster.id);
                                    } else {
                                      _selectedIds.add(cluster.id);
                                    }
                                  });
                                },
                              )
                            : CircleAvatar(
                                backgroundColor: Colors.green.withOpacity(0.2),
                                child: const Icon(Icons.grid_on, color: Colors.green),
                              ),
                        title: Text(cluster.name),
                        subtitle: Text('${cluster.coordinates.length} נקודות'),
                        trailing: _isSelectMode ? null : PopupMenuButton(
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'view',
                              child: Row(
                                children: [
                                  Icon(Icons.visibility, color: Colors.blue),
                                  SizedBox(width: 8),
                                  Text('צפייה'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'edit',
                              child: Row(
                                children: [
                                  Icon(Icons.edit, color: Colors.orange),
                                  SizedBox(width: 8),
                                  Text('ערוך'),
                                ],
                              ),
                            ),
                          ],
                          onSelected: (value) {
                            switch (value) {
                              case 'view':
                                _viewCluster(cluster);
                                break;
                              case 'edit':
                                _editCluster(cluster);
                                break;
                            }
                          },
                        ),
                        onTap: _isSelectMode
                            ? () {
                                setState(() {
                                  if (isSelected) {
                                    _selectedIds.remove(cluster.id);
                                  } else {
                                    _selectedIds.add(cluster.id);
                                  }
                                });
                              }
                            : () => _viewCluster(cluster),
                        onLongPress: _isDeveloper && !_isSelectMode
                            ? () {
                                setState(() {
                                  _isSelectMode = true;
                                  _selectedIds.add(cluster.id);
                                });
                              }
                            : null,
                      ),
                    );
                  },
                ),
      floatingActionButton: _isSelectMode
          ? null
          : FloatingActionButton(
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CreateClusterScreen(area: widget.area),
                  ),
                );
                if (result == true) {
                  _loadClusters();
                }
              },
              child: const Icon(Icons.add),
            ),
    );
  }

  AppBar _buildSelectModeAppBar() {
    return AppBar(
      title: Text('${_selectedIds.length} נבחרו'),
      backgroundColor: Colors.red,
      foregroundColor: Colors.white,
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: _exitSelectMode,
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.select_all),
          onPressed: _selectAll,
          tooltip: 'בחר הכל',
        ),
        IconButton(
          icon: const Icon(Icons.delete),
          onPressed: _selectedIds.isNotEmpty ? _deleteSelected : null,
          tooltip: 'מחק נבחרים',
        ),
      ],
    );
  }
}
