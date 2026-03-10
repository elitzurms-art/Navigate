import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// סוגי תוואי שטח — תואם ל-C++ enum
enum TerrainFeatureType {
  flat, // מישור
  dome, // כיפה
  ridge, // רכס
  spur, // שלוחה
  valley, // ואדי / נחל
  channel, // ערוץ
  saddle, // אוכף
  slope, // מדרון
}

/// Extension — תוויות עבריות וצבעים
extension TerrainFeatureTypeExt on TerrainFeatureType {
  String get hebrewLabel {
    switch (this) {
      case TerrainFeatureType.flat:
        return 'מישור';
      case TerrainFeatureType.dome:
        return 'כיפה';
      case TerrainFeatureType.ridge:
        return 'רכס';
      case TerrainFeatureType.spur:
        return 'שלוחה';
      case TerrainFeatureType.valley:
        return 'ואדי';
      case TerrainFeatureType.channel:
        return 'ערוץ';
      case TerrainFeatureType.saddle:
        return 'אוכף';
      case TerrainFeatureType.slope:
        return 'מדרון';
    }
  }

  Color get color {
    switch (this) {
      case TerrainFeatureType.flat:
        return Colors.grey.shade300;
      case TerrainFeatureType.dome:
        return Colors.brown.shade700;
      case TerrainFeatureType.ridge:
        return Colors.orange.shade800;
      case TerrainFeatureType.spur:
        return Colors.orange.shade400;
      case TerrainFeatureType.valley:
        return Colors.blue.shade700;
      case TerrainFeatureType.channel:
        return Colors.blue.shade400;
      case TerrainFeatureType.saddle:
        return Colors.purple.shade400;
      case TerrainFeatureType.slope:
        return Colors.green.shade600;
    }
  }
}

/// סוגי נקודות תורפה
enum VulnerabilityType {
  cliff, // מצוק
  pit, // בור
  deepChannel, // תעלה עמוקה
  steepSlope, // מדרון תלול
}

extension VulnerabilityTypeExt on VulnerabilityType {
  String get hebrewLabel {
    switch (this) {
      case VulnerabilityType.cliff:
        return 'מצוק';
      case VulnerabilityType.pit:
        return 'בור';
      case VulnerabilityType.deepChannel:
        return 'תעלה עמוקה';
      case VulnerabilityType.steepSlope:
        return 'מדרון תלול';
    }
  }

  Color get color {
    switch (this) {
      case VulnerabilityType.cliff:
        return Colors.red.shade900;
      case VulnerabilityType.pit:
        return Colors.red.shade700;
      case VulnerabilityType.deepChannel:
        return Colors.red.shade500;
      case VulnerabilityType.steepSlope:
        return Colors.orange.shade700;
    }
  }

  IconData get icon {
    switch (this) {
      case VulnerabilityType.cliff:
        return Icons.warning_amber;
      case VulnerabilityType.pit:
        return Icons.arrow_downward;
      case VulnerabilityType.deepChannel:
        return Icons.water;
      case VulnerabilityType.steepSlope:
        return Icons.terrain;
    }
  }
}

/// סוגי נקודות ציון חכמות
enum SmartWaypointType {
  domeCenter, // מרכז כיפה
  hiddenDome, // כיפה סמויה
  streamSplit, // פיצול נחלים
  ridgePoint, // נקודת רכס
  spurTip, // קצה שלוחה
  valleyJunction, // צומת ואדיות
  saddlePoint, // אוכף
  localPeak, // פסגה מקומית
}

extension SmartWaypointTypeExt on SmartWaypointType {
  String get hebrewLabel {
    switch (this) {
      case SmartWaypointType.domeCenter:
        return 'מרכז כיפה';
      case SmartWaypointType.hiddenDome:
        return 'כיפה סמויה';
      case SmartWaypointType.streamSplit:
        return 'פיצול נחלים';
      case SmartWaypointType.ridgePoint:
        return 'נקודת רכס';
      case SmartWaypointType.spurTip:
        return 'קצה שלוחה';
      case SmartWaypointType.valleyJunction:
        return 'צומת ואדיות';
      case SmartWaypointType.saddlePoint:
        return 'אוכף';
      case SmartWaypointType.localPeak:
        return 'פסגה מקומית';
    }
  }

  Color get color {
    switch (this) {
      case SmartWaypointType.domeCenter:
        return Colors.brown.shade700;
      case SmartWaypointType.hiddenDome:
        return Colors.brown.shade400;
      case SmartWaypointType.streamSplit:
        return Colors.blue.shade600;
      case SmartWaypointType.ridgePoint:
        return Colors.orange.shade800;
      case SmartWaypointType.spurTip:
        return Colors.orange.shade400;
      case SmartWaypointType.valleyJunction:
        return Colors.blue.shade800;
      case SmartWaypointType.saddlePoint:
        return Colors.purple.shade600;
      case SmartWaypointType.localPeak:
        return Colors.red.shade600;
    }
  }

  IconData get icon {
    switch (this) {
      case SmartWaypointType.domeCenter:
        return Icons.filter_hdr;
      case SmartWaypointType.hiddenDome:
        return Icons.visibility_off;
      case SmartWaypointType.streamSplit:
        return Icons.call_split;
      case SmartWaypointType.ridgePoint:
        return Icons.trending_up;
      case SmartWaypointType.spurTip:
        return Icons.arrow_forward;
      case SmartWaypointType.valleyJunction:
        return Icons.merge_type;
      case SmartWaypointType.saddlePoint:
        return Icons.swap_vert;
      case SmartWaypointType.localPeak:
        return Icons.landscape;
    }
  }
}

