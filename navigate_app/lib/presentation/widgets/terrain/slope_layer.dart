import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../services/terrain/terrain_models.dart';
import 'terrain_overlay_layer.dart';

/// שכבת שיפוע — צבעי gradient לפי זווית שיפוע.
/// ירוק = שטוח, צהוב = מתון, כתום = בינוני, אדום = תלול, סגול = מצוק.
class SlopeLayer extends StatelessWidget {
  /// תוצאת חישוב שיפוע וכיוון
  final SlopeAspectResult data;

  /// שקיפות השכבה
  final double opacity;

  /// גודל תמונת התצוגה בפיקסלים (רוחב = גובה)
  final int displaySize;

  /// ניגודיות — 0.0 (מינימום) עד 1.0 (מקסימום), ברירת מחדל 0.5
  final double contrast;

  /// מסכת גבול — תאים מחוץ לגבול (ערך 0) יהיו שקופים
  final Uint8List? boundaryMask;

  const SlopeLayer({
    super.key,
    required this.data,
    this.opacity = 0.6,
    this.displaySize = 500,
    this.contrast = 0.5,
    this.boundaryMask,
  });

  /// החזרת צבע לפי זווית שיפוע במעלות עם התאמת ניגודיות.
  /// ניגודיות גבוהה מורידה את הסף — שיפועים קטנים נראים יותר.
  /// ניגודיות נמוכה מעלה את הסף — רק שיפועים חדים בולטים.
  static Color slopeColor(double degrees, {double contrast = 0.5}) {
    final factor = 1.0 - contrast * 0.8;
    final t1 = 5.0 * factor;
    final t2 = 15.0 * factor;
    final t3 = 30.0 * factor;
    final t4 = 45.0 * factor;

    if (degrees < t1) {
      return const Color(0xFF4CAF50);
    }
    if (degrees < t2) {
      return Color.lerp(const Color(0xFF4CAF50), const Color(0xFFFFEB3B), (degrees - t1) / (t2 - t1))!;
    }
    if (degrees < t3) {
      return Color.lerp(const Color(0xFFFFEB3B), const Color(0xFFFF5722), (degrees - t2) / (t3 - t2))!;
    }
    if (degrees < t4) {
      return Color.lerp(const Color(0xFFFF5722), const Color(0xFFD32F2F), (degrees - t3) / (t4 - t3))!;
    }
    return const Color(0xFF880E4F);
  }

  @override
  Widget build(BuildContext context) {
    // יצירת פיקסלי RGBA מדוגמתים מרשת השיפוע
    final rgbaPixels = TerrainOverlayLayer.downsampleGrid(
      gridRows: data.rows,
      gridCols: data.cols,
      displaySize: displaySize,
      boundaryMask: boundaryMask,
      colorAt: (row, col) {
        // חילוץ ערך שיפוע מהרשת הליניארית
        final index = row * data.cols + col;
        final slopeDegrees = data.slopeGrid[index];
        return slopeColor(slopeDegrees, contrast: contrast);
      },
    );

    return TerrainOverlayLayer(
      rgbaPixels: rgbaPixels,
      imageWidth: displaySize,
      imageHeight: displaySize,
      bounds: data.bounds,
      opacity: opacity,
    );
  }
}
