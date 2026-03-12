import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../domain/entities/boundary.dart';
import '../../domain/entities/coordinate.dart';
import 'terrain_models.dart';

/// Whether terrain analysis is supported on this platform.
const bool terrainIsSupported = true;

/// שירות ניתוח שטח — מימוש Web (Pure Dart)
/// מנהל טעינת DEM דרך HTTP בלבד, אלגוריתמים ב-Dart טהור (ללא FFI)
class TerrainAnalysisService {
  static final TerrainAnalysisService _instance =
      TerrainAnalysisService._internal();
  factory TerrainAnalysisService() => _instance;
  TerrainAnalysisService._internal();

  bool _initialized = false;
  bool get isAvailable => true; // always available on web

  /// מטמון DEM — שם אריח → נתונים גולמיים (in-memory only, no disk cache)
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
  Float64List? _smoothedDem; // Gaussian σ=1 smoothed DEM for saddle detection
  Int32List? _flowAccumulation; // D8 flow accumulation grid
  Uint8List? _boundaryMask; // 1=inside polygon, 0=outside

  // Public getters
  Uint8List? get boundaryMask => _boundaryMask;
  int get activeRows => _activeRows;
  int get activeCols => _activeCols;
  LatLngBounds? get activeBounds => _activeBounds;

  /// היסט SRTM — תיקון אופקי של DEM עם אריחי המפה
  /// lat: חיוב = צפונה (מעלות). lng: חיוב = מזרחה (מעלות)
  double _demLatOffset = 0.00008; // ~9m north
  double _demLngOffset = -0.00015; // ~13m west

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

  /// גודל תא (מטרים) בכיוון צפון-דרום
  static double cellSizeNS(int gridSize) => 30.87 * (3601.0 / gridSize);

  /// גודל תא (מטרים) בכיוון מזרח-מערב — תלוי בקו רוחב
  static double cellSizeEW(double lat, int gridSize) =>
      30.87 * cos(lat * pi / 180) * (3601.0 / gridSize);

  /// אתחול השירות — no directory creation or cache init on web
  Future<void> initialize() async {
    if (_initialized) return;
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

  /// טעינת אריח DEM — הורדה מ-AWS בלבד (web: אין דיסק, אין assets)
  Future<bool> loadDemTile(int lat, int lng) async {
    if (!_initialized) return false;
    final name = tileName(lat, lng);
    if (_demCache.containsKey(name)) return true;

    // הורדת SRTM1 מ-AWS
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

      // שמירה במטמון in-memory בלבד (אין דיסק ב-web)
      _demCache[name] = _parseBigEndianInt16(Uint8List.fromList(decoded));
      _gridSizes[name] = gridSize;
      return true;
    } catch (e) {
      print('DEBUG TerrainAnalysisService (web): שגיאת הורדה: $e');
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
    if (!await loadDemTile(tileLat, tileLng)) return false;

    _activeBoundary = boundary;
    _cachedFeatures = null;
    _smoothedDem = null;
    _flowAccumulation = null;
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
    // Remove offset to get raw grid coordinates
    final lat = pos.latitude - _demLatOffset;
    final lng = pos.longitude - _demLngOffset;
    final fullRow = ((_activeSrcTileLat + 1.0 - lat) / step).round();
    final fullCol = ((lng - _activeSrcTileLng.toDouble()) / step).round();
    return (
      (fullRow - _activeMinRow).clamp(0, _activeRows - 1),
      (fullCol - _activeMinCol).clamp(0, _activeCols - 1),
    );
  }

  // ---------------------------------------------------------------------------
  // 6 שיטות ניתוח — מימוש Pure Dart (ללא FFI)
  // ---------------------------------------------------------------------------

  /// חישוב שיפוע ונטייה — Horn's Method (Pure Dart)
  Future<SlopeAspectResult?> computeSlopeAspect() async {
    if (_activeDem == null) return null;

    final centerLat = (_activeBounds!.north + _activeBounds!.south) / 2;
    final cellNS = cellSizeNS(_activeSrcGridSize);
    final cellEW = cellSizeEW(centerLat, _activeSrcGridSize);

    final n = _activeRows * _activeCols;
    final slopeGrid = Float32List(n);
    final aspectGrid = Float32List(n);
    final dem = _activeDem!;
    final rows = _activeRows;
    final cols = _activeCols;

    for (int r = 1; r < rows - 1; r++) {
      for (int c = 1; c < cols - 1; c++) {
        // 3×3 neighborhood elevations
        final zTL = dem[(r - 1) * cols + (c - 1)].toDouble(); // top-left
        final zTC = dem[(r - 1) * cols + c].toDouble();        // top-center
        final zTR = dem[(r - 1) * cols + (c + 1)].toDouble(); // top-right
        final zML = dem[r * cols + (c - 1)].toDouble();        // middle-left
        final zMR = dem[r * cols + (c + 1)].toDouble();        // middle-right
        final zBL = dem[(r + 1) * cols + (c - 1)].toDouble(); // bottom-left
        final zBC = dem[(r + 1) * cols + c].toDouble();        // bottom-center
        final zBR = dem[(r + 1) * cols + (c + 1)].toDouble(); // bottom-right

        // Skip NODATA cells (-32768)
        if (zTL == -32768 || zTC == -32768 || zTR == -32768 ||
            zML == -32768 || zMR == -32768 ||
            zBL == -32768 || zBC == -32768 || zBR == -32768) {
          continue; // slope=0, aspect=0 (default)
        }

        // Horn's method partial derivatives
        final dzdx = ((zTR + 2 * zMR + zBR) - (zTL + 2 * zML + zBL)) /
            (8.0 * cellEW);
        final dzdy = ((zTL + 2 * zTC + zTR) - (zBL + 2 * zBC + zBR)) /
            (8.0 * cellNS);

        // Slope in degrees
        final slopeDeg = atan(sqrt(dzdx * dzdx + dzdy * dzdy)) * 180.0 / pi;

        // Aspect in degrees (0=North, clockwise)
        double aspectDeg = atan2(dzdy, -dzdx) * 180.0 / pi;
        if (aspectDeg < 0) aspectDeg += 360.0;

        final idx = r * cols + c;
        slopeGrid[idx] = slopeDeg;
        aspectGrid[idx] = aspectDeg;
      }
    }
    // Edge cells remain 0 (slope=0, aspect=0)

    return SlopeAspectResult(
      slopeGrid: slopeGrid,
      aspectGrid: aspectGrid,
      rows: _activeRows,
      cols: _activeCols,
      bounds: _activeBounds!,
    );
  }

  /// סיווג תוואי שטח — TPI (Topographic Position Index) — Pure Dart
  Future<TerrainFeaturesResult?> classifyFeatures() async {
    if (_activeDem == null) return null;

    // Step 1: Compute slope/aspect
    final slopeAspect = await computeSlopeAspect();
    if (slopeAspect == null) return null;

    final rows = _activeRows;
    final cols = _activeCols;
    final n = rows * cols;
    final dem = _activeDem!;
    final slopeGrid = slopeAspect.slopeGrid;
    final featureGrid = Uint8List(n);

    // Step 2: Small TPI (3×3 window) — elevation minus mean of 8 neighbors
    final smallTPI = Float32List(n);
    for (int r = 1; r < rows - 1; r++) {
      for (int c = 1; c < cols - 1; c++) {
        final idx = r * cols + c;
        final center = dem[idx].toDouble();
        if (center == -32768) continue;

        double sum = 0;
        int count = 0;
        for (int dr = -1; dr <= 1; dr++) {
          for (int dc = -1; dc <= 1; dc++) {
            if (dr == 0 && dc == 0) continue;
            final val = dem[(r + dr) * cols + (c + dc)].toDouble();
            if (val != -32768) {
              sum += val;
              count++;
            }
          }
        }
        if (count > 0) {
          smallTPI[idx] = center - (sum / count);
        }
      }
    }

    // Step 3: Large TPI (21×21 window) using prefix sum optimization
    // Build prefix sum of elevations (using doubles to avoid overflow)
    final prefixSum = Float64List((rows + 1) * (cols + 1));
    final prefixCount = Int32List((rows + 1) * (cols + 1));
    // prefixSum row/col are 1-indexed: prefixSum[(r+1)*(cols+1)+(c+1)]
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final val = dem[r * cols + c].toDouble();
        final isValid = val != -32768;
        final pi = (r + 1) * (cols + 1) + (c + 1);
        prefixSum[pi] = (isValid ? val : 0) +
            prefixSum[r * (cols + 1) + (c + 1)] +
            prefixSum[(r + 1) * (cols + 1) + c] -
            prefixSum[r * (cols + 1) + c];
        prefixCount[pi] = (isValid ? 1 : 0) +
            prefixCount[r * (cols + 1) + (c + 1)] +
            prefixCount[(r + 1) * (cols + 1) + c] -
            prefixCount[r * (cols + 1) + c];
      }
    }

