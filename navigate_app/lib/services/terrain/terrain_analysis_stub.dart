import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../domain/entities/boundary.dart';
import 'terrain_models.dart';

/// Whether terrain analysis is supported on this platform.
const bool terrainIsSupported = false;

/// Stub implementation of TerrainAnalysisService for platforms where
/// native terrain analysis is NOT supported (e.g. mobile builds).
/// All analysis methods return null/empty/false.
class TerrainAnalysisService {
  static final TerrainAnalysisService _instance =
      TerrainAnalysisService._internal();
  factory TerrainAnalysisService() => _instance;
  TerrainAnalysisService._internal();

  bool get isAvailable => false;

  Uint8List? get boundaryMask => null;
  int get activeRows => 0;
  int get activeCols => 0;
  LatLngBounds? get activeBounds => null;

  // קבועי SRTM
  static const int srtm1GridSize = 3601;
  static const int srtm3GridSize = 1201;

  /// גודל תא (מטרים) בכיוון צפון-דרום
  static double cellSizeNS(int gridSize) => 30.87 * (3601.0 / gridSize);

  /// גודל תא (מטרים) בכיוון מזרח-מערב — תלוי בקו רוחב
  static double cellSizeEW(double lat, int gridSize) =>
      30.87 * cos(lat * pi / 180) * (3601.0 / gridSize);

  /// אתחול — no-op בגרסת stub
  Future<void> initialize() async {}

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

  bool hasTile(int lat, int lng) => false;

  int getGridSize(int lat, int lng) => srtm1GridSize;

  Future<bool> loadDemTile(int lat, int lng) async => false;

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

  Future<bool> loadForBoundary(
      Boundary boundary, int tileLat, int tileLng) async => false;

  Future<SlopeAspectResult?> computeSlopeAspect() async => null;

  Future<TerrainFeaturesResult?> classifyFeatures() async => null;

  Future<ViewshedResult?> computeViewshed(
    LatLng observer, {
    double height = 1.7,
    double maxDistKm = 5.0,
  }) async => null;

  Future<HiddenPath?> computeHiddenPath(
    LatLng start,
    LatLng end,
    List<LatLng> enemies, {
    double enemyHeight = 1.7,
    double exposureWeight = 100.0,
  }) async => null;

  Future<List<SmartWaypoint>> detectSmartWaypoints({
    double minProminence = 10.0,
    int minFeatureCells = 5,
  }) async => [];

  Future<List<VulnerabilityPoint>> detectVulnerabilities({
    double cliffThreshold = 45.0,
    double pitThreshold = 20.0,
  }) async => [];

  Future<List<VulnerabilityZone>> detectVulnerabilityZones({
    double cliffThreshold = 45.0,
    double pitThreshold = 20.0,
    int minClusterCells = 5,
  }) async => [];
}
