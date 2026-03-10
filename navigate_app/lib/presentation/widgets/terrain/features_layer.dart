import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../services/terrain/terrain_models.dart';
import 'terrain_overlay_layer.dart';

/// שכבת סיווג תוואי שטח — כל סוג תוואי מוצג בצבע שונה.
/// הצבעים נלקחים מה-extension של [TerrainFeatureType].
/// שטוח (flat) ומדרון (slope) מוצגים שקופים — רק תוואים בולטים נראים.
class FeaturesLayer extends StatelessWidget {
  /// תוצאת סיווג תוואי שטח
  final TerrainFeaturesResult data;

  /// שקיפות השכבה
  final double opacity;

  /// גודל תמונת התצוגה בפיקסלים (רוחב = גובה)
  final int displaySize;

  /// מסכת גבול — תאים מחוץ לגבול (ערך 0) יהיו שקופים
  final Uint8List? boundaryMask;

  const FeaturesLayer({
    super.key,
    required this.data,
    this.opacity = 0.6,
    this.displaySize = 500,
    this.boundaryMask,
  });

  @override
  Widget build(BuildContext context) {
    // רשימת סוגי תוואי שטח לפי אינדקס
    final featureTypes = TerrainFeatureType.values;

    // יצירת פיקסלי RGBA מדוגמתים מרשת הסיווג
    final rgbaPixels = TerrainOverlayLayer.downsampleGrid(
      gridRows: data.rows,
      gridCols: data.cols,
      displaySize: displaySize,
      boundaryMask: boundaryMask,
      colorAt: (row, col) {
        // חילוץ סוג תוואי מהרשת
        final index = row * data.cols + col;
        final featureIndex = data.featureGrid[index];

        // בדיקה שהאינדקס תקין
        if (featureIndex >= featureTypes.length) {
          return Colors.transparent;
        }

        final featureType = featureTypes[featureIndex];
        // שטוח ומדרון שקופים — רק תוואים בולטים מוצגים
        if (featureType == TerrainFeatureType.flat || featureType == TerrainFeatureType.slope) {
          return Colors.transparent;
        }
        return featureType.color;
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
