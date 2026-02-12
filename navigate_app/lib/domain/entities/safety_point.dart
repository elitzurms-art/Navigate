import 'package:equatable/equatable.dart';
import 'coordinate.dart';

/// נקודת תורפה בטיחותית (נת"ב) - Safety Vulnerability Point
/// נקודה או פוליגון אדום המסמן אזור מסוכן או חשוב לבטיחות
class SafetyPoint extends Equatable {
  final String id;
  final String areaId;
  final String name;
  final String description;
  final String type; // 'point' או 'polygon'
  final Coordinate? coordinates; // לנקודה בלבד
  final List<Coordinate>? polygonCoordinates; // לפוליגון בלבד
  final int sequenceNumber;
  final String severity; // 'low', 'medium', 'high', 'critical'
  final DateTime createdAt;
  final DateTime updatedAt;

  const SafetyPoint({
    required this.id,
    required this.areaId,
    required this.name,
    required this.description,
    this.type = 'point',
    this.coordinates,
    this.polygonCoordinates,
    required this.sequenceNumber,
    this.severity = 'medium',
    required this.createdAt,
    required this.updatedAt,
  }) : assert(
          (type == 'point' && coordinates != null && polygonCoordinates == null) ||
          (type == 'polygon' && polygonCoordinates != null && coordinates == null),
          'נקודה חייבת coordinates, פוליגון חייב polygonCoordinates',
        );

  @override
  List<Object?> get props => [
        id,
        areaId,
        name,
        description,
        type,
        coordinates,
        polygonCoordinates,
        sequenceNumber,
        severity,
        createdAt,
        updatedAt,
      ];

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'areaId': areaId,
      'name': name,
      'description': description,
      'type': type,
      if (coordinates != null) 'coordinates': coordinates!.toMap(),
      if (polygonCoordinates != null)
        'polygonCoordinates': polygonCoordinates!.map((c) => c.toMap()).toList(),
      'sequenceNumber': sequenceNumber,
      'severity': severity,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory SafetyPoint.fromMap(Map<String, dynamic> map) {
    return SafetyPoint(
      id: map['id'] as String,
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
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
    );
  }

  SafetyPoint copyWith({
    String? id,
    String? areaId,
    String? name,
    String? description,
    String? type,
    Coordinate? coordinates,
    List<Coordinate>? polygonCoordinates,
    int? sequenceNumber,
    String? severity,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SafetyPoint(
      id: id ?? this.id,
      areaId: areaId ?? this.areaId,
      name: name ?? this.name,
      description: description ?? this.description,
      type: type ?? this.type,
      coordinates: coordinates ?? this.coordinates,
      polygonCoordinates: polygonCoordinates ?? this.polygonCoordinates,
      sequenceNumber: sequenceNumber ?? this.sequenceNumber,
      severity: severity ?? this.severity,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
