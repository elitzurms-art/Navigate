import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:latlong2/latlong.dart';
import '../core/utils/utm_converter.dart';
import '../core/utils/geometry_utils.dart';
import '../core/utils/file_export_helper.dart';
import '../domain/entities/coordinate.dart';
import '../domain/entities/checkpoint.dart';
import '../domain/entities/boundary.dart';

/// פורמט קואורדינטות שזוהה
enum CoordinateFormat { utm12, utm6plus6, geographic, unknown }

/// שורה מנותחת מקובץ ייבוא
class ParsedCheckpointRow {
  final int rowIndex;
  int sequenceNumber;
  final Coordinate coordinate;
  final String description;
  final String detectedType;
  bool hasConflict;
  Checkpoint? conflictingCheckpoint;

  ParsedCheckpointRow({
    required this.rowIndex,
    required this.sequenceNumber,
    required this.coordinate,
    required this.description,
    required this.detectedType,
    this.hasConflict = false,
    this.conflictingCheckpoint,
  });
}

/// תוצאת ניתוח קובץ
class CheckpointImportResult {
  final List<ParsedCheckpointRow> parsedRows;
  final List<String> errors;
  final List<String> warnings;
  final CoordinateFormat detectedFormat;
  final int columnCount;

  CheckpointImportResult({
    required this.parsedRows,
    required this.errors,
    required this.warnings,
    required this.detectedFormat,
    required this.columnCount,
  });

  bool get hasErrors => errors.isNotEmpty;
  bool get isSuccess => !hasErrors && parsedRows.isNotEmpty;
}

/// תוצאת בדיקת גבול לנקודה בודדת
class BoundaryCheckResult {
  final int rowIndex;
  final int sequenceNumber;
  final bool isInside;
  final double? distanceMeters;

  BoundaryCheckResult({
    required this.rowIndex,
    required this.sequenceNumber,
    required this.isInside,
    this.distanceMeters,
  });
}

/// אופן טיפול בהתנגשות מספר סידורי
enum ConflictResolution { replaceExisting, renumberExisting, renumberNew }

/// שירות ייבוא נקודות ציון מקובץ CSV/XLSX
class CheckpointImportService {
  // ──────── נקודת כניסה ────────

  /// ניתוח קובץ — מזהה פורמט, מנתח שורות, מחזיר תוצאה
  static CheckpointImportResult parseFile(String filePath, Uint8List fileBytes, {String? sheetName}) {
    final ext = filePath.split('.').last.toLowerCase();
    List<List<dynamic>> rows;

    if (ext == 'csv') {
      rows = _parseCsv(fileBytes);
    } else if (ext == 'xlsx' || ext == 'xls') {
      rows = _parseXlsx(fileBytes, sheetName: sheetName);
    } else {
      return CheckpointImportResult(
        parsedRows: [],
        errors: ['פורמט קובץ לא נתמך: .$ext — יש להשתמש ב-CSV או XLSX'],
        warnings: [],
        detectedFormat: CoordinateFormat.unknown,
        columnCount: 0,
      );
    }

    if (rows.isEmpty) {
      return CheckpointImportResult(
        parsedRows: [],
        errors: ['הקובץ ריק — לא נמצאו שורות נתונים'],
        warnings: [],
        detectedFormat: CoordinateFormat.unknown,
        columnCount: 0,
      );
    }

    return _parseRows(rows);
  }

  // ──────── CSV ────────

  static List<List<dynamic>> _parseCsv(Uint8List bytes) {
    // הסרת BOM אם קיים
    var content = utf8.decode(bytes, allowMalformed: true);
    if (content.startsWith('\uFEFF')) {
      content = content.substring(1);
    }

    // זיהוי אוטומטי של מפריד: tab, נקודה-פסיק, או פסיק
    final firstDataLine = content.split('\n').firstWhere(
        (l) => l.trim().isNotEmpty, orElse: () => '');
    String delimiter = ',';
    if (firstDataLine.contains('\t')) {
      delimiter = '\t';
    } else if (firstDataLine.contains(';')) {
      delimiter = ';';
    }

    return CsvToListConverter(fieldDelimiter: delimiter).convert(content);
  }

  // ──────── XLSX ────────

  /// מחזיר רשימת שמות גיליונות בקובץ XLSX
  static List<String> getSheetNames(Uint8List fileBytes) {
    final excel = Excel.decodeBytes(fileBytes);
    return excel.tables.keys.toList();
  }

