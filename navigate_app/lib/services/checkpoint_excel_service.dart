import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:latlong2/latlong.dart';
import '../core/utils/file_export_helper.dart';
import '../core/utils/utm_converter.dart';
import '../domain/entities/nav_layer.dart';
import '../domain/entities/navigation.dart' as domain;
import '../domain/entities/navigation_settings.dart';
import '../domain/entities/user.dart' as app_user;

/// תוצאת ייבוא מקובץ Excel
class ExcelImportResult {
  final Map<String, domain.AssignedRoute> routes;
  final List<NavCheckpoint> createdCheckpoints;
  final String? startPointId;
  final String? endPointId;
  final List<WaypointCheckpoint> waypoints;
  final List<String> errors;
  final List<String> warnings;

  const ExcelImportResult({
    required this.routes,
    this.createdCheckpoints = const [],
    this.startPointId,
    this.endPointId,
    this.waypoints = const [],
    this.errors = const [],
    this.warnings = const [],
  });

  bool get hasErrors => errors.isNotEmpty;
  bool get isSuccess => errors.isEmpty && routes.isNotEmpty;
}

/// שירות ייצוא/ייבוא נקודות ציון ב-Excel — לפי מספר סידורי
class CheckpointExcelService {
  static const int maxCheckpoints = 20;

  // ─── ייצוא תבנית ───────────────────────────────────────

  /// ייצוא תבנית Excel — עמודה אחת לנקודה (מספר סידורי).
  /// מחזיר נתיב קובץ שנשמר, או null אם המשתמש ביטל.
  static Future<String?> exportTemplate({
    required domain.Navigation navigation,
    required List<app_user.User> participants,
    required List<NavCheckpoint> checkpoints,
    List<NavBoundary> boundaries = const [],
    Map<String, String?> checkpointToBoundaryMap = const {},
  }) async {
    final excel = Excel.createExcel();

    // ── גיליון 1: "נקודות מנווטים" ──
    _buildNavigatorsSheet(excel, participants);

    // ── גיליון 2: "כללי" ──
    _buildGeneralSheet(excel);

    // ── גיליון 3+: "רשימת נקודות" — טבלת עזר ──
    if (boundaries.length >= 2) {
      // מספר גבולות גזרה → גיליון נפרד לכל גבול
      final boundaryGroups = <String?, List<NavCheckpoint>>{};
      for (final cp in checkpoints) {
        final boundaryId = checkpointToBoundaryMap[cp.id];
        boundaryGroups.putIfAbsent(boundaryId, () => []).add(cp);
      }

      for (final boundary in boundaries) {
        final bCps = boundaryGroups[boundary.id] ?? [];
        if (bCps.isEmpty) continue;
        var sheetName = 'נקודות — ${boundary.name}';
        if (sheetName.length > 31) sheetName = sheetName.substring(0, 31);
        _buildReferenceSheet(excel, bCps, sheetName: sheetName);
      }

      // נקודות ללא גבול
      final noBoundaryCps = boundaryGroups[null] ?? [];
      if (noBoundaryCps.isNotEmpty) {
        _buildReferenceSheet(excel, noBoundaryCps,
            sheetName: 'נקודות — ללא גבול');
      }
    } else {
      _buildReferenceSheet(excel, checkpoints);
    }

    // מחיקת Sheet1 ברירת מחדל
    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    final bytes = excel.encode();
    if (bytes == null) throw Exception('שגיאה בקידוד קובץ Excel');

    final fileBytes = Uint8List.fromList(bytes);
    final savePath = await saveFileWithBytes(
      dialogTitle: 'שמירת תבנית נקודות',
      fileName: '${navigation.name}_נקודות.xlsx',
      bytes: fileBytes,
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );

    if (savePath == null) return null;
    return savePath.endsWith('.xlsx') ? savePath : '$savePath.xlsx';
  }

