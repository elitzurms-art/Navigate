import 'package:flutter_test/flutter_test.dart';
import 'package:navigate_app/domain/entities/security_violation.dart';

void main() {
  group('ViolationType', () {
    test('fromCode returns exitLockTask for exit_lock_task', () {
      expect(ViolationType.fromCode('exit_lock_task'), ViolationType.exitLockTask);
    });

    test('fromCode returns appBackgrounded for app_backgrounded', () {
      expect(ViolationType.fromCode('app_backgrounded'), ViolationType.appBackgrounded);
    });

    test('fromCode returns screenOff for screen_off', () {
      expect(ViolationType.fromCode('screen_off'), ViolationType.screenOff);
    });

    test('fromCode returns screenOn for screen_on', () {
      expect(ViolationType.fromCode('screen_on'), ViolationType.screenOn);
    });

    test('fromCode returns appClosed for app_closed', () {
      expect(ViolationType.fromCode('app_closed'), ViolationType.appClosed);
    });

    test('fromCode returns exitGuidedAccess for exit_guided_access', () {
      expect(ViolationType.fromCode('exit_guided_access'), ViolationType.exitGuidedAccess);
    });

    test('fromCode returns gpsDisabled for gps_disabled', () {
      expect(ViolationType.fromCode('gps_disabled'), ViolationType.gpsDisabled);
    });

    test('fromCode returns internetDisconnected for internet_disconnected', () {
      expect(ViolationType.fromCode('internet_disconnected'), ViolationType.internetDisconnected);
    });

    test('fromCode returns phoneCallAnswered for phone_call_answered', () {
      expect(ViolationType.fromCode('phone_call_answered'), ViolationType.phoneCallAnswered);
    });

    test('fromCode returns appResignedActive for app_resigned_active', () {
      expect(ViolationType.fromCode('app_resigned_active'), ViolationType.appResignedActive);
    });

    test('fromCode returns appBecameActive for app_became_active', () {
      expect(ViolationType.fromCode('app_became_active'), ViolationType.appBecameActive);
    });

    test('fromCode returns foregroundIntegrityViolation for foreground_integrity_violation', () {
      expect(
        ViolationType.fromCode('foreground_integrity_violation'),
        ViolationType.foregroundIntegrityViolation,
      );
    });

    test('fromCode returns securityTamperingDetected for security_tampering_detected', () {
      expect(
        ViolationType.fromCode('security_tampering_detected'),
        ViolationType.securityTamperingDetected,
      );
    });

    test('fromCode returns appClosed for unknown code', () {
      expect(ViolationType.fromCode('unknown_code'), ViolationType.appClosed);
      expect(ViolationType.fromCode(''), ViolationType.appClosed);
      expect(ViolationType.fromCode('not_a_real_type'), ViolationType.appClosed);
    });
  });

  group('ViolationSeverity', () {
    test('has exactly 4 values: low, medium, high, critical', () {
      expect(ViolationSeverity.values.length, 4);
      expect(ViolationSeverity.values, [
        ViolationSeverity.low,
        ViolationSeverity.medium,
        ViolationSeverity.high,
        ViolationSeverity.critical,
      ]);
    });

    test('each severity has code, displayName, and emoji', () {
      expect(ViolationSeverity.low.code, 'low');
      expect(ViolationSeverity.low.displayName, 'נמוכה');
      expect(ViolationSeverity.low.emoji, 'ℹ️');

      expect(ViolationSeverity.medium.code, 'medium');
      expect(ViolationSeverity.medium.displayName, 'בינונית');
      expect(ViolationSeverity.medium.emoji, '⚠️');

      expect(ViolationSeverity.high.code, 'high');
      expect(ViolationSeverity.high.displayName, 'גבוהה');
      expect(ViolationSeverity.high.emoji, '🔴');

      expect(ViolationSeverity.critical.code, 'critical');
      expect(ViolationSeverity.critical.displayName, 'קריטית');
      expect(ViolationSeverity.critical.emoji, '🚨');
    });
  });

  group('SecurityViolation', () {
    final timestamp = DateTime(2026, 3, 10, 14, 30, 0);

    SecurityViolation createViolation({
      Map<String, dynamic>? metadata,
    }) {
      return SecurityViolation(
        id: 'v1',
        navigationId: 'nav1',
        navigatorId: 'user1',
        type: ViolationType.appBackgrounded,
        severity: ViolationSeverity.high,
        description: 'מעבר לרקע',
        timestamp: timestamp,
        metadata: metadata,
      );
    }

    test('toMap and fromMap roundtrip without metadata', () {
      final violation = createViolation();
      final map = violation.toMap();
      final restored = SecurityViolation.fromMap(map);

      expect(restored.id, violation.id);
      expect(restored.navigationId, violation.navigationId);
      expect(restored.navigatorId, violation.navigatorId);
      expect(restored.type, violation.type);
      expect(restored.severity, violation.severity);
      expect(restored.description, violation.description);
      expect(restored.timestamp, violation.timestamp);
      expect(restored.metadata, isNull);
    });

    test('fromMap with metadata preserves metadata map', () {
      final metadata = {'gpsLat': 31.5, 'gpsLng': 34.8, 'battery': 85};
      final violation = createViolation(metadata: metadata);
      final map = violation.toMap();
      final restored = SecurityViolation.fromMap(map);

      expect(restored.metadata, isNotNull);
      expect(restored.metadata!['gpsLat'], 31.5);
      expect(restored.metadata!['gpsLng'], 34.8);
      expect(restored.metadata!['battery'], 85);
    });

    test('toMap omits metadata when null', () {
      final violation = createViolation();
      final map = violation.toMap();

      expect(map.containsKey('metadata'), isFalse);
    });

    test('toMap includes metadata when present', () {
      final violation = createViolation(metadata: {'key': 'value'});
      final map = violation.toMap();

      expect(map.containsKey('metadata'), isTrue);
      expect(map['metadata'], {'key': 'value'});
    });

    test('Equatable compares by id, navigationId, navigatorId, type, severity, timestamp', () {
      final v1 = createViolation();
      final v2 = createViolation();

      expect(v1, equals(v2));

      // Different metadata but same props — still equal
      final v3 = createViolation(metadata: {'extra': true});
      expect(v1, equals(v3));

      // Different id — not equal
      final v4 = SecurityViolation(
        id: 'v2',
        navigationId: 'nav1',
        navigatorId: 'user1',
        type: ViolationType.appBackgrounded,
        severity: ViolationSeverity.high,
        description: 'מעבר לרקע',
        timestamp: timestamp,
      );
      expect(v1, isNot(equals(v4)));
    });

    test('fromMap resolves severity fallback to medium for unknown code', () {
      final map = {
        'id': 'v1',
        'navigationId': 'nav1',
        'navigatorId': 'user1',
        'type': 'app_backgrounded',
        'severity': 'unknown_severity',
        'description': 'test',
        'timestamp': timestamp.toIso8601String(),
      };

      final violation = SecurityViolation.fromMap(map);
      expect(violation.severity, ViolationSeverity.medium);
    });
  });

  group('SecuritySettings', () {
    test('defaults are correct', () {
      const settings = SecuritySettings();

      expect(settings.lockTaskEnabled, isTrue);
      expect(settings.requireGuidedAccess, isTrue);
      expect(settings.unlockCode, isNull);
      expect(settings.alertOnBackground, isTrue);
      expect(settings.alertOnScreenOff, isFalse);
      expect(settings.maxViolationsBeforeAlert, 3);
    });

    test('toMap and fromMap roundtrip with all fields', () {
      const settings = SecuritySettings(
        lockTaskEnabled: false,
        requireGuidedAccess: false,
        unlockCode: '1234',
        alertOnBackground: false,
        alertOnScreenOff: true,
        maxViolationsBeforeAlert: 5,
      );

      final map = settings.toMap();
      final restored = SecuritySettings.fromMap(map);

      expect(restored.lockTaskEnabled, isFalse);
      expect(restored.requireGuidedAccess, isFalse);
      expect(restored.unlockCode, '1234');
      expect(restored.alertOnBackground, isFalse);
      expect(restored.alertOnScreenOff, isTrue);
      expect(restored.maxViolationsBeforeAlert, 5);
    });

    test('fromMap uses defaults for missing fields', () {
      final settings = SecuritySettings.fromMap({});

      expect(settings.lockTaskEnabled, isTrue);
      expect(settings.requireGuidedAccess, isTrue);
      expect(settings.unlockCode, isNull);
      expect(settings.alertOnBackground, isTrue);
      expect(settings.alertOnScreenOff, isFalse);
      expect(settings.maxViolationsBeforeAlert, 3);
    });

    test('copyWith replaces specified fields only', () {
      const original = SecuritySettings();
      final modified = original.copyWith(
        lockTaskEnabled: false,
        maxViolationsBeforeAlert: 10,
      );

      expect(modified.lockTaskEnabled, isFalse);
      expect(modified.requireGuidedAccess, isTrue); // unchanged
      expect(modified.alertOnBackground, isTrue); // unchanged
      expect(modified.maxViolationsBeforeAlert, 10);
    });

    test('toMap omits unlockCode when null', () {
      const settings = SecuritySettings();
      final map = settings.toMap();

      expect(map.containsKey('unlockCode'), isFalse);
    });

    test('toMap includes unlockCode when present', () {
      const settings = SecuritySettings(unlockCode: 'secret');
      final map = settings.toMap();

      expect(map.containsKey('unlockCode'), isTrue);
      expect(map['unlockCode'], 'secret');
    });

    test('Equatable compares all fields', () {
      const s1 = SecuritySettings();
      const s2 = SecuritySettings();
      expect(s1, equals(s2));

      const s3 = SecuritySettings(lockTaskEnabled: false);
      expect(s1, isNot(equals(s3)));

      const s4 = SecuritySettings(unlockCode: '1234');
      expect(s1, isNot(equals(s4)));
    });
  });
}
