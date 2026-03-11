import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../domain/entities/coordinate.dart';
import '../../../domain/entities/boundary.dart';
import '../../../domain/entities/checkpoint.dart';
import '../../../domain/entities/nav_layer.dart';
import '../../../data/repositories/boundary_repository.dart';
import '../../../data/repositories/checkpoint_repository.dart';
import '../../../core/utils/polygon_operations.dart';
import '../../widgets/map_with_selector.dart';
import '../../widgets/map_controls.dart';

// ---------------------------------------------------------------------------
// Result class
// ---------------------------------------------------------------------------

/// תוצאת הגדרת גבול ניווט
class BoundarySetupResult {
  final List<Coordinate> coordinates;
  final List<List<Coordinate>>? multiPolygonCoordinates;
  final String geometryType; // 'polygon' or 'multipolygon'
  final NavBoundaryCreationMode creationMode;
  final List<String> sourceBoundaryIds;
  final String areaId;
  final String name;

  const BoundarySetupResult({
    required this.coordinates,
    this.multiPolygonCoordinates,
    required this.geometryType,
    required this.creationMode,
    required this.sourceBoundaryIds,
    required this.areaId,
    required this.name,
  });
}

// ---------------------------------------------------------------------------
// Main screen
// ---------------------------------------------------------------------------

/// מסך הגדרת גבול ניווט מתקדם — 3 מצבים: איחוד, ציור ידני, עריכת גבול קיים
class BoundarySetupScreen extends StatefulWidget {
  final String areaId;
  final List<Coordinate>? existingBoundaryCoordinates;
  final List<List<Coordinate>>? existingMultiPolygonCoordinates;
  final NavBoundaryCreationMode? existingCreationMode;
  final List<String>? existingSourceBoundaryIds;

  const BoundarySetupScreen({
    super.key,
    required this.areaId,
    this.existingBoundaryCoordinates,
    this.existingMultiPolygonCoordinates,
    this.existingCreationMode,
    this.existingSourceBoundaryIds,
  });

  @override
  State<BoundarySetupScreen> createState() => _BoundarySetupScreenState();
}

class _BoundarySetupScreenState extends State<BoundarySetupScreen> {
  // ---- Constants ----
  static const LatLng _defaultCenter = LatLng(31.5, 34.75);

  static const _boundaryColors = [
    Colors.blue,
    Colors.red,
    Colors.orange,
    Colors.purple,
    Colors.teal,
    Colors.indigo,
    Colors.pink,
    Colors.cyan,
  ];

  // ---- Repositories ----
  final BoundaryRepository _boundaryRepo = BoundaryRepository();
  final CheckpointRepository _checkpointRepo = CheckpointRepository();

  // ---- General state ----
  final MapController _mapController = MapController();
  NavBoundaryCreationMode _mode = NavBoundaryCreationMode.union;
  List<Boundary> _boundaries = [];
  List<Checkpoint> _checkpoints = [];
  bool _isLoading = true;

  // ---- Map layers & measurement ----
  bool _showGG = true;
  bool _showNZ = true;
  double _ggOpacity = 0.7;
  double _nzOpacity = 1.0;
  bool _measureMode = false;
  final List<LatLng> _measurePoints = [];

  // ---- Mode 1: Union ----
  Set<String> _selectedBoundaryIds = {};
  List<List<Coordinate>>? _unionResult;
  bool _isUnionMultiPolygon = false;

  // ---- Modes 2 & 3: Polygon editor ----
  List<LatLng> _manualDrawPoints = [];
  List<LatLng> _cloneEditPoints = [];

  List<LatLng> get _polygonPoints =>
      _mode == NavBoundaryCreationMode.cloneEdit
          ? _cloneEditPoints
          : _manualDrawPoints;

  set _polygonPoints(List<LatLng> value) {
    if (_mode == NavBoundaryCreationMode.cloneEdit) {
      _cloneEditPoints = value;
    } else {
      _manualDrawPoints = value;
    }
  }
  int? _selectedPointIndex;

  // ---- Multi-polygon editor (union sub-mode) ----
  bool _isEditingMultiPolygon = false;
  List<List<LatLng>> _multiPolygonEditorPoints = [];
  int _activePolygonIndex = 0;

  // ---- Mode 3: Clone ----
  String? _cloneSourceBoundaryId;

  @override
  void initState() {
    super.initState();
    _initFromExisting();
    _loadBoundaries();
  }

  void _initFromExisting() {
    if (widget.existingCreationMode != null) {
      _mode = widget.existingCreationMode!;
    }
    if (widget.existingSourceBoundaryIds != null) {
      _selectedBoundaryIds = widget.existingSourceBoundaryIds!.toSet();
    }
    if (widget.existingBoundaryCoordinates != null &&
        (_mode == NavBoundaryCreationMode.manual ||
            _mode == NavBoundaryCreationMode.cloneEdit)) {
      _polygonPoints = widget.existingBoundaryCoordinates!
          .map((c) => LatLng(c.lat, c.lng))
          .toList();
    }
  }