/// תוצאת חישוב שיפוע ונטייה
class SlopeAspectResult {
  final Float32List slopeGrid;
  final Float32List aspectGrid;
  final int rows;
  final int cols;
  final LatLngBounds bounds;

  const SlopeAspectResult({
    required this.slopeGrid,
    required this.aspectGrid,
    required this.rows,
    required this.cols,
    required this.bounds,
  });

  /// המרת שורה/עמודה לקואורדינטה
  LatLng gridToLatLng(int row, int col) {
    final latStep = (bounds.north - bounds.south) / (rows - 1);
    final lngStep = (bounds.east - bounds.west) / (cols - 1);
    // שורה 0 = צפון (lat גבוה), שורה אחרונה = דרום
    return LatLng(bounds.north - row * latStep, bounds.west + col * lngStep);
  }

  /// שיפוע בנקודה
  double? slopeAt(double lat, double lng) {
    final rc = _latLngToGrid(lat, lng);
    if (rc == null) return null;
    return slopeGrid[rc.$1 * cols + rc.$2];
  }

  /// נטייה בנקודה
  double? aspectAt(double lat, double lng) {
    final rc = _latLngToGrid(lat, lng);
    if (rc == null) return null;
    return aspectGrid[rc.$1 * cols + rc.$2];
  }

  (int, int)? _latLngToGrid(double lat, double lng) {
    if (lat < bounds.south || lat > bounds.north) return null;
    if (lng < bounds.west || lng > bounds.east) return null;
    final latStep = (bounds.north - bounds.south) / (rows - 1);
    final lngStep = (bounds.east - bounds.west) / (cols - 1);
    final row = ((bounds.north - lat) / latStep).round().clamp(0, rows - 1);
    final col = ((lng - bounds.west) / lngStep).round().clamp(0, cols - 1);
    return (row, col);
  }
}

/// תוצאת סיווג תוואי שטח
class TerrainFeaturesResult {
  final Uint8List featureGrid;
  final int rows;
  final int cols;
  final LatLngBounds bounds;

  const TerrainFeaturesResult({
    required this.featureGrid,
    required this.rows,
    required this.cols,
    required this.bounds,
  });

  LatLng gridToLatLng(int row, int col) {
    final latStep = (bounds.north - bounds.south) / (rows - 1);
    final lngStep = (bounds.east - bounds.west) / (cols - 1);
    return LatLng(bounds.north - row * latStep, bounds.west + col * lngStep);
  }

  TerrainFeatureType? featureAt(double lat, double lng) {
    if (lat < bounds.south || lat > bounds.north) return null;
    if (lng < bounds.west || lng > bounds.east) return null;
    final latStep = (bounds.north - bounds.south) / (rows - 1);
    final lngStep = (bounds.east - bounds.west) / (cols - 1);
    final row = ((bounds.north - lat) / latStep).round().clamp(0, rows - 1);
    final col = ((lng - bounds.west) / lngStep).round().clamp(0, cols - 1);
    final val = featureGrid[row * cols + col];
    if (val >= TerrainFeatureType.values.length) return null;
    return TerrainFeatureType.values[val];
  }
}

/// תוצאת חישוב קו ראייה
class ViewshedResult {
  final Uint8List visibleGrid;
  final int rows;
  final int cols;
  final LatLngBounds bounds;
  final LatLng observerPosition;
  final double observerHeight;

  const ViewshedResult({
    required this.visibleGrid,
    required this.rows,
    required this.cols,
    required this.bounds,
    required this.observerPosition,
    required this.observerHeight,
  });

  LatLng gridToLatLng(int row, int col) {
    final latStep = (bounds.north - bounds.south) / (rows - 1);
    final lngStep = (bounds.east - bounds.west) / (cols - 1);
    return LatLng(bounds.north - row * latStep, bounds.west + col * lngStep);
  }

  bool? isVisibleAt(double lat, double lng) {
    if (lat < bounds.south || lat > bounds.north) return null;
    if (lng < bounds.west || lng > bounds.east) return null;
    final latStep = (bounds.north - bounds.south) / (rows - 1);
    final lngStep = (bounds.east - bounds.west) / (cols - 1);
    final row = ((bounds.north - lat) / latStep).round().clamp(0, rows - 1);
    final col = ((lng - bounds.west) / lngStep).round().clamp(0, cols - 1);
    return visibleGrid[row * cols + col] == 1;
  }
}

/// נקודת ציון חכמה
class SmartWaypoint {
  final LatLng position;
  final SmartWaypointType type;
  final double prominence;
  final int elevation;

  const SmartWaypoint({
    required this.position,
    required this.type,
    required this.prominence,
    required this.elevation,
  });
}

/// נקודת תורפה
class VulnerabilityPoint {
  final LatLng position;
  final VulnerabilityType type;
  final double severity;

  const VulnerabilityPoint({
    required this.position,
    required this.type,
    required this.severity,
  });
}

/// מסלול נסתר
class HiddenPath {
  final List<LatLng> points;
  final double totalDistanceMeters;
  final double exposurePercent;

  const HiddenPath({
    required this.points,
    required this.totalDistanceMeters,
    required this.exposurePercent,
  });
}

/// אזור תורפה — פוליגון המקיף מפגע גדול (מצוק, בור וכו')
class VulnerabilityZone {
  final List<LatLng> polygon;
  final VulnerabilityType type;
  final double severity;
  final int cellCount;

  const VulnerabilityZone({
    required this.polygon,
    required this.type,
    required this.severity,
    required this.cellCount,
  });
}
