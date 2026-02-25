import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../../core/utils/file_export_helper.dart';

/// ייצוא מפה כתמונה — לוכד צילום מסך של Widget כלשהו
class MapImageExport {
  /// מפתח לוויידג'ט שרוצים לצלם
  final GlobalKey repaintBoundaryKey;

  MapImageExport({required this.repaintBoundaryKey});

  /// צילום מסך וייצוא כ-PNG
  Future<String?> exportAsImage({
    required BuildContext context,
    String fileName = 'map_export.png',
    double pixelRatio = 2.0,
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

      final bytes = byteData.buffer.asUint8List();
      final sanitizedName = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

      final result = await saveFileWithBytes(
        dialogTitle: 'ייצוא מפה כתמונה',
        fileName: sanitizedName,
        bytes: Uint8List.fromList(bytes),
        allowedExtensions: ['png'],
      );

      if (result != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('התמונה יוצאה בהצלחה')),
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
    return widget.child;
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
      icon: const Icon(Icons.image),
      tooltip: 'ייצוא מפה כתמונה',
      onPressed: () async {
        final exporter = MapImageExport(repaintBoundaryKey: captureKey);
        final name = navigatorName != null
            ? '${navigationName}_$navigatorName'
            : navigationName;
        await exporter.exportAsImage(
          context: context,
          fileName: '${name}_map.png',
        );
      },
    );
  }
}
