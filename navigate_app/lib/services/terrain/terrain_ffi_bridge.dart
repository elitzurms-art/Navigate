import 'dart:ffi' as ffi;
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

// --- טיפוסי C לפונקציות native ---

// חישוב שיפוע ונטייה
typedef _SlopeAspectC = ffi.Int32 Function(
  ffi.Pointer<ffi.Int16> dem,
  ffi.Int32 rows,
  ffi.Int32 cols,
  ffi.Double cellSizeNS,
  ffi.Double cellSizeEW,
  ffi.Pointer<ffi.Float> outSlope,
  ffi.Pointer<ffi.Float> outAspect,
);
typedef _SlopeAspectDart = int Function(
  ffi.Pointer<ffi.Int16> dem,
  int rows,
  int cols,
  double cellSizeNS,
  double cellSizeEW,
  ffi.Pointer<ffi.Float> outSlope,
  ffi.Pointer<ffi.Float> outAspect,
);

// סיווג תוואי שטח
typedef _ClassifyFeaturesC = ffi.Int32 Function(
  ffi.Pointer<ffi.Int16> dem,
  ffi.Pointer<ffi.Float> slope,
  ffi.Pointer<ffi.Float> aspect,
  ffi.Int32 rows,
  ffi.Int32 cols,
  ffi.Double cellSizeNS,
  ffi.Double cellSizeEW,
  ffi.Pointer<ffi.Uint8> outFeatures,
);
typedef _ClassifyFeaturesDart = int Function(
  ffi.Pointer<ffi.Int16> dem,
  ffi.Pointer<ffi.Float> slope,
  ffi.Pointer<ffi.Float> aspect,
  int rows,
  int cols,
  double cellSizeNS,
  double cellSizeEW,
  ffi.Pointer<ffi.Uint8> outFeatures,
);

// חישוב קו ראייה
typedef _ViewshedC = ffi.Int32 Function(
  ffi.Pointer<ffi.Int16> dem,
  ffi.Int32 rows,
  ffi.Int32 cols,
  ffi.Double cellSizeNS,
  ffi.Double cellSizeEW,
  ffi.Int32 obsRow,
  ffi.Int32 obsCol,
  ffi.Double obsHeight,
  ffi.Double maxDistCells,
  ffi.Pointer<ffi.Uint8> outVisible,
);
typedef _ViewshedDart = int Function(
  ffi.Pointer<ffi.Int16> dem,
  int rows,
  int cols,
  double cellSizeNS,
  double cellSizeEW,
  int obsRow,
  int obsCol,
  double obsHeight,
  double maxDistCells,
  ffi.Pointer<ffi.Uint8> outVisible,
);

// חישוב מסלול נסתר
typedef _HiddenPathC = ffi.Int32 Function(
  ffi.Pointer<ffi.Int16> dem,
  ffi.Pointer<ffi.Uint8> viewshed,
  ffi.Int32 rows,
  ffi.Int32 cols,
  ffi.Double cellSizeNS,
  ffi.Double cellSizeEW,
  ffi.Int32 startRow,
  ffi.Int32 startCol,
  ffi.Int32 endRow,
  ffi.Int32 endCol,
  ffi.Double exposureWeight,
  ffi.Pointer<ffi.Int32> outPathRows,
  ffi.Pointer<ffi.Int32> outPathCols,
  ffi.Pointer<ffi.Int32> outPathLength,
  ffi.Int32 maxPathLength,
);
typedef _HiddenPathDart = int Function(
  ffi.Pointer<ffi.Int16> dem,
  ffi.Pointer<ffi.Uint8> viewshed,
  int rows,
  int cols,
  double cellSizeNS,
  double cellSizeEW,
  int startRow,
  int startCol,
  int endRow,
  int endCol,
  double exposureWeight,
  ffi.Pointer<ffi.Int32> outPathRows,
  ffi.Pointer<ffi.Int32> outPathCols,
  ffi.Pointer<ffi.Int32> outPathLength,
  int maxPathLength,
);