  static List<List<dynamic>> _parseXlsx(Uint8List bytes, {String? sheetName}) {
    final excel = Excel.decodeBytes(bytes);
    final sheet = sheetName != null
        ? excel.tables[sheetName]
        : excel.tables[excel.tables.keys.first];
    if (sheet == null) return [];

    final rows = <List<dynamic>>[];
    for (final row in sheet.rows) {
      final cells = row.map((cell) => cell?.value ?? '').toList();
      // דילוג על שורות ריקות לחלוטין
      if (cells.every((c) => c.toString().trim().isEmpty)) continue;
      rows.add(cells);
    }
    return rows;
  }

  // ──────── ניתוח שורות ────────

  static CheckpointImportResult _parseRows(List<List<dynamic>> rawRows) {
    final errors = <String>[];
    final warnings = <String>[];
    final parsedRows = <ParsedCheckpointRow>[];

    // דילוג על שורת כותרת אם התא הראשון אינו מספרי
    int startIndex = 0;
    if (rawRows.isNotEmpty) {
      final firstCell = rawRows[0][0].toString().trim();
      if (int.tryParse(firstCell) == null) {
        startIndex = 1;
      }
    }

    if (startIndex >= rawRows.length) {
      return CheckpointImportResult(
        parsedRows: [],
        errors: ['הקובץ מכיל רק שורת כותרת — לא נמצאו נתונים'],
        warnings: [],
        detectedFormat: CoordinateFormat.unknown,
        columnCount: 0,
      );
    }

    final dataRows = rawRows.sublist(startIndex);
    final columnCount = _detectColumnCount(dataRows);
    final format = _detectFormat(dataRows, columnCount);

    if (format == CoordinateFormat.unknown) {
      return CheckpointImportResult(
        parsedRows: [],
        errors: ['לא ניתן לזהות את פורמט הקואורדינטות — ודא שהקובץ בפורמט UTM או גאוגרפי'],
        warnings: [],
        detectedFormat: format,
        columnCount: columnCount,
      );
    }

    final seenSequenceNumbers = <int>{};

    for (int i = 0; i < dataRows.length; i++) {
      final row = dataRows[i];
      final displayRow = i + startIndex + 1; // מספר שורה לתצוגה (1-based)

      try {
        // מספר סידורי
        final seqStr = row[0].toString().trim();
        final seq = int.tryParse(seqStr);
        if (seq == null) {
          warnings.add('שורה $displayRow: מספר סידורי לא תקין "$seqStr" — דילוג');
          continue;
        }

        // בדיקת כפילויות בתוך הקובץ
        if (seenSequenceNumbers.contains(seq)) {
          warnings.add('שורה $displayRow: מספר סידורי $seq כפול בקובץ — דילוג');
          continue;
        }
        seenSequenceNumbers.add(seq);

        // קואורדינטה
        Coordinate? coordinate;
        try {
          coordinate = _parseCoordinate(row, columnCount, format);
        } catch (e) {
          warnings.add('שורה $displayRow: שגיאה בפענוח קואורדינטה — $e');
          continue;
        }

        if (coordinate == null) {
          warnings.add('שורה $displayRow: קואורדינטה ריקה — דילוג');
          continue;
        }

        // תיאור (עמודה אחרונה)
        final descIndex = columnCount - 1;
        final description = descIndex < row.length
            ? row[descIndex].toString().trim()
            : '';

        // סיווג סוג נקודה
        final type = _classifyType(description);

        parsedRows.add(ParsedCheckpointRow(
          rowIndex: i,
          sequenceNumber: seq,
          coordinate: coordinate,
          description: description,
          detectedType: type,
        ));
      } catch (e) {
        warnings.add('שורה $displayRow: שגיאה כללית — $e');
      }
    }

    if (parsedRows.isEmpty && errors.isEmpty) {
      errors.add('לא נמצאו שורות תקינות לייבוא');
    }

    return CheckpointImportResult(
      parsedRows: parsedRows,
      errors: errors,
      warnings: warnings,
      detectedFormat: format,
      columnCount: columnCount,
    );
  }

  // ──────── זיהוי מספר עמודות ────────

  /// מזהה 3 או 4 עמודות — בודק עקביות בין 5 השורות הראשונות
  static int _detectColumnCount(List<List<dynamic>> dataRows) {
    final sampleSize = dataRows.length < 5 ? dataRows.length : 5;
    int maxNonEmpty = 0;

    for (int i = 0; i < sampleSize; i++) {
      final row = dataRows[i];
      int nonEmpty = 0;
      for (final cell in row) {
        if (cell.toString().trim().isNotEmpty) nonEmpty++;
      }
      if (nonEmpty > maxNonEmpty) maxNonEmpty = nonEmpty;
    }

    // 4 עמודות: מס"ד | מזרח | צפון | תיאור
    // 3 עמודות: מס"ד | UTM12/lat,lng | תיאור
    return maxNonEmpty >= 4 ? 4 : 3;
  }

