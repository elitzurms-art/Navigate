import 'dart:io';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import '../domain/entities/navigation_tree.dart';
import '../domain/entities/unit.dart';
import '../domain/entities/user.dart' as app_user;

class FrameworkExcelService {
  /// Exports a unit's sub-frameworks to Excel.
  /// Each SubFramework becomes a separate sheet.
  /// Returns the file path of the saved Excel file, or null if cancelled.
  static Future<String?> exportUnit({
    required Unit unit,
    required List<SubFramework> subFrameworks,
    required List<app_user.User> allUsers,
  }) async {
    final excel = Excel.createExcel();

    // Helper to resolve user display name
    String getUserName(String uid) {
      if (uid.startsWith('manual_')) return uid.substring(7);
      final matches = allUsers.where((u) => u.uid == uid);
      return matches.isNotEmpty ? matches.first.fullName : uid;
    }

    String getUserNumber(String uid) {
      if (uid.startsWith('manual_')) return '';
      final matches = allUsers.where((u) => u.uid == uid);
      return matches.isNotEmpty ? matches.first.personalNumber : uid;
    }

    // Write a sheet for each SubFramework
    void writeSheet(String sheetName, SubFramework sub) {
      // Excel sheet names max 31 chars, no special chars
      final safeName =
          sheetName.length > 31 ? sheetName.substring(0, 31) : sheetName;
      final sheet = excel[safeName];

      // Headers
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0))
          .value = TextCellValue('שם');
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 0))
          .value = TextCellValue('מספר אישי');
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 0))
          .value = TextCellValue('רמת ניווט');

      // Data rows
      for (var i = 0; i < sub.userIds.length; i++) {
        final uid = sub.userIds[i];
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i + 1))
            .value = TextCellValue(getUserName(uid));
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: i + 1))
            .value = TextCellValue(getUserNumber(uid));
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: i + 1))
            .value = TextCellValue(sub.getUserLevel(uid));
      }
    }

    for (final sub in subFrameworks) {
      writeSheet(sub.name, sub);
    }

    // Remove default Sheet1 after all sheets are created
    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    // Encode
    final bytes = excel.encode();
    if (bytes == null) throw Exception('Failed to encode Excel file');

    // Let user choose save location
    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}';
    final defaultFileName = '${unit.name}_$dateStr.xlsx';

    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: 'שמירת קובץ יחידה',
      fileName: defaultFileName,
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );

    if (savePath == null) return null; // User cancelled

    final filePath = savePath.endsWith('.xlsx') ? savePath : '$savePath.xlsx';
    final file = File(filePath);
    await file.writeAsBytes(bytes);

    return filePath;
  }

  /// Imports sub-frameworks from an Excel file.
  /// Each sheet becomes a SubFramework. Sheet name = SubFramework name.
  /// Returns a map of parent name -> list of SubFrameworks with userIds.
  static Future<Map<String, List<SubFramework>>> importSubFrameworks(
      String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    final excel = Excel.decodeBytes(bytes);

    final result = <String, List<SubFramework>>{};
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    var counter = 0;

    for (final sheetName in excel.tables.keys) {
      final table = excel.tables[sheetName]!;
      if (table.maxRows < 2) continue; // Skip empty sheets (only header)

      final userIds = <String>[];
      final userLevels = <String, String>{};

      // Read data rows (skip header at row 0)
      for (var row = 1; row < table.maxRows; row++) {
        final cells = table.row(row);
        if (cells.isEmpty) continue;

        // Try to get personal number from column 1
        final personalNumber =
            cells.length > 1 ? cells[1]?.value?.toString().trim() ?? '' : '';
        final name = cells[0]?.value?.toString().trim() ?? '';
        final level = cells.length > 2
            ? cells[2]?.value?.toString().trim() ?? ''
            : '';

        String? uid;
        if (personalNumber.isNotEmpty && personalNumber != '') {
          uid = personalNumber;
        } else if (name.isNotEmpty) {
          // Manual entry - no personal number
          uid = 'manual_$name';
        }

        if (uid != null) {
          userIds.add(uid);
          if (level.isNotEmpty && NavigationLevel.all.contains(level)) {
            userLevels[uid] = level;
          }
        }
      }

      if (userIds.isEmpty) continue;

      counter++;
      final subFramework = SubFramework(
        id: '${timestamp}_import_$counter',
        name: sheetName,
        userIds: userIds,
        userLevels: userLevels,
        isFixed: sheetName.contains('מפקדים') || sheetName.contains('מנהלת') || sheetName.contains('חיילים'),
      );

      // Group by parent: extract the part after " - " to find the parent name
      final dashIndex = sheetName.indexOf(' - ');
      final parentName =
          dashIndex > 0 ? sheetName.substring(dashIndex + 3) : '';

      result.putIfAbsent(parentName, () => []);
      result[parentName]!.add(subFramework);
    }

    return result;
  }
}
