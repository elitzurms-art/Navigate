import 'package:equatable/equatable.dart';
import 'coordinate.dart';

/// ביצת איזור (ב"א) - Cluster/Area Cell
/// פוליגון ירוק המגדיר תא שטח או אזור
class Cluster extends Equatable {
  final String id;
  final String areaId;
  final String name;
  final String description;
  final List<Coordinate> coordinates; // רשימת קואורדינטות המגדירות את הפוליגון
  final String color; // ברירת מחדל: ירוק
  final double strokeWidth; // עובי הקו
  final double fillOpacity; // שקיפות המילוי (0.0 - 1.0)
  final DateTime createdAt;
  final DateTime updatedAt;

  const Cluster({
    required this.id,
    required this.areaId,
    required this.name,
    required this.description,
    required this.coordinates,
    this.color = 'green',
    this.strokeWidth = 2.0,
    this.fillOpacity = 0.2,
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
        fillOpacity,
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
      'fillOpacity': fillOpacity,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory Cluster.fromMap(Map<String, dynamic> map) {
    return Cluster(
      id: map['id'] as String,
      areaId: map['areaId'] as String,
      name: map['name'] as String,
      description: map['description'] as String? ?? '',
      coordinates: (map['coordinates'] as List)
          .map((c) => Coordinate.fromMap(c as Map<String, dynamic>))
          .toList(),
      color: map['color'] as String? ?? 'green',
      strokeWidth: (map['strokeWidth'] as num?)?.toDouble() ?? 2.0,
      fillOpacity: (map['fillOpacity'] as num?)?.toDouble() ?? 0.2,
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
    );
  }

  Cluster copyWith({
    String? id,
    String? areaId,
    String? name,
    String? description,
    List<Coordinate>? coordinates,
    String? color,
    double? strokeWidth,
    double? fillOpacity,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Cluster(
      id: id ?? this.id,
      areaId: areaId ?? this.areaId,
      name: name ?? this.name,
      description: description ?? this.description,
      coordinates: coordinates ?? this.coordinates,
      color: color ?? this.color,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      fillOpacity: fillOpacity ?? this.fillOpacity,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
