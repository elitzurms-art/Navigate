import 'package:equatable/equatable.dart';

/// ישות שטח
class Area extends Equatable {
  final String id;
  final String name;
  final String description;
  final String createdBy;
  final DateTime createdAt;

  const Area({
    required this.id,
    required this.name,
    required this.description,
    required this.createdBy,
    required this.createdAt,
  });

  /// העתקה עם שינויים
  Area copyWith({
    String? id,
    String? name,
    String? description,
    String? createdBy,
    DateTime? createdAt,
  }) {
    return Area(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// המרה ל-Map (Firestore)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'createdBy': createdBy,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  /// יצירה מ-Map (Firestore)
  factory Area.fromMap(Map<String, dynamic> map) {
    return Area(
      id: map['id'] as String,
      name: map['name'] as String,
      description: map['description'] as String,
      createdBy: map['createdBy'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }

  @override
  List<Object?> get props => [id, name, description, createdBy, createdAt];

  @override
  String toString() => 'Area(id: $id, name: $name)';
}
