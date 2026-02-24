import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../domain/entities/area.dart';
import '../../../domain/entities/boundary.dart';
import '../../../domain/entities/coordinate.dart';
import '../../../data/repositories/boundary_repository.dart';
import '../../widgets/map_with_selector.dart';
import '../../widgets/map_controls.dart';

/// מסך עריכת גבול גזרה
class EditBoundaryScreen extends StatefulWidget {
  final Area area;
  final Boundary boundary;

  const EditBoundaryScreen({
    super.key,
    required this.area,
    required this.boundary,
  });

  @override
  State<EditBoundaryScreen> createState() => _EditBoundaryScreenState();
}

class _EditBoundaryScreenState extends State<EditBoundaryScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  final MapController _mapController = MapController();
  final BoundaryRepository _repository = BoundaryRepository();

  late List<LatLng> _polygonPoints;
  bool _isLoading = false;
  bool _measureMode = false;
  final List<LatLng> _measurePoints = [];
  int? _selectedPointIndex;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.boundary.name);
    _descriptionController = TextEditingController(text: widget.boundary.description);
    _polygonPoints = widget.boundary.coordinates
        .map((c) => LatLng(c.lat, c.lng))
        .toList();

    // התמקד באזור הפוליגון
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_polygonPoints.isNotEmpty) {
        final latitudes = _polygonPoints.map((p) => p.latitude).toList();
        final longitudes = _polygonPoints.map((p) => p.longitude).toList();

        final minLat = latitudes.reduce((a, b) => a < b ? a : b);
        final maxLat = latitudes.reduce((a, b) => a > b ? a : b);
        final minLng = longitudes.reduce((a, b) => a < b ? a : b);
        final maxLng = longitudes.reduce((a, b) => a > b ? a : b);

        final center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
        _mapController.move(center, 12);
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _addPoint(LatLng point) {
    setState(() {
      if (_selectedPointIndex != null) {
        _polygonPoints[_selectedPointIndex!] = point;
        _selectedPointIndex = null;
      } else {
        _polygonPoints.add(point);
      }
    });
  }

  void _undoLastPoint() {
    if (_polygonPoints.isNotEmpty) {
      setState(() {
        _selectedPointIndex = null;
        _polygonPoints.removeLast();
      });
    }
  }

  void _clearPoints() {
    setState(() {
      _selectedPointIndex = null;
      _polygonPoints.clear();
    });
  }

  void _deletePoint(int index) {
    setState(() {
      _polygonPoints.removeAt(index);
      _selectedPointIndex = null;
    });
  }

  void _insertMidpoint(int afterIndex) {
    final a = _polygonPoints[afterIndex];
    final b = _polygonPoints[(afterIndex + 1) % _polygonPoints.length];
    final mid = LatLng(
      (a.latitude + b.latitude) / 2,
      (a.longitude + b.longitude) / 2,
    );
    setState(() {
      final insertIndex = afterIndex + 1;
      if (insertIndex >= _polygonPoints.length) {
        _polygonPoints.add(mid);
        _selectedPointIndex = _polygonPoints.length - 1;
      } else {
        _polygonPoints.insert(insertIndex, mid);
        _selectedPointIndex = insertIndex;
      }
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

      final updatedBoundary = widget.boundary.copyWith(
        name: _nameController.text,
        description: _descriptionController.text,
        coordinates: coordinates,
        updatedAt: DateTime.now(),
      );

      await _repository.update(updatedBoundary);

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('גבול גזרה עודכן בהצלחה')),
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
        title: Text('עריכת גבול - ${widget.area.name}'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
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
                      labelText: 'שם הגבול',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.border_all),
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
              color: Colors.grey[200],
              child: Row(
                children: [
                  Icon(
                    _selectedPointIndex != null ? Icons.open_with : Icons.touch_app,
                    size: 20,
                    color: _selectedPointIndex != null ? Colors.green[700] : Colors.grey[700],
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _selectedPointIndex != null
                          ? 'לחץ על המפה להזיז נקודה ${_selectedPointIndex! + 1}'
                          : _polygonPoints.isEmpty
                              ? 'לחץ על המפה להוסיף נקודות'
                              : 'נקודות: ${_polygonPoints.length}',
                      style: TextStyle(
                        color: _selectedPointIndex != null ? Colors.green[700] : Colors.grey[700],
                        fontWeight: _selectedPointIndex != null ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                  if (_selectedPointIndex != null)
                    IconButton(
                      icon: Icon(Icons.close, size: 20, color: Colors.green[700]),
                      onPressed: () => setState(() => _selectedPointIndex = null),
                      tooltip: 'בטל בחירה',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  if (_polygonPoints.isNotEmpty) ...[
                    IconButton(
                      icon: const Icon(Icons.undo, size: 20),
                      onPressed: _undoLastPoint,
                      tooltip: 'בטל נקודה אחרונה',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.clear, size: 20),
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
                      initialCenter: const LatLng(31.5, 34.75),
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
                      if (_polygonPoints.length >= 2)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: _polygonPoints,
                              color: Colors.black,
                              strokeWidth: 3,
                            ),
                          ],
                        ),
                      if (_polygonPoints.length >= 3)
                        PolygonLayer(
                          polygons: [
                            Polygon(
                              points: _polygonPoints,
                              color: Colors.black.withOpacity(0.1),
                              borderColor: Colors.black,
                              borderStrokeWidth: 3,
                              isFilled: true,
                            ),
                          ],
                        ),
                      // נקודות אמצע — כפתורי "+" להוספת נקודה חדשה
                      if (_polygonPoints.length >= 3)
                        MarkerLayer(
                          markers: List.generate(_polygonPoints.length, (i) {
                            final a = _polygonPoints[i];
                            final b = _polygonPoints[(i + 1) % _polygonPoints.length];
                            final midLat = (a.latitude + b.latitude) / 2;
                            final midLng = (a.longitude + b.longitude) / 2;
                            return Marker(
                              point: LatLng(midLat, midLng),
                              width: 22,
                              height: 22,
                              child: GestureDetector(
                                onTap: () => _insertMidpoint(i),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withValues(alpha: 0.5),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 1.5),
                                  ),
                                  child: const Center(
                                    child: Icon(Icons.add, size: 14, color: Colors.white),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      if (_polygonPoints.isNotEmpty)
                        MarkerLayer(
                          markers: _polygonPoints.asMap().entries.map((entry) {
                            final isSelected = _selectedPointIndex == entry.key;
                            return Marker(
                              point: entry.value,
                              width: isSelected ? 34 : 30,
                              height: isSelected ? 34 : 30,
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    if (_selectedPointIndex == entry.key) {
                                      _selectedPointIndex = null;
                                    } else {
                                      _selectedPointIndex = entry.key;
                                    }
                                  });
                                },
                                onLongPress: () => _deletePoint(entry.key),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: isSelected ? Colors.green : Colors.black,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isSelected ? Colors.greenAccent : Colors.white,
                                      width: isSelected ? 3 : 2,
                                    ),
                                    boxShadow: isSelected
                                        ? [BoxShadow(color: Colors.green.withValues(alpha: 0.5), blurRadius: 8, spreadRadius: 2)]
                                        : null,
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
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
