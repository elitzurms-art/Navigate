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
      final boundary = repaintBoundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        _showError(context, 'לא ניתן לצלם את המפה');
        return null;
      }

      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        _showError(context, 'שגיאה בהמרת התמונה');
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

/// ווידג'ט עוטף ל-RepaintBoundary — עוטף את המפה לצילום מסך
class MapCaptureWrapper extends StatelessWidget {
  final GlobalKey captureKey;
  final Widget child;

  const MapCaptureWrapper({
    super.key,
    required this.captureKey,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: captureKey,
      child: child,
    );
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
