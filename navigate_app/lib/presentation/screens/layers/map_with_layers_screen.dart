import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../domain/entities/area.dart';
import '../../../domain/entities/checkpoint.dart';
import '../../../domain/entities/safety_point.dart';
import '../../../domain/entities/boundary.dart';
import '../../../domain/entities/cluster.dart';
import '../../../data/repositories/checkpoint_repository.dart';
import '../../../data/repositories/safety_point_repository.dart';
import '../../../data/repositories/boundary_repository.dart';
import '../../../data/repositories/cluster_repository.dart';
import '../../widgets/map_with_selector.dart';
import '../../widgets/map_controls.dart';

/// מסך מפה עם בקרת שכבות
class MapWithLayersScreen extends StatefulWidget {
  final Area area;

  const MapWithLayersScreen({super.key, required this.area});

  @override
  State<MapWithLayersScreen> createState() => _MapWithLayersScreenState();
}

class _MapWithLayersScreenState extends State<MapWithLayersScreen> {
  final MapController _mapController = MapController();
  final CheckpointRepository _checkpointRepository = CheckpointRepository();
  final SafetyPointRepository _safetyPointRepository = SafetyPointRepository();
  final BoundaryRepository _boundaryRepository = BoundaryRepository();
  final ClusterRepository _clusterRepository = ClusterRepository();

  // מצב שכבות
  bool _showNZ = true;
  bool _showNB = false;
  bool _showGG = false;
  bool _showBA = false;

  // שקיפות שכבות (0.0 - 1.0)
  double _nzOpacity = 1.0;
  double _nbOpacity = 1.0;
  double _ggOpacity = 0.5;
  double _baOpacity = 0.5;

  // נתונים
  List<Checkpoint> _checkpoints = [];
  List<SafetyPoint> _safetyPoints = [];
  List<Boundary> _boundaries = [];
  List<Cluster> _clusters = [];
  bool _isLoading = true;
  bool _showLayerControls = false;

  bool _measureMode = false;
  final List<LatLng> _measurePoints = [];

  static const LatLng _defaultCenter = LatLng(31.5, 34.75);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // טעינת כל השכבות במקביל
      final results = await Future.wait([
        _checkpointRepository.getByArea(widget.area.id),
        _safetyPointRepository.getByArea(widget.area.id),
        _boundaryRepository.getByArea(widget.area.id),
        _clusterRepository.getByArea(widget.area.id),
      ]);

      setState(() {
        _checkpoints = results[0] as List<Checkpoint>;
        _safetyPoints = results[1] as List<SafetyPoint>;
        _boundaries = results[2] as List<Boundary>;
        _clusters = results[3] as List<Cluster>;
        _isLoading = false;
      });

