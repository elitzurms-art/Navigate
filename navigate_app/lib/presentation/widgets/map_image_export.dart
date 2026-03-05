import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../core/utils/file_export_helper.dart';

/// ייצוא מפה כ-PDF — לוכד צילום מסך של Widget ומייצא כקובץ PDF
class MapImageExport {
  /// מפתח לוויידג'ט שרוצים לצלם
  final GlobalKey repaintBoundaryKey;

  MapImageExport({required this.repaintBoundaryKey});

  /// צילום מסך וייצוא כ-PDF
  Future<String?> exportAsPdf({
    required BuildContext context,
    String fileName = 'map_export.pdf',
    String? title,
    double pixelRatio = 3.0,
  }) async {
    try {
      // הפעלת מצב צילום — עוטף ב-RepaintBoundary
      final wrapperState = repaintBoundaryKey.currentContext
          ?.findAncestorStateOfType<MapCaptureWrapperState>();
      if (wrapperState != null) {
        wrapperState.enableCaptureMode();
        await WidgetsBinding.instance.endOfFrame;
        await Future.delayed(const Duration(milliseconds: 100));
      }

      final boundary = repaintBoundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        wrapperState?.disableCaptureMode();
        if (context.mounted) _showError(context, 'לא ניתן לצלם את המפה');
        return null;
      }

      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      // כיבוי מצב צילום
      wrapperState?.disableCaptureMode();

      if (byteData == null) {
        if (context.mounted) _showError(context, 'שגיאה בהמרת התמונה');
        return null;
      }

      final imageBytes = byteData.buffer.asUint8List();

      // בניית PDF
      final regularFont = await PdfGoogleFonts.rubikRegular();
      final boldFont = await PdfGoogleFonts.rubikBold();

      final pdf = pw.Document(
        theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont),
      );
      final mapImage = pw.MemoryImage(imageBytes);

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          textDirection: pw.TextDirection.rtl,
          margin: const pw.EdgeInsets.all(20),
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (title != null)
                pw.Text(title,
                    style: pw.TextStyle(
                        fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Text(
                '${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
                style: pw.TextStyle(
                    font: regularFont,
                    fontSize: 9,
                    color: PdfColors.grey700),
              ),
              pw.SizedBox(height: 10),
              pw.Expanded(
                child: pw.Center(
                  child: pw.Image(mapImage, fit: pw.BoxFit.contain),
                ),
              ),
            ],
          ),
        ),
      );

      final pdfBytes = Uint8List.fromList(await pdf.save());
      final sanitizedName = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

      final result = await saveFileWithBytes(
        dialogTitle: 'ייצוא מפה ל-PDF',
        fileName: sanitizedName,
        bytes: pdfBytes,
        allowedExtensions: ['pdf'],
      );

      if (result != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('המפה יוצאה בהצלחה כ-PDF')),
        );
      }

      return result;
    } catch (e) {
      // כיבוי מצב צילום במקרה של שגיאה
      final wrapperState = repaintBoundaryKey.currentContext
          ?.findAncestorStateOfType<MapCaptureWrapperState>();
      wrapperState?.disableCaptureMode();

      if (context.mounted) _showError(context, 'שגיאה: $e');
      return null;
    }
  }

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }
}

/// ווידג'ט עוטף למפה — ללא RepaintBoundary כברירת מחדל.
/// RepaintBoundary נוסף רק בזמן צילום מסך כדי לא לחסום רנדור תקין של המפה.
class MapCaptureWrapper extends StatefulWidget {
  final GlobalKey captureKey;
  final Widget child;

  const MapCaptureWrapper({
    super.key,
    required this.captureKey,
    required this.child,
  });

  @override
  State<MapCaptureWrapper> createState() => MapCaptureWrapperState();
}

class MapCaptureWrapperState extends State<MapCaptureWrapper> {
  bool _captureMode = false;

  void enableCaptureMode() {
    if (mounted) setState(() => _captureMode = true);
  }

  void disableCaptureMode() {
    if (mounted) setState(() => _captureMode = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_captureMode) {
      return RepaintBoundary(
        key: widget.captureKey,
        child: widget.child,
      );
    }
    return KeyedSubtree(key: widget.captureKey, child: widget.child);
  }
}

/// כפתור ייצוא מפה — ניתן להוסיף לסרגל כלים
class MapExportButton extends StatelessWidget {
  final GlobalKey captureKey;
  final String navigationName;
  final String? navigatorName;

  const MapExportButton({
    super.key,
    required this.captureKey,
    this.navigationName = 'navigation',
    this.navigatorName,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.picture_as_pdf),
      tooltip: 'ייצוא מפה ל-PDF',
      onPressed: () async {
        final exporter = MapImageExport(repaintBoundaryKey: captureKey);
        final name = navigatorName != null
            ? '${navigationName}_$navigatorName'
            : navigationName;
        await exporter.exportAsPdf(
          context: context,
          fileName: '${name}_map.pdf',
          title: navigatorName != null
              ? '$navigationName — $navigatorName'
              : navigationName,
        );
      },
    );
  }
}
