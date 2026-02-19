import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/extension_request.dart';

/// Repository לבקשות הארכה — Firestore בלבד (ללא Drift, real-time)
class ExtensionRequestRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _collection(String navigationId) {
    return _firestore
        .collection('navigations')
        .doc(navigationId)
        .collection('extension_requests');
  }

  /// יצירת בקשת הארכה (מנווט)
  Future<ExtensionRequest> create(ExtensionRequest request) async {
    final docRef = _collection(request.navigationId).doc();
    final data = request.toMap();
    data['id'] = docRef.id;
    data['createdAt'] = FieldValue.serverTimestamp();
    data.remove('respondedAt');
    await docRef.set(data);
    return request.copyWith(id: docRef.id);
  }

  /// מענה לבקשה (מפקד — אישור/דחייה)
  Future<void> respond({
    required String navigationId,
    required String requestId,
    required ExtensionRequestStatus status,
    required String respondedBy,
    int? approvedMinutes,
  }) async {
    await _collection(navigationId).doc(requestId).update({
      'status': status.name,
      if (approvedMinutes != null) 'approvedMinutes': approvedMinutes,
      'respondedBy': respondedBy,
      'respondedAt': FieldValue.serverTimestamp(),
    });
  }

  /// מפקד: האזנה לכל הבקשות בניווט (real-time)
  Stream<List<ExtensionRequest>> watchByNavigation(String navigationId) {
    return _collection(navigationId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        data['navigationId'] = navigationId;
        return ExtensionRequest.fromMap(data);
      }).toList();
    });
  }

  /// מנווט: האזנה לבקשות שלו בלבד (real-time)
  Stream<List<ExtensionRequest>> watchByNavigator(
    String navigationId,
    String navigatorId,
  ) {
    return _collection(navigationId)
        .where('navigatorId', isEqualTo: navigatorId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        data['navigationId'] = navigationId;
        return ExtensionRequest.fromMap(data);
      }).toList();
    });
  }

  /// סך דקות הארכה מאושרות למנווט מסוים
  Future<int> getTotalApprovedMinutes(
    String navigationId,
    String navigatorId,
  ) async {
    final snapshot = await _collection(navigationId)
        .where('navigatorId', isEqualTo: navigatorId)
        .where('status', isEqualTo: 'approved')
        .get();
    int total = 0;
    for (final doc in snapshot.docs) {
      total += (doc.data()['approvedMinutes'] as int?) ?? 0;
    }
    return total;
  }
}