      // התמקד באזור הנקודות
      if (_checkpoints.isNotEmpty) {
        final latitudes = _checkpoints.map((c) => c.coordinates.lat).toList();
        final longitudes = _checkpoints.map((c) => c.coordinates.lng).toList();

        final minLat = latitudes.reduce((a, b) => a < b ? a : b);
        final maxLat = latitudes.reduce((a, b) => a > b ? a : b);
        final minLng = longitudes.reduce((a, b) => a < b ? a : b);
        final maxLng = longitudes.reduce((a, b) => a > b ? a : b);

        final center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
        _mapController.move(center, 12);
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('מפה - ${widget.area.name}'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_showLayerControls ? Icons.layers_clear : Icons.layers),
            onPressed: () {
              setState(() {
                _showLayerControls = !_showLayerControls;
              });
            },
            tooltip: 'בקרת שכבות',
          ),
        ],
      ),
      body: Stack(
        children: [
          // המפה
          MapWithTypeSelector(
            mapController: _mapController,
            showTypeSelector: false,
            options: MapOptions(
              initialCenter: _defaultCenter,
              initialZoom: 8,
              onTap: (tapPosition, point) {
                if (_measureMode) {
                  setState(() => _measurePoints.add(point));
                  return;
                }
              },
            ),
            layers: [

              // שכבת נ"ז - נקודות ציון (עיגול כחול/ירוק עם מספר)
              if (_showNZ && _checkpoints.isNotEmpty)
                MarkerLayer(
                  markers: _checkpoints.map((checkpoint) {
                    final isNavigatorCheckpoint = checkpoint.color == 'blue';
                    final markerColor = isNavigatorCheckpoint ? Colors.blue : Colors.green;
                    return Marker(
                      point: LatLng(
                        checkpoint.coordinates.lat,
                        checkpoint.coordinates.lng,
                      ),
                      width: 32,
                      height: 32,
                      child: Opacity(
                        opacity: _nzOpacity,
                        child: Container(
                          decoration: BoxDecoration(
                            color: markerColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: Center(
                            child: Text(
                              '${checkpoint.sequenceNumber}',
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

              // שכבת נת"ב - נקודות תורפה בטיחותיות (נקודות)
              if (_showNB && _safetyPoints.where((p) => p.type == 'point').isNotEmpty)
                MarkerLayer(
                  markers: _safetyPoints
                      .where((p) => p.type == 'point' && p.coordinates != null)
                      .map((point) {
                    return Marker(
                      point: LatLng(
                        point.coordinates!.lat,
                        point.coordinates!.lng,
                      ),
                      width: 40,
                      height: 50,
                      child: Opacity(
                        opacity: _nbOpacity,
                        child: Column(
                          children: [
                            Icon(
                              Icons.warning,
                              color: _getSeverityColor(point.severity),
                              size: 32,
                            ),
                            Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${point.sequenceNumber}',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),

              // שכבת נת"ב - נקודות תורפה בטיחותיות (פוליגונים אדומים)
              if (_showNB && _safetyPoints.where((p) => p.type == 'polygon').isNotEmpty)
                PolygonLayer(
                  polygons: _safetyPoints
                      .where((p) => p.type == 'polygon' && p.polygonCoordinates != null)
                      .map((point) {
                    return Polygon(
                      points: point.polygonCoordinates!
                          .map((c) => LatLng(c.lat, c.lng))
                          .toList(),
                      color: Colors.red.withOpacity(0.2 * _nbOpacity),
                      borderColor: Colors.red.withOpacity(_nbOpacity),
                      borderStrokeWidth: 3,
                      isFilled: true,
                    );
                  }).toList(),
                ),

              // שכבת ג"ג - גבול גזרה (שחור)
              if (_showGG && _boundaries.isNotEmpty)
                PolygonLayer(
                  polygons: _boundaries.map((boundary) {
                    return Polygon(
                      points: boundary.coordinates.map((c) => LatLng(c.lat, c.lng)).toList(),
                      color: Colors.black.withOpacity(0.1 * _ggOpacity),
                      borderColor: Colors.black.withOpacity(_ggOpacity),
                      borderStrokeWidth: boundary.strokeWidth,
                      isFilled: true,
                    );
                  }).toList(),
                ),

              // שכבת ב"א - ביצי איזור
              if (_showBA && _clusters.isNotEmpty)
                PolygonLayer(
                  polygons: _clusters.map((cluster) {
                    return Polygon(
                      points: cluster.coordinates.map((c) => LatLng(c.lat, c.lng)).toList(),
                      color: Colors.green.withOpacity(cluster.fillOpacity * _baOpacity),
                      borderColor: Colors.green.withOpacity(_baOpacity),
                      borderStrokeWidth: cluster.strokeWidth,
                      isFilled: true,
                    );
                  }).toList(),
                ),
              ...MapControls.buildMeasureLayers(_measurePoints),
            ],
          ),

          // בקרי מפה
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

          // אינדיקטור טעינה
          if (_isLoading)
            Container(
              color: Colors.black26,
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),

          // פאנל בקרת שכבות
          if (_showLayerControls)
            Positioned(
              top: 10,
              left: 10,
              child: Container(
                width: 300,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // כותרת
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(12),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.layers, color: Colors.white),
                          const SizedBox(width: 8),
                          const Text(
                            'בקרת שכבות',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white, size: 20),
                            onPressed: () {
                              setState(() {
                                _showLayerControls = false;
                              });
                            },
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),

                    // שכבת נ"ז
                    _buildLayerControl(
                      title: 'נ"ז - נקודות ציון',
                      subtitle: '${_checkpoints.length} נקודות',
                      color: Colors.blue,
                      isVisible: _showNZ,
                      opacity: _nzOpacity,
                      onVisibilityChanged: (value) {
                        setState(() => _showNZ = value);
                      },
                      onOpacityChanged: (value) {
                        setState(() => _nzOpacity = value);
                      },
                    ),

                    const Divider(height: 1),

                    // שכבת נת"ב
                    _buildLayerControl(
                      title: 'נת"ב - נקודות תורפה בטיחותיות',
                      subtitle: _safetyPoints.isEmpty ? 'אין נקודות' : '${_safetyPoints.length} נקודות',
                      color: Colors.red,
                      isVisible: _showNB,
                      opacity: _nbOpacity,
                      onVisibilityChanged: (value) {
                        setState(() => _showNB = value);
                      },
                      onOpacityChanged: (value) {
                        setState(() => _nbOpacity = value);
                      },
                    ),

                    const Divider(height: 1),

                    // שכבת ג"ג
                    _buildLayerControl(
                      title: 'ג"ג - גבול גזרה',
                      subtitle: _boundaries.isEmpty ? 'אין גבולות' : '${_boundaries.length} גבולות',
                      color: Colors.black,
                      isVisible: _showGG,
                      opacity: _ggOpacity,
                      onVisibilityChanged: (value) {
                        setState(() => _showGG = value);
                      },
                      onOpacityChanged: (value) {
                        setState(() => _ggOpacity = value);
                      },
                    ),

                    const Divider(height: 1),

                    // שכבת ב"א
                    _buildLayerControl(
                      title: 'ב"א - ביצי איזור',
                      subtitle: _clusters.isEmpty ? 'אין ביצות' : '${_clusters.length} ביצות',
                      color: Colors.green,
                      isVisible: _showBA,
                      opacity: _baOpacity,
                      onVisibilityChanged: (value) {
                        setState(() => _showBA = value);
                      },
                      onOpacityChanged: (value) {
                        setState(() => _baOpacity = value);
                      },
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // כפתור zoom in
          FloatingActionButton(
            heroTag: 'zoom_in',
            mini: true,
            onPressed: () {
              final zoom = _mapController.camera.zoom + 1;
              _mapController.move(_mapController.camera.center, zoom);
            },
            child: const Icon(Icons.add),
          ),
          const SizedBox(height: 8),
          // כפתור zoom out
          FloatingActionButton(
            heroTag: 'zoom_out',
            mini: true,
            onPressed: () {
              final zoom = _mapController.camera.zoom - 1;
              _mapController.move(_mapController.camera.center, zoom);
            },
            child: const Icon(Icons.remove),
          ),
        ],
      ),
    );
  }

  Widget _buildLayerControl({
    required String title,
    required String subtitle,
    required Color color,
    required bool isVisible,
    required double opacity,
    required ValueChanged<bool> onVisibilityChanged,
    required ValueChanged<double> onOpacityChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: color.withOpacity(0.2),
                radius: 16,
                child: Icon(Icons.layers, color: color, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: isVisible,
                onChanged: onVisibilityChanged,
                activeColor: color,
              ),
            ],
          ),
          if (isVisible) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const SizedBox(width: 44),
                const Icon(Icons.opacity, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: Slider(
                    value: opacity,
                    min: 0.0,
                    max: 1.0,
                    divisions: 100,
                    label: '${(opacity * 100).round()}%',
                    activeColor: color,
                    onChanged: onOpacityChanged,
                  ),
                ),
                SizedBox(
                  width: 40,
                  child: Text(
                    '${(opacity * 100).round()}%',
                    style: const TextStyle(fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// קבלת צבע לנקודת בטיחות — תמיד אדום (ללא צבע לפי חומרה)
  Color _getSeverityColor(String severity) {
    return Colors.red;
  }
}
