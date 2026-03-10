import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'terrain_models.dart';

/// שירות מטמון לתוצאות ניתוח שטח
/// שומר רשתות בינאריות + מטא-דאטה ב-JSON לדיסק
class TerrainCacheService {
  late Directory _cacheDir;
  bool _initialized = false;

  /// אתחול — יוצר את תיקיית המטמון אם לא קיימת
  Future<void> initialize() async {
    if (_initialized) return;
    final docsDir = await getApplicationDocumentsDirectory();
    _cacheDir = Directory('${docsDir.path}/terrain_cache');
    if (!await _cacheDir.exists()) {
      await _cacheDir.create(recursive: true);
    }
    _initialized = true;
  }

  // ---------------------------------------------------------------------------
  // שיפוע ונטייה
  // ---------------------------------------------------------------------------

  /// שמירת תוצאת שיפוע/נטייה — שני קבצים בינאריים + JSON מטא-דאטה
  Future<void> saveSlopeAspect(String tileName, SlopeAspectResult result) async {
    if (!_initialized) return;
    try {
      final slopeFile = File('${_cacheDir.path}/${tileName}_slope.bin');
      final aspectFile = File('${_cacheDir.path}/${tileName}_aspect.bin');
      final metaFile = File('${_cacheDir.path}/${tileName}_slope_meta.json');

      // כתיבת נתונים בינאריים — Float32 גולמי
      await slopeFile.writeAsBytes(result.slopeGrid.buffer.asUint8List());
      await aspectFile.writeAsBytes(result.aspectGrid.buffer.asUint8List());

      // כתיבת מטא-דאטה
      final meta = {
        'rows': result.rows,
        'cols': result.cols,
        'south': result.bounds.south,
        'west': result.bounds.west,
        'north': result.bounds.north,
        'east': result.bounds.east,
      };
      await metaFile.writeAsString(jsonEncode(meta));
    } catch (e) {
      print('DEBUG TerrainCacheService: שגיאה בשמירת שיפוע/נטייה: $e');
    }
  }

