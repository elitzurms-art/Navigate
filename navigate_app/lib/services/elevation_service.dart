import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// שירות גובה אופליין — קורא קבצי SRTM3 (.hgt).
/// ישראל מוטמעת ב-assets (10 קבצים, ~28MB).
/// אזורים נוספים (חו"ל) ניתנים להורדה מ-AWS S3.
/// Singleton — נטען פעם אחת, שומר cache בזיכרון.
class ElevationService {
  static final ElevationService _instance = ElevationService._internal();
  factory ElevationService() => _instance;
  ElevationService._internal();

  bool _initialized = false;
  late Directory _downloadDir;

  /// cache בזיכרון — שם קובץ → נתוני גובה (1201×1201 signed int16)
  final Map<String, Int16List> _tileCache = {};

  static const int _gridSize = 1201; // SRTM3: 1201×1201
  static const int _fileSize = _gridSize * _gridSize * 2; // 2,884,802 bytes
  static const int _noData = -32768;

  /// קבצי ישראל המוטמעים ב-assets
  static const List<String> _bundledTiles = [
    'N29E034', 'N29E035',
    'N30E034', 'N30E035',
    'N31E034', 'N31E035',
    'N32E034', 'N32E035',
    'N33E034', 'N33E035',
  ];

  /// אתחול — יוצר תיקיית הורדות לחו"ל
  Future<void> initialize() async {
    if (_initialized) return;
    final docsDir = await getApplicationDocumentsDirectory();
    _downloadDir = Directory('${docsDir.path}/elevation');
    if (!await _downloadDir.exists()) {
      await _downloadDir.create(recursive: true);
    }
    _initialized = true;
    print('DEBUG ElevationService: initialized (${_bundledTiles.length} bundled + downloads at ${_downloadDir.path})');
  }

  /// בדיקה מהירה — האם יש נתונים עבור הקואורדינטה
  bool hasDataFor(double lat, double lng) {
    final name = _tileName(lat, lng);
    if (_tileCache.containsKey(name)) return true;
    if (_bundledTiles.contains(name)) return true;
    final file = File('${_downloadDir.path}/$name.hgt');
    return file.existsSync();
  }

  /// גובה בנקודה — מחזיר מטרים (או null אם אין נתונים)
  Future<int?> getElevation(double lat, double lng) async {
    if (!_initialized) return null;

    final name = _tileName(lat, lng);
    final data = await _loadTile(name);
    if (data == null) return null;

    // חישוב row/col עם אינטרפולציה בילינארית
    final latFloor = lat.floor().toDouble();
    final lngFloor = lng.floor().toDouble();

    final rowExact = ((latFloor + 1) - lat) * 1200;
    final colExact = (lng - lngFloor) * 1200;

    final row = rowExact.floor();
    final col = colExact.floor();

    // 4 נקודות סביב
    final h00 = _readHeight(data, row, col);
    final h01 = _readHeight(data, row, col + 1);
    final h10 = _readHeight(data, row + 1, col);
    final h11 = _readHeight(data, row + 1, col + 1);

    if (h00 == _noData || h01 == _noData || h10 == _noData || h11 == _noData) {
      if (h00 != _noData) return h00;
      if (h01 != _noData) return h01;
      if (h10 != _noData) return h10;
      if (h11 != _noData) return h11;
      return null;
    }

    // אינטרפולציה בילינארית
    final fracRow = rowExact - row;
    final fracCol = colExact - col;
    final elevation = h00 * (1 - fracRow) * (1 - fracCol) +
        h01 * (1 - fracRow) * fracCol +
        h10 * fracRow * (1 - fracCol) +
        h11 * fracRow * fracCol;

    return elevation.round();
  }

  // ──────────────── הורדה (חו"ל בלבד) ────────────────

