import 'package:flutter/material.dart';
import '../../../domain/entities/area.dart';
import '../../../domain/entities/safety_point.dart';
import '../../../data/repositories/safety_point_repository.dart';
import 'create_safety_point_screen.dart';
import 'edit_safety_point_screen.dart';

/// מסך רשימת נקודות תורפה בטיחותיות (נת"ב)
class SafetyPointsListScreen extends StatefulWidget {
  final Area area;

  const SafetyPointsListScreen({super.key, required this.area});

  @override
  State<SafetyPointsListScreen> createState() => _SafetyPointsListScreenState();
}

class _SafetyPointsListScreenState extends State<SafetyPointsListScreen> with WidgetsBindingObserver {
  final SafetyPointRepository _repository = SafetyPointRepository();
  List<SafetyPoint> _points = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPoints();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadPoints();
    }
  }

  Future<void> _loadPoints() async {
    setState(() => _isLoading = true);
    try {
      final points = await _repository.getByArea(widget.area.id);
      setState(() {
        _points = points;
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

  Future<void> _viewPoint(SafetyPoint point) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(point.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (point.description.isNotEmpty) ...[
              const Text('תיאור:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(point.description),
              const SizedBox(height: 12),
            ],
            const Text('סוג:', style: TextStyle(fontWeight: FontWeight.bold)),
            Text(point.type == 'point' ? 'נקודה' : 'פוליגון'),
            const SizedBox(height: 12),
            const Text('מספר סידורי:', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('${point.sequenceNumber}'),
            const SizedBox(height: 12),
            const Text('רמת חומרה:', style: TextStyle(fontWeight: FontWeight.bold)),
            Row(
              children: [
                Icon(
                  Icons.warning,
                  color: _getSeverityColor(point.severity),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(_getSeverityLabel(point.severity)),
              ],
            ),
            const SizedBox(height: 12),
            if (point.type == 'point' && point.coordinates != null) ...[
              const Text('קואורדינטות:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('${point.coordinates!.lat.toStringAsFixed(6)}, ${point.coordinates!.lng.toStringAsFixed(6)}'),
            ],
            if (point.type == 'polygon' && point.polygonCoordinates != null) ...[
              const Text('פוליגון:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('${point.polygonCoordinates!.length} נקודות'),
            ],
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

  Future<void> _editPoint(SafetyPoint point) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditSafetyPointScreen(
          area: widget.area,
          point: point,
        ),
      ),
    );
    if (result == true) {
      _loadPoints();
    }
  }

  Color _getSeverityColor(String severity) {
    switch (severity) {
      case 'low':
        return Colors.orange;
      case 'medium':
        return Colors.red;
      case 'high':
        return Colors.red.shade700;
      case 'critical':
        return Colors.red.shade900;
      default:
        return Colors.red;
    }
  }

  String _getSeverityLabel(String severity) {
    switch (severity) {
      case 'low':
        return 'נמוכה';
      case 'medium':
        return 'בינונית';
      case 'high':
        return 'גבוהה';
      case 'critical':
        return 'קריטית';
      default:
        return 'בינונית';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('נת"ב - ${widget.area.name}'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _points.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.warning_amber, size: 100, color: Colors.grey[300]),
                      const SizedBox(height: 20),
                      Text(
                        'אין נקודות נת"ב',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'לחץ על + להוספת נת"ב',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: Colors.grey[500]),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _points.length,
                  itemBuilder: (context, index) {
                    final point = _points[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _getSeverityColor(point.severity).withOpacity(0.2),
                          child: Text(
                            '${point.sequenceNumber}',
                            style: TextStyle(
                              color: _getSeverityColor(point.severity),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(point.name),
                        subtitle: Text(_getSeverityLabel(point.severity)),
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
                                _viewPoint(point);
                                break;
                              case 'edit':
                                _editPoint(point);
                                break;
                            }
                          },
                        ),
                        onTap: () => _viewPoint(point),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CreateSafetyPointScreen(area: widget.area),
            ),
          );
          if (result == true) {
            _loadPoints();
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
