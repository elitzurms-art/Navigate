import 'package:flutter/material.dart';
import '../../../domain/entities/area.dart';
import '../../../domain/entities/boundary.dart';
import '../../../domain/entities/checkpoint.dart';
import '../../../data/repositories/boundary_repository.dart';
import '../../../data/repositories/checkpoint_repository.dart';
import '../../../core/utils/geometry_utils.dart';
import 'create_boundary_screen.dart';
import 'edit_boundary_screen.dart';

/// מסך רשימת גבולות גדוד
class BoundariesListScreen extends StatefulWidget {
  final Area area;

  const BoundariesListScreen({super.key, required this.area});

  @override
  State<BoundariesListScreen> createState() => _BoundariesListScreenState();
}

class _BoundariesListScreenState extends State<BoundariesListScreen> with WidgetsBindingObserver {
  final BoundaryRepository _repository = BoundaryRepository();
  final CheckpointRepository _checkpointRepository = CheckpointRepository();
  List<Boundary> _boundaries = [];
  List<Checkpoint> _checkpoints = [];
  Map<String, int> _checkpointsPerBoundary = {}; // ספירה לכל גבול
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadBoundaries();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadBoundaries();
    }
  }

  Future<void> _loadBoundaries() async {
    setState(() => _isLoading = true);
    try {
      final boundaries = await _repository.getByArea(widget.area.id);
      final checkpoints = await _checkpointRepository.getByArea(widget.area.id);

      // חישוב כמה נקודות ציון יש בכל גבול
      Map<String, int> checkpointsCount = {};
      for (final boundary in boundaries) {
        if (boundary.coordinates.isNotEmpty) {
          final pointsInBoundary = GeometryUtils.filterPointsInPolygon(
            points: checkpoints,
            getCoordinate: (cp) => cp.coordinates,
            polygon: boundary.coordinates,
          );
          checkpointsCount[boundary.id] = pointsInBoundary.length;
          print('גבול "${boundary.name}": ${pointsInBoundary.length} נקודות ציון');
        } else {
          checkpointsCount[boundary.id] = 0;
        }
      }

      setState(() {
        _boundaries = boundaries;
        _checkpoints = checkpoints;
        _checkpointsPerBoundary = checkpointsCount;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה בטעינת גבולות: $e')),
        );
      }
    }
  }

  Future<void> _viewBoundary(Boundary boundary) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(boundary.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (boundary.description.isNotEmpty) ...[
              const Text('תיאור:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(boundary.description),
              const SizedBox(height: 12),
            ],
            const Text('פוליגון:', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('${boundary.coordinates.length} נקודות בפוליגון'),
            const SizedBox(height: 12),
            const Text('נקודות ציון בשטח:', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('${_checkpointsPerBoundary[boundary.id] ?? 0} נקודות ציון'),
            const SizedBox(height: 12),
            const Text('סגנון:', style: TextStyle(fontWeight: FontWeight.bold)),
            Row(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  color: Colors.black,
                ),
                const SizedBox(width: 8),
                Text('עובי: ${boundary.strokeWidth}'),
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

  Future<void> _editBoundary(Boundary boundary) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditBoundaryScreen(
          area: widget.area,
          boundary: boundary,
        ),
      ),
    );
    if (result == true) {
      _loadBoundaries();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('גבולות גדוד - ${widget.area.name}'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _boundaries.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.border_all, size: 100, color: Colors.grey[300]),
                      const SizedBox(height: 20),
                      Text(
                        'אין גבולות',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'לחץ על + להוספת גבול גדוד',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: Colors.grey[500]),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _boundaries.length,
                  itemBuilder: (context, index) {
                    final boundary = _boundaries[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.black.withOpacity(0.1),
                          child: const Icon(Icons.border_all, color: Colors.black),
                        ),
                        title: Text(boundary.name),
                        subtitle: Text(
                          'פוליגון: ${boundary.coordinates.length} נקודות • '
                          'נ.צ. בשטח: ${_checkpointsPerBoundary[boundary.id] ?? 0}',
                        ),
                        trailing: PopupMenuButton(
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
                                _viewBoundary(boundary);
                                break;
                              case 'edit':
                                _editBoundary(boundary);
                                break;
                            }
                          },
                        ),
                        onTap: () => _viewBoundary(boundary),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CreateBoundaryScreen(area: widget.area),
            ),
          );
          if (result == true) {
            _loadBoundaries();
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
