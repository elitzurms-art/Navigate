import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../domain/entities/navigation.dart' as domain;
import '../../../domain/entities/checkpoint.dart';
import '../../../domain/entities/safety_point.dart';
import '../../../domain/entities/boundary.dart';
import '../../../domain/entities/cluster.dart';
import '../../../data/repositories/navigation_repository.dart';
import '../../../data/repositories/checkpoint_repository.dart';
import '../../../data/repositories/safety_point_repository.dart';
import '../../../data/repositories/boundary_repository.dart';
import '../../../data/repositories/cluster_repository.dart';
import '../navigations/create_navigation_screen.dart';
import '../navigations/approval_screen.dart';
import '../../widgets/map_with_selector.dart';
import '../../widgets/map_controls.dart';
import '../navigations/investigation_screen.dart';


/// מסך ניווטים במצב למידה ותחקור - מציג את כל הניווטים עם מפה ושכבות לקריאה בלבד
class LearningNavigationsScreen extends StatefulWidget {
  const LearningNavigationsScreen({super.key});

  @override
  State<LearningNavigationsScreen> createState() => _LearningNavigationsScreenState();
}

class _LearningNavigationsScreenState extends State<LearningNavigationsScreen> {
  final NavigationRepository _repository = NavigationRepository();
  final CheckpointRepository _checkpointRepository = CheckpointRepository();
  final SafetyPointRepository _safetyPointRepository = SafetyPointRepository();
  final BoundaryRepository _boundaryRepository = BoundaryRepository();
  final ClusterRepository _clusterRepository = ClusterRepository();
  final MapController _mapController = MapController();

  List<domain.Navigation> _navigations = [];
  bool _isLoading = true;

  // שכבות מפה - מצב תצוגה בלבד (toggle show/hide)
  bool _showNZ = true;
  bool _showNB = false;
  bool _showGG = false;
  bool _showBA = false;
  bool _showMap = true;

  // שקיפות שכבות
  double _nzOpacity = 1.0;
  double _nbOpacity = 1.0;
  double _ggOpacity = 1.0;
  double _baOpacity = 1.0;

  // נתוני שכבות
  List<Checkpoint> _checkpoints = [];
  List<SafetyPoint> _safetyPoints = [];
  List<Boundary> _boundaries = [];
  List<Cluster> _clusters = [];
  bool _isLoadingLayers = false;

  // ניווט שנבחר לטעינת שכבות
  domain.Navigation? _selectedNavigation;

  // מדידה
  bool _measureMode = false;
  final List<LatLng> _measurePoints = [];

  static const LatLng _defaultCenter = LatLng(31.5, 34.75);

  @override
  void initState() {
    super.initState();
    _loadNavigations();
  }

