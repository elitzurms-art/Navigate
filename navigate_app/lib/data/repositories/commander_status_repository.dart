import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/app_constants.dart';
import '../../domain/entities/commander_location.dart';
import '../sync/ref_counted_stream.dart';

/// Repository לניהול מיקומי מפקדים בזמן אמת
class CommanderStatusRepository {
  final FirebaseFirestore _firestore;

  CommanderStatusRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  static final Map<String, RefCountedStream<Map<String, CommanderLocation>>>
      _streams = {};

  CollectionReference<Map<String, dynamic>> _statusCollection(
          String navigationId) =>
      _firestore
          .collection(AppConstants.navigationsCollection)
          .doc(navigationId)
          .collection('commander_status');

  /// מאזין למיקומי מפקדים בניווט נתון
  Stream<Map<String, CommanderLocation>> watchCommanderLocations(
      String navigationId) {
    final key = 'commander_status_$navigationId';
    _streams[key] ??= RefCountedStream<Map<String, CommanderLocation>>(
      sourceFactory: () => _statusCollection(navigationId)
          .snapshots()
          .map((snap) => _parseLocations(snap)),
      pollFallback: () => _pollLocations(navigationId),
    );
    return _streams[key]!.stream;
  }

  /// פרסום מיקום מפקד ל-Firestore (non-blocking)
  Future<void> publishLocation(
    String navigationId,
    String commanderId,
    Map<String, dynamic> data,
  ) async {
    unawaited(_statusCollection(navigationId)
        .doc(commanderId)
        .set(data, SetOptions(merge: true))
        .catchError((_) {}));
  }

  Future<Map<String, CommanderLocation>> _pollLocations(
      String navigationId) async {
    final snap = await _statusCollection(navigationId).get();
    return _parseLocations(snap);
  }

  Map<String, CommanderLocation> _parseLocations(
      QuerySnapshot<Map<String, dynamic>> snap) {
    final result = <String, CommanderLocation>{};
    for (final doc in snap.docs) {
      result[doc.id] = CommanderLocation.fromFirestore(doc.id, doc.data());
    }
    return result;
  }

  static void clearCache() {
    for (final stream in _streams.values) {
      stream.dispose();
    }
    _streams.clear();
  }
}