// זיהוי נקודות ציון חכמות
typedef _SmartWaypointsC = ffi.Int32 Function(
  ffi.Pointer<ffi.Int16> dem,
  ffi.Pointer<ffi.Float> slope,
  ffi.Pointer<ffi.Uint8> features,
  ffi.Int32 rows,
  ffi.Int32 cols,
  ffi.Double cellSizeNS,
  ffi.Double cellSizeEW,
  ffi.Double minProminence,
  ffi.Int32 minFeatureCells,
  ffi.Pointer<ffi.Int32> outRows,
  ffi.Pointer<ffi.Int32> outCols,
  ffi.Pointer<ffi.Uint8> outTypes,
  ffi.Pointer<ffi.Float> outProminence,
  ffi.Pointer<ffi.Int32> outCount,
  ffi.Int32 maxCount,
);
typedef _SmartWaypointsDart = int Function(
  ffi.Pointer<ffi.Int16> dem,
  ffi.Pointer<ffi.Float> slope,
  ffi.Pointer<ffi.Uint8> features,
  int rows,
  int cols,
  double cellSizeNS,
  double cellSizeEW,
  double minProminence,
  int minFeatureCells,
  ffi.Pointer<ffi.Int32> outRows,
  ffi.Pointer<ffi.Int32> outCols,
  ffi.Pointer<ffi.Uint8> outTypes,
  ffi.Pointer<ffi.Float> outProminence,
  ffi.Pointer<ffi.Int32> outCount,
  int maxCount,
);

// זיהוי נקודות תורפה
typedef _VulnerabilitiesC = ffi.Int32 Function(
  ffi.Pointer<ffi.Int16> dem,
  ffi.Pointer<ffi.Float> slope,
  ffi.Int32 rows,
  ffi.Int32 cols,
  ffi.Double cellSizeNS,
  ffi.Double cellSizeEW,
  ffi.Double cliffThreshold,
  ffi.Double pitThreshold,
  ffi.Pointer<ffi.Int32> outRows,
  ffi.Pointer<ffi.Int32> outCols,
  ffi.Pointer<ffi.Uint8> outTypes,
  ffi.Pointer<ffi.Float> outSeverity,
  ffi.Pointer<ffi.Int32> outCount,
  ffi.Int32 maxCount,
);
typedef _VulnerabilitiesDart = int Function(
  ffi.Pointer<ffi.Int16> dem,
  ffi.Pointer<ffi.Float> slope,
  int rows,
  int cols,
  double cellSizeNS,
  double cellSizeEW,
  double cliffThreshold,
  double pitThreshold,
  ffi.Pointer<ffi.Int32> outRows,
  ffi.Pointer<ffi.Int32> outCols,
  ffi.Pointer<ffi.Uint8> outTypes,
  ffi.Pointer<ffi.Float> outSeverity,
  ffi.Pointer<ffi.Int32> outCount,
  int maxCount,
);

/// גשר FFI לספריית terrain_engine.dll
/// מטפל בהקצאת זיכרון, קריאות native ושחרור
class TerrainFFIBridge {
  static final TerrainFFIBridge _instance = TerrainFFIBridge._internal();
  factory TerrainFFIBridge() => _instance;

  bool _available = false;
  bool get isAvailable => _available;

  ffi.DynamicLibrary? _lib;

  // מצביעי פונקציות native — מאותחלים רק אם ה-DLL נטען בהצלחה
  late _SlopeAspectDart _computeSlopeAspect;
  late _ClassifyFeaturesDart _classifyFeatures;
  late _ViewshedDart _computeViewshed;
  late _HiddenPathDart _computeHiddenPath;
  late _SmartWaypointsDart _detectSmartWaypoints;
  late _VulnerabilitiesDart _detectVulnerabilities;

  TerrainFFIBridge._internal() {
    try {
      _lib = ffi.DynamicLibrary.open('terrain_engine.dll');
      _bindFunctions();
      _available = true;
      print('DEBUG TerrainFFIBridge: terrain_engine.dll נטען בהצלחה');
    } catch (e) {
      print('DEBUG TerrainFFIBridge: DLL לא נמצא: $e');
      _available = false;
    }
  }

