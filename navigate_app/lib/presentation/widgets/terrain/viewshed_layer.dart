import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../../services/terrain/terrain_models.dart';
import 'terrain_overlay_layer.dart';

/// שכבת קו ראייה — ירוק שקוף = נראה, אדום שקוף = מוסתר.
/// כוללת סמן של נקודת התצפית (עיגול כתום עם אייקון עין).
class ViewshedLayer extends StatelessWidget {
  /// תוצאת חישוב קו ראייה
  final ViewshedResult data;

  /// שקיפות השכבה
  final double opacity;

  /// גודל תמונת התצוגה בפיקסלים (רוחב = גובה)
  final int displaySize;

  /// מסכת גבול — תאים מחוץ לגבול (ערך 0) יהיו שקופים
  final Uint8List? boundaryMask;

  const ViewshedLayer({
    super.key,
    required this.data,
    this.opacity = 0.5,
    this.displaySize = 500,
    this.boundaryMask,
  });

  /// צבע לתאים נראים — ירוק שקוף
  static const _visibleColor = Color(0x6000C853);

  /// צבע לתאים מוסתרים — אדום שקוף
  static const _hiddenColor = Color(0x60FF1744);

  @override
  Widget build(BuildContext context) {
    // יצירת פיקסלי RGBA מדוגמתים מרשת קו הראייה
    final rgbaPixels = TerrainOverlayLayer.downsampleGrid(
      gridRows: data.rows,
      gridCols: data.cols,
      displaySize: displaySize,
      boundaryMask: boundaryMask,
      colorAt: (row, col) {
        final index = row * data.cols + col;
        final isVisible = data.visibleGrid[index] == 1;
        return isVisible ? _visibleColor : _hiddenColor;
      },
    );

    // שילוב שכבת overlay עם סמן נקודת תצפית
    return Stack(
      children: [
        // שכבת תמונת קו ראייה
        TerrainOverlayLayer(
          rgbaPixels: rgbaPixels,
          imageWidth: displaySize,
          imageHeight: displaySize,
          bounds: data.bounds,
          opacity: opacity,
        ),
        // סמן נקודת תצפית
        MarkerLayer(
          markers: [
            Marker(
              point: data.observerPosition,
              width: 36,
              height: 36,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.orange.shade700,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.visibility,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
