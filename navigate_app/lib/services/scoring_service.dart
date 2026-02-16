import 'package:flutter/material.dart';
import '../domain/entities/navigation_score.dart';
import '../domain/entities/checkpoint_punch.dart';
import '../domain/entities/navigation_settings.dart';

/// שירות חישוב ציונים
class ScoringService {
  /// חישוב ציון אוטומטי לפי הגדרות
  NavigationScore calculateAutomaticScore({
    required String navigationId,
    required String navigatorId,
    required List<CheckpointPunch> punches,
    required VerificationSettings verificationSettings,
    ScoringCriteria? scoringCriteria,
    bool isDisqualified = false,
  }) {
    print('מחשב ציון אוטומטי ל-$navigatorId');

    // מנווט שנפסל מקבל ציון 0
    if (isDisqualified) {
      return NavigationScore(
        id: '${navigationId}_${navigatorId}_${DateTime.now().millisecondsSinceEpoch}',
        navigationId: navigationId,
        navigatorId: navigatorId,
        totalScore: 0,
        checkpointScores: {},
        calculatedAt: DateTime.now(),
        isManual: false,
        notes: 'נפסל — פריצת אבטחה',
      );
    }

    Map<String, CheckpointScore> checkpointScores = {};
    int approvedCount = 0;

    for (final punch in punches) {
      if (punch.isDeleted) continue;

      final distance = punch.distanceFromCheckpoint ?? 0;
      bool approved = false;
      int score = 0;

      // חישוב לפי שיטה
      if (verificationSettings.verificationType == 'approved_failed') {
        final threshold = verificationSettings.approvalDistance ?? 50;
        approved = distance <= threshold;
        score = approved ? 100 : 0;
      } else if (verificationSettings.verificationType == 'score_by_distance') {
        approved = true;
        score = _calculateScoreByDistance(
          distance,
          verificationSettings.scoreRanges ?? [],
        );
      } else {
        approved = distance <= 50;
        score = approved ? 100 : 0;
      }

      // משקל לנקודה (מקריטריוני ניקוד)
      int cpWeight = 0;
      if (scoringCriteria != null) {
        if (scoringCriteria.mode == 'equal') {
          cpWeight = scoringCriteria.equalWeightPerCheckpoint ?? 0;
        } else {
          cpWeight = scoringCriteria.checkpointWeights[punch.checkpointId] ?? 0;
        }
      }

      checkpointScores[punch.checkpointId] = CheckpointScore(
        checkpointId: punch.checkpointId,
        approved: approved,
        score: score,
        distanceMeters: distance,
        weight: cpWeight,
      );

      if (approved) approvedCount++;
    }

    // חישוב ציון כולל
    int totalScore;
    if (scoringCriteria != null) {
      // ציון משוקלל: Σ(weight × percentage / 100)
      double weightedSum = 0;
      for (final cpScore in checkpointScores.values) {
        if (cpScore.weight > 0) {
          weightedSum += cpScore.weight * cpScore.score / 100.0;
        }
      }
      // קריטריונים מותאמים = 0 בחישוב אוטומטי (המפקד ימלא)
      totalScore = weightedSum.round();
    } else {
      // ממוצע רגיל (backward compat)
      final scoreSum = checkpointScores.values.fold<int>(0, (s, cs) => s + cs.score);
      totalScore = checkpointScores.isNotEmpty
          ? (scoreSum / checkpointScores.length).round()
          : 0;
    }

    print('✓ ציון מחושב: $totalScore ($approvedCount/${punches.length} אושרו)');

    return NavigationScore(
      id: '${navigationId}_${navigatorId}_${DateTime.now().millisecondsSinceEpoch}',
      navigationId: navigationId,
      navigatorId: navigatorId,
      totalScore: totalScore,
      checkpointScores: checkpointScores,
      calculatedAt: DateTime.now(),
      isManual: false,
    );
  }

  /// חישוב ציון לפי מרחק עם טווחים
  int _calculateScoreByDistance(
    double distanceMeters,
    List<DistanceScoreRange> ranges,
  ) {
    if (ranges.isEmpty) {
      // ברירת מחדל פשוטה
      if (distanceMeters <= 10) return 100;
      if (distanceMeters <= 20) return 90;
      if (distanceMeters <= 50) return 80;
      if (distanceMeters <= 100) return 70;
      return 50;
    }

    // חיפוש בטווחים
    for (final range in ranges) {
      if (distanceMeters <= range.maxDistance) {
        return range.scorePercentage;
      }
    }

    // אם עבר את כל הטווחים
    return ranges.last.scorePercentage ~/ 2; // חצי מהציון האחרון
  }

  /// חישוב ציון משוקלל כולל קריטריונים מותאמים
  static int calculateWeightedTotal({
    required Map<String, CheckpointScore> checkpointScores,
    required Map<String, int> customCriteriaScores,
  }) {
    double total = 0;
    for (final cpScore in checkpointScores.values) {
      if (cpScore.weight > 0) {
        total += cpScore.weight * cpScore.score / 100.0;
      }
    }
    for (final earned in customCriteriaScores.values) {
      total += earned;
    }
    return total.round();
  }

  /// חישוב ממוצע רגיל (backward compat)
  static int calculateAverage(Map<String, CheckpointScore> cpScores) {
    if (cpScores.isEmpty) return 0;
    final sum = cpScores.values.fold<int>(0, (s, cs) => s + cs.score);
    return (sum / cpScores.length).round();
  }

  /// יצירת ציון ידני
  NavigationScore createManualScore({
    required String navigationId,
    required String navigatorId,
    required int totalScore,
    required Map<String, CheckpointScore> checkpointScores,
    String? notes,
  }) {
    return NavigationScore(
      id: '${navigationId}_${navigatorId}_${DateTime.now().millisecondsSinceEpoch}',
      navigationId: navigationId,
      navigatorId: navigatorId,
      totalScore: totalScore,
      checkpointScores: checkpointScores,
      calculatedAt: DateTime.now(),
      isManual: true,
      notes: notes,
    );
  }

  /// עדכון ציון (עריכה ידנית)
  NavigationScore updateScore(
    NavigationScore existingScore, {
    int? newTotalScore,
    Map<String, CheckpointScore>? newCheckpointScores,
    String? newNotes,
  }) {
    return existingScore.copyWith(
      totalScore: newTotalScore,
      checkpointScores: newCheckpointScores,
      notes: newNotes,
      isManual: true, // הופך לידני אחרי עריכה
      calculatedAt: DateTime.now(),
    );
  }

  /// הפצת ציון למנווט
  NavigationScore publishScore(NavigationScore score) {
    return score.copyWith(
      isPublished: true,
      publishedAt: DateTime.now(),
    );
  }

  /// קבלת דירוג (A, B, C, D, F)
  String getGrade(int score) {
    if (score >= 90) return 'A';
    if (score >= 80) return 'B';
    if (score >= 70) return 'C';
    if (score >= 60) return 'D';
    return 'F';
  }

  /// קבלת צבע לציון
  static Color getScoreColor(int score) {
    if (score >= 90) return const Color(0xFF4CAF50); // ירוק
    if (score >= 80) return const Color(0xFF8BC34A); // ירוק בהיר
    if (score >= 70) return const Color(0xFFFFC107); // צהוב
    if (score >= 60) return const Color(0xFFFF9800); // כתום
    return const Color(0xFFF44336); // אדום
  }
}