  /// קישור כל הפונקציות מה-DLL
  void _bindFunctions() {
    _computeSlopeAspect = _lib!
        .lookupFunction<_SlopeAspectC, _SlopeAspectDart>('terrain_compute_slope_aspect');
    _classifyFeatures = _lib!
        .lookupFunction<_ClassifyFeaturesC, _ClassifyFeaturesDart>('terrain_classify_features');
    _computeViewshed =
        _lib!.lookupFunction<_ViewshedC, _ViewshedDart>('terrain_compute_viewshed');
    _computeHiddenPath =
        _lib!.lookupFunction<_HiddenPathC, _HiddenPathDart>('terrain_compute_hidden_path');
    _detectSmartWaypoints = _lib!
        .lookupFunction<_SmartWaypointsC, _SmartWaypointsDart>('terrain_detect_smart_waypoints');
    _detectVulnerabilities = _lib!
        .lookupFunction<_VulnerabilitiesC, _VulnerabilitiesDart>('terrain_detect_vulnerabilities');
  }

  // ---------------------------------------------------------------------------
  // עטיפות Dart — כל פונקציה מקצה זיכרון, קוראת ל-native ומשחררת
  // ---------------------------------------------------------------------------

  /// חישוב שיפוע ונטייה עבור רשת DEM
  ({Float32List slope, Float32List aspect})? computeSlopeAspect(
    Int16List dem,
    int rows,
    int cols,
    double cellSizeNS,
    double cellSizeEW,
  ) {
    if (!_available) return null;
    final n = rows * cols;

    // הקצאת זיכרון native לקלט ולפלט
    final pDem = calloc<ffi.Int16>(n);
    final pSlope = calloc<ffi.Float>(n);
    final pAspect = calloc<ffi.Float>(n);

    try {
      // העתקת DEM לזיכרון native
      for (int i = 0; i < n; i++) {
        pDem[i] = dem[i];
      }

      final result = _computeSlopeAspect(
          pDem, rows, cols, cellSizeNS, cellSizeEW, pSlope, pAspect);
      if (result != 0) return null;

      // העתקת תוצאות לזיכרון Dart
      final slope = Float32List(n);
      final aspect = Float32List(n);
      for (int i = 0; i < n; i++) {
        slope[i] = pSlope[i];
        aspect[i] = pAspect[i];
      }

      return (slope: slope, aspect: aspect);
    } finally {
      // שחרור כל הזיכרון שהוקצה
      calloc.free(pDem);
      calloc.free(pSlope);
      calloc.free(pAspect);
    }
  }

  /// סיווג תוואי שטח — דורש DEM, שיפוע ונטייה
  Uint8List? classifyFeatures(
    Int16List dem,
    Float32List slope,
    Float32List aspect,
    int rows,
    int cols,
    double cellSizeNS,
    double cellSizeEW,
  ) {
    if (!_available) return null;
    final n = rows * cols;

    // הקצאת זיכרון native
    final pDem = calloc<ffi.Int16>(n);
    final pSlope = calloc<ffi.Float>(n);
    final pAspect = calloc<ffi.Float>(n);
    final pFeatures = calloc<ffi.Uint8>(n);

    try {
      // העתקת קלט לזיכרון native
      for (int i = 0; i < n; i++) {
        pDem[i] = dem[i];
        pSlope[i] = slope[i];
        pAspect[i] = aspect[i];
      }

      final result = _classifyFeatures(
          pDem, pSlope, pAspect, rows, cols, cellSizeNS, cellSizeEW, pFeatures);
      if (result != 0) return null;

      // העתקת תוצאות לזיכרון Dart
      final features = Uint8List(n);
      for (int i = 0; i < n; i++) {
        features[i] = pFeatures[i];
      }

      return features;
    } finally {
      calloc.free(pDem);
      calloc.free(pSlope);
      calloc.free(pAspect);
      calloc.free(pFeatures);
    }
  }

