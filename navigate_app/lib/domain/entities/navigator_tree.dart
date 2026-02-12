import 'package:equatable/equatable.dart';

/// חבר בעץ מבנה
class TreeMember extends Equatable {
  final String userId;
  final String role;
  final String? subgroup;
  final int? pairOrder; // רק ל-secured: 1 = ראשון, 2 = שני

  const TreeMember({
    required this.userId,
    required this.role,
    this.subgroup,
    this.pairOrder,
  });

  TreeMember copyWith({
    String? userId,
    String? role,
    String? subgroup,
    int? pairOrder,
  }) {
    return TreeMember(
      userId: userId ?? this.userId,
      role: role ?? this.role,
      subgroup: subgroup ?? this.subgroup,
      pairOrder: pairOrder ?? this.pairOrder,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'role': role,
      if (subgroup != null) 'subgroup': subgroup,
      if (pairOrder != null) 'pairOrder': pairOrder,
    };
  }

  factory TreeMember.fromMap(Map<String, dynamic> map) {
    return TreeMember(
      userId: map['userId'] as String,
      role: map['role'] as String,
      subgroup: map['subgroup'] as String?,
      pairOrder: map['pairOrder'] as int?,
    );
  }

  @override
  List<Object?> get props => [userId, role, subgroup, pairOrder];
}

/// הרשאות עץ
class TreePermissions extends Equatable {
  final List<String> editors;
  final List<String> viewers;

  const TreePermissions({
    required this.editors,
    required this.viewers,
  });

  TreePermissions copyWith({
    List<String>? editors,
    List<String>? viewers,
  }) {
    return TreePermissions(
      editors: editors ?? this.editors,
      viewers: viewers ?? this.viewers,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'editors': editors,
      'viewers': viewers,
    };
  }

  factory TreePermissions.fromMap(Map<String, dynamic> map) {
    return TreePermissions(
      editors: List<String>.from(map['editors'] as List),
      viewers: List<String>.from(map['viewers'] as List),
    );
  }

  @override
  List<Object?> get props => [editors, viewers];
}

/// ישות עץ מבנה מנווטים
class NavigatorTree extends Equatable {
  final String id;
  final String name;
  final String type; // 'single', 'pairs_group', 'secured'
  final List<TreeMember> members;
  final String createdBy;
  final TreePermissions permissions;

  const NavigatorTree({
    required this.id,
    required this.name,
    required this.type,
    required this.members,
    required this.createdBy,
    required this.permissions,
  });

  /// האם זה עץ בודד
  bool get isSingle => type == 'single';

  /// האם זה עץ זוגות/קבוצות
  bool get isPairsGroup => type == 'pairs_group';

  /// האם זה עץ מאובטח
  bool get isSecured => type == 'secured';

  NavigatorTree copyWith({
    String? id,
    String? name,
    String? type,
    List<TreeMember>? members,
    String? createdBy,
    TreePermissions? permissions,
  }) {
    return NavigatorTree(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      members: members ?? this.members,
      createdBy: createdBy ?? this.createdBy,
      permissions: permissions ?? this.permissions,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'members': members.map((m) => m.toMap()).toList(),
      'createdBy': createdBy,
      'permissions': permissions.toMap(),
    };
  }

  factory NavigatorTree.fromMap(Map<String, dynamic> map) {
    return NavigatorTree(
      id: map['id'] as String,
      name: map['name'] as String,
      type: map['type'] as String,
      members: (map['members'] as List)
          .map((m) => TreeMember.fromMap(m as Map<String, dynamic>))
          .toList(),
      createdBy: map['createdBy'] as String,
      permissions: TreePermissions.fromMap(
        map['permissions'] as Map<String, dynamic>,
      ),
    );
  }

  @override
  List<Object?> get props => [id, name, type, members, createdBy, permissions];

  @override
  String toString() => 'NavigatorTree(id: $id, name: $name, type: $type)';
}
