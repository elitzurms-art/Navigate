import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:latlong2/latlong.dart';
import '../core/utils/file_export_helper.dart';
import '../core/utils/utm_converter.dart';
import '../domain/entities/coordinate.dart';
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
    required this.createdCheckpoints,
    this.startPointId,
    this.endPointId,
    this.waypoints = const [],
    this.errors = const [],
    this.warnings = const [],
  });

  bool get hasErrors => errors.isNotEmpty;
  bool get isSuccess => errors.isEmpty && routes.isNotEmpty;
}

/// שירות ייצוא/ייבוא נקודות ציון ב-Excel
class CheckpointExcelService {
  static const int maxCheckpoints = 20;

  // ─── ייצוא תבנית ───────────────────────────────────────

  /// ייצוא תבנית Excel עם שמות המנווטים שנבחרו.
  /// מחזיר נתיב קובץ שנשמר, או null אם המשתמש ביטל.
  static Future<String?> exportTemplate({
    required domain.Navigation navigation,
    required List<app_user.User> participants,
  }) async {
    final excel = Excel.createExcel();

    // ── גיליון 1: "נקודות מנווטים" ──
    _buildNavigatorsSheet(excel, participants);

    // ── גיליון 2: "כללי" ──
    _buildGeneralSheet(excel);

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

  /// בונה את גיליון "נקודות מנווטים"
  static void _buildNavigatorsSheet(
    Excel excel,
    List<app_user.User> participants,
  ) {
    final sheet = excel['נקודות מנווטים'];

    // ── שורת כותרות ראשית (Row 0) ──
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0))
        .value = TextCellValue('שם');
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 0))
        .value = TextCellValue('מספר אישי');

    for (var i = 0; i < maxCheckpoints; i++) {
      final colBase = 2 + (i * 2);
      // כותרת ראשית — נ.צ. X (ממוזגת על 2 עמודות)
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: colBase, rowIndex: 0))
          .value = TextCellValue('נ.צ. ${i + 1}');
    }

    // ── שורת כותרות-משנה (Row 1) — מזרח/צפון ──
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1))
        .value = TextCellValue('');
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 1))
        .value = TextCellValue('');

    for (var i = 0; i < maxCheckpoints; i++) {
      final colBase = 2 + (i * 2);
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: colBase, rowIndex: 1))
          .value = TextCellValue('מזרח');
      sheet
          .cell(CellIndex.indexByColumnRow(
              columnIndex: colBase + 1, rowIndex: 1))
          .value = TextCellValue('צפון');
    }

    // ── שורות נתונים (Row 2+) — שם ומספר אישי ──
    for (var i = 0; i < participants.length; i++) {
      final user = participants[i];
      final row = i + 2;
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
          .value = TextCellValue(user.fullName);
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
          .value = TextCellValue(user.personalNumber);
    }
  }

  /// בונה את גיליון "כללי"
  static void _buildGeneralSheet(Excel excel) {
    final sheet = excel['כללי'];

    // כותרות
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0))
        .value = TextCellValue('סוג נקודה');
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 0))
        .value = TextCellValue('מזרח');
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 0))
        .value = TextCellValue('צפון');

    // נקודת התחלה (חובה)
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1))
        .value = TextCellValue('נקודת התחלה');

    // נקודת סיום
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2))
        .value = TextCellValue('נקודת סיום');

    // נקודות ביניים — שורות ריקות עם כותרת
    for (var i = 0; i < 10; i++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 3 + i))
          .value = TextCellValue('נקודת ביניים ${i + 1}');
    }
  }

  // ─── ייבוא מקובץ ─────────────────────────────────────

  /// ייבוא קובץ Excel ויצירת צירים.
  /// מחזיר תוצאת ייבוא עם routes, checkpoints, שגיאות ואזהרות.
  static Future<ExcelImportResult> importFromExcel({
    required String filePath,
    required domain.Navigation navigation,
    required List<app_user.User> participants,
  }) async {
    final errors = <String>[];
    final warnings = <String>[];

    // ── קריאת הקובץ ──
    final Uint8List fileBytes;
    try {
      fileBytes = await File(filePath).readAsBytes();
    } catch (e) {
      return ExcelImportResult(
        routes: {},
        createdCheckpoints: [],
        errors: ['שגיאה בקריאת הקובץ: $e'],
      );
    }

    final Excel excel;
    try {
      excel = Excel.decodeBytes(fileBytes);
    } catch (e) {
      return ExcelImportResult(
        routes: {},
        createdCheckpoints: [],
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
    final allCreatedCheckpoints = <NavCheckpoint>[];
    var checkpointCounter = 0;

    final generalSheet = excel.tables['כללי'];
    if (generalSheet == null) {
      warnings.add('לא נמצא גיליון "כללי" — ללא נקודת התחלה/סיום');
    } else {
      // שורה 1: נקודת התחלה (חובה)
      final startCoord = _parseCoordinateFromRow(generalSheet, 1);
      if (startCoord == null) {
        errors.add('נקודת התחלה חסרה בגיליון "כללי" — שדה חובה');
      } else {
        checkpointCounter++;
        final startCp = _createNavCheckpoint(
          navigation: navigation,
          name: 'נקודת התחלה',
          type: 'start',
          coordinate: startCoord,
          sequenceNumber: 0,
          counter: checkpointCounter,
        );
        allCreatedCheckpoints.add(startCp);
        startPointId = startCp.id;
      }

      // שורה 2: נקודת סיום
      final endCoord = _parseCoordinateFromRow(generalSheet, 2);
      if (endCoord != null) {
        checkpointCounter++;
        final endCp = _createNavCheckpoint(
          navigation: navigation,
          name: 'נקודת סיום',
          type: 'end',
          coordinate: endCoord,
          sequenceNumber: 9999,
          counter: checkpointCounter,
        );
        allCreatedCheckpoints.add(endCp);
        endPointId = endCp.id;
      }

      // שורות 3+: נקודות ביניים
      for (var row = 3; row < generalSheet.maxRows; row++) {
        final coord = _parseCoordinateFromRow(generalSheet, row);
        if (coord == null) continue;
        checkpointCounter++;
        final wpCp = _createNavCheckpoint(
          navigation: navigation,
          name: 'נקודת ביניים ${row - 2}',
          type: 'mandatory_passage',
          coordinate: coord,
          sequenceNumber: row - 2,
          counter: checkpointCounter,
        );
        allCreatedCheckpoints.add(wpCp);
        waypointCheckpoints.add(wpCp);
      }
    }

    // ── ניתוח גיליון "נקודות מנווטים" ──
    final navSheet = excel.tables['נקודות מנווטים'];
    if (navSheet == null) {
      return ExcelImportResult(
        routes: {},
        createdCheckpoints: allCreatedCheckpoints,
        errors: [...errors, 'לא נמצא גיליון "נקודות מנווטים"'],
        warnings: warnings,
      );
    }

    if (navSheet.maxRows < 3) {
      return ExcelImportResult(
        routes: {},
        createdCheckpoints: allCreatedCheckpoints,
        errors: [...errors, 'גיליון "נקודות מנווטים" ריק — אין שורות נתונים'],
        warnings: warnings,
      );
    }

    final routes = <String, domain.AssignedRoute>{};

    // שורות נתונים מתחילות מ-row 2 (0=כותרות, 1=משנה)
    for (var row = 2; row < navSheet.maxRows; row++) {
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
          warnings.add('שורה ${row + 1}: נמצאו מספר מנווטים בשם "$name" — יש להזין מספר אישי');
          continue;
        } else {
          warnings.add('שורה ${row + 1}: מנווט "$name" לא נמצא');
          continue;
        }
      }

      // ניתוח נקודות ציון — כל 2 עמודות מעמודה 2
      final navigatorCheckpointIds = <String>[];
      var cpIndex = 0;

      for (var col = 2; col < 2 + (maxCheckpoints * 2); col += 2) {
        cpIndex++;
        final coord = _parseCoordinateFromCells(
          cells: cells,
          colIndex: col,
        );
        if (coord == null) continue;

        checkpointCounter++;
        final cp = _createNavCheckpoint(
          navigation: navigation,
          name: 'נ.צ. $cpIndex (${participantMap[navigatorUid]?.fullName ?? name})',
          type: 'checkpoint',
          coordinate: coord,
          sequenceNumber: cpIndex,
          counter: checkpointCounter,
        );
        allCreatedCheckpoints.add(cp);
        navigatorCheckpointIds.add(cp.id);
      }

      if (navigatorCheckpointIds.isEmpty) {
        warnings.add(
            'שורה ${row + 1}: למנווט "$name" לא הוזנו נקודות ציון');
        continue;
      }

      // חישוב אורך ציר
      final routeLength = _calculateRouteLength(
        checkpoints: allCreatedCheckpoints
            .where((cp) => navigatorCheckpointIds.contains(cp.id))
            .toList(),
        startCheckpoint: startPointId != null
            ? allCreatedCheckpoints
                .where((cp) => cp.id == startPointId)
                .firstOrNull
            : null,
        endCheckpoint: endPointId != null
            ? allCreatedCheckpoints
                .where((cp) => cp.id == endPointId)
                .firstOrNull
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
      createdCheckpoints: allCreatedCheckpoints,
      startPointId: startPointId,
      endPointId: endPointId,
      waypoints: waypointSettings,
      errors: errors,
      warnings: warnings,
    );
  }

  // ─── עזרים פנימיים ──────────────────────────────────────

  /// ניתוח קואורדינטה משורה בגיליון "כללי".
  /// עמודה 1 = מזרח (או 12 ספרות), עמודה 2 = צפון.
  static Coordinate? _parseCoordinateFromRow(Sheet sheet, int rowIndex) {
    if (rowIndex >= sheet.maxRows) return null;
    final cells = sheet.row(rowIndex);
    return _parseCoordinateFromCells(cells: cells, colIndex: 1);
  }

  /// ניתוח קואורדינטה מזוג עמודות.
  /// תומך ב-3 פורמטים:
  ///   1. 12 ספרות בעמודה אחת
  ///   2. 6+6 בשתי עמודות
  ///   3. תא ריק = דילוג
  static Coordinate? _parseCoordinateFromCells({
    required List<Data?> cells,
    required int colIndex,
  }) {
    final cell1 = colIndex < cells.length
        ? cells[colIndex]?.value?.toString().trim() ?? ''
        : '';
    final cell2 = colIndex + 1 < cells.length
        ? cells[colIndex + 1]?.value?.toString().trim() ?? ''
        : '';

    if (cell1.isEmpty && cell2.isEmpty) return null;

    String utmString;

    // ניקוי — הסרת רווחים ותווים לא-ספרתיים
    final cleaned1 = cell1.replaceAll(RegExp(r'[^\d]'), '');
    final cleaned2 = cell2.replaceAll(RegExp(r'[^\d]'), '');

    if (cleaned1.length == 12 && cleaned2.isEmpty) {
      // פורמט 1: 12 ספרות בעמודה אחת
      utmString = cleaned1;
    } else if (cleaned1.length == 6 && cleaned2.length == 6) {
      // פורמט 2: 6+6 בשתי עמודות (מזרח + צפון)
      utmString = cleaned1 + cleaned2;
    } else if (cleaned1.isNotEmpty || cleaned2.isNotEmpty) {
      // פורמט לא תקין — ננסה לעשות padding
      if (cleaned1.isNotEmpty && cleaned2.isNotEmpty) {
        final east = cleaned1.padLeft(6, '0');
        final north = cleaned2.padLeft(6, '0');
        if (east.length <= 6 && north.length <= 6) {
          utmString = east + north;
        } else {
          return null; // ערך ארוך מדי
        }
      } else if (cleaned1.length == 12) {
        utmString = cleaned1;
      } else {
        return null; // לא ניתן לנתח
      }
    } else {
      return null;
    }

    if (!UtmConverter.isValidUtm(utmString)) return null;

    try {
      final latLng = UtmConverter.utmToLatLng(utmString);
      return Coordinate(
        lat: latLng.latitude,
        lng: latLng.longitude,
        utm: utmString,
      );
    } catch (_) {
      return null;
    }
  }

  /// יצירת NavCheckpoint חדש מקואורדינטה
  static NavCheckpoint _createNavCheckpoint({
    required domain.Navigation navigation,
    required String name,
    required String type,
    required Coordinate coordinate,
    required int sequenceNumber,
    required int counter,
  }) {
    final id =
        'excel_${navigation.id}_${DateTime.now().millisecondsSinceEpoch}_$counter';
    return NavCheckpoint(
      id: id,
      navigationId: navigation.id,
      sourceId: id, // ייבוא מ-Excel — אין מקור גלובלי
      areaId: navigation.areaId,
      name: name,
      description: 'יובא מקובץ Excel',
      type: type,
      color: type == 'start'
          ? 'green'
          : type == 'end'
              ? 'green'
              : 'blue',
      geometryType: 'point',
      coordinates: coordinate,
      sequenceNumber: sequenceNumber,
      labels: const [],
      createdBy: navigation.createdBy,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
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