  // ──────── זיהוי פורמט ────────

  static CoordinateFormat _detectFormat(List<List<dynamic>> dataRows, int columnCount) {
    final sampleSize = dataRows.length < 5 ? dataRows.length : 5;

    if (columnCount == 3) {
      // עמודה 1 — UTM 12 ספרות, או lat,lng
      int utm12Count = 0;
      int geoCount = 0;

      for (int i = 0; i < sampleSize; i++) {
        if (dataRows[i].length < 2) continue;
        final val = dataRows[i][1].toString().trim();
        final digits = val.replaceAll(RegExp(r'[^0-9]'), '');
        if (digits.length == 12 && int.tryParse(digits) != null) {
          utm12Count++;
        } else if (_looksLikeGeoPair(val)) {
          geoCount++;
        }
      }

      if (utm12Count >= geoCount && utm12Count > 0) return CoordinateFormat.utm12;
      if (geoCount > 0) return CoordinateFormat.geographic;
    } else {
      // 4 עמודות — עמודות 1 ו-2
      int utm6Count = 0;
      int geoCount = 0;

      for (int i = 0; i < sampleSize; i++) {
        if (dataRows[i].length < 3) continue;
        final val1 = dataRows[i][1].toString().trim();
        final val2 = dataRows[i][2].toString().trim();
        final digits1 = val1.replaceAll(RegExp(r'[^0-9]'), '');
        final digits2 = val2.replaceAll(RegExp(r'[^0-9]'), '');

        if ((digits1.length == 6 || digits1.length == 7) &&
            (digits2.length == 6 || digits2.length == 7) &&
            int.tryParse(digits1) != null && int.tryParse(digits2) != null) {
          utm6Count++;
        } else {
          final d1 = double.tryParse(val1);
          final d2 = double.tryParse(val2);
          if (d1 != null && d2 != null) {
            // טווח ישראל: lat 29-34, lng 34-36
            if (_isIsraelLat(d1) && _isIsraelLng(d2) ||
                _isIsraelLat(d2) && _isIsraelLng(d1)) {
              geoCount++;
            }
          }
        }
      }

      if (utm6Count >= geoCount && utm6Count > 0) return CoordinateFormat.utm6plus6;
      if (geoCount > 0) return CoordinateFormat.geographic;
    }

    return CoordinateFormat.unknown;
  }

  static bool _looksLikeGeoPair(String val) {
    // "32.0853, 34.7818" or "32.0853 34.7818"
    final parts = val.split(RegExp(r'[,\s]+'));
    if (parts.length != 2) return false;
    final a = double.tryParse(parts[0].trim());
    final b = double.tryParse(parts[1].trim());
    if (a == null || b == null) return false;
    return (_isIsraelLat(a) && _isIsraelLng(b)) ||
        (_isIsraelLat(b) && _isIsraelLng(a));
  }

  static bool _isIsraelLat(double v) => v >= 29 && v <= 34;
  static bool _isIsraelLng(double v) => v >= 34 && v <= 36;

  // ──────── פענוח קואורדינטה ────────

