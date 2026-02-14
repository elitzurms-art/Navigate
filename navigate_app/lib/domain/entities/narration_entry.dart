import 'package:equatable/equatable.dart';

/// שורה בטבלת סיפור דרך
class NarrationEntry extends Equatable {
  final int index;            // מסד (1,2,3...)
  final String segmentKm;    // מקטע (ק"מ) — מרחק בין נקודה קודמת לנוכחית
  final String pointName;    // שם הנקודה
  final String cumulativeKm; // מרחק מצטבר (ק"מ)
  final String bearing;      // כיוון (מעלות + מילולי)
  final String description;  // תיאור הדרך וסימנים בשטח (עריך)
  final String action;       // פעולה נדרשת (עריך)
  final double? elevationM;  // גובה במטרים (הזנה ידנית)
  final double? walkingTimeMin; // זמן הליכה בדקות (מחושב)
  final String obstacles;    // מכשולים/מגבלות (עריך)

  const NarrationEntry({
    required this.index,
    this.segmentKm = '',
    required this.pointName,
    this.cumulativeKm = '',
    this.bearing = '',
    this.description = '',
    this.action = '',
    this.elevationM,
    this.walkingTimeMin,
    this.obstacles = '',
  });

  NarrationEntry copyWith({
    int? index,
    String? segmentKm,
    String? pointName,
    String? cumulativeKm,
    String? bearing,
    String? description,
    String? action,
    double? elevationM,
    bool clearElevation = false,
    double? walkingTimeMin,
    bool clearWalkingTime = false,
    String? obstacles,
  }) {
    return NarrationEntry(
      index: index ?? this.index,
      segmentKm: segmentKm ?? this.segmentKm,
      pointName: pointName ?? this.pointName,
      cumulativeKm: cumulativeKm ?? this.cumulativeKm,
      bearing: bearing ?? this.bearing,
      description: description ?? this.description,
      action: action ?? this.action,
      elevationM: clearElevation ? null : (elevationM ?? this.elevationM),
      walkingTimeMin: clearWalkingTime ? null : (walkingTimeMin ?? this.walkingTimeMin),
      obstacles: obstacles ?? this.obstacles,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'index': index,
      'segmentKm': segmentKm,
      'pointName': pointName,
      'cumulativeKm': cumulativeKm,
      'bearing': bearing,
      'description': description,
      'action': action,
      if (elevationM != null) 'elevationM': elevationM,
      if (walkingTimeMin != null) 'walkingTimeMin': walkingTimeMin,
      'obstacles': obstacles,
    };
  }

  factory NarrationEntry.fromMap(Map<String, dynamic> map) {
    return NarrationEntry(
      index: map['index'] as int,
      segmentKm: map['segmentKm'] as String? ?? '',
      pointName: map['pointName'] as String? ?? '',
      cumulativeKm: map['cumulativeKm'] as String? ?? '',
      bearing: map['bearing'] as String? ?? '',
      description: map['description'] as String? ?? '',
      action: map['action'] as String? ?? '',
      elevationM: (map['elevationM'] as num?)?.toDouble(),
      walkingTimeMin: (map['walkingTimeMin'] as num?)?.toDouble(),
      obstacles: map['obstacles'] as String? ?? '',
    );
  }

  @override
  List<Object?> get props => [
        index,
        segmentKm,
        pointName,
        cumulativeKm,
        bearing,
        description,
        action,
        elevationM,
        walkingTimeMin,
        obstacles,
      ];
}
