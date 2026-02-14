import 'package:flutter/material.dart';
import '../../../domain/entities/area.dart';
import '../../../domain/entities/checkpoint.dart';
import '../../../data/repositories/checkpoint_repository.dart';
import '../../../data/repositories/boundary_repository.dart';
import '../../../services/auth_service.dart';
import '../../../core/utils/test_data_generator.dart';
import 'create_checkpoint_screen.dart';
import 'edit_checkpoint_screen.dart';

/// מסך רשימת נקודות ציון
class CheckpointsListScreen extends StatefulWidget {
  final Area area;

  const CheckpointsListScreen({super.key, required this.area});

  @override
  State<CheckpointsListScreen> createState() => _CheckpointsListScreenState();
}

class _CheckpointsListScreenState extends State<CheckpointsListScreen> with WidgetsBindingObserver {
  final CheckpointRepository _checkpointRepository = CheckpointRepository();
  List<Checkpoint> _checkpoints = [];
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
    _loadCheckpoints();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadCheckpoints();
    }
  }

  Future<void> _checkUserRole() async {
    final user = await AuthService().getCurrentUser();
    if (mounted) {
      setState(() => _isDeveloper = user?.isDeveloper ?? false);
    }
  }

  Future<void> _loadCheckpoints() async {
    setState(() => _isLoading = true);
    try {
      final checkpoints = await _checkpointRepository.getByArea(widget.area.id);
      setState(() {
        _checkpoints = checkpoints;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
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
      _selectedIds.addAll(_checkpoints.map((c) => c.id));
    });
  }

  Future<void> _deleteSelected() async {
    final count = _selectedIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('מחיקת נקודות ציון'),
        content: Text('האם למחוק $count נקודות ציון?\n\nהמחיקה תסונכרן לכל המכשירים.'),
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
      await _checkpointRepository.deleteMany(
        _selectedIds.toList(),
        areaId: widget.area.id,
      );
      _exitSelectMode();
      _loadCheckpoints();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('נמחקו $count נקודות ציון')),
        );
      }
    }
  }

  Future<void> _deleteAllCheckpoints() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('מחיקת כל הנקודות'),
        content: Text('האם למחוק את כל ${_checkpoints.length} הנקודות מהמכשיר?\n\nהנקודות ב-Firestore לא יימחקו.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('מחק הכל'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final deleted = await _checkpointRepository.deleteByArea(widget.area.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('נמחקו $deleted נקודות מהמכשיר')),
        );
        _loadCheckpoints();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _isSelectMode ? _buildSelectModeAppBar() : _buildNormalAppBar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _checkpoints.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.place, size: 100, color: Colors.grey[300]),
                      const SizedBox(height: 20),
                      Text(
                        'אין נקודות עדיין',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              color: Colors.grey[600],
                            ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _checkpoints.length,
                  itemBuilder: (context, index) {
                    final checkpoint = _checkpoints[index];
                    final color = checkpoint.color == 'blue' ? Colors.blue : Colors.green;
                    final isSelected = _selectedIds.contains(checkpoint.id);

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
                                      _selectedIds.remove(checkpoint.id);
                                    } else {
                                      _selectedIds.add(checkpoint.id);
                                    }
                                  });
                                },
                              )
                            : CircleAvatar(
                                backgroundColor: color,
                                child: Text(
                                  '${checkpoint.sequenceNumber}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                        title: Text(checkpoint.name),
                        subtitle: Text(checkpoint.description),
                        trailing: _isSelectMode ? null : PopupMenuButton(
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
                              value: 'view',
                              child: Row(
                                children: [
                                  Icon(Icons.info, color: Colors.green),
                                  SizedBox(width: 8),
                                  Text('פרטים'),
                                ],
                              ),
                            ),
                          ],
                          onSelected: (value) {
                            if (value == 'edit') {
                              _editCheckpoint(checkpoint);
                            } else if (value == 'view') {
                              _viewCheckpoint(checkpoint);
                            }
                          },
                        ),
                        onTap: _isSelectMode
                            ? () {
                                setState(() {
                                  if (isSelected) {
                                    _selectedIds.remove(checkpoint.id);
                                  } else {
                                    _selectedIds.add(checkpoint.id);
                                  }
                                });
                              }
                            : null,
                        onLongPress: _isDeveloper && !_isSelectMode
                            ? () {
                                setState(() {
                                  _isSelectMode = true;
                                  _selectedIds.add(checkpoint.id);
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
                    builder: (context) => CreateCheckpointScreen(area: widget.area),
                  ),
                );
                if (result == true) {
                  _loadCheckpoints();
                }
              },
              child: const Icon(Icons.add),
            ),
    );
  }

  AppBar _buildNormalAppBar() {
    return AppBar(
      title: Text('נקודות ציון - ${widget.area.name}'),
      backgroundColor: Theme.of(context).primaryColor,
      foregroundColor: Colors.white,
      actions: [
        if (_checkpoints.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: _deleteAllCheckpoints,
            tooltip: 'מחק את כל הנקודות',
          ),
        IconButton(
          icon: const Icon(Icons.science),
          onPressed: _create20TestCheckpoints,
          tooltip: 'צור נקודות אקראיות בתוך שטח',
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _loadCheckpoints,
        ),
      ],
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

  Future<void> _editCheckpoint(Checkpoint checkpoint) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditCheckpointScreen(
          area: widget.area,
          checkpoint: checkpoint,
        ),
      ),
    );
    if (result == true) {
      _loadCheckpoints();
    }
  }

  void _viewCheckpoint(Checkpoint checkpoint) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(checkpoint.name),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('מספר סידורי', '${checkpoint.sequenceNumber}'),
              _buildDetailRow('תיאור', checkpoint.description),
              _buildDetailRow('סוג', _getTypeText(checkpoint.type)),
              _buildDetailRow('צבע', checkpoint.color == 'blue' ? 'כחול' : 'ירוק'),
              if (checkpoint.coordinates != null) ...[
                _buildDetailRow('קו רוחב', checkpoint.coordinates!.lat.toStringAsFixed(6)),
                _buildDetailRow('קו אורך', checkpoint.coordinates!.lng.toStringAsFixed(6)),
                if (checkpoint.coordinates!.utm.isNotEmpty)
                  _buildDetailRow('UTM', checkpoint.coordinates!.utm),
              ],
              if (checkpoint.labels.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  'תוויות:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: checkpoint.labels.map((label) {
                    return Chip(
                      label: Text(label),
                      backgroundColor: Colors.blue.shade50,
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
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

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  String _getTypeText(String type) {
    switch (type) {
      case 'checkpoint':
        return 'נקודת ציון';
      case 'mandatory_passage':
        return 'מעבר חובה';
      case 'start':
        return 'התחלה';
      case 'end':
        return 'סיום';
      default:
        return type;
    }
  }

  Future<void> _create20TestCheckpoints() async {
    // טעינת גבולות
    final boundaryRepo = BoundaryRepository();
    final boundaries = await boundaryRepo.getByArea(widget.area.id);

    // משתנים לדיאלוג
    int numberOfCheckpoints = 20;
    String? selectedBoundaryId = boundaries.isNotEmpty ? boundaries.first.id : null;

    // הצגת דיאלוג עם אפשרויות
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('יצירת נקודות בדיקה'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // כמות נקודות
              const Text('כמות נקודות:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextFormField(
                initialValue: numberOfCheckpoints.toString(),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'הכנס מספר',
                ),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  final num = int.tryParse(value);
                  if (num != null && num > 0) {
                    numberOfCheckpoints = num;
                  }
                },
              ),
              const SizedBox(height: 16),

              // בחירת גבול
              const Text('גבול גזרה:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: selectedBoundaryId,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'בחר גבול',
                ),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('ללא גבול (אזור מרכזי)'),
                  ),
                  ...boundaries.map((boundary) => DropdownMenuItem(
                    value: boundary.id,
                    child: Text(boundary.name),
                  )),
                ],
                onChanged: (value) {
                  setDialogState(() {
                    selectedBoundaryId = value;
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
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.green),
              child: const Text('צור'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    // הצגת מחוון טעינה
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text('יוצר $numberOfCheckpoints נקודות...'),
                ],
              ),
            ),
          ),
        ),
      );
    }

    try {
      final generator = TestDataGenerator();

      if (selectedBoundaryId == null) {
        // יצירה סביב נקודה מרכזית (תל אביב)
        await generator.createCheckpointsInArea(
          areaId: widget.area.id,
          count: numberOfCheckpoints,
          centerLat: 32.0853,
          centerLng: 34.7818,
          radiusKm: 2.0,
        );
      } else {
        // יצירה בתוך הגבול הנבחר
        final selectedBoundary = boundaries.firstWhere((b) => b.id == selectedBoundaryId);
        await generator.createCheckpointsInBoundary(
          areaId: widget.area.id,
          count: numberOfCheckpoints,
          boundaryCoordinates: selectedBoundary.coordinates,
        );
      }

      // סגירת מחוון הטעינה
      if (mounted) {
        Navigator.pop(context);
      }

      // רענון הרשימה
      await _loadCheckpoints();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('נוצרו $numberOfCheckpoints נקודות ציון בהצלחה!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      // סגירת מחוון הטעינה במקרה של שגיאה
      if (mounted) {
        Navigator.pop(context);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה ביצירת נקודות: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
