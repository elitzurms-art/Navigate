import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigate_app/domain/entities/unit.dart';
import 'package:navigate_app/domain/entities/unit_checklist.dart';

void main() {
  final now = DateTime(2026, 3, 10, 12, 0, 0);

  Unit _makeUnit({
    String id = 'unit-1',
    String name = 'פלוגה א',
    String description = 'תיאור',
    String type = 'company',
    String? parentUnitId,
    List<String> managerIds = const ['111', '222'],
    String createdBy = '111',
    DateTime? createdAt,
    DateTime? updatedAt,
    bool isClassified = false,
    int? level,
    bool isNavigators = false,
    bool isGeneral = false,
    List<UnitChecklist> checklists = const [],
  }) {
    return Unit(
      id: id,
      name: name,
      description: description,
      type: type,
      parentUnitId: parentUnitId,
      managerIds: managerIds,
      createdBy: createdBy,
      createdAt: createdAt ?? now,
      updatedAt: updatedAt ?? now,
      isClassified: isClassified,
      level: level,
      isNavigators: isNavigators,
      isGeneral: isGeneral,
      checklists: checklists,
    );
  }

  group('Unit', () {
    // ── 1. toMap / fromMap roundtrip ──
    test('toMap / fromMap roundtrip preserves all fields', () {
      final unit = _makeUnit(
        parentUnitId: 'parent-1',
        level: 3,
        isClassified: true,
        isNavigators: true,
        isGeneral: true,
      );
      final map = unit.toMap();
      final restored = Unit.fromMap(map);

      expect(restored.id, unit.id);
      expect(restored.name, unit.name);
      expect(restored.description, unit.description);
      expect(restored.type, unit.type);
      expect(restored.parentUnitId, unit.parentUnitId);
      expect(restored.managerIds, unit.managerIds);
      expect(restored.createdBy, unit.createdBy);
      expect(restored.createdAt, unit.createdAt);
      expect(restored.updatedAt, unit.updatedAt);
      expect(restored.isClassified, unit.isClassified);
      expect(restored.level, unit.level);
      expect(restored.isNavigators, unit.isNavigators);
      expect(restored.isGeneral, unit.isGeneral);
    });

    // ── 2. fromMap defaults ──
    test('fromMap uses defaults for optional fields', () {
      final map = <String, dynamic>{
        'id': 'u1',
        'name': 'יחידה',
        'description': 'תיאור',
        'type': 'brigade',
        'managerIds': <String>['111'],
        'createdBy': '111',
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      };

      final unit = Unit.fromMap(map);
      expect(unit.isClassified, false);
      expect(unit.isNavigators, false);
      expect(unit.isGeneral, false);
      expect(unit.level, isNull);
      expect(unit.parentUnitId, isNull);
      expect(unit.checklists, isEmpty);
    });

    // ── 3-6. getTypeName for each type ──
    test('getTypeName returns חטיבה for brigade', () {
      expect(_makeUnit(type: 'brigade').getTypeName(), 'חטיבה');
    });

    test('getTypeName returns גדוד for battalion', () {
      expect(_makeUnit(type: 'battalion').getTypeName(), 'גדוד');
    });

    test('getTypeName returns פלוגה for company', () {
      expect(_makeUnit(type: 'company').getTypeName(), 'פלוגה');
    });

    test('getTypeName returns מחלקה for platoon', () {
      expect(_makeUnit(type: 'platoon').getTypeName(), 'מחלקה');
    });

    // ── 7. getTypeName unknown ──
    test('getTypeName returns raw type for unknown type', () {
      expect(_makeUnit(type: 'division').getTypeName(), 'division');
    });

    // ── 8. getIcon returns correct icons ──
    test('getIcon returns correct icon per type', () {
      expect(_makeUnit(type: 'brigade').getIcon(), Icons.military_tech);
      expect(_makeUnit(type: 'battalion').getIcon(), Icons.shield);
      expect(_makeUnit(type: 'company').getIcon(), Icons.group);
      expect(_makeUnit(type: 'platoon').getIcon(), Icons.groups);
      expect(_makeUnit(type: 'unknown').getIcon(), Icons.business);
    });

    // ── 9. copyWith ──
    test('copyWith creates a new unit with updated fields', () {
      final unit = _makeUnit(level: 2);
      final updated = unit.copyWith(name: 'גדוד ב', level: 3, isGeneral: true);

      expect(updated.name, 'גדוד ב');
      expect(updated.level, 3);
      expect(updated.isGeneral, true);
      // Unchanged fields
      expect(updated.id, unit.id);
      expect(updated.type, unit.type);
      expect(updated.managerIds, unit.managerIds);
    });

    // ── 10. copyWith preserves original when no arguments ──
    test('copyWith with no arguments returns equal unit', () {
      final unit = _makeUnit(parentUnitId: 'p1', level: 4, isNavigators: true);
      final copy = unit.copyWith();
      expect(copy, equals(unit));
    });

    // ── 11. Equatable — equal objects ──
    test('Equatable: two identical units are equal', () {
      final a = _makeUnit(level: 4, isNavigators: true);
      final b = _makeUnit(level: 4, isNavigators: true);
      expect(a, equals(b));
    });

    // ── 12. Equatable — different objects ──
    test('Equatable: units with different names are not equal', () {
      final a = _makeUnit(name: 'א');
      final b = _makeUnit(name: 'ב');
      expect(a, isNot(equals(b)));
    });

    // ── 13. level as num in fromMap ──
    test('fromMap handles level as double (num?.toInt)', () {
      final map = <String, dynamic>{
        'id': 'u2',
        'name': 'יחידה',
        'description': 'תיאור',
        'type': 'platoon',
        'managerIds': <String>['111'],
        'createdBy': '111',
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
        'level': 5.0, // double, not int
      };

      final unit = Unit.fromMap(map);
      expect(unit.level, 5);
      expect(unit.level, isA<int>());
    });

    // ── 14. parentUnitId conditional in toMap ──
    test('toMap omits parentUnitId when null', () {
      final unit = _makeUnit(parentUnitId: null);
      final map = unit.toMap();
      expect(map.containsKey('parentUnitId'), false);
    });

    test('toMap includes parentUnitId when set', () {
      final unit = _makeUnit(parentUnitId: 'parent-1');
      final map = unit.toMap();
      expect(map['parentUnitId'], 'parent-1');
    });

    // ── 15. level conditional in toMap ──
    test('toMap omits level when null', () {
      final unit = _makeUnit(level: null);
      final map = unit.toMap();
      expect(map.containsKey('level'), false);
    });

    test('toMap includes level when set', () {
      final unit = _makeUnit(level: 4);
      final map = unit.toMap();
      expect(map['level'], 4);
    });

    // ── 16. checklists serialization ──
    test('toMap/fromMap roundtrip with nested checklists', () {
      final checklist = UnitChecklist(
        id: 'cl-1',
        title: 'צ׳קליסט',
        sections: [
          ChecklistSection(
            id: 's-1',
            title: 'סקציה',
            items: [
              const ChecklistItem(id: 'i-1', title: 'פריט 1'),
              const ChecklistItem(id: 'i-2', title: 'פריט 2'),
            ],
          ),
        ],
      );
      final unit = _makeUnit(checklists: [checklist]);
      final map = unit.toMap();

      expect(map.containsKey('checklists'), true);
      expect((map['checklists'] as List).length, 1);

      final restored = Unit.fromMap(map);
      expect(restored.checklists.length, 1);
      expect(restored.checklists[0].id, 'cl-1');
      expect(restored.checklists[0].sections[0].items.length, 2);
    });

    // ── 17. checklists omitted from toMap when empty ──
    test('toMap omits checklists when empty', () {
      final unit = _makeUnit(checklists: const []);
      final map = unit.toMap();
      expect(map.containsKey('checklists'), false);
    });

    // ── 18. managerIds list preservation ──
    test('managerIds list is preserved through toMap/fromMap', () {
      final unit = _makeUnit(managerIds: ['aaa', 'bbb', 'ccc']);
      final map = unit.toMap();
      final restored = Unit.fromMap(map);
      expect(restored.managerIds, ['aaa', 'bbb', 'ccc']);
    });
  });
}
