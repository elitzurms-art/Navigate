import 'dart:convert';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../domain/entities/variables_sheet.dart';
import '../domain/entities/navigation.dart';
import '../core/utils/file_export_helper.dart';

/// שירות יצירת PDF לדף משתנים — נספח 24
class VariablesSheetPdfService {
  /// יצירת PDF וייצוא
  Future<String?> exportPdf({
    required Navigation navigation,
    required VariablesSheet sheet,
  }) async {
    final pdf = pw.Document();

    // Load Hebrew font
    final rubikRegular = await PdfGoogleFonts.rubikRegular();
    final rubikBold = await PdfGoogleFonts.rubikBold();

    final theme = pw.ThemeData.withFont(
      base: rubikRegular,
      bold: rubikBold,
    );

    // Page 1
    pdf.addPage(_buildPage1(sheet, navigation, theme));
    // Page 2
    pdf.addPage(_buildPage2(sheet, navigation, theme));
    // Page 3
    pdf.addPage(_buildPage3(sheet, navigation, theme));

    final bytes = await pdf.save();
    final fileName = 'דף_משתנים_${navigation.name}.pdf';

    return saveFileWithBytes(
      dialogTitle: 'ייצוא דף משתנים',
      fileName: fileName,
      bytes: Uint8List.fromList(bytes),
      allowedExtensions: ['pdf'],
    );
  }

