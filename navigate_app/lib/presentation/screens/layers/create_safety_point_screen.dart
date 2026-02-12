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

/// מסך יצירת נת"ב חדש
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
  LatLng? _selectedLocation;
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
    if (_selectedLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('נא לבחור מיקום על המפה')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final point = SafetyPoint(
        id: const Uuid().v4(),
        areaId: widget.area.id,
        name: _nameController.text,
        description: _descriptionController.text,
        coordinates: Coordinate(
          lat: _selectedLocation!.latitude,
          lng: _selectedLocation!.longitude,
          utm: '', // TODO: calculate UTM
        ),
        sequenceNumber: int.parse(_sequenceController.text),
        severity: _selectedSeverity,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

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

            // מפה
            const Text(
              'מיקום על המפה',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'לחץ על המפה לבחירת מיקום',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 8),
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
                        _selectedLocation = point;
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
                    // שכבת נת"ב קיימות
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
                    // הנקודה החדשה שנבחרה
                    if (_selectedLocation != null)
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
                  ],
                ),
              ),
            ),
            if (_selectedLocation != null) ...[
              const SizedBox(height: 8),
              Text(
                'קואורדינטות: ${_selectedLocation!.latitude.toStringAsFixed(6)}, ${_selectedLocation!.longitude.toStringAsFixed(6)}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
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