  Future<void> _loadNavigations() async {
    setState(() => _isLoading = true);
    try {
      final allNavs = await _repository.getAll();
      // סינון - מצב למידה ותחקור: אישור או תחקור
      final filteredNavs = allNavs
          .where((nav) => nav.status == 'approval' || nav.status == 'review')
          .toList();
      setState(() {
        _navigations = filteredNavs;
        _isLoading = false;
      });

      // טעינת שכבות לניווט הראשון
      if (_navigations.isNotEmpty && _selectedNavigation == null) {
        _selectNavigation(_navigations.first);
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  /// בחירת ניווט לטעינת שכבות מהמפה
  Future<void> _selectNavigation(domain.Navigation navigation) async {
    setState(() {
      _selectedNavigation = navigation;
      _isLoadingLayers = true;
    });

    try {
      // טעינת כל השכבות מהאזור של הניווט
      final results = await Future.wait([
        _checkpointRepository.getByArea(navigation.areaId),
        _safetyPointRepository.getByArea(navigation.areaId),
        _boundaryRepository.getByArea(navigation.areaId),
        _clusterRepository.getByArea(navigation.areaId),
      ]);

      setState(() {
        _checkpoints = results[0] as List<Checkpoint>;
        _safetyPoints = results[1] as List<SafetyPoint>;
        _boundaries = results[2] as List<Boundary>;
        _clusters = results[3] as List<Cluster>;
        _isLoadingLayers = false;
      });

      // התמקדות באזור הנקודות
      final pointCheckpoints = _checkpoints.where((c) => !c.isPolygon && c.coordinates != null).toList();
      if (pointCheckpoints.isNotEmpty) {
        final latitudes = pointCheckpoints.map((c) => c.coordinates!.lat).toList();
        final longitudes = pointCheckpoints.map((c) => c.coordinates!.lng).toList();
        final minLat = latitudes.reduce((a, b) => a < b ? a : b);
        final maxLat = latitudes.reduce((a, b) => a > b ? a : b);
        final minLng = longitudes.reduce((a, b) => a < b ? a : b);
        final maxLng = longitudes.reduce((a, b) => a > b ? a : b);
        final center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
        _mapController.move(center, 12);
      }
    } catch (e) {
      setState(() => _isLoadingLayers = false);
    }
  }

  /// פתיחת מסך מתאים לפי סטטוס הניווט
  void _openNavigationScreen(domain.Navigation navigation) {
    Widget screen;
    if (navigation.status == 'approval') {
      screen = ApprovalScreen(navigation: navigation, isNavigator: true);
    } else {
      screen = InvestigationScreen(navigation: navigation, isNavigator: true);
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => screen),
    ).then((_) => _loadNavigations());
  }




  /// מעבר לעריכת הגדרות ניווט (בלי שכבות)
  void _editNavigationSettings(domain.Navigation navigation) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreateNavigationScreen(
          navigation: navigation,
          alertsOnlyMode: true,
        ),
      ),
    ).then((result) {
      if (result == true) _loadNavigations();
    });
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'approval':
        return 'אישור';
      case 'review':
        return 'סקירה';
      default:
        return status;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'approval':
        return Colors.amber;
      case 'review':
        return Colors.deepPurple;
      default:
        return Colors.grey;
    }
  }

  Color _getSeverityColor(String severity) {
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('למידה ותחקור - ניווטים'),
        backgroundColor: const Color(0xFF4CAF50),
        foregroundColor: Colors.white,
        actions: [
          // Toggle הצגת מפה
          IconButton(
            icon: Icon(_showMap ? Icons.map : Icons.map_outlined),
            onPressed: () {
              setState(() => _showMap = !_showMap);
            },
            tooltip: 'הצג/הסתר מפה',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadNavigations,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _navigations.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.school, size: 100, color: Colors.grey[300]),
                      const SizedBox(height: 20),
                      const Text(
                        'אין ניווטים בלמידה ותחקור',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'ניווטים בסטטוס "אישור" או "סקירה" יופיעו כאן',
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // מפה עם שכבות (לקריאה בלבד)
                    if (_showMap)
                      Expanded(
                        flex: 2,
                        child: Stack(
                          children: [
                            _buildMap(),
                            if (_isLoadingLayers)
                              Container(
                                color: Colors.black26,
                                child: const Center(child: CircularProgressIndicator()),
                              ),
                            // הודעה שהשכבות לקריאה בלבד
                            Positioned(
                              bottom: 8,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'שכבות לתצוגה בלבד',
                                  style: TextStyle(color: Colors.white, fontSize: 11),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // רשימת ניווטים
                    Expanded(
                      flex: 3,
                      child: _buildNavigationsList(),
                    ),
                  ],
                ),
    );
  }

  Widget _buildMap() {
    return Stack(
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
          }
        },
      ),
      layers: [

        // שכבת NZ - נקודות ציון (לקריאה בלבד)
        if (_showNZ && _checkpoints.isNotEmpty)
          MarkerLayer(
            markers: _checkpoints.where((cp) => !cp.isPolygon && cp.coordinates != null).map((checkpoint) {
              final markerColor = checkpoint.color == 'green' ? Colors.green : Colors.blue;
              return Marker(
                point: LatLng(
                  checkpoint.coordinates!.lat,
                  checkpoint.coordinates!.lng,
                ),
                width: 36,
                height: 36,
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

        // שכבת NB - נקודות תורפה (נקודות)
        if (_showNB && _safetyPoints.where((p) => p.type == 'point').isNotEmpty)
          MarkerLayer(
            markers: _safetyPoints
                .where((p) => p.type == 'point' && p.coordinates != null)
                .map((point) {
              return Marker(
                point: LatLng(point.coordinates!.lat, point.coordinates!.lng),
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
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),

        // שכבת NB - פוליגונים
        if (_showNB && _safetyPoints.where((p) => p.type == 'polygon').isNotEmpty)
          PolygonLayer(
            polygons: _safetyPoints
                .where((p) => p.type == 'polygon' && p.polygonCoordinates != null)
                .map((point) {
              return Polygon(
                points: point.polygonCoordinates!
                    .map((c) => LatLng(c.lat, c.lng))
                    .toList(),
                color: _getSeverityColor(point.severity).withValues(alpha: 0.3 * _nbOpacity),
                borderColor: _getSeverityColor(point.severity).withValues(alpha: _nbOpacity),
                borderStrokeWidth: 3,
                isFilled: true,
              );
            }).toList(),
          ),

        // שכבת GG - גבול גזרה
        if (_showGG && _boundaries.isNotEmpty)
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

        // שכבת BA - ביצי אזור
        if (_showBA && _clusters.isNotEmpty)
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
        ...MapControls.buildMeasureLayers(_measurePoints),
      ],
    ),
        MapControls(
          mapController: _mapController,
          layers: [
            MapLayerConfig(
              id: 'nz',
              label: 'נקודות ציון',
              color: Colors.blue,
              visible: _showNZ,
              onVisibilityChanged: (v) => setState(() => _showNZ = v),
              opacity: _nzOpacity,
              onOpacityChanged: (v) => setState(() => _nzOpacity = v),
            ),
            MapLayerConfig(
              id: 'nb',
              label: 'נקודות בטיחות',
              color: Colors.red,
              visible: _showNB,
              onVisibilityChanged: (v) => setState(() => _showNB = v),
              opacity: _nbOpacity,
              onOpacityChanged: (v) => setState(() => _nbOpacity = v),
            ),
            MapLayerConfig(
              id: 'gg',
              label: 'גבול גזרה',
              color: Colors.black,
              visible: _showGG,
              onVisibilityChanged: (v) => setState(() => _showGG = v),
              opacity: _ggOpacity,
              onOpacityChanged: (v) => setState(() => _ggOpacity = v),
            ),
            MapLayerConfig(
              id: 'ba',
              label: 'ביצי אזור',
              color: Colors.green,
              visible: _showBA,
              onVisibilityChanged: (v) => setState(() => _showBA = v),
              opacity: _baOpacity,
              onOpacityChanged: (v) => setState(() => _baOpacity = v),
            ),
          ],
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
    );
  }

  Widget _buildNavigationsList() {
    return Column(
      children: [
        // כותרת רשימת ניווטים
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: const Color(0xFF4CAF50).withOpacity(0.1),
          child: Row(
            children: [
              const Icon(Icons.school, color: Color(0xFF4CAF50), size: 20),
              const SizedBox(width: 8),
              Text(
                'ניווטים בלמידה ותחקור (${_navigations.length})',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Color(0xFF4CAF50),
                ),
              ),
            ],
          ),
        ),

        // בחירת ניווט לתצוגת שכבות (אם יש יותר מאחד)
        if (_navigations.length > 1)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                const Text('שכבות עבור: ', style: TextStyle(fontSize: 12)),
                Expanded(
                  child: DropdownButton<String>(
                    value: _selectedNavigation?.id,
                    isExpanded: true,
                    isDense: true,
                    items: _navigations.map((nav) {
                      return DropdownMenuItem(
                        value: nav.id,
                        child: Text(nav.name, style: const TextStyle(fontSize: 13)),
                      );
                    }).toList(),
                    onChanged: (navId) {
                      if (navId != null) {
                        final nav = _navigations.firstWhere((n) => n.id == navId);
                        _selectNavigation(nav);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),

        // רשימת ניווטים
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: _navigations.length,
            itemBuilder: (context, index) {
              final navigation = _navigations[index];
              return _buildNavigationCard(navigation);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildNavigationCard(domain.Navigation navigation) {
    final isSelected = _selectedNavigation?.id == navigation.id;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: isSelected ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected
            ? const BorderSide(color: Color(0xFF4CAF50), width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: () => _selectNavigation(navigation),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // כותרת + סטטוס
              Row(
                children: [
                  Expanded(
                    child: Text(
                      navigation.name,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getStatusColor(navigation.status).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _getStatusColor(navigation.status)),
                    ),
                    child: Text(
                      _getStatusText(navigation.status),
                      style: TextStyle(
                        color: _getStatusColor(navigation.status),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // פרטים
              Row(
                children: [
                  Icon(Icons.route, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    'צירים: ${navigation.routes.length}',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  ),
                  const SizedBox(width: 16),
                  Icon(Icons.gps_fixed, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    'GPS: ${navigation.gpsUpdateIntervalSeconds}s',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // כפתורי עריכה מותרים: עץ מנווטים, הרשאות, הגדרות ניווט
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _buildEditChip(
                    icon: Icons.settings,
                    label: 'הגדרות ניווט',
                    onTap: () => _editNavigationSettings(navigation),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // כפתור כניסה למסך המתאים
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _openNavigationScreen(navigation),
                  icon: Icon(
                    navigation.status == 'approval' ? Icons.check_circle : Icons.analytics,
                    size: 18,
                  ),
                  label: Text(
                    navigation.status == 'approval' ? 'כניסה לאישור' : 'כניסה לתחקור',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _getStatusColor(navigation.status),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEditChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ActionChip(
      avatar: Icon(icon, size: 16, color: const Color(0xFF388E3C)),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: onTap,
      backgroundColor: const Color(0xFF4CAF50).withOpacity(0.1),
      side: BorderSide(color: const Color(0xFF4CAF50).withOpacity(0.3)),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
