import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import '../../domain/entities/boundary.dart';
import '../../domain/entities/coordinate.dart';
import 'terrain_ffi_bridge.dart';
import 'terrain_models.dart';
import 'terrain_cache_service.dart';

const bool terrainIsSupported =
    bool.fromEnvironment('TERRAIN_ENABLED', defaultValue: false);

/// שירות ניתוח שטח ראשי — Singleton
/// מנהל טעינת DEM, תקשורת עם מנוע C++ דרך FFI, ומטמון תוצאות
class TerrainAnalysisService {
  static final TerrainAnalysisService _instance =
      TerrainAnalysisService._internal();
  factory TerrainAnalysisService() => _instance;
  TerrainAnalysisService._internal() {
    if (terrainIsSupported) {
      _ffi = TerrainFFIBridge();
      _cache = TerrainCacheService();
    }
  }

  TerrainFFIBridge? _ffi;
  TerrainCacheService? _cache;
  late Directory _demDir;
  bool _initialized = false;
  bool get isAvailable => terrainIsSupported && (_ffi?.isAvailable ?? false);

  /// מטמון DEM — שם אריח → נתונים גולמיים
  final Map<String, Int16List> _demCache = {};

  /// גודל רשת לכל אריח (3601 ל-SRTM1, 1201 ל-SRTM3)
  final Map<String, int> _gridSizes = {};

  // Active boundary sub-grid state
  Boundary? _activeBoundary;
  Int16List? _activeDem;
  int _activeRows = 0;
  int _activeCols = 0;
  int _activeMinRow = 0;
  int _activeMinCol = 0;
  int _activeSrcGridSize = 0;
  int _activeSrcTileLat = 0;
  int _activeSrcTileLng = 0;
  LatLngBounds? _activeBounds;
  TerrainFeaturesResult? _cachedFeatures;
  Uint8List? _boundaryMask; // 1=inside polygon, 0=outside

  // Public getters
  Uint8List? get boundaryMask => _boundaryMask;
  int get activeRows => _activeRows;
  int get activeCols => _activeCols;
  LatLngBounds? get activeBounds => _activeBounds;

  // תיקון היסט אופקי של SRTM — הזזה שיטתית (CE90 ~10-20m)
  double _demLatOffset = 0.00008; // ~9m צפונה
  double _demLngOffset = -0.00015; // ~13m מערבה

  /// עדכון היסט DEM — לכיול ידני
  void setDemOffset(double latOffset, double lngOffset) {
    _demLatOffset = latOffset;
    _demLngOffset = lngOffset;
    if (_activeDem != null) _recomputeActiveBounds();
  }

  (double, double) get demOffset => (_demLatOffset, _demLngOffset);

  /// חישוב מחדש של גבולות תת-הרשת עם היסט נוכחי
  void _recomputeActiveBounds() {
    final step = 1.0 / (_activeSrcGridSize - 1);
    final north = (_activeSrcTileLat + 1.0) - _activeMinRow * step + _demLatOffset;
    final south = (_activeSrcTileLat + 1.0) - (_activeMinRow + _activeRows - 1) * step + _demLatOffset;
    final west = _activeSrcTileLng.toDouble() + _activeMinCol * step + _demLngOffset;
    final east = _activeSrcTileLng.toDouble() + (_activeMinCol + _activeCols - 1) * step + _demLngOffset;
    _activeBounds = LatLngBounds(LatLng(south, west), LatLng(north, east));
  }

  // קבועי SRTM
  static const int srtm1GridSize = 3601;
  static const int srtm1FileSize = srtm1GridSize * srtm1GridSize * 2;
  static const int srtm3GridSize = 1201;
  static const int srtm3FileSize = srtm3GridSize * srtm3GridSize * 2;

  /// אריחים מוטמעים (SRTM3 — 1201x1201) — כיסוי ישראל
  static const List<String> _bundledTiles = [
    'N29E034',
    'N29E035',
    'N30E034',
    'N30E035',
    'N31E034',
    'N31E035',
    'N32E034',
    'N32E035',
    'N33E034',
    'N33E035',
  ];

  /// גודל תא (מטרים) בכיוון צפון-דרום
  static double cellSizeNS(int gridSize) => 30.87 * (3601.0 / gridSize);

  /// גודל תא (מטרים) בכיוון מזרח-מערב — תלוי בקו רוחב
  static double cellSizeEW(double lat, int gridSize) =>
      30.87 * cos(lat * pi / 180) * (3601.0 / gridSize);

  /// אתחול השירות — יצירת תיקיות ואתחול מטמון
  Future<void> initialize() async {
    if (!terrainIsSupported) return;
    if (_initialized) return;
    final docsDir = await getApplicationDocumentsDirectory();
    _demDir = Directory('${docsDir.path}/terrain_dem');
    if (!await _demDir.exists()) await _demDir.create(recursive: true);
    await _cache?.initialize();
    _initialized = true;
  }

