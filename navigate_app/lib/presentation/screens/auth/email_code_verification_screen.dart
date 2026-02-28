import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/auth_service.dart';
import '../../../services/session_service.dart';
import 'sms_verification_screen.dart' show VerificationPurpose;

/// מסך אימות קוד מייל (6 ספרות) — לדסקטופ
class EmailCodeVerificationScreen extends StatefulWidget {
  final String email;
  final String personalNumber;
  final VerificationPurpose purpose;
  final Map<String, String>? registrationData;
  final String? fallbackCode; // קוד שהוחזר מהשרת כש-SMTP לא מוגדר

  const EmailCodeVerificationScreen({
    super.key,
    required this.email,
    required this.personalNumber,
    required this.purpose,
    this.registrationData,
    this.fallbackCode,
  });

  @override
  State<EmailCodeVerificationScreen> createState() =>
      _EmailCodeVerificationScreenState();
}

class _EmailCodeVerificationScreenState
    extends State<EmailCodeVerificationScreen> {
  final AuthService _authService = AuthService();
  final _codeController = TextEditingController();
  bool _isLoading = false;
  bool _isResending = false;
  String? _fallbackCode;

  @override
  void initState() {
    super.initState();
    _fallbackCode = widget.fallbackCode;
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  /// אימות קוד מייל
  Future<void> _verifyCode() async {
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
      await _authService.verifyEmailCode(
        personalNumber: widget.personalNumber,
        code: code,
      );

      if (mounted) {
        await _handleVerificationSuccess();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);

        String errorMessage = 'קוד אימות שגוי';
        final errorStr = e.toString();
        if (errorStr.contains('code_expired')) {
          errorMessage = 'קוד האימות פג תוקף. שלח קוד חדש.';
        } else if (errorStr.contains('max_attempts_exceeded')) {
          errorMessage = 'חרגת ממספר הניסיונות המותר. שלח קוד חדש.';
        } else if (errorStr.contains('invalid_code')) {
          errorMessage = 'קוד אימות שגוי. נסה שוב.';
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
        await _authService.completeLogin(widget.personalNumber);
        await SessionService().clearSession();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('התחברת בהצלחה!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context)
              .pushNamedAndRemoveUntil('/home', (route) => false);
        }
      } else {
        // הרשמה
        final data = widget.registrationData!;
        await _authService.registerUser(
          personalNumber: data['personalNumber']!,
          firstName: data['firstName']!,
          lastName: data['lastName']!,
          email: data['email'] ?? '',
          phoneNumber: data['phoneNumber'] ?? '',
          emailVerified: true,
        );
        await SessionService().clearSession();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('נרשמת בהצלחה!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context)
              .pushNamedAndRemoveUntil('/home', (route) => false);
        }
      }
    } catch (e, stackTrace) {
      print('DEBUG _handleVerificationSuccess ERROR: $e');
      print('DEBUG _handleVerificationSuccess STACK: $stackTrace');
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

  /// שליחה מחדש של קוד מייל
  Future<void> _resendCode() async {
    setState(() => _isResending = true);

    try {
      final code = await _authService.sendEmailVerificationCode(
        email: widget.email,
        personalNumber: widget.personalNumber,
        purpose: widget.purpose == VerificationPurpose.login
            ? 'login'
            : 'registration',
      );

      if (mounted) {
        setState(() {
          _isResending = false;
          _codeController.clear();
          _fallbackCode = code;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('קוד אימות חדש נשלח למייל'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isResending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בשליחה מחדש: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('אימות כתובת מייל'),
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
                  Icons.email,
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
              'קוד אימות נשלח לכתובת המייל',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.email,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
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
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
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
                  _verifyCode();
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
                onPressed: _verifyCode,
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

            // הצגת קוד fallback כשאין SMTP
            if (_fallbackCode != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.amber[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber[300]!),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.info_outline, color: Colors.amber[700], size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'שליחת מייל לא זמינה',
                          style: TextStyle(
                            color: Colors.amber[900],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'קוד האימות שלך:',
                      style: TextStyle(color: Colors.amber[900]),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      _fallbackCode!,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 8,
                        color: Colors.blue[700],
                      ),
                      textDirection: TextDirection.ltr,
                    ),
                  ],
                ),
              ),
            ],

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
