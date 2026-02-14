import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';
import '../../../domain/entities/area.dart';
import '../../../domain/entities/cluster.dart';
import '../../../domain/entities/coordinate.dart';
import '../../../domain/entities/checkpoint.dart';
import '../../../domain/entities/safety_point.dart';
import '../../../domain/entities/boundary.dart';
import '../../../data/repositories/cluster_repository.dart';
import '../../../data/repositories/checkpoint_repository.dart';
import '../../../data/repositories/safety_point_repository.dart';
import '../../../data/repositories/boundary_repository.dart';
import '../../widgets/map_with_selector.dart';
import '../../widgets/map_controls.dart';

/// מסך יצירת ביצת איזור
class CreateClusterScreen extends StatefulWidget {
  final Area area;

  const CreateClusterScreen({super.key, required this.area});

  @override
  State<CreateClusterScreen> createState() => _CreateClusterScreenState();
}

class _CreateClusterScreenState extends State<CreateClusterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final MapController _mapController = MapController();
  final ClusterRepository _repository = ClusterRepository();
  final CheckpointRepository _checkpointRepo = CheckpointRepository();
  final SafetyPointRepository _safetyPointRepo = SafetyPointRepository();
  final BoundaryRepository _boundaryRepo = BoundaryRepository();
  final ClusterRepository _clusterRepo = ClusterRepository();

  List<LatLng> _polygonPoints = [];
  bool _isLoading = false;
  bool _showOtherLayers = true;
  bool _showGG = true;
  bool _showBA = true;
  bool _showNZ = true;
  bool _showNB = true;
  double _ggOpacity = 1.0;
  double _baOpacity = 1.0;
  double _nzOpacity = 1.0;
  double _nbOpacity = 1.0;
  bool _measureMode = false;
  final List<LatLng> _measurePoints = [];

  // שכבות אחרות
  List<Checkpoint> _checkpoints = [];
  List<SafetyPoint> _safetyPoints = [];
  List<Boundary> _boundaries = [];
  List<Cluster> _existingClusters = [];

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
        _safetyPoints = safetyPoints;
        _boundaries = boundaries;
        _existingClusters = clusters;
      });
    } catch (e) {
      print('שגיאה בטעינת שכבות: $e');
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _addPoint(LatLng point) {
    setState(() {
      _polygonPoints.add(point);
    });
  }

  void _undoLastPoint() {
    if (_polygonPoints.isNotEmpty) {
      setState(() {
        _polygonPoints.removeLast();
      });
    }
  }

  void _clearPoints() {
    setState(() {
      _polygonPoints.clear();
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_polygonPoints.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('יש לסמן לפחות 3 נקודות ליצירת פוליגון')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final coordinates = _polygonPoints.map((point) {
        return Coordinate(
          lat: point.latitude,
          lng: point.longitude,
          utm: '', // TODO: calculate UTM
        );
      }).toList();

      final cluster = Cluster(
        id: const Uuid().v4(),
        areaId: widget.area.id,
        name: _nameController.text,
        description: _descriptionController.text,
        coordinates: coordinates,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await _repository.add(cluster);

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ביצת איזור נוצרה בהצלחה')),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('ביצת איזור חדשה - ${widget.area.name}'),
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
        child: Column(
          children: [
            // טופס
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // שם
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'שם הביצה',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.grid_on),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'נא להזין שם';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  // תיאור
                  TextFormField(
                    controller: _descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'תיאור',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.description),
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),

            // מידע על הפוליגון
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.green[50],
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 20, color: Colors.green),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _polygonPoints.isEmpty
                          ? 'לחץ על המפה להתחלת ציור הביצה'
                          : 'נקודות: ${_polygonPoints.length}',
                      style: const TextStyle(color: Colors.green),
                    ),
                  ),
                  if (_polygonPoints.isNotEmpty) ...[
                    IconButton(
                      icon: const Icon(Icons.undo, size: 20, color: Colors.green),
                      onPressed: _undoLastPoint,
                      tooltip: 'בטל נקודה אחרונה',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.clear, size: 20, color: Colors.green),
                      onPressed: _clearPoints,
                      tooltip: 'נקה הכל',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ],
              ),
            ),

            // מפה
            Expanded(
              child: Stack(
                children: [
                  MapWithTypeSelector(
                    showTypeSelector: false,
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _defaultCenter,
                      initialZoom: 8,
                      onTap: (tapPosition, point) {
                        if (_measureMode) {
                          setState(() => _measurePoints.add(point));
                          return;
                        }
                        _addPoint(point);
                      },
                    ),
                    layers: [
                      // שכבת גבולות גזרה (ג"ג)
                      if (_showOtherLayers && _showGG && _boundaries.isNotEmpty)
                        PolygonLayer(
                          polygons: _boundaries.map((boundary) {
                            return Polygon(
                              points: boundary.coordinates.map((c) => LatLng(c.lat, c.lng)).toList(),
                              color: Colors.black.withValues(alpha: 0.05 * _ggOpacity),
                              borderColor: Colors.black.withValues(alpha: 0.3 * _ggOpacity),
                              borderStrokeWidth: boundary.strokeWidth,
                              isFilled: true,
                            );
                          }).toList(),
                        ),
                      // שכבת ביצי איזור קיימות
                      if (_showOtherLayers && _showBA && _existingClusters.isNotEmpty)
                        PolygonLayer(
                          polygons: _existingClusters.map((cluster) {
                            return Polygon(
                              points: cluster.coordinates.map((c) => LatLng(c.lat, c.lng)).toList(),
                              color: _parseColor(cluster.color).withValues(alpha: cluster.fillOpacity * 0.4 * _baOpacity),
                              borderColor: _parseColor(cluster.color).withValues(alpha: 0.6 * _baOpacity),
                              borderStrokeWidth: cluster.strokeWidth,
                              isFilled: true,
                            );
                          }).toList(),
                        ),
                      // שכבת נקודות ציון
                      if (_showOtherLayers && _showNZ && _checkpoints.isNotEmpty)
                        MarkerLayer(
                          markers: _checkpoints.map((cp) {
                            return Marker(
                              point: LatLng(cp.coordinates?.lat ?? 0, cp.coordinates?.lng ?? 0),
                              width: 24,
                              height: 24,
                              child: Opacity(
                                opacity: _nzOpacity,
                                child: Icon(
                                  Icons.place,
                                  color: (cp.color == 'blue' ? Colors.blue : Colors.green).withOpacity(0.6),
                                  size: 24,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      // שכבת נת"ב
                      if (_showOtherLayers && _showNB && _safetyPoints.isNotEmpty)
                        MarkerLayer(
                          markers: _safetyPoints
                              .where((sp) => sp.type == 'point' && sp.coordinates != null)
                              .map((sp) {
                            return Marker(
                              point: LatLng(sp.coordinates!.lat, sp.coordinates!.lng),
                              width: 24,
                              height: 24,
                              child: Opacity(
                                opacity: _nbOpacity,
                                child: Icon(
                                  Icons.warning,
                                  color: _getSeverityColor(sp.severity).withOpacity(0.6),
                                  size: 24,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      // הפוליגון החדש שנוצר
                      if (_polygonPoints.length >= 2)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: _polygonPoints,
                              color: Colors.green,
                              strokeWidth: 2,
                            ),
                          ],
                        ),
                      if (_polygonPoints.length >= 3)
                        PolygonLayer(
                          polygons: [
                            Polygon(
                              points: _polygonPoints,
                              color: Colors.green.withOpacity(0.2),
                              borderColor: Colors.green,
                              borderStrokeWidth: 2,
                              isFilled: true,
                            ),
                          ],
                        ),
                      if (_polygonPoints.isNotEmpty)
                        MarkerLayer(
                          markers: _polygonPoints.asMap().entries.map((entry) {
                            return Marker(
                              point: entry.value,
                              width: 30,
                              height: 30,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                ),
                                child: Center(
                                  child: Text(
                                    '${entry.key + 1}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ...MapControls.buildMeasureLayers(_measurePoints),
                    ],
                  ),
                  MapControls(
                    mapController: _mapController,
                    measureMode: _measureMode,
                    onMeasureModeChanged: (v) => setState(() {
                      _measureMode = v;
                      if (!v) _measurePoints.clear();
                    }),
                    measurePoints: _measurePoints,
                    onMeasureClear: () => setState(() => _measurePoints.clear()),
                    onMeasureUndo: () => setState(() {
                      if (_measurePoints.isNotEmpty) _measurePoints.removeLast();
                    }),
                    layers: [
                      MapLayerConfig(id: 'gg', label: 'גבול גזרה', color: Colors.black, visible: _showGG, opacity: _ggOpacity, onVisibilityChanged: (v) => setState(() => _showGG = v), onOpacityChanged: (v) => setState(() => _ggOpacity = v)),
                      MapLayerConfig(id: 'ba', label: 'ביצי אזור', color: Colors.green, visible: _showBA, opacity: _baOpacity, onVisibilityChanged: (v) => setState(() => _showBA = v), onOpacityChanged: (v) => setState(() => _baOpacity = v)),
                      MapLayerConfig(id: 'nz', label: 'נקודות ציון', color: Colors.blue, visible: _showNZ, opacity: _nzOpacity, onVisibilityChanged: (v) => setState(() => _showNZ = v), onOpacityChanged: (v) => setState(() => _nzOpacity = v)),
                      MapLayerConfig(id: 'nb', label: 'נקודות בטיחות', color: Colors.red, visible: _showNB, opacity: _nbOpacity, onVisibilityChanged: (v) => setState(() => _showNB = v), onOpacityChanged: (v) => setState(() => _nbOpacity = v)),
                    ],
                  ),
                ],
              ),
            ),
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

  /// קבלת צבע לפי רמת חומרה
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
}
