import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/map_config.dart';
import '../../../domain/entities/boundary.dart';
import '../../../services/terrain/terrain_analysis_service.dart';
import '../../../services/terrain/terrain_models.dart';
import '../../widgets/map_controls.dart';
import '../../widgets/terrain/features_layer.dart';
import '../../widgets/terrain/slope_layer.dart';
import '../../widgets/terrain/smart_waypoints_layer.dart';
import '../../widgets/terrain/viewshed_layer.dart';
import '../../widgets/terrain/vulnerability_layer.dart';

/// מסך ניתוח תוואי שטח — מודול לימודי.
/// מקבל גבול גזרה, טוען DEM אוטומטית ומאפשר 6 סוגי ניתוח.
class TerrainAnalysisScreen extends StatefulWidget {
  final Boundary boundary;

  const TerrainAnalysisScreen({super.key, required this.boundary});

  @override
  State<TerrainAnalysisScreen> createState() => _TerrainAnalysisScreenState();
}

/// מצבי אינטראקציה — בחירת נקודות על המפה
enum _InteractionMode {
  none,
  selectObserver,
  selectPathStart,
  selectPathEnd,
  addEnemies,
}

class _TerrainAnalysisScreenState extends State<TerrainAnalysisScreen> {
  final TerrainAnalysisService _service = TerrainAnalysisService();
  final MapController _mapController = MapController();

  // --- אריח DEM ---
  bool _loading = false;
  String _statusMessage = '';
  bool _demLoaded = false;

  // --- תוצאות חישוב (null = לא חושב / בוטל) ---
  SlopeAspectResult? _slopeAspect;
  TerrainFeaturesResult? _features;
  ViewshedResult? _viewshed;
  HiddenPath? _hiddenPath;
  List<SmartWaypoint> _allSmartWaypoints = [];
  List<VulnerabilityPoint> _vulnerabilities = [];
  List<VulnerabilityZone> _vulnerabilityZones = [];

  // --- שכבות גלויות ---
  bool _showSlope = false;
  bool _showFeatures = false;
  bool _showViewshed = false;
  bool _showWaypoints = false;
  bool _showVulnerability = false;
  bool _showHiddenPath = false;

  // --- שקיפות שכבות ---
  double _slopeOpacity = 0.6;
  double _featuresOpacity = 0.6;
  double _viewshedOpacity = 0.5;

  // --- ניגודיות שיפוע ---
  double _slopeContrast = 0.5;

  // --- נקודות ציון חכמות — slider + חלוקה לפי סוג ---
  int _waypointDisplayCount = 100;
  Map<SmartWaypointType, int> _waypointTypeCounts = {};
  bool _showTypePanel = false;

  // --- אינטראקציה ---
  _InteractionMode _interactionMode = _InteractionMode.none;
  LatLng? _observerPosition;
  LatLng? _pathStart;
  LatLng? _pathEnd;
  List<LatLng> _enemyPositions = [];

  // --- מדידה ---
  bool _measureMode = false;
  final List<LatLng> _measurePoints = [];

  // --- מידע נקודה (נקודת ציון / תורפה) ---
  String? _pointInfo;

  @override
  void initState() {
    super.initState();
    _initService();
  }

  Future<void> _initService() async {
    await _service.initialize();
    if (!_service.isAvailable) {
      setState(
        () => _statusMessage = 'שגיאה: terrain_engine.dll לא נמצא',
      );
      return;
    }
    await _loadDem();
  }

  Future<void> _loadDem() async {
    setState(() {
      _loading = true;
      _statusMessage = 'טוען נתוני גובה...';
    });
    final coords = widget.boundary.coordinates;
    int tileLat = 31, tileLng = 34;
    if (coords.isNotEmpty) {
      double avgLat = 0, avgLng = 0;
      for (final c in coords) {
        avgLat += c.lat;
        avgLng += c.lng;
      }
      avgLat /= coords.length;
      avgLng /= coords.length;
      tileLat = avgLat.floor();
      tileLng = avgLng.floor();
    }
    final success =
        await _service.loadForBoundary(widget.boundary, tileLat, tileLng);
    setState(() {
      _loading = false;
      _demLoaded = success;
      _statusMessage = success ? 'DEM נטען — בחר פעולה' : 'שגיאה בטעינת DEM';
    });
    if (success) _fitToBoundary();
  }

