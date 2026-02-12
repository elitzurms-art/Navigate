import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../../core/constants/app_constants.dart';

/// שירות Firebase - wrapper ל-Firestore ו-Storage
class FirebaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // Collections
  CollectionReference get usersCollection =>
      _firestore.collection(AppConstants.usersCollection);

  CollectionReference get areasCollection =>
      _firestore.collection(AppConstants.areasCollection);

  CollectionReference get layersNzCollection =>
      _firestore.collection(AppConstants.layersNzCollection);

  CollectionReference get layersNbCollection =>
      _firestore.collection(AppConstants.layersNbCollection);

  CollectionReference get layersGgCollection =>
      _firestore.collection(AppConstants.layersGgCollection);

  CollectionReference get layersBaCollection =>
      _firestore.collection(AppConstants.layersBaCollection);

  CollectionReference get navigatorTreesCollection =>
      _firestore.collection(AppConstants.navigatorTreesCollection);

  CollectionReference get navigationsCollection =>
      _firestore.collection(AppConstants.navigationsCollection);

  CollectionReference get navigationTracksCollection =>
      _firestore.collection(AppConstants.navigationTracksCollection);

  CollectionReference get navigationApprovalCollection =>
      _firestore.collection(AppConstants.navigationApprovalCollection);

  /// הוספת מסמך עם ID אוטומטי
  Future<String> addDocument(
    String collectionPath,
    Map<String, dynamic> data,
  ) async {
    final docRef = await _firestore.collection(collectionPath).add(data);
    return docRef.id;
  }

  /// הגדרת מסמך (יוצר או מעדכן)
  Future<void> setDocument(
    String collectionPath,
    String documentId,
    Map<String, dynamic> data,
  ) async {
    await _firestore
        .collection(collectionPath)
        .doc(documentId)
        .set(data, SetOptions(merge: true));
  }

  /// עדכון מסמך
  Future<void> updateDocument(
    String collectionPath,
    String documentId,
    Map<String, dynamic> data,
  ) async {
    await _firestore.collection(collectionPath).doc(documentId).update(data);
  }

  /// מחיקת מסמך
  Future<void> deleteDocument(
    String collectionPath,
    String documentId,
  ) async {
    await _firestore.collection(collectionPath).doc(documentId).delete();
  }

  /// קבלת מסמך
  Future<Map<String, dynamic>?> getDocument(
    String collectionPath,
    String documentId,
  ) async {
    final doc = await _firestore
        .collection(collectionPath)
        .doc(documentId)
        .get();
    return doc.data();
  }

  /// קבלת כל המסמכים בקולקשן
  Future<List<Map<String, dynamic>>> getCollection(
    String collectionPath, {
    int? limit,
  }) async {
    Query query = _firestore.collection(collectionPath);

    if (limit != null) {
      query = query.limit(limit);
    }

    final snapshot = await query.get();
    return snapshot.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      data['id'] = doc.id;
      return data;
    }).toList();
  }

  /// שאילתה עם תנאי
  Future<List<Map<String, dynamic>>> queryCollection(
    String collectionPath, {
    String? whereField,
    dynamic whereValue,
    String? orderByField,
    bool descending = false,
    int? limit,
  }) async {
    Query query = _firestore.collection(collectionPath);

    if (whereField != null && whereValue != null) {
      query = query.where(whereField, isEqualTo: whereValue);
    }

    if (orderByField != null) {
      query = query.orderBy(orderByField, descending: descending);
    }

    if (limit != null) {
      query = query.limit(limit);
    }

    final snapshot = await query.get();
    return snapshot.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      data['id'] = doc.id;
      return data;
    }).toList();
  }

  /// האזנה לשינויים במסמך
  Stream<Map<String, dynamic>?> watchDocument(
    String collectionPath,
    String documentId,
  ) {
    return _firestore
        .collection(collectionPath)
        .doc(documentId)
        .snapshots()
        .map((snapshot) => snapshot.data());
  }

  /// האזנה לשינויים בקולקשן
  Stream<List<Map<String, dynamic>>> watchCollection(
    String collectionPath, {
    String? whereField,
    dynamic whereValue,
  }) {
    Query query = _firestore.collection(collectionPath);

    if (whereField != null && whereValue != null) {
      query = query.where(whereField, isEqualTo: whereValue);
    }

    return query.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        return data;
      }).toList();
    });
  }

  /// העלאת קובץ ל-Storage
  Future<String> uploadFile(
    String path,
    List<int> fileBytes, {
    String? contentType,
  }) async {
    final ref = _storage.ref().child(path);
    final uploadTask = ref.putData(
      Uint8List.fromList(fileBytes),
      SettableMetadata(contentType: contentType),
    );

    final snapshot = await uploadTask;
    return await snapshot.ref.getDownloadURL();
  }

  /// הורדת קובץ מ-Storage
  Future<List<int>> downloadFile(String path) async {
    final ref = _storage.ref().child(path);
    return await ref.getData() ?? [];
  }

  /// מחיקת קובץ מ-Storage
  Future<void> deleteFile(String path) async {
    final ref = _storage.ref().child(path);
    await ref.delete();
  }

  /// Batch write (כתיבה מרובת מסמכים)
  Future<void> batchWrite(
    List<Map<String, dynamic>> operations,
  ) async {
    final batch = _firestore.batch();

    for (final operation in operations) {
      final type = operation['type'] as String;
      final collection = operation['collection'] as String;
      final docId = operation['docId'] as String;
      final data = operation['data'] as Map<String, dynamic>?;

      final docRef = _firestore.collection(collection).doc(docId);

      switch (type) {
        case 'set':
          batch.set(docRef, data!);
          break;
        case 'update':
          batch.update(docRef, data!);
          break;
        case 'delete':
          batch.delete(docRef);
          break;
      }
    }

    await batch.commit();
  }
}
