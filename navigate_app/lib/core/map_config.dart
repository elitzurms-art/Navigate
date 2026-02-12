import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// סוגי מפה זמינים
enum MapType {
  standard,
  topographic,
  satellite,
}

/// קונפיגורציית מפה גלובלית — singleton
class MapConfig {
  static final MapConfig _instance = MapConfig._internal();
  factory MapConfig() => _instance;
  MapConfig._internal();

  static const _prefsKey = 'map_tile_type';
  static const userAgentPackageName = 'com.elitzur_software.navigate';

  /// notifier שכל המפות מאזינות לו
  final ValueNotifier<MapType> typeNotifier =
      ValueNotifier<MapType>(MapType.standard);

  MapType get currentType => typeNotifier.value;

  /// טעינה מ-SharedPreferences
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    if (saved != null) {
      typeNotifier.value = MapType.values.firstWhere(
        (t) => t.name == saved,
        orElse: () => MapType.standard,
      );
    }
  }

  /// שינוי סוג מפה ושמירה
  Future<void> setType(MapType type) async {
    typeNotifier.value = type;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, type.name);
  }

  /// URL template לפי סוג מפה
  String urlTemplate(MapType type) {
    switch (type) {
      case MapType.standard:
        return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
      case MapType.topographic:
        return 'https://tile.opentopomap.org/{z}/{x}/{y}.png';
      case MapType.satellite:
        return 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
    }
  }

  /// maxZoom לפי סוג מפה (OpenTopoMap תומך עד 17 בלבד)
  double maxZoom(MapType type) {
    switch (type) {
      case MapType.standard:
        return 19;
      case MapType.topographic:
        return 17;
      case MapType.satellite:
        return 19;
    }
  }

  /// גודל אריח משוער ב-KB לפי סוג מפה
  double estimatedTileSizeKB(MapType type) {
    switch (type) {
      case MapType.standard:
        return 15.0;
      case MapType.topographic:
        return 25.0;
      case MapType.satellite:
        return 40.0;
    }
  }

  /// תווית בעברית
  String label(MapType type) {
    switch (type) {
      case MapType.standard:
        return 'רגילה';
      case MapType.topographic:
        return 'טופוגרפית';
      case MapType.satellite:
        return 'לוויין';
    }
  }
}