  /// גיליון "נקודות מנווטים" — עמודה אחת לנקודה (מספר סידורי)
  static void _buildNavigatorsSheet(
    Excel excel,
    List<app_user.User> participants,
  ) {
    final sheet = excel['נקודות מנווטים'];

    // ── שורת כותרות (Row 0) ──
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0))
        .value = TextCellValue('שם');
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 0))
        .value = TextCellValue('מספר אישי');

    for (var i = 0; i < maxCheckpoints; i++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 2 + i, rowIndex: 0))
          .value = TextCellValue('נ.צ. ${i + 1}');
    }

    // ── שורות נתונים (Row 1+) — ללא שורת משנה ──
    for (var i = 0; i < participants.length; i++) {
      final user = participants[i];
      final row = i + 1;
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
          .value = TextCellValue(user.fullName);
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
          .value = TextCellValue(user.personalNumber);
    }
  }

  /// גיליון "כללי" — מספר סידורי במקום UTM
  static void _buildGeneralSheet(Excel excel) {
    final sheet = excel['כללי'];

    // כותרות
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0))
        .value = TextCellValue('סוג נקודה');
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 0))
        .value = TextCellValue('מספר סידורי');

    // נקודת התחלה (חובה)
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1))
        .value = TextCellValue('נקודת התחלה');

    // נקודת סיום
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2))
        .value = TextCellValue('נקודת סיום');

    // נקודות ביניים
    for (var i = 0; i < 10; i++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 3 + i))
          .value = TextCellValue('נקודת ביניים ${i + 1}');
    }
  }

  /// גיליון "רשימת נקודות" — טבלת עזר עם כל הנקודות הזמינות בגבול הגזרה
  static void _buildReferenceSheet(
    Excel excel,
    List<NavCheckpoint> checkpoints, {
    String sheetName = 'רשימת נקודות',
  }) {
    final sheet = excel[sheetName];

    // כותרות
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0))
        .value = TextCellValue('מספר סידורי');
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 0))
        .value = TextCellValue('תיאור');
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 0))
        .value = TextCellValue('נ.צ. (UTM)');

    final sorted = [...checkpoints]
      ..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));
    for (var i = 0; i < sorted.length; i++) {
      final cp = sorted[i];
      final row = i + 1;
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
          .value = IntCellValue(cp.sequenceNumber);
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
          .value = TextCellValue(cp.description);
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row))
          .value = TextCellValue(cp.coordinates?.utm ?? '');
    }
  }

  // ─── ייבוא מקובץ ─────────────────────────────────────

  /// ייבוא קובץ Excel — מספרים סידוריים של נקודות קיימות.
  /// מחזיר תוצאת ייבוא עם routes, שגיאות ואזהרות.
  static Future<ExcelImportResult> importFromExcel({
    required String filePath,
    required domain.Navigation navigation,
    required List<app_user.User> participants,
    required List<NavCheckpoint> checkpoints,
  }) async {
    final errors = <String>[];
    final warnings = <String>[];

    // ── מיפוי מספר סידורי → נקודה ──
    final seqMap = <int, List<NavCheckpoint>>{};
    for (final cp in checkpoints) {
      seqMap.putIfAbsent(cp.sequenceNumber, () => []).add(cp);
    }

    // בדיקת כפילויות — מספר סידורי מופיע במספר נקודות (גבולות גזרה שונים)
    final duplicateSeqs =
        seqMap.entries.where((e) => e.value.length > 1).toList();
    if (duplicateSeqs.isNotEmpty) {
      for (final dup in duplicateSeqs) {
        errors.add(
          'מספר סידורי ${dup.key} מופיע ב-${dup.value.length} נקודות שונות: '
          '${dup.value.map((c) => c.name).join(", ")} — '
          'יש לבחור לאיזה גבול גזרה הכוונה',
        );
      }
      return ExcelImportResult(
        routes: {},
        errors: errors,
        warnings: warnings,
      );
    }

    final seqToCheckpoint = <int, NavCheckpoint>{};
    for (final entry in seqMap.entries) {
      seqToCheckpoint[entry.key] = entry.value.first;
    }

    // ── קריאת הקובץ ──
    final Uint8List fileBytes;
    try {
      fileBytes = await File(filePath).readAsBytes();
    } catch (e) {
      return ExcelImportResult(
        routes: {},
        errors: ['שגיאה בקריאת הקובץ: $e'],
      );
    }

    final Excel excel;
    try {
      excel = Excel.decodeBytes(fileBytes);
    } catch (e) {
      return ExcelImportResult(
        routes: {},
        errors: ['הקובץ אינו קובץ Excel תקין: $e'],
      );
    }

    // ── מיפוי משתתפים לפי מספר אישי ──
    final participantMap = <String, app_user.User>{};
    for (final user in participants) {
      participantMap[user.uid] = user;
    }

    // ── ניתוח גיליון "כללי" ──
    String? startPointId;
    String? endPointId;
    final waypointCheckpoints = <NavCheckpoint>[];

    final generalSheet = excel.tables['כללי'];
    if (generalSheet == null) {
      warnings.add('לא נמצא גיליון "כללי" — ללא נקודת התחלה/סיום');
    } else {
      // שורה 1: נקודת התחלה (חובה)
      final startSeq = _parseSeqNumberFromRow(generalSheet, 1);
      if (startSeq == null) {
        errors.add('נקודת התחלה חסרה בגיליון "כללי" — שדה חובה');
      } else {
        final startCp = seqToCheckpoint[startSeq];
        if (startCp == null) {
          errors.add(
              'נקודת התחלה: מספר סידורי $startSeq לא נמצא ברשימת הנקודות');
        } else {
          startPointId = startCp.id;
        }
      }

      // שורה 2: נקודת סיום
      final endSeq = _parseSeqNumberFromRow(generalSheet, 2);
      if (endSeq != null) {
        final endCp = seqToCheckpoint[endSeq];
        if (endCp == null) {
          errors.add(
              'נקודת סיום: מספר סידורי $endSeq לא נמצא ברשימת הנקודות');
        } else {
          endPointId = endCp.id;
        }
      }

      // שורות 3+: נקודות ביניים
      for (var row = 3; row < generalSheet.maxRows; row++) {
        final wpSeq = _parseSeqNumberFromRow(generalSheet, row);
        if (wpSeq == null) continue;
        final wpCp = seqToCheckpoint[wpSeq];
        if (wpCp == null) {
          warnings
              .add('נקודת ביניים ${row - 2}: מספר סידורי $wpSeq לא נמצא');
          continue;
        }
        waypointCheckpoints.add(wpCp);
      }
    }

    // ── ניתוח גיליון "נקודות מנווטים" ──
    final navSheet = excel.tables['נקודות מנווטים'];
    if (navSheet == null) {
      return ExcelImportResult(
        routes: {},
        errors: [...errors, 'לא נמצא גיליון "נקודות מנווטים"'],
        warnings: warnings,
      );
    }

    if (navSheet.maxRows < 2) {
      return ExcelImportResult(
        routes: {},
        errors: [
          ...errors,
          'גיליון "נקודות מנווטים" ריק — אין שורות נתונים'
        ],
        warnings: warnings,
      );
    }

    final routes = <String, domain.AssignedRoute>{};

    // שורות נתונים מתחילות מ-row 1 (row 0 = כותרות, ללא שורת משנה)
    for (var row = 1; row < navSheet.maxRows; row++) {
      final cells = navSheet.row(row);
      if (cells.isEmpty) continue;

      // עמודה 0: שם, עמודה 1: מספר אישי
      final name = cells.isNotEmpty
          ? cells[0]?.value?.toString().trim() ?? ''
          : '';
      final personalNumber = cells.length > 1
          ? cells[1]?.value?.toString().trim() ?? ''
          : '';

      if (personalNumber.isEmpty && name.isEmpty) continue;

      // זיהוי המנווט
      String? navigatorUid;
      if (personalNumber.isNotEmpty) {
        if (participantMap.containsKey(personalNumber)) {
          navigatorUid = personalNumber;
        } else {
          warnings.add(
              'שורה ${row + 1}: מנווט "$name" (מ.א. $personalNumber) לא נמצא ברשימת המשתתפים');
          continue;
        }
      } else {
        // חיפוש לפי שם
        final matches =
            participants.where((u) => u.fullName == name).toList();
        if (matches.length == 1) {
          navigatorUid = matches.first.uid;
        } else if (matches.length > 1) {
          warnings.add(
              'שורה ${row + 1}: נמצאו מספר מנווטים בשם "$name" — יש להזין מספר אישי');
          continue;
        } else {
          warnings.add('שורה ${row + 1}: מנווט "$name" לא נמצא');
          continue;
        }
      }

      // ניתוח מספרים סידוריים — עמודה אחת לנקודה
      final navigatorCheckpointIds = <String>[];

      for (var col = 2; col < 2 + maxCheckpoints; col++) {
        final seqNum = _parseSeqNumberFromCell(cells, col);
        if (seqNum == null) continue;

        final cp = seqToCheckpoint[seqNum];
        if (cp == null) {
          warnings.add(
              'שורה ${row + 1}, נ.צ. ${col - 1}: מספר סידורי $seqNum לא נמצא');
          continue;
        }
        navigatorCheckpointIds.add(cp.id);
      }

      if (navigatorCheckpointIds.isEmpty) {
        warnings.add(
            'שורה ${row + 1}: למנווט "$name" לא הוזנו נקודות ציון');
        continue;
      }

      // חישוב אורך ציר
      final routeCheckpoints = checkpoints
          .where((cp) => navigatorCheckpointIds.contains(cp.id))
          .toList();
      final routeLength = _calculateRouteLength(
        checkpoints: routeCheckpoints,
        startCheckpoint: startPointId != null
            ? checkpoints.where((cp) => cp.id == startPointId).firstOrNull
            : null,
        endCheckpoint: endPointId != null
            ? checkpoints.where((cp) => cp.id == endPointId).firstOrNull
            : null,
      );

      routes[navigatorUid] = domain.AssignedRoute(
        checkpointIds: navigatorCheckpointIds,
        routeLengthKm: routeLength,
        sequence: navigatorCheckpointIds,
        startPointId: startPointId,
        endPointId: endPointId,
        waypointIds: waypointCheckpoints.map((wp) => wp.id).toList(),
        status: 'optimal',
      );
    }

    if (routes.isEmpty && errors.isEmpty) {
      errors.add('לא נמצאו צירים תקינים בקובץ');
    }

    // ייצור WaypointCheckpoint list עבור navigation
    final waypointSettings = waypointCheckpoints
        .asMap()
        .entries
        .map((entry) => WaypointCheckpoint(
              checkpointId: entry.value.id,
              placementType: 'between_checkpoints',
              afterCheckpointIndex: entry.key,
            ))
        .toList();

    return ExcelImportResult(
      routes: routes,
      startPointId: startPointId,
      endPointId: endPointId,
      waypoints: waypointSettings,
      errors: errors,
      warnings: warnings,
    );
  }

  // ─── עזרים פנימיים ──────────────────────────────────────

  /// ניתוח מספר סידורי משורה בגיליון "כללי" (עמודה 1)
  static int? _parseSeqNumberFromRow(Sheet sheet, int rowIndex) {
    if (rowIndex >= sheet.maxRows) return null;
    final cells = sheet.row(rowIndex);
    return _parseSeqNumberFromCell(cells, 1);
  }

  /// ניתוח מספר סידורי מתא בודד
  static int? _parseSeqNumberFromCell(List<Data?> cells, int colIndex) {
    if (colIndex >= cells.length) return null;
    final cell = cells[colIndex];
    if (cell == null || cell.value == null) return null;

    final value = cell.value;
    if (value is IntCellValue) return value.value;
    if (value is DoubleCellValue) return value.value.toInt();

    final str = value.toString().trim();
    if (str.isEmpty) return null;
    return int.tryParse(str);
  }

  /// חישוב אורך ציר בק"מ (קו ישר בין נקודות)
  static double _calculateRouteLength({
    required List<NavCheckpoint> checkpoints,
    NavCheckpoint? startCheckpoint,
    NavCheckpoint? endCheckpoint,
  }) {
    if (checkpoints.isEmpty) return 0;

    final points = <LatLng>[];

    if (startCheckpoint?.coordinates != null) {
      points.add(startCheckpoint!.coordinates!.toLatLng());
    }

    for (final cp in checkpoints) {
      if (cp.coordinates != null) {
        points.add(cp.coordinates!.toLatLng());
      }
    }

    if (endCheckpoint?.coordinates != null) {
      points.add(endCheckpoint!.coordinates!.toLatLng());
    }

    if (points.length < 2) return 0;

    var totalMeters = 0.0;
    for (var i = 0; i < points.length - 1; i++) {
      totalMeters += UtmConverter.distanceBetween(points[i], points[i + 1]);
    }

    return totalMeters / 1000.0;
  }
}
