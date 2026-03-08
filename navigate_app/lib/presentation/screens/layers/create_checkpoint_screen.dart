import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../domain/entities/area.dart';
import '../../../domain/entities/checkpoint.dart';
import '../../../domain/entities/coordinate.dart';
import '../../../domain/entities/safety_point.dart';
import '../../../domain/entities/boundary.dart';
import '../../../data/repositories/checkpoint_repository.dart';
import '../../../data/repositories/safety_point_repository.dart';
import '../../../data/repositories/boundary_repository.dart';
import '../../../services/auth_service.dart';
import '../../../core/utils/utm_converter.dart';
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
  final _descriptionController = TextEditingController();
  final _sequenceController = TextEditingController();
  final _eastingController = TextEditingController();
  final _northingController = TextEditingController();

  final CheckpointRepository _checkpointRepo = CheckpointRepository();
  final SafetyPointRepository _safetyPointRepo = SafetyPointRepository();
  final BoundaryRepository _boundaryRepo = BoundaryRepository();

  String _selectedType = 'checkpoint';
  String _geometryType = 'point'; // 'point' או 'polygon'
  LatLng? _selectedLocation;
  final List<LatLng> _polygonVertices = []; // קודקודי הפוליגון
  final MapController _mapController = MapController();
  bool _isSaving = false;
  bool _showOtherLayers = true;
  bool _showGG = true;
  bool _showNZ = true;
  bool _showNB = true;
  double _ggOpacity = 1.0;
  double _nzOpacity = 1.0;
  double _nbOpacity = 1.0;
  bool _measureMode = false;
  final List<LatLng> _measurePoints = [];

  // שכבות אחרות
  List<Checkpoint> _existingCheckpoints = [];
  List<SafetyPoint> _safetyPoints = [];
  List<Boundary> _boundaries = [];

  // מיקום ברירת מחדל - מרכז ישראל
  static const LatLng _defaultCenter = LatLng(31.5, 34.75);

  bool get _isPolygonMode => _geometryType == 'polygon';

  Color get _typeColor => Checkpoint.flutterColorForType(_selectedType);

  int get _nextAvailableSequence {
    final usedNumbers = _existingCheckpoints.map((cp) => cp.sequenceNumber).toSet();
    int candidate = 1;
    while (usedNumbers.contains(candidate)) {
      candidate++;
    }
    return candidate;
  }

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

      setState(() {
        _existingCheckpoints = checkpoints;
        _safetyPoints = safetyPoints;
        _boundaries = boundaries;
      });
    } catch (e) {
      print('שגיאה בטעינת שכבות: $e');
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _sequenceController.dispose();
    _eastingController.dispose();
    _northingController.dispose();
    super.dispose();
  }

  void _updateLocationFromUtm() {
    final easting = _eastingController.text;
    final northing = _northingController.text;
    if (easting.length == 6 && northing.length == 6 &&
        int.tryParse(easting) != null && int.tryParse(northing) != null) {
      try {
        final utmString = easting + northing;
        final latLng = UtmConverter.utmToLatLng(utmString);
        setState(() {
          _selectedLocation = latLng;
          _mapController.move(latLng, 14);
        });
      } catch (_) {}
    }
  }

  void _updateUtmFromLocation(LatLng point) {
    try {
      final utmString = UtmConverter.latLngToUtm(point);
      if (utmString.length == 12) {
        _eastingController.text = utmString.substring(0, 6);
        _northingController.text = utmString.substring(6, 12);
      }
    } catch (_) {}
  }

  Future<void> _openGoogleMaps() async {
    if (_selectedLocation == null) return;
    final url = Uri.parse(
      'https://www.google.com/maps?q=${_selectedLocation!.latitude},${_selectedLocation!.longitude}',
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
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
              decoration: InputDecoration(
                labelText: 'מספר סידורי',
                hintText: '$_nextAvailableSequence',
                hintStyle: const TextStyle(color: Colors.grey),
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.numbers),
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'נא להזין מספר';
                }
                final num = int.tryParse(value);
                if (num == null) {
                  return 'יש להזין מספר תקין';
                }
                // בדיקת ייחודיות מספר סידורי באזור
                final duplicate = _existingCheckpoints.any(
                  (cp) => cp.sequenceNumber == num,
                );
                if (duplicate) {
                  return 'מספר סידורי $num כבר קיים באזור זה';
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
            const SizedBox(height: 8),
            // תצוגת צבע אוטומטי
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: _typeColor,
                  radius: 10,
                ),
                const SizedBox(width: 8),
                Text(
                  'צבע: ${_getColorName(Checkpoint.colorForType(_selectedType))}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

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
                  _eastingController.clear();
                  _northingController.clear();
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
                              _updateUtmFromLocation(point);
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
                                    color: Checkpoint.flutterColor(cp.color).withOpacity(0.6),
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
                              final color = Checkpoint.flutterColor(cp.color);
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
                                    color: Colors.red.withOpacity(0.6),
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
                                  color: _typeColor,
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
                                      color: _typeColor.withOpacity(0.2),
                                      borderColor: _typeColor,
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
                                  color: _typeColor,
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
                                    color: _typeColor,
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

              // שדות UTM (רק במצב נקודה)
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _northingController,
                      decoration: const InputDecoration(
                        labelText: 'צפונה (Northing)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.grid_on),
                      ),
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      onChanged: (_) => _updateLocationFromUtm(),
                      validator: (value) {
                        if (_isPolygonMode || _selectedLocation != null) return null;
                        if (value == null || value.isEmpty) {
                          return 'נדרש (או לחץ על המפה)';
                        }
                        if (value.length != 6 || int.tryParse(value) == null) {
                          return '6 ספרות';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _eastingController,
                      decoration: const InputDecoration(
                        labelText: 'מזרחה (Easting)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.grid_on),
                      ),
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      onChanged: (_) => _updateLocationFromUtm(),
                      validator: (value) {
                        if (_isPolygonMode || _selectedLocation != null) return null;
                        if (value == null || value.isEmpty) {
                          return 'נדרש (או לחץ על המפה)';
                        }
                        if (value.length != 6 || int.tryParse(value) == null) {
                          return '6 ספרות';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // קישור לגוגל מפות
              if (_selectedLocation != null)
                InkWell(
                  onTap: _openGoogleMaps,
                  child: Row(
                    children: [
                      Icon(Icons.map, color: Colors.blue[700], size: 18),
                      const SizedBox(width: 4),
                      Text(
                        'פתח בגוגל מפות',
                        style: TextStyle(
                          color: Colors.blue[700],
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ],
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('יש לתקן את השדות המסומנים'),
          backgroundColor: Colors.orange,
        ),
      );
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

      final utmString = _eastingController.text + _northingController.text;
      final autoColor = Checkpoint.colorForType(_selectedType);

      final checkpoint = Checkpoint(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        areaId: widget.area.id,
        name: '',
        description: _descriptionController.text,
        type: _selectedType,
        color: autoColor,
        geometryType: _geometryType,
        sequenceNumber: int.parse(_sequenceController.text),
        coordinates: !_isPolygonMode
            ? Coordinate(
                lat: _selectedLocation!.latitude,
                lng: _selectedLocation!.longitude,
                utm: utmString,
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
        labels: const [],
        createdBy: currentUser.uid,
        createdAt: DateTime.now(),
      );

      await _checkpointRepo.create(checkpoint);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('הנקודה נשמרה — #${checkpoint.sequenceNumber}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בשמירה: $e'),
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

  String _getColorName(String colorString) {
    switch (colorString) {
      case 'blue':
        return 'כחול';
      case 'green':
        return 'ירוק';
      case 'red':
        return 'אדום';
      case 'yellow':
        return 'צהוב';
      default:
        return colorString;
    }
  }
}