  static Coordinate? _parseCoordinate(
      List<dynamic> row, int columnCount, CoordinateFormat format) {
    switch (format) {
      case CoordinateFormat.utm12:
        final raw = row[1].toString().trim().replaceAll(RegExp(r'[^0-9]'), '');
        if (raw.isEmpty) return null;
        if (raw.length != 12) throw FormatException('UTM חייב להכיל 12 ספרות, נמצאו ${raw.length}');
        if (!UtmConverter.isValidUtm(raw)) throw const FormatException('ערך UTM לא תקין');
        final latLng = UtmConverter.utmToLatLng(raw);
        return Coordinate(lat: latLng.latitude, lng: latLng.longitude, utm: raw);

      case CoordinateFormat.utm6plus6:
        var east = row[1].toString().trim().replaceAll(RegExp(r'[^0-9]'), '');
        var north = row[2].toString().trim().replaceAll(RegExp(r'[^0-9]'), '');
        if (east.isEmpty && north.isEmpty) return null;

        // תמיכה ב-UTM מלא (7 ספרות) — חיתוך ספרה ראשונה לקבלת מוסכמת 6 ספרות צה"לית
        if (east.length == 7) east = east.substring(1);
        if (north.length == 7) north = north.substring(1);

        if (east.length != 6 || north.length != 6) {
          throw FormatException('UTM 6+6 — כל ערך חייב להכיל 6-7 ספרות (מזרח: ${row[1]}, צפון: ${row[2]})');
        }
        final utmStr = east + north;
        if (!UtmConverter.isValidUtm(utmStr)) throw const FormatException('ערך UTM לא תקין');
        final latLng = UtmConverter.utmToLatLng(utmStr);
        return Coordinate(lat: latLng.latitude, lng: latLng.longitude, utm: utmStr);

      case CoordinateFormat.geographic:
        double? lat, lng;
        if (columnCount == 3) {
          // עמודה אחת: "lat, lng" or "lat lng"
          final val = row[1].toString().trim();
          final parts = val.split(RegExp(r'[,\s]+'));
          if (parts.length != 2) throw const FormatException('פורמט גאוגרפי חייב להכיל שני ערכים');
          lat = double.tryParse(parts[0].trim());
          lng = double.tryParse(parts[1].trim());
        } else {
          // שתי עמודות
          lat = double.tryParse(row[1].toString().trim());
          lng = double.tryParse(row[2].toString().trim());
        }

        if (lat == null || lng == null) throw const FormatException('ערכים גאוגרפיים לא תקינים');

        // החלפה אם lat/lng מוחלפים
        if (_isIsraelLng(lat) && _isIsraelLat(lng)) {
          final tmp = lat;
          lat = lng;
          lng = tmp;
        }

        final utmStr = UtmConverter.latLngToUtm(LatLng(lat, lng));
        return Coordinate(lat: lat, lng: lng, utm: utmStr);

      case CoordinateFormat.unknown:
        return null;
    }
  }

  // ──────── סיווג סוג נקודה ────────

  static String _classifyType(String description) {
    final d = description.trim();
    if (d.isEmpty) return 'checkpoint';

    // נקודת התחלה
    if (RegExp(r'''נ[\.\s]?ה|נ"ה|התחלה''').hasMatch(d)) return 'start';
    // מעבר חובה
    if (RegExp(r'''נ[\.\s]?ב|נ"ב|מ[\.\s]?ח|מ"ח|חובה''').hasMatch(d)) return 'mandatory_passage';
    // נקודת סיום
    if (RegExp(r'''נ[\.\s]?ס|נ"ס|סוף|סיום''').hasMatch(d)) return 'end';

    return 'checkpoint';
  }

  // ──────── בדיקת התנגשויות ────────

  /// בודק התנגשויות עם נקודות קיימות לפי מספר סידורי
  static void checkConflicts(
      List<ParsedCheckpointRow> parsedRows, List<Checkpoint> existingCheckpoints) {
    final existingBySeq = <int, Checkpoint>{};
    for (final cp in existingCheckpoints) {
      existingBySeq[cp.sequenceNumber] = cp;
    }

    for (final row in parsedRows) {
      final existing = existingBySeq[row.sequenceNumber];
      if (existing != null) {
        row.hasConflict = true;
        row.conflictingCheckpoint = existing;
      } else {
        row.hasConflict = false;
        row.conflictingCheckpoint = null;
      }
    }
  }

  // ──────── בדיקת גבול גזרה ────────

  /// בדיקה האם כל נקודה בתוך הפוליגון, ומרחק מהגבול אם לא
  static List<BoundaryCheckResult> checkBoundary(
      List<ParsedCheckpointRow> parsedRows, Boundary boundary) {
    final polygon = boundary.coordinates;
    final results = <BoundaryCheckResult>[];

    for (final row in parsedRows) {
      final inside = GeometryUtils.isPointInPolygon(row.coordinate, polygon);

      double? distance;
      if (!inside) {
        distance = _minDistanceToBoundary(row.coordinate, polygon);
      }

      results.add(BoundaryCheckResult(
        rowIndex: row.rowIndex,
        sequenceNumber: row.sequenceNumber,
        isInside: inside,
        distanceMeters: distance,
      ));
    }

    return results;
  }

  static double _minDistanceToBoundary(Coordinate point, List<Coordinate> polygon) {
    double minDist = double.infinity;
    for (int i = 0; i < polygon.length; i++) {
      final a = polygon[i];
      final b = polygon[(i + 1) % polygon.length];
      final dist = GeometryUtils.distanceFromPointToSegmentMeters(point, a, b);
      if (dist < minDist) minDist = dist;
    }
    return minDist;
  }

  // ──────── בניית Checkpoint entities ────────

