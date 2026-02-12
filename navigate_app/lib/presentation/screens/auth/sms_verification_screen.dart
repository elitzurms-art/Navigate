import 'package:flutter/material.dart';
import '../../../services/auth_service.dart';
import '../../../services/session_service.dart';

/// מטרת האימות — כניסה או הרשמה
enum VerificationPurpose { login, registration }

/// מסך אימות קוד SMS
class SmsVerificationScreen extends StatefulWidget {
  final String phoneNumber;
  final String verificationId;
  final String personalNumber;
  final VerificationPurpose purpose;
  final Map<String, String>? registrationData;
  final bool autoVerified;

  const SmsVerificationScreen({
    super.key,
    required this.phoneNumber,
    required this.verificationId,
    required this.personalNumber,
    required this.purpose,
    this.registrationData,
    this.autoVerified = false,
  });

  @override
  State<SmsVerificationScreen> createState() => _SmsVerificationScreenState();
}

class _SmsVerificationScreenState extends State<SmsVerificationScreen> {
  final AuthService _authService = AuthService();
  final _codeController = TextEditingController();
  bool _isLoading = false;
  bool _isResending = false;
  String _currentVerificationId = '';

  @override
  void initState() {
    super.initState();
    _currentVerificationId = widget.verificationId;

    // אם אימות אוטומטי - מעבר ישר
    if (widget.autoVerified) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleVerificationSuccess();
      });
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  /// אימות קוד SMS וכניסה
  Future<void> _verifySmsCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty || code.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('נא להזין קוד אימות בן 6 ספרות'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // כניסה עם קוד SMS
      await _authService.signInWithSmsCode(
        verificationId: _currentVerificationId,
        smsCode: code,
      );

      if (mounted) {
        await _handleVerificationSuccess();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);

        String errorMessage = 'קוד אימות שגוי';
        if (e.toString().contains('invalid-verification-code')) {
          errorMessage = 'קוד אימות שגוי. נסה שוב.';
        } else if (e.toString().contains('session-expired')) {
          errorMessage = 'קוד האימות פג תוקף. שלח קוד חדש.';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// טיפול לאחר אימות מוצלח
  Future<void> _handleVerificationSuccess() async {
    if (!mounted) return;

    try {
      if (widget.purpose == VerificationPurpose.login) {
        // כניסה — שמירת session ומעבר לבית
        await _authService.completeLogin(widget.personalNumber);
        await SessionService().clearSession();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('התחברת בהצלחה!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
        }
      } else {
        // הרשמה — רישום המשתמש ומעבר לבית
        final data = widget.registrationData!;
        await _authService.registerUser(
          personalNumber: data['personalNumber']!,
          firstName: data['firstName']!,
          lastName: data['lastName']!,
          email: data['email'] ?? '',
          phoneNumber: data['phoneNumber']!,
          phoneVerified: true,
        );
        await SessionService().clearSession();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('נרשמת בהצלחה!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// שליחה מחדש של קוד SMS
  Future<void> _resendCode() async {
    setState(() => _isResending = true);

    try {
      await _authService.verifyPhoneNumber(
        phoneNumber: widget.phoneNumber,
        onCodeSent: (verificationId) {
          if (mounted) {
            setState(() {
              _currentVerificationId = verificationId;
              _isResending = false;
              _codeController.clear();
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('קוד אימות חדש נשלח'),
                backgroundColor: Colors.green,
              ),
            );
          }
        },
        onVerificationFailed: (error) {
          if (mounted) {
            setState(() => _isResending = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('שגיאה בשליחה מחדש: $error'),
                backgroundColor: Colors.red,
              ),
            );
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isResending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // אם אימות אוטומטי - מסך טעינה
    if (widget.autoVerified) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 24),
              Text(
                'מאמת מספר טלפון...',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('אימות מספר טלפון'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),

            // אייקון
            Center(
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.sms,
                  size: 40,
                  color: Colors.blue[700],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // כותרת
            Text(
              'הזן קוד אימות',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),

            // הסבר
            Text(
              'קוד אימות נשלח למספר',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.phoneNumber,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
              textDirection: TextDirection.ltr,
            ),
            const SizedBox(height: 32),

            // שדה קוד אימות
            TextFormField(
              controller: _codeController,
              decoration: InputDecoration(
                labelText: 'קוד אימות',
                hintText: '______',
                prefixIcon: const Icon(Icons.lock_outline),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                counterText: '',
              ),
              keyboardType: TextInputType.number,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.center,
              maxLength: 6,
              style: const TextStyle(
                fontSize: 24,
                letterSpacing: 8,
                fontWeight: FontWeight.bold,
              ),
              enabled: !_isLoading,
              autofocus: true,
              onChanged: (value) {
                // אימות אוטומטי כשיש 6 ספרות
                if (value.length == 6) {
                  _verifySmsCode();
                }
              },
            ),
            const SizedBox(height: 24),

            // כפתור אימות
            if (_isLoading)
              const Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('מאמת קוד...'),
                  ],
                ),
              )
            else
              ElevatedButton.icon(
                onPressed: _verifySmsCode,
                icon: const Icon(Icons.check),
                label: const Text('אמת קוד'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),

            const SizedBox(height: 24),

            // שליחה מחדש
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'לא קיבלת קוד?',
                  style: TextStyle(color: Colors.grey[600]),
                ),
                const SizedBox(width: 4),
                _isResending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : TextButton(
                        onPressed: _resendCode,
                        child: const Text('שלח שוב'),
                      ),
              ],
            ),

            const SizedBox(height: 16),

            // חזרה
            Center(
              child: TextButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text('חזרה'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
