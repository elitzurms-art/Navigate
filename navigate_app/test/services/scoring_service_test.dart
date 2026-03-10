import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigate_app/services/scoring_service.dart';
import 'package:navigate_app/domain/entities/checkpoint_punch.dart';
import 'package:navigate_app/domain/entities/navigation_score.dart';
import 'package:navigate_app/domain/entities/navigation_settings.dart';
import 'package:navigate_app/domain/entities/coordinate.dart';

void main() {
  late ScoringService scoringService;

  setUp(() {
    scoringService = ScoringService();
  });

  // Helper to create a punch
  CheckpointPunch makePunch({
    String id = 'punch1',
    String checkpointId = 'cp1',
    double? distance = 10.0,
    PunchStatus status = PunchStatus.active,
    DateTime? punchTime,
    String? supersededByPunchId,
  }) {
    return CheckpointPunch(
      id: id,
      navigationId: 'nav1',
      navigatorId: 'user1',
      checkpointId: checkpointId,
      punchLocation: const Coordinate(lat: 31.5, lng: 34.5, utm: ''),
      punchTime: punchTime ?? DateTime(2026, 3, 10, 10, 0),
      status: status,
      distanceFromCheckpoint: distance,
      supersededByPunchId: supersededByPunchId,
    );
  }

  group('calculateAutomaticScore', () {
    test('isDisqualified returns totalScore 0', () {
      final score = scoringService.calculateAutomaticScore(
        navigationId: 'nav1',
        navigatorId: 'user1',
        punches: [makePunch()],
        verificationSettings: const VerificationSettings(
          autoVerification: true,
          verificationType: 'approved_failed',
          approvalDistance: 50,
        ),
        isDisqualified: true,
      );
      expect(score.totalScore, 0);
      expect(score.isManual, isFalse);
      expect(score.notes, contains('נפסל'));
    });

    test('approved_failed mode: within distance returns 100', () {
      final score = scoringService.calculateAutomaticScore(
        navigationId: 'nav1',
        navigatorId: 'user1',
        punches: [makePunch(distance: 30.0)],
        verificationSettings: const VerificationSettings(
          autoVerification: true,
          verificationType: 'approved_failed',
          approvalDistance: 50,
        ),
      );
      expect(score.totalScore, 100);
      expect(score.checkpointScores['cp1']!.approved, isTrue);
      expect(score.checkpointScores['cp1']!.score, 100);
    });

    test('approved_failed mode: beyond distance returns 0', () {
      final score = scoringService.calculateAutomaticScore(
        navigationId: 'nav1',
        navigatorId: 'user1',
        punches: [makePunch(distance: 60.0)],
        verificationSettings: const VerificationSettings(
          autoVerification: true,
          verificationType: 'approved_failed',
          approvalDistance: 50,
        ),
      );
      expect(score.totalScore, 0);
      expect(score.checkpointScores['cp1']!.approved, isFalse);
      expect(score.checkpointScores['cp1']!.score, 0);
    });

    test('score_by_distance with custom ranges', () {
      final score = scoringService.calculateAutomaticScore(
        navigationId: 'nav1',
        navigatorId: 'user1',
        punches: [makePunch(distance: 15.0)],
        verificationSettings: const VerificationSettings(
          autoVerification: true,
          verificationType: 'score_by_distance',
          scoreRanges: [
            DistanceScoreRange(maxDistance: 10, scorePercentage: 100),
            DistanceScoreRange(maxDistance: 20, scorePercentage: 80),
            DistanceScoreRange(maxDistance: 50, scorePercentage: 60),
          ],
        ),
      );
      // 15m falls in the 20m range -> 80
      expect(score.totalScore, 80);
      expect(score.checkpointScores['cp1']!.score, 80);
    });

    test('score_by_distance with empty ranges uses defaults', () {
      final score = scoringService.calculateAutomaticScore(
        navigationId: 'nav1',
        navigatorId: 'user1',
        punches: [makePunch(distance: 5.0)],
        verificationSettings: const VerificationSettings(
          autoVerification: true,
          verificationType: 'score_by_distance',
          scoreRanges: [],
        ),
      );
      // 5m <= 10 -> default 100
      expect(score.totalScore, 100);
    });

    test('score_by_distance default ranges: 15m -> 90', () {
      final score = scoringService.calculateAutomaticScore(
        navigationId: 'nav1',
        navigatorId: 'user1',
        punches: [makePunch(distance: 15.0)],
        verificationSettings: const VerificationSettings(
          autoVerification: true,
          verificationType: 'score_by_distance',
          scoreRanges: [],
        ),
      );
      // 15m: >10, <=20 -> 90
      expect(score.totalScore, 90);
    });

    test('score_by_distance beyond all ranges returns half of last', () {
      final score = scoringService.calculateAutomaticScore(
        navigationId: 'nav1',
        navigatorId: 'user1',
        punches: [makePunch(distance: 200.0)],
        verificationSettings: const VerificationSettings(
          autoVerification: true,
          verificationType: 'score_by_distance',
          scoreRanges: [
            DistanceScoreRange(maxDistance: 10, scorePercentage: 100),
            DistanceScoreRange(maxDistance: 50, scorePercentage: 60),
          ],
        ),
      );
      // Beyond 50m -> last.scorePercentage / 2 = 60 / 2 = 30
      expect(score.totalScore, 30);
    });

    test('filters superseded punches (uses latest)', () {
      final olderPunch = makePunch(
        id: 'punch1',
        checkpointId: 'cp1',
        distance: 100.0,
        punchTime: DateTime(2026, 3, 10, 10, 0),
        supersededByPunchId: 'punch2',
      );
      final newerPunch = makePunch(
        id: 'punch2',
        checkpointId: 'cp1',
        distance: 5.0,
        punchTime: DateTime(2026, 3, 10, 10, 5),
      );
      final score = scoringService.calculateAutomaticScore(
        navigationId: 'nav1',
        navigatorId: 'user1',
        punches: [olderPunch, newerPunch],
        verificationSettings: const VerificationSettings(
          autoVerification: true,
          verificationType: 'approved_failed',
          approvalDistance: 50,
        ),
      );
      // Superseded punch is filtered out by isScoreable.
      // Only newerPunch (distance 5.0) should be used -> approved -> 100
      expect(score.totalScore, 100);
      expect(score.checkpointScores['cp1']!.score, 100);
    });

    test('filters deleted and rejected punches', () {
      final deletedPunch = makePunch(
        id: 'p1',
        checkpointId: 'cp1',
        distance: 5.0,
        status: PunchStatus.deleted,
      );
      final rejectedPunch = makePunch(
        id: 'p2',
        checkpointId: 'cp2',
        distance: 5.0,
        status: PunchStatus.rejected,
      );
      final activePunch = makePunch(
        id: 'p3',
        checkpointId: 'cp3',
        distance: 5.0,
        status: PunchStatus.active,
      );
      final score = scoringService.calculateAutomaticScore(
        navigationId: 'nav1',
        navigatorId: 'user1',
        punches: [deletedPunch, rejectedPunch, activePunch],
        verificationSettings: const VerificationSettings(
          autoVerification: true,
          verificationType: 'approved_failed',
          approvalDistance: 50,
        ),
      );
      // Only activePunch is scoreable
      expect(score.checkpointScores.length, 1);
      expect(score.checkpointScores.containsKey('cp3'), isTrue);
    });

    test('with scoring criteria (weighted)', () {
      final punch1 = makePunch(
        id: 'p1',
        checkpointId: 'cp1',
        distance: 5.0,
        punchTime: DateTime(2026, 3, 10, 10, 0),
      );
      final punch2 = makePunch(
        id: 'p2',
        checkpointId: 'cp2',
        distance: 5.0,
        punchTime: DateTime(2026, 3, 10, 10, 5),
      );
      final score = scoringService.calculateAutomaticScore(
        navigationId: 'nav1',
        navigatorId: 'user1',
        punches: [punch1, punch2],
        verificationSettings: const VerificationSettings(
          autoVerification: true,
          verificationType: 'approved_failed',
          approvalDistance: 50,
        ),
        scoringCriteria: const ScoringCriteria(
          mode: 'equal',
          equalWeightPerCheckpoint: 50,
        ),
      );
      // Each checkpoint scores 100, weight 50
      // weightedSum = 50 * 100/100 + 50 * 100/100 = 100
      expect(score.totalScore, 100);
    });

    test('without scoring criteria (average)', () {
      final punch1 = makePunch(
        id: 'p1',
        checkpointId: 'cp1',
        distance: 5.0,
        punchTime: DateTime(2026, 3, 10, 10, 0),
      );
      final punch2 = makePunch(
        id: 'p2',
        checkpointId: 'cp2',
        distance: 60.0,
        punchTime: DateTime(2026, 3, 10, 10, 5),
      );
      final score = scoringService.calculateAutomaticScore(
        navigationId: 'nav1',
        navigatorId: 'user1',
        punches: [punch1, punch2],
        verificationSettings: const VerificationSettings(
          autoVerification: true,
          verificationType: 'approved_failed',
          approvalDistance: 50,
        ),
      );
      // cp1: 100 (within 50m), cp2: 0 (beyond 50m)
      // average = (100 + 0) / 2 = 50
      expect(score.totalScore, 50);
    });

    test('null distance results in score 0 for that checkpoint', () {
      final score = scoringService.calculateAutomaticScore(
        navigationId: 'nav1',
        navigatorId: 'user1',
        punches: [makePunch(distance: null)],
        verificationSettings: const VerificationSettings(
          autoVerification: true,
          verificationType: 'approved_failed',
          approvalDistance: 50,
        ),
      );
      expect(score.checkpointScores['cp1']!.score, 0);
      expect(score.checkpointScores['cp1']!.approved, isFalse);
    });

    test('no punches returns score 0', () {
      final score = scoringService.calculateAutomaticScore(
        navigationId: 'nav1',
        navigatorId: 'user1',
        punches: [],
        verificationSettings: const VerificationSettings(
          autoVerification: true,
          verificationType: 'approved_failed',
          approvalDistance: 50,
        ),
      );
      expect(score.totalScore, 0);
      expect(score.checkpointScores, isEmpty);
    });

    test('multiple punches for same checkpoint uses latest', () {
      final earlier = makePunch(
        id: 'p1',
        checkpointId: 'cp1',
        distance: 100.0,
        punchTime: DateTime(2026, 3, 10, 10, 0),
      );
      final later = makePunch(
        id: 'p2',
        checkpointId: 'cp1',
        distance: 5.0,
        punchTime: DateTime(2026, 3, 10, 10, 10),
      );
      final score = scoringService.calculateAutomaticScore(
        navigationId: 'nav1',
        navigatorId: 'user1',
        punches: [earlier, later],
        verificationSettings: const VerificationSettings(
          autoVerification: true,
          verificationType: 'approved_failed',
          approvalDistance: 50,
        ),
      );
      // Should use the later punch (distance 5.0) -> approved
      expect(score.checkpointScores['cp1']!.approved, isTrue);
      expect(score.checkpointScores['cp1']!.score, 100);
    });
  });

  group('calculateWeightedTotal', () {
    test('calculates weighted total correctly', () {
      final cpScores = {
        'cp1': const CheckpointScore(
          checkpointId: 'cp1',
          approved: true,
          score: 100,
          distanceMeters: 5.0,
          weight: 30,
        ),
        'cp2': const CheckpointScore(
          checkpointId: 'cp2',
          approved: true,
          score: 80,
          distanceMeters: 15.0,
          weight: 20,
        ),
      };
      final customScores = {'criteria1': 10};
      final total = ScoringService.calculateWeightedTotal(
        checkpointScores: cpScores,
        customCriteriaScores: customScores,
      );
      // 30 * 100/100 + 20 * 80/100 + 10 = 30 + 16 + 10 = 56
      expect(total, 56);
    });

    test('zero weight checkpoints contribute nothing', () {
      final cpScores = {
        'cp1': const CheckpointScore(
          checkpointId: 'cp1',
          approved: true,
          score: 100,
          distanceMeters: 5.0,
          weight: 0,
        ),
      };
      final total = ScoringService.calculateWeightedTotal(
        checkpointScores: cpScores,
        customCriteriaScores: {},
      );
      expect(total, 0);
    });
  });

  group('calculateAverage', () {
    test('with scores', () {
      final cpScores = {
        'cp1': const CheckpointScore(
          checkpointId: 'cp1',
          approved: true,
          score: 100,
          distanceMeters: 5.0,
        ),
        'cp2': const CheckpointScore(
          checkpointId: 'cp2',
          approved: false,
          score: 60,
          distanceMeters: 80.0,
        ),
      };
      final avg = ScoringService.calculateAverage(cpScores);
      expect(avg, 80); // (100 + 60) / 2 = 80
    });

    test('empty scores returns 0', () {
      expect(ScoringService.calculateAverage({}), 0);
    });
  });

  group('createManualScore', () {
    test('sets isManual to true', () {
      final score = scoringService.createManualScore(
        navigationId: 'nav1',
        navigatorId: 'user1',
        totalScore: 85,
        checkpointScores: {},
        notes: 'Manual override',
      );
      expect(score.isManual, isTrue);
      expect(score.totalScore, 85);
      expect(score.notes, 'Manual override');
    });
  });

  group('updateScore', () {
    test('sets isManual to true after update', () {
      final original = NavigationScore(
        id: 'score1',
        navigationId: 'nav1',
        navigatorId: 'user1',
        totalScore: 50,
        checkpointScores: const {},
        calculatedAt: DateTime(2026, 3, 10),
        isManual: false,
      );
      final updated = scoringService.updateScore(original, newTotalScore: 75);
      expect(updated.isManual, isTrue);
      expect(updated.totalScore, 75);
    });

    test('update preserves fields not being changed', () {
      final original = NavigationScore(
        id: 'score1',
        navigationId: 'nav1',
        navigatorId: 'user1',
        totalScore: 50,
        checkpointScores: const {
          'cp1': CheckpointScore(
            checkpointId: 'cp1',
            approved: true,
            score: 100,
            distanceMeters: 5.0,
          ),
        },
        calculatedAt: DateTime(2026, 3, 10),
        isManual: false,
      );
      final updated = scoringService.updateScore(original, newNotes: 'Updated');
      expect(updated.id, original.id);
      expect(updated.navigationId, original.navigationId);
      expect(updated.checkpointScores.length, 1);
      expect(updated.notes, 'Updated');
    });
  });

  group('publishScore', () {
    test('sets isPublished and publishedAt', () {
      final score = NavigationScore(
        id: 'score1',
        navigationId: 'nav1',
        navigatorId: 'user1',
        totalScore: 85,
        checkpointScores: const {},
        calculatedAt: DateTime(2026, 3, 10),
        isPublished: false,
      );
      final published = scoringService.publishScore(score);
      expect(published.isPublished, isTrue);
      expect(published.publishedAt, isNotNull);
    });
  });

  group('getGrade', () {
    test('95 returns A', () {
      expect(scoringService.getGrade(95), 'A');
    });

    test('90 returns A', () {
      expect(scoringService.getGrade(90), 'A');
    });

    test('85 returns B', () {
      expect(scoringService.getGrade(85), 'B');
    });

    test('80 returns B', () {
      expect(scoringService.getGrade(80), 'B');
    });

    test('75 returns C', () {
      expect(scoringService.getGrade(75), 'C');
    });

    test('65 returns D', () {
      expect(scoringService.getGrade(65), 'D');
    });

    test('50 returns F', () {
      expect(scoringService.getGrade(50), 'F');
    });

    test('0 returns F', () {
      expect(scoringService.getGrade(0), 'F');
    });

    test('100 returns A', () {
      expect(scoringService.getGrade(100), 'A');
    });
  });

  group('getScoreColor', () {
    test('90+ returns green', () {
      expect(ScoringService.getScoreColor(95), const Color(0xFF4CAF50));
    });

    test('80-89 returns light green', () {
      expect(ScoringService.getScoreColor(85), const Color(0xFF8BC34A));
    });

    test('70-79 returns yellow', () {
      expect(ScoringService.getScoreColor(75), const Color(0xFFFFC107));
    });

    test('60-69 returns orange', () {
      expect(ScoringService.getScoreColor(65), const Color(0xFFFF9800));
    });

    test('below 60 returns red', () {
      expect(ScoringService.getScoreColor(50), const Color(0xFFF44336));
    });

    test('0 returns red', () {
      expect(ScoringService.getScoreColor(0), const Color(0xFFF44336));
    });

    test('boundary: 90 returns green', () {
      expect(ScoringService.getScoreColor(90), const Color(0xFF4CAF50));
    });

    test('boundary: 80 returns light green', () {
      expect(ScoringService.getScoreColor(80), const Color(0xFF8BC34A));
    });

    test('boundary: 70 returns yellow', () {
      expect(ScoringService.getScoreColor(70), const Color(0xFFFFC107));
    });

    test('boundary: 60 returns orange', () {
      expect(ScoringService.getScoreColor(60), const Color(0xFFFF9800));
    });
  });
}
