import 'package:flutter_test/flutter_test.dart';
import 'package:navigate_app/domain/entities/unit_checklist.dart';
import 'package:navigate_app/domain/entities/user.dart';
import '../../helpers/entity_factories.dart';

void main() {
  final now = DateTime(2026, 3, 10, 12, 0, 0);

  // ── helpers ──
  ChecklistItem _item(String id, String title) =>
      ChecklistItem(id: id, title: title);

  ChecklistSection _section(String id, String title, List<ChecklistItem> items) =>
      ChecklistSection(id: id, title: title, items: items);

  UnitChecklist _checklist({
    String id = 'cl-1',
    String title = 'צ׳קליסט',
    List<ChecklistSection>? sections,
    bool isMandatory = false,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? copiedFromUnitId,
    String? copiedFromChecklistId,
    DateTime? copiedAt,
  }) {
    return UnitChecklist(
      id: id,
      title: title,
      sections: sections ??
          [
            _section('s-1', 'סקציה א', [
              _item('i-1', 'פריט 1'),
              _item('i-2', 'פריט 2'),
            ]),
            _section('s-2', 'סקציה ב', [
              _item('i-3', 'פריט 3'),
            ]),
          ],
      isMandatory: isMandatory,
      createdAt: createdAt,
      updatedAt: updatedAt,
      copiedFromUnitId: copiedFromUnitId,
      copiedFromChecklistId: copiedFromChecklistId,
      copiedAt: copiedAt,
    );
  }

  // ═══════════════════════════════════════════
  //  ChecklistItem
  // ═══════════════════════════════════════════
  group('ChecklistItem', () {
    test('toMap / fromMap roundtrip', () {
      final item = _item('i-1', 'בדיקת סוללה');
      final map = item.toMap();
      expect(map, {'id': 'i-1', 'title': 'בדיקת סוללה'});

      final restored = ChecklistItem.fromMap(map);
      expect(restored, equals(item));
    });

    test('Equatable: equal items', () {
      expect(_item('a', 'x'), equals(_item('a', 'x')));
    });

    test('Equatable: different items', () {
      expect(_item('a', 'x'), isNot(equals(_item('b', 'x'))));
    });
  });

  // ═══════════════════════════════════════════
  //  ChecklistSection
  // ═══════════════════════════════════════════
  group('ChecklistSection', () {
    test('toMap / fromMap roundtrip with nested items', () {
      final section = _section('s-1', 'בדיקות', [
        _item('i-1', 'סוללה'),
        _item('i-2', 'קליטת GPS'),
      ]);
      final map = section.toMap();
      final restored = ChecklistSection.fromMap(map);

      expect(restored, equals(section));
      expect(restored.items.length, 2);
      expect(restored.items[0].title, 'סוללה');
    });

    test('Equatable: different sections', () {
      final a = _section('s-1', 'a', [_item('i-1', 'x')]);
      final b = _section('s-1', 'b', [_item('i-1', 'x')]);
      expect(a, isNot(equals(b)));
    });
  });

  // ═══════════════════════════════════════════
  //  UnitChecklist
  // ═══════════════════════════════════════════
  group('UnitChecklist', () {
    // ── 1. toMap / fromMap roundtrip ──
    test('toMap / fromMap roundtrip', () {
      final checklist = _checklist(
        createdAt: now,
        updatedAt: now,
        copiedFromUnitId: 'src-unit',
        copiedFromChecklistId: 'src-cl',
        copiedAt: now,
        isMandatory: true,
      );
      final map = checklist.toMap();
      final restored = UnitChecklist.fromMap(map);

      expect(restored.id, checklist.id);
      expect(restored.title, checklist.title);
      expect(restored.sections.length, checklist.sections.length);
      expect(restored.isMandatory, true);
      expect(restored.createdAt, now);
      expect(restored.updatedAt, now);
      expect(restored.copiedFromUnitId, 'src-unit');
      expect(restored.copiedFromChecklistId, 'src-cl');
      expect(restored.copiedAt, now);
    });

    // ── 2. totalItems getter ──
    test('totalItems counts items across all sections', () {
      final checklist = _checklist(); // 2 + 1 items
      expect(checklist.totalItems, 3);
    });

    test('totalItems returns 0 for empty sections', () {
      final checklist = _checklist(sections: []);
      expect(checklist.totalItems, 0);
    });

    // ── 3. allItemIds getter ──
    test('allItemIds returns all item IDs in order', () {
      final checklist = _checklist();
      expect(checklist.allItemIds, ['i-1', 'i-2', 'i-3']);
    });

    // ── 4. isMandatory default false ──
    test('isMandatory defaults to false', () {
      final checklist = _checklist();
      expect(checklist.isMandatory, false);
    });

    test('fromMap defaults isMandatory to false when missing', () {
      final map = <String, dynamic>{
        'id': 'cl-x',
        'title': 'test',
        'sections': <dynamic>[],
      };
      final checklist = UnitChecklist.fromMap(map);
      expect(checklist.isMandatory, false);
    });

    // ── 5. conditional fields in toMap ──
    test('toMap omits createdAt/updatedAt/copiedFrom when null', () {
      final checklist = _checklist();
      final map = checklist.toMap();
      expect(map.containsKey('createdAt'), false);
      expect(map.containsKey('updatedAt'), false);
      expect(map.containsKey('copiedFromUnitId'), false);
      expect(map.containsKey('copiedFromChecklistId'), false);
      expect(map.containsKey('copiedAt'), false);
    });

    test('toMap includes createdAt/updatedAt/copiedFrom when set', () {
      final checklist = _checklist(
        createdAt: now,
        updatedAt: now,
        copiedFromUnitId: 'u1',
        copiedFromChecklistId: 'cl1',
        copiedAt: now,
      );
      final map = checklist.toMap();
      expect(map.containsKey('createdAt'), true);
      expect(map.containsKey('updatedAt'), true);
      expect(map.containsKey('copiedFromUnitId'), true);
      expect(map.containsKey('copiedFromChecklistId'), true);
      expect(map.containsKey('copiedAt'), true);
    });

    // ── 6. copyWith ──
    test('copyWith updates specified fields', () {
      final original = _checklist(isMandatory: false);
      final updated = original.copyWith(title: 'חדש', isMandatory: true);
      expect(updated.title, 'חדש');
      expect(updated.isMandatory, true);
      expect(updated.id, original.id);
      expect(updated.sections, original.sections);
    });

    // ── 7. Equatable ──
    test('Equatable: identical checklists are equal', () {
      final a = _checklist(createdAt: now, updatedAt: now);
      final b = _checklist(createdAt: now, updatedAt: now);
      expect(a, equals(b));
    });
  });

  // ═══════════════════════════════════════════
  //  ChecklistSignature
  // ═══════════════════════════════════════════
  group('ChecklistSignature', () {
    test('toMap / fromMap roundtrip', () {
      final sig = ChecklistSignature(
        completedAt: now,
        completedByUserId: '1234567',
        completedByName: 'ישראל ישראלי',
        userRole: 'commander',
        unitId: 'unit-1',
      );
      final map = sig.toMap();
      final restored = ChecklistSignature.fromMap(map);

      expect(restored, equals(sig));
      expect(restored.completedAt, now);
      expect(restored.userRole, 'commander');
      expect(restored.unitId, 'unit-1');
    });

    test('toMap omits optional fields when null', () {
      final sig = ChecklistSignature(
        completedAt: now,
        completedByUserId: '111',
        completedByName: 'name',
      );
      final map = sig.toMap();
      expect(map.containsKey('userRole'), false);
      expect(map.containsKey('unitId'), false);
    });

    test('fromMap handles missing optional fields', () {
      final map = <String, dynamic>{
        'completedAt': now.toIso8601String(),
        'completedByUserId': '111',
        'completedByName': 'name',
      };
      final sig = ChecklistSignature.fromMap(map);
      expect(sig.userRole, isNull);
      expect(sig.unitId, isNull);
    });
  });

  // ═══════════════════════════════════════════
  //  ChecklistCompletion
  // ═══════════════════════════════════════════
  group('ChecklistCompletion', () {
    final template = _checklist(); // items: i-1, i-2, i-3

    // ── 1. toggleItem creates new instance + removes signature ──
    test('toggleItem creates new instance and removes signature', () {
      final sig = ChecklistSignature(
        completedAt: now,
        completedByUserId: '111',
        completedByName: 'name',
      );
      final initial = ChecklistCompletion(
        completions: {
          'cl-1': {'i-1': true, 'i-2': true, 'i-3': true},
        },
        signatures: {'cl-1': sig},
      );

      final toggled = initial.toggleItem('cl-1', 'i-1');

      // New instance
      expect(identical(toggled, initial), false);
      // Item toggled from true to false
      expect(toggled.completions['cl-1']!['i-1'], false);
      // Signature removed
      expect(toggled.signatures.containsKey('cl-1'), false);
      // Original unchanged
      expect(initial.completions['cl-1']!['i-1'], true);
      expect(initial.signatures.containsKey('cl-1'), true);
    });

    test('toggleItem on new checklist creates entry', () {
      const initial = ChecklistCompletion();
      final toggled = initial.toggleItem('cl-new', 'item-1');
      expect(toggled.completions['cl-new']!['item-1'], true);
    });

    test('toggleItem toggles false to true', () {
      final initial = ChecklistCompletion(
        completions: {
          'cl-1': {'i-1': false},
        },
      );
      final toggled = initial.toggleItem('cl-1', 'i-1');
      expect(toggled.completions['cl-1']!['i-1'], true);
    });

    // ── 2. isChecklistComplete ──
    test('isChecklistComplete returns true when all items checked', () {
      final completion = ChecklistCompletion(
        completions: {
          'cl-1': {'i-1': true, 'i-2': true, 'i-3': true},
        },
      );
      expect(completion.isChecklistComplete('cl-1', template), true);
    });

    test('isChecklistComplete returns false when some items unchecked', () {
      final completion = ChecklistCompletion(
        completions: {
          'cl-1': {'i-1': true, 'i-2': false, 'i-3': true},
        },
      );
      expect(completion.isChecklistComplete('cl-1', template), false);
    });

    test('isChecklistComplete returns false when checklist not started', () {
      const completion = ChecklistCompletion();
      expect(completion.isChecklistComplete('cl-1', template), false);
    });

    // ── 3. completedCount ──
    test('completedCount returns count of true items', () {
      final completion = ChecklistCompletion(
        completions: {
          'cl-1': {'i-1': true, 'i-2': false, 'i-3': true},
        },
      );
      expect(completion.completedCount('cl-1'), 2);
    });

    test('completedCount returns 0 for unknown checklist', () {
      const completion = ChecklistCompletion();
      expect(completion.completedCount('nonexistent'), 0);
    });

    // ── 4. percentage ──
    test('percentage returns 100 when totalItems is 0', () {
      const completion = ChecklistCompletion();
      expect(completion.percentage('cl-1', 0), 100.0);
    });

    test('percentage returns partial value', () {
      final completion = ChecklistCompletion(
        completions: {
          'cl-1': {'i-1': true, 'i-2': false, 'i-3': false},
        },
      );
      // 1 out of 3 = 33.33...
      expect(completion.percentage('cl-1', 3), closeTo(33.33, 0.01));
    });

    test('percentage returns 100 when all done', () {
      final completion = ChecklistCompletion(
        completions: {
          'cl-1': {'i-1': true, 'i-2': true, 'i-3': true},
        },
      );
      expect(completion.percentage('cl-1', 3), 100.0);
    });

    // ── 5. signChecklist ──
    test('signChecklist creates signature from User', () {
      final user = createTestUser(
        uid: '7654321',
        firstName: 'משה',
        lastName: 'כהן',
        role: 'commander',
        unitId: 'unit-5',
      );

      final completion = ChecklistCompletion(
        completions: {
          'cl-1': {'i-1': true, 'i-2': true, 'i-3': true},
        },
      );

      final signed = completion.signChecklist('cl-1', user);

      expect(signed.signatures.containsKey('cl-1'), true);
      final sig = signed.signatures['cl-1']!;
      expect(sig.completedByUserId, '7654321');
      expect(sig.completedByName, 'משה כהן');
      expect(sig.userRole, 'commander');
      expect(sig.unitId, 'unit-5');
      expect(sig.completedAt, isA<DateTime>());
      // Original unchanged
      expect(completion.signatures.containsKey('cl-1'), false);
    });

    // ── 6. getSignature ──
    test('getSignature returns signature when present', () {
      final sig = ChecklistSignature(
        completedAt: now,
        completedByUserId: '111',
        completedByName: 'name',
      );
      final completion = ChecklistCompletion(signatures: {'cl-1': sig});
      expect(completion.getSignature('cl-1'), sig);
    });

    test('getSignature returns null when absent', () {
      const completion = ChecklistCompletion();
      expect(completion.getSignature('cl-1'), isNull);
    });

    // ── 7. toMap / fromMap roundtrip ──
    test('toMap / fromMap roundtrip', () {
      final sig = ChecklistSignature(
        completedAt: now,
        completedByUserId: '111',
        completedByName: 'name',
        userRole: 'commander',
        unitId: 'unit-1',
      );
      final original = ChecklistCompletion(
        completions: {
          'cl-1': {'i-1': true, 'i-2': false},
          'cl-2': {'i-3': true},
        },
        signatures: {'cl-1': sig},
      );

      final map = original.toMap();
      final restored = ChecklistCompletion.fromMap(map);

      expect(restored.completions['cl-1']!['i-1'], true);
      expect(restored.completions['cl-1']!['i-2'], false);
      expect(restored.completions['cl-2']!['i-3'], true);
      expect(restored.signatures['cl-1']!.completedByUserId, '111');
      expect(restored.signatures['cl-1']!.userRole, 'commander');
    });

    test('fromMap handles empty/missing maps', () {
      final restored = ChecklistCompletion.fromMap(<String, dynamic>{});
      expect(restored.completions, isEmpty);
      expect(restored.signatures, isEmpty);
    });

    // ── 8. Equatable ──
    test('Equatable: identical completions are equal', () {
      final a = ChecklistCompletion(
        completions: {
          'cl-1': {'i-1': true},
        },
      );
      final b = ChecklistCompletion(
        completions: {
          'cl-1': {'i-1': true},
        },
      );
      expect(a, equals(b));
    });

    test('Equatable: different completions are not equal', () {
      final a = ChecklistCompletion(
        completions: {
          'cl-1': {'i-1': true},
        },
      );
      final b = ChecklistCompletion(
        completions: {
          'cl-1': {'i-1': false},
        },
      );
      expect(a, isNot(equals(b)));
    });
  });
}
