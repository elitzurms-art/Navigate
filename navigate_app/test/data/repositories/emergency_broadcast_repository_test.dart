import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigate_app/data/repositories/emergency_broadcast_repository.dart';

void main() {
  late FakeFirebaseFirestore fakeFirestore;
  late EmergencyBroadcastRepository repository;

  const navId = 'nav_001';
  const commanderId = 'cmd_111';
  const participants = ['user_a', 'user_b', 'user_c'];

  setUp(() async {
    EmergencyBroadcastRepository.clearCache();
    fakeFirestore = FakeFirebaseFirestore();
    repository = EmergencyBroadcastRepository(firestore: fakeFirestore);

    // Seed navigation doc -- createBroadcast and cancelBroadcast use .update()
    // which requires the doc to exist.
    await fakeFirestore
        .collection('navigations')
        .doc(navId)
        .set({'status': 'active', 'emergencyActive': false});
  });

  tearDown(() {
    EmergencyBroadcastRepository.clearCache();
  });

  // ---------------------------------------------------------------------------
  // createBroadcast -- creates doc + updates navigation
  // ---------------------------------------------------------------------------
  group('createBroadcast', () {
    test('creates broadcast doc with correct fields', () async {
      final broadcastId = await repository.createBroadcast(
        navId,
        message: 'Emergency alert!',
        instructions: 'Take cover immediately',
        emergencyMode: 2,
        createdBy: commanderId,
        participants: participants,
      );

      expect(broadcastId, isNotEmpty);

      // Verify broadcast doc.
      final broadcastDoc = await fakeFirestore
          .collection('navigations')
          .doc(navId)
          .collection('emergency_broadcasts')
          .doc(broadcastId)
          .get();

      expect(broadcastDoc.exists, isTrue);
      final data = broadcastDoc.data()!;
      expect(data['message'], 'Emergency alert!');
      expect(data['instructions'], 'Take cover immediately');
      expect(data['emergencyMode'], 2);
      expect(data['createdBy'], commanderId);
      expect(data['participants'], participants);
      expect(data['acknowledgedBy'], isEmpty);
      expect(data['status'], 'active');
      expect(data['createdAt'], isNotNull);
    });

    test('updates navigation doc with emergency flags', () async {
      final broadcastId = await repository.createBroadcast(
        navId,
        message: 'Emergency!',
        instructions: 'Gather at rally point',
        emergencyMode: 1,
        createdBy: commanderId,
        participants: participants,
      );

      // Verify navigation doc was updated.
      final navDoc = await fakeFirestore
          .collection('navigations')
          .doc(navId)
          .get();

      final navData = navDoc.data()!;
      expect(navData['emergencyActive'], isTrue);
      expect(navData['emergencyMode'], 1);
      expect(navData['activeBroadcastId'], broadcastId);
    });
  });

  // ---------------------------------------------------------------------------
  // cancelBroadcast -- creates cancellation + marks original cancelled
  // ---------------------------------------------------------------------------
  group('cancelBroadcast', () {
    test('marks original broadcast cancelled and creates cancellation doc', () async {
      // First create a broadcast.
      final broadcastId = await repository.createBroadcast(
        navId,
        message: 'Emergency!',
        instructions: 'Take cover',
        emergencyMode: 1,
        createdBy: commanderId,
        participants: participants,
      );

      // Now cancel it.
      final cancelId = await repository.cancelBroadcast(
        navId,
        activeBroadcastId: broadcastId,
        createdBy: commanderId,
        participants: participants,
      );

      expect(cancelId, isNotEmpty);
      expect(cancelId, isNot(broadcastId));

      // Verify original broadcast is marked cancelled.
      final originalDoc = await fakeFirestore
          .collection('navigations')
          .doc(navId)
          .collection('emergency_broadcasts')
          .doc(broadcastId)
          .get();

      expect(originalDoc.data()!['status'], 'cancelled');
      expect(originalDoc.data()!['cancelledAt'], isNotNull);

      // Verify cancellation doc was created.
      final cancelDoc = await fakeFirestore
          .collection('navigations')
          .doc(navId)
          .collection('emergency_broadcasts')
          .doc(cancelId)
          .get();

      expect(cancelDoc.exists, isTrue);
      final cancelData = cancelDoc.data()!;
      expect(cancelData['type'], 'cancellation');
      expect(cancelData['originalBroadcastId'], broadcastId);
      expect(cancelData['participants'], participants);
      expect(cancelData['acknowledgedBy'], isEmpty);
      expect(cancelData['createdBy'], commanderId);

      // Verify navigation doc updated with emergencyActive=false.
      final navDoc = await fakeFirestore
          .collection('navigations')
          .doc(navId)
          .get();

      final navData = navDoc.data()!;
      expect(navData['emergencyActive'], isFalse);
      expect(navData['cancelBroadcastId'], cancelId);
    });
  });

  // ---------------------------------------------------------------------------
  // acknowledge -- adds userId to acknowledgedBy
  // ---------------------------------------------------------------------------
  group('acknowledge', () {
    test('adds userId to acknowledgedBy array', () async {
      final broadcastId = await repository.createBroadcast(
        navId,
        message: 'Emergency!',
        instructions: 'Take cover',
        emergencyMode: 1,
        createdBy: commanderId,
        participants: participants,
      );

      // Acknowledge from two participants.
      await repository.acknowledge(navId, broadcastId, 'user_a');
      await repository.acknowledge(navId, broadcastId, 'user_b');

      final doc = await fakeFirestore
          .collection('navigations')
          .doc(navId)
          .collection('emergency_broadcasts')
          .doc(broadcastId)
          .get();

      final acked = List<String>.from(doc.data()!['acknowledgedBy'] ?? []);
      expect(acked, contains('user_a'));
      expect(acked, contains('user_b'));
      expect(acked, isNot(contains('user_c')));
    });

    test('duplicate acknowledge does not add userId twice', () async {
      final broadcastId = await repository.createBroadcast(
        navId,
        message: 'Emergency!',
        instructions: 'Take cover',
        emergencyMode: 1,
        createdBy: commanderId,
        participants: participants,
      );

      await repository.acknowledge(navId, broadcastId, 'user_a');
      await repository.acknowledge(navId, broadcastId, 'user_a');

      final doc = await fakeFirestore
          .collection('navigations')
          .doc(navId)
          .collection('emergency_broadcasts')
          .doc(broadcastId)
          .get();

      final acked = List<String>.from(doc.data()!['acknowledgedBy'] ?? []);
      // FieldValue.arrayUnion ensures no duplicates.
      expect(acked.where((id) => id == 'user_a').length, 1);
    });
  });

  // ---------------------------------------------------------------------------
  // getBroadcastDoc -- returns doc data
  // ---------------------------------------------------------------------------
  group('getBroadcastDoc', () {
    test('returns doc data for existing broadcast', () async {
      final broadcastId = await repository.createBroadcast(
        navId,
        message: 'Emergency!',
        instructions: 'Rally point alpha',
        emergencyMode: 3,
        createdBy: commanderId,
        participants: participants,
      );

      final data = await repository.getBroadcastDoc(navId, broadcastId);

      expect(data, isNotNull);
      expect(data!['message'], 'Emergency!');
      expect(data['instructions'], 'Rally point alpha');
      expect(data['emergencyMode'], 3);
      expect(data['createdBy'], commanderId);
      expect(data['participants'], participants);
      expect(data['status'], 'active');
    });

    test('returns null for non-existent doc', () async {
      final data = await repository.getBroadcastDoc(navId, 'non_existent_id');

      expect(data, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // resendToUnacknowledged -- creates retry doc
  // ---------------------------------------------------------------------------
  group('resendToUnacknowledged', () {
    test('creates retry doc with only unacknowledged participants', () async {
      final broadcastId = await repository.createBroadcast(
        navId,
        message: 'Emergency alert!',
        instructions: 'Gather at point B',
        emergencyMode: 2,
        createdBy: commanderId,
        participants: participants, // user_a, user_b, user_c
      );

      // user_a acknowledges.
      await repository.acknowledge(navId, broadcastId, 'user_a');

      // Resend to unacknowledged.
      await repository.resendToUnacknowledged(navId, broadcastId);

      // Find the retry doc (it is a new doc, not the original).
      final snap = await fakeFirestore
          .collection('navigations')
          .doc(navId)
          .collection('emergency_broadcasts')
          .get();

      // Should have 2 docs: original + retry.
      expect(snap.docs.length, 2);

      final retryDoc = snap.docs.firstWhere((d) => d.id != broadcastId);
      final retryData = retryDoc.data();

      expect(retryData['status'], 'retry');
      expect(retryData['originalBroadcastId'], broadcastId);
      expect(retryData['message'], 'Emergency alert!');
      expect(retryData['instructions'], 'Gather at point B');
      expect(retryData['emergencyMode'], 2);
      expect(retryData['createdBy'], commanderId);
      expect(retryData['acknowledgedBy'], isEmpty);

      // Only user_b and user_c should be in retry participants.
      final retryParticipants = List<String>.from(retryData['participants']);
      expect(retryParticipants, containsAll(['user_b', 'user_c']));
      expect(retryParticipants, isNot(contains('user_a')));
      expect(retryParticipants.length, 2);
    });

    test('does not create retry doc if all acknowledged', () async {
      final broadcastId = await repository.createBroadcast(
        navId,
        message: 'Emergency!',
        instructions: 'Take cover',
        emergencyMode: 1,
        createdBy: commanderId,
        participants: participants, // user_a, user_b, user_c
      );

      // All participants acknowledge.
      await repository.acknowledge(navId, broadcastId, 'user_a');
      await repository.acknowledge(navId, broadcastId, 'user_b');
      await repository.acknowledge(navId, broadcastId, 'user_c');

      // Resend to unacknowledged -- should be no-op.
      await repository.resendToUnacknowledged(navId, broadcastId);

      // Should still have only 1 doc (the original).
      final snap = await fakeFirestore
          .collection('navigations')
          .doc(navId)
          .collection('emergency_broadcasts')
          .get();

      expect(snap.docs.length, 1);
      expect(snap.docs.first.id, broadcastId);
    });

    test('no-op for non-existent broadcast', () async {
      // Should not throw.
      await repository.resendToUnacknowledged(navId, 'non_existent_id');

      final snap = await fakeFirestore
          .collection('navigations')
          .doc(navId)
          .collection('emergency_broadcasts')
          .get();

      expect(snap.docs, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // clearCache -- disposes streams
  // ---------------------------------------------------------------------------
  group('clearCache', () {
    test('disposes streams without errors', () async {
      final broadcastId = await repository.createBroadcast(
        navId,
        message: 'Emergency!',
        instructions: 'Take cover',
        emergencyMode: 1,
        createdBy: commanderId,
        participants: participants,
      );

      // Subscribe to create a cached stream.
      final sub = repository.watchBroadcast(navId, broadcastId).listen((_) {});

      // clearCache should not throw.
      EmergencyBroadcastRepository.clearCache();

      sub.cancel();
    });
  });
}
