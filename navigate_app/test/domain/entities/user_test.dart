import 'package:flutter_test/flutter_test.dart';
import 'package:navigate_app/domain/entities/user.dart';

import '../../helpers/entity_factories.dart';

void main() {
  final now = DateTime(2026, 2, 15, 10, 0, 0);

  // ---------------------------------------------------------------------------
  // toMap / fromMap roundtrip
  // ---------------------------------------------------------------------------
  group('toMap / fromMap roundtrip', () {
    test('full user survives roundtrip', () {
      final user = createTestUser(
        uid: '7654321',
        firstName: 'משה',
        lastName: 'כהן',
        phoneNumber: '0521234567',
        phoneVerified: true,
        email: 'moshe@test.com',
        emailVerified: true,
        role: 'commander',
        unitId: 'unit-42',
        fcmToken: 'fcm-abc',
        firebaseUid: 'firebase-xyz',
        approvalStatus: 'approved',
        soloQuizPassedAt: now,
        soloQuizScore: 90,
        commanderQuizPassedAt: now,
        commanderQuizScore: 85,
        activeSessionId: 'session-1',
        createdAt: now,
        updatedAt: now,
      );

      final map = user.toMap();
      final restored = User.fromMap(map);

      expect(restored.uid, user.uid);
      expect(restored.firstName, user.firstName);
      expect(restored.lastName, user.lastName);
      expect(restored.phoneNumber, user.phoneNumber);
      expect(restored.phoneVerified, user.phoneVerified);
      expect(restored.email, user.email);
      expect(restored.emailVerified, user.emailVerified);
      expect(restored.role, user.role);
      expect(restored.unitId, user.unitId);
      expect(restored.fcmToken, user.fcmToken);
      expect(restored.firebaseUid, user.firebaseUid);
      expect(restored.approvalStatus, user.approvalStatus);
      expect(restored.soloQuizPassedAt, user.soloQuizPassedAt);
      expect(restored.soloQuizScore, user.soloQuizScore);
      expect(restored.commanderQuizPassedAt, user.commanderQuizPassedAt);
      expect(restored.commanderQuizScore, user.commanderQuizScore);
      expect(restored.activeSessionId, user.activeSessionId);
      expect(restored.createdAt, user.createdAt);
      expect(restored.updatedAt, user.updatedAt);
    });

    test('toMap includes personalNumber and fullName for backward compat', () {
      final user = createTestUser(firstName: 'אבי', lastName: 'לוי');
      final map = user.toMap();

      expect(map['personalNumber'], user.uid);
      expect(map['fullName'], 'אבי לוי');
    });

    test('toMap omits null optional fields (unitId, fcmToken, etc.)', () {
      final user = createTestUser(
        unitId: null,
        fcmToken: null,
        firebaseUid: null,
        approvalStatus: null,
        soloQuizPassedAt: null,
        soloQuizScore: null,
        commanderQuizPassedAt: null,
        commanderQuizScore: null,
        activeSessionId: null,
      );
      final map = user.toMap();

      expect(map.containsKey('unitId'), isFalse);
      expect(map.containsKey('fcmToken'), isFalse);
      expect(map.containsKey('firebaseUid'), isFalse);
      expect(map.containsKey('soloQuizPassedAt'), isFalse);
      expect(map.containsKey('soloQuizScore'), isFalse);
      expect(map.containsKey('commanderQuizPassedAt'), isFalse);
      expect(map.containsKey('commanderQuizScore'), isFalse);
      expect(map.containsKey('activeSessionId'), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // fromMap with defaults (missing fields)
  // ---------------------------------------------------------------------------
  group('fromMap with defaults', () {
    test('minimal map produces valid user with defaults', () {
      final map = <String, dynamic>{
        'uid': '9999999',
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      };
      final user = User.fromMap(map);

      expect(user.uid, '9999999');
      expect(user.firstName, '');
      expect(user.lastName, '');
      expect(user.phoneNumber, '');
      expect(user.phoneVerified, false);
      expect(user.email, '');
      expect(user.emailVerified, false);
      expect(user.role, 'navigator');
      expect(user.unitId, isNull);
      expect(user.fcmToken, isNull);
      expect(user.firebaseUid, isNull);
      expect(user.approvalStatus, isNull);
    });

    test('missing createdAt/updatedAt default to now', () {
      final user = User.fromMap({'uid': '1111111'});
      // Should not throw; createdAt/updatedAt are set via DateTime.now()
      expect(user.createdAt, isNotNull);
      expect(user.updatedAt, isNotNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Approval status 4-way Firestore conversion
  // ---------------------------------------------------------------------------
  group('approval status Firestore conversion', () {
    test('isApproved: true -> approvalStatus approved', () {
      final user = User.fromMap({
        'uid': '1111111',
        'isApproved': true,
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      });
      expect(user.approvalStatus, 'approved');
      expect(user.isApproved, isTrue);
    });

    test('isApproved: false -> approvalStatus rejected', () {
      final user = User.fromMap({
        'uid': '1111111',
        'isApproved': false,
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      });
      expect(user.approvalStatus, 'rejected');
      expect(user.isRejected, isTrue);
    });

    test('isApproved: "pending" -> approvalStatus pending', () {
      final user = User.fromMap({
        'uid': '1111111',
        'isApproved': 'pending',
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      });
      expect(user.approvalStatus, 'pending');
      expect(user.isPending, isTrue);
    });

    test('isApproved missing -> approvalStatus null', () {
      final user = User.fromMap({
        'uid': '1111111',
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      });
      expect(user.approvalStatus, isNull);
      expect(user.isApproved, isFalse);
      expect(user.isPending, isFalse);
      expect(user.isRejected, isFalse);
    });

    test('toMap writes isApproved: true when approved', () {
      final user = createTestUser(approvalStatus: 'approved');
      expect(user.toMap()['isApproved'], true);
    });

    test('toMap writes isApproved: false when rejected', () {
      final user = createTestUser(approvalStatus: 'rejected');
      expect(user.toMap()['isApproved'], false);
    });

    test('toMap writes isApproved: "pending" when pending', () {
      final user = createTestUser(approvalStatus: 'pending');
      expect(user.toMap()['isApproved'], 'pending');
    });

    test('toMap writes isApproved: null when approvalStatus is null', () {
      final user = createTestUser(approvalStatus: null);
      expect(user.toMap()['isApproved'], isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Computed getters for each role
  // ---------------------------------------------------------------------------
  group('role getters', () {
    test('navigator role', () {
      final user = createTestUser(role: 'navigator');
      expect(user.isNavigator, isTrue);
      expect(user.isCommander, isFalse);
      expect(user.isAdmin, isFalse);
      expect(user.isUnitAdmin, isFalse);
      expect(user.isDeveloper, isFalse);
      expect(user.hasCommanderPermissions, isFalse);
      expect(user.isManagement, isFalse);
    });

    test('commander role', () {
      final user = createTestUser(role: 'commander');
      expect(user.isCommander, isTrue);
      expect(user.isNavigator, isFalse);
      expect(user.hasCommanderPermissions, isTrue);
      expect(user.isManagement, isFalse);
    });

    test('admin role', () {
      final user = createTestUser(role: 'admin');
      expect(user.isAdmin, isTrue);
      expect(user.hasCommanderPermissions, isTrue);
      expect(user.isManagement, isTrue);
    });

    test('unit_admin role', () {
      final user = createTestUser(role: 'unit_admin');
      expect(user.isUnitAdmin, isTrue);
      expect(user.hasCommanderPermissions, isTrue);
      expect(user.isManagement, isTrue);
    });

    test('developer role', () {
      final user = createTestUser(role: 'developer');
      expect(user.isDeveloper, isTrue);
      expect(user.hasCommanderPermissions, isTrue);
      expect(user.isManagement, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // fullName
  // ---------------------------------------------------------------------------
  group('fullName', () {
    test('both names present', () {
      final user = createTestUser(firstName: 'דוד', lastName: 'כהן');
      expect(user.fullName, 'דוד כהן');
    });

    test('only firstName present', () {
      final user = createTestUser(firstName: 'דוד', lastName: '');
      expect(user.fullName, 'דוד');
    });

    test('only lastName present', () {
      final user = createTestUser(firstName: '', lastName: 'כהן');
      expect(user.fullName, 'כהן');
    });

    test('both empty', () {
      final user = createTestUser(firstName: '', lastName: '');
      expect(user.fullName, '');
    });

    test('whitespace-only names treated as empty', () {
      final user = createTestUser(firstName: '  ', lastName: '  ');
      expect(user.fullName, '');
    });
  });

  // ---------------------------------------------------------------------------
  // needsUnitSelection
  // ---------------------------------------------------------------------------
  group('needsUnitSelection', () {
    test('true for navigator without unit', () {
      final user = createTestUser(role: 'navigator', unitId: null);
      expect(user.needsUnitSelection, isTrue);
    });

    test('true for navigator with empty unitId', () {
      final user = createTestUser(role: 'navigator', unitId: '');
      expect(user.needsUnitSelection, isTrue);
    });

    test('false for navigator with unit', () {
      final user = createTestUser(role: 'navigator', unitId: 'unit-1');
      expect(user.needsUnitSelection, isFalse);
    });

    test('false for commander without unit (has commander permissions)', () {
      final user = createTestUser(role: 'commander', unitId: null);
      expect(user.needsUnitSelection, isFalse);
    });

    test('false for admin without unit', () {
      final user = createTestUser(role: 'admin', unitId: null);
      expect(user.needsUnitSelection, isFalse);
    });

    test('false for developer without unit', () {
      final user = createTestUser(role: 'developer', unitId: null);
      expect(user.needsUnitSelection, isFalse);
    });

    test('false for unit_admin without unit', () {
      final user = createTestUser(role: 'unit_admin', unitId: null);
      expect(user.needsUnitSelection, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // isOnboarded / isAwaitingApproval / wasRejected
  // ---------------------------------------------------------------------------
  group('onboarding state getters', () {
    test('isOnboarded: has unit and approved', () {
      final user = createTestUser(unitId: 'unit-1', approvalStatus: 'approved');
      expect(user.isOnboarded, isTrue);
      expect(user.isAwaitingApproval, isFalse);
      expect(user.wasRejected, isFalse);
    });

    test('isAwaitingApproval: has unit and pending', () {
      final user = createTestUser(unitId: 'unit-1', approvalStatus: 'pending');
      expect(user.isOnboarded, isFalse);
      expect(user.isAwaitingApproval, isTrue);
      expect(user.wasRejected, isFalse);
    });

    test('wasRejected: has unit and rejected', () {
      final user = createTestUser(unitId: 'unit-1', approvalStatus: 'rejected');
      expect(user.isOnboarded, isFalse);
      expect(user.isAwaitingApproval, isFalse);
      expect(user.wasRejected, isTrue);
    });

    test('no unit => none of the onboarding states are true', () {
      final user = createTestUser(unitId: null, approvalStatus: 'approved');
      expect(user.isOnboarded, isFalse);
      expect(user.isAwaitingApproval, isFalse);
      expect(user.wasRejected, isFalse);
    });

    test('empty unitId => none of the onboarding states are true', () {
      final user = createTestUser(unitId: '', approvalStatus: 'approved');
      expect(user.isOnboarded, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // copyWith: change fields + clear flags
  // ---------------------------------------------------------------------------
  group('copyWith', () {
    test('change regular fields', () {
      final user = createTestUser();
      final updated = user.copyWith(
        firstName: 'שרה',
        lastName: 'לוי',
        role: 'commander',
        email: 'sarah@test.com',
      );

      expect(updated.firstName, 'שרה');
      expect(updated.lastName, 'לוי');
      expect(updated.role, 'commander');
      expect(updated.email, 'sarah@test.com');
      // Unchanged fields remain
      expect(updated.uid, user.uid);
      expect(updated.phoneNumber, user.phoneNumber);
    });

    test('clearUnitId sets unitId to null', () {
      final user = createTestUser(unitId: 'unit-1');
      final updated = user.copyWith(clearUnitId: true);
      expect(updated.unitId, isNull);
    });

    test('clearApprovalStatus sets approvalStatus to null', () {
      final user = createTestUser(approvalStatus: 'approved');
      final updated = user.copyWith(clearApprovalStatus: true);
      expect(updated.approvalStatus, isNull);
    });

    test('clearFirebaseUid sets firebaseUid to null', () {
      final user = createTestUser(firebaseUid: 'fb-uid');
      final updated = user.copyWith(clearFirebaseUid: true);
      expect(updated.firebaseUid, isNull);
    });

    test('clearSoloQuizPassedAt sets soloQuizPassedAt to null', () {
      final user = createTestUser(soloQuizPassedAt: now);
      final updated = user.copyWith(clearSoloQuizPassedAt: true);
      expect(updated.soloQuizPassedAt, isNull);
    });

    test('clearSoloQuizScore sets soloQuizScore to null', () {
      final user = createTestUser(soloQuizScore: 85);
      final updated = user.copyWith(clearSoloQuizScore: true);
      expect(updated.soloQuizScore, isNull);
    });

    test('clearCommanderQuizPassedAt sets commanderQuizPassedAt to null', () {
      final user = createTestUser(commanderQuizPassedAt: now);
      final updated = user.copyWith(clearCommanderQuizPassedAt: true);
      expect(updated.commanderQuizPassedAt, isNull);
    });

    test('clearCommanderQuizScore sets commanderQuizScore to null', () {
      final user = createTestUser(commanderQuizScore: 95);
      final updated = user.copyWith(clearCommanderQuizScore: true);
      expect(updated.commanderQuizScore, isNull);
    });

    test('clearActiveSessionId sets activeSessionId to null', () {
      final user = createTestUser(activeSessionId: 'session-1');
      final updated = user.copyWith(clearActiveSessionId: true);
      expect(updated.activeSessionId, isNull);
    });

    test('clear flag takes priority over new value', () {
      final user = createTestUser(unitId: 'unit-1');
      final updated = user.copyWith(unitId: 'unit-2', clearUnitId: true);
      // clear flag wins
      expect(updated.unitId, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Backward compat: personalNumber key, fullName key splitting
  // ---------------------------------------------------------------------------
  group('backward compatibility', () {
    test('fromMap reads personalNumber when uid is missing', () {
      final user = User.fromMap({
        'personalNumber': '5555555',
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      });
      expect(user.uid, '5555555');
    });

    test('fromMap prefers uid over personalNumber', () {
      final user = User.fromMap({
        'uid': '1111111',
        'personalNumber': '2222222',
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      });
      expect(user.uid, '1111111');
    });

    test('fromMap splits fullName when firstName/lastName missing', () {
      final user = User.fromMap({
        'uid': '1234567',
        'fullName': 'משה כהן לוי',
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      });
      expect(user.firstName, 'משה');
      expect(user.lastName, 'כהן לוי');
    });

    test('fromMap splits single-word fullName into firstName only', () {
      final user = User.fromMap({
        'uid': '1234567',
        'fullName': 'משה',
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      });
      expect(user.firstName, 'משה');
      expect(user.lastName, '');
    });

    test('fromMap ignores fullName when firstName/lastName are present', () {
      final user = User.fromMap({
        'uid': '1234567',
        'firstName': 'דוד',
        'lastName': 'לוי',
        'fullName': 'משה כהן',
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      });
      expect(user.firstName, 'דוד');
      expect(user.lastName, 'לוי');
    });
  });

  // ---------------------------------------------------------------------------
  // Quiz validity
  // ---------------------------------------------------------------------------
  group('quiz validity', () {
    test('hasSoloQuizValid: recently passed (valid)', () {
      final user = createTestUser(
        soloQuizPassedAt: DateTime.now().subtract(const Duration(days: 10)),
        soloQuizScore: 90,
      );
      expect(user.hasSoloQuizValid, isTrue);
    });

    test('hasSoloQuizValid: passed long ago (invalid)', () {
      final user = createTestUser(
        soloQuizPassedAt: DateTime.now().subtract(const Duration(days: 200)),
        soloQuizScore: 90,
      );
      expect(user.hasSoloQuizValid, isFalse);
    });

    test('hasSoloQuizValid: null (invalid)', () {
      final user = createTestUser(soloQuizPassedAt: null);
      expect(user.hasSoloQuizValid, isFalse);
    });

    test('hasSoloQuizValid: exactly at 120 days boundary (valid)', () {
      // Passed exactly 119 days ago — should be valid
      final user = createTestUser(
        soloQuizPassedAt: DateTime.now().subtract(const Duration(days: 119)),
      );
      expect(user.hasSoloQuizValid, isTrue);
    });

    test('hasCommanderQuizValid: recently passed (valid)', () {
      final user = createTestUser(
        commanderQuizPassedAt: DateTime.now().subtract(const Duration(days: 5)),
        commanderQuizScore: 80,
      );
      expect(user.hasCommanderQuizValid, isTrue);
    });

    test('hasCommanderQuizValid: passed long ago (invalid)', () {
      final user = createTestUser(
        commanderQuizPassedAt: DateTime.now().subtract(const Duration(days: 150)),
        commanderQuizScore: 80,
      );
      expect(user.hasCommanderQuizValid, isFalse);
    });

    test('hasCommanderQuizValid: null (invalid)', () {
      final user = createTestUser(commanderQuizPassedAt: null);
      expect(user.hasCommanderQuizValid, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Equatable
  // ---------------------------------------------------------------------------
  group('Equatable', () {
    test('equal objects', () {
      final user1 = createTestUser(uid: '1234567', createdAt: now, updatedAt: now);
      final user2 = createTestUser(uid: '1234567', createdAt: now, updatedAt: now);
      expect(user1, equals(user2));
      expect(user1.hashCode, user2.hashCode);
    });

    test('different uid makes objects unequal', () {
      final user1 = createTestUser(uid: '1234567', createdAt: now, updatedAt: now);
      final user2 = createTestUser(uid: '7654321', createdAt: now, updatedAt: now);
      expect(user1, isNot(equals(user2)));
    });

    test('different role makes objects unequal', () {
      final user1 = createTestUser(role: 'navigator', createdAt: now, updatedAt: now);
      final user2 = createTestUser(role: 'commander', createdAt: now, updatedAt: now);
      expect(user1, isNot(equals(user2)));
    });

    test('different approvalStatus makes objects unequal', () {
      final user1 = createTestUser(approvalStatus: 'approved', createdAt: now, updatedAt: now);
      final user2 = createTestUser(approvalStatus: 'pending', createdAt: now, updatedAt: now);
      expect(user1, isNot(equals(user2)));
    });
  });

  // ---------------------------------------------------------------------------
  // bypassesOnboarding
  // ---------------------------------------------------------------------------
  group('bypassesOnboarding', () {
    test('true for admin', () {
      final user = createTestUser(role: 'admin');
      expect(user.bypassesOnboarding, isTrue);
    });

    test('true for developer', () {
      final user = createTestUser(role: 'developer');
      expect(user.bypassesOnboarding, isTrue);
    });

    test('false for commander', () {
      final user = createTestUser(role: 'commander');
      expect(user.bypassesOnboarding, isFalse);
    });

    test('false for navigator', () {
      final user = createTestUser(role: 'navigator');
      expect(user.bypassesOnboarding, isFalse);
    });

    test('false for unit_admin', () {
      final user = createTestUser(role: 'unit_admin');
      expect(user.bypassesOnboarding, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // personalNumber getter
  // ---------------------------------------------------------------------------
  group('personalNumber getter', () {
    test('returns uid', () {
      final user = createTestUser(uid: '7777777');
      expect(user.personalNumber, '7777777');
      expect(user.personalNumber, user.uid);
    });
  });

  // ---------------------------------------------------------------------------
  // toString
  // ---------------------------------------------------------------------------
  group('toString', () {
    test('contains uid, fullName, and role', () {
      final user = createTestUser(
        uid: '1234567',
        firstName: 'דוד',
        lastName: 'כהן',
        role: 'commander',
      );
      final str = user.toString();
      expect(str, contains('1234567'));
      expect(str, contains('דוד כהן'));
      expect(str, contains('commander'));
    });
  });
}
