import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';
import '../../../domain/entities/area.dart';
import '../../../domain/entities/safety_point.dart';
import '../../../domain/entities/coordinate.dart';
import '../../../domain/entities/checkpoint.dart';
import '../../../domain/entities/boundary.dart';
import '../../../domain/entities/cluster.dart';
import '../../../data/repositories/safety_point_repository.dart';
import '../../../data/repositories/checkpoint_repository.dart';
import '../../../data/repositories/boundary_repository.dart';
import '../../../data/repositories/cluster_repository.dart';
import '../../widgets/map_with_selector.dart';

/// מסך יצירת נת"ב חדש — נקודה או פוליגון
class CreateSafetyPointScreen extends StatefulWidget {
  final Area area;

  const CreateSafetyPointScreen({super.key, required this.area});

  @override
  State<CreateSafetyPointScreen> createState() => _CreateSafetyPointScreenState();
}

class _CreateSafetyPointScreenState extends State<CreateSafetyPointScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _sequenceController = TextEditingController(text: '1');
  final MapController _mapController = MapController();
  final SafetyPointRepository _repository = SafetyPointRepository();
  final CheckpointRepository _checkpointRepo = CheckpointRepository();
  final SafetyPointRepository _safetyPointRepo = SafetyPointRepository();
  final BoundaryRepository _boundaryRepo = BoundaryRepository();
  final ClusterRepository _clusterRepo = ClusterRepository();

  String _selectedSeverity = 'medium';
  String _selectedType = 'point'; // 'point' or 'polygon'
  LatLng? _selectedLocation; // לנקודה
  List<LatLng> _polygonPoints = []; // לפוליגון
  bool _isLoading = false;
  bool _showOtherLayers = true;

  // שכבות אחרות
  List<Checkpoint> _checkpoints = [];
  List<SafetyPoint> _existingSafetyPoints = [];
  List<Boundary> _boundaries = [];
  List<Cluster> _clusters = [];

  static const LatLng _defaultCenter = LatLng(31.5, 34.75);

  @override
  void initState() {
    super.initState();
    _loadOtherLayers();
  }

  Future<void> _loadOtherLayers() async {
    try {
      final checkpoints = await _checkpointRepo.getByArea(widget.area.id);
      final safetyPoints = await _safetyPointRepo.getByArea(widget.area.id);
      final boundaries = await _boundaryRepo.getByArea(widget.area.id);
      final clusters = await _clusterRepo.getByArea(widget.area.id);

      setState(() {
        _checkpoints = checkpoints;
        _existingSafetyPoints = safetyPoints;
        _boundaries = boundaries;
        _clusters = clusters;
      });
    } catch (e) {
      print('שגיאה בטעינת שכבות: $e');
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _sequenceController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedType == 'point' && _selectedLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('נא לבחור מיקום על המפה')),
      );
      return;
    }

    if (_selectedType == 'polygon' && _polygonPoints.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('נא לסמן לפחות 3 נקודות לפוליגון')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final SafetyPoint point;

      if (_selectedType == 'point') {
        point = SafetyPoint(
          id: const Uuid().v4(),
          areaId: widget.area.id,
          name: _nameController.text,
          description: _descriptionController.text,
          type: 'point',
          coordinates: Coordinate(
            lat: _selectedLocation!.latitude,
            lng: _selectedLocation!.longitude,
            utm: '',
          ),
          sequenceNumber: int.parse(_sequenceController.text),
          severity: _selectedSeverity,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
      } else {
        point = SafetyPoint(
          id: const Uuid().v4(),
          areaId: widget.area.id,
          name: _nameController.text,
          description: _descriptionController.text,
          type: 'polygon',
          polygonCoordinates: _polygonPoints
              .map((ll) => Coordinate(lat: ll.latitude, lng: ll.longitude, utm: ''))
              .toList(),
          sequenceNumber: int.parse(_sequenceController.text),
          severity: _selectedSeverity,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
      }

      await _repository.add(point);

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('נת"ב נוצר בהצלחה')),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה: $e')),
        );
      }
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
        title: Text('נת"ב חדש - ${widget.area.name}'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_showOtherLayers ? Icons.layers : Icons.layers_outlined),
            onPressed: () {
              setState(() => _showOtherLayers = !_showOtherLayers);
            },
            tooltip: _showOtherLayers ? 'הסתר שכבות אחרות' : 'הצג שכבות אחרות',
          ),
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _save,
              tooltip: 'שמור',
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // שם
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'שם נקודת הבטיחות',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.warning),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'נא להזין שם';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // תיאור
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'תיאור',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.description),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),

            // מספר סידורי
            TextFormField(
              controller: _sequenceController,
              decoration: const InputDecoration(
                labelText: 'מספר סידורי',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.numbers),
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'נא להזין מספר';
                }
                if (int.tryParse(value) == null) {
                  return 'נא להזין מספר תקין';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // רמת חומרה
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'רמת חומרה',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: ['low', 'medium', 'high', 'critical'].map((severity) {
                        return ChoiceChip(
                          label: Text(_getSeverityLabel(severity)),
                          selected: _selectedSeverity == severity,
                          onSelected: (selected) {
                            if (selected) {
                              setState(() => _selectedSeverity = severity);
                            }
                          },
                          selectedColor: _getSeverityColor(severity).withOpacity(0.3),
                          labelStyle: TextStyle(
                            color: _selectedSeverity == severity
                                ? _getSeverityColor(severity)
                                : null,
                            fontWeight: _selectedSeverity == severity
                                ? FontWeight.bold
                                : null,
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // סוג — נקודה או פוליגון
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'סוג נת"ב',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.location_on, size: 18),
                                SizedBox(width: 4),
                                Text('נקודה'),
                              ],
                            ),
                            selected: _selectedType == 'point',
                            onSelected: (selected) {
                              if (selected) {
                                setState(() {
                                  _selectedType = 'point';
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ChoiceChip(
                            label: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.pentagon_outlined, size: 18),
                                SizedBox(width: 4),
                                Text('פוליגון'),
                              ],
                            ),
                            selected: _selectedType == 'polygon',
                            onSelected: (selected) {
                              if (selected) {
                                setState(() {
                                  _selectedType = 'polygon';
                                });
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // מפה
            Text(
              _selectedType == 'point' ? 'מיקום על המפה' : 'ציור פוליגון על המפה',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _selectedType == 'point'
                  ? 'לחץ על המפה לבחירת מיקום'
                  : 'לחץ על המפה להוספת קודקודים (לפחות 3)',
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 8),

            // toolbar לפוליגון
            if (_selectedType == 'polygon' && _polygonPoints.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(Icons.pentagon_outlined, size: 18, color: Colors.grey[700]),
                    const SizedBox(width: 8),
                    Text(
                      '${_polygonPoints.length} קודקודים',
                      style: TextStyle(color: Colors.grey[700]),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () {
                        setState(() => _polygonPoints.removeLast());
                      },
                      icon: const Icon(Icons.undo, size: 18),
                      label: const Text('בטל אחרון'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.orange,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                    const SizedBox(width: 4),
                    TextButton.icon(
                      onPressed: () {
                        setState(() => _polygonPoints.clear());
                      },
                      icon: const Icon(Icons.clear, size: 18),
                      label: const Text('נקה'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                  ],
                ),
              ),

            SizedBox(
              height: 300,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: MapWithTypeSelector(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _defaultCenter,
                    initialZoom: 8,
                    onTap: (tapPosition, point) {
                      setState(() {
                        if (_selectedType == 'point') {
                          _selectedLocation = point;
                        } else {
                          _polygonPoints.add(point);
                        }
                      });
                    },
                  ),
                  layers: [
                    // שכבת גבולות גזרה (ג"ג)
                    if (_showOtherLayers && _boundaries.isNotEmpty)
                      PolygonLayer(
                        polygons: _boundaries.map((boundary) {
                          return Polygon(
                            points: boundary.coordinates.map((c) => LatLng(c.lat, c.lng)).toList(),
                            color: Colors.black.withOpacity(0.1),
                            borderColor: Colors.black,
                            borderStrokeWidth: boundary.strokeWidth,
                            isFilled: true,
                          );
                        }).toList(),
                      ),
                    // שכבת ביצי איזור (בא)
                    if (_showOtherLayers && _clusters.isNotEmpty)
                      PolygonLayer(
                        polygons: _clusters.map((cluster) {
                          return Polygon(
                            points: cluster.coordinates.map((c) => LatLng(c.lat, c.lng)).toList(),
                            color: _parseColor(cluster.color).withOpacity(cluster.fillOpacity),
                            borderColor: _parseColor(cluster.color),
                            borderStrokeWidth: cluster.strokeWidth,
                            isFilled: true,
                          );
                        }).toList(),
                      ),
                    // שכבת נקודות ציון
                    if (_showOtherLayers && _checkpoints.isNotEmpty)
                      MarkerLayer(
                        markers: _checkpoints.map((cp) {
                          return Marker(
                            point: LatLng(cp.coordinates.lat, cp.coordinates.lng),
                            width: 30,
                            height: 30,
                            child: Icon(
                              Icons.place,
                              color: (cp.color == 'blue' ? Colors.blue : Colors.green).withOpacity(0.6),
                              size: 30,
                            ),
                          );
                        }).toList(),
                      ),
                    // שכבת נת"ב קיימות — נקודות
                    if (_showOtherLayers && _existingSafetyPoints.isNotEmpty)
                      MarkerLayer(
                        markers: _existingSafetyPoints
                            .where((sp) => sp.type == 'point' && sp.coordinates != null)
                            .map((sp) {
                          return Marker(
                            point: LatLng(sp.coordinates!.lat, sp.coordinates!.lng),
                            width: 30,
                            height: 30,
                            child: Icon(
                              Icons.warning,
                              color: _getSeverityColor(sp.severity).withOpacity(0.6),
                              size: 30,
                            ),
                          );
                        }).toList(),
                      ),
                    // שכבת נת"ב קיימות — פוליגונים
                    if (_showOtherLayers && _existingSafetyPoints.isNotEmpty)
                      PolygonLayer(
                        polygons: _existingSafetyPoints
                            .where((sp) => sp.type == 'polygon' && sp.polygonCoordinates != null && sp.polygonCoordinates!.length >= 3)
                            .map((sp) {
                          return Polygon(
                            points: sp.polygonCoordinates!.map((c) => LatLng(c.lat, c.lng)).toList(),
                            color: _getSeverityColor(sp.severity).withOpacity(0.2),
                            borderColor: _getSeverityColor(sp.severity).withOpacity(0.6),
                            borderStrokeWidth: 2,
                            isFilled: true,
                          );
                        }).toList(),
                      ),
                    // הנקודה החדשה שנבחרה (סוג נקודה)
                    if (_selectedType == 'point' && _selectedLocation != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _selectedLocation!,
                            width: 50,
                            height: 50,
                            child: Icon(
                              Icons.warning,
                              color: _getSeverityColor(_selectedSeverity),
                              size: 40,
                            ),
                          ),
                        ],
                      ),
                    // הפוליגון החדש שמצויר (סוג פוליגון)
                    if (_selectedType == 'polygon' && _polygonPoints.length >= 3)
                      PolygonLayer(
                        polygons: [
                          Polygon(
                            points: _polygonPoints,
                            color: _getSeverityColor(_selectedSeverity).withOpacity(0.2),
                            borderColor: _getSeverityColor(_selectedSeverity),
                            borderStrokeWidth: 3,
                            isFilled: true,
                          ),
                        ],
                      ),
                    // קו בין נקודות הפוליגון (כשפחות מ-3)
                    if (_selectedType == 'polygon' && _polygonPoints.length >= 2 && _polygonPoints.length < 3)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: _polygonPoints,
                            color: _getSeverityColor(_selectedSeverity),
                            strokeWidth: 2,
                          ),
                        ],
                      ),
                    // markers לקודקודי הפוליגון
                    if (_selectedType == 'polygon' && _polygonPoints.isNotEmpty)
                      MarkerLayer(
                        markers: _polygonPoints.asMap().entries.map((entry) {
                          return Marker(
                            point: entry.value,
                            width: 24,
                            height: 24,
                            child: Container(
                              decoration: BoxDecoration(
                                color: _getSeverityColor(_selectedSeverity),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: Center(
                                child: Text(
                                  '${entry.key + 1}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),
            ),
            if (_selectedType == 'point' && _selectedLocation != null) ...[
              const SizedBox(height: 8),
              Text(
                'קואורדינטות: ${_selectedLocation!.latitude.toStringAsFixed(6)}, ${_selectedLocation!.longitude.toStringAsFixed(6)}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
            if (_selectedType == 'polygon' && _polygonPoints.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${_polygonPoints.length} קודקודים${_polygonPoints.length < 3 ? ' (נדרשים לפחות 3)' : ''}',
                style: TextStyle(
                  fontSize: 12,
                  color: _polygonPoints.length < 3 ? Colors.red : Colors.grey,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// המרת מחרוזת צבע ל-Color
  Color _parseColor(String colorStr) {
    final colorMap = {
      'black': Colors.black,
      'blue': Colors.blue,
      'green': Colors.green,
      'red': Colors.red,
      'yellow': Colors.yellow,
      'orange': Colors.orange,
      'purple': Colors.purple,
    };
    return colorMap[colorStr.toLowerCase()] ?? Colors.grey;
  }
}
