import 'package:equatable/equatable.dart';

/// רמות ניווט
class NavigationLevel {
  static const String struggling = 'מתקשה';
  static const String beginner = 'מתחיל';
  static const String average = 'ממוצע';
  static const String good = 'טוב';
  static const String excellent = 'מצויין';

  static const String defaultLevel = average;

  static const List<String> all = [struggling, beginner, average, good, excellent];
}

/// תת-מסגרת (קבוצת משתמשים)
class SubFramework extends Equatable {
  final String id;
  final String name;
  final List<String> userIds;
  final Map<String, String> userLevels; // uid -> רמת ניווט
  final String? navigatorType; // 'single', 'pairs', 'secured' - רק למנווטים
  final bool isFixed; // האם זה תת-מסגרת קבועה (מפקדים, מנהלת, מבקרים)
  final String? unitId; // מזהה היחידה שהתת-מסגרת שייכת אליה

  const SubFramework({
    required this.id,
    required this.name,
    required this.userIds,
    this.userLevels = const {},
    this.navigatorType,
    this.isFixed = false,
    this.unitId,
  });

  /// מחזיר את רמת הניווט של משתמש (ברירת מחדל: ממוצע)
  String getUserLevel(String uid) =>
      userLevels[uid] ?? NavigationLevel.defaultLevel;

  SubFramework copyWith({
    String? id,
    String? name,
    List<String>? userIds,
    Map<String, String>? userLevels,
    String? navigatorType,
    bool? isFixed,
    String? unitId,
  }) {
    return SubFramework(
      id: id ?? this.id,
      name: name ?? this.name,
      userIds: userIds ?? this.userIds,
      userLevels: userLevels ?? this.userLevels,
      navigatorType: navigatorType ?? this.navigatorType,
      isFixed: isFixed ?? this.isFixed,
      unitId: unitId ?? this.unitId,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'userIds': userIds,
      if (userLevels.isNotEmpty) 'userLevels': userLevels,
      if (navigatorType != null) 'navigatorType': navigatorType,
      'isFixed': isFixed,
      if (unitId != null) 'unitId': unitId,
    };
  }

  factory SubFramework.fromMap(Map<String, dynamic> map) {
    return SubFramework(
      id: map['id'] as String,
      name: map['name'] as String,
      userIds: List<String>.from(map['userIds'] as List),
      userLevels: map['userLevels'] != null
          ? Map<String, String>.from(map['userLevels'] as Map)
          : const {},
      navigatorType: map['navigatorType'] as String?,
      isFixed: map['isFixed'] as bool? ?? false,
      unitId: map['unitId'] as String?,
    );
  }

  @override
  List<Object?> get props => [id, name, userIds, userLevels, navigatorType, isFixed, unitId];
}

/// רמות היררכיה צבאיות
class FrameworkLevel {
  static const int division = 1;    // אוגדה
  static const int brigade = 2;     // חטיבה
  static const int battalion = 3;   // גדוד
  static const int company = 4;     // פלוגה
  static const int platoon = 5;     // מחלקה

  static const Map<int, String> names = {
    division: 'אוגדה',
    brigade: 'חטיבה',
    battalion: 'גדוד',
    company: 'פלוגה',
    platoon: 'מחלקה',
  };

  /// מחזיר את שם הרמה בעברית
  static String getName(int level) => names[level] ?? 'לא ידוע';

  /// מחזיר רשימת רמות מתחת לרמה הנתונה
  static List<int> getLevelsBelow(int level) {
    return names.keys.where((l) => l > level).toList()..sort();
  }

  /// מחזיר את הרמה הבאה מתחת לרמה הנתונה (רמה אחת בלבד)
  static int? getNextLevelBelow(int level) {
    final below = getLevelsBelow(level);
    return below.isNotEmpty ? below.first : null;
  }

  /// מחזיר את כל הרמות
  static List<int> get allLevels => names.keys.toList()..sort();

  /// ממיר סוג יחידה לרמה היררכית
  static int? fromUnitType(String unitType) {
    switch (unitType) {
      case 'brigade':
        return brigade;
      case 'battalion':
        return battalion;
      case 'company':
        return company;
      case 'platoon':
        return platoon;
      default:
        return null;
    }
  }
}