  /// חישוב קו ראייה מנקודת תצפית
  Uint8List? computeViewshed(
    Int16List dem,
    int rows,
    int cols,
    double cellSizeNS,
    double cellSizeEW,
    int obsRow,
    int obsCol,
    double obsHeight,
    double maxDistCells,
  ) {
    if (!_available) return null;
    final n = rows * cols;

    // הקצאת זיכרון native
    final pDem = calloc<ffi.Int16>(n);
    final pVisible = calloc<ffi.Uint8>(n);

    try {
      // העתקת DEM לזיכרון native
      for (int i = 0; i < n; i++) {
        pDem[i] = dem[i];
      }

      final result = _computeViewshed(pDem, rows, cols, cellSizeNS, cellSizeEW,
          obsRow, obsCol, obsHeight, maxDistCells, pVisible);
      if (result != 0) return null;

      // העתקת תוצאות לזיכרון Dart
      final visible = Uint8List(n);
      for (int i = 0; i < n; i++) {
        visible[i] = pVisible[i];
      }

      return visible;
    } finally {
      calloc.free(pDem);
      calloc.free(pVisible);
    }
  }

  /// חישוב מסלול נסתר בין שתי נקודות — מנסה למנוע חשיפה לתצפית
  ({List<int> rows, List<int> cols, int length})? computeHiddenPath(
    Int16List dem,
    Uint8List viewshed,
    int rows,
    int cols,
    double cellSizeNS,
    double cellSizeEW,
    int startRow,
    int startCol,
    int endRow,
    int endCol,
    double exposureWeight,
  ) {
    if (!_available) return null;
    final n = rows * cols;
    // אורך מקסימלי למסלול
    const maxPathLength = 50000;

    // הקצאת זיכרון native — קלט
    final pDem = calloc<ffi.Int16>(n);
    final pViewshed = calloc<ffi.Uint8>(n);
    // הקצאת זיכרון native — פלט
    final pPathRows = calloc<ffi.Int32>(maxPathLength);
    final pPathCols = calloc<ffi.Int32>(maxPathLength);
    final pPathLength = calloc<ffi.Int32>(1);

    try {
      // העתקת קלט לזיכרון native
      for (int i = 0; i < n; i++) {
        pDem[i] = dem[i];
        pViewshed[i] = viewshed[i];
      }

      final result = _computeHiddenPath(
        pDem,
        pViewshed,
        rows,
        cols,
        cellSizeNS,
        cellSizeEW,
        startRow,
        startCol,
        endRow,
        endCol,
        exposureWeight,
        pPathRows,
        pPathCols,
        pPathLength,
        maxPathLength,
      );
      if (result != 0) return null;

      final pathLength = pPathLength[0];
      if (pathLength <= 0) return null;

      // העתקת נתוני המסלול לזיכרון Dart
      final outRows = List<int>.generate(pathLength, (i) => pPathRows[i]);
      final outCols = List<int>.generate(pathLength, (i) => pPathCols[i]);

      return (rows: outRows, cols: outCols, length: pathLength);
    } finally {
      calloc.free(pDem);
      calloc.free(pViewshed);
      calloc.free(pPathRows);
      calloc.free(pPathCols);
      calloc.free(pPathLength);
    }
  }