  void _fitToBoundary() {
    final coords = widget.boundary.coordinates;
    if (coords.isEmpty) return;
    final points = coords.map((c) => LatLng(c.lat, c.lng)).toList();
    final bounds = LatLngBounds.fromPoints(points);
    _mapController.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(40)),
    );
  }

  // =====================================================================
  // Toggle — לחיצה ראשונה מחשבת, לחיצה שנייה מוחקת לגמרי
  // =====================================================================

  void _toggleSlope() {
    if (_slopeAspect != null) {
      setState(() {
        _slopeAspect = null;
        _showSlope = false;
      });
    } else {
      _computeSlope();
    }
  }

  void _toggleFeatures() {
    if (_features != null) {
      setState(() {
        _features = null;
        _showFeatures = false;
      });
    } else {
      _computeFeatures();
    }
  }

  void _toggleViewshed() {
    if (_viewshed != null) {
      setState(() {
        _viewshed = null;
        _showViewshed = false;
        _observerPosition = null;
        _interactionMode = _InteractionMode.none;
      });
    } else {
      setState(() {
        _interactionMode = _InteractionMode.selectObserver;
        _statusMessage = 'בחר נקודת תצפית על המפה';
      });
    }
  }

  void _toggleHiddenPath() {
    if (_hiddenPath != null) {
      setState(() {
        _hiddenPath = null;
        _showHiddenPath = false;
        _pathStart = null;
        _pathEnd = null;
        _enemyPositions = [];
        _interactionMode = _InteractionMode.none;
      });
    } else {
      setState(() {
        _pathStart = null;
        _pathEnd = null;
        _enemyPositions = [];
        _interactionMode = _InteractionMode.selectPathStart;
        _statusMessage = 'בחר נקודת התחלה על המפה';
      });
    }
  }

  void _toggleWaypoints() {
    if (_allSmartWaypoints.isNotEmpty) {
      setState(() {
        _allSmartWaypoints = [];
        _showWaypoints = false;
        _waypointTypeCounts = {};
        _showTypePanel = false;
      });
    } else {
      _detectWaypoints();
    }
  }

  void _toggleVulnerabilities() {
    if (_vulnerabilities.isNotEmpty || _vulnerabilityZones.isNotEmpty) {
      setState(() {
        _vulnerabilities = [];
        _vulnerabilityZones = [];
        _showVulnerability = false;
      });
    } else {
      _detectVulnerabilities();
    }
  }

  // =====================================================================
  // חישובים
  // =====================================================================

  Future<void> _computeSlope() async {
    setState(() {
      _loading = true;
      _statusMessage = 'מחשב שיפוע...';
    });
    final result = await _service.computeSlopeAspect();
    setState(() {
      _loading = false;
      _slopeAspect = result;
      _showSlope = result != null;
      _statusMessage =
          result != null ? 'חישוב שיפוע הושלם' : 'שגיאה בחישוב שיפוע';
    });
  }

  Future<void> _computeFeatures() async {
    setState(() {
      _loading = true;
      _statusMessage = 'מסווג תוואי שטח...';
    });
    final result = await _service.classifyFeatures();
    setState(() {
      _loading = false;
      _features = result;
      _showFeatures = result != null;
      _statusMessage = result != null
          ? 'סיווג תוואי שטח הושלם'
          : 'שגיאה בסיווג תוואי שטח';
    });
  }

  Future<void> _computeViewshed() async {
    if (_observerPosition == null) return;
    setState(() {
      _loading = true;
      _statusMessage = 'מחשב שטחים חיים / מתים...';
    });
    final result = await _service.computeViewshed(_observerPosition!);
    setState(() {
      _loading = false;
      _viewshed = result;
      _showViewshed = result != null;
      _statusMessage = result != null
          ? 'חישוב שטחים חיים / מתים הושלם'
          : 'שגיאה בחישוב שטחים חיים / מתים';
      _interactionMode = _InteractionMode.none;
    });
  }

  Future<void> _computeHiddenPath() async {
    if (_pathStart == null || _pathEnd == null || _enemyPositions.isEmpty) {
      return;
    }
    setState(() {
      _loading = true;
      _statusMessage = 'מחשב מסלול נסתר...';
    });
    final result = await _service.computeHiddenPath(
      _pathStart!,
      _pathEnd!,
      _enemyPositions,
    );
    setState(() {
      _loading = false;
      _hiddenPath = result;
      _showHiddenPath = result != null;
      _statusMessage = result != null
          ? 'מסלול נסתר: '
              '${result.totalDistanceMeters.toStringAsFixed(0)}מ\', '
              'חשיפה: ${result.exposurePercent.toStringAsFixed(1)}%'
          : 'שגיאה בחישוב מסלול נסתר';
      _interactionMode = _InteractionMode.none;
    });
  }

  Future<void> _detectWaypoints() async {
    setState(() {
      _loading = true;
      _statusMessage = 'מזהה נקודות ציון חכמות...';
    });
    final result = await _service.detectSmartWaypoints(
      minProminence: 5.0,
      minFeatureCells: 3,
    );
    // מיון לפי בולטות — הקיצוניות ביותר ראשונות
    result.sort((a, b) => b.prominence.compareTo(a.prominence));
    setState(() {
      _loading = false;
      _allSmartWaypoints = result;
      _showWaypoints = result.isNotEmpty;
      _waypointDisplayCount = result.length.clamp(1, 100);
      _redistributeWaypoints(_waypointDisplayCount);
      _statusMessage = result.isNotEmpty
          ? 'נמצאו ${result.length} נקודות ציון — הזז את הסליידר לסינון'
          : 'לא נמצאו נקודות ציון';
    });
  }

  Future<void> _detectVulnerabilities() async {
    setState(() {
      _loading = true;
      _statusMessage = 'מזהה נקודות תורפה...';
    });
    // חישוב נקודות ואזורי תורפה במקביל
    final results = await Future.wait([
      _service.detectVulnerabilities(),
      _service.detectVulnerabilityZones(),
    ]);
    final points = results[0] as List<VulnerabilityPoint>;
    final zones = results[1] as List<VulnerabilityZone>;
    // מיון לפי חומרה — הקשות ביותר ראשונות
    points.sort((a, b) => b.severity.compareTo(a.severity));
    setState(() {
      _loading = false;
      _vulnerabilities = points;
      _vulnerabilityZones = zones;
      _showVulnerability = points.isNotEmpty || zones.isNotEmpty;
      _statusMessage = points.isNotEmpty || zones.isNotEmpty
          ? 'נמצאו ${points.length} נקודות ו-${zones.length} אזורי תורפה'
          : 'לא נמצאו נקודות תורפה';
    });
  }

  /// חלוקה מחדש של נקודות ציון לפי סוג
  void _redistributeWaypoints(int total) {
    final byType = <SmartWaypointType, List<SmartWaypoint>>{};
    for (final wp in _allSmartWaypoints) {
      byType.putIfAbsent(wp.type, () => []).add(wp);
    }
    final types = byType.keys.toList();
    if (types.isEmpty) return;
    final perType = total ~/ types.length;
    final remainder = total % types.length;
    _waypointTypeCounts = {};
    for (int i = 0; i < types.length; i++) {
      final available = byType[types[i]]!.length;
      _waypointTypeCounts[types[i]] =
          min(perType + (i < remainder ? 1 : 0), available);
    }
    _waypointDisplayCount = total;
  }

  /// נקודות ציון מוצגות — מסוננות לפי חלוקת סוגים
  List<SmartWaypoint> get _displayedWaypoints {
    if (_allSmartWaypoints.isEmpty) return [];
    final result = <SmartWaypoint>[];
    final byType = <SmartWaypointType, List<SmartWaypoint>>{};
    for (final wp in _allSmartWaypoints) {
      byType.putIfAbsent(wp.type, () => []).add(wp);
    }
    for (final entry in byType.entries) {
      final count = _waypointTypeCounts[entry.key] ?? 0;
      result.addAll(entry.value.take(count));
    }
    return result;
  }

  // =====================================================================
  // טיפול בלחיצה על המפה
  // =====================================================================

  void _onMapTap(TapPosition tapPosition, LatLng point) {
    if (_measureMode) {
      setState(() => _measurePoints.add(point));
      return;
    }

    switch (_interactionMode) {
      case _InteractionMode.none:
        // ביטול הצגת מידע נקודה
        if (_pointInfo != null) setState(() => _pointInfo = null);
        break;

      case _InteractionMode.selectObserver:
        setState(() {
          _observerPosition = point;
          _statusMessage = 'מחשב שטחים חיים / מתים...';
        });
        _computeViewshed();
        break;

      case _InteractionMode.selectPathStart:
        setState(() {
          _pathStart = point;
          _interactionMode = _InteractionMode.selectPathEnd;
          _statusMessage = 'בחר נקודת סיום על המפה';
        });
        break;

      case _InteractionMode.selectPathEnd:
        setState(() {
          _pathEnd = point;
          _enemyPositions = [];
          _interactionMode = _InteractionMode.addEnemies;
          _statusMessage = 'בחר מיקומי אויב על המפה (עד 10)';
        });
        break;

      case _InteractionMode.addEnemies:
        if (_enemyPositions.length < 10) {
          setState(() {
            _enemyPositions.add(point);
            _statusMessage =
                'בחר מיקום אויב (${_enemyPositions.length}/10)';
          });
          // אם הגענו ל-10, מחשבים אוטומטית
          if (_enemyPositions.length >= 10) {
            _computeHiddenPath();
          }
        }
        break;
    }
  }

  /// סיום בחירת אויבים ידנית — ניתן ללחוץ "סיים" כשיש לפחות אויב אחד
  void _finishEnemySelection() {
    if (_enemyPositions.isNotEmpty) {
      _computeHiddenPath();
    }
  }

  void _onWaypointTap(SmartWaypoint wp) {
    setState(() {
      _pointInfo = '${wp.type.hebrewLabel}\n'
          'גובה: ${wp.elevation}מ\'\n'
          'בולטות: ${wp.prominence.toStringAsFixed(1)}מ\'';
    });
  }

  void _onVulnerabilityTap(VulnerabilityPoint vp) {
    setState(() {
      _pointInfo = '${vp.type.hebrewLabel}\n'
          'חומרה: ${(vp.severity * 100).toStringAsFixed(0)}%';
    });
  }

  // =====================================================================
  // Build
  // =====================================================================

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text('ניתוח שטח — ${widget.boundary.name}'),
          actions: [
            if (_statusMessage.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Center(
                  child: Text(
                    _statusMessage,
                    style:
                        const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ),
              ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          ],
        ),
        body: Column(
          children: [
            _buildComputeBar(),
            // סליידר ניגודיות שיפוע — מוצג רק כשהשכבה פעילה
            if (_showSlope && _slopeAspect != null) _buildContrastSlider(),
            // סליידר נקודות ציון — מוצג רק כשיש תוצאות
            if (_showWaypoints && _allSmartWaypoints.isNotEmpty)
              _buildWaypointSlider(),
            // פאנל חלוקה לפי סוג
            if (_showWaypoints &&
                _allSmartWaypoints.isNotEmpty &&
                _showTypePanel)
              _buildTypeDistributionPanel(),
            Expanded(child: _buildMapStack()),
          ],
        ),
      ),
    );
  }

  /// סרגל כפתורי חישוב עליון — כל כפתור toggle
  Widget _buildComputeBar() {
    final isInteracting = _interactionMode != _InteractionMode.none;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isInteracting ? Colors.blue.shade50 : Colors.grey.shade100,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade300, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _computeChip(Icons.terrain, 'שיפוע',
                      _slopeAspect != null, _toggleSlope),
                  _computeChip(Icons.landscape, 'תוואי',
                      _features != null, _toggleFeatures),
                  _computeChip(
                      Icons.visibility,
                      'שטחים חיים / מתים',
                      _viewshed != null,
                      _toggleViewshed),
                  _computeChip(Icons.route, 'מסלול נסתר',
                      _hiddenPath != null, _toggleHiddenPath),
                  _computeChip(Icons.flag, 'נק\' ציון',
                      _allSmartWaypoints.isNotEmpty, _toggleWaypoints),
                  _computeChip(
                      Icons.warning,
                      'תורפה',
                      _vulnerabilities.isNotEmpty ||
                          _vulnerabilityZones.isNotEmpty,
                      _toggleVulnerabilities),
                ],
              ),
            ),
          ),
          // ביטול אינטראקציה
          if (isInteracting)
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              tooltip: 'ביטול',
              onPressed: () {
                setState(() {
                  _interactionMode = _InteractionMode.none;
                  _statusMessage = 'בחירה בוטלה';
                });
              },
            ),
        ],
      ),
    );
  }

  Widget _computeChip(
      IconData icon, String label, bool active, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: ActionChip(
        avatar: Icon(icon,
            size: 18, color: active ? Colors.white : Colors.grey.shade700),
        label: Text(label, style: const TextStyle(fontSize: 12)),
        backgroundColor: active ? Colors.teal : Colors.white,
        labelStyle: active
            ? const TextStyle(color: Colors.white, fontSize: 12)
            : null,
        side: BorderSide(
          color: active ? Colors.teal : Colors.grey.shade400,
          width: 0.5,
        ),
        onPressed: _loading || !_demLoaded ? null : onTap,
      ),
    );
  }

  /// סליידר ניגודיות שיפוע
  Widget _buildContrastSlider() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: Colors.green.shade50,
      child: Row(
        children: [
          const Icon(Icons.contrast, size: 16, color: Colors.green),
          const SizedBox(width: 8),
          const Text(
            'ניגודיות',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          Expanded(
            child: Slider(
              value: _slopeContrast,
              min: 0.0,
              max: 1.0,
              divisions: 20,
              onChanged: (v) => setState(() => _slopeContrast = v),
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(
              '${(_slopeContrast * 100).round()}%',
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  /// סליידר בחירת כמות נקודות ציון + toggle פאנל סוגים
  Widget _buildWaypointSlider() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: Colors.teal.shade50,
      child: Row(
        children: [
          const Icon(Icons.flag, size: 16, color: Colors.teal),
          const SizedBox(width: 8),
          Text(
            '$_waypointDisplayCount / ${_allSmartWaypoints.length}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          Expanded(
            child: Slider(
              value: _waypointDisplayCount.toDouble(),
              min: 1,
              max: _allSmartWaypoints.length.clamp(1, 1000).toDouble(),
              divisions:
                  (_allSmartWaypoints.length.clamp(1, 1000) - 1).clamp(1, 999),
              onChanged: (v) {
                setState(() {
                  _redistributeWaypoints(v.round());
                });
              },
            ),
          ),
          const Text('קיצוניות ',
              style: TextStyle(fontSize: 10, color: Colors.grey)),
          const SizedBox(width: 4),
          InkWell(
            onTap: () => setState(() => _showTypePanel = !_showTypePanel),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                _showTypePanel ? Icons.expand_less : Icons.tune,
                size: 18,
                color: Colors.teal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// פאנל חלוקה לפי סוג נקודת ציון
  Widget _buildTypeDistributionPanel() {
    final byType = <SmartWaypointType, List<SmartWaypoint>>{};
    for (final wp in _allSmartWaypoints) {
      byType.putIfAbsent(wp.type, () => []).add(wp);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: Colors.teal.shade50.withValues(alpha: 0.7),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: byType.entries.map((entry) {
          final typeMax = entry.value.length;
          final current = _waypointTypeCounts[entry.key] ?? 0;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Icon(entry.key.icon, size: 14, color: entry.key.color),
                const SizedBox(width: 6),
                SizedBox(
                  width: 80,
                  child: Text(
                    entry.key.hebrewLabel,
                    style: const TextStyle(fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '$current/$typeMax',
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 2,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 5),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 10),
                      activeTrackColor: entry.key.color.withValues(alpha: 0.7),
                      thumbColor: entry.key.color,
                    ),
                    child: Slider(
                      value: current.toDouble(),
                      min: 0,
                      max: typeMax.toDouble(),
                      divisions: typeMax > 0 ? typeMax : 1,
                      onChanged: (v) {
                        setState(() {
                          _waypointTypeCounts[entry.key] = v.round();
                          // עדכון סה"כ מוצג
                          _waypointDisplayCount = _waypointTypeCounts.values
                              .fold(0, (sum, c) => sum + c);
                        });
                      },
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  /// המפה + כל השכבות הצפות
  Widget _buildMapStack() {
    final config = MapConfig();
    final boundaryMask = _service.boundaryMask;

    return Stack(
      children: [
        // --- המפה ---
        ValueListenableBuilder<MapType>(
          valueListenable: config.typeNotifier,
          builder: (context, mapType, _) {
            final activeBounds = _service.activeBounds;
            final initialCenter = activeBounds != null
                ? LatLng(
                    (activeBounds.north + activeBounds.south) / 2,
                    (activeBounds.east + activeBounds.west) / 2,
                  )
                : const LatLng(31.5, 34.5);

            return FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: initialCenter,
                initialZoom: 13,
                onTap: _onMapTap,
              ),
              children: [
                TileLayer(
                  urlTemplate: config.urlTemplate(mapType),
                  maxZoom: config.maxZoom(mapType),
                  userAgentPackageName: MapConfig.userAgentPackageName,
                ),

                // פוליגון גבול גזרה
                _buildBoundaryPolygon(),

                // שכבות ניתוח
                if (_showSlope && _slopeAspect != null)
                  SlopeLayer(
                    data: _slopeAspect!,
                    opacity: _slopeOpacity,
                    contrast: _slopeContrast,
                    boundaryMask: boundaryMask,
                  ),

                if (_showFeatures && _features != null)
                  FeaturesLayer(
                    data: _features!,
                    opacity: _featuresOpacity,
                    boundaryMask: boundaryMask,
                  ),

                if (_showViewshed && _viewshed != null)
                  ViewshedLayer(
                    data: _viewshed!,
                    opacity: _viewshedOpacity,
                    boundaryMask: boundaryMask,
                  ),

                if (_showWaypoints && _displayedWaypoints.isNotEmpty)
                  SmartWaypointsLayer(
                    waypoints: _displayedWaypoints,
                    onWaypointTap: _onWaypointTap,
                  ),

                if (_showVulnerability &&
                    (_vulnerabilities.isNotEmpty ||
                        _vulnerabilityZones.isNotEmpty))
                  VulnerabilityLayer(
                    points: _vulnerabilities,
                    zones: _vulnerabilityZones,
                    onPointTap: _onVulnerabilityTap,
                  ),

                if (_showHiddenPath && _hiddenPath != null)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _hiddenPath!.points,
                        color: Colors.cyan,
                        strokeWidth: 4.0,
                      ),
                    ],
                  ),

                // סמני אינטראקציה
                _buildInteractionMarkers(),

                // שכבות מדידה
                ...MapControls.buildMeasureLayers(_measurePoints),
              ],
            );
          },
        ),

        // --- MapControls סטנדרטי ---
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
          layers: _buildLayerConfigs(),
        ),

        // --- מקרא שיפוע — שמאל למטה ---
        if (_showSlope && _slopeAspect != null)
          Positioned(
            bottom: 16,
            left: 16,
            child: _buildSlopeLegendOverlay(),
          ),

        // --- מקרא תוואי שטח — שמאל למטה (מתחת לשיפוע אם שניהם גלויים) ---
        if (_showFeatures && _features != null)
          Positioned(
            bottom: (_showSlope && _slopeAspect != null) ? 140 : 16,
            left: 16,
            child: _buildFeaturesLegendOverlay(),
          ),

        // --- מידע נקודה — ימין למטה ---
        if (_pointInfo != null)
          Positioned(
            bottom: 16,
            right: 60,
            child: _buildPointInfoOverlay(),
          ),

        // --- שורת סטטוס / אינטראקציה ---
        if (_interactionMode != _InteractionMode.none)
          Positioned(
            top: 8,
            left: 60,
            right: 60,
            child: _buildInteractionBanner(),
          ),
      ],
    );
  }

  /// הגדרות שכבות ל-MapControls
  List<MapLayerConfig> _buildLayerConfigs() {
    return [
      if (_slopeAspect != null)
        MapLayerConfig(
          id: 'slope',
          label: 'שיפוע',
          color: Colors.green,
          visible: _showSlope,
          onVisibilityChanged: (v) => setState(() => _showSlope = v),
          opacity: _slopeOpacity,
          onOpacityChanged: (v) => setState(() => _slopeOpacity = v),
        ),
      if (_features != null)
        MapLayerConfig(
          id: 'features',
          label: 'תוואי שטח',
          color: Colors.orange,
          visible: _showFeatures,
          onVisibilityChanged: (v) => setState(() => _showFeatures = v),
          opacity: _featuresOpacity,
          onOpacityChanged: (v) => setState(() => _featuresOpacity = v),
        ),
      if (_viewshed != null)
        MapLayerConfig(
          id: 'viewshed',
          label: 'שטחים חיים / מתים',
          color: Colors.red,
          visible: _showViewshed,
          onVisibilityChanged: (v) => setState(() => _showViewshed = v),
          opacity: _viewshedOpacity,
          onOpacityChanged: (v) => setState(() => _viewshedOpacity = v),
        ),
      if (_allSmartWaypoints.isNotEmpty)
        MapLayerConfig(
          id: 'waypoints',
          label: 'נקודות ציון',
          color: Colors.brown,
          visible: _showWaypoints,
          onVisibilityChanged: (v) => setState(() => _showWaypoints = v),
        ),
      if (_vulnerabilities.isNotEmpty || _vulnerabilityZones.isNotEmpty)
        MapLayerConfig(
          id: 'vulnerability',
          label: 'נקודות תורפה',
          color: Colors.red.shade900,
          visible: _showVulnerability,
          onVisibilityChanged: (v) =>
              setState(() => _showVulnerability = v),
        ),
      if (_hiddenPath != null)
        MapLayerConfig(
          id: 'hiddenPath',
          label: 'מסלול נסתר',
          color: Colors.cyan,
          visible: _showHiddenPath,
          onVisibilityChanged: (v) => setState(() => _showHiddenPath = v),
        ),
    ];
  }

  /// פוליגון גבול גזרה
  Widget _buildBoundaryPolygon() {
    final points =
        widget.boundary.coordinates.map((c) => LatLng(c.lat, c.lng)).toList();
    if (points.length < 3) return const SizedBox.shrink();

    return PolygonLayer(
      polygons: [
        Polygon(
          points: points,
          color: Colors.black.withValues(alpha: 0.05),
          borderColor: Colors.black,
          borderStrokeWidth: 2.5,
        ),
      ],
    );
  }

  /// סמני אינטראקציה — נקודות שנבחרו
  Widget _buildInteractionMarkers() {
    final markers = <Marker>[];

    if (_observerPosition != null &&
        !(_showViewshed && _viewshed != null)) {
      markers.add(_circleMarker(
          _observerPosition!, Colors.orange.shade700, Icons.visibility));
    }
    if (_pathStart != null) {
      markers.add(_circleMarker(
          _pathStart!, Colors.green.shade600, Icons.play_arrow));
    }
    if (_pathEnd != null) {
      markers.add(
          _circleMarker(_pathEnd!, Colors.red.shade600, Icons.stop));
    }
    // סמני אויב — כל הנקודות ברשימה
    for (final enemyPos in _enemyPositions) {
      markers.add(Marker(
        point: enemyPos,
        width: 34,
        height: 34,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.red.shade900,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.yellow, width: 2),
          ),
          child:
              const Icon(Icons.gps_fixed, color: Colors.yellow, size: 20),
        ),
      ));
    }

    return MarkerLayer(markers: markers);
  }

  Marker _circleMarker(LatLng point, Color color, IconData icon) {
    return Marker(
      point: point,
      width: 32,
      height: 32,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }

  /// מקרא שיפוע — שקוף על המפה בצד שמאל למטה
  Widget _buildSlopeLegendOverlay() {
    return Material(
      color: Colors.white.withValues(alpha: 0.9),
      elevation: 3,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('מקרא שיפוע',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            _legendDot(const Color(0xFF4CAF50), '0\u00B0-5\u00B0'),
            _legendDot(const Color(0xFFCDDC39), '5\u00B0-15\u00B0'),
            _legendDot(const Color(0xFFFF9800), '15\u00B0-30\u00B0'),
            _legendDot(const Color(0xFFFF5722), '30\u00B0-45\u00B0'),
            _legendDot(const Color(0xFF880E4F), '45\u00B0+'),
          ],
        ),
      ),
    );
  }

  /// מקרא תוואי שטח — שקוף על המפה בצד שמאל למטה
  Widget _buildFeaturesLegendOverlay() {
    // רק הסוגים הרלוונטיים — ללא flat/slope
    const legendTypes = [
      TerrainFeatureType.dome,
      TerrainFeatureType.ridge,
      TerrainFeatureType.spur,
      TerrainFeatureType.valley,
      TerrainFeatureType.channel,
      TerrainFeatureType.saddle,
    ];

    return Material(
      color: Colors.white.withValues(alpha: 0.9),
      elevation: 3,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('מקרא תוואי שטח',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            ...legendTypes
                .map((t) => _legendDot(t.color, t.hebrewLabel)),
          ],
        ),
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration:
                BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 10)),
        ],
      ),
    );
  }

  /// מידע נקודה — ימין למטה
  Widget _buildPointInfoOverlay() {
    return Material(
      color: Colors.white.withValues(alpha: 0.9),
      elevation: 3,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: Text(
                _pointInfo!,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(width: 4),
            InkWell(
              onTap: () => setState(() => _pointInfo = null),
              child:
                  Icon(Icons.close, size: 14, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  /// באנר אינטראקציה — הוראות למשתמש
  Widget _buildInteractionBanner() {
    String text;
    Widget? trailing;

    switch (_interactionMode) {
      case _InteractionMode.selectObserver:
        text = 'לחץ על המפה לבחירת נקודת תצפית';
        break;
      case _InteractionMode.selectPathStart:
        text = 'לחץ על המפה לבחירת נקודת התחלה';
        break;
      case _InteractionMode.selectPathEnd:
        text = 'לחץ על המפה לבחירת נקודת סיום';
        break;
      case _InteractionMode.addEnemies:
        text = 'בחר מיקום אויב (${_enemyPositions.length}/10)  ';
        if (_enemyPositions.isNotEmpty) {
          trailing = TextButton(
            onPressed: _finishEnemySelection,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'סיים בחירת אויבים',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          );
        }
        break;
      case _InteractionMode.none:
        text = '';
        break;
    }

    return Material(
      color: Colors.blue.shade600,
      elevation: 4,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.touch_app, size: 18, color: Colors.white),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                text,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing,
            ],
          ],
        ),
      ),
    );
  }
}
