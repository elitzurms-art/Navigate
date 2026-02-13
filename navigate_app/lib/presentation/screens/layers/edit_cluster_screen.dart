import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../domain/entities/area.dart';
import '../../../domain/entities/cluster.dart';
import '../../../domain/entities/coordinate.dart';
import '../../../data/repositories/cluster_repository.dart';
import '../../widgets/map_with_selector.dart';
import '../../widgets/map_controls.dart';

/// מסך עריכת ביצת איזור
class EditClusterScreen extends StatefulWidget {
  final Area area;
  final Cluster cluster;

  const EditClusterScreen({
    super.key,
    required this.area,
    required this.cluster,
  });

  @override
  State<EditClusterScreen> createState() => _EditClusterScreenState();
}

class _EditClusterScreenState extends State<EditClusterScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  final MapController _mapController = MapController();
  final ClusterRepository _repository = ClusterRepository();

  late List<LatLng> _polygonPoints;
  bool _isLoading = false;
  bool _measureMode = false;
  final List<LatLng> _measurePoints = [];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.cluster.name);
    _descriptionController = TextEditingController(text: widget.cluster.description);
    _polygonPoints = widget.cluster.coordinates
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

      final updatedCluster = widget.cluster.copyWith(
        name: _nameController.text,
        description: _descriptionController.text,
        coordinates: coordinates,
        updatedAt: DateTime.now(),
      );

      await _repository.update(updatedCluster);

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ביצת איזור עודכנה בהצלחה')),
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
        title: Text('עריכת ביצה - ${widget.area.name}'),
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
                      'נקודות: ${_polygonPoints.length} (לחץ על המפה להוסיף)',
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