  /// טעינת תוצאת שיפוע/נטייה מהמטמון
  Future<SlopeAspectResult?> loadSlopeAspect(String tileName) async {
    if (!_initialized) return null;
    try {
      final slopeFile = File('${_cacheDir.path}/${tileName}_slope.bin');
      final aspectFile = File('${_cacheDir.path}/${tileName}_aspect.bin');
      final metaFile = File('${_cacheDir.path}/${tileName}_slope_meta.json');

      // בדיקה שכל הקבצים קיימים
      if (!await slopeFile.exists() ||
          !await aspectFile.exists() ||
          !await metaFile.exists()) {
        return null;
      }

      // קריאת מטא-דאטה
      final metaJson = jsonDecode(await metaFile.readAsString());
      final rows = metaJson['rows'] as int;
      final cols = metaJson['cols'] as int;

      // קריאת נתונים בינאריים
      final slopeBytes = await slopeFile.readAsBytes();
      final aspectBytes = await aspectFile.readAsBytes();

      // בנייה מחדש של Float32List מהבתים הגולמיים
      final slopeGrid =
          Float32List.view(Uint8List.fromList(slopeBytes).buffer);
      final aspectGrid =
          Float32List.view(Uint8List.fromList(aspectBytes).buffer);

      final bounds = LatLngBounds(
        LatLng(metaJson['south'] as double, metaJson['west'] as double),
        LatLng(metaJson['north'] as double, metaJson['east'] as double),
      );

      return SlopeAspectResult(
        slopeGrid: slopeGrid,
        aspectGrid: aspectGrid,
        rows: rows,
        cols: cols,
        bounds: bounds,
      );
    } catch (e) {
      print('DEBUG TerrainCacheService: שגיאה בטעינת שיפוע/נטייה: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // סיווג תוואי שטח
  // ---------------------------------------------------------------------------

  /// שמירת תוצאת סיווג תוואי — קובץ בינארי + JSON מטא-דאטה
  Future<void> saveFeatures(
      String tileName, TerrainFeaturesResult result) async {
    if (!_initialized) return;
    try {
      final featuresFile =
          File('${_cacheDir.path}/${tileName}_features.bin');
      final metaFile =
          File('${_cacheDir.path}/${tileName}_features_meta.json');

      // כתיבת נתונים בינאריים — Uint8 גולמי
      await featuresFile.writeAsBytes(result.featureGrid);

      // כתיבת מטא-דאטה
      final meta = {
        'rows': result.rows,
        'cols': result.cols,
        'south': result.bounds.south,
        'west': result.bounds.west,
        'north': result.bounds.north,
        'east': result.bounds.east,
      };
      await metaFile.writeAsString(jsonEncode(meta));
    } catch (e) {
      print('DEBUG TerrainCacheService: שגיאה בשמירת תוואי: $e');
    }
  }

  /// טעינת תוצאת סיווג תוואי מהמטמון
  Future<TerrainFeaturesResult?> loadFeatures(String tileName) async {
    if (!_initialized) return null;
    try {
      final featuresFile =
          File('${_cacheDir.path}/${tileName}_features.bin');
      final metaFile =
          File('${_cacheDir.path}/${tileName}_features_meta.json');

      if (!await featuresFile.exists() || !await metaFile.exists()) {
        return null;
      }

      final metaJson = jsonDecode(await metaFile.readAsString());
      final rows = metaJson['rows'] as int;
      final cols = metaJson['cols'] as int;

      final featureGrid = Uint8List.fromList(await featuresFile.readAsBytes());

      final bounds = LatLngBounds(
        LatLng(metaJson['south'] as double, metaJson['west'] as double),
        LatLng(metaJson['north'] as double, metaJson['east'] as double),
      );

      return TerrainFeaturesResult(
        featureGrid: featureGrid,
        rows: rows,
        cols: cols,
        bounds: bounds,
      );
    } catch (e) {
      print('DEBUG TerrainCacheService: שגיאה בטעינת תוואי: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // קו ראייה (viewshed)
  // ---------------------------------------------------------------------------

  /// שמירת תוצאת קו ראייה — המפתח כולל מיקום הצופה
  Future<void> saveViewshed(String key, ViewshedResult result) async {
    if (!_initialized) return;
    try {
      final visFile = File('${_cacheDir.path}/${key}_viewshed.bin');
      final metaFile = File('${_cacheDir.path}/${key}_viewshed_meta.json');

      // כתיבת נתונים בינאריים — Uint8 גולמי
      await visFile.writeAsBytes(result.visibleGrid);

      // כתיבת מטא-דאטה — כולל מיקום וגובה הצופה
      final meta = {
        'rows': result.rows,
        'cols': result.cols,
        'south': result.bounds.south,
        'west': result.bounds.west,
        'north': result.bounds.north,
        'east': result.bounds.east,
        'observerLat': result.observerPosition.latitude,
        'observerLng': result.observerPosition.longitude,
        'observerHeight': result.observerHeight,
      };
      await metaFile.writeAsString(jsonEncode(meta));
    } catch (e) {
      print('DEBUG TerrainCacheService: שגיאה בשמירת קו ראייה: $e');
    }
  }

  /// טעינת תוצאת קו ראייה מהמטמון
  Future<ViewshedResult?> loadViewshed(String key) async {
    if (!_initialized) return null;
    try {
      final visFile = File('${_cacheDir.path}/${key}_viewshed.bin');
      final metaFile = File('${_cacheDir.path}/${key}_viewshed_meta.json');

      if (!await visFile.exists() || !await metaFile.exists()) {
        return null;
      }

      final metaJson = jsonDecode(await metaFile.readAsString());
      final rows = metaJson['rows'] as int;
      final cols = metaJson['cols'] as int;

      final visibleGrid = Uint8List.fromList(await visFile.readAsBytes());

      final bounds = LatLngBounds(
        LatLng(metaJson['south'] as double, metaJson['west'] as double),
        LatLng(metaJson['north'] as double, metaJson['east'] as double),
      );

      final observerPosition = LatLng(
        metaJson['observerLat'] as double,
        metaJson['observerLng'] as double,
      );

      return ViewshedResult(
        visibleGrid: visibleGrid,
        rows: rows,
        cols: cols,
        bounds: bounds,
        observerPosition: observerPosition,
        observerHeight: metaJson['observerHeight'] as double,
      );
    } catch (e) {
      print('DEBUG TerrainCacheService: שגיאה בטעינת קו ראייה: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // ניהול מטמון
  // ---------------------------------------------------------------------------

  /// מחיקת מטמון של אריח ספציפי — כל הקבצים הקשורים
  Future<void> clearTileCache(String tileName) async {
    if (!_initialized) return;
    try {
      final dir = _cacheDir;
      final entities = await dir.list().toList();
      for (final entity in entities) {
        if (entity is File) {
          final fileName = entity.uri.pathSegments.last;
          // מחיקת כל קובץ שמתחיל בשם האריח
          if (fileName.startsWith(tileName)) {
            await entity.delete();
          }
        }
      }
    } catch (e) {
      print('DEBUG TerrainCacheService: שגיאה במחיקת מטמון אריח: $e');
    }
  }

  /// מחיקת כל המטמון
  Future<void> clearAll() async {
    if (!_initialized) return;
    try {
      if (await _cacheDir.exists()) {
        await _cacheDir.delete(recursive: true);
        await _cacheDir.create(recursive: true);
      }
    } catch (e) {
      print('DEBUG TerrainCacheService: שגיאה במחיקת כל המטמון: $e');
    }
  }

  /// סטטיסטיקת מטמון — מספר קבצים וגודל כולל ב-MB
  Future<({int fileCount, double sizeMB})> getCacheStats() async {
    if (!_initialized) return (fileCount: 0, sizeMB: 0.0);
    try {
      int fileCount = 0;
      int totalBytes = 0;

      final entities = await _cacheDir.list().toList();
      for (final entity in entities) {
        if (entity is File) {
          fileCount++;
          totalBytes += await entity.length();
        }
      }

      final sizeMB = totalBytes / (1024.0 * 1024.0);
      return (fileCount: fileCount, sizeMB: sizeMB);
    } catch (e) {
      print('DEBUG TerrainCacheService: שגיאה בחישוב סטטיסטיקה: $e');
      return (fileCount: 0, sizeMB: 0.0);
    }
  }
}