  Future<void> _loadBoundaries() async {
    try {
      final results = await Future.wait([
        _boundaryRepo.getByArea(widget.areaId),
        _checkpointRepo.getByArea(widget.areaId),
      ]);
      if (!mounted) return;
      setState(() {
        _boundaries = results[0] as List<Boundary>;
        _checkpoints = results[1] as List<Checkpoint>;
        _isLoading = false;
      });
      // Recompute union if we already have pre-selected boundaries
      if (_mode == NavBoundaryCreationMode.union &&
          _selectedBoundaryIds.isNotEmpty) {
        _computeUnion();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('שגיאה בטעינת גבולות: $e')),
      );
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Union helpers
  // ---------------------------------------------------------------------------

  void _computeUnion() {
    if (_selectedBoundaryIds.isEmpty) {
      setState(() {
        _unionResult = null;
        _isUnionMultiPolygon = false;
      });
      return;
    }

    final selected = _boundaries
        .where((b) => _selectedBoundaryIds.contains(b.id))
        .toList();

    if (selected.length == 1) {
      setState(() {
        _unionResult = [selected.first.coordinates];
        _isUnionMultiPolygon = false;
      });
      return;
    }

    final polygons = selected.map((b) => b.coordinates).toList();
    final result = PolygonOperations.unionPolygons(polygons);

    setState(() {
      _unionResult = result;
      _isUnionMultiPolygon = result.length > 1;
    });
  }

  void _toggleBoundarySelection(String id) {
    setState(() {
      if (_selectedBoundaryIds.contains(id)) {
        _selectedBoundaryIds.remove(id);
      } else {
        _selectedBoundaryIds.add(id);
      }
    });
    _computeUnion();
  }

  // ---------------------------------------------------------------------------
  // Polygon editor helpers (Modes 2 & 3)
  // ---------------------------------------------------------------------------

  /// Returns the active polygon points list (multi-polygon editor or regular).
  List<LatLng> get _currentEditPoints => _isEditingMultiPolygon
      ? _multiPolygonEditorPoints[_activePolygonIndex]
      : _polygonPoints;

  void _addPoint(LatLng point) {
    setState(() {
      if (_selectedPointIndex != null) {
        _currentEditPoints[_selectedPointIndex!] = point;
        _selectedPointIndex = null;
      } else {
        _currentEditPoints.add(point);
      }
    });
  }

  void _undoLastPoint() {
    if (_currentEditPoints.isNotEmpty) {
      setState(() {
        _selectedPointIndex = null;
        _currentEditPoints.removeLast();
      });
    }
  }

  void _clearPoints() {
    setState(() {
      _selectedPointIndex = null;
      _currentEditPoints.clear();
    });
  }

  void _deletePoint(int index) {
    setState(() {
      _currentEditPoints.removeAt(index);
      _selectedPointIndex = null;
    });
  }

  void _insertMidpoint(int afterIndex) {
    final a = _currentEditPoints[afterIndex];
    final b = _currentEditPoints[(afterIndex + 1) % _currentEditPoints.length];
    final mid = LatLng(
      (a.latitude + b.latitude) / 2,
      (a.longitude + b.longitude) / 2,
    );
    setState(() {
      final insertIndex = afterIndex + 1;
      if (insertIndex >= _currentEditPoints.length) {
        _currentEditPoints.add(mid);
        _selectedPointIndex = _currentEditPoints.length - 1;
      } else {
        _currentEditPoints.insert(insertIndex, mid);
        _selectedPointIndex = insertIndex;
      }
    });
  }

  Future<void> _cloneBoundary(String boundaryId) async {
    // אזהרה אם יש שינויים שלא ישמרו
    if (_cloneSourceBoundaryId != null &&
        _cloneSourceBoundaryId != boundaryId &&
        _cloneEditPoints.isNotEmpty) {
      final sourceBoundary = _boundaries
          .where((b) => b.id == _cloneSourceBoundaryId)
          .firstOrNull;
      final originalPoints = sourceBoundary?.coordinates
              .map((c) => LatLng(c.lat, c.lng))
              .toList() ??
          [];
      final hasEdits = _cloneEditPoints.length != originalPoints.length ||
          !_pointsMatch(_cloneEditPoints, originalPoints);
      if (hasEdits) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('שינויים לא שמורים'),
            content: const Text(
              'ביצעת עריכות על הגבול הנוכחי.\n'
              'מעבר לגבול אחר ימחק את השינויים.\n\n'
              'להמשיך?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('ביטול'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('המשך — מחק שינויים'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
      }
    }

    final boundary = _boundaries.firstWhere((b) => b.id == boundaryId);
    setState(() {
      _cloneSourceBoundaryId = boundaryId;
      _polygonPoints =
          boundary.coordinates.map((c) => LatLng(c.lat, c.lng)).toList();
      _selectedPointIndex = null;
    });

    // Zoom to the cloned boundary
    if (_polygonPoints.isNotEmpty) {
      _fitMapToPoints(_polygonPoints);
    }
  }

  /// השוואת שתי רשימות נקודות (סדר חשוב)
  bool _pointsMatch(List<LatLng> a, List<LatLng> b) {
    for (int i = 0; i < a.length; i++) {
      if (a[i].latitude != b[i].latitude || a[i].longitude != b[i].longitude) {
        return false;
      }
    }
    return true;
  }

  void _fitMapToPoints(List<LatLng> points) {
    if (points.isEmpty) return;
    try {
      final bounds = LatLngBounds.fromPoints(points);
      _mapController.fitBounds(
        bounds,
        options: const FitBoundsOptions(padding: EdgeInsets.all(40)),
      );
    } catch (_) {
      // Ignore if map is not ready yet
    }
  }

  // ---------------------------------------------------------------------------
  // Confirm / return result
  // ---------------------------------------------------------------------------

  String get _autoName {
    switch (_mode) {
      case NavBoundaryCreationMode.union:
        final names = _boundaries
            .where((b) => _selectedBoundaryIds.contains(b.id))
            .map((b) => b.name)
            .toList();
        return names.isEmpty ? '' : 'איחוד ${names.join('+')}';
      case NavBoundaryCreationMode.manual:
        return 'גבול ידני';
      case NavBoundaryCreationMode.cloneEdit:
        final source = _boundaries
            .where((b) => b.id == _cloneSourceBoundaryId)
            .firstOrNull;
        return source != null ? '${source.name} ערוך' : '';
      case NavBoundaryCreationMode.legacy:
        return 'גבול ניווט';
    }
  }

  void _confirmSelection() {
    final name = _autoName;
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('לא ניתן ליצור שם אוטומטי — בחר גבולות')),
      );
      return;
    }

    switch (_mode) {
      case NavBoundaryCreationMode.union:
        _confirmUnion(name);
        break;
      case NavBoundaryCreationMode.manual:
        _confirmManualDraw(name);
        break;
      case NavBoundaryCreationMode.cloneEdit:
        _confirmCloneEdit(name);
        break;
      case NavBoundaryCreationMode.legacy:
        break;
    }
  }

  void _confirmUnion(String name) {
    if (_isEditingMultiPolygon) {
      _confirmMultiPolygonEdit(name);
      return;
    }
    if (_selectedBoundaryIds.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('נא לבחור לפחות שני גבולות לאיחוד')),
      );
      return;
    }
    if (_unionResult == null || _unionResult!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('שגיאה בחישוב האיחוד')),
      );
      return;
    }

    if (_isUnionMultiPolygon) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('הגבולות אינם חופפים — יש לבחור אופן חיבור')),
      );
      return;
    }

    // Single polygon
    final coords = _unionResult!.first;
    _showConfirmDialog(BoundarySetupResult(
      coordinates: coords,
      geometryType: 'polygon',
      creationMode: NavBoundaryCreationMode.union,
      sourceBoundaryIds: _selectedBoundaryIds.toList(),
      areaId: widget.areaId,
      name: name,
    ));
  }

  void _confirmManualDraw(String name) {
    if (_polygonPoints.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('נדרשות לפחות 3 נקודות')),
      );
      return;
    }
    final coords = _polygonPoints
        .map((p) => Coordinate(lat: p.latitude, lng: p.longitude, utm: ''))
        .toList();

    _showConfirmDialog(BoundarySetupResult(
      coordinates: coords,
      geometryType: 'polygon',
      creationMode: NavBoundaryCreationMode.manual,
      sourceBoundaryIds: [],
      areaId: widget.areaId,
      name: name,
    ));
  }

  void _confirmCloneEdit(String name) {
    if (_polygonPoints.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('נדרשות לפחות 3 נקודות')),
      );
      return;
    }
    final coords = _polygonPoints
        .map((p) => Coordinate(lat: p.latitude, lng: p.longitude, utm: ''))
        .toList();

    _showConfirmDialog(BoundarySetupResult(
      coordinates: coords,
      geometryType: 'polygon',
      creationMode: NavBoundaryCreationMode.cloneEdit,
      sourceBoundaryIds:
          _cloneSourceBoundaryId != null ? [_cloneSourceBoundaryId!] : [],
      areaId: widget.areaId,
      name: name,
    ));
  }

  void _enterMultiPolygonEditMode() {
    if (_unionResult == null || _unionResult!.isEmpty) return;
    setState(() {
      _isEditingMultiPolygon = true;
      _activePolygonIndex = 0;
      _selectedPointIndex = null;
      _multiPolygonEditorPoints = _unionResult!
          .map((coords) => coords.map((c) => LatLng(c.lat, c.lng)).toList())
          .toList();
    });
  }

  void _confirmMultiPolygonEdit(String name) {
    final valid = _multiPolygonEditorPoints
        .where((pts) => pts.length >= 3)
        .toList();
    if (valid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('נדרש לפחות פוליגון אחד עם 3 נקודות')),
      );
      return;
    }
    final multiCoords = valid
        .map((pts) => pts
            .map((p) => Coordinate(lat: p.latitude, lng: p.longitude, utm: ''))
            .toList())
        .toList();

    // Try to merge edited polygons into a single polygon
    final merged = PolygonOperations.unionPolygons(multiCoords);
    if (merged.length != 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('הגבולות שנערכו אינם חופפים — לא ניתן לאחד לפוליגון אחד'),
        ),
      );
      return;
    }

    _showConfirmDialog(BoundarySetupResult(
      coordinates: merged.first,
      geometryType: 'polygon',
      creationMode: NavBoundaryCreationMode.union,
      sourceBoundaryIds: _selectedBoundaryIds.toList(),
      areaId: widget.areaId,
      name: name,
    ));
  }

  // ---------------------------------------------------------------------------
  // Confirm dialog + map preview
  // ---------------------------------------------------------------------------

  void _showConfirmDialog(BoundarySetupResult result) {
    // Collect all polygon points for preview
    final allPolygons = <List<LatLng>>[];
    if (result.multiPolygonCoordinates != null) {
      for (final coords in result.multiPolygonCoordinates!) {
        allPolygons.add(coords.map((c) => LatLng(c.lat, c.lng)).toList());
      }
    } else {
      allPolygons.add(
        result.coordinates.map((c) => LatLng(c.lat, c.lng)).toList(),
      );
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('אישור גבול ניווט'),
        content: Text(
          'האם לשמור את הגבול "${result.name}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _showPreviewMap(allPolygons);
              if (mounted) _showConfirmDialog(result);
            },
            child: const Text('צפייה במפה'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop<BoundarySetupResult>(context, result);
            },
            child: const Text('אישור'),
          ),
        ],
      ),
    );
  }

  Future<void> _showPreviewMap(List<List<LatLng>> polygons) {
    // Calculate bounds for fitting
    final allPoints = polygons.expand((p) => p).toList();
    final bounds = LatLngBounds.fromPoints(allPoints);

    return showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: const Text('תצוגה מקדימה'),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.6,
              child: MapWithTypeSelector(
                showTypeSelector: false,
                options: MapOptions(
                  initialCameraFit: CameraFit.bounds(
                    bounds: bounds,
                    padding: const EdgeInsets.all(40),
                  ),
                ),
                layers: [
                  PolygonLayer(
                    polygons: polygons.map((pts) => Polygon(
                      points: pts,
                      color: Colors.blue.withOpacity(0.15),
                      borderColor: Colors.blue,
                      borderStrokeWidth: 2.5,
                      isFilled: true,
                    )).toList(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Shared map helpers — reference layers + controls
  // ---------------------------------------------------------------------------

  /// שכבות רקע משותפות — גבולות + נקודות ציון הקיימים בשטח
  List<Widget> _buildReferenceLayers({Set<String>? excludeBoundaryIds}) {
    final layers = <Widget>[];

    // גבולות גזרה קיימים
    if (_showGG && _boundaries.isNotEmpty) {
      final filtered = excludeBoundaryIds != null
          ? _boundaries.where((b) => !excludeBoundaryIds.contains(b.id)).toList()
          : _boundaries;
      if (filtered.isNotEmpty) {
        layers.add(
          PolygonLayer(
            polygons: filtered.map((boundary) {
              return Polygon(
                points: boundary.coordinates
                    .map((c) => LatLng(c.lat, c.lng))
                    .toList(),
                color: Colors.black.withOpacity(0.1 * _ggOpacity),
                borderColor: Colors.black.withOpacity(_ggOpacity),
                borderStrokeWidth: 1.5,
                isFilled: true,
              );
            }).toList(),
          ),
        );
      }
    }

    // נקודות ציון
    if (_showNZ && _checkpoints.isNotEmpty) {
      final pointCheckpoints = _checkpoints
          .where((cp) => cp.geometryType == 'point' && cp.coordinates != null)
          .toList();
      if (pointCheckpoints.isNotEmpty) {
        layers.add(
          MarkerLayer(
            markers: pointCheckpoints.map((cp) {
              final color = _checkpointColor(cp.type);
              return Marker(
                point: LatLng(cp.coordinates!.lat, cp.coordinates!.lng),
                width: 24,
                height: 24,
                child: Opacity(
                  opacity: _nzOpacity,
                  child: Container(
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: Center(
                      child: Text(
                        cp.name.length > 2 ? cp.name.substring(0, 2) : cp.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      }

      // פוליגוני נקודות ציון
      final polyCheckpoints = _checkpoints
          .where((cp) =>
              cp.geometryType == 'polygon' && cp.polygonCoordinates != null)
          .toList();
      if (polyCheckpoints.isNotEmpty) {
        layers.add(
          PolygonLayer(
            polygons: polyCheckpoints.map((cp) {
              final color = _checkpointColor(cp.type);
              return Polygon(
                points: cp.polygonCoordinates!
                    .map((c) => LatLng(c.lat, c.lng))
                    .toList(),
                color: color.withOpacity(0.15 * _nzOpacity),
                borderColor: color.withOpacity(_nzOpacity),
                borderStrokeWidth: 2,
                isFilled: true,
              );
            }).toList(),
          ),
        );
      }
    }

    return layers;
  }

  Color _checkpointColor(String type) {
    switch (type) {
      case 'start':
        return Colors.green;
      case 'end':
        return Colors.red;
      case 'mandatory_passage':
        return Colors.amber;
      default:
        return Colors.blue;
    }
  }

  /// בקרי מפה סטנדרטיים — שכבות, מדידה, חץ צפון, גובה, UTM
  Widget _buildMapControls() {
    return MapControls(
      mapController: _mapController,
      layers: [
        MapLayerConfig(
          id: 'gg',
          label: 'גבולות גזרה',
          color: Colors.black,
          visible: _showGG,
          opacity: _ggOpacity,
          onVisibilityChanged: (v) => setState(() => _showGG = v),
          onOpacityChanged: (v) => setState(() => _ggOpacity = v),
        ),
        MapLayerConfig(
          id: 'nz',
          label: 'נקודות ציון',
          color: Colors.blue,
          visible: _showNZ,
          opacity: _nzOpacity,
          onVisibilityChanged: (v) => setState(() => _showNZ = v),
          onOpacityChanged: (v) => setState(() => _nzOpacity = v),
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
    );
  }

  /// טיפול בלחיצה על מפה — מדידה או פעולת עריכה
  void _handleMapTap(TapPosition tapPosition, LatLng point) {
    if (_measureMode) {
      setState(() => _measurePoints.add(point));
    } else {
      _addPoint(point);
    }
  }

  // ---------------------------------------------------------------------------
  // Auto corridor + merge
  // ---------------------------------------------------------------------------

  void _autoCreateCorridorAndMerge() {
    if (_unionResult == null || _unionResult!.length < 2) return;

    // עותק עבודה — רשימת פוליגונים שנמזג אותם בהדרגה
    final working = _unionResult!.map((p) => List<Coordinate>.from(p)).toList();

    // לולאה: בכל סיבוב מוצאים את הזוג הקרוב ביותר, יוצרים מסדרון ומנסים union
    while (working.length > 1) {
      // מציאת הזוג הקרוב ביותר
      double bestDist = double.infinity;
      int bestI = 0;
      int bestJ = 1;
      for (int i = 0; i < working.length; i++) {
        for (int j = i + 1; j < working.length; j++) {
          final closest =
              PolygonOperations.findClosestPoints(working[i], working[j]);
          final d = PolygonOperations.distanceBetween(closest.a, closest.b);
          if (d < bestDist) {
            bestDist = d;
            bestI = i;
            bestJ = j;
          }
        }
      }

      // יצירת מסדרון — רוחב = max(distance * 1.2, 50)
      final closest =
          PolygonOperations.findClosestPoints(working[bestI], working[bestJ]);
      final corridorWidth = bestDist * 1.2 < 50 ? 50.0 : bestDist * 1.2;
      final corridor = PolygonOperations.createCorridor(
        closest.a,
        closest.b,
        corridorWidth,
      );

      // ניסיון union של הזוג + מסדרון
      final merged = PolygonOperations.unionPolygons([
        working[bestI],
        working[bestJ],
        corridor,
      ]);

      // הסרת הזוג (מהסוף קודם כדי לא לפגוע באינדקסים)
      working.removeAt(bestJ);
      working.removeAt(bestI);

      if (merged.length == 1) {
        // union הצליח — מוסיפים את התוצאה המאוחדת
        working.add(merged.first);
      } else {
        // union נכשל — מוסיפים את כל החלקים (פוליגונים + מסדרון) לעריכה ידנית
        working.addAll(merged);
        break; // עוצרים — המשתמש יערוך ידנית
      }
    }

    // כניסה למצב עריכת multi-polygon עם התוצאה
    setState(() {
      _isEditingMultiPolygon = true;
      _selectedPointIndex = null;
      _multiPolygonEditorPoints = working
          .map((coords) => coords.map((c) => LatLng(c.lat, c.lng)).toList())
          .toList();
      _activePolygonIndex = _multiPolygonEditorPoints.length - 1;
    });

    // Zoom למפה
    final allPoints =
        _multiPolygonEditorPoints.expand((pts) => pts).toList();
    if (allPoints.isNotEmpty) {
      _fitMapToPoints(allPoints);
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const Text('גבול ניווט'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          if (!_isLoading)
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _confirmSelection,
              tooltip: 'אישור',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Mode selector
                if (!_isEditingMultiPolygon)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<NavBoundaryCreationMode>(
                        segments: const [
                          ButtonSegment(
                            value: NavBoundaryCreationMode.union,
                            label: Text('איחוד גבולות'),
                            icon: Icon(Icons.join_full),
                          ),
                          ButtonSegment(
                            value: NavBoundaryCreationMode.manual,
                            label: Text('ציור גבול ניווט ידני'),
                            icon: Icon(Icons.draw),
                          ),
                          ButtonSegment(
                            value: NavBoundaryCreationMode.cloneEdit,
                            label: Text('שכפול ג"ג קיים ועריכתו'),
                            icon: Icon(Icons.content_copy),
                          ),
                        ],
                        selected: {_mode},
                        onSelectionChanged: (selected) {
                          setState(() {
                            _mode = selected.first;
                            // Reset editor state when switching modes
                            _selectedPointIndex = null;
                          });
                        },
                      ),
                    ),
                  ),
                // Mode-specific content
                Expanded(child: _buildModeContent()),
              ],
            ),
    );
  }

  Widget _buildModeContent() {
    switch (_mode) {
      case NavBoundaryCreationMode.union:
        return _isEditingMultiPolygon
            ? _buildMultiPolygonEditor()
            : _buildUnionMode();
      case NavBoundaryCreationMode.manual:
        return _buildManualMode();
      case NavBoundaryCreationMode.cloneEdit:
        return _buildCloneEditMode();
      case NavBoundaryCreationMode.legacy:
        return const Center(child: Text('מצב לא נתמך'));
    }
  }

  // ---------------------------------------------------------------------------
  // Mode 1: Union
  // ---------------------------------------------------------------------------

  Widget _buildUnionMode() {
    return Column(
      children: [
        // Boundary selection list
        if (_boundaries.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'לא נמצאו גבולות גזרה בשטח זה',
              style: TextStyle(color: Colors.grey),
            ),
          )
        else
          Container(
            constraints: const BoxConstraints(maxHeight: 180),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _boundaries.length,
              itemBuilder: (context, index) {
                final boundary = _boundaries[index];
                final isSelected =
                    _selectedBoundaryIds.contains(boundary.id);
                final color =
                    _boundaryColors[index % _boundaryColors.length];
                return CheckboxListTile(
                  dense: true,
                  value: isSelected,
                  onChanged: (_) => _toggleBoundarySelection(boundary.id),
                  title: Text(boundary.name),
                  subtitle: Text('${boundary.coordinates.length} נקודות'),
                  secondary: CircleAvatar(
                    radius: 12,
                    backgroundColor: color,
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        // Multi-polygon warning + actions
        if (_isUnionMultiPolygon && _unionResult != null) ...[
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.shade300),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: Colors.amber.shade700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'הגבולות שנבחרו אינם חופפים — נוצרו ${_unionResult!.length} פוליגונים נפרדים',
                        style: TextStyle(
                          color: Colors.amber.shade900,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _autoCreateCorridorAndMerge,
                        icon: const Icon(Icons.route, size: 18),
                        label: const Text('יצירת מסדרון אוטומטי'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.blue.shade700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _enterMultiPolygonEditMode,
                        icon: const Icon(Icons.layers, size: 18),
                        label: const Text(
                          'חיבור פוליגונים ידני',
                          style: TextStyle(fontSize: 12),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.purple.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        // Map
        Expanded(child: _buildUnionMap()),
      ],
    );
  }

  Widget _buildUnionMap() {
    return Stack(
      children: [
        MapWithTypeSelector(
          showTypeSelector: false,
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _defaultCenter,
            initialZoom: 8,
            onTap: _measureMode
                ? (_, point) => setState(() => _measurePoints.add(point))
                : null,
          ),
          layers: [
            // Reference layers (checkpoints)
            ..._buildReferenceLayers(excludeBoundaryIds: _boundaries.map((b) => b.id).toSet()),
            // Selected boundaries in unique colors
            if (_boundaries.isNotEmpty)
              PolygonLayer(
                polygons: _boundaries
                    .asMap()
                    .entries
                    .where((e) => _selectedBoundaryIds.contains(e.value.id))
                    .map((entry) {
                  final color =
                      _boundaryColors[entry.key % _boundaryColors.length];
                  return Polygon(
                    points: entry.value.coordinates
                        .map((c) => LatLng(c.lat, c.lng))
                        .toList(),
                    color: color.withOpacity(0.15),
                    borderColor: color,
                    borderStrokeWidth: 2.5,
                    isFilled: true,
                  );
                }).toList(),
              ),
            // Non-selected boundaries (faded)
            if (_boundaries.isNotEmpty)
              PolygonLayer(
                polygons: _boundaries
                    .where((b) => !_selectedBoundaryIds.contains(b.id))
                    .map((boundary) {
                  return Polygon(
                    points: boundary.coordinates
                        .map((c) => LatLng(c.lat, c.lng))
                        .toList(),
                    color: Colors.grey.withOpacity(0.05),
                    borderColor: Colors.grey.withOpacity(0.3),
                    borderStrokeWidth: 1.5,
                    isFilled: true,
                  );
                }).toList(),
              ),
            // Union preview (green)
            if (_unionResult != null && !_isUnionMultiPolygon)
              PolygonLayer(
                polygons: _unionResult!.map((coords) {
                  return Polygon(
                    points: coords.map((c) => LatLng(c.lat, c.lng)).toList(),
                    color: Colors.green.withOpacity(0.2),
                    borderColor: Colors.green.shade700,
                    borderStrokeWidth: 3,
                    isFilled: true,
                  );
                }).toList(),
              ),
            // Multi-polygon preview (orange outline per polygon)
            if (_unionResult != null && _isUnionMultiPolygon)
              PolygonLayer(
                polygons: _unionResult!.asMap().entries.map((entry) {
                  final color =
                      _boundaryColors[entry.key % _boundaryColors.length];
                  return Polygon(
                    points:
                        entry.value.map((c) => LatLng(c.lat, c.lng)).toList(),
                    color: color.withOpacity(0.1),
                    borderColor: color,
                    borderStrokeWidth: 2,
                    isFilled: true,
                  );
                }).toList(),
              ),
            // Measurement overlay
            ...MapControls.buildMeasureLayers(_measurePoints),
          ],
        ),
        _buildMapControls(),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Mode 2: Manual draw
  // ---------------------------------------------------------------------------

  Widget _buildManualMode() {
    return Column(
      children: [
        _buildEditorToolbar(),
        Expanded(child: _buildPolygonEditorMap()),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Mode 3: Clone edit
  // ---------------------------------------------------------------------------

  Widget _buildCloneEditMode() {
    return Column(
      children: [
        // Title
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              'בחר גבול גזרה לשכפול',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
        ),
        // Boundary selection list (single selection)
        if (_boundaries.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'לא נמצאו גבולות גזרה בשטח זה',
              style: TextStyle(color: Colors.grey),
            ),
          )
        else
          Container(
            constraints: const BoxConstraints(maxHeight: 180),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _boundaries.length,
              itemBuilder: (context, index) {
                final boundary = _boundaries[index];
                final isSelected = _cloneSourceBoundaryId == boundary.id;
                final color =
                    _boundaryColors[index % _boundaryColors.length];
                return RadioListTile<String>(
                  dense: true,
                  controlAffinity: ListTileControlAffinity.trailing,
                  value: boundary.id,
                  groupValue: _cloneSourceBoundaryId,
                  onChanged: (id) {
                    if (id != null) _cloneBoundary(id);
                  },
                  title: Text(boundary.name),
                  subtitle: Text('${boundary.coordinates.length} נקודות'),
                  secondary: CircleAvatar(
                    radius: 12,
                    backgroundColor: color,
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        _buildEditorToolbar(),
        Expanded(child: _buildPolygonEditorMap()),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Shared polygon editor UI
  // ---------------------------------------------------------------------------

  Widget _buildEditorToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.grey[200],
      child: Row(
        children: [
          Icon(
            _selectedPointIndex != null ? Icons.open_with : Icons.touch_app,
            size: 20,
            color: _selectedPointIndex != null
                ? Colors.green[700]
                : Colors.grey[700],
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _selectedPointIndex != null
                  ? 'לחץ על המפה להזיז נקודה ${_selectedPointIndex! + 1}'
                  : _currentEditPoints.isEmpty
                      ? 'לחץ על המפה להתחלת ציור הגבול'
                      : 'נקודות: ${_currentEditPoints.length}',
              style: TextStyle(
                color: _selectedPointIndex != null
                    ? Colors.green[700]
                    : Colors.grey[700],
                fontWeight: _selectedPointIndex != null
                    ? FontWeight.bold
                    : FontWeight.normal,
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
          if (_currentEditPoints.isNotEmpty) ...[
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
    );
  }

  Widget _buildPolygonEditorMap() {
    return Stack(
      children: [
        MapWithTypeSelector(
          showTypeSelector: false,
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _defaultCenter,
            initialZoom: 8,
            onTap: (tapPosition, point) => _handleMapTap(tapPosition, point),
          ),
          layers: [
            // Reference layers (boundaries + checkpoints)
            ..._buildReferenceLayers(),
            // Drawn polygon — outline
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
            // Drawn polygon — filled
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
            // Midpoint markers (insert vertex)
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
                          color: Colors.blue.withOpacity(0.5),
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
            // Vertex markers
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
                            color:
                                isSelected ? Colors.greenAccent : Colors.white,
                            width: isSelected ? 3 : 2,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: Colors.green.withOpacity(0.5),
                                    blurRadius: 8,
                                    spreadRadius: 2,
                                  ),
                                ]
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
            // Measurement overlay
            ...MapControls.buildMeasureLayers(_measurePoints),
          ],
        ),
        _buildMapControls(),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Multi-polygon editor (union sub-mode)
  // ---------------------------------------------------------------------------

  Widget _buildMultiPolygonEditor() {
    return Column(
      children: [
        _buildPolygonSelectorStrip(),
        _buildEditorToolbar(),
        Expanded(child: _buildMultiPolygonEditorMap()),
      ],
    );
  }

  Widget _buildPolygonSelectorStrip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: Colors.grey[100],
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(_multiPolygonEditorPoints.length, (index) {
            final pts = _multiPolygonEditorPoints[index];
            final isActive = index == _activePolygonIndex;
            return Padding(
              padding: const EdgeInsets.only(left: 6),
              child: ChoiceChip(
                label: Text('פוליגון ${index + 1} (${pts.length} נק\')'),
                selected: isActive,
                selectedColor: Colors.green.shade100,
                onSelected: (_) {
                  setState(() {
                    _activePolygonIndex = index;
                    _selectedPointIndex = null;
                  });
                },
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildMultiPolygonEditorMap() {
    final activePoints = _multiPolygonEditorPoints[_activePolygonIndex];

    return Stack(
      children: [
        MapWithTypeSelector(
          showTypeSelector: false,
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _defaultCenter,
            initialZoom: 8,
            onTap: (tapPosition, point) => _handleMapTap(tapPosition, point),
          ),
          layers: [
            // Reference layers (checkpoints only — boundaries are the polygons being edited)
            ..._buildReferenceLayers(excludeBoundaryIds: _boundaries.map((b) => b.id).toSet()),
            // All polygons (filled + border)
            PolygonLayer(
              polygons: _multiPolygonEditorPoints.asMap().entries.map((entry) {
                final isActive = entry.key == _activePolygonIndex;
                final pts = entry.value;
                if (pts.length < 3) return null;
                final color = isActive
                    ? Colors.green
                    : _boundaryColors[entry.key % _boundaryColors.length];
                return Polygon(
                  points: pts,
                  color: color.withOpacity(isActive ? 0.15 : 0.08),
                  borderColor: isActive ? Colors.green.shade700 : color.withOpacity(0.6),
                  borderStrokeWidth: isActive ? 3 : 2,
                  isFilled: true,
                );
              }).whereType<Polygon>().toList(),
            ),
            // Active polygon outline (polyline for < 3 points)
            if (activePoints.length >= 2 && activePoints.length < 3)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: activePoints,
                    color: Colors.green.shade700,
                    strokeWidth: 3,
                  ),
                ],
              ),
            // Midpoint markers on active polygon
            if (activePoints.length >= 3)
              MarkerLayer(
                markers: List.generate(activePoints.length, (i) {
                  final a = activePoints[i];
                  final b = activePoints[(i + 1) % activePoints.length];
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
                          color: Colors.blue.withOpacity(0.5),
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
            // Vertex markers on active polygon
            if (activePoints.isNotEmpty)
              MarkerLayer(
                markers: activePoints.asMap().entries.map((entry) {
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
                          color: isSelected ? Colors.green : Colors.green.shade800,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? Colors.greenAccent : Colors.white,
                            width: isSelected ? 3 : 2,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: Colors.green.withOpacity(0.5),
                                    blurRadius: 8,
                                    spreadRadius: 2,
                                  ),
                                ]
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
            // Measurement overlay
            ...MapControls.buildMeasureLayers(_measurePoints),
          ],
        ),
        _buildMapControls(),
      ],
    );
  }
}