  /// הורדת קובץ בודד מ-AWS — Stream עם progress (0.0 – 1.0), שלילי = שגיאה
  Stream<double> downloadTile(int lat, int lng) async* {
    final name = _tileNameFromInts(lat, lng);

    // אם מוטמע — לא צריך להוריד
    if (_bundledTiles.contains(name)) {
      yield 1.0;
      return;
    }

    final outFile = File('${_downloadDir.path}/$name.hgt');
    if (await outFile.exists() && await outFile.length() == _fileSize) {
      yield 1.0;
      return;
    }

    final url = _tileUrl(lat, lng);
    print('DEBUG ElevationService: downloading $url');
    final request = http.Request('GET', Uri.parse(url));
    final response = await http.Client().send(request);

    if (response.statusCode != 200) {
      print('DEBUG ElevationService: HTTP ${response.statusCode} for $url');
      yield -1.0;
      return;
    }

    final contentLength = response.contentLength ?? 0;
    final chunks = <int>[];
    int received = 0;

    await for (final chunk in response.stream) {
      chunks.addAll(chunk);
      received += chunk.length;
      if (contentLength > 0) {
        yield received / contentLength * 0.9;
      }
    }

    // הנתונים מ-AWS הם SRTM1 (3601×3601) ב-gzip — צריך לפרוס ולדגום ל-SRTM3
    try {
      final gzData = Uint8List.fromList(chunks);
      final decoded = GZipDecoder().decodeBytes(gzData);

      const srtm1Size = 3601;
      const srtm1FileSize = srtm1Size * srtm1Size * 2;

      if (decoded.length == _fileSize) {
        // כבר SRTM3 — שומר ישירות
        await outFile.writeAsBytes(decoded);
      } else if (decoded.length == srtm1FileSize) {
        // SRTM1 — דגימה ל-SRTM3 (כל נקודה שלישית)
        final out = Uint8List(_fileSize);
        for (int r = 0; r < _gridSize; r++) {
          for (int c = 0; c < _gridSize; c++) {
            final srcIdx = (r * 3 * srtm1Size + c * 3) * 2;
            final dstIdx = (r * _gridSize + c) * 2;
            out[dstIdx] = decoded[srcIdx];
            out[dstIdx + 1] = decoded[srcIdx + 1];
          }
        }
        await outFile.writeAsBytes(out);
      } else {
        print('DEBUG ElevationService: unexpected size ${decoded.length} for $name');
        yield -1.0;
        return;
      }

      _tileCache.remove(name);
      yield 1.0;
    } catch (e) {
      print('DEBUG ElevationService: decompress error: $e');
      yield -1.0;
    }
  }

  /// הורדת כל הקבצים לאזור — Stream עם (done, total)
  Stream<({int done, int total})> downloadRegion(
    double minLat, double minLng, double maxLat, double maxLng,
  ) async* {
    final tiles = _tilesForRegion(minLat, minLng, maxLat, maxLng);
    // סינון: רק קבצים שלא מוטמעים ולא כבר קיימים
    final needed = tiles.where((t) {
      final name = _tileNameFromInts(t.$1, t.$2);
      if (_bundledTiles.contains(name)) return false;
      final file = File('${_downloadDir.path}/$name.hgt');
      return !file.existsSync();
    }).toList();

    final total = needed.length;
    int done = 0;

    yield (done: 0, total: total);

    for (final tile in needed) {
      await for (final progress in downloadTile(tile.$1, tile.$2)) {
        if (progress < 0) break;
      }
      done++;
      yield (done: done, total: total);
    }
  }

  /// סטטיסטיקות קבצים שהורדו (לא כולל bundled)
  Future<({int tileCount, double sizeMB})> getDownloadedStats() async {
    if (!_initialized) return (tileCount: 0, sizeMB: 0.0);
    try {
      final files = _downloadDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.hgt'))
          .toList();
      int totalBytes = 0;
      for (final f in files) {
        totalBytes += await f.length();
      }
      return (tileCount: files.length, sizeMB: totalBytes / (1024 * 1024));
    } catch (e) {
      return (tileCount: 0, sizeMB: 0.0);
    }
  }

