import 'package:flutter/material.dart';
import '../../../domain/entities/navigation.dart' as domain;
import '../../../domain/entities/checkpoint.dart';
import '../../../data/repositories/nav_layer_repository.dart';
import '../../../data/repositories/navigation_repository.dart';
import '../../../services/routes_distribution_service.dart';

/// שלב 4 - עריכת צירים
class RoutesEditScreen extends StatefulWidget {
  final domain.Navigation navigation;

  const RoutesEditScreen({super.key, required this.navigation});

  @override
  State<RoutesEditScreen> createState() => _RoutesEditScreenState();
}

class _RoutesEditScreenState extends State<RoutesEditScreen> {
  final NavLayerRepository _navLayerRepo = NavLayerRepository();
  final NavigationRepository _navRepo = NavigationRepository();
  final RoutesDistributionService _distributionService = RoutesDistributionService();

  List<Checkpoint> _checkpoints = [];
  Map<String, domain.AssignedRoute> _routes = {};
  String? _selectedNavigatorId;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _routes = Map.from(widget.navigation.routes);
    _loadCheckpoints();
  }

  Future<void> _loadCheckpoints() async {
    setState(() => _isLoading = true);
    try {
      // טעינת נקודות ציון מהשכבות הניווטיות (כבר מסוננות לפי גבול גזרה)
      final navCheckpoints = await _navLayerRepo.getCheckpointsByNavigation(
        widget.navigation.id,
      );
      final checkpoints = navCheckpoints.map((nc) => Checkpoint(
        id: nc.sourceId,
        areaId: nc.areaId,
        name: nc.name,
        description: nc.description,
        type: nc.type,
        color: nc.color,
        coordinates: nc.coordinates,
        sequenceNumber: nc.sequenceNumber,
        labels: nc.labels,
        createdBy: nc.createdBy,
        createdAt: nc.createdAt,
      )).toList();
      setState(() {
        _checkpoints = checkpoints;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה בטעינת נקודות: $e')),
        );
      }
    }
  }

  Future<void> _saveChanges() async {
    setState(() => _isLoading = true);

    try {
      final updatedNavigation = widget.navigation.copyWith(
        routes: _routes,
        routesStage: 'verification',
        updatedAt: DateTime.now(),
      );

      await _navRepo.update(updatedNavigation);

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('שינויים נשמרו')),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה בשמירה: $e')),
        );
      }
    }
  }

  Future<void> _redistributeForNavigator(String navigatorId) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('חלוקה מחדש'),
        content: Text('האם לחלק מחדש נקודות למנווט $navigatorId?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('חלק'),
          ),
        ],
      ),
    );

    if (result != true) return;

    // TODO: לממש חלוקה מחדש למנווט ספציפי
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('בפיתוח - חלוקה מחדש למנווט ספציפי')),
    );
  }

  Future<void> _redistributeAll() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('חלוקה מחדש לכולם'),
        content: const Text('האם לחלק מחדש נקודות לכל המנווטים?\nהחלוקה הנוכחית תימחק.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('חלק', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (result != true) return;

    // TODO: לממש חלוקה מחדש לכולם
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('בפיתוח - חלוקה מחדש לכולם')),
    );
  }

  void _editNavigatorRoute(String navigatorId) {
    setState(() => _selectedNavigatorId = navigatorId);
    _showEditDialog(navigatorId);
  }

  Future<void> _showEditDialog(String navigatorId) async {
    final route = _routes[navigatorId];
    if (route == null) return;

    final selectedCheckpointIds = Set<String>.from(route.checkpointIds);

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('עריכת ציר - $navigatorId'),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: ListView.builder(
                itemCount: _checkpoints.length,
                itemBuilder: (context, index) {
                  final checkpoint = _checkpoints[index];
                  final isSelected = selectedCheckpointIds.contains(checkpoint.id);

                  return CheckboxListTile(
                    title: Text('${checkpoint.name} (${checkpoint.sequenceNumber})'),
                    subtitle: Text(checkpoint.coordinates != null ? '${checkpoint.coordinates!.lat.toStringAsFixed(4)}, ${checkpoint.coordinates!.lng.toStringAsFixed(4)}' : 'פוליגון'),
                    value: isSelected,
                    onChanged: (selected) {
                      setDialogState(() {
                        if (selected == true) {
                          selectedCheckpointIds.add(checkpoint.id);
                        } else {
                          selectedCheckpointIds.remove(checkpoint.id);
                        }
                      });
                    },
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('ביטול'),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    // עדכון הנקודות
                    final newCheckpointIds = selectedCheckpointIds.toList();
                    final newSequence = newCheckpointIds; // TODO: לאפשר שינוי סדר

                    // חישוב אורך מחדש
                    final selectedCheckpoints = _checkpoints
                        .where((cp) => newCheckpointIds.contains(cp.id))
                        .toList();

                    double length = 0.0; // TODO: חישוב מדויק

                    _routes[navigatorId] = route.copyWith(
                      checkpointIds: newCheckpointIds,
                      sequence: newSequence,
                      routeLengthKm: length,
                      status: 'optimal', // TODO: לבדוק לפי טווח
                      isVerified: false,
                    );
                  });
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('ציר עודכן')),
                  );
                },
                child: const Text('שמור'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('עריכת צירים'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'חלק מחדש לכולם',
            onPressed: _redistributeAll,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _routes.isEmpty
              ? const Center(
                  child: Text('אין צירים'),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _routes.length,
                  itemBuilder: (context, index) {
                    final entry = _routes.entries.elementAt(index);
                    final navigatorId = entry.key;
                    final route = entry.value;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ExpansionTile(
                        leading: CircleAvatar(
                          backgroundColor: _getRouteColor(route.status).withOpacity(0.2),
                          child: Icon(
                            Icons.person,
                            color: _getRouteColor(route.status),
                          ),
                        ),
                        title: Text(navigatorId),
                        subtitle: Text(
                          '${route.checkpointIds.length} נקודות • ${route.routeLengthKm.toStringAsFixed(2)} ק"מ',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: _getRouteColor(route.status),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.expand_more),
                          ],
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'נקודות ציון:',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: route.checkpointIds.map((id) {
                                    final checkpoint = _checkpoints.firstWhere(
                                      (cp) => cp.id == id,
                                      orElse: () => _checkpoints.first,
                                    );
                                    return Chip(
                                      label: Text('${checkpoint.sequenceNumber}'),
                                      backgroundColor: Colors.blue[50],
                                    );
                                  }).toList(),
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () => _editNavigatorRoute(navigatorId),
                                        icon: const Icon(Icons.edit),
                                        label: const Text('ערוך ידנית'),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () => _redistributeForNavigator(navigatorId),
                                        icon: const Icon(Icons.refresh),
                                        label: const Text('חלק מחדש'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
      bottomNavigationBar: BottomAppBar(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: ElevatedButton.icon(
            onPressed: _saveChanges,
            icon: const Icon(Icons.save),
            label: const Text('שמור שינויים'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 50),
            ),
          ),
        ),
      ),
    );
  }

  Color _getRouteColor(String status) {
    switch (status) {
      case 'too_short':
        return Colors.yellow[700]!;
      case 'optimal':
        return Colors.blue;
      case 'too_long':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}
