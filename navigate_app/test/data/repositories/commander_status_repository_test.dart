import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigate_app/data/repositories/commander_status_repository.dart';
import 'package:navigate_app/domain/entities/commander_location.dart';

void main() {
  late FakeFirebaseFirestore fakeFirestore;
  late CommanderStatusRepository repository;

  const navId = 'nav_001';
  const commanderId1 = 'cmd_111';
  const commanderId2 = 'cmd_222';

  /// Helper to seed a commander_status doc under navigations/{navId}/commander_status/{docId}.
  Future<void> seedCommanderStatus(
    String docId, {
    required Map<String, dynamic> data,
  }) async {
    await fakeFirestore
        .collection('navigations')
        .doc(navId)
        .collection('commander_status')
        .doc(docId)
        .set(data);
  }

  setUp(() {
    CommanderStatusRepository.clearCache();
    fakeFirestore = FakeFirebaseFirestore();
    repository = CommanderStatusRepository(firestore: fakeFirestore);
  });

  tearDown(() {
    CommanderStatusRepository.clearCache();
  });

  // ---------------------------------------------------------------------------
  // watchCommanderLocations -- emits locations on changes
  // ---------------------------------------------------------------------------
  group('watchCommanderLocations', () {
    test('emits locations on changes', () async {
      await seedCommanderStatus(commanderId1, data: {
        'userId': commanderId1,
        'name': 'Commander A',
        'latitude': 31.7683,
        'longitude': 35.2137,
        'updatedAt': '2026-03-14T10:00:00Z',
      });

      await seedCommanderStatus(commanderId2, data: {
        'userId': commanderId2,
        'name': 'Commander B',
        'latitude': 32.0853,
        'longitude': 34.7818,
        'updatedAt': '2026-03-14T10:05:00Z',
      });

      final result = await repository.watchCommanderLocations(navId).first;

      expect(result, isA<Map<String, CommanderLocation>>());
      expect(result.length, 2);
      expect(result.containsKey(commanderId1), isTrue);
      expect(result.containsKey(commanderId2), isTrue);

      // Verify first commander location.
      final loc1 = result[commanderId1]!;
      expect(loc1.userId, commanderId1);
      expect(loc1.name, 'Commander A');
      expect(loc1.position.latitude, 31.7683);
      expect(loc1.position.longitude, 35.2137);

      // Verify second commander location.
      final loc2 = result[commanderId2]!;
      expect(loc2.userId, commanderId2);
      expect(loc2.name, 'Commander B');
      expect(loc2.position.latitude, 32.0853);
      expect(loc2.position.longitude, 34.7818);
    });

    test('empty collection emits empty map', () async {
      final result = await repository.watchCommanderLocations(navId).first;

      expect(result, isA<Map<String, CommanderLocation>>());
      expect(result, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // publishLocation -- writes doc
  // ---------------------------------------------------------------------------
  group('publishLocation', () {
    test('writes doc to Firestore', () async {
      final data = {
        'userId': commanderId1,
        'name': 'Commander A',
        'latitude': 31.7683,
        'longitude': 35.2137,
        'updatedAt': '2026-03-14T10:00:00Z',
      };

      await repository.publishLocation(navId, commanderId1, data);

      // publishLocation uses unawaited(), so give a small delay for the
      // write to complete in the fake Firestore microtask queue.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final doc = await fakeFirestore
          .collection('navigations')
          .doc(navId)
          .collection('commander_status')
          .doc(commanderId1)
          .get();

      expect(doc.exists, isTrue);
      final written = doc.data()!;
      expect(written['userId'], commanderId1);
      expect(written['name'], 'Commander A');
      expect(written['latitude'], 31.7683);
      expect(written['longitude'], 35.2137);
    });

    test('merge preserves existing fields', () async {
      // Seed initial doc.
      await seedCommanderStatus(commanderId1, data: {
        'userId': commanderId1,
        'name': 'Commander A',
        'latitude': 31.0,
        'longitude': 35.0,
        'updatedAt': '2026-03-14T09:00:00Z',
      });

      // Publish partial update via repository (uses merge: true).
      await repository.publishLocation(navId, commanderId1, {
        'latitude': 32.0,
        'longitude': 34.0,
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final doc = await fakeFirestore
          .collection('navigations')
          .doc(navId)
          .collection('commander_status')
          .doc(commanderId1)
          .get();

      final written = doc.data()!;
      expect(written['name'], 'Commander A'); // preserved
      expect(written['latitude'], 32.0); // updated
      expect(written['longitude'], 34.0); // updated
    });
  });

  // ---------------------------------------------------------------------------
  // clearCache -- disposes streams
  // ---------------------------------------------------------------------------
  group('clearCache', () {
    test('disposes streams without errors', () {
      // Subscribe to create a cached stream.
      final sub = repository.watchCommanderLocations(navId).listen((_) {});

      // clearCache should not throw.
      CommanderStatusRepository.clearCache();

      sub.cancel();
    });

    test('after clearCache a fresh stream can be created', () async {
      // Create and dispose a stream.
      final sub = repository.watchCommanderLocations(navId).listen((_) {});
      CommanderStatusRepository.clearCache();
      sub.cancel();

      // Seed data and subscribe again with a fresh repo.
      final repo2 = CommanderStatusRepository(firestore: fakeFirestore);
      await seedCommanderStatus(commanderId1, data: {
        'userId': commanderId1,
        'name': 'Commander X',
        'latitude': 30.0,
        'longitude': 34.0,
        'updatedAt': '2026-03-14T12:00:00Z',
      });

      final result = await repo2.watchCommanderLocations(navId).first;
      expect(result.length, 1);
      expect(result[commanderId1]!.name, 'Commander X');
    });
  });
}
