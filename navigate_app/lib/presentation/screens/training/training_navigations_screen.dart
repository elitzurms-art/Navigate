import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../domain/entities/navigation.dart' as domain;
import '../../../domain/entities/user_role.dart';
import '../../../domain/entities/checkpoint.dart';
import '../../../domain/entities/safety_point.dart';
import '../../../domain/entities/boundary.dart';
import '../../../domain/entities/cluster.dart';
import '../../../data/repositories/navigation_repository.dart';
import '../../../data/repositories/checkpoint_repository.dart';
import '../../../data/repositories/safety_point_repository.dart';
import '../../../data/repositories/boundary_repository.dart';
import '../../../data/repositories/cluster_repository.dart';
import '../../widgets/map_with_selector.dart';
import '../navigations/active_navigation_screen.dart';
import '../navigations/navigation_management_screen.dart';
import '../navigations/create_navigation_screen.dart';


/// מסך ניווטים במצב אימון - מציג את כל הניווטים עם מפה ושכבות לקריאה בלבד
class TrainingNavigationsScreen extends StatefulWidget {
  const TrainingNavigationsScreen({super.key});

  @override
  State<TrainingNavigationsScreen> createState() => _TrainingNavigationsScreenState();
}

class _TrainingNavigationsScreenState extends State<TrainingNavigationsScreen> {
  final NavigationRepository _repository = NavigationRepository();
  final CheckpointRepository _checkpointRepository = CheckpointRepository();
  final SafetyPointRepository _safetyPointRepository = SafetyPointRepository();
  final BoundaryRepository _boundaryRepository = BoundaryRepository();
  final ClusterRepository _clusterRepository = ClusterRepository();
  final MapController _mapController = MapController();

  List<domain.Navigation> _navigations = [];
  bool _isLoading = true;
  bool _isCommander = true;

  // שכבות מפה - מצב תצוגה בלבד (toggle show/hide)
  bool _showNZ = true;
  bool _showNB = false;
  bool _showGG = false;
  bool _showBA = false;
  bool _showLayerControls = false;
  bool _showMap = true;

  // נתוני שכבות
  List<Checkpoint> _checkpoints = [];
  List<SafetyPoint> _safetyPoints = [];
  List<Boundary> _boundaries = [];
  List<Cluster> _clusters = [];
  bool _isLoadingLayers = false;

  // ניווט שנבחר לטעינת שכבות
  domain.Navigation? _selectedNavigation;

  static const LatLng _defaultCenter = LatLng(31.5, 34.75);

  @override
  void initState() {
    super.initState();
    _checkRole();
    _loadNavigations();
  }

  Future<void> _checkRole() async {
    final prefs = await SharedPreferences.getInstance();
    final roleCode = prefs.getString('guest_role');
    if (roleCode != null) {
      final role = UserRole.fromCode(roleCode);
      setState(() {
        _isCommander = !role.isNavigator;
      });
    }
  }

  Future<void> _loadNavigations() async {
    setState(() => _isLoading = true);
    try {
      final allNavs = await _repository.getAll();
      // סינון - מצב אימון: ממתין או פעיל
      final filteredNavs = allNavs
          .where((nav) => nav.status == 'waiting' || nav.status == 'active')
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
      setState(() => _isLoadingLayers = false);
    }
  }

  Future<void> _startTrainingNavigation(domain.Navigation navigation) async {
    if (!navigation.routesDistributed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('הניווט טרם חולק לצירים'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('התחל אימון'),
        content: Text(
          'האם להתחיל אימון עבור:\n${navigation.name}?\n\n'
          'המערכת תתחיל להקליט GPS ותנעל את האפליקציה.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.green),
            child: const Text('התחל אימון'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('מתחיל אימון...'),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final updatedNavigation = navigation.copyWith(
      status: 'active',
      activeStartTime: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await _repository.update(updatedNavigation);

    if (mounted) {
      Navigator.pop(context);

      if (_isCommander) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => NavigationManagementScreen(
              navigation: updatedNavigation,
            ),
          ),
        ).then((_) => _loadNavigations());
      } else {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ActiveNavigationScreen(
              navigation: updatedNavigation,
              navigatorId: 'אימון',
              assignedCheckpoints: [],
            ),
          ),
        ).then((_) => _loadNavigations());
      }
    }
  }

