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

  /// זריעת שאלות ברירת מחדל (15 שאלות) + הגדרות מבחן
  Future<void> seedDefaultQuestions() async {
    final batch = _firestore.batch();

    final questions = _defaultQuestions;
    for (final q in questions) {
      final docRef = _firestore.collection('solo_quiz_questions').doc();
      batch.set(docRef, q);
    }

    // הגדרות מבחן
    batch.set(
      _firestore.collection('solo_quiz_config').doc('settings'),
      {'passingScore': 85},
    );

    await batch.commit();
  }

  static List<Map<String, dynamic>> get _defaultQuestions => [
    // === הצהרות מוכנות (5) ===
    {
      'order': 1,
      'type': 'yes_no',
      'question': 'האם אתה מעיד על עצמך כי רמת הניווט שלך טובה ומעלה?',
      'options': <String>[],
      'correctAnswers': [0],
      'isReadiness': true,
    },
    {
      'order': 2,
      'type': 'yes_no',
      'question': 'האם ביכולתך ליישם את תכונות האופי והערכים הבאים: דבקות במשימה, אמינות, אחריות ובטיחות, מקצועיות ומשמעת, רעות, איתנות, קבלת החלטות איכותיות?',
      'options': <String>[],
      'correctAnswers': [0],
      'isReadiness': true,
    },
    {
      'order': 3,
      'type': 'yes_no',
      'question': 'האם ביצעת מעל 10 ניווטי לילה?',
      'options': <String>[],
      'correctAnswers': [0],
      'isReadiness': true,
    },
    {
      'order': 4,
      'type': 'yes_no',
      'question': 'קראת והבנת את התחקירים?',
      'options': <String>[],
      'correctAnswers': [0],
      'isReadiness': true,
    },
    {
      'order': 5,
      'type': 'yes_no',
      'question': 'קראת והבנת את ההוראות?',
      'options': <String>[],
      'correctAnswers': [0],
      'isReadiness': true,
    },
    // === שאלות ידע (10) ===
    {
      'order': 6,
      'type': 'single',
      'question': 'מהי הגישה הנכונה לניווט בדד?',
      'options': [
        'ניווט בדד זהה לניווט רגיל, רק לבד',
        'ניווט בדד דורש פחות הכנה כי אין צוות',
        'ניווט בדד דורש יתר זהירות, הכנה מקיפה ומודעות מוגברת לבטיחות',
      ],
      'correctAnswers': [2],
      'isReadiness': false,
    },
    {
      'order': 7,
      'type': 'single',
      'question': 'מה הלקח החוזר בשלושת התחקירים?',
      'options': [
        'חשיבות הערכת מצב רציפה ודיווח מיידי על כל שינוי',
        'חשיבות הציוד האישי',
        'חשיבות הכושר הגופני',
        'חשיבות הניווט המהיר',
      ],
      'correctAnswers': [0],
      'isReadiness': false,
    },
    {
      'order': 8,
      'type': 'single',
      'question': 'מהו מצב הנשק בניווט בדד?',
      'options': [
        'שחור/לבן — על פי החלטת אל"מ הגזרה',
        'תמיד שחור',
        'תמיד לבן',
      ],
      'correctAnswers': [0],
      'isReadiness': false,
    },
    {
      'order': 9,
      'type': 'single',
      'question': 'מהו מרחק הבטיחות המינימלי מכביש?',
      'options': [
        '10 מטרים',
        '25 מטרים',
        '50 מטרים',
        '100 מטרים',
      ],
      'correctAnswers': [2],
      'isReadiness': false,
    },
    {
      'order': 10,
      'type': 'multiple',
      'question': 'מהו נוהל הברבור (כשיש קשר)?',
      'options': [
        'דיווח למוקד',
        'מתן סימן היכר מוסכם',
        'תיאום חילוץ אם נדרש',
        'הישארות במקום עד להוראה אחרת',
        'שמירה על קשר רציף',
      ],
      'correctAnswers': [0, 1, 2, 3, 4],
      'isReadiness': false,
    },
    {
      'order': 11,
      'type': 'single',
      'question': 'אילו מדדים חובה לבדוק לפני ניווט בדד?',
      'options': [
        'דופק בלבד',
        'חום ודופק',
        'לחץ דם וחום',
        'חום, דופק ולחץ דם',
      ],
      'correctAnswers': [3],
      'isReadiness': false,
    },
    {
      'order': 12,
      'type': 'single',
      'question': 'כמה ניווטי מאבטח חובה לפני ניווט בדד?',
      'options': [
        'עשרה ניווטי לילה מוצלחים',
        'חמישה ניווטי לילה',
        'שלושה ניווטי לילה',
        'ניווט אחד מוצלח מספיק',
      ],
      'correctAnswers': [0],
      'isReadiness': false,
    },
    {
      'order': 13,
      'type': 'single',
      'question': 'מנווט שנפגע — מה יעשה?',
      'options': [
        'ימשיך לנווט עד הנקודה הבאה',
        'ידווח דו"ח מצב, ירה ירי נותבים, ישתלט על שטח שולט וישלח דרורית',
        'ינסה לחזור לבסיס בעצמו',
        'יחכה בשקט עד שימצאו אותו',
      ],
      'correctAnswers': [1],
      'isReadiness': false,
    },
    {
      'order': 14,
      'type': 'single',
      'question': 'אין קשר מעל שעה — מה יעשה המנווט?',
      'options': [
        'יטפס למקום הגבוה ביותר בסביבה וינסה ליצור קשר',
        'ימשיך לנווט כרגיל',
        'יחזור לנקודת ההתחלה',
      ],
      'correctAnswers': [0],
      'isReadiness': false,
    },
    {
      'order': 15,
      'type': 'single',
      'question': 'תנאי מזג אוויר קשים — מה יעשה המנווט?',
      'options': [
        'ימשיך לנווט בקצב מהיר יותר',
        'יחזור מיד לבסיס',
        'יעצור במקום מוצל ובטוח וידווח למוקד',
      ],
      'correctAnswers': [2],
      'isReadiness': false,
    },
  ];

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
