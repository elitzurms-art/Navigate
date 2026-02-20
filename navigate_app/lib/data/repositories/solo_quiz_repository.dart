import 'package:cloud_firestore/cloud_firestore.dart';

/// שאלת מבחן בדד
class SoloQuizQuestion {
  final String id;
  final int order;
  final String type; // 'yes_no', 'single', 'multiple'
  final String question;
  final List<String> options;
  final List<int> correctAnswers;
  final bool isReadiness; // הצהרת מוכנות — לא נספרת בציון

  const SoloQuizQuestion({
    required this.id,
    required this.order,
    required this.type,
    required this.question,
    this.options = const [],
    this.correctAnswers = const [],
    this.isReadiness = false,
  });

  factory SoloQuizQuestion.fromMap(Map<String, dynamic> map, String id) {
    return SoloQuizQuestion(
      id: id,
      order: map['order'] as int? ?? 0,
      type: map['type'] as String? ?? 'single',
      question: map['question'] as String? ?? '',
      options: (map['options'] as List?)?.cast<String>() ?? [],
      correctAnswers: (map['correctAnswers'] as List?)?.cast<int>() ?? [],
      isReadiness: map['isReadiness'] as bool? ?? false,
    );
  }
}

/// תשובות מנווט למבחן
class QuizAnswers {
  final String navigatorId;
  final Map<String, dynamic> answers; // questionId → selected answer(s)
  final DateTime? completedAt;
  final int? score;
  final bool? passed;

  const QuizAnswers({
    required this.navigatorId,
    this.answers = const {},
    this.completedAt,
    this.score,
    this.passed,
  });

  factory QuizAnswers.fromMap(Map<String, dynamic> map, String navigatorId) {
    return QuizAnswers(
      navigatorId: navigatorId,
      answers: Map<String, dynamic>.from(map['answers'] as Map? ?? {}),
      completedAt: map['completedAt'] != null
          ? (map['completedAt'] is Timestamp
              ? (map['completedAt'] as Timestamp).toDate()
              : DateTime.parse(map['completedAt'] as String))
          : null,
      score: map['score'] as int?,
      passed: map['passed'] as bool?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'answers': answers,
      if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
      if (score != null) 'score': score,
      if (passed != null) 'passed': passed,
    };
  }
}

/// Repository למבחן בדד — Firestore בלבד
class SoloQuizRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// טעינת שאלות מבחן
  Future<List<SoloQuizQuestion>> getQuestions() async {
    final snapshot = await _firestore
        .collection('solo_quiz_questions')
        .orderBy('order')
        .get();
    return snapshot.docs
        .map((doc) => SoloQuizQuestion.fromMap(doc.data(), doc.id))
        .toList();
  }

  /// טעינת הגדרות מבחן (אחוז מעבר)
  Future<int> getPassingScore() async {
    final doc = await _firestore
        .collection('solo_quiz_config')
        .doc('settings')
        .get();
    if (doc.exists) {
      return doc.data()?['passingScore'] as int? ?? 85;
    }
    return 85;
  }

  /// שמירת תשובות (בזמן אמת, לפני הגשה)
  Future<void> saveAnswers({
    required String navigationId,
    required String navigatorId,
    required Map<String, dynamic> answers,
  }) async {
    await _firestore
        .collection('navigations')
        .doc(navigationId)
        .collection('quiz_answers')
        .doc(navigatorId)
        .set({
      'answers': answers,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// הגשת מבחן (עם ציון ותוצאה)
  Future<void> submitQuiz({
    required String navigationId,
    required String navigatorId,
    required Map<String, dynamic> answers,
    required int score,
    required bool passed,
  }) async {
    await _firestore
        .collection('navigations')
        .doc(navigationId)
        .collection('quiz_answers')
        .doc(navigatorId)
        .set({
      'answers': answers,
      'completedAt': FieldValue.serverTimestamp(),
      'score': score,
      'passed': passed,
    });
  }

  /// טעינת תשובות קיימות (חזרה למבחן)
  Future<QuizAnswers?> getAnswers({
    required String navigationId,
    required String navigatorId,
  }) async {
    final doc = await _firestore
        .collection('navigations')
        .doc(navigationId)
        .collection('quiz_answers')
        .doc(navigatorId)
        .get();
    if (doc.exists && doc.data() != null) {
      return QuizAnswers.fromMap(doc.data()!, navigatorId);
    }
    return null;
  }

  /// חישוב ציון מבחן
  int calculateScore(
    List<SoloQuizQuestion> questions,
    Map<String, dynamic> answers,
  ) {
    // סופרים רק שאלות שאינן הצהרות מוכנות
    final scoredQuestions = questions.where((q) => !q.isReadiness).toList();
    if (scoredQuestions.isEmpty) return 100;

    int correct = 0;
    for (final question in scoredQuestions) {
      final answer = answers[question.id];
      if (answer == null) continue;

      if (question.type == 'yes_no') {
        // עבור yes_no: correctAnswers[0] = 0 (כן) או 1 (לא)
        if (question.correctAnswers.isNotEmpty &&
            answer == question.correctAnswers[0]) {
          correct++;
        }
      } else if (question.type == 'single') {
        if (question.correctAnswers.isNotEmpty &&
            answer == question.correctAnswers[0]) {
          correct++;
        }
      } else if (question.type == 'multiple') {
        // עבור multiple: צריך שכל התשובות הנכונות ייבחרו
        final selected = (answer as List?)?.cast<int>() ?? [];
        final correctSet = question.correctAnswers.toSet();
        if (selected.toSet().containsAll(correctSet) &&
            correctSet.containsAll(selected.toSet())) {
          correct++;
        }
      }
    }

    return ((correct / scoredQuestions.length) * 100).round();
  }
}
