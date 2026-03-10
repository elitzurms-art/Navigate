import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
/// שכבת overlay בסיסית — ממירה רשת ערכים לתמונה צבעונית על המפה.
/// מקבלת מערך RGBA ומציגה אותו כשכבת תמונה שקופה מעל אריחי המפה.
class TerrainOverlayLayer extends StatefulWidget {
  /// רשת RGBA — כל פיקסל 4 בייטים (R,G,B,A)
  final Uint8List rgbaPixels;

  /// רוחב התמונה (פיקסלים)
  final int imageWidth;

  /// גובה התמונה (פיקסלים)
  final int imageHeight;

  /// גבולות גאוגרפיים של התמונה
  final LatLngBounds bounds;

  /// שקיפות השכבה (0.0 עד 1.0)
  final double opacity;

  const TerrainOverlayLayer({
    super.key,
    required this.rgbaPixels,
    required this.imageWidth,
    required this.imageHeight,
    required this.bounds,
    this.opacity = 0.6,
  });

  @override
  State<TerrainOverlayLayer> createState() => _TerrainOverlayLayerState();

  /// יצירת רשת RGBA מדוגמתת מרשת גדולה.
  /// מדגום רשת [gridRows]×[gridCols] לגודל [displaySize]×[displaySize]
  /// באמצעות דגימת שכן קרוב (nearest-neighbor).
  static Uint8List downsampleGrid({
    required int gridRows,
    required int gridCols,
    required int displaySize,
    required Color Function(int row, int col) colorAt,
    Uint8List? boundaryMask,
  }) {
    // הקצאת מערך RGBA — 4 בייטים לכל פיקסל
    final pixels = Uint8List(displaySize * displaySize * 4);

    for (int y = 0; y < displaySize; y++) {
      // מיפוי פיקסל תצוגה לשורת רשת מקורית
      final row = (y * gridRows ~/ displaySize).clamp(0, gridRows - 1);

      for (int x = 0; x < displaySize; x++) {
        // מיפוי פיקסל תצוגה לעמודת רשת מקורית
        final col = (x * gridCols ~/ displaySize).clamp(0, gridCols - 1);

        final offset = (y * displaySize + x) * 4;

        // בדיקת מסכת גבול — תאים מחוץ לגבול שקופים
        if (boundaryMask != null && boundaryMask[row * gridCols + col] == 0) {
          // Outside boundary — transparent
          pixels[offset] = 0;
          pixels[offset + 1] = 0;
          pixels[offset + 2] = 0;
          pixels[offset + 3] = 0;
          continue;
        }

        final color = colorAt(row, col);

        pixels[offset] = (color.r * 255).round();
        pixels[offset + 1] = (color.g * 255).round();
        pixels[offset + 2] = (color.b * 255).round();
        pixels[offset + 3] = (color.a * 255).round();
      }
    }

    return pixels;
  }
}

class _TerrainOverlayLayerState extends State<TerrainOverlayLayer> {
  /// בייטים של תמונת PNG מקודדת
  Uint8List? _pngBytes;

  /// האם התמונה בתהליך יצירה
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _generateImage();
  }

  @override
  void didUpdateWidget(TerrainOverlayLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // יצירה מחדש אם הנתונים השתנו
    if (oldWidget.rgbaPixels != widget.rgbaPixels ||
        oldWidget.imageWidth != widget.imageWidth ||
        oldWidget.imageHeight != widget.imageHeight) {
      _generateImage();
    }
  }

  /// המרת פיקסלי RGBA לתמונת PNG באמצעות dart:ui
  Future<void> _generateImage() async {
    if (_isGenerating) return;
    _isGenerating = true;

    try {
      // פענוח פיקסלים לאובייקט תמונה
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        widget.rgbaPixels,
        widget.imageWidth,
        widget.imageHeight,
        ui.PixelFormat.rgba8888,
        (ui.Image image) {
          completer.complete(image);
        },
      );

      final image = await completer.future;

      // המרה לפורמט PNG
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();

      if (byteData == null) return;

      if (mounted) {
        setState(() {
          _pngBytes = byteData.buffer.asUint8List();
        });
      }
    } finally {
      _isGenerating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // הצגת מיכל ריק בזמן יצירת התמונה
    if (_pngBytes == null) {
      return const SizedBox.shrink();
    }

    return OverlayImageLayer(
      overlayImages: [
        OverlayImage(
          bounds: widget.bounds,
          imageProvider: MemoryImage(_pngBytes!),
          opacity: widget.opacity,
        ),
      ],
    );
  }
}
