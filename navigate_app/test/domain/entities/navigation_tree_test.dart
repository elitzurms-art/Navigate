import 'package:flutter_test/flutter_test.dart';
import 'package:navigate_app/domain/entities/navigation_tree.dart';

void main() {
  group('NavigationLevel', () {
    test('all list contains 5 levels in order', () {
      expect(NavigationLevel.all, [
        'מתקשה',
        'מתחיל',
        'ממוצע',
        'טוב',
        'מצויין',
      ]);
      expect(NavigationLevel.all.length, 5);
    });

    test('constants match expected Hebrew values', () {
      expect(NavigationLevel.struggling, 'מתקשה');
      expect(NavigationLevel.beginner, 'מתחיל');
      expect(NavigationLevel.average, 'ממוצע');
      expect(NavigationLevel.good, 'טוב');
      expect(NavigationLevel.excellent, 'מצויין');
      expect(NavigationLevel.defaultLevel, NavigationLevel.average);
    });
  });

  group('SubFramework', () {
    SubFramework createSubFramework({
      Map<String, String>? userLevels,
      String? unitId,
      bool isFixed = false,
    }) {
      return SubFramework(
        id: 'sf1',
        name: 'מנווטים',
        userIds: ['u1', 'u2'],
        userLevels: userLevels ?? const {},
        navigatorType: 'single',
        isFixed: isFixed,
        unitId: unitId,
      );
    }

    test('toMap and fromMap roundtrip', () {
      final sf = createSubFramework(
        userLevels: {'u1': 'טוב', 'u2': 'מתחיל'},
        unitId: 'unit1',
        isFixed: true,
      );

      final map = sf.toMap();
      final restored = SubFramework.fromMap(map);

      expect(restored.id, 'sf1');
      expect(restored.name, 'מנווטים');
      expect(restored.userIds, ['u1', 'u2']);
      expect(restored.userLevels, {'u1': 'טוב', 'u2': 'מתחיל'});
      expect(restored.navigatorType, 'single');
      expect(restored.isFixed, isTrue);
      expect(restored.unitId, 'unit1');
    });

    test('toMap omits optional fields when null/empty', () {
      const sf = SubFramework(
        id: 'sf1',
        name: 'test',
        userIds: [],
      );

      final map = sf.toMap();
      expect(map.containsKey('userLevels'), isFalse);
      expect(map.containsKey('navigatorType'), isFalse);
      expect(map.containsKey('unitId'), isFalse);
      expect(map['isFixed'], isFalse);
    });

    test('getUserLevel returns custom level when set', () {
      final sf = createSubFramework(userLevels: {'u1': 'מצויין'});

      expect(sf.getUserLevel('u1'), 'מצויין');
    });

    test('getUserLevel returns ממוצע as default for unknown user', () {
      final sf = createSubFramework();

      expect(sf.getUserLevel('unknown_user'), 'ממוצע');
    });

    test('fromMap defaults isFixed to false when missing', () {
      final sf = SubFramework.fromMap({
        'id': 'sf1',
        'name': 'test',
        'userIds': <String>[],
      });

      expect(sf.isFixed, isFalse);
    });

    test('fromMap defaults userLevels to empty map when not a Map', () {
      final sf = SubFramework.fromMap({
        'id': 'sf1',
        'name': 'test',
        'userIds': <String>[],
        'userLevels': 'not a map',
      });

      expect(sf.userLevels, isEmpty);
    });

    test('Equatable compares all props', () {
      final sf1 = createSubFramework(unitId: 'u1');
      final sf2 = createSubFramework(unitId: 'u1');
      expect(sf1, equals(sf2));

      final sf3 = createSubFramework(unitId: 'u2');
      expect(sf1, isNot(equals(sf3)));
    });
  });

  group('FrameworkLevel', () {
    test('constants have expected values', () {
      expect(FrameworkLevel.division, 1);
      expect(FrameworkLevel.brigade, 2);
      expect(FrameworkLevel.battalion, 3);
      expect(FrameworkLevel.company, 4);
      expect(FrameworkLevel.platoon, 5);
    });

    test('getName returns Hebrew name for all known levels', () {
      expect(FrameworkLevel.getName(1), 'אוגדה');
      expect(FrameworkLevel.getName(2), 'חטיבה');
      expect(FrameworkLevel.getName(3), 'גדוד');
      expect(FrameworkLevel.getName(4), 'פלוגה');
      expect(FrameworkLevel.getName(5), 'מחלקה');
    });

    test('getName returns לא ידוע for unknown level', () {
      expect(FrameworkLevel.getName(0), 'לא ידוע');
      expect(FrameworkLevel.getName(6), 'לא ידוע');
      expect(FrameworkLevel.getName(99), 'לא ידוע');
    });

    test('getLevelsBelow returns levels below the given level, sorted', () {
      expect(FrameworkLevel.getLevelsBelow(1), [2, 3, 4, 5]);
      expect(FrameworkLevel.getLevelsBelow(2), [3, 4, 5]);
      expect(FrameworkLevel.getLevelsBelow(3), [4, 5]);
      expect(FrameworkLevel.getLevelsBelow(4), [5]);
      expect(FrameworkLevel.getLevelsBelow(5), isEmpty);
    });

    test('getNextLevelBelow returns the immediate next level', () {
      expect(FrameworkLevel.getNextLevelBelow(1), 2);
      expect(FrameworkLevel.getNextLevelBelow(2), 3);
      expect(FrameworkLevel.getNextLevelBelow(3), 4);
      expect(FrameworkLevel.getNextLevelBelow(4), 5);
    });

    test('getNextLevelBelow returns null at the lowest level', () {
      expect(FrameworkLevel.getNextLevelBelow(5), isNull);
    });

    test('fromUnitType maps string types to integer levels', () {
      expect(FrameworkLevel.fromUnitType('division'), 1);
      expect(FrameworkLevel.fromUnitType('brigade'), 2);
      expect(FrameworkLevel.fromUnitType('battalion'), 3);
      expect(FrameworkLevel.fromUnitType('company'), 4);
      expect(FrameworkLevel.fromUnitType('platoon'), 5);
    });

    test('fromUnitType returns null for unknown type', () {
      expect(FrameworkLevel.fromUnitType('unknown'), isNull);
      expect(FrameworkLevel.fromUnitType(''), isNull);
      expect(FrameworkLevel.fromUnitType('squad'), isNull);
    });

    test('allLevels returns sorted list of all levels', () {
      expect(FrameworkLevel.allLevels, [1, 2, 3, 4, 5]);
    });
  });

  group('NavigationTree', () {
    final createdAt = DateTime(2026, 1, 15, 10, 0, 0);
    final updatedAt = DateTime(2026, 3, 10, 12, 0, 0);

    NavigationTree createTree({
      List<SubFramework>? subFrameworks,
      String? treeType,
      String? sourceTreeId,
      String? unitId,
    }) {
      return NavigationTree(
        id: 'tree1',
        name: 'עץ ראשון',
        subFrameworks: subFrameworks ?? const [],
        createdBy: '6868383',
        createdAt: createdAt,
        updatedAt: updatedAt,
        treeType: treeType,
        sourceTreeId: sourceTreeId,
        unitId: unitId,
      );
    }

    test('toMap and fromMap roundtrip', () {
      final tree = createTree(
        subFrameworks: [
          const SubFramework(
            id: 'sf1',
            name: 'מפקדים',
            userIds: ['u1'],
            isFixed: true,
            unitId: 'unit1',
          ),
          const SubFramework(
            id: 'sf2',
            name: 'חיילים',
            userIds: ['u2', 'u3'],
            isFixed: true,
            unitId: 'unit1',
          ),
        ],
        treeType: 'single',
        sourceTreeId: 'original1',
        unitId: 'unit1',
      );

      final map = tree.toMap();
      final restored = NavigationTree.fromMap(map);

      expect(restored.id, 'tree1');
      expect(restored.name, 'עץ ראשון');
      expect(restored.createdBy, '6868383');
      expect(restored.createdAt, createdAt);
      expect(restored.updatedAt, updatedAt);
      expect(restored.treeType, 'single');
      expect(restored.sourceTreeId, 'original1');
      expect(restored.unitId, 'unit1');
      expect(restored.subFrameworks.length, 2);
      expect(restored.subFrameworks[0].name, 'מפקדים');
      expect(restored.subFrameworks[1].name, 'חיילים');
    });

    test('toMap omits optional fields when null', () {
      final tree = createTree();
      final map = tree.toMap();

      expect(map.containsKey('treeType'), isFalse);
      expect(map.containsKey('sourceTreeId'), isFalse);
      expect(map.containsKey('unitId'), isFalse);
    });

    test('fromMap backward compat with old frameworks key', () {
      final map = {
        'id': 'tree1',
        'name': 'עץ ישן',
        'createdBy': '6868383',
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'frameworks': [
          {
            'unitId': 'unit_old',
            'subFrameworks': [
              {
                'id': 'sf1',
                'name': 'מנווטים',
                'userIds': ['u1', 'u2'],
              },
              {
                'id': 'sf2',
                'name': 'מפקדים',
                'userIds': ['u3'],
                'unitId': 'unit_explicit',
              },
            ],
          },
        ],
      };

      final tree = NavigationTree.fromMap(map);

      expect(tree.subFrameworks.length, 2);
      // First SubFramework should get unitId from parent framework
      expect(tree.subFrameworks[0].id, 'sf1');
      expect(tree.subFrameworks[0].unitId, 'unit_old');
      // Second SubFramework already had unitId — should keep it
      expect(tree.subFrameworks[1].id, 'sf2');
      expect(tree.subFrameworks[1].unitId, 'unit_explicit');
    });

    test('fromMap with neither subFrameworks nor frameworks defaults to empty list', () {
      final map = {
        'id': 'tree1',
        'name': 'עץ ריק',
        'createdBy': '6868383',
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

      final tree = NavigationTree.fromMap(map);
      expect(tree.subFrameworks, isEmpty);
    });

    test('createDefault creates tree with 2 fixed subFrameworks', () {
      final tree = NavigationTree.createDefault(
        id: 'new_tree',
        name: 'עץ חדש',
        createdBy: '6868383',
        unitId: 'unit1',
      );

      expect(tree.id, 'new_tree');
      expect(tree.name, 'עץ חדש');
      expect(tree.createdBy, '6868383');
      expect(tree.unitId, 'unit1');
      expect(tree.subFrameworks.length, 2);

      final cmd = tree.subFrameworks[0];
      expect(cmd.id, 'new_tree_cmd_mgmt');
      expect(cmd.name, 'מפקדים');
      expect(cmd.isFixed, isTrue);
      expect(cmd.unitId, 'unit1');
      expect(cmd.userIds, isEmpty);

      final soldiers = tree.subFrameworks[1];
      expect(soldiers.id, 'new_tree_soldiers');
      expect(soldiers.name, 'חיילים');
      expect(soldiers.isFixed, isTrue);
      expect(soldiers.unitId, 'unit1');
      expect(soldiers.userIds, isEmpty);
    });

    test('createDefault sets createdAt and updatedAt to now', () {
      final before = DateTime.now();
      final tree = NavigationTree.createDefault(
        id: 'test',
        name: 'test',
        createdBy: '6868383',
      );
      final after = DateTime.now();

      expect(tree.createdAt.isAfter(before) || tree.createdAt.isAtSameMomentAs(before), isTrue);
      expect(tree.createdAt.isBefore(after) || tree.createdAt.isAtSameMomentAs(after), isTrue);
      expect(tree.updatedAt, tree.createdAt);
    });

    test('copyWith replaces specified fields only', () {
      final original = createTree(unitId: 'unit1');
      final modified = original.copyWith(
        name: 'שם חדש',
        treeType: 'pairs_secured',
      );

      expect(modified.name, 'שם חדש');
      expect(modified.treeType, 'pairs_secured');
      expect(modified.id, 'tree1'); // unchanged
      expect(modified.unitId, 'unit1'); // unchanged
      expect(modified.createdBy, '6868383'); // unchanged
    });

    test('Equatable compares all props', () {
      final t1 = createTree(unitId: 'u1');
      final t2 = createTree(unitId: 'u1');
      expect(t1, equals(t2));

      final t3 = createTree(unitId: 'u2');
      expect(t1, isNot(equals(t3)));

      final t4 = createTree(unitId: 'u1').copyWith(name: 'different');
      expect(t1, isNot(equals(t4)));
    });

    test('fromMap with frameworks key flattens multiple frameworks', () {
      final map = {
        'id': 'tree1',
        'name': 'multi-fw',
        'createdBy': '6868383',
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'frameworks': [
          {
            'unitId': 'unitA',
            'subFrameworks': [
              {'id': 'sf1', 'name': 'group1', 'userIds': ['u1']},
            ],
          },
          {
            'unitId': 'unitB',
            'subFrameworks': [
              {'id': 'sf2', 'name': 'group2', 'userIds': ['u2']},
              {'id': 'sf3', 'name': 'group3', 'userIds': ['u3']},
            ],
          },
        ],
      };

      final tree = NavigationTree.fromMap(map);

      expect(tree.subFrameworks.length, 3);
      expect(tree.subFrameworks[0].unitId, 'unitA');
      expect(tree.subFrameworks[1].unitId, 'unitB');
      expect(tree.subFrameworks[2].unitId, 'unitB');
    });

    test('fromMap with frameworks key where framework has null subFrameworks', () {
      final map = {
        'id': 'tree1',
        'name': 'fw-no-sf',
        'createdBy': '6868383',
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'frameworks': [
          {
            'unitId': 'unitA',
            // no subFrameworks key
          },
        ],
      };

      final tree = NavigationTree.fromMap(map);
      expect(tree.subFrameworks, isEmpty);
    });

    test('toString returns formatted string', () {
      final tree = createTree();
      expect(tree.toString(), 'NavigationTree(id: tree1, name: עץ ראשון)');
    });
  });
}
