import 'package:flutter_test/flutter_test.dart';
import 'package:navigate_app/domain/entities/navigation_score.dart';

void main() {
  group('CheckpointScore', () {
    test('toMap and fromMap roundtrip', () {
      const score = CheckpointScore(
        checkpointId: 'cp1',
        approved: true,
        score: 85,
        distanceMeters: 12.5,
        rejectionReason: 'too far',
        weight: 3,
      );

      final map = score.toMap();
      final restored = CheckpointScore.fromMap(map);

      expect(restored.checkpointId, 'cp1');
      expect(restored.approved, isTrue);
      expect(restored.score, 85);
      expect(restored.distanceMeters, 12.5);
      expect(restored.rejectionReason, 'too far');
      expect(restored.weight, 3);
    });

    test('toMap omits rejectionReason when null', () {
      const score = CheckpointScore(
        checkpointId: 'cp1',
        approved: true,
        score: 100,
        distanceMeters: 0.0,
      );

      final map = score.toMap();
      expect(map.containsKey('rejectionReason'), isFalse);
    });

    test('toMap omits weight when 0 (default)', () {
      const score = CheckpointScore(
        checkpointId: 'cp1',
        approved: true,
        score: 90,
        distanceMeters: 5.0,
        weight: 0,
      );

      final map = score.toMap();
      expect(map.containsKey('weight'), isFalse);
    });

    test('toMap includes weight when greater than 0', () {
      const score = CheckpointScore(
        checkpointId: 'cp1',
        approved: true,
        score: 90,
        distanceMeters: 5.0,
        weight: 2,
      );

      final map = score.toMap();
      expect(map.containsKey('weight'), isTrue);
      expect(map['weight'], 2);
    });

    test('fromMap defaults weight to 0 when missing', () {
      final score = CheckpointScore.fromMap({
        'checkpointId': 'cp1',
        'approved': false,
        'score': 0,
        'distanceMeters': 100.0,
      });

      expect(score.weight, 0);
    });

    test('Equatable compares by checkpointId, approved, score, weight', () {
      const s1 = CheckpointScore(
        checkpointId: 'cp1',
        approved: true,
        score: 85,
        distanceMeters: 12.5,
        weight: 2,
      );
      const s2 = CheckpointScore(
        checkpointId: 'cp1',
        approved: true,
        score: 85,
        distanceMeters: 99.0, // different distance, not in props
        weight: 2,
      );
      expect(s1, equals(s2));

      const s3 = CheckpointScore(
        checkpointId: 'cp2',
        approved: true,
        score: 85,
        distanceMeters: 12.5,
        weight: 2,
      );
      expect(s1, isNot(equals(s3)));
    });
  });

  group('ScoringMethod', () {
    test('fromCode resolves all valid codes', () {
      expect(ScoringMethod.fromCode('approved_failed'), ScoringMethod.approvedFailed);
      expect(ScoringMethod.fromCode('distance_based'), ScoringMethod.distanceBased);
      expect(ScoringMethod.fromCode('manual'), ScoringMethod.manual);
    });

    test('fromCode falls back to approvedFailed for unknown code', () {
      expect(ScoringMethod.fromCode('unknown'), ScoringMethod.approvedFailed);
      expect(ScoringMethod.fromCode(''), ScoringMethod.approvedFailed);
      expect(ScoringMethod.fromCode('weighted'), ScoringMethod.approvedFailed);
    });

    test('each method has code and displayName', () {
      expect(ScoringMethod.approvedFailed.code, 'approved_failed');
      expect(ScoringMethod.approvedFailed.displayName, 'אישור/נכשל');
      expect(ScoringMethod.distanceBased.code, 'distance_based');
      expect(ScoringMethod.distanceBased.displayName, 'לפי מרחק');
      expect(ScoringMethod.manual.code, 'manual');
      expect(ScoringMethod.manual.displayName, 'ידני');
    });
  });

  group('NavigationScore', () {
    final calculatedAt = DateTime(2026, 3, 10, 15, 0, 0);
    final publishedAt = DateTime(2026, 3, 10, 16, 0, 0);

    NavigationScore createScore({
      Map<String, CheckpointScore>? checkpointScores,
      Map<String, int>? customCriteriaScores,
      bool isPublished = false,
      DateTime? pubAt,
      String? notes,
    }) {
      return NavigationScore(
        id: 'score1',
        navigationId: 'nav1',
        navigatorId: 'user1',
        totalScore: 87,
        checkpointScores: checkpointScores ?? const {},
        customCriteriaScores: customCriteriaScores ?? const {},
        calculatedAt: calculatedAt,
        isManual: false,
        notes: notes,
        isPublished: isPublished,
        publishedAt: pubAt,
      );
    }

    test('toMap and fromMap roundtrip with checkpointScores', () {
      final score = createScore(
        checkpointScores: {
          'cp1': const CheckpointScore(
            checkpointId: 'cp1',
            approved: true,
            score: 100,
            distanceMeters: 3.2,
          ),
          'cp2': const CheckpointScore(
            checkpointId: 'cp2',
            approved: false,
            score: 0,
            distanceMeters: 150.0,
            rejectionReason: 'too far',
          ),
        },
      );

      final map = score.toMap();
      final restored = NavigationScore.fromMap(map);

      expect(restored.id, 'score1');
      expect(restored.navigationId, 'nav1');
      expect(restored.navigatorId, 'user1');
      expect(restored.totalScore, 87);
      expect(restored.calculatedAt, calculatedAt);
      expect(restored.isManual, isFalse);
      expect(restored.checkpointScores.length, 2);
      expect(restored.checkpointScores['cp1']!.approved, isTrue);
      expect(restored.checkpointScores['cp2']!.rejectionReason, 'too far');
    });

    test('fromMap with missing checkpointScores defaults to empty map', () {
      final map = {
        'id': 'score1',
        'navigationId': 'nav1',
        'navigatorId': 'user1',
        'totalScore': 50,
        'calculatedAt': calculatedAt.toIso8601String(),
        // no checkpointScores key
      };

      final score = NavigationScore.fromMap(map);
      expect(score.checkpointScores, isEmpty);
    });

    test('fromMap with non-Map checkpointScores defaults to empty map', () {
      final map = {
        'id': 'score1',
        'navigationId': 'nav1',
        'navigatorId': 'user1',
        'totalScore': 50,
        'checkpointScores': 'not a map',
        'calculatedAt': calculatedAt.toIso8601String(),
      };

      final score = NavigationScore.fromMap(map);
      expect(score.checkpointScores, isEmpty);
    });

    test('fromMap with missing customCriteriaScores defaults to empty map', () {
      final map = {
        'id': 'score1',
        'navigationId': 'nav1',
        'navigatorId': 'user1',
        'totalScore': 50,
        'calculatedAt': calculatedAt.toIso8601String(),
        // no customCriteriaScores
      };

      final score = NavigationScore.fromMap(map);
      expect(score.customCriteriaScores, isEmpty);
    });

    test('fromMap with non-Map customCriteriaScores defaults to empty map', () {
      final map = {
        'id': 'score1',
        'navigationId': 'nav1',
        'navigatorId': 'user1',
        'totalScore': 50,
        'customCriteriaScores': 'not a map',
        'calculatedAt': calculatedAt.toIso8601String(),
      };

      final score = NavigationScore.fromMap(map);
      expect(score.customCriteriaScores, isEmpty);
    });

    test('copyWith replaces specified fields', () {
      final original = createScore();
      final modified = original.copyWith(
        totalScore: 95,
        isManual: true,
        notes: 'excellent',
      );

      expect(modified.totalScore, 95);
      expect(modified.isManual, isTrue);
      expect(modified.notes, 'excellent');
      expect(modified.id, 'score1'); // unchanged
      expect(modified.navigationId, 'nav1'); // unchanged
    });

    test('Equatable compares by id, navigationId, navigatorId, totalScore, isPublished', () {
      final s1 = createScore();
      final s2 = createScore();
      expect(s1, equals(s2));

      // Different notes but same props — still equal
      final s3 = createScore(notes: 'some note');
      expect(s1, equals(s3));

      // Different totalScore — not equal
      final s4 = createScore().copyWith(totalScore: 50);
      expect(s1, isNot(equals(s4)));
    });

    test('with customCriteriaScores toMap and fromMap roundtrip', () {
      final score = createScore(
        customCriteriaScores: {'criterion1': 8, 'criterion2': 5},
      );

      final map = score.toMap();
      expect(map.containsKey('customCriteriaScores'), isTrue);

      final restored = NavigationScore.fromMap(map);
      expect(restored.customCriteriaScores, {'criterion1': 8, 'criterion2': 5});
    });

    test('toMap omits customCriteriaScores when empty', () {
      final score = createScore(customCriteriaScores: const {});
      final map = score.toMap();

      expect(map.containsKey('customCriteriaScores'), isFalse);
    });

    test('isPublished and publishedAt serialization', () {
      final score = createScore(
        isPublished: true,
        pubAt: publishedAt,
      );

      final map = score.toMap();
      expect(map['isPublished'], isTrue);
      expect(map.containsKey('publishedAt'), isTrue);

      final restored = NavigationScore.fromMap(map);
      expect(restored.isPublished, isTrue);
      expect(restored.publishedAt, publishedAt);
    });

    test('toMap omits publishedAt when null', () {
      final score = createScore();
      final map = score.toMap();

      expect(map['isPublished'], isFalse);
      expect(map.containsKey('publishedAt'), isFalse);
    });

    test('toMap omits notes when null', () {
      final score = createScore();
      final map = score.toMap();

      expect(map.containsKey('notes'), isFalse);
    });

    test('toMap includes notes when present', () {
      final score = createScore(notes: 'test note');
      final map = score.toMap();

      expect(map.containsKey('notes'), isTrue);
      expect(map['notes'], 'test note');
    });
  });
}