  /// שם אריח — לדוגמה "N31E034"
  String tileName(int lat, int lng) {
    final ns = lat >= 0 ? 'N' : 'S';
    final ew = lng >= 0 ? 'E' : 'W';
    return '$ns${lat.abs().toString().padLeft(2, '0')}$ew${lng.abs().toString().padLeft(3, '0')}';
  }

  /// גבולות אריח — מהפינה הדרום-מערבית לצפון-מזרחית
  LatLngBounds getTileBounds(int lat, int lng) {
    return LatLngBounds(
      LatLng(lat.toDouble(), lng.toDouble()),
      LatLng(lat.toDouble() + 1.0, lng.toDouble() + 1.0),
    );
  }

  /// בדיקה אם אריח טעון בזיכרון
  bool hasTile(int lat, int lng) => _demCache.containsKey(tileName(lat, lng));

  /// גודל רשת של אריח טעון
  int getGridSize(int lat, int lng) =>
      _gridSizes[tileName(lat, lng)] ?? srtm1GridSize;

  /// טעינת אריח DEM — מדיסק מקומי, מ-assets מוטמעים, או הורדה מ-AWS
  Future<bool> loadDemTile(int lat, int lng) async {
    if (!terrainIsSupported || !_initialized) return false;
    final name = tileName(lat, lng);
    if (_demCache.containsKey(name)) return true;

    // 1. בדיקת קובץ SRTM1 מקומי
    final file = File('${_demDir.path}/$name.hgt');
    if (await file.exists()) {
      final bytes = await file.readAsBytes();
      if (bytes.length == srtm1FileSize) {
        _demCache[name] = _parseBigEndianInt16(bytes);
        _gridSizes[name] = srtm1GridSize;
        return true;
      } else if (bytes.length == srtm3FileSize) {
        _demCache[name] = _parseBigEndianInt16(bytes);
        _gridSizes[name] = srtm3GridSize;
        return true;
      }
    }

    // 2. ניסיון טעינה מ-asset מוטמע (SRTM3)
    if (_bundledTiles.contains(name)) {
      try {
        final byteData = await rootBundle.load('assets/elevation/$name.hgt');
        final bytes = byteData.buffer.asUint8List();
        if (bytes.length == srtm3FileSize) {
          _demCache[name] = _parseBigEndianInt16(bytes);
          _gridSizes[name] = srtm3GridSize;
          return true;
        }
      } catch (_) {
        // asset לא נמצא — ממשיך להורדה
      }
    }

    // 3. הורדת SRTM1 מ-AWS
    try {
      final ns = lat >= 0 ? 'N' : 'S';
      final latPad = lat.abs().toString().padLeft(2, '0');
      final url =
          'https://elevation-tiles-prod.s3.amazonaws.com/skadi/$ns$latPad/$name.hgt.gz';

      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) return false;

      // פריסת קובץ GZip
      final decoded = GZipDecoder().decodeBytes(response.bodyBytes);

      int gridSize;
      if (decoded.length == srtm1FileSize) {
        gridSize = srtm1GridSize;
      } else if (decoded.length == srtm3FileSize) {
        gridSize = srtm3GridSize;
      } else {
        return false;
      }

      // שמירה לדיסק לשימוש עתידי
      await file.writeAsBytes(decoded);

      _demCache[name] = _parseBigEndianInt16(Uint8List.fromList(decoded));
      _gridSizes[name] = gridSize;
      return true;
    } catch (e) {
      print('DEBUG TerrainAnalysisService: שגיאת הורדה: $e');
      return false;
    }
  }

  /// המרת בתים big-endian ל-signed int16
  Int16List _parseBigEndianInt16(Uint8List bytes) {
    final count = bytes.length ~/ 2;
    final data = Int16List(count);
    for (int i = 0; i < count; i++) {
      int value = (bytes[i * 2] << 8) | bytes[i * 2 + 1];
      // המרה מ-unsigned ל-signed
      if (value >= 32768) value -= 65536;
      data[i] = value;
    }
    return data;
  }

  /// המרת שורה/עמודה ברשת לקואורדינטה גיאוגרפית
  LatLng gridToLatLng(
      int row, int col, int tileLat, int tileLng, int gridSize) {
    final step = 1.0 / (gridSize - 1);
    // שורה 0 = צפון (tileLat + 1), שורה אחרונה = דרום (tileLat)
    return LatLng(
      (tileLat + 1.0) - row * step,
      tileLng.toDouble() + col * step,
    );
  }

  /// המרת קואורדינטה גיאוגרפית לשורה/עמודה ברשת
  (int row, int col) latLngToGrid(
      LatLng pos, int tileLat, int tileLng, int gridSize) {
    final step = 1.0 / (gridSize - 1);
    final row = (((tileLat + 1.0) - pos.latitude) / step)
        .round()
        .clamp(0, gridSize - 1);
    final col = ((pos.longitude - tileLng.toDouble()) / step)
        .round()
        .clamp(0, gridSize - 1);
    return (row, col);
  }

  // ---------------------------------------------------------------------------
  // Boundary sub-grid — טעינת DEM וחילוץ תת-רשת לגבול גזרה
  // ---------------------------------------------------------------------------

  /// Load DEM and extract sub-grid for boundary — all computations will use this sub-grid
  Future<bool> loadForBoundary(Boundary boundary, int tileLat, int tileLng) async {
    if (!terrainIsSupported) return false;
    if (!await loadDemTile(tileLat, tileLng)) return false;

    _activeBoundary = boundary;
    _cachedFeatures = null;
    _activeSrcTileLat = tileLat;
    _activeSrcTileLng = tileLng;

    final name = tileName(tileLat, tileLng);
    final fullDem = _demCache[name]!;
    final gridSize = _gridSizes[name]!;
    _activeSrcGridSize = gridSize;

    // Compute bounding box of boundary in grid coords
    int minRow = gridSize - 1, maxRow = 0, minCol = gridSize - 1, maxCol = 0;
    for (final coord in boundary.coordinates) {
      final (row, col) = latLngToGrid(LatLng(coord.lat, coord.lng), tileLat, tileLng, gridSize);
      minRow = min(minRow, row);
      maxRow = max(maxRow, row);
      minCol = min(minCol, col);
      maxCol = max(maxCol, col);
    }

    // Add padding for kernel operations (TPI uses 21×21)
    const padding = 15;
    minRow = max(0, minRow - padding);
    maxRow = min(gridSize - 1, maxRow + padding);
    minCol = max(0, minCol - padding);
    maxCol = min(gridSize - 1, maxCol + padding);

    _activeMinRow = minRow;
    _activeMinCol = minCol;
    _activeRows = maxRow - minRow + 1;
    _activeCols = maxCol - minCol + 1;

    // Extract sub-grid
    _activeDem = Int16List(_activeRows * _activeCols);
    for (int r = 0; r < _activeRows; r++) {
      for (int c = 0; c < _activeCols; c++) {
        _activeDem![r * _activeCols + c] = fullDem[(minRow + r) * gridSize + (minCol + c)];
      }
    }

    // Compute sub-grid geographic bounds (with DEM alignment offset)
    final step = 1.0 / (gridSize - 1);
    final north = (tileLat + 1.0) - minRow * step + _demLatOffset;
    final south = (tileLat + 1.0) - (minRow + _activeRows - 1) * step + _demLatOffset;
    final west = tileLng.toDouble() + minCol * step + _demLngOffset;
    final east = tileLng.toDouble() + (minCol + _activeCols - 1) * step + _demLngOffset;
    _activeBounds = LatLngBounds(LatLng(south, west), LatLng(north, east));

    // Create polygon mask using ray-casting
    _boundaryMask = Uint8List(_activeRows * _activeCols);
    final polyCoords = boundary.coordinates;
    for (int r = 0; r < _activeRows; r++) {
      for (int c = 0; c < _activeCols; c++) {
        final lat = north - r * step;
        final lng = west + c * step;
        _boundaryMask![r * _activeCols + c] = _isInsidePolygon(lat, lng, polyCoords) ? 1 : 0;
      }
    }

    return true;
  }

  /// Ray-casting point-in-polygon test
  bool _isInsidePolygon(double lat, double lng, List<Coordinate> polygon) {
    bool inside = false;
    int j = polygon.length - 1;
    for (int i = 0; i < polygon.length; i++) {
      if ((polygon[i].lng > lng) != (polygon[j].lng > lng) &&
          lat < (polygon[j].lat - polygon[i].lat) * (lng - polygon[i].lng) /
              (polygon[j].lng - polygon[i].lng) + polygon[i].lat) {
        inside = !inside;
      }
      j = i;
    }
    return inside;
  }

  // ---------------------------------------------------------------------------
  // Sub-grid coordinate helpers
  // ---------------------------------------------------------------------------

  LatLng _subGridToLatLng(int row, int col) {
    final step = 1.0 / (_activeSrcGridSize - 1);
    return LatLng(
      (_activeSrcTileLat + 1.0) - (_activeMinRow + row) * step + _demLatOffset,
      _activeSrcTileLng.toDouble() + (_activeMinCol + col) * step + _demLngOffset,
    );
  }

  (int row, int col) _latLngToSubGrid(LatLng pos) {
    final step = 1.0 / (_activeSrcGridSize - 1);
    // הסרת ההיסט כדי לחזור לקואורדינטות DEM מקוריות
    final rawLat = pos.latitude - _demLatOffset;
    final rawLng = pos.longitude - _demLngOffset;
    final fullRow = ((_activeSrcTileLat + 1.0 - rawLat) / step).round();
    final fullCol = ((rawLng - _activeSrcTileLng.toDouble()) / step).round();
    return (
      (fullRow - _activeMinRow).clamp(0, _activeRows - 1),
      (fullCol - _activeMinCol).clamp(0, _activeCols - 1),
    );
  }

  // ---------------------------------------------------------------------------
  // 6 שיטות ניתוח — כל אחת משתמשת בתת-הרשת הפעילה
  // ---------------------------------------------------------------------------

  /// חישוב שיפוע ונטייה לתת-הרשת הפעילה
  Future<SlopeAspectResult?> computeSlopeAspect() async {
    if (!isAvailable || _activeDem == null) return null;

    final centerLat = (_activeBounds!.north + _activeBounds!.south) / 2;
    final ns = cellSizeNS(_activeSrcGridSize);
    final ew = cellSizeEW(centerLat, _activeSrcGridSize);

    // קריאה לפונקציית FFI
    final ffiResult = _ffi!.computeSlopeAspect(
        _activeDem!, _activeRows, _activeCols, ns, ew);
    if (ffiResult == null) return null;

    return SlopeAspectResult(
      slopeGrid: ffiResult.slope,
      aspectGrid: ffiResult.aspect,
      rows: _activeRows,
      cols: _activeCols,
      bounds: _activeBounds!,
    );
  }

  /// סיווג תוואי שטח — דורש חישוב שיפוע/נטייה קודם
  Future<TerrainFeaturesResult?> classifyFeatures() async {
    if (!isAvailable || _activeDem == null) return null;

    // חישוב שיפוע/נטייה — דרוש כקלט לסיווג
    final slopeAspect = await computeSlopeAspect();
    if (slopeAspect == null) return null;

    final centerLat = (_activeBounds!.north + _activeBounds!.south) / 2;
    final ns = cellSizeNS(_activeSrcGridSize);
    final ew = cellSizeEW(centerLat, _activeSrcGridSize);

    // קריאה לפונקציית FFI
    final features = _ffi!.classifyFeatures(
      _activeDem!,
      slopeAspect.slopeGrid,
      slopeAspect.aspectGrid,
      _activeRows,
      _activeCols,
      ns,
      ew,
    );
    if (features == null) return null;

    final result = TerrainFeaturesResult(
      featureGrid: features,
      rows: _activeRows,
      cols: _activeCols,
      bounds: _activeBounds!,
    );
    _cachedFeatures = result;
    return result;
  }

  /// חישוב קו ראייה מנקודת תצפית נתונה
  Future<ViewshedResult?> computeViewshed(
    LatLng observer, {
    double height = 1.7,
    double maxDistKm = 5.0,
  }) async {
    if (!isAvailable || _activeDem == null) return null;

    final centerLat = (_activeBounds!.north + _activeBounds!.south) / 2;
    final ns = cellSizeNS(_activeSrcGridSize);
    final ew = cellSizeEW(centerLat, _activeSrcGridSize);

    // המרת מיקום הצופה לשורה/עמודה בתת-רשת
    final (obsRow, obsCol) = _latLngToSubGrid(observer);
    // המרת מרחק מקסימלי מק"מ לתאי רשת
    final maxDistCells = (maxDistKm * 1000.0) / ns;

    // קריאה לפונקציית FFI
    final visible = _ffi!.computeViewshed(
      _activeDem!,
      _activeRows,
      _activeCols,
      ns,
      ew,
      obsRow,
      obsCol,
      height,
      maxDistCells,
    );
    if (visible == null) return null;

    return ViewshedResult(
      visibleGrid: visible,
      rows: _activeRows,
      cols: _activeCols,
      bounds: _activeBounds!,
      observerPosition: observer,
      observerHeight: height,
    );
  }

  /// חישוב מסלול נסתר — מנסה למזער חשיפה לתצפית אויב
  Future<HiddenPath?> computeHiddenPath(
    LatLng start,
    LatLng end,
    List<LatLng> enemies, {
    double enemyHeight = 1.7,
    double exposureWeight = 100.0,
  }) async {
    if (!terrainIsSupported) return null;
    if (_activeDem == null || enemies.isEmpty) return null;

    // Compute viewshed for each enemy and combine
    Uint8List? combinedViewshed;
    for (final enemy in enemies) {
      final vs = await computeViewshed(enemy, height: enemyHeight);
      if (vs == null) continue;
      if (combinedViewshed == null) {
        combinedViewshed = Uint8List.fromList(vs.visibleGrid);
      } else {
        // OR-combine: visible from ANY enemy = visible
        for (int i = 0; i < combinedViewshed.length; i++) {
          if (vs.visibleGrid[i] == 1) combinedViewshed[i] = 1;
        }
      }
    }

    if (combinedViewshed == null) return null;

    final centerLat = (_activeBounds!.north + _activeBounds!.south) / 2;
    final ns = cellSizeNS(_activeSrcGridSize);
    final ew = cellSizeEW(centerLat, _activeSrcGridSize);

    // המרת נקודות התחלה וסיום לשורות/עמודות בתת-רשת
    final (startRow, startCol) = _latLngToSubGrid(start);
    final (endRow, endCol) = _latLngToSubGrid(end);

    // קריאה לפונקציית FFI
    final pathResult = _ffi!.computeHiddenPath(
      _activeDem!,
      combinedViewshed,
      _activeRows,
      _activeCols,
      ns,
      ew,
      startRow,
      startCol,
      endRow,
      endCol,
      exposureWeight,
    );
    if (pathResult == null || pathResult.length == 0) return null;

    // המרת נתוני המסלול לנקודות גיאוגרפיות
    final points = <LatLng>[];
    int exposedCount = 0;
    for (int i = 0; i < pathResult.length; i++) {
      points.add(_subGridToLatLng(pathResult.rows[i], pathResult.cols[i]));
      // ספירת נקודות חשופות לתצפית
      if (combinedViewshed[pathResult.rows[i] * _activeCols + pathResult.cols[i]] == 1) {
        exposedCount++;
      }
    }

    // חישוב מרחק כולל של המסלול
    double totalDist = 0;
    for (int i = 1; i < points.length; i++) {
      totalDist +=
          const Distance().as(LengthUnit.Meter, points[i - 1], points[i]);
    }

    return HiddenPath(
      points: points,
      totalDistanceMeters: totalDist,
      exposurePercent: pathResult.length > 0
          ? (exposedCount / pathResult.length * 100)
          : 0,
    );
  }

  /// זיהוי נקודות ציון חכמות — כיפות, רכסים, צמתים ועוד
  Future<List<SmartWaypoint>> detectSmartWaypoints({
    double minProminence = 10.0,
    int minFeatureCells = 5,
  }) async {
    if (!isAvailable || _activeDem == null) return [];

    // חישוב שיפוע וסיווג תוואי — דרושים כקלט
    final slopeAspect = await computeSlopeAspect();
    if (slopeAspect == null) return [];
    final features = await classifyFeatures();
    if (features == null) return [];

    final centerLat = (_activeBounds!.north + _activeBounds!.south) / 2;
    final ns = cellSizeNS(_activeSrcGridSize);
    final ew = cellSizeEW(centerLat, _activeSrcGridSize);

    // קריאה לפונקציית FFI
    final result = _ffi!.detectSmartWaypoints(
      _activeDem!,
      slopeAspect.slopeGrid,
      features.featureGrid,
      _activeRows,
      _activeCols,
      ns,
      ew,
      minProminence,
      minFeatureCells,
    );
    if (result == null) return [];

    // מיפוי סוגי C++ לסוגי Dart
    // C++ enum (1-based): 1=dome, 2=hiddenDome, 3=streamSplit,
    //   4=ridge(→saddle), 5=spur(→shoulder), 6=valleyJunction, 7=saddle, 8=localPeak
    const cppTypeMap = <int, SmartWaypointType>{
      1: SmartWaypointType.domeCenter,
      2: SmartWaypointType.hiddenDome,
      3: SmartWaypointType.streamSplit,
      4: SmartWaypointType.saddlePoint,    // ridge → אוכף
      5: SmartWaypointType.shoulder,        // spur → כתף
      6: SmartWaypointType.valleyJunction,
      7: SmartWaypointType.saddlePoint,
      8: SmartWaypointType.localPeak,
    };

    // המרת תוצאות לאובייקטי SmartWaypoint
    final waypoints = <SmartWaypoint>[];
    for (int i = 0; i < result.count; i++) {
      final pos = _subGridToLatLng(result.rows[i], result.cols[i]);
      final typeIndex = result.types[i];
      var type = cppTypeMap[typeIndex];
      if (type == null) continue;

      // Filter saddle candidates with topological check
      if (type == SmartWaypointType.saddlePoint) {
        final (r, c) = _latLngToSubGrid(pos);
        if (!_isTopologicalSaddle(r, c, _activeDem!, _activeRows, _activeCols)) continue;
      }

      // Filter by boundary mask
      if (_boundaryMask != null) {
        final (r, c) = _latLngToSubGrid(pos);
        if (_boundaryMask![r * _activeCols + c] == 0) continue; // outside boundary
      }

      waypoints.add(SmartWaypoint(
        position: pos,
        type: type,
        prominence: result.prominence[i],
        elevation: _activeDem![result.rows[i] * _activeCols + result.cols[i]],
      ));
    }

    return _applyWaypointSpacing(waypoints);
  }

  /// זיהוי נקודות תורפה — מצוקים, בורות, מדרונות תלולים
  Future<List<VulnerabilityPoint>> detectVulnerabilities({
    double cliffThreshold = 45.0,
    double pitThreshold = 20.0,
  }) async {
    if (!isAvailable || _activeDem == null) return [];

    // חישוב שיפוע — דרוש כקלט
    final slopeAspect = await computeSlopeAspect();
    if (slopeAspect == null) return [];

    final centerLat = (_activeBounds!.north + _activeBounds!.south) / 2;
    final ns = cellSizeNS(_activeSrcGridSize);
    final ew = cellSizeEW(centerLat, _activeSrcGridSize);

    // קריאה לפונקציית FFI
    final result = _ffi!.detectVulnerabilities(
      _activeDem!,
      slopeAspect.slopeGrid,
      _activeRows,
      _activeCols,
      ns,
      ew,
      cliffThreshold,
      pitThreshold,
    );
    if (result == null) return [];

    // המרת תוצאות לאובייקטי VulnerabilityPoint
    final points = <VulnerabilityPoint>[];
    for (int i = 0; i < result.count; i++) {
      final pos = _subGridToLatLng(result.rows[i], result.cols[i]);
      final typeIndex = result.types[i];
      // enum ב-C++ מתחיל מ-1
      if (typeIndex < 1 || typeIndex > VulnerabilityType.values.length) {
        continue;
      }

      // Filter by boundary mask
      if (_boundaryMask != null) {
        final (r, c) = _latLngToSubGrid(pos);
        if (_boundaryMask![r * _activeCols + c] == 0) continue; // outside boundary
      }

      points.add(VulnerabilityPoint(
        position: pos,
        type: VulnerabilityType.values[typeIndex - 1],
        severity: result.severity[i].clamp(0.0, 1.0),
      ));
    }

    return points;
  }

  // ---------------------------------------------------------------------------
  // Vulnerability zone detection — connected component clustering
  // ---------------------------------------------------------------------------

  /// זיהוי אזורי תורפה — מקבץ נקודות תורפה סמוכות לפוליגונים
  Future<List<VulnerabilityZone>> detectVulnerabilityZones({
    double cliffThreshold = 45.0,
    double pitThreshold = 20.0,
    int minClusterCells = 5,
  }) async {
    if (!terrainIsSupported) return [];

    // First get the slope grid
    final slopeResult = await computeSlopeAspect();
    if (slopeResult == null || _activeDem == null) return [];

    final n = _activeRows * _activeCols;

    // Use cached features for deepChannel detection
    final features = _cachedFeatures ?? await classifyFeatures();

    // Build vulnerability grid: type at each cell (0=none)
    final vulnGrid = Uint8List(n);
    for (int r = 1; r < _activeRows - 1; r++) {
      for (int c = 1; c < _activeCols - 1; c++) {
        final i = r * _activeCols + c;
        if (_boundaryMask != null && _boundaryMask![i] == 0) continue;
        final slope = slopeResult.slopeGrid[i];
        final elev = _activeDem![i];
        if (elev == -32768) continue;

        if (slope >= cliffThreshold) {
          vulnGrid[i] = 1; // cliff
        } else if (slope >= cliffThreshold * 0.8) {
          // Check if it's a pit (lower than all neighbors)
          bool isPit = true;
          for (int dr = -1; dr <= 1; dr++) {
            for (int dc = -1; dc <= 1; dc++) {
              if (dr == 0 && dc == 0) continue;
              final ni = (r + dr) * _activeCols + (c + dc);
              if (_activeDem![ni] != -32768 && _activeDem![ni] < elev) {
                isPit = false;
              }
            }
          }
          if (isPit) vulnGrid[i] = 2; // pit
        }

        // steepSlope: derived threshold <= slope < cliffThreshold
        final steepSlopeThreshold = cliffThreshold * 0.67;
        if (vulnGrid[i] == 0 && slope >= steepSlopeThreshold && slope < cliffThreshold) {
          vulnGrid[i] = 4; // steepSlope
        }

        // deepChannel: valley(4)/channel(5) feature + slope >= derived threshold
        final deepChannelSlope = cliffThreshold * 0.33;
        if (vulnGrid[i] == 0 && features != null) {
          final feat = features.featureGrid[i];
          if ((feat == 4 || feat == 5) && slope >= deepChannelSlope) {
            vulnGrid[i] = 3; // deepChannel
          }
        }
      }
    }

    // Connected component labeling
    final labels = Int32List(n);
    int nextLabel = 1;
    final labelType = <int, int>{}; // label → vuln type

    for (int r = 0; r < _activeRows; r++) {
      for (int c = 0; c < _activeCols; c++) {
        final i = r * _activeCols + c;
        if (vulnGrid[i] == 0 || labels[i] != 0) continue;

        // BFS flood fill
        final queue = <int>[i];
        labels[i] = nextLabel;
        labelType[nextLabel] = vulnGrid[i];
        int head = 0;
        while (head < queue.length) {
          final ci = queue[head++];
          final cr = ci ~/ _activeCols;
          final cc = ci % _activeCols;
          for (int dr = -1; dr <= 1; dr++) {
            for (int dc = -1; dc <= 1; dc++) {
              if (dr == 0 && dc == 0) continue;
              final nr = cr + dr;
              final nc = cc + dc;
              if (nr < 0 || nr >= _activeRows || nc < 0 || nc >= _activeCols) continue;
              final ni = nr * _activeCols + nc;
              if (labels[ni] == 0 && vulnGrid[ni] == vulnGrid[ci]) {
                labels[ni] = nextLabel;
                queue.add(ni);
              }
            }
          }
        }
        nextLabel++;
      }
    }

    // For each label, collect boundary cells and create convex hull polygon
    final zones = <VulnerabilityZone>[];
    for (int label = 1; label < nextLabel; label++) {
      final cells = <int>[];
      for (int i = 0; i < n; i++) {
        if (labels[i] == label) cells.add(i);
      }
      // steepSlope needs higher threshold (many cells match)
      final effectiveMinCells = (labelType[label] == 4) ? 12 : minClusterCells;
      if (cells.length < effectiveMinCells) continue;

      // Compute slope statistics for the zone
      double slopeSum = 0;
      double slopeMax = 0;
      for (final ci in cells) {
        final s = slopeResult.slopeGrid[ci];
        slopeSum += s;
        if (s > slopeMax) slopeMax = s;
      }
      final avgSlope = cells.isNotEmpty ? slopeSum / cells.length : 0.0;

      // Collect LatLng points from cell positions
      final points = <LatLng>[];
      for (final i in cells) {
        final r = i ~/ _activeCols;
        final c = i % _activeCols;
        points.add(_subGridToLatLng(r, c));
      }

      // Compute convex hull
      final hull = _convexHull(points);
      if (hull.length < 3) continue;

      final typeIdx = labelType[label] ?? 1;
      final vulnType = typeIdx >= 1 && typeIdx <= VulnerabilityType.values.length
          ? VulnerabilityType.values[typeIdx - 1]
          : VulnerabilityType.cliff;

      zones.add(VulnerabilityZone(
        polygon: hull,
        type: vulnType,
        severity: 0.5 + 0.5 * (cells.length / 100).clamp(0.0, 1.0),
        cellCount: cells.length,
        avgSlope: avgSlope,
        maxSlope: slopeMax,
      ));
    }

    return zones;
  }

  /// Compute combined viewshed for multiple enemies — reusable
  Future<Uint8List?> computeCombinedViewshed(
    List<LatLng> enemies, {
    double enemyHeight = 1.7,
  }) async {
    if (!terrainIsSupported || _activeDem == null || enemies.isEmpty) return null;

    Uint8List? combined;
    for (final enemy in enemies) {
      final vs = await computeViewshed(enemy, height: enemyHeight);
      if (vs == null) continue;
      if (combined == null) {
        combined = Uint8List.fromList(vs.visibleGrid);
      } else {
        for (int i = 0; i < combined.length; i++) {
          if (vs.visibleGrid[i] == 1) combined[i] = 1;
        }
      }
    }
    return combined;
  }

  /// Check if a point is visible in a pre-computed combined viewshed
  bool isPointVisibleToEnemies(LatLng point, Uint8List combinedViewshed) {
    if (_activeDem == null) return false;
    final (r, c) = _latLngToSubGrid(point);
    final idx = r * _activeCols + c;
    if (idx < 0 || idx >= combinedViewshed.length) return false;
    return combinedViewshed[idx] == 1;
  }

  /// Compute multi-waypoint hidden path
  Future<MultiWaypointHiddenPath?> computeMultiWaypointHiddenPath(
    List<LatLng> waypoints,
    List<LatLng> enemies, {
    double enemyHeight = 1.7,
    double exposureWeight = 100.0,
  }) async {
    if (waypoints.length < 2 || enemies.isEmpty) return null;

    // Compute combined viewshed once
    final combinedViewshed = await computeCombinedViewshed(enemies, enemyHeight: enemyHeight);
    if (combinedViewshed == null) return null;

    final segments = <HiddenPathSegment>[];
    double totalDist = 0;
    double totalExposed = 0;
    double totalHidden = 0;

    for (int w = 0; w < waypoints.length - 1; w++) {
      final path = await computeHiddenPath(
        waypoints[w],
        waypoints[w + 1],
        enemies,
        enemyHeight: enemyHeight,
        exposureWeight: exposureWeight,
      );
      if (path == null) return null;

      // Build visibility mask and compute exposure/hidden meters
      final mask = Uint8List(path.points.length);
      double segExposed = 0;
      double segHidden = 0;

      for (int i = 0; i < path.points.length; i++) {
        final visible = isPointVisibleToEnemies(path.points[i], combinedViewshed);
        mask[i] = visible ? 1 : 0;

        if (i > 0) {
          final d = const Distance().as(LengthUnit.Meter, path.points[i - 1], path.points[i]);
          if (mask[i - 1] == 1) {
            segExposed += d;
          } else {
            segHidden += d;
          }
        }
      }

      final segDist = path.totalDistanceMeters;
      segments.add(HiddenPathSegment(
        points: path.points,
        distanceMeters: segDist,
        exposurePercent: segDist > 0 ? (segExposed / segDist * 100) : 0,
        exposureMeters: segExposed,
        hiddenMeters: segHidden,
        visibilityMask: mask,
      ));

      totalDist += segDist;
      totalExposed += segExposed;
      totalHidden += segHidden;
    }

    return MultiWaypointHiddenPath(
      segments: segments,
      waypoints: waypoints,
      totalDistanceMeters: totalDist,
      totalExposurePercent: totalDist > 0 ? (totalExposed / totalDist * 100) : 0,
      totalExposureMeters: totalExposed,
      totalHiddenMeters: totalHidden,
    );
  }

  // ---------------------------------------------------------------------------
  // Helper: topological saddle detection
  // ---------------------------------------------------------------------------

  /// בדיקת אוכף טופולוגי — עלייה ב-2 כיוונים נגדיים וירידה ב-2 אחרים
  bool _isTopologicalSaddle(int r, int c, Int16List dem, int rows, int cols) {
    final center = dem[r * cols + c].toDouble();
    if (center == -32768) return false;
    const dr = [-1, -1, 0, 1, 1, 1, 0, -1];
    const dc = [0, 1, 1, 1, 0, -1, -1, -1];

    int signChanges = 0, lastSign = 0, firstSign = 0;
    for (int d = 0; d < 8; d++) {
      final nr = r + dr[d], nc = c + dc[d];
      if (nr < 0 || nr >= rows || nc < 0 || nc >= cols) return false;
      final val = dem[nr * cols + nc].toDouble();
      if (val == -32768) return false;
      final sign = val > center ? 1 : (val < center ? -1 : 0);
      if (sign == 0) continue;
      if (firstSign == 0) firstSign = sign;
      if (lastSign != 0 && sign != lastSign) signChanges++;
      lastSign = sign;
    }
    if (lastSign != 0 && firstSign != 0 && lastSign != firstSign) signChanges++;
    return signChanges == 4;
  }

  // ---------------------------------------------------------------------------
  // Helper: waypoint spacing — minimum distance between junctions/saddles
  // ---------------------------------------------------------------------------

  /// סינון ריווח — מרחק מינימלי בין צמתים/אוכפים
  List<SmartWaypoint> _applyWaypointSpacing(List<SmartWaypoint> waypoints) {
    final junctions = <SmartWaypoint>[];
    final saddles = <SmartWaypoint>[];
    final others = <SmartWaypoint>[];
    for (final w in waypoints) {
      if (w.type == SmartWaypointType.valleyJunction) {
        junctions.add(w);
      } else if (w.type == SmartWaypointType.saddlePoint) {
        saddles.add(w);
      } else {
        others.add(w);
      }
    }

    // Sort by prominence descending (major confluences first)
    junctions.sort((a, b) => b.prominence.compareTo(a.prominence));
    saddles.sort((a, b) => b.prominence.compareTo(a.prominence));

    // Greedy 70m spacing for junctions
    final acceptedJ = _greedySpacing(junctions, 70.0);
    // Greedy 50m spacing for saddles
    final acceptedS = _greedySpacing(saddles, 50.0);

    return [...others, ...acceptedJ, ...acceptedS];
  }

  List<SmartWaypoint> _greedySpacing(List<SmartWaypoint> sorted, double minMeters) {
    final accepted = <SmartWaypoint>[];
    for (final wp in sorted) {
      bool tooClose = accepted.any((a) =>
          const Distance().as(LengthUnit.Meter, wp.position, a.position) < minMeters);
      if (!tooClose) accepted.add(wp);
    }
    return accepted;
  }

  /// Convex hull — Graham scan
  List<LatLng> _convexHull(List<LatLng> points) {
    if (points.length < 3) return points;

    // Find lowest point (southernmost, then westernmost)
    var start = points[0];
    for (final p in points) {
      if (p.latitude < start.latitude ||
          (p.latitude == start.latitude && p.longitude < start.longitude)) {
        start = p;
      }
    }

    // Sort by polar angle
    final sorted = List<LatLng>.from(points);
    sorted.sort((a, b) {
      final angleA = atan2(a.latitude - start.latitude, a.longitude - start.longitude);
      final angleB = atan2(b.latitude - start.latitude, b.longitude - start.longitude);
      return angleA.compareTo(angleB);
    });

    final hull = <LatLng>[];
    for (final p in sorted) {
      while (hull.length >= 2) {
        final a = hull[hull.length - 2];
        final b = hull[hull.length - 1];
        final cross = (b.longitude - a.longitude) * (p.latitude - a.latitude) -
                      (b.latitude - a.latitude) * (p.longitude - a.longitude);
        if (cross <= 0) {
          hull.removeLast();
        } else {
          break;
        }
      }
      hull.add(p);
    }

    return hull;
  }
}
