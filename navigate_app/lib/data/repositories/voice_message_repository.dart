import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../domain/entities/voice_message.dart';

/// Repository להודעות קוליות — Firestore בלבד (ללא Drift, real-time)
class VoiceMessageRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// שליחת הודעה קולית
  Future<VoiceMessage> sendMessage({
    required String navigationId,
    required String filePath,
    required double duration,
    required String senderId,
    required String senderName,
    String? targetId,
    String? targetName,
  }) async {
    // העלאת קובץ אודיו ל-Firebase Storage
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final storagePath = 'voice_messages/$navigationId/$timestamp.m4a';
    final ref = _storage.ref().child(storagePath);

    await ref.putFile(File(filePath));
    final downloadUrl = await ref.getDownloadURL();

    // יצירת מסמך ב-Firestore
    final docRef = _firestore
        .collection('rooms')
        .doc(navigationId)
        .collection('messages')
        .doc();

    final messageData = {
      'type': 'voice',
      'audioUrl': downloadUrl,
      'duration': duration,
      'senderId': senderId,
      'senderName': senderName,
      if (targetId != null) 'targetId': targetId,
      if (targetName != null) 'targetName': targetName,
      'createdAt': FieldValue.serverTimestamp(),
    };

    await docRef.set(messageData);

    // מחיקת קובץ זמני
    try {
      await File(filePath).delete();
    } catch (_) {}

    return VoiceMessage(
      id: docRef.id,
      navigationId: navigationId,
      senderId: senderId,
      senderName: senderName,
      targetId: targetId,
      targetName: targetName,
      audioUrl: downloadUrl,
      duration: duration,
      createdAt: DateTime.now(),
    );
  }

  /// האזנה להודעות בזמן אמת
  Stream<List<VoiceMessage>> watchMessages(
    String navigationId, {
    required String currentUserId,
  }) {
    return _firestore
        .collection('rooms')
        .doc(navigationId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            data['navigationId'] = navigationId;
            return VoiceMessage.fromMap(data);
          })
          .where((msg) =>
              msg.targetId == null ||
              msg.targetId == currentUserId ||
              msg.senderId == currentUserId)
          .toList();
    });
  }

  /// יצירת חדר שיחה לניווט
  Future<void> createRoom(String navigationId, String navigationName) async {
    await _firestore.collection('rooms').doc(navigationId).set({
      'name': navigationName,
      'navigationId': navigationId,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// מחיקת חדר שיחה
  Future<void> deleteRoom(String navigationId) async {
    // מחיקת כל ההודעות
    final messages = await _firestore
        .collection('rooms')
        .doc(navigationId)
        .collection('messages')
        .get();

    for (final doc in messages.docs) {
      await doc.reference.delete();
    }

    // מחיקת מסמך החדר
    await _firestore.collection('rooms').doc(navigationId).delete();
  }
}