/// עץ ניווט
class NavigationTree extends Equatable {
  final String id;
  final String name;
  final List<SubFramework> subFrameworks; // תתי-מסגרות (קבוצות משתמשים)
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? treeType;      // 'single' / 'pairs_secured' (null = עץ מבנה)
  final String? sourceTreeId;  // אם זה שכפול — מזהה העץ המקורי
  final String? unitId;        // מזהה היחידה

  const NavigationTree({
    required this.id,
    required this.name,
    required this.subFrameworks,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.treeType,
    this.sourceTreeId,
    this.unitId,
  });

  /// יצירת עץ ניווט חדש עם תתי-מסגרות ברירת מחדל
  factory NavigationTree.createDefault({
    required String id,
    required String name,
    required String createdBy,
    String? treeType,
    String? unitId,
  }) {
    final now = DateTime.now();
    return NavigationTree(
      id: id,
      name: name,
      createdBy: createdBy,
      createdAt: now,
      updatedAt: now,
      treeType: treeType,
      unitId: unitId,
      subFrameworks: [
        // תתי-מסגרות קבועות (כללי)
        SubFramework(
          id: '${id}_commanders',
          name: 'מפקדים',
          userIds: [],
          isFixed: true,
          unitId: unitId,
        ),
        SubFramework(
          id: '${id}_manager',
          name: 'מנהלת',
          userIds: [],
          isFixed: true,
          unitId: unitId,
        ),
        SubFramework(
          id: '${id}_observers',
          name: 'מבקרים',
          userIds: [],
          isFixed: true,
          unitId: unitId,
        ),
      ],
    );
  }

  NavigationTree copyWith({
    String? id,
    String? name,
    List<SubFramework>? subFrameworks,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? treeType,
    String? sourceTreeId,
    String? unitId,
  }) {
    return NavigationTree(
      id: id ?? this.id,
      name: name ?? this.name,
      subFrameworks: subFrameworks ?? this.subFrameworks,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      treeType: treeType ?? this.treeType,
      sourceTreeId: sourceTreeId ?? this.sourceTreeId,
      unitId: unitId ?? this.unitId,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'subFrameworks': subFrameworks.map((sf) => sf.toMap()).toList(),
      'createdBy': createdBy,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      if (treeType != null) 'treeType': treeType,
      if (sourceTreeId != null) 'sourceTreeId': sourceTreeId,
      if (unitId != null) 'unitId': unitId,
    };
  }

  factory NavigationTree.fromMap(Map<String, dynamic> map) {
    // תמיכה בפורמט ישן (frameworks) ובפורמט חדש (subFrameworks)
    List<SubFramework> subFrameworks;
    if (map.containsKey('subFrameworks')) {
      subFrameworks = (map['subFrameworks'] as List)
          .map((sf) => SubFramework.fromMap(sf as Map<String, dynamic>))
          .toList();
    } else if (map.containsKey('frameworks')) {
      // מיגרציה מפורמט ישן: שטח את כל ה-SubFrameworks מכל ה-Frameworks
      subFrameworks = [];
      for (final fMap in (map['frameworks'] as List)) {
        final f = fMap as Map<String, dynamic>;
        final fUnitId = f['unitId'] as String?;
        if (f['subFrameworks'] != null) {
          for (final sfMap in (f['subFrameworks'] as List)) {
            final sf = SubFramework.fromMap(sfMap as Map<String, dynamic>);
            subFrameworks.add(sf.unitId == null ? sf.copyWith(unitId: fUnitId) : sf);
          }
        }
      }
    } else {
      subFrameworks = [];
    }

    return NavigationTree(
      id: map['id'] as String,
      name: map['name'] as String,
      subFrameworks: subFrameworks,
      createdBy: map['createdBy'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
      treeType: map['treeType'] as String?,
      sourceTreeId: map['sourceTreeId'] as String?,
      unitId: map['unitId'] as String?,
    );
  }

  @override
  List<Object?> get props => [id, name, subFrameworks, createdBy, createdAt, updatedAt, treeType, sourceTreeId, unitId];

  @override
  String toString() => 'NavigationTree(id: $id, name: $name)';
}
