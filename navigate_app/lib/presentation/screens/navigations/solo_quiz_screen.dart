import 'package:flutter/material.dart';
import '../../../domain/entities/navigation.dart' as domain;
import '../../../domain/entities/user.dart';
import '../../../data/repositories/solo_quiz_repository.dart';
import '../../../data/repositories/user_repository.dart';

/// מסך מבחן ניווט בדד
class SoloQuizScreen extends StatefulWidget {
  final domain.Navigation navigation;
  final User currentUser;

  const SoloQuizScreen({
    super.key,
    required this.navigation,
    required this.currentUser,
  });

  @override
  State<SoloQuizScreen> createState() => _SoloQuizScreenState();
}

class _SoloQuizScreenState extends State<SoloQuizScreen> {
  final SoloQuizRepository _quizRepo = SoloQuizRepository();
  final UserRepository _userRepo = UserRepository();

  List<SoloQuizQuestion> _questions = [];
  Map<String, dynamic> _answers = {};
  int _passingScore = 85;
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _error;

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

      // טעינת שאלות + הגדרות
      final questions = await _quizRepo.getQuestions();
      final passingScore = await _quizRepo.getPassingScore();

      if (questions.isEmpty) {
        setState(() {
          _error = 'שאלות טרם הוגדרו — פנה למפקד';
          _isLoading = false;
        });
        return;
      }

      // טעינת תשובות קיימות (אם יש)
      final existing = await _quizRepo.getAnswers(
        navigationId: widget.navigation.id,
        navigatorId: widget.currentUser.uid,
      );

      setState(() {
        _questions = questions;
        _passingScore = passingScore;
        if (existing != null && existing.completedAt == null) {
          // יש תשובות שטרם הוגשו — שחזור
          _answers = Map<String, dynamic>.from(existing.answers);
        }
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

  Future<void> _submitQuiz() async {
    // בדיקה שכל השאלות נענו
    final unanswered = _questions.where((q) => !_answers.containsKey(q.id)).toList();
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
      final score = _quizRepo.calculateScore(_questions, _answers);
      final passed = score >= _passingScore;

      // שמירה ב-Firestore (quiz_answers)
      await _quizRepo.submitQuiz(
        navigationId: widget.navigation.id,
        navigatorId: widget.currentUser.uid,
        answers: _answers,
        score: score,
        passed: passed,
      );

      // עדכון User (אם עבר)
      if (passed) {
        final updatedUser = widget.currentUser.copyWith(
          soloQuizPassedAt: DateTime.now(),
          soloQuizScore: score,
          updatedAt: DateTime.now(),
        );
        await _userRepo.saveUserLocally(updatedUser);
      }

      setState(() => _isSubmitting = false);

      if (!mounted) return;

      // dialog עם תוצאה
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
                  'ניתן לנסות שוב כל עוד המבחן פתוח',
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
                  Navigator.pop(context); // חזרה ל-home
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('מבחן ניווט בדד'),
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
              : _questions.isEmpty
                  ? const Center(child: Text('לא נמצאו שאלות'))
                  : _buildQuizContent(),
    );
  }

  Widget _buildQuizContent() {
    return Column(
      children: [
        // פס התקדמות
        LinearProgressIndicator(
          value: _answers.length / _questions.length,
          backgroundColor: Colors.grey[200],
          color: Colors.purple,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_answers.length}/${_questions.length} שאלות נענו',
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
            padding: const EdgeInsets.all(16),
            itemCount: _questions.length,
            itemBuilder: (context, index) {
              return _buildQuestionCard(_questions[index], index + 1);
            },
          ),
        ),

        // כפתור הגשה
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _isSubmitting ? null : _submitQuiz,
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send),
              label: Text(
                _isSubmitting ? 'שולח...' : 'שלח מבחן',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuestionCard(SoloQuizQuestion question, int number) {
    final isAnswered = _answers.containsKey(question.id);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isAnswered ? Colors.green.withValues(alpha: 0.5) : Colors.grey.withValues(alpha: 0.3),
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
                  decoration: BoxDecoration(
                    color: question.isReadiness ? Colors.blue : Colors.purple,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '$number',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    question.question,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            if (question.isReadiness)
              Padding(
                padding: const EdgeInsets.only(top: 4, right: 40),
                child: Text(
                  'הצהרת מוכנות',
                  style: TextStyle(fontSize: 12, color: Colors.blue[600]),
                ),
              ),
            const SizedBox(height: 12),

            // אפשרויות
            if (question.type == 'yes_no')
              _buildYesNoOptions(question)
            else if (question.type == 'single')
              _buildSingleOptions(question)
            else if (question.type == 'multiple')
              _buildMultipleOptions(question),
          ],
        ),
      ),
    );
  }

  Widget _buildYesNoOptions(SoloQuizQuestion question) {
    final selected = _answers[question.id] as int?;
    return Column(
      children: [
        RadioListTile<int>(
          title: const Text('כן'),
          value: 0,
          groupValue: selected,
          onChanged: (value) {
            setState(() => _answers[question.id] = value);
            _saveAnswersToFirestore();
          },
          dense: true,
        ),
        RadioListTile<int>(
          title: const Text('לא'),
          value: 1,
          groupValue: selected,
          onChanged: (value) {
            setState(() => _answers[question.id] = value);
            _saveAnswersToFirestore();
          },
          dense: true,
        ),
      ],
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
