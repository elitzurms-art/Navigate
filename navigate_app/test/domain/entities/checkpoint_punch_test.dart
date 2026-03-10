import 'package:flutter_test/flutter_test.dart';
import 'package:navigate_app/domain/entities/checkpoint_punch.dart';
import 'package:navigate_app/domain/entities/coordinate.dart';

void main() {
  final now = DateTime(2026, 3, 10, 12, 0, 0);
  final later = DateTime(2026, 3, 10, 12, 30, 0);

  final punchLocation = const Coordinate(lat: 31.5, lng: 34.75, utm: '123456789012');

  CheckpointPunch makePunch({
    String id = 'p1',
    String navigationId = 'nav1',
    String navigatorId = 'user1',
    String checkpointId = 'cp1',
    Coordinate? location,
    DateTime? punchTime,
    PunchStatus status = PunchStatus.active,
    double? distanceFromCheckpoint,
    String? rejectionReason,
    DateTime? approvalTime,
    String? approvedBy,
    int? punchIndex,
    String? supersededByPunchId,
  }) {
    return CheckpointPunch(
      id: id,
      navigationId: navigationId,
      navigatorId: navigatorId,
      checkpointId: checkpointId,
      punchLocation: location ?? punchLocation,
      punchTime: punchTime ?? now,
      status: status,
      distanceFromCheckpoint: distanceFromCheckpoint,
      rejectionReason: rejectionReason,
      approvalTime: approvalTime,
      approvedBy: approvedBy,
      punchIndex: punchIndex,
      supersededByPunchId: supersededByPunchId,
    );
  }

  // ===========================================================================
  // PunchStatus
  // ===========================================================================

  group('PunchStatus', () {
    test('fromCode returns correct enum for each known code', () {
      expect(PunchStatus.fromCode('active'), PunchStatus.active);
      expect(PunchStatus.fromCode('deleted'), PunchStatus.deleted);
      expect(PunchStatus.fromCode('approved'), PunchStatus.approved);
      expect(PunchStatus.fromCode('rejected'), PunchStatus.rejected);
    });

    test('fromCode falls back to active for unknown code', () {
      expect(PunchStatus.fromCode('unknown'), PunchStatus.active);
      expect(PunchStatus.fromCode(''), PunchStatus.active);
    });

    test('code and displayName are correct', () {
      expect(PunchStatus.active.code, 'active');
      expect(PunchStatus.deleted.code, 'deleted');
      expect(PunchStatus.approved.code, 'approved');
      expect(PunchStatus.rejected.code, 'rejected');
    });
  });

  // ===========================================================================
  // CheckpointPunch
  // ===========================================================================

  group('CheckpointPunch', () {
    // ---- toMap / fromMap roundtrip ----

    group('toMap / fromMap', () {
      test('roundtrip with all fields preserves data', () {
        final punch = makePunch(
          status: PunchStatus.approved,
          distanceFromCheckpoint: 15.3,
          rejectionReason: 'Too far',
          approvalTime: later,
          approvedBy: 'cmd1',
          punchIndex: 2,
          supersededByPunchId: 'p_old',
        );

        final map = punch.toMap();
        final restored = CheckpointPunch.fromMap(map);

        expect(restored.id, punch.id);
        expect(restored.navigationId, punch.navigationId);
        expect(restored.navigatorId, punch.navigatorId);
        expect(restored.checkpointId, punch.checkpointId);
        expect(restored.punchLocation.lat, punchLocation.lat);
        expect(restored.punchLocation.lng, punchLocation.lng);
        expect(restored.punchLocation.utm, punchLocation.utm);
        expect(restored.punchTime, punch.punchTime);
        expect(restored.status, PunchStatus.approved);
        expect(restored.distanceFromCheckpoint, 15.3);
        expect(restored.rejectionReason, 'Too far');
        expect(restored.approvalTime, later);
        expect(restored.approvedBy, 'cmd1');
        expect(restored.punchIndex, 2);
        expect(restored.supersededByPunchId, 'p_old');
      });

      test('roundtrip with minimal (required-only) fields', () {
        final punch = makePunch();

        final map = punch.toMap();
        final restored = CheckpointPunch.fromMap(map);

        expect(restored.id, 'p1');
        expect(restored.status, PunchStatus.active);
        expect(restored.distanceFromCheckpoint, isNull);
        expect(restored.rejectionReason, isNull);
        expect(restored.approvalTime, isNull);
        expect(restored.approvedBy, isNull);
        expect(restored.punchIndex, isNull);
        expect(restored.supersededByPunchId, isNull);
      });

      test('toMap flattens punchLocation into punchLat/punchLng/punchUtm', () {
        final map = makePunch().toMap();
        expect(map['punchLat'], punchLocation.lat);
        expect(map['punchLng'], punchLocation.lng);
        expect(map['punchUtm'], punchLocation.utm);
        expect(map.containsKey('punchLocation'), isFalse);
      });

      test('fromMap reconstructs Coordinate from flat fields', () {
        final map = {
          'id': 'p2',
          'navigationId': 'nav1',
          'navigatorId': 'user1',
          'checkpointId': 'cp1',
          'punchLat': 32.0,
          'punchLng': 35.0,
          'punchUtm': '999999999999',
          'punchTime': now.toIso8601String(),
          'status': 'active',
        };

        final punch = CheckpointPunch.fromMap(map);
        expect(punch.punchLocation.lat, 32.0);
        expect(punch.punchLocation.lng, 35.0);
        expect(punch.punchLocation.utm, '999999999999');
      });
    });

    // ---- Conditional field omission in toMap ----

    group('toMap conditional fields', () {
      test('omits optional fields when null', () {
        final map = makePunch().toMap();
        expect(map.containsKey('distanceFromCheckpoint'), isFalse);
        expect(map.containsKey('rejectionReason'), isFalse);
        expect(map.containsKey('approvalTime'), isFalse);
        expect(map.containsKey('approvedBy'), isFalse);
        expect(map.containsKey('punchIndex'), isFalse);
        expect(map.containsKey('supersededByPunchId'), isFalse);
      });

      test('includes optional fields when present', () {
        final map = makePunch(
          distanceFromCheckpoint: 5.0,
          rejectionReason: 'reason',
          approvalTime: later,
          approvedBy: 'cmd1',
          punchIndex: 0,
          supersededByPunchId: 'p99',
        ).toMap();

        expect(map.containsKey('distanceFromCheckpoint'), isTrue);
        expect(map.containsKey('rejectionReason'), isTrue);
        expect(map.containsKey('approvalTime'), isTrue);
        expect(map.containsKey('approvedBy'), isTrue);
        expect(map.containsKey('punchIndex'), isTrue);
        expect(map.containsKey('supersededByPunchId'), isTrue);
      });
    });

    // ---- Boolean getters ----

    group('isScoreable', () {
      test('active punch without superseding is scoreable', () {
        expect(makePunch(status: PunchStatus.active).isScoreable, isTrue);
      });

      test('approved punch is scoreable', () {
        expect(makePunch(status: PunchStatus.approved).isScoreable, isTrue);
      });

      test('deleted punch is not scoreable', () {
        expect(makePunch(status: PunchStatus.deleted).isScoreable, isFalse);
      });

      test('rejected punch is not scoreable', () {
        expect(makePunch(status: PunchStatus.rejected).isScoreable, isFalse);
      });

      test('superseded punch is not scoreable', () {
        expect(
          makePunch(status: PunchStatus.active, supersededByPunchId: 'p2').isScoreable,
          isFalse,
        );
      });
    });

    group('isActive', () {
      test('active non-superseded punch is active', () {
        expect(makePunch(status: PunchStatus.active).isActive, isTrue);
      });

      test('deleted punch is not active', () {
        expect(makePunch(status: PunchStatus.deleted).isActive, isFalse);
      });

      test('superseded punch is not active', () {
        expect(
          makePunch(status: PunchStatus.active, supersededByPunchId: 'p2').isActive,
          isFalse,
        );
      });

      test('approved but not superseded is active', () {
        expect(makePunch(status: PunchStatus.approved).isActive, isTrue);
      });
    });

    group('isPending', () {
      test('active status means pending', () {
        expect(makePunch(status: PunchStatus.active).isPending, isTrue);
      });

      test('approved status is not pending', () {
        expect(makePunch(status: PunchStatus.approved).isPending, isFalse);
      });
    });

    group('isApproved / isRejected / isDeleted / isSuperseded', () {
      test('isApproved', () {
        expect(makePunch(status: PunchStatus.approved).isApproved, isTrue);
        expect(makePunch(status: PunchStatus.active).isApproved, isFalse);
      });

      test('isRejected', () {
        expect(makePunch(status: PunchStatus.rejected).isRejected, isTrue);
        expect(makePunch(status: PunchStatus.active).isRejected, isFalse);
      });

      test('isDeleted', () {
        expect(makePunch(status: PunchStatus.deleted).isDeleted, isTrue);
        expect(makePunch(status: PunchStatus.active).isDeleted, isFalse);
      });

      test('isSuperseded', () {
        expect(makePunch(supersededByPunchId: 'p2').isSuperseded, isTrue);
        expect(makePunch(supersededByPunchId: null).isSuperseded, isFalse);
      });
    });

    // ---- copyWith ----

    group('copyWith', () {
      test('changes specified fields and preserves the rest', () {
        final original = makePunch(punchIndex: 0, status: PunchStatus.active);
        final updated = original.copyWith(
          status: PunchStatus.approved,
          approvedBy: 'cmd1',
          approvalTime: later,
        );

        expect(updated.status, PunchStatus.approved);
        expect(updated.approvedBy, 'cmd1');
        expect(updated.approvalTime, later);
        expect(updated.id, original.id);
        expect(updated.punchIndex, 0);
        expect(updated.navigationId, original.navigationId);
      });

      test('returns new instance even with no changes', () {
        final original = makePunch();
        final updated = original.copyWith();
        expect(updated, equals(original));
        expect(identical(updated, original), isFalse);
      });
    });

    // ---- Equatable ----

    group('Equatable', () {
      test('two punches with same props are equal', () {
        final a = makePunch();
        final b = makePunch();
        expect(a, equals(b));
      });

      test('punches with different id are not equal', () {
        final a = makePunch(id: 'p1');
        final b = makePunch(id: 'p2');
        expect(a, isNot(equals(b)));
      });

      test('punches with different status are not equal', () {
        final a = makePunch(status: PunchStatus.active);
        final b = makePunch(status: PunchStatus.deleted);
        expect(a, isNot(equals(b)));
      });
    });
  });

  // ===========================================================================
  // AlertType
  // ===========================================================================

  group('AlertType', () {
    test('fromCode returns correct enum for each known code', () {
      expect(AlertType.fromCode('emergency'), AlertType.emergency);
      expect(AlertType.fromCode('barbur'), AlertType.barbur);
      expect(AlertType.fromCode('health_check_expired'), AlertType.healthCheckExpired);
      expect(AlertType.fromCode('health_report'), AlertType.healthReport);
      expect(AlertType.fromCode('speed'), AlertType.speed);
      expect(AlertType.fromCode('no_movement'), AlertType.noMovement);
      expect(AlertType.fromCode('boundary'), AlertType.boundary);
      expect(AlertType.fromCode('route_deviation'), AlertType.routeDeviation);
      expect(AlertType.fromCode('safety_point'), AlertType.safetyPoint);
      expect(AlertType.fromCode('proximity'), AlertType.proximity);
      expect(AlertType.fromCode('battery'), AlertType.battery);
      expect(AlertType.fromCode('no_reception'), AlertType.noReception);
      expect(AlertType.fromCode('security_breach'), AlertType.securityBreach);
    });

    test('fromCode falls back to emergency for unknown code', () {
      expect(AlertType.fromCode('unknown'), AlertType.emergency);
      expect(AlertType.fromCode(''), AlertType.emergency);
    });

    test('each alert type has non-empty code, displayName, and emoji', () {
      for (final type in AlertType.values) {
        expect(type.code, isNotEmpty);
        expect(type.displayName, isNotEmpty);
        expect(type.emoji, isNotEmpty);
      }
    });
  });

  // ===========================================================================
  // NavigatorAlert
  // ===========================================================================

  group('NavigatorAlert', () {
    final alertLocation = const Coordinate(lat: 31.5, lng: 34.75, utm: '123456789012');

    NavigatorAlert makeAlert({
      String id = 'a1',
      String navigationId = 'nav1',
      String navigatorId = 'user1',
      AlertType type = AlertType.barbur,
      Coordinate? location,
      DateTime? timestamp,
      bool isActive = true,
      DateTime? resolvedAt,
      String? resolvedBy,
      int? minutesOverdue,
      String? navigatorName,
      Map<String, bool>? barburChecklist,
    }) {
      return NavigatorAlert(
        id: id,
        navigationId: navigationId,
        navigatorId: navigatorId,
        type: type,
        location: location ?? alertLocation,
        timestamp: timestamp ?? now,
        isActive: isActive,
        resolvedAt: resolvedAt,
        resolvedBy: resolvedBy,
        minutesOverdue: minutesOverdue,
        navigatorName: navigatorName,
        barburChecklist: barburChecklist,
      );
    }

    group('toMap / fromMap', () {
      test('roundtrip with all fields including barburChecklist', () {
        final checklist = {
          'returnToAxis': true,
          'goToHighPoint': false,
          'openMap': true,
          'showLocation': false,
        };

        final alert = makeAlert(
          isActive: false,
          resolvedAt: later,
          resolvedBy: 'cmd1',
          minutesOverdue: 15,
          navigatorName: 'John',
          barburChecklist: checklist,
        );

        final map = alert.toMap();
        final restored = NavigatorAlert.fromMap(map);

        expect(restored.id, alert.id);
        expect(restored.navigationId, alert.navigationId);
        expect(restored.navigatorId, alert.navigatorId);
        expect(restored.type, AlertType.barbur);
        expect(restored.location.lat, alertLocation.lat);
        expect(restored.location.lng, alertLocation.lng);
        expect(restored.location.utm, alertLocation.utm);
        expect(restored.timestamp, now);
        expect(restored.isActive, isFalse);
        expect(restored.resolvedAt, later);
        expect(restored.resolvedBy, 'cmd1');
        expect(restored.minutesOverdue, 15);
        expect(restored.navigatorName, 'John');
        expect(restored.barburChecklist, checklist);
      });

      test('fromMap handles missing optional fields gracefully', () {
        final map = {
          'id': 'a2',
          'navigationId': 'nav1',
          'navigatorId': 'user1',
          'type': 'emergency',
          'lat': 31.5,
          'lng': 34.75,
          'utm': '123456789012',
          'timestamp': now.toIso8601String(),
          // isActive, resolvedAt, resolvedBy, minutesOverdue,
          // navigatorName, barburChecklist all missing
        };

        final alert = NavigatorAlert.fromMap(map);

        expect(alert.type, AlertType.emergency);
        expect(alert.isActive, isTrue);
        expect(alert.resolvedAt, isNull);
        expect(alert.resolvedBy, isNull);
        expect(alert.minutesOverdue, isNull);
        expect(alert.navigatorName, isNull);
        expect(alert.barburChecklist, isNull);
      });

      test('toMap flattens location into lat/lng/utm', () {
        final map = makeAlert().toMap();
        expect(map['lat'], alertLocation.lat);
        expect(map['lng'], alertLocation.lng);
        expect(map['utm'], alertLocation.utm);
        expect(map.containsKey('location'), isFalse);
      });

      test('toMap omits conditional fields when null', () {
        final map = makeAlert().toMap();
        expect(map.containsKey('resolvedAt'), isFalse);
        expect(map.containsKey('resolvedBy'), isFalse);
        expect(map.containsKey('minutesOverdue'), isFalse);
        expect(map.containsKey('navigatorName'), isFalse);
        expect(map.containsKey('barburChecklist'), isFalse);
      });

      test('toMap stores type as code string', () {
        final map = makeAlert(type: AlertType.speed).toMap();
        expect(map['type'], 'speed');
      });

      test('fromMap with missing lat/lng defaults to 0', () {
        final map = {
          'id': 'a3',
          'navigationId': 'nav1',
          'navigatorId': 'user1',
          'type': 'emergency',
          'timestamp': now.toIso8601String(),
          // lat, lng, utm missing
        };

        final alert = NavigatorAlert.fromMap(map);
        expect(alert.location.lat, 0.0);
        expect(alert.location.lng, 0.0);
        expect(alert.location.utm, '');
      });
    });

    group('Equatable', () {
      test('alerts with same props are equal', () {
        final a = makeAlert();
        final b = makeAlert();
        expect(a, equals(b));
      });

      test('alerts with different id are not equal', () {
        final a = makeAlert(id: 'a1');
        final b = makeAlert(id: 'a2');
        expect(a, isNot(equals(b)));
      });

      test('alerts with different barburChecklist are not equal', () {
        final a = makeAlert(barburChecklist: {'returnToAxis': true});
        final b = makeAlert(barburChecklist: {'returnToAxis': false});
        expect(a, isNot(equals(b)));
      });
    });
  });
}