  Future<void> _pauseTraining(domain.Navigation navigation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('השהיית אימון'),
        content: const Text('האם להשהות את האימון?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            child: const Text('השהה'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final updatedNavigation = navigation.copyWith(
      status: 'ready',
      updatedAt: DateTime.now(),
    );
    await _repository.update(updatedNavigation);
    _loadNavigations();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('האימון הושהה'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _finishTraining(domain.Navigation navigation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('סיום אימון'),
        content: const Text(
          'האם לסיים את האימון ולשמור?\n\n'
          'נתוני ה-GPS ישמרו לתחקור.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('סיים ושמור'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('שומר אימון...'),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final updatedNavigation = navigation.copyWith(
      status: 'review',
      updatedAt: DateTime.now(),
    );
    await _repository.update(updatedNavigation);

    if (mounted) {
      Navigator.pop(context);
      _loadNavigations();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('האימון הסתיים ונשמר'),
          backgroundColor: Colors.green,
        ),
      );
    }
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
      case 'waiting':
        return 'ממתין';
      case 'active':
        return 'פעיל';
      default:
        return status;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'waiting':
        return Colors.cyan;
      case 'active':
        return Colors.green;
      default:
        return Colors.grey;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('אימון - ניווטים'),
        backgroundColor: Colors.orange,
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
          // Toggle בקרת שכבות
          if (_showMap)
            IconButton(
              icon: Icon(_showLayerControls ? Icons.layers_clear : Icons.layers),
              onPressed: () {
                setState(() => _showLayerControls = !_showLayerControls);
              },
              tooltip: 'בקרת שכבות',
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
                      Icon(Icons.fitness_center, size: 100, color: Colors.grey[300]),
                      const SizedBox(height: 20),
                      const Text(
                        'אין ניווטים במצב אימון',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'ניווטים בסטטוס "ממתין" או "פעיל" יופיעו כאן',
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
                            if (_showLayerControls) _buildLayerControlsPanel(),
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
    return MapWithTypeSelector(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _defaultCenter,
        initialZoom: 8,
      ),
      layers: [

        // שכבת NZ - נקודות ציון (לקריאה בלבד)
        if (_showNZ && _checkpoints.isNotEmpty)
          MarkerLayer(
            markers: _checkpoints.map((checkpoint) {
              return Marker(
                point: LatLng(
                  checkpoint.coordinates.lat,
                  checkpoint.coordinates.lng,
                ),
                width: 40,
                height: 50,
                child: Column(
                  children: [
                    Icon(
                      Icons.place,
                      color: checkpoint.color == 'blue' ? Colors.blue : Colors.green,
                      size: 32,
                    ),
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${checkpoint.sequenceNumber}',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
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
                color: _getSeverityColor(point.severity).withOpacity(0.3),
                borderColor: _getSeverityColor(point.severity),
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
                color: Colors.transparent,
                borderColor: Colors.black,
                borderStrokeWidth: boundary.strokeWidth,
                isFilled: false,
              );
            }).toList(),
          ),

        // שכבת BA - ביצי אזור
        if (_showBA && _clusters.isNotEmpty)
          PolygonLayer(
            polygons: _clusters.map((cluster) {
              return Polygon(
                points: cluster.coordinates.map((c) => LatLng(c.lat, c.lng)).toList(),
                color: Colors.green.withOpacity(cluster.fillOpacity),
                borderColor: Colors.green,
                borderStrokeWidth: cluster.strokeWidth,
                isFilled: true,
              );
            }).toList(),
          ),
      ],
    );
  }

  /// פאנל בקרת שכבות - toggle בלבד (ללא עריכה)
  Widget _buildLayerControlsPanel() {
    return Positioned(
      top: 10,
      left: 10,
      child: Container(
        width: 280,
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
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.layers, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'שכבות (תצוגה בלבד)',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 18),
                    onPressed: () => setState(() => _showLayerControls = false),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            _buildLayerToggle(
              title: 'נ"ז - נקודות ציון',
              subtitle: '${_checkpoints.length} נקודות',
              color: Colors.blue,
              isVisible: _showNZ,
              onChanged: (v) => setState(() => _showNZ = v),
            ),
            const Divider(height: 1),
            _buildLayerToggle(
              title: 'נת"ב - נקודות תורפה',
              subtitle: '${_safetyPoints.length} נקודות',
              color: Colors.red,
              isVisible: _showNB,
              onChanged: (v) => setState(() => _showNB = v),
            ),
            const Divider(height: 1),
            _buildLayerToggle(
              title: 'ג"ג - גבול גזרה',
              subtitle: '${_boundaries.length} גבולות',
              color: Colors.black,
              isVisible: _showGG,
              onChanged: (v) => setState(() => _showGG = v),
            ),
            const Divider(height: 1),
            _buildLayerToggle(
              title: 'ב"א - ביצי אזור',
              subtitle: '${_clusters.length} ביצות',
              color: Colors.green,
              isVisible: _showBA,
              onChanged: (v) => setState(() => _showBA = v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLayerToggle({
    required String title,
    required String subtitle,
    required Color color,
    required bool isVisible,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withOpacity(0.2),
            radius: 14,
            child: Icon(Icons.layers, color: color, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
              ],
            ),
          ),
          Switch(
            value: isVisible,
            onChanged: onChanged,
            activeColor: color,
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationsList() {
    return Column(
      children: [
        // כותרת רשימת ניווטים
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.orange.withOpacity(0.1),
          child: Row(
            children: [
              const Icon(Icons.fitness_center, color: Colors.orange, size: 20),
              const SizedBox(width: 8),
              Text(
                'ניווטים באימון (${_navigations.length})',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.orange,
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
    final isActive = navigation.status == 'active';
    final isSelected = _selectedNavigation?.id == navigation.id;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: isSelected ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected
            ? BorderSide(color: Colors.orange, width: 2)
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

              // כפתורי פעולה (התחל/השהה/סיים)
              Row(
                children: [
                  if (!isActive) ...[
                    if (_isCommander)
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _startTrainingNavigation(navigation),
                          icon: const Icon(Icons.play_arrow, size: 18),
                          label: const Text('התחל ניהול והקלטה'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Center(
                            child: Text(
                              'ממתין לתחילת ניווט...',
                              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ),
                  ],
                  if (isActive) ...[
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _pauseTraining(navigation),
                        icon: const Icon(Icons.pause, size: 18),
                        label: const Text('השהה'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _finishTraining(navigation),
                        icon: const Icon(Icons.stop, size: 18),
                        label: const Text('סיים ושמור'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                  ],
                ],
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
      avatar: Icon(icon, size: 16, color: Colors.orange.shade700),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: onTap,
      backgroundColor: Colors.orange.withOpacity(0.1),
      side: BorderSide(color: Colors.orange.shade200),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
