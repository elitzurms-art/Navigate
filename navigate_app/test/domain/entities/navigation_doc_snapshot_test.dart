import 'package:flutter_test/flutter_test.dart';
import 'package:navigate_app/domain/entities/navigation_doc_snapshot.dart';

import '../../helpers/entity_factories.dart';

void main() {
  // ---------------------------------------------------------------------------
  // fromFirestore — נתוני ניווט תקינים + שדות חירום
  // ---------------------------------------------------------------------------
  group('fromFirestore — valid navigation data', () {
    test('parses navigation and emergency fields correctly', () {
      final data = buildMinimalNavigationMap({
        'emergencyActive': true,
        'emergencyMode': 2,
        'activeBroadcastId': 'broadcast-abc',
        'cancelBroadcastId': 'cancel-xyz',
      });

      final snapshot = NavigationDocSnapshot.fromFirestore('nav-001', data);

      expect(snapshot.id, 'nav-001');
      expect(snapshot.navigation, isNotNull);
      expect(snapshot.navigation!.id, 'nav-001');
      expect(snapshot.emergencyActive, true);
      expect(snapshot.emergencyMode, 2);
      expect(snapshot.activeBroadcastId, 'broadcast-abc');
      expect(snapshot.cancelBroadcastId, 'cancel-xyz');
    });
  });

  // ---------------------------------------------------------------------------
  // fromFirestore — נתונים לא תקינים (parsing נכשל)
  // ---------------------------------------------------------------------------
  group('fromFirestore — invalid data (parsing fails)', () {
    test('empty map still parses navigation (fromMap uses defaults) with docId as id', () {
      // Navigation.fromMap tolerates missing fields by using defaults,
      // and fromFirestore sets data['id'] = docId — so navigation is NOT null.
      final snapshot = NavigationDocSnapshot.fromFirestore('doc-bad', <String, dynamic>{});

      expect(snapshot.id, 'doc-bad');
      // Navigation.fromMap succeeds because it defaults most fields
      expect(snapshot.navigation, isNotNull);
      expect(snapshot.navigation!.id, 'doc-bad');
      // emergency fields still parsed with defaults
      expect(snapshot.emergencyActive, false);
      expect(snapshot.emergencyMode, 0);
      expect(snapshot.activeBroadcastId, isNull);
      expect(snapshot.cancelBroadcastId, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // fromFirestore — שדות חירום חסרים
  // ---------------------------------------------------------------------------
  group('fromFirestore — missing emergency fields', () {
    test('defaults to false/0/null when emergency fields missing', () {
      final data = buildMinimalNavigationMap();

      final snapshot = NavigationDocSnapshot.fromFirestore('nav-001', data);

      expect(snapshot.navigation, isNotNull);
      expect(snapshot.emergencyActive, false);
      expect(snapshot.emergencyMode, 0);
      expect(snapshot.activeBroadcastId, isNull);
      expect(snapshot.cancelBroadcastId, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // fromFirestore sets data['id'] = docId — ה-docId הופך ל-id של ה-navigation
  // ---------------------------------------------------------------------------
  group('fromFirestore sets data[id] = docId', () {
    test('docId becomes navigation id', () {
      final data = buildMinimalNavigationMap({
        'id': 'old-id-in-map',
      });

      final snapshot = NavigationDocSnapshot.fromFirestore('override-doc-id', data);

      expect(snapshot.id, 'override-doc-id');
      expect(snapshot.navigation, isNotNull);
      expect(snapshot.navigation!.id, 'override-doc-id');
    });
  });

  // ---------------------------------------------------------------------------
  // constructor defaults — ברירות מחדל של הבנאי
  // ---------------------------------------------------------------------------
  group('constructor defaults', () {
    test('emergencyActive defaults to false', () {
      final snapshot = createTestNavigationDocSnapshot();
      expect(snapshot.emergencyActive, false);
    });

    test('emergencyMode defaults to 0', () {
      final snapshot = createTestNavigationDocSnapshot();
      expect(snapshot.emergencyMode, 0);
    });

    test('activeBroadcastId defaults to null', () {
      final snapshot = createTestNavigationDocSnapshot();
      expect(snapshot.activeBroadcastId, isNull);
    });

    test('cancelBroadcastId defaults to null', () {
      final snapshot = createTestNavigationDocSnapshot();
      expect(snapshot.cancelBroadcastId, isNull);
    });

    test('navigation defaults to null', () {
      final snapshot = createTestNavigationDocSnapshot();
      expect(snapshot.navigation, isNull);
    });
  });
}
