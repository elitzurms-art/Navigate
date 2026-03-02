import 'package:equatable/equatable.dart';
import 'user.dart';

/// פריט בודד בצ'קליסט
class ChecklistItem extends Equatable {
  final String id;
  final String title;

  const ChecklistItem({
    required this.id,
    required this.title,
  });

  Map<String, dynamic> toMap() => {'id': id, 'title': title};

  factory ChecklistItem.fromMap(Map<String, dynamic> map) {
    return ChecklistItem(
      id: map['id'] as String,
      title: map['title'] as String,
    );
  }

  @override
  List<Object?> get props => [id, title];
}

/// קטגוריה בתוך צ'קליסט
class ChecklistSection extends Equatable {
  final String id;
  final String title;
  final List<ChecklistItem> items;

  const ChecklistSection({
    required this.id,
    required this.title,
    required this.items,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'items': items.map((i) => i.toMap()).toList(),
      };

  factory ChecklistSection.fromMap(Map<String, dynamic> map) {
    return ChecklistSection(
      id: map['id'] as String,
      title: map['title'] as String,
      items: (map['items'] as List)
          .map((i) => ChecklistItem.fromMap(i as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  List<Object?> get props => [id, title, items];
}

/// תבנית צ'קליסט — ברמת היחידה
class UnitChecklist extends Equatable {
  final String id;
  final String title;
  final List<ChecklistSection> sections;
  final bool isMandatory;

  const UnitChecklist({
    required this.id,
    required this.title,
    required this.sections,
    this.isMandatory = false,
  });

  int get totalItems => sections.fold(0, (s, sec) => s + sec.items.length);

  /// All item IDs in this checklist
  List<String> get allItemIds =>
      sections.expand((s) => s.items.map((i) => i.id)).toList();

  UnitChecklist copyWith({
    String? id,
    String? title,
    List<ChecklistSection>? sections,
    bool? isMandatory,
  }) {
    return UnitChecklist(
      id: id ?? this.id,
      title: title ?? this.title,
      sections: sections ?? this.sections,
      isMandatory: isMandatory ?? this.isMandatory,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'sections': sections.map((s) => s.toMap()).toList(),
        'isMandatory': isMandatory,
      };

  factory UnitChecklist.fromMap(Map<String, dynamic> map) {
    return UnitChecklist(
      id: map['id'] as String,
      title: map['title'] as String,
      sections: (map['sections'] as List)
          .map((s) => ChecklistSection.fromMap(s as Map<String, dynamic>))
          .toList(),
      isMandatory: map['isMandatory'] as bool? ?? false,
    );
  }

  @override
  List<Object?> get props => [id, title, sections, isMandatory];
}

/// חתימה על צ'קליסט שהושלם
class ChecklistSignature extends Equatable {
  final DateTime completedAt;
  final String completedByUserId;
  final String completedByName;
  final String? userRole;
  final String? unitId;

  const ChecklistSignature({
    required this.completedAt,
    required this.completedByUserId,
    required this.completedByName,
    this.userRole,
    this.unitId,
  });

  Map<String, dynamic> toMap() => {
        'completedAt': completedAt.toIso8601String(),
        'completedByUserId': completedByUserId,
        'completedByName': completedByName,
        if (userRole != null) 'userRole': userRole,
        if (unitId != null) 'unitId': unitId,
      };

  factory ChecklistSignature.fromMap(Map<String, dynamic> map) {
    return ChecklistSignature(
      completedAt: DateTime.parse(map['completedAt'] as String),
      completedByUserId: map['completedByUserId'] as String,
      completedByName: map['completedByName'] as String,
      userRole: map['userRole'] as String?,
      unitId: map['unitId'] as String?,
    );
  }

  @override
  List<Object?> get props =>
      [completedAt, completedByUserId, completedByName, userRole, unitId];
}

/// מילוי צ'קליסטים — ברמת הניווט
class ChecklistCompletion extends Equatable {
  /// checklistId → { itemId: true/false }
  final Map<String, Map<String, bool>> completions;

  /// checklistId → signature
  final Map<String, ChecklistSignature> signatures;

  const ChecklistCompletion({
    this.completions = const {},
    this.signatures = const {},
  });

  /// Is every item in the template marked true?
  bool isChecklistComplete(String checklistId, UnitChecklist template) {
    final map = completions[checklistId];
    if (map == null) return false;
    return template.allItemIds.every((id) => map[id] == true);
  }

  /// Count of completed items for a checklist
  int completedCount(String checklistId) {
    final map = completions[checklistId];
    if (map == null) return 0;
    return map.values.where((v) => v).length;
  }

  /// Completion percentage (0-100)
  double percentage(String checklistId, int totalItems) {
    if (totalItems == 0) return 100;
    return (completedCount(checklistId) / totalItems) * 100;
  }

  /// Get signature for a checklist
  ChecklistSignature? getSignature(String checklistId) =>
      signatures[checklistId];

  /// Toggle an item — returns new instance. Removes signature if exists.
  ChecklistCompletion toggleItem(String checklistId, String itemId) {
    final newCompletions =
        Map<String, Map<String, bool>>.from(completions.map(
      (k, v) => MapEntry(k, Map<String, bool>.from(v)),
    ));
    newCompletions.putIfAbsent(checklistId, () => {});
    final current = newCompletions[checklistId]![itemId] ?? false;
    newCompletions[checklistId]![itemId] = !current;

    // Remove signature if exists (protection: signature must match actual state)
    final newSignatures =
        Map<String, ChecklistSignature>.from(signatures);
    newSignatures.remove(checklistId);

    return ChecklistCompletion(
      completions: newCompletions,
      signatures: newSignatures,
    );
  }

  /// Sign a completed checklist
  ChecklistCompletion signChecklist(String checklistId, User user) {
    final newSignatures =
        Map<String, ChecklistSignature>.from(signatures);
    newSignatures[checklistId] = ChecklistSignature(
      completedAt: DateTime.now(),
      completedByUserId: user.uid,
      completedByName: user.fullName,
      userRole: user.role,
      unitId: user.unitId,
    );
    return ChecklistCompletion(
      completions: completions,
      signatures: newSignatures,
    );
  }

  Map<String, dynamic> toMap() => {
        'completions': completions.map(
          (k, v) => MapEntry(k, v.map((ik, iv) => MapEntry(ik, iv))),
        ),
        'signatures': signatures.map(
          (k, v) => MapEntry(k, v.toMap()),
        ),
      };

  factory ChecklistCompletion.fromMap(Map<String, dynamic> map) {
    final completionsRaw = map['completions'] as Map<String, dynamic>? ?? {};
    final signaturesRaw = map['signatures'] as Map<String, dynamic>? ?? {};

    return ChecklistCompletion(
      completions: completionsRaw.map(
        (k, v) => MapEntry(
          k,
          (v as Map<String, dynamic>).map(
            (ik, iv) => MapEntry(ik, iv as bool),
          ),
        ),
      ),
      signatures: signaturesRaw.map(
        (k, v) => MapEntry(
          k,
          ChecklistSignature.fromMap(v as Map<String, dynamic>),
        ),
      ),
    );
  }

  @override
  List<Object?> get props => [completions, signatures];
}