  /// זיהוי נקודות ציון חכמות — כיפות, פסגות, צמתים ועוד
  ({List<int> rows, List<int> cols, Uint8List types, Float32List prominence, int count})?
      detectSmartWaypoints(
    Int16List dem,
    Float32List slope,
    Uint8List features,
    int rows,
    int cols,
    double cellSizeNS,
    double cellSizeEW,
    double minProminence,
    int minFeatureCells,
  ) {
    if (!_available) return null;
    final n = rows * cols;
    // מספר מקסימלי של נקודות ציון
    const maxCount = 10000;

    // הקצאת זיכרון native — קלט
    final pDem = calloc<ffi.Int16>(n);
    final pSlope = calloc<ffi.Float>(n);
    final pFeatures = calloc<ffi.Uint8>(n);
    // הקצאת זיכרון native — פלט
    final pOutRows = calloc<ffi.Int32>(maxCount);
    final pOutCols = calloc<ffi.Int32>(maxCount);
    final pOutTypes = calloc<ffi.Uint8>(maxCount);
    final pOutProminence = calloc<ffi.Float>(maxCount);
    final pOutCount = calloc<ffi.Int32>(1);

    try {
      // העתקת קלט לזיכרון native
      for (int i = 0; i < n; i++) {
        pDem[i] = dem[i];
        pSlope[i] = slope[i];
        pFeatures[i] = features[i];
      }

      final result = _detectSmartWaypoints(
        pDem,
        pSlope,
        pFeatures,
        rows,
        cols,
        cellSizeNS,
        cellSizeEW,
        minProminence,
        minFeatureCells,
        pOutRows,
        pOutCols,
        pOutTypes,
        pOutProminence,
        pOutCount,
        maxCount,
      );
      if (result != 0) return null;

      final count = pOutCount[0];
      if (count <= 0) return (rows: <int>[], cols: <int>[], types: Uint8List(0), prominence: Float32List(0), count: 0);

      // העתקת תוצאות לזיכרון Dart
      final outRows = List<int>.generate(count, (i) => pOutRows[i]);
      final outCols = List<int>.generate(count, (i) => pOutCols[i]);
      final outTypes = Uint8List(count);
      final outProminence = Float32List(count);
      for (int i = 0; i < count; i++) {
        outTypes[i] = pOutTypes[i];
        outProminence[i] = pOutProminence[i];
      }

      return (
        rows: outRows,
        cols: outCols,
        types: outTypes,
        prominence: outProminence,
        count: count,
      );
    } finally {
      calloc.free(pDem);
      calloc.free(pSlope);
      calloc.free(pFeatures);
      calloc.free(pOutRows);
      calloc.free(pOutCols);
      calloc.free(pOutTypes);
      calloc.free(pOutProminence);
      calloc.free(pOutCount);
    }
  }

  /// זיהוי נקודות תורפה — מצוקים, בורות, מדרונות תלולים
  ({List<int> rows, List<int> cols, Uint8List types, Float32List severity, int count})?
      detectVulnerabilities(
    Int16List dem,
    Float32List slope,
    int rows,
    int cols,
    double cellSizeNS,
    double cellSizeEW,
    double cliffThreshold,
    double pitThreshold,
  ) {
    if (!_available) return null;
    final n = rows * cols;
    // מספר מקסימלי של נקודות תורפה
    const maxCount = 10000;

    // הקצאת זיכרון native — קלט
    final pDem = calloc<ffi.Int16>(n);
    final pSlope = calloc<ffi.Float>(n);
    // הקצאת זיכרון native — פלט
    final pOutRows = calloc<ffi.Int32>(maxCount);
    final pOutCols = calloc<ffi.Int32>(maxCount);
    final pOutTypes = calloc<ffi.Uint8>(maxCount);
    final pOutSeverity = calloc<ffi.Float>(maxCount);
    final pOutCount = calloc<ffi.Int32>(1);

    try {
      // העתקת קלט לזיכרון native
      for (int i = 0; i < n; i++) {
        pDem[i] = dem[i];
        pSlope[i] = slope[i];
      }

      final result = _detectVulnerabilities(
        pDem,
        pSlope,
        rows,
        cols,
        cellSizeNS,
        cellSizeEW,
        cliffThreshold,
        pitThreshold,
        pOutRows,
        pOutCols,
        pOutTypes,
        pOutSeverity,
        pOutCount,
        maxCount,
      );
      if (result != 0) return null;

      final count = pOutCount[0];
      if (count <= 0) return (rows: <int>[], cols: <int>[], types: Uint8List(0), severity: Float32List(0), count: 0);

      // העתקת תוצאות לזיכרון Dart
      final outRows = List<int>.generate(count, (i) => pOutRows[i]);
      final outCols = List<int>.generate(count, (i) => pOutCols[i]);
      final outTypes = Uint8List(count);
      final outSeverity = Float32List(count);
      for (int i = 0; i < count; i++) {
        outTypes[i] = pOutTypes[i];
        outSeverity[i] = pOutSeverity[i];
      }

      return (
        rows: outRows,
        cols: outCols,
        types: outTypes,
        severity: outSeverity,
        count: count,
      );
    } finally {
      calloc.free(pDem);
      calloc.free(pSlope);
      calloc.free(pOutRows);
      calloc.free(pOutCols);
      calloc.free(pOutTypes);
      calloc.free(pOutSeverity);
      calloc.free(pOutCount);
    }
  }
}
