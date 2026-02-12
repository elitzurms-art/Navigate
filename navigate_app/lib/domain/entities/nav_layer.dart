import 'package:equatable/equatable.dart';
import 'coordinate.dart';

/// נקודת ציון לניווט ספציפי (עותק מקומי לניווט)
/// כל שכבות הניווט מאוחסנות עם sourceId שמצביע על המקור הגלובלי
class NavCheckpoint extends Equatable {
  final String id;
  final String navigationId;
  final String sourceId; // מזהה נקודת הציון המקורית (גלובלית)
  final String areaId;
  final String name;
  final String description;
  final String type; // 'checkpoint', 'mandatory_passage', 'start', 'end'
  final String color; // 'blue', 'green'
  final Coordinate coordinates;
  final int sequenceNumber;
  final List<String> labels;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  const NavCheckpoint({
    required this.id,
    required this.navigationId,
    required this.sourceId,
    required this.areaId,
    required this.name,
    required this.description,
    required this.type,
    required this.color,
    required this.coordinates,
    required this.sequenceNumber,
    this.labels = const [],
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  NavCheckpoint copyWith({
    String? id,
    String? navigationId,
    String? sourceId,
    String? areaId,
    String? name,
    String? description,
    String? type,
    String? color,
    Coordinate? coordinates,
    int? sequenceNumber,
    List<String>? labels,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return NavCheckpoint(
      id: id ?? this.id,
      navigationId: navigationId ?? this.navigationId,
      sourceId: sourceId ?? this.sourceId,
      areaId: areaId ?? this.areaId,
      name: name ?? this.name,
      description: description ?? this.description,
      type: type ?? this.type,
      color: color ?? this.color,
      coordinates: coordinates ?? this.coordinates,
      sequenceNumber: sequenceNumber ?? this.sequenceNumber,
      labels: labels ?? this.labels,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'navigationId': navigationId,
      'sourceId': sourceId,
      'areaId': areaId,
      'name': name,
      'description': description,
      'type': type,
      'color': color,
      'coordinates': coordinates.toMap(),
      'sequenceNumber': sequenceNumber,
      'labels': labels,
      'createdBy': createdBy,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory NavCheckpoint.fromMap(Map<String, dynamic> map) {
    return NavCheckpoint(
      id: map['id'] as String,
      navigationId: map['navigationId'] as String,
      sourceId: map['sourceId'] as String,
      areaId: map['areaId'] as String,
      name: map['name'] as String,
      description: map['description'] as String,
      type: map['type'] as String,
      color: map['color'] as String,
      coordinates: Coordinate.fromMap(map['coordinates'] as Map<String, dynamic>),
      sequenceNumber: map['sequenceNumber'] as int,
      labels: map['labels'] != null ? List<String>.from(map['labels'] as List) : [],
      createdBy: map['createdBy'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
    );
  }

  @override
  List<Object?> get props => [
        id, navigationId, sourceId, areaId, name, description,
        type, color, coordinates, sequenceNumber, labels,
        createdBy, createdAt, updatedAt,
      ];
}

/// נקודת תורפה בטיחותית לניווט ספציפי
class NavSafetyPoint extends Equatable {
  final String id;
  final String navigationId;
  final String sourceId;
  final String areaId;
  final String name;
  final String description;
  final String type; // 'point' או 'polygon'
  final Coordinate? coordinates;
  final List<Coordinate>? polygonCoordinates;
  final int sequenceNumber;
  final String severity;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  const NavSafetyPoint({
    required this.id,
    required this.navigationId,
    required this.sourceId,
    required this.areaId,
    required this.name,
    required this.description,
    this.type = 'point',
    this.coordinates,
    this.polygonCoordinates,
    required this.sequenceNumber,
    this.severity = 'medium',
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  NavSafetyPoint copyWith({
    String? id,
    String? navigationId,
    String? sourceId,
    String? areaId,
    String? name,
    String? description,
    String? type,
    Coordinate? coordinates,
    List<Coordinate>? polygonCoordinates,
    int? sequenceNumber,
    String? severity,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return NavSafetyPoint(
      id: id ?? this.id,
      navigationId: navigationId ?? this.navigationId,
      sourceId: sourceId ?? this.sourceId,
      areaId: areaId ?? this.areaId,
      name: name ?? this.name,
      description: description ?? this.description,
      type: type ?? this.type,
      coordinates: coordinates ?? this.coordinates,
      polygonCoordinates: polygonCoordinates ?? this.polygonCoordinates,
      sequenceNumber: sequenceNumber ?? this.sequenceNumber,
      severity: severity ?? this.severity,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'navigationId': navigationId,
      'sourceId': sourceId,
      'areaId': areaId,
      'name': name,
      'description': description,
      'type': type,
      if (coordinates != null) 'coordinates': coordinates!.toMap(),
      if (polygonCoordinates != null)
        'polygonCoordinates': polygonCoordinates!.map((c) => c.toMap()).toList(),
      'sequenceNumber': sequenceNumber,
      'severity': severity,
      'createdBy': createdBy,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory NavSafetyPoint.fromMap(Map<String, dynamic> map) {
    return NavSafetyPoint(
      id: map['id'] as String,
      navigationId: map['navigationId'] as String,
      sourceId: map['sourceId'] as String,
      areaId: map['areaId'] as String,
      name: map['name'] as String,
      description: map['description'] as String? ?? '',
      type: map['type'] as String? ?? 'point',
      coordinates: map['coordinates'] != null
          ? Coordinate.fromMap(map['coordinates'] as Map<String, dynamic>)
          : null,
      polygonCoordinates: map['polygonCoordinates'] != null
          ? (map['polygonCoordinates'] as List)
              .map((c) => Coordinate.fromMap(c as Map<String, dynamic>))
              .toList()
          : null,
      sequenceNumber: map['sequenceNumber'] as int,
      severity: map['severity'] as String? ?? 'medium',
      createdBy: map['createdBy'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
    );
  }

  @override
  List<Object?> get props => [
        id, navigationId, sourceId, areaId, name, description,
        type, coordinates, polygonCoordinates, sequenceNumber,
        severity, createdBy, createdAt, updatedAt,
      ];
}

/// גבול גזרה לניווט ספציפי
class NavBoundary extends Equatable {
  final String id;
  final String navigationId;
  final String sourceId;
  final String areaId;
  final String name;
  final String description;
  final List<Coordinate> coordinates;
  final String color;
  final double strokeWidth;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  const NavBoundary({
    required this.id,
    required this.navigationId,
    required this.sourceId,
    required this.areaId,
    required this.name,
    required this.description,
    required this.coordinates,
    this.color = 'black',
    this.strokeWidth = 3.0,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  NavBoundary copyWith({
    String? id,
    String? navigationId,
    String? sourceId,
    String? areaId,
    String? name,
    String? description,
    List<Coordinate>? coordinates,
    String? color,
    double? strokeWidth,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return NavBoundary(
      id: id ?? this.id,
      navigationId: navigationId ?? this.navigationId,
      sourceId: sourceId ?? this.sourceId,
      areaId: areaId ?? this.areaId,
      name: name ?? this.name,
      description: description ?? this.description,
      coordinates: coordinates ?? this.coordinates,
      color: color ?? this.color,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'navigationId': navigationId,
      'sourceId': sourceId,
      'areaId': areaId,
      'name': name,
      'description': description,
      'coordinates': coordinates.map((c) => c.toMap()).toList(),
      'color': color,
      'strokeWidth': strokeWidth,
      'createdBy': createdBy,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory NavBoundary.fromMap(Map<String, dynamic> map) {
    return NavBoundary(
      id: map['id'] as String,
      navigationId: map['navigationId'] as String,
      sourceId: map['sourceId'] as String,
      areaId: map['areaId'] as String,
      name: map['name'] as String,
      description: map['description'] as String? ?? '',
      coordinates: (map['coordinates'] as List)
          .map((c) => Coordinate.fromMap(c as Map<String, dynamic>))
          .toList(),
      color: map['color'] as String? ?? 'black',
      strokeWidth: (map['strokeWidth'] as num?)?.toDouble() ?? 3.0,
      createdBy: map['createdBy'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
    );
  }

  @override
  List<Object?> get props => [
        id, navigationId, sourceId, areaId, name, description,
        coordinates, color, strokeWidth, createdBy, createdAt, updatedAt,
      ];
}

/// ביצת איזור לניווט ספציפי
class NavCluster extends Equatable {
  final String id;
  final String navigationId;
  final String sourceId;
  final String areaId;
  final String name;
  final String description;
  final List<Coordinate> coordinates;
  final String color;
  final double strokeWidth;
  final double fillOpacity;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  const NavCluster({
    required this.id,
    required this.navigationId,
    required this.sourceId,
    required this.areaId,
    required this.name,
    required this.description,
    required this.coordinates,
    this.color = 'green',
    this.strokeWidth = 2.0,
    this.fillOpacity = 0.2,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  NavCluster copyWith({
    String? id,
    String? navigationId,
    String? sourceId,
    String? areaId,
    String? name,
    String? description,
    List<Coordinate>? coordinates,
    String? color,
    double? strokeWidth,
    double? fillOpacity,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return NavCluster(
      id: id ?? this.id,
      navigationId: navigationId ?? this.navigationId,
      sourceId: sourceId ?? this.sourceId,
      areaId: areaId ?? this.areaId,
      name: name ?? this.name,
      description: description ?? this.description,
      coordinates: coordinates ?? this.coordinates,
      color: color ?? this.color,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      fillOpacity: fillOpacity ?? this.fillOpacity,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'navigationId': navigationId,
      'sourceId': sourceId,
      'areaId': areaId,
      'name': name,
      'description': description,
      'coordinates': coordinates.map((c) => c.toMap()).toList(),
      'color': color,
      'strokeWidth': strokeWidth,
      'fillOpacity': fillOpacity,
      'createdBy': createdBy,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory NavCluster.fromMap(Map<String, dynamic> map) {
    return NavCluster(
      id: map['id'] as String,
      navigationId: map['navigationId'] as String,
      sourceId: map['sourceId'] as String,
      areaId: map['areaId'] as String,
      name: map['name'] as String,
      description: map['description'] as String? ?? '',
      coordinates: (map['coordinates'] as List)
          .map((c) => Coordinate.fromMap(c as Map<String, dynamic>))
          .toList(),
      color: map['color'] as String? ?? 'green',
      strokeWidth: (map['strokeWidth'] as num?)?.toDouble() ?? 2.0,
      fillOpacity: (map['fillOpacity'] as num?)?.toDouble() ?? 0.2,
      createdBy: map['createdBy'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
    );
  }

  @override
  List<Object?> get props => [
        id, navigationId, sourceId, areaId, name, description,
        coordinates, color, strokeWidth, fillOpacity, createdBy, createdAt, updatedAt,
      ];
}
