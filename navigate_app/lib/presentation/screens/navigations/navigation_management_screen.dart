import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../../../domain/entities/navigation.dart' as domain;
import '../../../domain/entities/checkpoint.dart';
import '../../../domain/entities/checkpoint_punch.dart';
import '../../../domain/entities/boundary.dart';
import '../../../data/repositories/checkpoint_repository.dart';
import '../../../data/repositories/boundary_repository.dart';
import '../../../data/repositories/navigation_repository.dart';
import '../../../core/utils/geometry_utils.dart';
import '../../../services/gps_tracking_service.dart';
import '../../widgets/map_with_selector.dart';

/// מסך ניהול ניווט פעיל (למפקד)
class NavigationManagementScreen extends StatefulWidget {
  final domain.Navigation navigation;

  const NavigationManagementScreen({
    super.key,
    required this.navigation,
  });

  @override
  State<NavigationManagementScreen> createState() => _NavigationManagementScreenState();
}

class _NavigationManagementScreenState extends State<NavigationManagementScreen>
    with SingleTickerProviderStateMixin {
  final CheckpointRepository _checkpointRepo = CheckpointRepository();
  final BoundaryRepository _boundaryRepo = BoundaryRepository();
  final NavigationRepository _navRepo = NavigationRepository();
  final MapController _mapController = MapController();

  late TabController _tabController;

  List<Checkpoint> _checkpoints = [];
  Boundary? _boundary;
  bool _isLoading = false;

  // מנווטים נבחרים לתצוגה
  Map<String, bool> _selectedNavigators = {};

  // מיקומים בזמן אמת (סימולציה)
  Map<String, NavigatorLiveData> _navigatorData = {};

  // שכבות
  bool _showNZ = true;
  bool _showGG = true;
  bool _showTracks = true;
  bool _showPunches = true;

  double _nzOpacity = 1.0;
  double _ggOpacity = 0.5;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
    _initializeNavigators();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final checkpoints = await _checkpointRepo.getByArea(widget.navigation.areaId);

      Boundary? boundary;
      if (widget.navigation.boundaryLayerId != null) {
        boundary = await _boundaryRepo.getById(widget.navigation.boundaryLayerId!);
      }

      setState(() {
        _checkpoints = checkpoints;
        _boundary = boundary;
        _isLoading = false;
      });

      if (boundary != null && boundary.coordinates.isNotEmpty) {
        final center = GeometryUtils.getPolygonCenter(boundary.coordinates);
        _mapController.move(LatLng(center.lat, center.lng), 13.0);
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _initializeNavigators() {
    for (final navigatorId in widget.navigation.routes.keys) {
      _selectedNavigators[navigatorId] = true;
      // TODO: בפועל יגיע מהשרת בזמן אמת
      _navigatorData[navigatorId] = NavigatorLiveData(
        navigatorId: navigatorId,
        isActive: false,
        currentPosition: null,
        trackPoints: [],
        punches: [],
        lastUpdate: null,
      );
    }
  }

  Future<void> _finishNavigatorNavigation(String navigatorId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('סיום ניווט למנווט'),
        content: Text('האם לסיים את הניווט עבור $navigatorId?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('סיים'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        _navigatorData[navigatorId]?.isActive = false;
      });

      // TODO: שמירה ב-DB

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('הניווט של $navigatorId הסתיים')),
        );
      }
    }
  }

  Future<void> _finishAllNavigation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('סיום ניווט כללי'),
        content: const Text(
          'האם לסיים את הניווט עבור כל המנווטים?\n\n'
          'פעולה זו תסיים את הניווט באופן סופי.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.red,
            ),
            child: const Text('סיים ניווט כללי'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // עדכון סטטוס ניווט
    final updatedNavigation = widget.navigation.copyWith(
      status: 'approval',
      activeStartTime: null,
      updatedAt: DateTime.now(),
    );
    await _navRepo.update(updatedNavigation);

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('הניווט הסתיים - מעבר למצב אישור'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _measureDistance() {
    // TODO: מדידת מרחק בין מנווטים
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('מדידת מרחק - בפיתוח')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.navigation.name),
            const Text(
              'ניהול ניווט',
              style: TextStyle(fontSize: 14),
            ),
          ],
        ),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.map), text: 'מפה'),
            Tab(icon: Icon(Icons.table_chart), text: 'סטטוס'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.straighten),
            tooltip: 'מדידת מרחק',
            onPressed: _measureDistance,
          ),
          IconButton(
            icon: const Icon(Icons.stop_circle),
            tooltip: 'סיום ניווט כללי',
            onPressed: _finishAllNavigation,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildMapView(),
                _buildStatusView(),
              ],
            ),
    );
  }

  Widget _buildMapView() {
    return Column(
      children: [
        // בקרת שכבות
        Container(
          padding: const EdgeInsets.all(8),
          color: Colors.grey[100],
          child: Column(
            children: [
              // בחירת מנווטים
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _navigatorData.entries.map((entry) {
                    final data = entry.value;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: FilterChip(
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(data.navigatorId),
                            const SizedBox(width: 4),
                            Icon(
                              data.isActive ? Icons.circle : Icons.circle_outlined,
                              size: 12,
                              color: data.isActive ? Colors.green : Colors.grey,
                            ),
                          ],
                        ),
                        selected: _selectedNavigators[data.navigatorId] ?? false,
                        onSelected: (selected) {
                          setState(() {
                            _selectedNavigators[data.navigatorId] = selected;
                          });
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),

              // שכבות
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildLayerToggle('נ.צ', _showNZ, (v) => setState(() => _showNZ = v)),
                  _buildLayerToggle('ג.ג', _showGG, (v) => setState(() => _showGG = v)),
                  _buildLayerToggle('מסלולים', _showTracks, (v) => setState(() => _showTracks = v)),
                  _buildLayerToggle('דקירות', _showPunches, (v) => setState(() => _showPunches = v)),
                ],
              ),
            ],
          ),
        ),

        // מפה
        Expanded(
          child: MapWithTypeSelector(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: widget.navigation.displaySettings.openingLat != null
                  ? LatLng(
                      widget.navigation.displaySettings.openingLat!,
                      widget.navigation.displaySettings.openingLng!,
                    )
                  : const LatLng(32.0853, 34.7818),
              initialZoom: 13.0,
            ),
            layers: [
              // גבול ג"ג
              if (_showGG && _boundary != null && _boundary!.coordinates.isNotEmpty)
                PolygonLayer(
                  polygons: [
                    Polygon(
                      points: _boundary!.coordinates
                          .map((coord) => LatLng(coord.lat, coord.lng))
                          .toList(),
                      color: Colors.blue.withOpacity(0.2 * _ggOpacity),
                      borderColor: Colors.blue,
                      borderStrokeWidth: 2,
                    ),
                  ],
                ),

              // נקודות ציון
              if (_showNZ)
                MarkerLayer(
                  markers: _checkpoints.map((cp) {
                    return Marker(
                      point: LatLng(cp.coordinates.lat, cp.coordinates.lng),
                      width: 40,
                      height: 40,
                      child: Column(
                        children: [
                          Icon(
                            Icons.place,
                            color: Colors.blue.withOpacity(_nzOpacity),
                            size: 32,
                          ),
                          Text(
                            '${cp.sequenceNumber}',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),

              // מסלולים של מנווטים
              if (_showTracks) ..._buildNavigatorTracks(),

              // דקירות
              if (_showPunches) ..._buildPunchMarkers(),

              // מיקומים נוכחיים של מנווטים
              ..._buildNavigatorMarkers(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'סטטוס מנווטים',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),

        ..._navigatorData.entries.map((entry) {
          final navigatorId = entry.key;
          final data = entry.value;

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: Icon(
                data.isActive ? Icons.navigation : Icons.check_circle,
                color: data.isActive ? Colors.green : Colors.grey,
                size: 32,
              ),
              title: Text(navigatorId),
              subtitle: Text(
                data.isActive
                    ? 'פעיל - ${data.punches.length} דקירות'
                    : 'סיים ניווט',
              ),
              trailing: data.isActive
                  ? IconButton(
                      icon: const Icon(Icons.stop_circle, color: Colors.red),
                      onPressed: () => _finishNavigatorNavigation(navigatorId),
                      tooltip: 'סיים למנווט',
                    )
                  : null,
              onTap: () => _showNavigatorDetails(navigatorId, data),
            ),
          );
        }),
      ],
    );
  }

  List<Widget> _buildNavigatorTracks() {
    List<Widget> tracks = [];

    for (final entry in _navigatorData.entries) {
      final navigatorId = entry.key;
      final data = entry.value;

      if (!(_selectedNavigators[navigatorId] ?? false)) continue;
      if (data.trackPoints.isEmpty) continue;

      final points = data.trackPoints
          .map((tp) => LatLng(tp.coordinate.lat, tp.coordinate.lng))
          .toList();

      tracks.add(
        PolylineLayer(
          polylines: [
            Polyline(
              points: points,
              strokeWidth: 3,
              color: data.isActive ? Colors.green : Colors.grey,
            ),
          ],
        ),
      );
    }

    return tracks;
  }

  List<Widget> _buildPunchMarkers() {
    List<Widget> markers = [];

    for (final entry in _navigatorData.entries) {
      final navigatorId = entry.key;
      final data = entry.value;

      if (!(_selectedNavigators[navigatorId] ?? false)) continue;

      final punchMarkers = data.punches.where((p) => !p.isDeleted).map((punch) {
        Color color;
        if (punch.isApproved) {
          color = Colors.green;
        } else if (punch.isRejected) {
          color = Colors.red;
        } else {
          color = Colors.orange;
        }

        return Marker(
          point: LatLng(punch.punchLocation.lat, punch.punchLocation.lng),
          width: 30,
          height: 30,
          child: Icon(
            Icons.flag,
            color: color,
            size: 30,
          ),
        );
      }).toList();

      if (punchMarkers.isNotEmpty) {
        markers.add(MarkerLayer(markers: punchMarkers));
      }
    }

    return markers;
  }

  List<Widget> _buildNavigatorMarkers() {
    List<Marker> markers = [];

    for (final entry in _navigatorData.entries) {
      final navigatorId = entry.key;
      final data = entry.value;

      if (!(_selectedNavigators[navigatorId] ?? false)) continue;
      if (data.currentPosition == null) continue;

      markers.add(
        Marker(
          point: data.currentPosition!,
          width: 60,
          height: 60,
          child: Column(
            children: [
              Icon(
                Icons.person_pin_circle,
                color: data.isActive ? Colors.green : Colors.grey,
                size: 40,
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: data.isActive ? Colors.green : Colors.grey,
                    width: 2,
                  ),
                ),
                child: Text(
                  navigatorId,
                  style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return markers.isNotEmpty ? [MarkerLayer(markers: markers)] : [];
  }

  Widget _buildLayerToggle(String label, bool value, ValueChanged<bool> onChanged) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Checkbox(
          value: value,
          onChanged: (v) => onChanged(v ?? false),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  void _showNavigatorDetails(String navigatorId, NavigatorLiveData data) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(navigatorId),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('סטטוס: ${data.isActive ? "פעיל" : "סיים"}'),
            const SizedBox(height: 8),
            Text('דקירות: ${data.punches.length}'),
            Text('נקודות מסלול: ${data.trackPoints.length}'),
            if (data.lastUpdate != null)
              Text('עדכון אחרון: ${data.lastUpdate!.toLocal().toString().split('.')[0]}'),
          ],
        ),
        actions: [
          if (data.isActive)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _finishNavigatorNavigation(navigatorId);
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('סיים למנווט'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('סגור'),
          ),
        ],
      ),
    );
  }
}

/// נתונים חיים של מנווט
class NavigatorLiveData {
  final String navigatorId;
  bool isActive;
  LatLng? currentPosition;
  List<TrackPoint> trackPoints;
  List<CheckpointPunch> punches;
  DateTime? lastUpdate;

  NavigatorLiveData({
    required this.navigatorId,
    required this.isActive,
    this.currentPosition,
    required this.trackPoints,
    required this.punches,
    this.lastUpdate,
  });
}