  /// בונה ישויות Checkpoint סופיות
  static List<Checkpoint> buildCheckpoints({
    required List<ParsedCheckpointRow> rows,
    required String areaId,
    required String createdBy,
    required Map<int, ConflictResolution> conflictResolutions,
    required List<Checkpoint> existingCheckpoints,
    bool autoNumber = false,
  }) {
    final now = DateTime.now();
    final results = <Checkpoint>[];

    // מספור אוטומטי — התחלה אחרי המקסימום הקיים
    int nextSeq = 1;
    if (autoNumber && existingCheckpoints.isNotEmpty) {
      nextSeq = existingCheckpoints
              .map((c) => c.sequenceNumber)
              .reduce((a, b) => a > b ? a : b) +
          1;
    }

    for (final row in rows) {
      final seq = autoNumber ? nextSeq++ : row.sequenceNumber;
      final type = row.detectedType;
      final color = Checkpoint.colorForType(type);

      results.add(Checkpoint(
        id: '${now.millisecondsSinceEpoch}_${results.length}',
        areaId: areaId,
        name: '',
        description: row.description,
        type: type,
        color: color,
        coordinates: row.coordinate,
        sequenceNumber: seq,
        createdBy: createdBy,
        createdAt: now,
      ));
    }

    return results;
  }

  /// מחזיר רשימת Checkpoint קיימות שצריך לעדכן (renumber) במקרה של התנגשות
  static List<Checkpoint> buildRenumberedExisting({
    required List<ParsedCheckpointRow> rows,
    required Map<int, ConflictResolution> conflictResolutions,
    required List<Checkpoint> existingCheckpoints,
  }) {
    final updated = <Checkpoint>[];
    final allSeqUsed = <int>{};

    // אסוף את כל מספרי הסדר שנמצאים בשימוש (חדשים + קיימים)
    for (final cp in existingCheckpoints) {
      allSeqUsed.add(cp.sequenceNumber);
    }
    for (final row in rows) {
      allSeqUsed.add(row.sequenceNumber);
    }

    int nextFreeSeq() {
      int s = allSeqUsed.isEmpty ? 1 : allSeqUsed.reduce((a, b) => a > b ? a : b) + 1;
      allSeqUsed.add(s);
      return s;
    }

    for (final row in rows) {
      if (!row.hasConflict || row.conflictingCheckpoint == null) continue;
      final resolution = conflictResolutions[row.sequenceNumber];
      if (resolution == ConflictResolution.renumberExisting) {
        final existing = row.conflictingCheckpoint!;
        final newSeq = nextFreeSeq();
        updated.add(existing.copyWith(sequenceNumber: newSeq));
      }
    }

    return updated;
  }

  // ──────── ייצוא תבנית ────────

  /// יוצר ושומר תבנית CSV להורדה
  static Future<String?> exportTemplate() async {
    const bom = '\uFEFF';
    const header = 'מס"ד,מזרח,צפון,תיאור';
    const example1 = '1,123456,654321,נ.ה. נקודת התחלה';
    const example2 = '2,123789,654987,נקודת ציון';
    const example3 = '3,124000,655000,מ.ח מעבר חובה';
    const example4 = '4,124500,655500,נ.ס. נקודת סיום';

    final csvContent = '$bom$header\n$example1\n$example2\n$example3\n$example4';
    final bytes = Uint8List.fromList(utf8.encode(csvContent));

    return saveFileWithBytes(
      dialogTitle: 'שמור תבנית ייבוא נקודות ציון',
      fileName: 'checkpoint_import_template.csv',
      bytes: bytes,
      allowedExtensions: ['csv'],
    );
  }

  // ──────── בחירת קובץ ────────

  /// פותח בורר קבצים ומחזיר נתיב ובייטים
  static Future<({String path, Uint8List bytes})?> pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'בחר קובץ נקודות ציון',
      type: FileType.custom,
      allowedExtensions: ['csv', 'xlsx', 'xls'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) return null;
    final file = result.files.first;

    Uint8List? bytes = file.bytes;
    if (bytes == null && file.path != null) {
      // דסקטופ — קריאה מנתיב
      bytes = await _readFileBytes(file.path!);
    }
    if (bytes == null) return null;

    final path = file.path ?? file.name;
    return (path: path, bytes: bytes);
  }

  static Future<Uint8List?> _readFileBytes(String path) async {
    try {
      return await File(path).readAsBytes();
    } catch (_) {
      return null;
    }
  }

  // ──────── תיאור פורמט ────────

  static String formatDescription(CoordinateFormat format) {
    switch (format) {
      case CoordinateFormat.utm12:
        return 'UTM 12 ספרות';
      case CoordinateFormat.utm6plus6:
        return 'UTM 6+6 ספרות (מזרח + צפון)';
      case CoordinateFormat.geographic:
        return 'קואורדינטות גאוגרפיות (lat/lng)';
      case CoordinateFormat.unknown:
        return 'לא זוהה';
    }
  }
}
