import 'package:flutter/material.dart';
import '../../../services/auth_service.dart';
import '../../../services/session_service.dart';
import 'sms_verification_screen.dart'; // for VerificationPurpose enum

/// מסך אימות מייל — לשימוש ב-Windows (Email Link Auth)
/// המשתמש מקבל לינק במייל, מדביק אותו כאן, והמערכת מאמתת
class EmailVerificationScreen extends StatefulWidget {
  final String email;
  final String personalNumber;
  final VerificationPurpose purpose;
  final Map<String, String>? registrationData;

  const EmailVerificationScreen({
    super.key,
    required this.email,
    required this.personalNumber,
    required this.purpose,
    this.registrationData,
  });

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  final AuthService _authService = AuthService();
  final _linkController = TextEditingController();
  bool _isSending = false;
  bool _linkSent = false;
  bool _isVerifying = false;

  @override
  void dispose() {
    _linkController.dispose();
    super.dispose();
  }

  /// שליחת לינק אימות למייל
  Future<void> _sendLink() async {
    setState(() => _isSending = true);

    _authService.sendEmailSignInLink(
      email: widget.email,
      onSuccess: () {
        if (mounted) {
          setState(() {
            _isSending = false;
            _linkSent = true;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('לינק אימות נשלח למייל'),
              backgroundColor: Colors.green,
            ),
          );
        }
      },
      onFailed: (error) {
        if (mounted) {
          setState(() => _isSending = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('שגיאה בשליחת מייל: $error'),
              backgroundColor: Colors.red,
            ),
          );
        }
      },
    );
  }

  /// אימות באמצעות הלינק שהודבק
  Future<void> _verifyWithLink() async {
    final link = _linkController.text.trim();
    if (link.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('נא להדביק את הלינק מהמייל'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // בדיקה מהירה אם הלינק תקין
    if (!_authService.isValidEmailSignInLink(link)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('הלינק שהודבק אינו תקין. נסה להעתיק שוב מהמייל.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isVerifying = true);

    try {
      final result = await _authService.signInWithEmailLink(
        email: widget.email,
        emailLink: link,
      );

      if (result != null) {
        await _handleSuccess();
      } else {
        if (mounted) {
          setState(() => _isVerifying = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('האימות נכשל. וודא שהלינק תקין ונסה שוב.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isVerifying = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// טיפול בהצלחה — כניסה או הרשמה
  Future<void> _handleSuccess() async {
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
        final data = widget.registrationData!;
        await _authService.registerUser(
          personalNumber: data['personalNumber']!,
          firstName: data['firstName']!,
          lastName: data['lastName']!,
          email: data['email'] ?? '',
          phoneNumber: data['phoneNumber']!,
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
    } catch (e) {
      if (mounted) {
        setState(() => _isVerifying = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// דילוג על אימות מייל (dev only — לטסטים)
  Future<void> _skipVerification() async {
    setState(() => _isVerifying = true);
    await _handleSuccess();
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
            const SizedBox(height: 40),

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
              'אימות באמצעות מייל',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),

            // הסבר
            Text(
              'לינק אימות יישלח לכתובת:',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.email,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textDirection: TextDirection.ltr,
            ),
            const SizedBox(height: 40),

            if (!_linkSent) ...[
              // שלב 1: שליחת לינק
              if (_isSending)
                const Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text('שולח לינק אימות...'),
                    ],
                  ),
                )
              else
                ElevatedButton.icon(
                  onPressed: _sendLink,
                  icon: const Icon(Icons.send),
                  label: const Text('שלח לינק אימות'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
            ] else ...[
              // שלב 2: לינק נשלח — הדבקת הלינק
              Card(
                color: Colors.green[50],
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green[700]),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'לינק נשלח!',
                              style: TextStyle(
                                color: Colors.green[700],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'פתח את המייל, העתק את הלינק, והדבק אותו כאן.',
                              style: TextStyle(color: Colors.green[700]),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // שדה הדבקת לינק
              TextFormField(
                controller: _linkController,
                decoration: InputDecoration(
                  labelText: 'הדבק לינק מהמייל',
                  hintText: 'https://...',
                  prefixIcon: const Icon(Icons.link),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                textDirection: TextDirection.ltr,
                maxLines: 2,
                enabled: !_isVerifying,
              ),
              const SizedBox(height: 16),

              // כפתור אימות
              if (_isVerifying)
                const Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text('מאמת...'),
                    ],
                  ),
                )
              else
                ElevatedButton.icon(
                  onPressed: _verifyWithLink,
                  icon: const Icon(Icons.check),
                  label: const Text('אמת לינק'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),

              const SizedBox(height: 16),

              // שליחה מחדש
              Center(
                child: TextButton.icon(
                  onPressed: _isSending ? null : _sendLink,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('שלח לינק מחדש'),
                ),
              ),

              // דילוג (dev)
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: _isVerifying ? null : _skipVerification,
                  child: Text(
                    'דלג על אימות (פיתוח)',
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 24),

            // חזרה
            Center(
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).pop(),
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
