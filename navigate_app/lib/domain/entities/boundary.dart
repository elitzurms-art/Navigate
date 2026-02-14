import 'package:equatable/equatable.dart';
import 'coordinate.dart';

/// גבול גזרה (ג"ג) - Boundary
/// פוליגון שחור המגדיר את גבולות האזור
class Boundary extends Equatable {
  final String id;
  final String areaId;
  final String name;
  final String description;
  final List<Coordinate> coordinates; // רשימת קואורדינטות המגדירות את הפוליגון
  final String color; // ברירת מחדל: שחור
  final double strokeWidth; // עובי הקו
  final DateTime createdAt;
  final DateTime updatedAt;

  const Boundary({
    required this.id,
    required this.areaId,
    required this.name,
    required this.description,
    required this.coordinates,
    this.color = 'black',
    this.strokeWidth = 3.0,
    required this.createdAt,
    required this.updatedAt,
  });

  @override
  List<Object?> get props => [
        id,
        areaId,
        name,
        description,
        coordinates,
        color,
        strokeWidth,
        createdAt,
        updatedAt,
      ];

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'areaId': areaId,
      'name': name,
      'description': description,
      'coordinates': coordinates.map((c) => c.toMap()).toList(),
      'color': color,
      'strokeWidth': strokeWidth,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory Boundary.fromMap(Map<String, dynamic> map) {
    return Boundary(
      id: map['id'] as String,
      areaId: map['areaId'] as String,
      name: map['name'] as String,
      description: map['description'] as String? ?? '',
      coordinates: (map['coordinates'] as List)
          .map((c) => Coordinate.fromMap(c as Map<String, dynamic>))
          .toList(),
      color: map['color'] as String? ?? 'black',
      strokeWidth: (map['strokeWidth'] as num?)?.toDouble() ?? 3.0,
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
    );
  }

  Boundary copyWith({
    String? id,
    String? areaId,
    String? name,
    String? description,
    List<Coordinate>? coordinates,
    String? color,
    double? strokeWidth,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Boundary(
      id: id ?? this.id,
      areaId: areaId ?? this.areaId,
      name: name ?? this.name,
      description: description ?? this.description,
      coordinates: coordinates ?? this.coordinates,
      color: color ?? this.color,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
