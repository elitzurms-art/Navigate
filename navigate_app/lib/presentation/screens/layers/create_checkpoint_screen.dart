import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../domain/entities/area.dart';
import '../../../domain/entities/checkpoint.dart';
import '../../../domain/entities/coordinate.dart';
import '../../../domain/entities/safety_point.dart';
import '../../../domain/entities/boundary.dart';
import '../../../domain/entities/cluster.dart';
import '../../../data/repositories/checkpoint_repository.dart';
import '../../../data/repositories/safety_point_repository.dart';
import '../../../data/repositories/boundary_repository.dart';
import '../../../data/repositories/cluster_repository.dart';
import '../../../services/auth_service.dart';
import '../../widgets/map_with_selector.dart';
import '../../widgets/map_controls.dart';

/// מסך יצירת נקודת ציון (נקודה או פוליגון)
class CreateCheckpointScreen extends StatefulWidget {
  final Area area;

  const CreateCheckpointScreen({super.key, required this.area});

  @override
  State<CreateCheckpointScreen> createState() => _CreateCheckpointScreenState();
}

class _CreateCheckpointScreenState extends State<CreateCheckpointScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _sequenceController = TextEditingController();
  final _latController = TextEditingController();
  final _lngController = TextEditingController();
  final _utmController = TextEditingController();
  final _labelController = TextEditingController();

  final CheckpointRepository _checkpointRepo = CheckpointRepository();
  final SafetyPointRepository _safetyPointRepo = SafetyPointRepository();
  final BoundaryRepository _boundaryRepo = BoundaryRepository();
  final ClusterRepository _clusterRepo = ClusterRepository();

  String _selectedType = 'checkpoint';
  String _selectedColor = 'blue';
  String _geometryType = 'point'; // 'point' או 'polygon'
  LatLng? _selectedLocation;
  final List<LatLng> _polygonVertices = []; // קודקודי הפוליגון
  final List<String> _labels = [];
  final MapController _mapController = MapController();
  bool _isSaving = false;
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
  List<Checkpoint> _existingCheckpoints = [];
  List<SafetyPoint> _safetyPoints = [];
  List<Boundary> _boundaries = [];
  List<Cluster> _clusters = [];

  // מיקום ברירת מחדל - מרכז ישראל
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
        _existingCheckpoints = checkpoints;
        _safetyPoints = safetyPoints;
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
    _latController.dispose();
    _lngController.dispose();
    _utmController.dispose();
    _labelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('נקודת ציון חדשה - ${widget.area.name}'),
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
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
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
              icon: const Icon(Icons.save),
              onPressed: _saveCheckpoint,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // שם הנקודה
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'שם הנקודה',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.label),
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
              maxLines: 2,
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
                  return 'יש להזין מספר תקין';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // סוג הנקודה
            DropdownButtonFormField<String>(
              value: _selectedType,
              decoration: const InputDecoration(
                labelText: 'סוג הנקודה',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.category),
              ),
              items: const [
                DropdownMenuItem(value: 'checkpoint', child: Text('נקודת ציון')),
                DropdownMenuItem(value: 'mandatory_passage', child: Text('נקודת מעבר חובה')),
                DropdownMenuItem(value: 'start', child: Text('נקודת התחלה')),
                DropdownMenuItem(value: 'end', child: Text('נקודת סיום')),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedType = value!;
                });
              },
            ),
            const SizedBox(height: 16),

            // צבע הנקודה
            DropdownButtonFormField<String>(
              value: _selectedColor,
              decoration: const InputDecoration(
                labelText: 'צבע',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.palette),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'blue',
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.blue,
                        radius: 10,
                      ),
                      SizedBox(width: 8),
                      Text('כחול'),
                    ],
                  ),
                ),
                DropdownMenuItem(
                  value: 'green',
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.green,
                        radius: 10,
                      ),
                      SizedBox(width: 8),
                      Text('ירוק'),
                    ],
                  ),
                ),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedColor = value!;
                });
              },
            ),
            const SizedBox(height: 24),

            // תוויות/תאי שטח
            Text(
              'תוויות ותאי שטח',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _labelController,
                    decoration: const InputDecoration(
                      labelText: 'הוסף תווית',
                      border: OutlineInputBorder(),
                      hintText: 'לדוגמה: תא-1, מגזר-A',
                    ),
                    onSubmitted: (_) => _addLabel(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _addLabel,
                  icon: const Icon(Icons.add),
                  label: const Text('הוסף'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_labels.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _labels.map((label) {
                  return Chip(
                    label: Text(label),
                    deleteIcon: const Icon(Icons.close, size: 18),
                    onDeleted: () {
                      setState(() {
                        _labels.remove(label);
                      });
                    },
                  );
                }).toList(),
              ),
            const SizedBox(height: 24),

            // בחירת סוג גאומטריה
            Text(
              'גאומטריה',
              style: Theme.of(context).textTheme.titleLarge,
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
                  // איפוס בחירת מיקום בעת מעבר בין מצבים
                  _selectedLocation = null;
                  _polygonVertices.clear();
                  _latController.clear();
                  _lngController.clear();
                });
              },
            ),
            const SizedBox(height: 16),

            // מפה לבחירת מיקום
            Container(
              height: 300,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
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
                            setState(() {
                              _polygonVertices.add(point);
                            });
                          } else {
                            setState(() {
                              _selectedLocation = point;
                              _latController.text = point.latitude.toStringAsFixed(6);
                              _lngController.text = point.longitude.toStringAsFixed(6);
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
                        // שכבת נקודות ציון קיימות — נקודתיות
                        if (_showOtherLayers && _showNZ && _existingCheckpoints.isNotEmpty)
                          MarkerLayer(
                            markers: _existingCheckpoints
                                .where((cp) => !cp.isPolygon && cp.coordinates != null)
                                .map((cp) {
                              return Marker(
                                point: LatLng(cp.coordinates!.lat, cp.coordinates!.lng),
                                width: 30,
                                height: 30,
                                child: Opacity(
                                  opacity: _nzOpacity,
                                  child: Icon(
                                    Icons.place,
                                    color: (cp.color == 'blue' ? Colors.blue : Colors.green).withOpacity(0.6),
                                    size: 30,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        // שכבת נקודות ציון קיימות — פוליגוניות
                        if (_showOtherLayers && _showNZ)
                          PolygonLayer(
                            polygons: _existingCheckpoints
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
                        // שכבת נקודות תורפה בטיחותיות (נת"ב)
                        if (_showOtherLayers && _showNB && _safetyPoints.isNotEmpty)
                          MarkerLayer(
                            markers: _safetyPoints
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
                        // הנקודה/פוליגון החדש/ה שנבחר/ה
                        if (!_isPolygonMode && _selectedLocation != null)
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: _selectedLocation!,
                                width: 40,
                                height: 40,
                                child: Icon(
                                  Icons.place,
                                  color: _selectedColor == 'blue' ? Colors.blue : Colors.green,
                                  size: 40,
                                ),
                              ),
                            ],
                          ),
                        // פוליגון חדש — קודקודים + צורה
                        if (_isPolygonMode && _polygonVertices.isNotEmpty) ...[
                          PolygonLayer(
                            polygons: _polygonVertices.length >= 3
                                ? [
                                    Polygon(
                                      points: _polygonVertices,
                                      color: (_selectedColor == 'blue' ? Colors.blue : Colors.green)
                                          .withOpacity(0.2),
                                      borderColor: _selectedColor == 'blue' ? Colors.blue : Colors.green,
                                      borderStrokeWidth: 2.5,
                                      isFilled: true,
                                    ),
                                  ]
                                : [],
                          ),
                          // קו בין קודקודים (אם < 3)
                          if (_polygonVertices.length >= 2 && _polygonVertices.length < 3)
                            PolylineLayer(
                              polylines: [
                                Polyline(
                                  points: _polygonVertices,
                                  color: _selectedColor == 'blue' ? Colors.blue : Colors.green,
                                  strokeWidth: 2.5,
                                ),
                              ],
                            ),
                          // סמנים על הקודקודים
                          MarkerLayer(
                            markers: _polygonVertices.asMap().entries.map((entry) {
                              final idx = entry.key;
                              final vertex = entry.value;
                              return Marker(
                                point: vertex,
                                width: 24,
                                height: 24,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: _selectedColor == 'blue' ? Colors.blue : Colors.green,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${idx + 1}',
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
            const SizedBox(height: 8),

            // הנחיות ופקדי פוליגון
            if (_isPolygonMode) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _polygonVertices.length < 3
                        ? 'לחץ על המפה להוספת קודקודים (${_polygonVertices.length}/3 מינימום)'
                        : 'פוליגון עם ${_polygonVertices.length} קודקודים',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                  ),
                ],
              ),
            ] else ...[
              Text(
                'לחץ על המפה לבחירת מיקום',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[600],
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              // קואורדינטות ידניות (רק במצב נקודה)
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _latController,
                      decoration: const InputDecoration(
                        labelText: 'קו רוחב (Lat)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (value) {
                        final lat = double.tryParse(value);
                        final lng = double.tryParse(_lngController.text);
                        if (lat != null && lng != null) {
                          setState(() {
                            _selectedLocation = LatLng(lat, lng);
                            _mapController.move(_selectedLocation!, 12);
                          });
                        }
                      },
                      validator: (value) {
                        if (!_isPolygonMode) {
                          if (value == null || value.isEmpty) {
                            return 'נדרש';
                          }
                          if (double.tryParse(value) == null) {
                            return 'מספר לא תקין';
                          }
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _lngController,
                      decoration: const InputDecoration(
                        labelText: 'קו אורך (Lng)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (value) {
                        final lat = double.tryParse(_latController.text);
                        final lng = double.tryParse(value);
                        if (lat != null && lng != null) {
                          setState(() {
                            _selectedLocation = LatLng(lat, lng);
                            _mapController.move(_selectedLocation!, 12);
                          });
                        }
                      },
                      validator: (value) {
                        if (!_isPolygonMode) {
                          if (value == null || value.isEmpty) {
                            return 'נדרש';
                          }
                          if (double.tryParse(value) == null) {
                            return 'מספר לא תקין';
                          }
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // UTM (אופציונלי)
              TextFormField(
                controller: _utmController,
                decoration: const InputDecoration(
                  labelText: 'UTM (אופציונלי)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.grid_on),
                  hintText: 'לדוגמה: 36R 123456 7654321',
                ),
              ),
              const SizedBox(height: 16),

              // כפתור למיקום נוכחי
              OutlinedButton.icon(
                onPressed: _useCurrentLocation,
                icon: const Icon(Icons.my_location),
                label: const Text('השתמש במיקום הנוכחי'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _addLabel() {
    if (_labelController.text.isNotEmpty) {
      setState(() {
        _labels.add(_labelController.text);
        _labelController.clear();
      });
    }
  }

  Future<void> _useCurrentLocation() async {
    // TODO: שימוש ב-GPS Service לקבלת מיקום נוכחי
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('קבלת מיקום נוכחי - בפיתוח'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  Future<void> _saveCheckpoint() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // ולידציה לפי סוג גאומטריה
    if (_isPolygonMode) {
      if (_polygonVertices.length < 3) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('פוליגון חייב להכיל לפחות 3 קודקודים'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    } else {
      if (_selectedLocation == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('יש לבחור מיקום על המפה'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    setState(() => _isSaving = true);

    try {
      final authService = AuthService();
      final currentUser = await authService.getCurrentUser();
      if (currentUser == null) {
        throw Exception('משתמש לא מחובר');
      }

      final checkpoint = Checkpoint(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        areaId: widget.area.id,
        name: _nameController.text,
        description: _descriptionController.text,
        type: _selectedType,
        color: _selectedColor,
        geometryType: _geometryType,
        sequenceNumber: int.parse(_sequenceController.text),
        coordinates: !_isPolygonMode
            ? Coordinate(
                lat: _selectedLocation!.latitude,
                lng: _selectedLocation!.longitude,
                utm: _utmController.text.isEmpty ? '' : _utmController.text,
              )
            : null,
        polygonCoordinates: _isPolygonMode
            ? _polygonVertices
                .map((v) => Coordinate(
                      lat: v.latitude,
                      lng: v.longitude,
                      utm: '',
                    ))
                .toList()
            : null,
        labels: _labels,
        createdBy: currentUser.uid,
        createdAt: DateTime.now(),
      );

      final repository = CheckpointRepository();
      await repository.create(checkpoint);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('נקודת ציון נוצרה בהצלחה'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה ביצירה: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  /// צבע נקודת בטיחות — תמיד אדום
  Color _getSeverityColor(String severity) {
    return Colors.red;
  }
}
