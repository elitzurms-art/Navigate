import 'package:equatable/equatable.dart';
import 'coordinate.dart';

/// ישות נקודת ציון (שכבת NZ)
class Checkpoint extends Equatable {
  final String id;
  final String areaId;
  final String name;
  final String description;
  final String type; // 'checkpoint', 'mandatory_passage', 'start', 'end'
  final String color; // 'blue', 'green'
  final Coordinate coordinates;
  final int sequenceNumber;
  final List<String> labels; // תוויות/תאי שטח לשיוך לניווטים

  // הרשאות והיררכיה
  final String? unitId; // יחידה שיצרה
  final String? frameworkId; // מסגרת שיצרה
  final bool isPublic; // האם ציבורית לכל היחידות

  final String createdBy;
  final DateTime createdAt;

  const Checkpoint({
    required this.id,
    required this.areaId,
    required this.name,
    required this.description,
    required this.type,
    required this.color,
    required this.coordinates,
    required this.sequenceNumber,
    this.labels = const [],
    this.unitId,
    this.frameworkId,
    this.isPublic = false,
    required this.createdBy,
    required this.createdAt,
  });

  /// האם זו נקודת התחלה
  bool get isStart => type == 'start';

  /// האם זו נקודת סיום
  bool get isEnd => type == 'end';

  /// האם זו נקודת מעבר חובה
  bool get isMandatory => type == 'mandatory_passage';

  /// העתקה עם שינויים
  Checkpoint copyWith({
    String? id,
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
  }) {
    return Checkpoint(
      id: id ?? this.id,
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
    );
  }

  /// המרה ל-Map (Firestore)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
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
    };
  }

  /// יצירה מ-Map (Firestore)
  factory Checkpoint.fromMap(Map<String, dynamic> map) {
    return Checkpoint(
      id: map['id'] as String,
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
    );
  }

  @override
  List<Object?> get props => [
    id,
    areaId,
    name,
    description,
    type,
    color,
    coordinates,
    sequenceNumber,
    labels,
    createdBy,
    createdAt,
  ];

  @override
  String toString() => 'Checkpoint(id: $id, name: $name, type: $type, labels: $labels)';
}
