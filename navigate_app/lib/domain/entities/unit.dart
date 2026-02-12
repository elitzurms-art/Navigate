import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

/// יחידה צבאית
class Unit extends Equatable {
  final String id;
  final String name;
  final String description;
  final String type; // 'brigade', 'battalion', 'company', 'platoon'
  final String? parentUnitId; // יחידת אב (אם קיימת)
  final List<String> managerIds; // מנהלי המערכת של היחידה
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isClassified; // יחידה מסווגת — לא מוצגת לאחרים
  final int? level; // רמת היחידה (1=אוגדה .. 5=מחלקה)
  final bool isNavigators; // יחידת מנווטים
  final bool isGeneral; // יחידה כללית

  const Unit({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    this.parentUnitId,
    required this.managerIds,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.isClassified = false,
    this.level,
    this.isNavigators = false,
    this.isGeneral = false,
  });

  Unit copyWith({
    String? id,
    String? name,
    String? description,
    String? type,
    String? parentUnitId,
    List<String>? managerIds,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isClassified,
    int? level,
    bool? isNavigators,
    bool? isGeneral,
  }) {
    return Unit(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      type: type ?? this.type,
      parentUnitId: parentUnitId ?? this.parentUnitId,
      managerIds: managerIds ?? this.managerIds,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isClassified: isClassified ?? this.isClassified,
      level: level ?? this.level,
      isNavigators: isNavigators ?? this.isNavigators,
      isGeneral: isGeneral ?? this.isGeneral,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'type': type,
      if (parentUnitId != null) 'parentUnitId': parentUnitId,
      'managerIds': managerIds,
      'createdBy': createdBy,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'isClassified': isClassified,
      if (level != null) 'level': level,
      'isNavigators': isNavigators,
      'isGeneral': isGeneral,
    };
  }

  factory Unit.fromMap(Map<String, dynamic> map) {
    return Unit(
      id: map['id'] as String,
      name: map['name'] as String,
      description: map['description'] as String,
      type: map['type'] as String,
      parentUnitId: map['parentUnitId'] as String?,
      managerIds: List<String>.from(map['managerIds'] as List),
      createdBy: map['createdBy'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
      isClassified: map['isClassified'] as bool? ?? false,
      level: (map['level'] as num?)?.toInt(),
      isNavigators: map['isNavigators'] as bool? ?? false,
      isGeneral: map['isGeneral'] as bool? ?? false,
    );
  }

  @override
  List<Object?> get props => [id, name, type, parentUnitId, updatedAt, isClassified, level, isNavigators, isGeneral];

  /// קבלת שם סוג היחידה
  String getTypeName() {
    switch (type) {
      case 'brigade':
        return 'חטיבה';
      case 'battalion':
        return 'גדוד';
      case 'company':
        return 'פלוגה';
      case 'platoon':
        return 'מחלקה';
      default:
        return type;
    }
  }

  /// אייקון לפי סוג
  IconData getIcon() {
    switch (type) {
      case 'brigade':
        return Icons.military_tech;
      case 'battalion':
        return Icons.shield;
      case 'company':
        return Icons.group;
      case 'platoon':
        return Icons.groups;
      default:
        return Icons.business;
    }
  }
}
