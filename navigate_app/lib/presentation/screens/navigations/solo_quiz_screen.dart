import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../domain/entities/navigation.dart' as domain;
import '../../../domain/entities/user.dart';
import '../../../data/repositories/solo_quiz_repository.dart';
import '../../../data/repositories/user_repository.dart';

/// מסך מבחן ניווט — שני שלבים: הצהרות מוכנות + מבחן ידע (בדד) או מבחן ידע בלבד (רגיל)
class SoloQuizScreen extends StatefulWidget {
  final domain.Navigation navigation;
  final User currentUser;
  final String quizType; // 'solo' או 'regular'

  const SoloQuizScreen({
    super.key,
    required this.navigation,
    required this.currentUser,
    this.quizType = 'solo',
  });

  @override
  State<SoloQuizScreen> createState() => _SoloQuizScreenState();
}

class _SoloQuizScreenState extends State<SoloQuizScreen> {
  final SoloQuizRepository _quizRepo = SoloQuizRepository();
  final UserRepository _userRepo = UserRepository();

  List<SoloQuizQuestion> _readinessQuestions = [];
  List<SoloQuizQuestion> _knowledgeQuestions = [];
  Map<String, dynamic> _answers = {};
  int _passingScore = 85;
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _error;

  /// 0 = שלב מוכנות (שאלה אחת בכל פעם), 1 = שלב ידע (כולן ביחד)
  int _phase = 0;
  /// אינדקס השאלה הנוכחית בשלב המוכנות (0–4)
  int _readinessIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadQuiz();
  }

  Future<void> _loadQuiz() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final bool isRegular = widget.quizType == 'regular';
      final questions = isRegular
          ? await _quizRepo.getRegularQuestions()
          : await _quizRepo.getQuestions();
      final passingScore = isRegular
          ? await _quizRepo.getRegularPassingScore()
          : await _quizRepo.getPassingScore();

      if (questions.isEmpty) {
        setState(() {
          _error = 'שאלות טרם הוגדרו — פנה למפקד';
          _isLoading = false;
        });
        return;
      }

      final readiness = isRegular
          ? <SoloQuizQuestion>[]
          : questions.where((q) => q.isReadiness).toList();
      final knowledge = questions.where((q) => !q.isReadiness).toList();

      // טעינת תשובות קיימות (אם יש)
      final existing = await _quizRepo.getAnswers(
        navigationId: widget.navigation.id,
        navigatorId: widget.currentUser.uid,
      );

      int phase = readiness.isEmpty ? 1 : 0;
      int readinessIndex = 0;
      Map<String, dynamic> answers = {};

      if (existing != null && existing.completedAt == null) {
        answers = Map<String, dynamic>.from(existing.answers);

        // בדיקה אם כל שאלות המוכנות נענו ב"כן"
        if (readiness.isNotEmpty) {
          final allReadinessPassed = readiness.every((q) {
            final answer = answers[q.id];
            return answer != null && answer == 0; // 0 = כן
          });

          if (allReadinessPassed) {
            phase = 1;
          }
        }
      }

      setState(() {
        _readinessQuestions = readiness;
        _knowledgeQuestions = knowledge;
        _passingScore = passingScore;
        _answers = answers;
        _phase = phase;
        _readinessIndex = readinessIndex;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'שגיאה בטעינת המבחן: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _saveAnswersToFirestore() async {
    try {
      await _quizRepo.saveAnswers(
        navigationId: widget.navigation.id,
        navigatorId: widget.currentUser.uid,
        answers: _answers,
      );
    } catch (_) {
      // שמירה ברקע — לא חוסמת
    }
  }

  void _onReadinessAnswer(SoloQuizQuestion question, int value) {
    setState(() => _answers[question.id] = value);
    _saveAnswersToFirestore();
  }

  void _showDisqualificationDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.block, color: Colors.red[700], size: 28),
            const SizedBox(width: 8),
            const Expanded(child: Text('לא ניתן להמשיך')),
          ],
        ),
        content: const Text(
          'אינך מתאים לביצוע ניווט בדד — פנה למפקד',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx); // סגירת dialog
              Navigator.pop(context); // חזרה מהמבחן
            },
            child: const Text('סגור'),
          ),
        ],
      ),
    );
  }

  void _advanceReadiness() {
    final question = _readinessQuestions[_readinessIndex];
    final selected = _answers[question.id] as int?;

    // בחר "לא" ולחץ הבא — פסילה
    if (selected == 1) {
      _showDisqualificationDialog();
      return;
    }

    if (_readinessIndex < _readinessQuestions.length - 1) {
      setState(() => _readinessIndex++);
    } else {
      // כל שאלות המוכנות נענו ב"כן" — מעבר לשלב 2
      setState(() => _phase = 1);
    }
  }

  Future<void> _submitQuiz() async {
    // בדיקה שכל שאלות הידע נענו
    final unanswered = _knowledgeQuestions
        .where((q) => !_answers.containsKey(q.id))
        .toList();
    if (unanswered.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('יש ${unanswered.length} שאלות שלא נענו'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final allQuestions = [..._readinessQuestions, ..._knowledgeQuestions];
      final score = _quizRepo.calculateScore(allQuestions, _answers);
      final passed = score >= _passingScore;

      await _quizRepo.submitQuiz(
        navigationId: widget.navigation.id,
        navigatorId: widget.currentUser.uid,
        answers: _answers,
        score: score,
        passed: passed,
      );

      if (passed && widget.quizType == 'solo') {
        final updatedUser = widget.currentUser.copyWith(
          soloQuizPassedAt: DateTime.now(),
          soloQuizScore: score,
          updatedAt: DateTime.now(),
        );
        await _userRepo.saveUserLocally(updatedUser);
      }

      setState(() => _isSubmitting = false);

      if (!mounted) return;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              Icon(
                passed ? Icons.check_circle : Icons.cancel,
                color: passed ? Colors.green : Colors.red,
                size: 28,
              ),
              const SizedBox(width: 8),
              Text(passed ? 'עברת בהצלחה!' : 'לא עברת'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'ציון: $score%',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: passed ? Colors.green : Colors.red,
                ),
              ),
              const SizedBox(height: 8),
              Text('סף מעבר: $_passingScore%'),
              if (!passed) ...[
                const SizedBox(height: 16),
                const Text(
                  'ניתן לנסות שוב',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                if (passed) {
                  Navigator.pop(context);
                } else {
                  // איפוס — חזרה לשלב המתאים
                  setState(() {
                    _phase = _readinessQuestions.isEmpty ? 1 : 0;
                    _readinessIndex = 0;
                    _answers = {};
                  });
                }
              },
              child: Text(passed ? 'סגור' : 'חזרה למבחן'),
            ),
          ],
        ),
      );
    } catch (e) {
      setState(() => _isSubmitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה בהגשת המבחן: $e')),
        );
      }
    }
  }

  Future<void> _openDocumentUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('לא ניתן לפתוח את הקישור')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.quizType == 'regular' ? 'מבחן ניווט' : 'מבחן ניווט בדד'),
        backgroundColor: Colors.purple,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
                      const SizedBox(height: 16),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadQuiz,
                        child: const Text('נסה שוב'),
                      ),
                    ],
                  ),
                )
              : _phase == 0
                  ? _buildReadinessPhase()
                  : _buildKnowledgePhase(),
    );
  }

  // ============================================================
  // שלב 1 — הצהרות מוכנות (שאלה אחת בכל פעם)
  // ============================================================

  Widget _buildReadinessPhase() {
    if (_readinessQuestions.isEmpty) {
      return const Center(child: Text('לא נמצאו שאלות מוכנות'));
    }

    final question = _readinessQuestions[_readinessIndex];
    final selected = _answers[question.id] as int?;
    final isAnswered = selected != null;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // כותרת שלב
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            color: Colors.blue[50],
            child: Text(
              'שלב 1 מתוך 2 — הצהרות מוכנות',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.blue[800],
              ),
              textAlign: TextAlign.center,
            ),
          ),

          // נקודות התקדמות
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_readinessQuestions.length, (index) {
                final isCompleted = index < _readinessIndex ||
                    (index == _readinessIndex && selected == 0);
                final isCurrent = index == _readinessIndex;
                return Container(
                  width: isCurrent ? 14 : 10,
                  height: isCurrent ? 14 : 10,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isCompleted
                        ? Colors.green
                        : isCurrent
                            ? Colors.blue
                            : Colors.grey[300],
                    border: isCurrent
                        ? Border.all(color: Colors.blue[700]!, width: 2)
                        : null,
                  ),
                );
              }),
            ),
          ),

          // כרטיס שאלה
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // כותרת סקציה
                  if (question.sectionTitle != null) ...[
                    Text(
                      question.sectionTitle!,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[800],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

                  // קישור למסמך
                  if (question.documentUrl != null) ...[
                    OutlinedButton.icon(
                      onPressed: () =>
                          _openDocumentUrl(question.documentUrl!),
                      icon: const Icon(Icons.description, size: 18),
                      label: const Text('לחץ לקריאת המסמך'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.blue[700],
                        side: BorderSide(color: Colors.blue[300]!),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // טקסט השאלה
                  Text(
                    question.question,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // כן / לא
                  RadioListTile<int>(
                    title: const Text('כן', style: TextStyle(fontSize: 16)),
                    value: 0,
                    groupValue: selected,
                    onChanged: (value) =>
                        _onReadinessAnswer(question, value!),
                    activeColor: Colors.green,
                    dense: true,
                    visualDensity: VisualDensity.compact,
                  ),
                  RadioListTile<int>(
                    title: const Text('לא', style: TextStyle(fontSize: 16)),
                    value: 1,
                    groupValue: selected,
                    onChanged: (value) =>
                        _onReadinessAnswer(question, value!),
                    activeColor: Colors.red,
                    dense: true,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // כפתור "הבא"
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: isAnswered ? _advanceReadiness : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                _readinessIndex < _readinessQuestions.length - 1
                    ? 'הבא'
                    : 'המשך למבחן',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // שלב 2 — מבחן ידע (כל השאלות ביחד)
  // ============================================================

  Widget _buildKnowledgePhase() {
    final answeredCount = _knowledgeQuestions
        .where((q) => _answers.containsKey(q.id))
        .length;

    return Column(
      children: [
        // כותרת שלב
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: Colors.purple[50],
          child: Text(
            _readinessQuestions.isEmpty ? 'מבחן ידע' : 'שלב 2 מתוך 2 — מבחן ידע',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.purple[800],
            ),
            textAlign: TextAlign.center,
          ),
        ),

        // פס התקדמות
        LinearProgressIndicator(
          value: _knowledgeQuestions.isEmpty
              ? 0
              : answeredCount / _knowledgeQuestions.length,
          backgroundColor: Colors.grey[200],
          color: Colors.purple,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$answeredCount/${_knowledgeQuestions.length} שאלות נענו',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                'סף מעבר: $_passingScore%',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
          ),
        ),

        // רשימת שאלות
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            itemCount: _knowledgeQuestions.length,
            itemBuilder: (context, index) {
              return _buildQuestionCard(
                  _knowledgeQuestions[index], index + 1);
            },
          ),
        ),

        // כפתור הגשה
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          child: SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: _isSubmitting ? null : _submitQuiz,
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send),
              label: Text(
                _isSubmitting ? 'שולח...' : 'שלח מבחן',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // כרטיס שאלה (שלב 2 — ידע)
  // ============================================================

  Widget _buildQuestionCard(SoloQuizQuestion question, int number) {
    final isAnswered = _answers.containsKey(question.id);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isAnswered
              ? Colors.green.withValues(alpha: 0.5)
              : Colors.grey.withValues(alpha: 0.3),
          width: isAnswered ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // כותרת שאלה
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                    color: Colors.purple,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '$number',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    question.question,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // אפשרויות
            if (question.type == 'single')
              _buildSingleOptions(question)
            else if (question.type == 'multiple')
              _buildMultipleOptions(question),
          ],
        ),
      ),
    );
  }

  Widget _buildSingleOptions(SoloQuizQuestion question) {
    final selected = _answers[question.id] as int?;
    return Column(
      children: List.generate(question.options.length, (index) {
        return RadioListTile<int>(
          title: Text(question.options[index]),
          value: index,
          groupValue: selected,
          onChanged: (value) {
            setState(() => _answers[question.id] = value);
            _saveAnswersToFirestore();
          },
          dense: true,
        );
      }),
    );
  }

  Widget _buildMultipleOptions(SoloQuizQuestion question) {
    final selected = (_answers[question.id] as List?)?.cast<int>() ?? [];
    return Column(
      children: List.generate(question.options.length, (index) {
        return CheckboxListTile(
          title: Text(question.options[index]),
          value: selected.contains(index),
          onChanged: (checked) {
            setState(() {
              final current = List<int>.from(selected);
              if (checked == true) {
                current.add(index);
              } else {
                current.remove(index);
              }
              _answers[question.id] = current;
            });
            _saveAnswersToFirestore();
          },
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
        );
      }),
    );
  }
}
