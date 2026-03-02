import 'dart:convert';
import '../../core/map_config.dart';

/// רשומת הורדת מפה — מתעדת כל הורדה עם אפשרות חידוש
class MapDownloadRecord {
  final String id;
  final String boundaryName;
  final String mapType; // 'standard' / 'topographic' / 'satellite'
  final int minZoom;
  final int maxZoom;
  final String status; // 'downloading' / 'completed' / 'failed'
  final int totalTiles;
  final int downloadedTiles;
  final int failedTiles;
  final String createdAt; // ISO 8601
  final String boundsJson; // JSON {south, west, north, east}

  const MapDownloadRecord({
    required this.id,
    required this.boundaryName,
    required this.mapType,
    required this.minZoom,
    required this.maxZoom,
    required this.status,
    required this.totalTiles,
    required this.downloadedTiles,
    required this.failedTiles,
    required this.createdAt,
    required this.boundsJson,
  });

  /// תווית תצוגה — "דרום הרמה — טופוגרפית — זום 10-16"
  String get displayLabel {
    final mapConfig = MapConfig();
    final type = MapType.values.firstWhere(
      (t) => t.name == mapType,
      orElse: () => MapType.standard,
    );
    return '$boundaryName — ${mapConfig.label(type)} — זום $minZoom-$maxZoom';
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'boundaryName': boundaryName,
      'mapType': mapType,
      'minZoom': minZoom,
      'maxZoom': maxZoom,
      'status': status,
      'totalTiles': totalTiles,
      'downloadedTiles': downloadedTiles,
      'failedTiles': failedTiles,
      'createdAt': createdAt,
      'boundsJson': boundsJson,
    };
  }

  factory MapDownloadRecord.fromMap(Map<String, dynamic> map) {
    return MapDownloadRecord(
      id: map['id'] as String,
      boundaryName: map['boundaryName'] as String,
      mapType: map['mapType'] as String,
      minZoom: map['minZoom'] as int,
      maxZoom: map['maxZoom'] as int,
      status: map['status'] as String,
      totalTiles: map['totalTiles'] as int,
      downloadedTiles: map['downloadedTiles'] as int,
      failedTiles: map['failedTiles'] as int,
      createdAt: map['createdAt'] as String,
      boundsJson: map['boundsJson'] as String,
    );
  }

  MapDownloadRecord copyWith({
    String? id,
    String? boundaryName,
    String? mapType,
    int? minZoom,
    int? maxZoom,
    String? status,
    int? totalTiles,
    int? downloadedTiles,
    int? failedTiles,
    String? createdAt,
    String? boundsJson,
  }) {
    return MapDownloadRecord(
      id: id ?? this.id,
      boundaryName: boundaryName ?? this.boundaryName,
      mapType: mapType ?? this.mapType,
      minZoom: minZoom ?? this.minZoom,
      maxZoom: maxZoom ?? this.maxZoom,
      status: status ?? this.status,
      totalTiles: totalTiles ?? this.totalTiles,
      downloadedTiles: downloadedTiles ?? this.downloadedTiles,
      failedTiles: failedTiles ?? this.failedTiles,
      createdAt: createdAt ?? this.createdAt,
      boundsJson: boundsJson ?? this.boundsJson,
    );
  }

  /// המרת boundsJson ל-map של קואורדינטות
  Map<String, double> get boundsMap {
    final map = jsonDecode(boundsJson) as Map<String, dynamic>;
    return {
      'south': (map['south'] as num).toDouble(),
      'west': (map['west'] as num).toDouble(),
      'north': (map['north'] as num).toDouble(),
      'east': (map['east'] as num).toDouble(),
    };
  }
}
