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
import '../../widgets/map_controls.dart';

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
  String _geometryType = 'point'; // 'point' או 'polygon'
  LatLng? _selectedLocation;
  final List<LatLng> _polygonVertices = [];
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
  List<SafetyPoint> _existingSafetyPoints = [];
  List<Boundary> _boundaries = [];
  List<Cluster> _clusters = [];

  static const LatLng _defaultCenter = LatLng(31.5, 34.75);

  bool get _isPolygonMode => _geometryType == 'polygon';

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

    // ולידציה לפי סוג גאומטריה
    if (_isPolygonMode) {
      if (_polygonVertices.length < 3) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('פוליגון חייב להכיל לפחות 3 קודקודים')),
        );
        return;
      }
    } else {
      if (_selectedLocation == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('נא לבחור מיקום על המפה')),
        );
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      final point = SafetyPoint(
        id: const Uuid().v4(),
        areaId: widget.area.id,
        name: _nameController.text,
        description: _descriptionController.text,
        type: _geometryType,
        coordinates: !_isPolygonMode
            ? Coordinate(
                lat: _selectedLocation!.latitude,
                lng: _selectedLocation!.longitude,
                utm: '',
              )
            : null,
        polygonCoordinates: _isPolygonMode
            ? _polygonVertices
                .map((v) => Coordinate(lat: v.latitude, lng: v.longitude, utm: ''))
                .toList()
            : null,
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

  /// צבע נקודת בטיחות — תמיד אדום (ללא צבע לפי חומרה)
  Color _getSeverityColor(String severity) {
    return Colors.red;
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

            // בחירת סוג גאומטריה
            const Text(
              'גאומטריה',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'point',
                  label: Text('נקודה'),
                  icon: Icon(Icons.place),
                ),
                ButtonSegment(
                  value: 'polygon',
                  label: Text('פוליגון'),
                  icon: Icon(Icons.pentagon_outlined),
                ),
              ],
              selected: {_geometryType},
              onSelectionChanged: (selected) {
                setState(() {
                  _geometryType = selected.first;
                  _selectedLocation = null;
                  _polygonVertices.clear();
                });
              },
            ),
            const SizedBox(height: 16),

            // מפה
            Text(
              _isPolygonMode ? 'סימון פוליגון על המפה' : 'מיקום על המפה',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 300,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
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
                          if (_isPolygonMode) {
                            setState(() => _polygonVertices.add(point));
                          } else {
                            setState(() {
                              _selectedLocation = point;
                            });
                          }
                        },
                      ),
                      layers: [
                        // שכבת גבולות גזרה (ג"ג)
                        if (_showOtherLayers && _showGG && _boundaries.isNotEmpty)
                          PolygonLayer(
                            polygons: _boundaries.map((boundary) {
                              return Polygon(
                                points: boundary.coordinates.map((c) => LatLng(c.lat, c.lng)).toList(),
                                color: Colors.black.withValues(alpha: 0.1 * _ggOpacity),
                                borderColor: Colors.black.withValues(alpha: _ggOpacity),
                                borderStrokeWidth: boundary.strokeWidth,
                                isFilled: true,
                              );
                            }).toList(),
                          ),
                        // שכבת ביצי איזור (בא) — ירוק
                        if (_showOtherLayers && _showBA && _clusters.isNotEmpty)
                          PolygonLayer(
                            polygons: _clusters.map((cluster) {
                              return Polygon(
                                points: cluster.coordinates.map((c) => LatLng(c.lat, c.lng)).toList(),
                                color: Colors.green.withValues(alpha: cluster.fillOpacity * _baOpacity),
                                borderColor: Colors.green.withValues(alpha: _baOpacity),
                                borderStrokeWidth: cluster.strokeWidth,
                                isFilled: true,
                              );
                            }).toList(),
                          ),
                        // שכבת נקודות ציון (עיגול כחול/ירוק עם מספר)
                        if (_showOtherLayers && _showNZ && _checkpoints.isNotEmpty)
                          MarkerLayer(
                            markers: _checkpoints
                                .where((cp) => !cp.isPolygon && cp.coordinates != null)
                                .map((cp) {
                              final markerColor = cp.color == 'blue' ? Colors.blue : Colors.green;
                              return Marker(
                                point: LatLng(cp.coordinates!.lat, cp.coordinates!.lng),
                                width: 28,
                                height: 28,
                                child: Opacity(
                                  opacity: 0.6 * _nzOpacity,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: markerColor,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 1.5),
                                    ),
                                    child: Center(
                                      child: Text(
                                        '${cp.sequenceNumber}',
                                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        // שכבת נקודות ציון פוליגוניות
                        if (_showOtherLayers && _showNZ)
                          PolygonLayer(
                            polygons: _checkpoints
                                .where((cp) => cp.isPolygon && cp.polygonCoordinates != null)
                                .map((cp) {
                              final color = cp.color == 'blue' ? Colors.blue : Colors.green;
                              return Polygon(
                                points: cp.polygonCoordinates!.map((c) => LatLng(c.lat, c.lng)).toList(),
                                color: color.withOpacity(0.15 * _nzOpacity),
                                borderColor: color.withOpacity(0.6 * _nzOpacity),
                                borderStrokeWidth: 2,
                                isFilled: true,
                              );
                            }).toList(),
                          ),
                        // שכבת נת"ב קיימות
                        if (_showOtherLayers && _showNB && _existingSafetyPoints.isNotEmpty)
                          MarkerLayer(
                            markers: _existingSafetyPoints
                                .where((sp) => sp.type == 'point' && sp.coordinates != null)
                                .map((sp) {
                              return Marker(
                                point: LatLng(sp.coordinates!.lat, sp.coordinates!.lng),
                                width: 30,
                                height: 30,
                                child: Opacity(
                                  opacity: _nbOpacity,
                                  child: Icon(
                                    Icons.warning,
                                    color: _getSeverityColor(sp.severity).withOpacity(0.6),
                                    size: 30,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        // הנקודה החדשה שנבחרה (מצב נקודה)
                        if (!_isPolygonMode && _selectedLocation != null)
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
                        // פוליגון חדש — קודקודים + צורה (מצב פוליגון)
                        if (_isPolygonMode && _polygonVertices.isNotEmpty) ...[
                          PolygonLayer(
                            polygons: _polygonVertices.length >= 3
                                ? [
                                    Polygon(
                                      points: _polygonVertices,
                                      color: Colors.red.withOpacity(0.2),
                                      borderColor: Colors.red,
                                      borderStrokeWidth: 2.5,
                                      isFilled: true,
                                    ),
                                  ]
                                : [],
                          ),
                          if (_polygonVertices.length >= 2 && _polygonVertices.length < 3)
                            PolylineLayer(
                              polylines: [
                                Polyline(
                                  points: _polygonVertices,
                                  color: Colors.red,
                                  strokeWidth: 2.5,
                                ),
                              ],
                            ),
                          MarkerLayer(
                            markers: _polygonVertices.asMap().entries.map((entry) {
                              return Marker(
                                point: entry.value,
                                width: 24,
                                height: 24,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.red,
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
            ),
            // הנחיות ופקדי פוליגון / תצוגת קואורדינטות
            if (_isPolygonMode) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _polygonVertices.length < 3
                        ? 'לחץ על המפה להוספת קודקודים (${_polygonVertices.length}/3 מינימום)'
                        : 'פוליגון עם ${_polygonVertices.length} קודקודים',
                    style: TextStyle(
                      fontSize: 12,
                      color: _polygonVertices.length < 3 ? Colors.orange[700] : Colors.green[700],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _polygonVertices.isNotEmpty
                        ? () => setState(() => _polygonVertices.removeLast())
                        : null,
                    icon: const Icon(Icons.undo, size: 18),
                    label: const Text('בטל אחרון'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: _polygonVertices.isNotEmpty
                        ? () => setState(() => _polygonVertices.clear())
                        : null,
                    icon: const Icon(Icons.clear_all, size: 18),
                    label: const Text('נקה הכל'),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                  ),
                ],
              ),
            ] else if (_selectedLocation != null) ...[
              const SizedBox(height: 8),
              Text(
                'קואורדינטות: ${_selectedLocation!.latitude.toStringAsFixed(6)}, ${_selectedLocation!.longitude.toStringAsFixed(6)}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ] else ...[
              const SizedBox(height: 8),
              const Text(
                'לחץ על המפה לבחירת מיקום',
                style: TextStyle(color: Colors.grey, fontSize: 12),
                textAlign: TextAlign.center,
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
