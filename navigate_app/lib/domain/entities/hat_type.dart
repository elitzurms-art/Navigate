import 'package:equatable/equatable.dart';

/// סוגי כובעים (תפקידים) במערכת
enum HatType {
  admin,
  commander,
  navigator,
}

/// מידע על כובע ספציפי של משתמש ביחידה/תת-מסגרת מסוימת
class HatInfo extends Equatable {
  final HatType type;
  final String? subFrameworkId;
  final String? subFrameworkName;
  final String treeId;
  final String treeName;
  final String unitId;
  final String unitName;

  const HatInfo({
    required this.type,
    this.subFrameworkId,
    this.subFrameworkName,
    required this.treeId,
    required this.treeName,
    required this.unitId,
    required this.unitName,
  });

  /// שם תצוגה של סוג הכובע
  String get typeName {
    switch (type) {
      case HatType.admin:
        return 'מנהל מערכת';
      case HatType.commander:
        return 'מפקד';
      case HatType.navigator:
        return 'מנווט';
    }
  }

  /// תיאור מלא של הכובע
  String get description {
    final parts = <String>[unitName];
    if (subFrameworkName != null) {
      parts.add(subFrameworkName!);
    }
    parts.add(typeName);
    return parts.join(' - ');
  }

  /// המרה ל-Map לשמירה ב-SharedPreferences
  Map<String, String> toPrefsMap() {
    return {
      'session_hat_type': type.name,
      'session_tree_id': treeId,
      'session_tree_name': treeName,
      'session_unit_id': unitId,
      'session_unit_name': unitName,
      if (subFrameworkId != null) 'session_sub_framework_id': subFrameworkId!,
      if (subFrameworkName != null) 'session_sub_framework_name': subFrameworkName!,
    };
  }

  @override
  List<Object?> get props => [
        type,
        subFrameworkId,
        subFrameworkName,
        treeId,
        treeName,
        unitId,
        unitName,
      ];
}
