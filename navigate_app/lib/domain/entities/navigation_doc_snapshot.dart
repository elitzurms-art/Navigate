import 'navigation.dart';

/// עטיפת snapshot של מסמך ניווט מ-Firestore, כולל שדות שלא בישות Navigation
class NavigationDocSnapshot {
  final String id;
  final Navigation? navigation;
  final bool emergencyActive;
  final int emergencyMode;
  final String? activeBroadcastId;
  final String? cancelBroadcastId;

  const NavigationDocSnapshot({
    required this.id,
    this.navigation,
    this.emergencyActive = false,
    this.emergencyMode = 0,
    this.activeBroadcastId,
    this.cancelBroadcastId,
  });

  factory NavigationDocSnapshot.fromFirestore(
    String docId,
    Map<String, dynamic> data,
  ) {
    Navigation? nav;
    try {
      data['id'] = docId;
      nav = Navigation.fromMap(data);
    } catch (_) {
      nav = null;
    }
    return NavigationDocSnapshot(
      id: docId,
      navigation: nav,
      emergencyActive: data['emergencyActive'] as bool? ?? false,
      emergencyMode: data['emergencyMode'] as int? ?? 0,
      activeBroadcastId: data['activeBroadcastId'] as String?,
      cancelBroadcastId: data['cancelBroadcastId'] as String?,
    );
  }
}
