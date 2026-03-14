import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigate_app/data/repositories/system_status_repository.dart';
import 'package:navigate_app/domain/entities/navigator_status.dart';

void main() {
  late FakeFirebaseFirestore fakeFirestore;
  late SystemStatusRepository repository;

  const navId = 'nav_001';
  const navigatorId1 = 'user_111';
  const navigatorId2 = 'user_222';

  /// Helper to seed a system_status doc under navigations/{navId}/system_status/{docId}.
  Future<void> seedStatus(
    String docId, {
    required Map<String, dynamic> data,
  }) async {
    await fakeFirestore
        .collection('navigations')
        .doc(navId)
        .collection('system_status')
        .doc(docId)
        .set(data);
  }

  setUp(() {
    SystemStatusRepository.clearCache();
    fakeFirestore = FakeFirebaseFirestore();
    repository = SystemStatusRepository(firestore: fakeFirestore);
  });

  tearDown(() {
    SystemStatusRepository.clearCache();
  });

  // ---------------------------------------------------------------------------
  // watchStatuses -- emits statuses on changes
  // ---------------------------------------------------------------------------
  group('watchStatuses', () {
    test('emits statuses on changes', () async {
      // Seed two navigator status docs.
      await seedStatus(navigatorId1, data: {
        'navigatorId': navigatorId1,
        'isConnected': true,
        'batteryLevel': 85,
        'hasGPS': true,
        'receptionLevel': 3,
        'latitude': 31.7683,
        'longitude': 35.2137,
        'positionSource': 'gps',
        'gpsAccuracy': 5.0,
        'mapsStatus': 'completed',
        'hasMicrophonePermission': true,
        'hasPhonePermission': false,
        'hasDNDPermission': true,
      });

      await seedStatus(navigatorId2, data: {
        'navigatorId': navigatorId2,
        'isConnected': false,
        'batteryLevel': 42,
        'hasGPS': false,
        'receptionLevel': 1,
        'gpsAccuracy': 50.0,
        'mapsStatus': 'notStarted',
      });

      final result = await repository.watchStatuses(navId).first;

      expect(result, isA<Map<String, NavigatorStatus>>());
      expect(result.length, 2);
      expect(result.containsKey(navigatorId1), isTrue);
      expect(result.containsKey(navigatorId2), isTrue);

      // Verify first navigator status.
      final status1 = result[navigatorId1]!;
      expect(status1.isConnected, isTrue);
      expect(status1.hasReported, isTrue);
      expect(status1.batteryLevel, 85);
      expect(status1.hasGPS, isTrue);
      expect(status1.receptionLevel, 3);
      expect(status1.latitude, 31.7683);
      expect(status1.longitude, 35.2137);
      expect(status1.positionSource, 'gps');
      expect(status1.gpsAccuracy, 5.0);
      expect(status1.mapsStatus, 'completed');
      expect(status1.mapsReady, isTrue);
      expect(status1.hasMicrophonePermission, isTrue);
      expect(status1.hasPhonePermission, isFalse);
      expect(status1.hasDNDPermission, isTrue);

      // Verify second navigator status.
      final status2 = result[navigatorId2]!;
      expect(status2.isConnected, isFalse);
      expect(status2.batteryLevel, 42);
      expect(status2.hasGPS, isFalse);
      expect(status2.receptionLevel, 1);
      expect(status2.mapsReady, isFalse);
    });

    test('empty collection emits empty map', () async {
      final result = await repository.watchStatuses(navId).first;

      expect(result, isA<Map<String, NavigatorStatus>>());
      expect(result, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // pollStatuses -- one-shot fetch
  // ---------------------------------------------------------------------------
  group('pollStatuses', () {
    test('one-shot fetch returns correct data', () async {
      await seedStatus(navigatorId1, data: {
        'navigatorId': navigatorId1,
        'isConnected': true,
        'batteryLevel': 90,
        'hasGPS': true,
        'receptionLevel': 4,
      });

      final result = await repository.pollStatuses(navId);

      expect(result, isA<Map<String, NavigatorStatus>>());
      expect(result.length, 1);
      expect(result.containsKey(navigatorId1), isTrue);

      final status = result[navigatorId1]!;
      expect(status.isConnected, isTrue);
      expect(status.batteryLevel, 90);
      expect(status.hasGPS, isTrue);
      expect(status.receptionLevel, 4);
    });
  });

  // ---------------------------------------------------------------------------
  // reportStatus -- writes doc
  // ---------------------------------------------------------------------------
  group('reportStatus', () {
    test('writes doc with merge', () async {
      final data = {
        'navigatorId': navigatorId1,
        'isConnected': true,
        'batteryLevel': 75,
        'hasGPS': true,
        'receptionLevel': 2,
        'latitude': 32.0853,
        'longitude': 34.7818,
        'positionSource': 'gps',
        'gpsAccuracy': 10.0,
        'mapsStatus': 'completed',
      };

      await repository.reportStatus(navId, navigatorId1, data);

      // Read back from fake Firestore.
      final doc = await fakeFirestore
          .collection('navigations')
          .doc(navId)
          .collection('system_status')
          .doc(navigatorId1)
          .get();

      expect(doc.exists, isTrue);
      final written = doc.data()!;
      expect(written['navigatorId'], navigatorId1);
      expect(written['isConnected'], isTrue);
      expect(written['batteryLevel'], 75);
      expect(written['hasGPS'], isTrue);
      expect(written['latitude'], 32.0853);
      expect(written['longitude'], 34.7818);
    });

    test('merge preserves existing fields', () async {
      // Write initial data.
      await repository.reportStatus(navId, navigatorId1, {
        'navigatorId': navigatorId1,
        'isConnected': true,
        'batteryLevel': 80,
      });

      // Merge partial update.
      await repository.reportStatus(navId, navigatorId1, {
        'batteryLevel': 60,
      });

      final doc = await fakeFirestore
          .collection('navigations')
          .doc(navId)
          .collection('system_status')
          .doc(navigatorId1)
          .get();

      final written = doc.data()!;
      expect(written['navigatorId'], navigatorId1); // preserved from first write
      expect(written['isConnected'], isTrue); // preserved from first write
      expect(written['batteryLevel'], 60); // updated
    });
  });

  // ---------------------------------------------------------------------------
  // deleteAll -- removes all docs
  // ---------------------------------------------------------------------------
  group('deleteAll', () {
    test('removes all docs from collection', () async {
      await seedStatus('nav_a', data: {'navigatorId': 'nav_a', 'isConnected': true, 'batteryLevel': 90, 'hasGPS': true});
      await seedStatus('nav_b', data: {'navigatorId': 'nav_b', 'isConnected': false, 'batteryLevel': 50, 'hasGPS': false});
      await seedStatus('nav_c', data: {'navigatorId': 'nav_c', 'isConnected': true, 'batteryLevel': 70, 'hasGPS': true});

      // Verify 3 docs exist before delete.
      var snap = await fakeFirestore
          .collection('navigations')
          .doc(navId)
          .collection('system_status')
          .get();
      expect(snap.docs.length, 3);

      await repository.deleteAll(navId);

      // Verify collection is empty.
      snap = await fakeFirestore
          .collection('navigations')
          .doc(navId)
          .collection('system_status')
          .get();
      expect(snap.docs, isEmpty);
    });

    test('no-op on empty collection', () async {
      // Should not throw.
      await repository.deleteAll(navId);

      final snap = await fakeFirestore
          .collection('navigations')
          .doc(navId)
          .collection('system_status')
          .get();
      expect(snap.docs, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // clearCache -- disposes streams
  // ---------------------------------------------------------------------------
  group('clearCache', () {
    test('disposes streams without errors', () {
      // Subscribe to create a cached stream.
      final sub = repository.watchStatuses(navId).listen((_) {});

      // clearCache should not throw.
      SystemStatusRepository.clearCache();

      sub.cancel();
    });

    test('after clearCache a fresh stream can be created', () async {
      // Create and dispose a stream.
      final sub = repository.watchStatuses(navId).listen((_) {});
      SystemStatusRepository.clearCache();
      sub.cancel();

      // Seed data and subscribe again with a fresh repo.
      final repo2 = SystemStatusRepository(firestore: fakeFirestore);
      await seedStatus(navigatorId1, data: {
        'navigatorId': navigatorId1,
        'isConnected': true,
        'batteryLevel': 50,
        'hasGPS': false,
      });

      final result = await repo2.watchStatuses(navId).first;
      expect(result.length, 1);
      expect(result[navigatorId1]!.batteryLevel, 50);
    });
  });
}