    final largeTPI = Float32List(n);
    const halfWin = 10; // 21×21 → half = 10
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final idx = r * cols + c;
        final center = dem[idx].toDouble();
        if (center == -32768) continue;

        final r1 = max(0, r - halfWin);
        final r2 = min(rows - 1, r + halfWin);
        final c1 = max(0, c - halfWin);
        final c2 = min(cols - 1, c + halfWin);

        // Prefix sum rectangle query (1-indexed)
        final sumVal = prefixSum[(r2 + 1) * (cols + 1) + (c2 + 1)] -
            prefixSum[r1 * (cols + 1) + (c2 + 1)] -
            prefixSum[(r2 + 1) * (cols + 1) + c1] +
            prefixSum[r1 * (cols + 1) + c1];
        final countVal = prefixCount[(r2 + 1) * (cols + 1) + (c2 + 1)] -
            prefixCount[r1 * (cols + 1) + (c2 + 1)] -
            prefixCount[(r2 + 1) * (cols + 1) + c1] +
            prefixCount[r1 * (cols + 1) + c1];

        // Subtract center cell from the window sum
        if (countVal > 1) {
          final meanExcluding = (sumVal - center) / (countVal - 1);
          largeTPI[idx] = center - meanExcluding;
        }
      }
    }

    // Step 3b: Medium TPI scales (7×7 and 13×13) using same prefix sum
    final medSmallTPI = Float32List(n);
    const halfWinMS = 3; // 7×7
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final idx = r * cols + c;
        final center = dem[idx].toDouble();
        if (center == -32768) continue;
        final r1 = max(0, r - halfWinMS);
        final r2 = min(rows - 1, r + halfWinMS);
        final c1 = max(0, c - halfWinMS);
        final c2 = min(cols - 1, c + halfWinMS);
        final sumVal = prefixSum[(r2 + 1) * (cols + 1) + (c2 + 1)] -
            prefixSum[r1 * (cols + 1) + (c2 + 1)] -
            prefixSum[(r2 + 1) * (cols + 1) + c1] +
            prefixSum[r1 * (cols + 1) + c1];
        final countVal = prefixCount[(r2 + 1) * (cols + 1) + (c2 + 1)] -
            prefixCount[r1 * (cols + 1) + (c2 + 1)] -
            prefixCount[(r2 + 1) * (cols + 1) + c1] +
            prefixCount[r1 * (cols + 1) + c1];
        if (countVal > 1) {
          medSmallTPI[idx] = center - (sumVal - center) / (countVal - 1);
        }
      }
    }

    final medLargeTPI = Float32List(n);
    const halfWinML = 6; // 13×13
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final idx = r * cols + c;
        final center = dem[idx].toDouble();
        if (center == -32768) continue;
        final r1 = max(0, r - halfWinML);
        final r2 = min(rows - 1, r + halfWinML);
        final c1 = max(0, c - halfWinML);
        final c2 = min(cols - 1, c + halfWinML);
        final sumVal = prefixSum[(r2 + 1) * (cols + 1) + (c2 + 1)] -
            prefixSum[r1 * (cols + 1) + (c2 + 1)] -
            prefixSum[(r2 + 1) * (cols + 1) + c1] +
            prefixSum[r1 * (cols + 1) + c1];
        final countVal = prefixCount[(r2 + 1) * (cols + 1) + (c2 + 1)] -
            prefixCount[r1 * (cols + 1) + (c2 + 1)] -
            prefixCount[(r2 + 1) * (cols + 1) + c1] +
            prefixCount[r1 * (cols + 1) + c1];
        if (countVal > 1) {
          medLargeTPI[idx] = center - (sumVal - center) / (countVal - 1);
        }
      }
    }

    // Step 4: Classification
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final idx = r * cols + c;
        if (dem[idx] == -32768) {
          featureGrid[idx] = 0; // flat (NODATA treated as flat)
          continue;
        }

        final slope = slopeGrid[idx];
        final sT = smallTPI[idx];
        final lT = largeTPI[idx];

        if (slope < 5 && sT.abs() < 1) {
          featureGrid[idx] = 0; // flat
        } else if (lT > 1 && sT > 1) {
          featureGrid[idx] = 1; // dome
        } else if (lT > 1 && sT.abs() <= 1) {
          featureGrid[idx] = 2; // ridge
        } else if (lT > 1 && sT < -1) {
          featureGrid[idx] = 3; // spur
        } else if (lT < -1 && sT < -1) {
          featureGrid[idx] = 4; // valley
        } else if (lT < -1 && sT.abs() <= 1) {
          featureGrid[idx] = 5; // channel
        } else if (lT.abs() <= 1 && slope >= 5) {
          if (sT.abs() > 0.5) {
            featureGrid[idx] = 6; // saddle
          } else {
            featureGrid[idx] = 7; // slope
          }
        } else {
          featureGrid[idx] = 7; // slope (default)
        }
      }
    }

    // Step 5: Multi-scale enhancement — catch features missed by dual-scale
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final idx = r * cols + c;
        if (dem[idx] == -32768) continue;
        final current = featureGrid[idx];
        // Only upgrade slope/flat cells — never downgrade existing classification
        if (current != 7 && current != 0) continue;
        final mST = medSmallTPI[idx];
        final mLT = medLargeTPI[idx];
        final slope = slopeGrid[idx];
        if (current == 7) {
          // Slope: check if medium scales reveal saddle pattern
          if (mLT.abs() <= 1 && mST.abs() > 0.5) {
            featureGrid[idx] = 6; // saddle (medium-scale)
          }
        } else if (current == 0 && slope >= 2) {
          // Near-flat with some slope: check medium-scale features
          if (mLT < -1 && mST < -1) {
            featureGrid[idx] = 4; // valley (broad, visible at medium scale)
          } else if (mLT < -1 && mST.abs() <= 1) {
            featureGrid[idx] = 5; // channel (broad)
          }
        }
      }
    }

    final result = TerrainFeaturesResult(
      featureGrid: featureGrid,
      rows: _activeRows,
      cols: _activeCols,
      bounds: _activeBounds!,
    );
    _cachedFeatures = result;
    return result;
  }

  /// חישוב קו ראייה — Perimeter Ray-Cast (Pure Dart)
  Future<ViewshedResult?> computeViewshed(
    LatLng observer, {
    double height = 1.7,
    double maxDistKm = 5.0,
  }) async {
    if (_activeDem == null) return null;

    final centerLat = (_activeBounds!.north + _activeBounds!.south) / 2;
    final cellNS = cellSizeNS(_activeSrcGridSize);
    final cellEW = cellSizeEW(centerLat, _activeSrcGridSize);

    final (obsRow, obsCol) = _latLngToSubGrid(observer);
    final maxDistCells = (maxDistKm * 1000.0) / cellNS;

    final rows = _activeRows;
    final cols = _activeCols;
    final dem = _activeDem!;
    final visibleGrid = Uint8List(rows * cols);

    // Observer elevation + height
    final observerElev = dem[obsRow * cols + obsCol].toDouble() + height;

    // Mark observer cell as visible
    visibleGrid[obsRow * cols + obsCol] = 1;

    // Collect all perimeter cells
    final perimeterCells = <(int, int)>[];
    // Top and bottom rows
    for (int c = 0; c < cols; c++) {
      perimeterCells.add((0, c));
      if (rows > 1) perimeterCells.add((rows - 1, c));
    }
    // Left and right columns (excluding corners already added)
    for (int r = 1; r < rows - 1; r++) {
      perimeterCells.add((r, 0));
      if (cols > 1) perimeterCells.add((r, cols - 1));
    }

    // Cast a ray from observer to each perimeter cell
    for (final (pr, pc) in perimeterCells) {
      _castRay(
        obsRow,
        obsCol,
        pr,
        pc,
        observerElev,
        maxDistCells,
        cellNS,
        cellEW,
        dem,
        rows,
        cols,
        visibleGrid,
      );
    }

    return ViewshedResult(
      visibleGrid: visibleGrid,
      rows: rows,
      cols: cols,
      bounds: _activeBounds!,
      observerPosition: observer,
      observerHeight: height,
    );
  }

  /// Cast a single ray from observer to target perimeter cell using DDA
  void _castRay(
    int obsRow,
    int obsCol,
    int targetRow,
    int targetCol,
    double observerElev,
    double maxDistCells,
    double cellNS,
    double cellEW,
    Int16List dem,
    int rows,
    int cols,
    Uint8List visibleGrid,
  ) {
    final dr = targetRow - obsRow;
    final dc = targetCol - obsCol;
    final steps = max(dr.abs(), dc.abs());
    if (steps == 0) return;

    final rowStep = dr / steps;
    final colStep = dc / steps;

    double maxElevAngle = double.negativeInfinity;

    for (int s = 1; s <= steps; s++) {
      final r = (obsRow + rowStep * s).round();
      final c = (obsCol + colStep * s).round();

      if (r < 0 || r >= rows || c < 0 || c >= cols) break;

      // Distance in cells (accounting for non-square cells)
      final dRow = (r - obsRow).toDouble();
      final dCol = (c - obsCol).toDouble();
      final distMeters =
          sqrt(dRow * dRow * cellNS * cellNS + dCol * dCol * cellEW * cellEW);

      if (distMeters < 1.0) continue;

      // Check max distance
      final distCells = sqrt(dRow * dRow + dCol * dCol);
      if (distCells > maxDistCells) break;

      final cellElev = dem[r * cols + c].toDouble();
      if (cellElev == -32768) continue; // NODATA

      final elevAngle = atan2(cellElev - observerElev, distMeters);

      if (elevAngle > maxElevAngle) {
        visibleGrid[r * cols + c] = 1;
        maxElevAngle = elevAngle;
      }
      // else: cell is not visible (occluded), stays 0
    }
  }

  /// חישוב מסלול נסתר — A* (Pure Dart)
  Future<HiddenPath?> computeHiddenPath(
    LatLng start,
    LatLng end,
    List<LatLng> enemies, {
    double enemyHeight = 1.7,
    double exposureWeight = 100.0,
  }) async {
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
    final cellNS = cellSizeNS(_activeSrcGridSize);
    final cellEW = cellSizeEW(centerLat, _activeSrcGridSize);

    final (startRow, startCol) = _latLngToSubGrid(start);
    final (endRow, endCol) = _latLngToSubGrid(end);

    // Run A* pathfinding in pure Dart
    final pathCells = _aStarHiddenPath(
      startRow,
      startCol,
      endRow,
      endCol,
      combinedViewshed,
      cellNS,
      cellEW,
      exposureWeight,
    );

    if (pathCells == null || pathCells.isEmpty) return null;

    // Convert grid cells to LatLng points
    final points = <LatLng>[];
    int exposedCount = 0;
    for (final (r, c) in pathCells) {
      points.add(_subGridToLatLng(r, c));
      if (combinedViewshed[r * _activeCols + c] == 1) {
        exposedCount++;
      }
    }

    // Compute total distance
    double totalDist = 0;
    for (int i = 1; i < points.length; i++) {
      totalDist +=
          const Distance().as(LengthUnit.Meter, points[i - 1], points[i]);
    }

    return HiddenPath(
      points: points,
      totalDistanceMeters: totalDist,
      exposurePercent: pathCells.isNotEmpty
          ? (exposedCount / pathCells.length * 100)
          : 0,
    );
  }

  /// A* search for hidden path — Pure Dart implementation
  List<(int, int)>? _aStarHiddenPath(
    int startRow,
    int startCol,
    int endRow,
    int endCol,
    Uint8List visibility,
    double cellNS,
    double cellEW,
    double exposureWeight,
  ) {
    final rows = _activeRows;
    final cols = _activeCols;
    final dem = _activeDem!;

    // Bound search area: rectangle expanded by 50% around start/end
    final minR = min(startRow, endRow);
    final maxR = max(startRow, endRow);
    final minC = min(startCol, endCol);
    final maxC = max(startCol, endCol);
    final expandR = max(((maxR - minR) * 0.5).ceil(), 20);
    final expandC = max(((maxC - minC) * 0.5).ceil(), 20);
    final boundMinR = max(0, minR - expandR);
    final boundMaxR = min(rows - 1, maxR + expandR);
    final boundMinC = max(0, minC - expandC);
    final boundMaxC = min(cols - 1, maxC + expandC);

    // Heuristic: Euclidean distance to end (in meters)
    double heuristic(int r, int c) {
      final dr = (r - endRow).toDouble() * cellNS;
      final dc = (c - endCol).toDouble() * cellEW;
      return sqrt(dr * dr + dc * dc);
    }

    // g-cost map
    final gCost = <int, double>{};
    // parent map for path reconstruction
    final parent = <int, int>{};
    // closed set
    final closed = <int>{};

    int key(int r, int c) => r * cols + c;

    final startKey = key(startRow, startCol);
    final endKey = key(endRow, endCol);
    gCost[startKey] = 0;

    // Open set as a list-based priority queue (sorted by f-cost)
    // Each entry: (fCost, gCost, row, col)
    final open = <_AStarNode>[];
    open.add(_AStarNode(heuristic(startRow, startCol), 0, startRow, startCol));

    // 8-connected neighbor offsets
    const neighborDr = [-1, -1, -1, 0, 0, 1, 1, 1];
    const neighborDc = [-1, 0, 1, -1, 1, -1, 0, 1];

    while (open.isNotEmpty) {
      // Find node with smallest f-cost
      int bestIdx = 0;
      for (int i = 1; i < open.length; i++) {
        if (open[i].f < open[bestIdx].f) bestIdx = i;
      }
      final current = open[bestIdx];
      open.removeAt(bestIdx);

      final cr = current.row;
      final cc = current.col;
      final ck = key(cr, cc);

      if (closed.contains(ck)) continue;
      closed.add(ck);

      // Goal reached
      if (ck == endKey) {
        // Reconstruct path
        final path = <(int, int)>[];
        int? cur = endKey;
        while (cur != null) {
          final r = cur ~/ cols;
          final c = cur % cols;
          path.add((r, c));
          cur = parent[cur];
        }
        return path.reversed.toList();
      }

      // Explore neighbors
      for (int d = 0; d < 8; d++) {
        final nr = cr + neighborDr[d];
        final nc = cc + neighborDc[d];

        // Bounds check
        if (nr < boundMinR || nr > boundMaxR || nc < boundMinC || nc > boundMaxC) {
          continue;
        }
        final nk = key(nr, nc);
        if (closed.contains(nk)) continue;

        final nElev = dem[nk].toDouble();
        if (nElev == -32768) continue; // NODATA

        // Move cost: distance * slope factor + exposure penalty
        final isDiag = (neighborDr[d] != 0 && neighborDc[d] != 0);
        final dist = isDiag
            ? sqrt(cellNS * cellNS + cellEW * cellEW)
            : (neighborDr[d] != 0 ? cellNS : cellEW);

        final cElev = dem[ck].toDouble();
        final elevDiff = (nElev - cElev).abs();
        final slopeFactor = 1.0 + elevDiff / dist;

        // Exposure penalty: higher cost if cell is visible to enemies
        final exposurePenalty = visibility[nk] == 1 ? exposureWeight : 0.0;

        final moveCost = dist * slopeFactor + exposurePenalty;
        final newG = (gCost[ck] ?? double.infinity) + moveCost;

        if (newG < (gCost[nk] ?? double.infinity)) {
          gCost[nk] = newG;
          parent[nk] = ck;
          final f = newG + heuristic(nr, nc);
          open.add(_AStarNode(f, newG, nr, nc));
        }
      }
    }

    // No path found
    return null;
  }

  /// זיהוי נקודות ציון חכמות — Pure Dart
  Future<List<SmartWaypoint>> detectSmartWaypoints({
    double minProminence = 10.0,
    int minFeatureCells = 5,
  }) async {
    if (_activeDem == null) return [];

    // Compute slope/aspect and features
    final slopeAspect = await computeSlopeAspect();
    if (slopeAspect == null) return [];
    final features = await classifyFeatures();
    if (features == null) return [];

    final rows = _activeRows;
    final cols = _activeCols;
    final dem = _activeDem!;
    final featureGrid = features.featureGrid;

    // Count feature cluster sizes using connected components
    final clusterSizes = _computeFeatureClusterSizes(featureGrid, rows, cols);

    final waypoints = <SmartWaypoint>[];

    for (int r = 2; r < rows - 2; r++) {
      for (int c = 2; c < cols - 2; c++) {
        final idx = r * cols + c;
        final feature = featureGrid[idx];

        // Skip flat (0) and slope (7) — only interesting features
        if (feature == 0 || feature == 7) continue;

        final elev = dem[idx].toDouble();
        if (elev == -32768) continue;

        // Check cluster size
        if (clusterSizes[idx] < minFeatureCells) continue;

        // Compute prominence: abs(elevation - mean of 5×5 window)
        double windowSum = 0;
        int windowCount = 0;
        for (int dr = -2; dr <= 2; dr++) {
          for (int dc = -2; dc <= 2; dc++) {
            if (dr == 0 && dc == 0) continue;
            final val = dem[(r + dr) * cols + (c + dc)].toDouble();
            if (val != -32768) {
              windowSum += val;
              windowCount++;
            }
          }
        }
        if (windowCount == 0) continue;
        final prominence = (elev - windowSum / windowCount).abs();
        if (prominence < minProminence) continue;

        // Check if local extremum in its feature class
        bool isExtremum = _isLocalExtremum(r, c, feature, dem, featureGrid, rows, cols);
        if (!isExtremum) continue;

        // Determine waypoint type based on feature
        SmartWaypointType? type;
        switch (feature) {
          case 1: // dome — classify via 8-directional line-of-sight
            type = _classifyDomeVisibility(r, c);
            break;
          case 2: // ridge — only mark as saddle if topological saddle
            if (_isTopologicalSaddle(r, c, dem, rows, cols)) {
              type = SmartWaypointType.saddlePoint;
            }
            break;
          case 3: // spur → כתף
            type = SmartWaypointType.shoulder;
            break;
          case 4: // valley — junction detection with variable-radius arms + flow accumulation
            {
              const directions = [(-1,0),(-1,1),(0,1),(1,1),(1,0),(1,-1),(0,-1),(-1,-1)];

              // Variable-radius arm counting (up to 3 cells out)
              // Weighted: require ≥2 valley/channel cells per direction for a strong arm
              final dirHasValley = <bool>[];
              for (final (dr, dc) in directions) {
                int valleyCells = 0;
                for (int step = 1; step <= 3; step++) {
                  final nr = r + dr * step;
                  final nc = c + dc * step;
                  if (nr >= 0 && nr < rows && nc >= 0 && nc < cols) {
                    final nf = featureGrid[nr * cols + nc];
                    if (nf == 4 || nf == 5) valleyCells++;
                  }
                }
                dirHasValley.add(valleyCells >= 2);
              }
              int arms = 0;
              for (int i = 0; i < 8; i++) {
                if (dirHasValley[i] && !dirHasValley[(i + 7) % 8]) arms++;
              }

              // Fallback: also check with immediate neighbors for narrow valleys
              if (arms < 3) {
                final ring = <bool>[];
                for (final (dr, dc) in directions) {
                  final nr = r + dr;
                  final nc = c + dc;
                  if (nr >= 0 && nr < rows && nc >= 0 && nc < cols) {
                    final nf = featureGrid[nr * cols + nc];
                    ring.add(nf == 4 || nf == 5);
                  } else {
                    ring.add(false);
                  }
                }
                int narrowArms = 0;
                for (int i = 0; i < 8; i++) {
                  if (ring[i] && !ring[(i + 7) % 8]) narrowArms++;
                }
                arms = max(arms, narrowArms);
              }

              // Flow accumulation enhancement: detect real confluences
              final flowAcc = _getFlowAccumulation();
              final cellFlow = flowAcc[idx];

              if (arms >= 3) {
                type = SmartWaypointType.valleyJunction;
              } else if (arms >= 2 && cellFlow > 50) {
                // High flow accumulation confirms real stream confluence
                type = SmartWaypointType.valleyJunction;
              } else if (cellFlow > 30) {
                // Check if multiple upstream neighbors have significant flow
                // (confluence of streams even without clear TPI arms)
                int upstreamHighFlow = 0;
                for (final (dr, dc) in directions) {
                  final nr = r + dr;
                  final nc = c + dc;
                  if (nr >= 0 && nr < rows && nc >= 0 && nc < cols) {
                    final nFlow = flowAcc[nr * cols + nc];
                    if (nFlow > cellFlow * 0.2 && nFlow > 10) {
                      upstreamHighFlow++;
                    }
                  }
                }
                if (upstreamHighFlow >= 2) {
                  type = SmartWaypointType.valleyJunction;
                }
              }
            }
            break;
          case 5: // channel — stream split (enhanced with flow accumulation)
            {
              final flowAcc = _getFlowAccumulation();
              final cellFlow = flowAcc[idx];
              if (cellFlow > 20) {
                // High flow confirms real stream channel
                type = SmartWaypointType.streamSplit;
              } else {
                // Low flow: check if channel arms diverge (actual split)
                const directions = [(-1,0),(-1,1),(0,1),(1,1),(1,0),(1,-1),(0,-1),(-1,-1)];
                int channelNeighbors = 0;
                for (final (dr, dc) in directions) {
                  for (int step = 1; step <= 2; step++) {
                    final nr = r + dr * step;
                    final nc = c + dc * step;
                    if (nr >= 0 && nr < rows && nc >= 0 && nc < cols) {
                      final nf = featureGrid[nr * cols + nc];
                      if (nf == 5) { channelNeighbors++; break; }
                    }
                  }
                }
                if (channelNeighbors >= 2) {
                  type = SmartWaypointType.streamSplit;
                }
              }
            }
            break;
          case 6: // TPI saddle — verify topologically
            if (_isTopologicalSaddle(r, c, dem, rows, cols)) {
              type = SmartWaypointType.saddlePoint;
            }
            break;
          default:
            continue;
        }

        if (type == null) continue;

        // Filter by boundary mask
        if (_boundaryMask != null && _boundaryMask![idx] == 0) continue;

        // Check if it's a local peak (higher than all 8 neighbors)
        bool isLocalPeak = true;
        for (int dr = -1; dr <= 1; dr++) {
          for (int dc = -1; dc <= 1; dc++) {
            if (dr == 0 && dc == 0) continue;
            final nVal = dem[(r + dr) * cols + (c + dc)].toDouble();
            if (nVal != -32768 && nVal >= elev) {
              isLocalPeak = false;
              break;
            }
          }
          if (!isLocalPeak) break;
        }
        if (isLocalPeak && feature == 1) {
          type = SmartWaypointType.localPeak;
        }

        waypoints.add(SmartWaypoint(
          position: _subGridToLatLng(r, c),
          type: type,
          prominence: prominence,
          elevation: dem[idx],
        ));
      }
    }

    return _applyWaypointSpacing(waypoints);
  }

  /// Check if cell (r,c) is a local extremum within its feature class
  bool _isLocalExtremum(
      int r, int c, int feature, Int16List dem, Uint8List featureGrid, int rows, int cols) {
    final elev = dem[r * cols + c].toDouble();
    // For domes/ridges/spurs: local max among same-feature neighbors
    // For valleys/channels: local min among same-feature neighbors
    final isHigh = (feature == 1 || feature == 2 || feature == 3 || feature == 6);

    for (int dr = -1; dr <= 1; dr++) {
      for (int dc = -1; dc <= 1; dc++) {
        if (dr == 0 && dc == 0) continue;
        final nr = r + dr;
        final nc = c + dc;
        if (nr < 0 || nr >= rows || nc < 0 || nc >= cols) continue;
        final nIdx = nr * cols + nc;
        if (featureGrid[nIdx] != feature) continue;
        final nElev = dem[nIdx].toDouble();
        if (nElev == -32768) continue;
        if (isHigh && nElev > elev) return false;
        if (!isHigh && nElev < elev) return false;
      }
    }
    return true;
  }

  /// Compute connected component sizes for each feature cell
  Int32List _computeFeatureClusterSizes(Uint8List featureGrid, int rows, int cols) {
    final n = rows * cols;
    final labels = Int32List(n);
    final sizes = <int, int>{};
    int nextLabel = 1;

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final idx = r * cols + c;
        final feature = featureGrid[idx];
        if (feature == 0 || feature == 7 || labels[idx] != 0) continue;

        // BFS flood fill for same-feature cells
        final queue = <int>[idx];
        labels[idx] = nextLabel;
        int head = 0;
        int size = 0;
        while (head < queue.length) {
          final ci = queue[head++];
          size++;
          final cr = ci ~/ cols;
          final cc = ci % cols;
          for (int dr = -1; dr <= 1; dr++) {
            for (int dc = -1; dc <= 1; dc++) {
              if (dr == 0 && dc == 0) continue;
              final nr = cr + dr;
              final nc = cc + dc;
              if (nr < 0 || nr >= rows || nc < 0 || nc >= cols) continue;
              final ni = nr * cols + nc;
              if (labels[ni] == 0 && featureGrid[ni] == feature) {
                labels[ni] = nextLabel;
                queue.add(ni);
              }
            }
          }
        }
        sizes[nextLabel] = size;
        nextLabel++;
      }
    }

    // Map back to per-cell sizes
    final result = Int32List(n);
    for (int i = 0; i < n; i++) {
      if (labels[i] != 0) {
        result[i] = sizes[labels[i]] ?? 0;
      }
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // Vulnerability analysis helpers
  // ---------------------------------------------------------------------------

  /// TRI (Terrain Ruggedness Index) — RMS of elevation differences to 8 neighbors
  Float32List _computeTRI() {
    final dem = _activeDem!;
    final rows = _activeRows, cols = _activeCols;
    final tri = Float32List(rows * cols);
    const dr = [-1, -1, 0, 1, 1, 1, 0, -1];
    const dc = [0, 1, 1, 1, 0, -1, -1, -1];
    for (int r = 1; r < rows - 1; r++) {
      for (int c = 1; c < cols - 1; c++) {
        final idx = r * cols + c;
        final center = dem[idx].toDouble();
        if (center == -32768) continue;
        double sumSq = 0;
        int count = 0;
        for (int d = 0; d < 8; d++) {
          final val = dem[(r + dr[d]) * cols + (c + dc[d])].toDouble();
          if (val == -32768) continue;
          final diff = val - center;
          sumSq += diff * diff;
          count++;
        }
        tri[idx] = count > 0 ? sqrt(sumSq / count) : 0;
      }
    }
    return tri;
  }

  /// Curvature grid (Laplacian) — uses Gaussian-smoothed DEM
  Float32List _computeCurvatureGrid() {
    final smoothed = _getSmoothedDem();
    final rows = _activeRows, cols = _activeCols;
    final cellNS = cellSizeNS(_activeSrcGridSize);
    final centerLat = (_activeBounds!.north + _activeBounds!.south) / 2;
    final cellEW = cellSizeEW(centerLat, _activeSrcGridSize);
    final curvature = Float32List(rows * cols);
    for (int r = 1; r < rows - 1; r++) {
      for (int c = 1; c < cols - 1; c++) {
        final idx = r * cols + c;
        final center = smoothed[idx];
        if (center == -32768) continue;
        final up = smoothed[(r - 1) * cols + c];
        final down = smoothed[(r + 1) * cols + c];
        final left = smoothed[r * cols + (c - 1)];
        final right = smoothed[r * cols + (c + 1)];
        if (up == -32768 || down == -32768 || left == -32768 || right == -32768) continue;
        // Laplacian: positive = concave (pit/channel), negative = convex (cliff edge)
        curvature[idx] = ((up + down - 2 * center) / (cellNS * cellNS) +
                           (left + right - 2 * center) / (cellEW * cellEW)).toDouble();
      }
    }
    return curvature;
  }

  /// Local relief grid — max−min elevation within distance-based window
  Float32List _computeLocalReliefGrid() {
    final dem = _activeDem!;
    final rows = _activeRows, cols = _activeCols;
    const reliefRadiusMeters = 100.0;
    final windowR = (reliefRadiusMeters / cellSizeNS(_activeSrcGridSize)).round().clamp(1, 5);
    final relief = Float32List(rows * cols);
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final idx = r * cols + c;
        if (dem[idx] == -32768) continue;
        double minE = 32767, maxE = -32768;
        for (int dr = -windowR; dr <= windowR; dr++) {
          for (int dc = -windowR; dc <= windowR; dc++) {
            final nr = r + dr, nc = c + dc;
            if (nr < 0 || nr >= rows || nc < 0 || nc >= cols) continue;
            final val = dem[nr * cols + nc].toDouble();
            if (val == -32768) continue;
            if (val < minE) minE = val;
            if (val > maxE) maxE = val;
          }
        }
        relief[idx] = maxE > minE ? (maxE - minE).toDouble() : 0;
      }
    }
    return relief;
  }

  /// Adaptive threshold — scales base threshold by local relief
  double _adaptiveThreshold(double baseThreshold, double localRelief) {
    final scale = 0.8 + 0.4 * log(localRelief / 50.0 + 1);
    return baseThreshold * scale.clamp(0.5, 1.5);
  }

  /// Combined severity — multi-factor score per vulnerability type
  double _computePointSeverity(VulnerabilityType type, {
    required double slope,
    required double curvature,
    required double depth,
    required double tri,
    required double localRelief,
  }) {
    switch (type) {
      case VulnerabilityType.cliff:
        return (0.60 * (slope / 90.0).clamp(0.0, 1.0) +
                0.20 * (curvature.abs() / 0.05).clamp(0.0, 1.0) +
                0.15 * (tri / 30.0).clamp(0.0, 1.0) +
                0.05 * (localRelief / 200.0).clamp(0.0, 1.0)).clamp(0.0, 1.0);
      case VulnerabilityType.pit:
        return (0.20 * (slope / 45.0).clamp(0.0, 1.0) +
                0.20 * (curvature.abs() / 0.05).clamp(0.0, 1.0) +
                0.40 * (depth / 30.0).clamp(0.0, 1.0) +
                0.10 * (tri / 30.0).clamp(0.0, 1.0) +
                0.10 * (localRelief / 200.0).clamp(0.0, 1.0)).clamp(0.0, 1.0);
      case VulnerabilityType.deepChannel:
        return (0.40 * (slope / 60.0).clamp(0.0, 1.0) +
                0.30 * (curvature.abs() / 0.05).clamp(0.0, 1.0) +
                0.20 * (tri / 30.0).clamp(0.0, 1.0) +
                0.10 * (localRelief / 200.0).clamp(0.0, 1.0)).clamp(0.0, 1.0);
      case VulnerabilityType.steepSlope:
        return (0.60 * (slope / 60.0).clamp(0.0, 1.0) +
                0.10 * (curvature.abs() / 0.05).clamp(0.0, 1.0) +
                0.20 * (tri / 30.0).clamp(0.0, 1.0) +
                0.10 * (localRelief / 200.0).clamp(0.0, 1.0)).clamp(0.0, 1.0);
    }
  }

  /// Marching squares contour — extracts concave boundary from cell set
  List<LatLng> _marchingSquaresContour(Set<int> cellSet, int cols, int rows) {
    // Build binary grid (padded by 1 on each side)
    final w = cols + 2, h = rows + 2;
    final grid = Uint8List(w * h);
    for (final idx in cellSet) {
      final r = idx ~/ cols, c = idx % cols;
      grid[(r + 1) * w + (c + 1)] = 1;
    }

    // Find first boundary edge
    int startR = -1, startC = -1;
    outer:
    for (int r = 0; r < h - 1; r++) {
      for (int c = 0; c < w - 1; c++) {
        // Top-left of 2x2 block
        final tl = grid[r * w + c];
        final tr = grid[r * w + c + 1];
        final bl = grid[(r + 1) * w + c];
        final br = grid[(r + 1) * w + c + 1];
        final config = tl | (tr << 1) | (bl << 2) | (br << 3);
        if (config != 0 && config != 15) {
          startR = r;
          startC = c;
          break outer;
        }
      }
    }
    if (startR < 0) return [];

    // Trace contour
    final contourPoints = <(double, double)>[];
    final visited = <int>{};
    int cr = startR, cc = startC;
    int prevDir = 0; // 0=right, 1=down, 2=left, 3=up

    for (int step = 0; step < w * h * 2; step++) {
      final key = cr * w + cc;
      if (visited.contains(key) && step > 2 && cr == startR && cc == startC) break;
      visited.add(key);

      final tl = grid[cr * w + cc];
      final tr = grid[cr * w + cc + 1];
      final bl = grid[(cr + 1) * w + cc];
      final br = grid[(cr + 1) * w + cc + 1];
      final config = tl | (tr << 1) | (bl << 2) | (br << 3);

      // Add midpoint of the boundary edge
      // Map back to original grid coordinates (subtract 1 for padding)
      final midR = cr + 0.5 - 1.0;
      final midC = cc + 0.5 - 1.0;
      contourPoints.add((midR, midC));

      // Direction lookup for marching squares
      int nextDir;
      switch (config) {
        case 1: nextDir = 3; break;  // TL only -> up
        case 2: nextDir = 0; break;  // TR only -> right
        case 3: nextDir = 0; break;  // TL+TR -> right
        case 4: nextDir = 2; break;  // BL only -> left
        case 5: nextDir = 3; break;  // TL+BL -> up
        case 6:                       // TR+BL -> saddle
          nextDir = (prevDir == 3) ? 2 : 0;
          break;
        case 7: nextDir = 0; break;  // TL+TR+BL -> right
        case 8: nextDir = 1; break;  // BR only -> down
        case 9:                       // TL+BR -> saddle
          nextDir = (prevDir == 0) ? 3 : 1;
          break;
        case 10: nextDir = 1; break; // TR+BR -> down
        case 11: nextDir = 1; break; // TL+TR+BR -> down
        case 12: nextDir = 2; break; // BL+BR -> left
        case 13: nextDir = 3; break; // TL+BL+BR -> up
        case 14: nextDir = 2; break; // TR+BL+BR -> left
        default: nextDir = prevDir; break;
      }

      switch (nextDir) {
        case 0: cc++; break; // right
        case 1: cr++; break; // down
        case 2: cc--; break; // left
        case 3: cr--; break; // up
      }
      prevDir = nextDir;

      if (cc < 0 || cc >= w - 1 || cr < 0 || cr >= h - 1) break;
    }

    if (contourPoints.length < 3) return [];

    // Convert grid row/col to LatLng
    final result = <LatLng>[];
    for (final (r, c) in contourPoints) {
      final clampedR = r.clamp(0, _activeRows - 1);
      final clampedC = c.clamp(0, _activeCols - 1);
      result.add(_subGridToLatLng(clampedR.round(), clampedC.round()));
    }

    return _simplifyPolygon(result);
  }

  /// Douglas-Peucker polygon simplification
  List<LatLng> _simplifyPolygon(List<LatLng> polygon, {double epsilon = 0.0001}) {
    if (polygon.length <= 4) return polygon;

    double maxDist = 0;
    int maxIdx = 0;
    final first = polygon.first;
    final last = polygon.last;

    for (int i = 1; i < polygon.length - 1; i++) {
      final d = _perpendicularDistance(polygon[i], first, last);
      if (d > maxDist) {
        maxDist = d;
        maxIdx = i;
      }
    }

    if (maxDist > epsilon) {
      final left = _simplifyPolygon(polygon.sublist(0, maxIdx + 1), epsilon: epsilon);
      final right = _simplifyPolygon(polygon.sublist(maxIdx), epsilon: epsilon);
      return [...left.sublist(0, left.length - 1), ...right];
    } else {
      return [first, last];
    }
  }

  double _perpendicularDistance(LatLng point, LatLng lineStart, LatLng lineEnd) {
    final dx = lineEnd.longitude - lineStart.longitude;
    final dy = lineEnd.latitude - lineStart.latitude;
    if (dx == 0 && dy == 0) {
      return sqrt(pow(point.longitude - lineStart.longitude, 2) +
                  pow(point.latitude - lineStart.latitude, 2));
    }
    final t = ((point.longitude - lineStart.longitude) * dx +
               (point.latitude - lineStart.latitude) * dy) /
              (dx * dx + dy * dy);
    final closestLng = lineStart.longitude + t * dx;
    final closestLat = lineStart.latitude + t * dy;
    return sqrt(pow(point.longitude - closestLng, 2) +
                pow(point.latitude - closestLat, 2));
  }

  // ---------------------------------------------------------------------------
  // Vulnerability detection — points and zones
  // ---------------------------------------------------------------------------

  /// זיהוי נקודות תורפה — מצוקים, בורות (Pure Dart)
  Future<List<VulnerabilityPoint>> detectVulnerabilities({
    double cliffThreshold = 45.0,
    double pitThreshold = 20.0,
    double minDepth = 2.0,
    int pitWindowRadius = 2,
  }) async {
    if (_activeDem == null) return [];

    final slopeAspect = await computeSlopeAspect();
    if (slopeAspect == null) return [];

    final rows = _activeRows;
    final cols = _activeCols;
    final dem = _activeDem!;
    final slopeGrid = slopeAspect.slopeGrid;
    final triGrid = _computeTRI();
    final curvatureGrid = _computeCurvatureGrid();
    final reliefGrid = _computeLocalReliefGrid();
    final points = <VulnerabilityPoint>[];

    final margin = pitWindowRadius + 1;
    for (int r = margin; r < rows - margin; r++) {
      for (int c = margin; c < cols - margin; c++) {
        final idx = r * cols + c;
        final elev = dem[idx].toDouble();
        if (elev == -32768) continue;

        // Filter by boundary mask
        if (_boundaryMask != null && _boundaryMask![idx] == 0) continue;

        final slope = slopeGrid[idx];
        final relief = reliefGrid[idx];
        final curv = curvatureGrid[idx];
        final tri = triGrid[idx];

        // Adaptive cliff threshold based on local relief
        final adaptedCliff = _adaptiveThreshold(cliffThreshold, relief.toDouble());

        // Cliff detection
        if (slope >= adaptedCliff) {
          final severity = _computePointSeverity(VulnerabilityType.cliff,
            slope: slope, curvature: curv, depth: 0, tri: tri, localRelief: relief);
          final pos = _subGridToLatLng(r, c);
          points.add(VulnerabilityPoint(
            position: pos,
            type: VulnerabilityType.cliff,
            severity: severity,
            slopeAtPoint: slope,
            curvature: curv,
            localRelief: relief,
            tri: tri,
          ));
          continue;
        }

        // Expanded pit detection with variable window size
        final adaptedPit = _adaptiveThreshold(pitThreshold, relief.toDouble());
        if (slope >= adaptedPit) {
          // Inner ring (3x3): center must be lower than average of neighbors
          double innerSum = 0;
          int innerCount = 0;
          bool innerLower = true;
          for (int dr = -1; dr <= 1; dr++) {
            for (int dc = -1; dc <= 1; dc++) {
              if (dr == 0 && dc == 0) continue;
              final nVal = dem[(r + dr) * cols + (c + dc)].toDouble();
              if (nVal != -32768) {
                innerSum += nVal;
                innerCount++;
              }
            }
          }
          if (innerCount > 0) {
            innerLower = elev < (innerSum / innerCount);
          }

          if (innerLower && pitWindowRadius > 1) {
            // Outer ring: average must be higher than inner average
            double outerSum = 0;
            int outerCount = 0;
            for (int dr = -pitWindowRadius; dr <= pitWindowRadius; dr++) {
              for (int dc = -pitWindowRadius; dc <= pitWindowRadius; dc++) {
                if (dr.abs() <= 1 && dc.abs() <= 1) continue; // skip inner ring
                final nr = r + dr, nc = c + dc;
                if (nr < 0 || nr >= rows || nc < 0 || nc >= cols) continue;
                final val = dem[nr * cols + nc].toDouble();
                if (val != -32768) {
                  outerSum += val;
                  outerCount++;
                }
              }
            }
            if (outerCount > 0 && innerCount > 0) {
              final outerAvg = outerSum / outerCount;
              final innerAvg = innerSum / innerCount;
              if (outerAvg <= innerAvg) innerLower = false;
            }
          }

          if (innerLower) {
            // Compute depth = difference from surrounding average
            double windowSum = 0;
            int windowCount = 0;
            for (int dr = -pitWindowRadius; dr <= pitWindowRadius; dr++) {
              for (int dc = -pitWindowRadius; dc <= pitWindowRadius; dc++) {
                if (dr == 0 && dc == 0) continue;
                final nr = r + dr, nc = c + dc;
                if (nr < 0 || nr >= rows || nc < 0 || nc >= cols) continue;
                final val = dem[nr * cols + nc].toDouble();
                if (val != -32768) {
                  windowSum += val;
                  windowCount++;
                }
              }
            }
            final depth = windowCount > 0 ? (windowSum / windowCount - elev) : 0.0;

            // minDepth filter — reject SRTM noise
            if (depth >= minDepth) {
              final severity = _computePointSeverity(VulnerabilityType.pit,
                slope: slope, curvature: curv, depth: depth, tri: tri, localRelief: relief);
              final pos = _subGridToLatLng(r, c);
              points.add(VulnerabilityPoint(
                position: pos,
                type: VulnerabilityType.pit,
                severity: severity,
                slopeAtPoint: slope,
                curvature: curv,
                depth: depth,
                localRelief: relief,
                tri: tri,
              ));
            }
          }
        }
      }
    }

    return points;
  }

  // ---------------------------------------------------------------------------
  // Vulnerability zone detection — connected component clustering (Pure Dart)
  // Enhanced with cross-type expansion, merge, buffer, marching squares contour
  // ---------------------------------------------------------------------------

  /// זיהוי אזורי תורפה — מקבץ נקודות תורפה סמוכות לפוליגונים
  Future<List<VulnerabilityZone>> detectVulnerabilityZones({
    double cliffThreshold = 45.0,
    double pitThreshold = 20.0,
    int minClusterCells = 5,
    double minAreaSquareMeters = 3000.0,
    double crossTypeThreshold = 20.0,
  }) async {
    // First get the slope grid
    final slopeResult = await computeSlopeAspect();
    if (slopeResult == null || _activeDem == null) return [];

    final rows = _activeRows;
    final cols = _activeCols;
    final n = rows * cols;
    final dem = _activeDem!;
    final cellNS = cellSizeNS(_activeSrcGridSize);
    final centerLat = (_activeBounds!.north + _activeBounds!.south) / 2;
    final cellEW = cellSizeEW(centerLat, _activeSrcGridSize);
    final cellAreaM2 = cellNS * cellEW;

    // Pre-compute auxiliary grids
    final triGrid = _computeTRI();
    final curvatureGrid = _computeCurvatureGrid();

    // Use cached features for deepChannel detection
    final features = _cachedFeatures ?? await classifyFeatures();

    // Build vulnerability grid: type at each cell (0=none)
    final vulnGrid = Uint8List(n);
    for (int r = 1; r < rows - 1; r++) {
      for (int c = 1; c < cols - 1; c++) {
        final i = r * cols + c;
        if (_boundaryMask != null && _boundaryMask![i] == 0) continue;
        final slope = slopeResult.slopeGrid[i];
        final elev = dem[i];
        if (elev == -32768) continue;

        if (slope >= cliffThreshold) {
          vulnGrid[i] = 1; // cliff
        } else if (slope >= cliffThreshold * 0.8) {
          // Check if it's a pit (lower than all neighbors)
          bool isPit = true;
          for (int dr = -1; dr <= 1; dr++) {
            for (int dc = -1; dc <= 1; dc++) {
              if (dr == 0 && dc == 0) continue;
              final ni = (r + dr) * cols + (c + dc);
              if (dem[ni] != -32768 && dem[ni] < elev) {
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

    // Phase 1: Connected component labeling (strict same-type BFS)
    final labels = Int32List(n);
    int nextLabel = 1;
    final labelType = <int, int>{}; // label -> vuln type

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final i = r * cols + c;
        if (vulnGrid[i] == 0 || labels[i] != 0) continue;

        // BFS flood fill
        final queue = <int>[i];
        labels[i] = nextLabel;
        labelType[nextLabel] = vulnGrid[i];
        int head = 0;
        while (head < queue.length) {
          final ci = queue[head++];
          final cr = ci ~/ cols;
          final cc = ci % cols;
          for (int dr = -1; dr <= 1; dr++) {
            for (int dc = -1; dc <= 1; dc++) {
              if (dr == 0 && dc == 0) continue;
              final nr = cr + dr;
              final nc = cc + dc;
              if (nr < 0 || nr >= rows || nc < 0 || nc >= cols) continue;
              final ni = nr * cols + nc;
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

    // Phase 2: Cross-type boundary expansion
    // Unlabeled cells with vulnGrid != 0 that are adjacent to a labeled zone
    // and have slope >= crossTypeThreshold get absorbed
    for (int r = 1; r < rows - 1; r++) {
      for (int c = 1; c < cols - 1; c++) {
        final i = r * cols + c;
        if (labels[i] != 0 || vulnGrid[i] == 0) continue;
        if (slopeResult.slopeGrid[i] < crossTypeThreshold) continue;

        // Find largest adjacent labeled zone
        int bestLabel = 0;
        for (int dr = -1; dr <= 1; dr++) {
          for (int dc = -1; dc <= 1; dc++) {
            if (dr == 0 && dc == 0) continue;
            final nr = r + dr, nc = c + dc;
            if (nr < 0 || nr >= rows || nc < 0 || nc >= cols) continue;
            final nl = labels[nr * cols + nc];
            if (nl > 0) {
              // Pick any neighbor label
              if (bestLabel == 0 || nl != bestLabel) {
                bestLabel = nl;
              }
            }
          }
        }
        if (bestLabel > 0) {
          labels[i] = bestLabel;
        }
      }
    }

    // Collect cells per label + compute slope stats for merge check
    final labelCells = <int, List<int>>{};
    final labelSlopeSum = <int, double>{};
    for (int i = 0; i < n; i++) {
      if (labels[i] > 0) {
        labelCells.putIfAbsent(labels[i], () => []).add(i);
        labelSlopeSum[labels[i]] = (labelSlopeSum[labels[i]] ?? 0) + slopeResult.slopeGrid[i];
      }
    }

    // Merge adjacent same-type components with slope similarity check
    final labelAvgSlope = <int, double>{};
    for (final entry in labelCells.entries) {
      labelAvgSlope[entry.key] = labelSlopeSum[entry.key]! / entry.value.length;
    }

    // Build bounding boxes per label for fast proximity check
    final labelMinR = <int, int>{}, labelMaxR = <int, int>{};
    final labelMinC = <int, int>{}, labelMaxC = <int, int>{};
    for (final entry in labelCells.entries) {
      int minR = rows, maxR = 0, minC = cols, maxC = 0;
      for (final idx in entry.value) {
        final r = idx ~/ cols, c = idx % cols;
        if (r < minR) minR = r;
        if (r > maxR) maxR = r;
        if (c < minC) minC = c;
        if (c > maxC) maxC = c;
      }
      labelMinR[entry.key] = minR;
      labelMaxR[entry.key] = maxR;
      labelMinC[entry.key] = minC;
      labelMaxC[entry.key] = maxC;
    }

    // Union-Find for merging
    final parent = <int, int>{};
    int find(int x) {
      if (!parent.containsKey(x)) parent[x] = x;
      if (parent[x] != x) parent[x] = find(parent[x]!);
      return parent[x]!;
    }
    void union(int a, int b) {
      final ra = find(a), rb = find(b);
      if (ra != rb) parent[ra] = rb;
    }

    final sortedLabels = labelCells.keys.toList();
    for (int i = 0; i < sortedLabels.length; i++) {
      final la = sortedLabels[i];
      final typeA = labelType[la] ?? 0;
      for (int j = i + 1; j < sortedLabels.length; j++) {
        final lb = sortedLabels[j];
        final typeB = labelType[lb] ?? 0;
        if (typeA != typeB) continue;

        // Fast bbox proximity check (within 1 cell)
        if (labelMinR[la]! > labelMaxR[lb]! + 2 || labelMaxR[la]! < labelMinR[lb]! - 2) continue;
        if (labelMinC[la]! > labelMaxC[lb]! + 2 || labelMaxC[la]! < labelMinC[lb]! - 2) continue;

        // Slope similarity check
        if ((labelAvgSlope[la]! - labelAvgSlope[lb]!).abs() >= 10.0) continue;

        // Check if any cell in la is within 1 cell of lb
        final setB = Set<int>.from(labelCells[lb]!);
        bool adjacent = false;
        for (final idx in labelCells[la]!) {
          final r = idx ~/ cols, c = idx % cols;
          for (int dr = -1; dr <= 1 && !adjacent; dr++) {
            for (int dc = -1; dc <= 1 && !adjacent; dc++) {
              if (dr == 0 && dc == 0) continue;
              final nr = r + dr, nc = c + dc;
              if (nr >= 0 && nr < rows && nc >= 0 && nc < cols) {
                if (setB.contains(nr * cols + nc)) adjacent = true;
              }
            }
          }
          if (adjacent) break;
        }
        if (adjacent) union(la, lb);
      }
    }

    // Rebuild merged cell lists
    final mergedCells = <int, List<int>>{};
    final mergedType = <int, int>{};
    for (final entry in labelCells.entries) {
      final root = find(entry.key);
      mergedCells.putIfAbsent(root, () => []).addAll(entry.value);
      mergedType[root] = labelType[entry.key] ?? 1;
    }

    // Buffer zones — distance-based dilation
    const bufferMeters = 15.0;
    final bufferCells = (bufferMeters / cellNS).round().clamp(0, 1);

    // For each merged component, create zone
    final zones = <VulnerabilityZone>[];
    for (final entry in mergedCells.entries) {
      var cells = entry.value;

      // Area-based filtering
      final zoneAreaM2 = cells.length * cellAreaM2;
      if (zoneAreaM2 < minAreaSquareMeters) continue;

      // Apply buffer dilation
      if (bufferCells > 0) {
        final expanded = Set<int>.from(cells);
        for (final idx in cells) {
          final r = idx ~/ cols, c = idx % cols;
          for (int dr = -bufferCells; dr <= bufferCells; dr++) {
            for (int dc = -bufferCells; dc <= bufferCells; dc++) {
              final nr = r + dr, nc = c + dc;
              if (nr >= 0 && nr < rows && nc >= 0 && nc < cols) {
                expanded.add(nr * cols + nc);
              }
            }
          }
        }
        cells = expanded.toList();
      }

      // Compute stats
      double slopeSum = 0, slopeMax = 0;
      double curvSum = 0, triSum = 0;
      double minElev = 32767, maxElev = -32768;
      int statCount = 0;
      for (final ci in cells) {
        final s = slopeResult.slopeGrid[ci];
        slopeSum += s;
        if (s > slopeMax) slopeMax = s;
        curvSum += curvatureGrid[ci];
        triSum += triGrid[ci];
        final elev = dem[ci].toDouble();
        if (elev != -32768) {
          if (elev < minElev) minElev = elev;
          if (elev > maxElev) maxElev = elev;
        }
        statCount++;
      }
      final avgSlope = statCount > 0 ? slopeSum / statCount : 0.0;
      final avgCurv = statCount > 0 ? curvSum / statCount : 0.0;
      final avgTri = statCount > 0 ? triSum / statCount : 0.0;
      final areaM2 = cells.length * cellAreaM2;

      // Compute concave hull via marching squares
      final cellSet = Set<int>.from(cells);
      var hull = _marchingSquaresContour(cellSet, cols, rows);
      if (hull.length < 3) {
        // Fallback to convex hull
        final pts = <LatLng>[];
        for (final i in cells) {
          pts.add(_subGridToLatLng(i ~/ cols, i % cols));
        }
        hull = _convexHull(pts);
      }
      if (hull.length < 3) continue;

      final typeIdx = mergedType[entry.key] ?? 1;
      final vulnType = typeIdx >= 1 && typeIdx <= VulnerabilityType.values.length
          ? VulnerabilityType.values[typeIdx - 1]
          : VulnerabilityType.cliff;

      // Multi-factor severity
      final severity = (
        0.45 * (avgSlope / 60.0).clamp(0.0, 1.0) +
        0.25 * (slopeMax / 75.0).clamp(0.0, 1.0) +
        0.15 * (avgCurv.abs() / 0.05).clamp(0.0, 1.0) +
        0.10 * (areaM2 / 10000.0).clamp(0.0, 1.0) +
        0.05 * ((maxElev - minElev) / 100.0).clamp(0.0, 1.0)
      ).clamp(0.0, 1.0);

      zones.add(VulnerabilityZone(
        polygon: hull,
        type: vulnType,
        severity: severity,
        cellCount: cells.length,
        avgSlope: avgSlope,
        maxSlope: slopeMax,
        areaSquareMeters: areaM2,
        minElevation: minElev == 32767 ? 0 : minElev,
        maxElevation: maxElev == -32768 ? 0 : maxElev,
        avgCurvature: avgCurv,
        avgTri: avgTri,
      ));
    }

    return zones;
  }

  /// Compute combined viewshed for multiple enemies — reusable
  Future<Uint8List?> computeCombinedViewshed(
    List<LatLng> enemies, {
    double enemyHeight = 1.7,
  }) async {
    if (_activeDem == null || enemies.isEmpty) return null;

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
          // Use previous point's visibility for the segment
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
  // Helper: Gaussian σ=1 smoothed DEM (cached)
  // ---------------------------------------------------------------------------

  /// חישוב DEM מוחלק עם Gaussian σ=1 — לייצוב sign changes בזיהוי אוכפים
  Float64List _getSmoothedDem() {
    if (_smoothedDem != null) return _smoothedDem!;

    final dem = _activeDem!;
    final rows = _activeRows;
    final cols = _activeCols;
    final smoothed = Float64List(rows * cols);

    // Gaussian 3×3, σ=1: [1,2,1; 2,4,2; 1,2,1] / 16
    const kernel = [1.0, 2.0, 1.0, 2.0, 4.0, 2.0, 1.0, 2.0, 1.0];

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final idx = r * cols + c;
        if (dem[idx] == -32768) {
          smoothed[idx] = -32768;
          continue;
        }
        if (r < 1 || r >= rows - 1 || c < 1 || c >= cols - 1) {
          smoothed[idx] = dem[idx].toDouble();
          continue;
        }
        double sum = 0;
        double weight = 0;
        int ki = 0;
        for (int dr = -1; dr <= 1; dr++) {
          for (int dc = -1; dc <= 1; dc++) {
            final val = dem[(r + dr) * cols + (c + dc)].toDouble();
            if (val != -32768) {
              sum += val * kernel[ki];
              weight += kernel[ki];
            }
            ki++;
          }
        }
        smoothed[idx] = weight > 0 ? sum / weight : dem[idx].toDouble();
      }
    }

    _smoothedDem = smoothed;
    return smoothed;
  }

  // ---------------------------------------------------------------------------
  // Helper: D8 flow accumulation (cached)
  // ---------------------------------------------------------------------------

  /// חישוב צבירת זרימה D8 — לזיהוי נחלים וצמתי ואדיות
  Int32List _getFlowAccumulation() {
    if (_flowAccumulation != null) return _flowAccumulation!;

    final dem = _activeDem!;
    final rows = _activeRows;
    final cols = _activeCols;
    final n = rows * cols;

    // D8 flow direction: each cell flows to steepest descent neighbor
    final flowDir = Int8List(n);
    for (int i = 0; i < n; i++) flowDir[i] = -1;

    const dr = [-1, -1, 0, 1, 1, 1, 0, -1];
    const dc = [0, 1, 1, 1, 0, -1, -1, -1];
    // Distance weights: cardinal = 1, diagonal = √2
    const dist = [1.0, 1.414, 1.0, 1.414, 1.0, 1.414, 1.0, 1.414];

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final idx = r * cols + c;
        final elev = dem[idx].toDouble();
        if (elev == -32768) continue;

        double maxSlope = 0;
        int bestDir = -1;
        for (int d = 0; d < 8; d++) {
          final nr = r + dr[d], nc = c + dc[d];
          if (nr < 0 || nr >= rows || nc < 0 || nc >= cols) continue;
          final nElev = dem[nr * cols + nc].toDouble();
          if (nElev == -32768) continue;
          final drop = elev - nElev;
          if (drop > 0) {
            final slope = drop / dist[d];
            if (slope > maxSlope) {
              maxSlope = slope;
              bestDir = d;
            }
          }
        }
        flowDir[idx] = bestDir;
      }
    }

    // Sort cells by elevation (descending) for top-down accumulation
    final indices = List<int>.generate(n, (i) => i);
    indices.sort((a, b) {
      final ea = dem[a] == -32768 ? -99999 : dem[a];
      final eb = dem[b] == -32768 ? -99999 : dem[b];
      return eb.compareTo(ea);
    });

    final accumulation = Int32List(n);
    for (int i = 0; i < n; i++) accumulation[i] = 1; // each cell contributes 1

    for (final idx in indices) {
      if (dem[idx] == -32768) continue;
      final dir = flowDir[idx];
      if (dir < 0) continue;

      final r = idx ~/ cols;
      final c = idx % cols;
      final nr = r + dr[dir], nc = c + dc[dir];
      if (nr >= 0 && nr < rows && nc >= 0 && nc < cols) {
        accumulation[nr * cols + nc] += accumulation[idx];
      }
    }

    _flowAccumulation = accumulation;
    return accumulation;
  }

  // ---------------------------------------------------------------------------
  // Helper: topological saddle detection (Gaussian-smoothed)
  // ---------------------------------------------------------------------------

  /// בדיקת אוכף טופולוגי — שימוש ב-DEM מוחלק (Gaussian σ=1) לייצוב sign changes
  bool _isTopologicalSaddle(int r, int c, Int16List dem, int rows, int cols) {
    // Use Gaussian-smoothed DEM for stable sign changes
    final smoothed = _getSmoothedDem();
    final center = smoothed[r * cols + c];
    if (center == -32768) return false;

    const drDir = [-1, -1, 0, 1, 1, 1, 0, -1];
    const dcDir = [0, 1, 1, 1, 0, -1, -1, -1];

    int signChanges = 0, lastSign = 0, firstSign = 0;
    for (int d = 0; d < 8; d++) {
      final nr = r + drDir[d], nc = c + dcDir[d];
      if (nr < 0 || nr >= rows || nc < 0 || nc >= cols) return false;
      final val = smoothed[nr * cols + nc];
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
  // Helper: 8-directional line-of-sight for dome visibility classification
  // ---------------------------------------------------------------------------

  /// סיווג כיפה — בדיקת נראות מ-8 כיוונים. אם נראית מ-≤2 כיוונים → כיפה סמויה
  SmartWaypointType _classifyDomeVisibility(int r, int c) {
    final dem = _activeDem!;
    final rows = _activeRows, cols = _activeCols;
    final center = dem[r * cols + c].toDouble();
    if (center == -32768) return SmartWaypointType.domeCenter;

    final cellNS = cellSizeNS(_activeSrcGridSize);
    final centerLat = (_activeBounds!.north + _activeBounds!.south) / 2;
    final cellEW = cellSizeEW(centerLat, _activeSrcGridSize);
    final checkDist = (500.0 / cellNS).round().clamp(1, min(rows, cols) ~/ 4);

    const dirR = [-1, -1, 0, 1, 1, 1, 0, -1];
    const dirC = [0, 1, 1, 1, 0, -1, -1, -1];

    int visibleFrom = 0, totalChecked = 0;

    for (int d = 0; d < 8; d++) {
      // Find lowest point in this direction within checkDist cells
      double lowest = 32767;
      int lowR = r, lowC = c;
      for (int step = 1; step <= checkDist; step++) {
        final rr = r + dirR[d] * step;
        final cc = c + dirC[d] * step;
        if (rr < 0 || rr >= rows || cc < 0 || cc >= cols) break;
        final val = dem[rr * cols + cc].toDouble();
        if (val != -32768 && val < lowest) {
          lowest = val;
          lowR = rr;
          lowC = cc;
        }
      }
      if (lowest >= 32767) continue;
      totalChecked++;

      // Cast line-of-sight from lowest point to dome
      final steps = max((r - lowR).abs(), (c - lowC).abs());
      if (steps == 0) continue;
      double maxAngle = -1e30;
      for (int i = 1; i < steps; i++) {
        final cr = lowR + ((r - lowR) * i / steps).round();
        final cc2 = lowC + ((c - lowC) * i / steps).round();
        if (cr < 0 || cr >= rows || cc2 < 0 || cc2 >= cols) break;
        final val = dem[cr * cols + cc2].toDouble();
        if (val == -32768) continue;
        final dR = (cr - lowR) * cellNS;
        final dC = (cc2 - lowC) * cellEW;
        final dist = sqrt(dR * dR + dC * dC);
        if (dist < 0.001) continue;
        final angle = (val - lowest) / dist;
        if (angle > maxAngle) maxAngle = angle;
      }
      final totalDR = (r - lowR) * cellNS;
      final totalDC = (c - lowC) * cellEW;
      final totalDist = sqrt(totalDR * totalDR + totalDC * totalDC);
      if (totalDist < 0.001) continue;
      if ((center - lowest) / totalDist >= maxAngle) visibleFrom++;
    }

    // Hidden = visible from ≤2 of 8 directions
    return (totalChecked >= 4 && visibleFrom <= 2)
        ? SmartWaypointType.hiddenDome
        : SmartWaypointType.domeCenter;
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

/// A* node for priority queue
class _AStarNode {
  final double f;
  final double g;
  final int row;
  final int col;

  const _AStarNode(this.f, this.g, this.row, this.col);
}