  pw.Page _buildPage1(VariablesSheet sheet, Navigation navigation, pw.ThemeData theme) {
    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      textDirection: pw.TextDirection.rtl,
      theme: theme,
      build: (context) {
        return pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildPageHeader('60', 'נספח 24 — דף משתנים לניווט'),
              _buildSubtitle(navigation.name),
              pw.SizedBox(height: 8),

              // Section 1 — הכנה מקדימה
              _buildSectionTitle(1, 'הכנה מקדימה'),
              _buildFieldRow('אימון מקדים', sheet.preliminaryTraining),
              _buildBoolFieldRow('בדיקת חובש', sheet.medicCheckDone, sheet.medicCheckNotes),
              _buildBoolFieldRow('בדיקת משקל', sheet.weightCheckDone, sheet.weightCheckNotes),
              _buildBoolFieldRow('תדריך נהגים', sheet.driverBriefingDone, sheet.driverBriefingNotes),
              pw.SizedBox(height: 6),

              // Section 2 — לוח זמנים
              _buildSectionTitle(2, 'לוח זמנים הכנה'),
              _buildPreparationTable(sheet.preparationSchedule),
              pw.SizedBox(height: 6),

              // Sections 3-5 — שעות
              _buildSectionTitle(3, 'שעת יציאה'),
              _buildFieldRow('שעת יציאה', sheet.departureTime),
              _buildSectionTitle(4, 'שעת מעבר'),
              _buildFieldRow('שעת מעבר', sheet.checkpointPassageTime),
              _buildSectionTitle(5, 'שעת סיום ניווט'),
              _buildFieldRow('שעת סיום', sheet.navigationEndTime),

              // Section 6
              _buildSectionTitle(6, 'נקודת כינוס חירום'),
              _buildFieldRow('נקודה', sheet.emergencyGatheringPoint),

              // Section 7
              _buildSectionTitle(7, 'שעת "גג" ובטיחות'),
              _buildFieldRow('שעת "גג"', sheet.ceilingTime),
              _buildFieldRow('גג בטיחות', sheet.safetyCeilingTime),

              // Section 8-9
              _buildSectionTitle(8, 'מזג אוויר ואסטרונומיה'),
              pw.Row(
                children: [
                  pw.Expanded(child: _buildFieldRow('עונה', sheet.season)),
                  pw.Expanded(child: _buildFieldRow('שקיעה', sheet.sunsetTime)),
                  pw.Expanded(child: _buildFieldRow('זריחה', sheet.sunriseTime)),
                ],
              ),
              pw.Row(
                children: [
                  pw.Expanded(child: _buildFieldRow('תאורת ירח',
                      sheet.moonIllumination != null
                          ? '${(sheet.moonIllumination! * 100).toStringAsFixed(0)}%'
                          : null)),
                  pw.Expanded(child: _buildFieldRow('טמפרטורה', sheet.weatherTemperature)),
                  pw.Expanded(child: _buildFieldRow('רוח', sheet.weatherWindSpeed)),
                ],
              ),
              if (sheet.weatherNotes != null)
                _buildFieldRow('דגשים', sheet.weatherNotes),
            ],
          ),
        );
      },
    );
  }

  pw.Page _buildPage2(VariablesSheet sheet, Navigation navigation, pw.ThemeData theme) {
    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      textDirection: pw.TextDirection.rtl,
      theme: theme,
      build: (context) {
        return pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildPageHeader('61', 'נספח 24 — דף משתנים לניווט (המשך)'),
              pw.SizedBox(height: 8),

              // Section 10 — בדיקת מערכות
              _buildSectionTitle(10, 'בדיקת מערכות'),
              _buildSystemCheckTable(sheet.systemCheckTable),
              pw.SizedBox(height: 6),

              // Section 11 — תקשורת
              _buildSectionTitle(11, 'רשתות תקשורת'),
              _buildCommunicationTable(sheet.communicationTable),
              pw.SizedBox(height: 6),

              // Section 12 — כוחות שכנים
              _buildSectionTitle(12, 'כוחות שכנים'),
              _buildNeighboringForcesTable(sheet.neighboringForces),
              pw.SizedBox(height: 6),

              // Section 13
              _buildSectionTitle(13, 'ציר תנועת הפיקוד'),
              _buildFieldRow('ציר', sheet.commandPostAxis),

              // Section 14
              _buildSectionTitle(14, 'מסוק חילוץ'),
              pw.Row(
                children: [
                  pw.Expanded(child: _buildFieldRow('טלפון', sheet.helicopterPhone)),
                  pw.Expanded(child: _buildFieldRow('תדר', sheet.helicopterFrequency)),
                ],
              ),
              _buildFieldRow('הנחיות', sheet.helicopterInstructions),

              // Section 15
              _buildSectionTitle(15, 'פקודות אש'),
              _buildFieldRow('פקודות', sheet.fireInstructions),

              // Section 16
              _buildSectionTitle(16, 'תקריות ותגובות'),
              _buildFieldRow('תקריות', sheet.incidentsAndResponses),

              // Section 17
              _buildSectionTitle(17, 'נתונים נוספים להכרת הגזרה'),
              _buildAdditionalDataTable(sheet.additionalData),
            ],
          ),
        );
      },
    );
  }

  pw.Page _buildPage3(VariablesSheet sheet, Navigation navigation, pw.ThemeData theme) {
    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      textDirection: pw.TextDirection.rtl,
      theme: theme,
      build: (context) {
        return pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildPageHeader('62', 'נספח 24 — דף משתנים לניווט (המשך)'),
              pw.SizedBox(height: 8),

              // Section 18
              _buildSectionTitle(18, 'סריקת נפגעים'),
              pw.Row(
                children: [
                  pw.Expanded(child: _buildFieldRow('סורק', sheet.casualtySweepBy)),
                  pw.Expanded(child: _buildFieldRow('תאריך', sheet.casualtySweepDate)),
                  pw.Expanded(child: _buildFieldRow('שעה', sheet.casualtySweepTime)),
                ],
              ),

              // Section 19
              _buildSectionTitle(19, 'הנחיות חיפוש וחילוץ'),
              _buildFieldRow('הנחיות', sheet.searchRescueInstructions),

              // Section 20
              _buildSectionTitle(20, 'אישור רכב'),
              pw.Row(
                children: [
                  pw.Expanded(child: _buildFieldRow('רכב 1', sheet.vehicleNumber1)),
                  pw.Expanded(child: _buildFieldRow('רכב 2', sheet.vehicleNumber2)),
                  pw.Expanded(child: _buildFieldRow('הגבלה 23:00',
                      sheet.afterElevenRestriction == true ? 'כן' : 'לא')),
                ],
              ),

              // Section 21
              _buildSectionTitle(21, 'הערות מפקד'),
              _buildFieldRow('הערות', sheet.commanderNotes),
              _buildFieldRow('לקחי מנווטים', sheet.previousNavigatorLessons),

              // Section 22
              _buildSectionTitle(22, 'משלים תדריך בטיחות'),
              _buildFieldRow('פירוט', sheet.safetyBriefingSupplement),
              pw.SizedBox(height: 12),

              // Section 23
              _buildSectionTitle(23, 'חתימת מנהל הניווט'),
              _buildSignatureBlock(sheet.managerSignature),
              pw.SizedBox(height: 12),

              // Section 24
              _buildSectionTitle(24, 'חתימת מאשר (מ"פ / סמ"פ)'),
              _buildSignatureBlock(sheet.approverSignature),
              pw.SizedBox(height: 12),

              // Section 25
              _buildSectionTitle(25, 'דף תיאום'),
              _buildFieldRow('הערות', sheet.coordinationSheetNotes),
            ],
          ),
        );
      },
    );
  }

  // ==== PDF Building Helpers ====

  pw.Widget _buildPageHeader(String pageNum, String title) {
    return pw.Column(
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('— שמור —', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
            pw.Text('עמוד $pageNum', style: const pw.TextStyle(fontSize: 10)),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Center(
          child: pw.Text(title,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)),
        ),
        pw.Divider(thickness: 1.5),
      ],
    );
  }

  pw.Widget _buildSubtitle(String navName) {
    return pw.Center(
      child: pw.Text('ניווט: $navName', style: const pw.TextStyle(fontSize: 12)),
    );
  }

  pw.Widget _buildSectionTitle(int number, String title) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      margin: const pw.EdgeInsets.only(top: 6, bottom: 3),
      decoration: pw.BoxDecoration(
        color: PdfColors.blue50,
        border: pw.Border.all(color: PdfColors.blue200),
      ),
      child: pw.Text('$number. $title',
        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
    );
  }

  pw.Widget _buildFieldRow(String label, String? value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 100,
            child: pw.Text('$label:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
          ),
          pw.Expanded(
            child: pw.Text(value ?? '________________', style: const pw.TextStyle(fontSize: 9)),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildBoolFieldRow(String label, bool? checked, String? notes) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        children: [
          pw.SizedBox(
            width: 100,
            child: pw.Text('$label:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
          ),
          pw.Text(checked == true ? '[V]' : '[ ]', style: const pw.TextStyle(fontSize: 9)),
          pw.SizedBox(width: 8),
          if (notes != null && notes.isNotEmpty)
            pw.Expanded(child: pw.Text(notes, style: const pw.TextStyle(fontSize: 9))),
        ],
      ),
    );
  }

  pw.Widget _buildPreparationTable(List<PreparationScheduleRow> rows) {
    return pw.Table(
      border: pw.TableBorder.all(),
      columnWidths: {
        0: const pw.FlexColumnWidth(2),
        1: const pw.FlexColumnWidth(1.5),
        2: const pw.FlexColumnWidth(1.5),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _cell('סוג הכנה', bold: true),
            _cell('תאריך ביצוע', bold: true),
            _cell('הערות', bold: true),
          ],
        ),
        ...rows.map((r) => pw.TableRow(children: [
          _cell(r.preparationType ?? ''),
          _cell(r.executionDate ?? ''),
          _cell(r.notes ?? ''),
        ])),
        // Pad to 4 rows minimum
        ...List.generate(
          (4 - rows.length).clamp(0, 4),
          (_) => pw.TableRow(children: [_cell(''), _cell(''), _cell('')]),
        ),
      ],
    );
  }

  pw.Widget _buildSystemCheckTable(List<SystemCheckRow> rows) {
    return pw.Table(
      border: pw.TableBorder.all(),
      columnWidths: {
        0: const pw.FlexColumnWidth(2),
        1: const pw.FlexColumnWidth(1),
        2: const pw.FlexColumnWidth(1),
        3: const pw.FlexColumnWidth(1.5),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _cell('מערכת', bold: true),
            _cell('נבדק', bold: true),
            _cell('תקין', bold: true),
            _cell('קליטת GPS', bold: true),
          ],
        ),
        ...rows.map((r) => pw.TableRow(children: [
          _cell(r.systemName ?? ''),
          _cell(r.checkPerformed == true ? 'V' : ''),
          _cell(r.findingsOk == true ? 'V' : ''),
          _cell(r.gpsReception ?? ''),
        ])),
      ],
    );
  }

  pw.Widget _buildCommunicationTable(List<CommunicationRow> rows) {
    return pw.Table(
      border: pw.TableBorder.all(),
      columnWidths: {
        0: const pw.FlexColumnWidth(1),
        1: const pw.FlexColumnWidth(1),
        2: const pw.FlexColumnWidth(1),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _cell('סוג רשת', bold: true),
            _cell('שם רשת', bold: true),
            _cell('תדר/ערוץ', bold: true),
          ],
        ),
        ...rows.map((r) => pw.TableRow(children: [
          _cell(r.networkType ?? ''),
          _cell(r.networkName ?? ''),
          _cell(r.frequency ?? ''),
        ])),
        ...List.generate(
          (3 - rows.length).clamp(0, 3),
          (_) => pw.TableRow(children: [_cell(''), _cell(''), _cell('')]),
        ),
      ],
    );
  }

  pw.Widget _buildNeighboringForcesTable(List<NeighboringForceRow> rows) {
    return pw.Table(
      border: pw.TableBorder.all(),
      columnWidths: {
        0: const pw.FlexColumnWidth(1.5),
        1: const pw.FlexColumnWidth(1),
        2: const pw.FlexColumnWidth(0.7),
        3: const pw.FlexColumnWidth(0.7),
        4: const pw.FlexColumnWidth(1),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _cell('כוח', bold: true),
            _cell('מיקום', bold: true),
            _cell('מרחק', bold: true),
            _cell('כיוון', bold: true),
            _cell('סוג אימון', bold: true),
          ],
        ),
        ...rows.map((r) => pw.TableRow(children: [
          _cell(r.forceName ?? ''),
          _cell(r.location ?? ''),
          _cell(r.distance ?? ''),
          _cell(r.direction ?? ''),
          _cell(r.trainingType ?? ''),
        ])),
      ],
    );
  }

  pw.Widget _buildAdditionalDataTable(List<AdditionalDataRow> rows) {
    return pw.Table(
      border: pw.TableBorder.all(),
      columnWidths: {
        0: const pw.FlexColumnWidth(1),
        1: const pw.FlexColumnWidth(1.5),
        2: const pw.FlexColumnWidth(1.5),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _cell('שלב ניווט', bold: true),
            _cell('פריט נתון', bold: true),
            _cell('פעילות מניעה', bold: true),
          ],
        ),
        ...rows.map((r) => pw.TableRow(children: [
          _cell(r.navigationPhase ?? ''),
          _cell(r.dataItem ?? ''),
          _cell(r.preventionActivity ?? ''),
        ])),
      ],
    );
  }

  pw.Widget _buildSignatureBlock(SignatureData? sig) {
    if (sig == null) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.SizedBox(width: 60, child: pw.Text('שם:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9))),
              pw.Text('________________', style: const pw.TextStyle(fontSize: 9)),
              pw.SizedBox(width: 20),
              pw.SizedBox(width: 60, child: pw.Text('דרגה:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9))),
              pw.Text('________________', style: const pw.TextStyle(fontSize: 9)),
            ],
          ),
          pw.SizedBox(height: 6),
          pw.Text('חתימה: ________________________', style: const pw.TextStyle(fontSize: 9)),
        ],
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          children: [
            pw.SizedBox(width: 60, child: pw.Text('שם:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9))),
            pw.Text(sig.name ?? '________________', style: const pw.TextStyle(fontSize: 9)),
            pw.SizedBox(width: 20),
            pw.SizedBox(width: 60, child: pw.Text('דרגה:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9))),
            pw.Text(sig.rank ?? '________________', style: const pw.TextStyle(fontSize: 9)),
          ],
        ),
        pw.SizedBox(height: 6),
        if (sig.signatureBase64 != null && sig.signatureBase64!.isNotEmpty)
          pw.Container(
            height: 60,
            width: 200,
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400),
            ),
            child: pw.Image(
              pw.MemoryImage(base64Decode(sig.signatureBase64!)),
              fit: pw.BoxFit.contain,
            ),
          )
        else
          pw.Text('חתימה: ________________________', style: const pw.TextStyle(fontSize: 9)),
      ],
    );
  }

  pw.Widget _cell(String text, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(3),
      child: pw.Text(text,
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
        textAlign: pw.TextAlign.center,
      ),
    );
  }
}