  /// מחיקת קבצים שהורדו (לא משפיע על bundled)
  Future<void> clearDownloaded() async {
    if (!_initialized) return;
    try {
      final files = _downloadDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.hgt'));
      for (final f in files) {
        final name = f.uri.pathSegments.last.replaceAll('.hgt', '');
        _tileCache.remove(name);
        await f.delete();
      }
      print('DEBUG ElevationService: downloaded tiles cleared');
    } catch (e) {
      print('DEBUG ElevationService: clearDownloaded error: $e');
    }
  }

  /// חישוב מספר קבצים נדרשים לאזור (לא כולל bundled)
  int countDownloadableTiles(
    double minLat, double minLng, double maxLat, double maxLng,
  ) {
    return _tilesForRegion(minLat, minLng, maxLat, maxLng)
        .where((t) => !_bundledTiles.contains(_tileNameFromInts(t.$1, t.$2)))
        .length;
  }

  // ──────────────── helpers ────────────────

  String _tileName(double lat, double lng) {
    return _tileNameFromInts(lat.floor(), lng.floor());
  }

  String _tileNameFromInts(int lat, int lng) {
    final ns = lat >= 0 ? 'N' : 'S';
    final ew = lng >= 0 ? 'E' : 'W';
    final latAbs = lat.abs().toString().padLeft(2, '0');
    final lngAbs = lng.abs().toString().padLeft(3, '0');
    return '$ns$latAbs$ew$lngAbs';
  }

  String _tileUrl(int lat, int lng) {
    final name = _tileNameFromInts(lat, lng);
    final ns = lat >= 0 ? 'N' : 'S';
    final latAbs = lat.abs().toString().padLeft(2, '0');
    return 'https://elevation-tiles-prod.s3.amazonaws.com/skadi/$ns$latAbs/$name.hgt.gz';
  }

  List<(int, int)> _tilesForRegion(
    double minLat, double minLng, double maxLat, double maxLng,
  ) {
    final tiles = <(int, int)>[];
    for (int lat = minLat.floor(); lat <= maxLat.floor(); lat++) {
      for (int lng = minLng.floor(); lng <= maxLng.floor(); lng++) {
        tiles.add((lat, lng));
      }
    }
    return tiles;
  }

  /// טעינת tile — קודם cache, אח"כ bundled asset, אח"כ קובץ שהורד
  Future<Int16List?> _loadTile(String name) async {
    if (_tileCache.containsKey(name)) return _tileCache[name]!;

    Uint8List? bytes;

    // 1. ניסיון מ-bundled assets
    if (_bundledTiles.contains(name)) {
      try {
        final byteData = await rootBundle.load('assets/elevation/$name.hgt');
        bytes = byteData.buffer.asUint8List();
      } catch (_) {}
    }

    // 2. ניסיון מקובץ שהורד
    if (bytes == null) {
      final file = File('${_downloadDir.path}/$name.hgt');
      if (await file.exists()) {
        bytes = await file.readAsBytes();
      }
    }

    if (bytes == null || bytes.length != _fileSize) return null;

    try {
      // המרה מ-big-endian signed int16
      final data = Int16List(_gridSize * _gridSize);
      for (int i = 0; i < data.length; i++) {
        final hi = bytes[i * 2];
        final lo = bytes[i * 2 + 1];
        int value = (hi << 8) | lo;
        if (value >= 32768) value -= 65536;
        data[i] = value;
      }

      _tileCache[name] = data;
      return data;
    } catch (e) {
      print('DEBUG ElevationService: load error for $name: $e');
      return null;
    }
  }

  int _readHeight(Int16List data, int row, int col) {
    if (row < 0 || row >= _gridSize || col < 0 || col >= _gridSize) {
      return _noData;
    }
    return data[row * _gridSize + col];
  }
}
