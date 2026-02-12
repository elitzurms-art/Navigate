import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/auth_service.dart';
import '../../../services/session_service.dart';
import 'sms_verification_screen.dart';
import 'email_verification_screen.dart';

/// מסך כניסה — הזנת מספר אישי
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _authService = AuthService();
  final _formKey = GlobalKey<FormState>();
  final _personalNumberController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkExistingSession();
  }

  @override
  void dispose() {
    _personalNumberController.dispose();
    super.dispose();
  }

  /// בדיקה אם יש משתמש מחובר
  Future<void> _checkExistingSession() async {
    final user = await _authService.getCurrentUser();
    if (user != null && mounted) {
      await SessionService().clearSession();
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/home');
      }
    }
  }

  String? _validatePersonalNumber(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'נא להזין מספר אישי';
    }
    final regex = RegExp(r'^\d{7}$');
    if (!regex.hasMatch(value.trim())) {
      return 'מספר אישי חייב להכיל 7 ספרות בדיוק';
    }
    return null;
  }

  /// כניסה — חיפוש משתמש לפי מספר אישי ושליחה לאימות
  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final personalNumber = _personalNumberController.text.trim();
      final user = await _authService.loginByPersonalNumber(personalNumber);

      if (!mounted) return;

      if (user == null) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('משתמש לא נמצא. הירשם תחילה.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // TODO: כשנפתור את אימות המייל — להחזיר אימות SMS/Email כאן
      // בינתיים: כניסה ישירה ללא אימות
      await _authService.completeLogin(personalNumber);
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

  /// מעבר למסך הרשמה
  void _navigateToRegister() {
    Navigator.of(context).pushNamed('/register');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).primaryColor,
              Theme.of(context).primaryColor.withOpacity(0.7),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // לוגו
                  const Icon(
                    Icons.navigation,
                    size: 100,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 24),

                  // כותרת
                  Text(
                    'Navigate',
                    style: Theme.of(context).textTheme.displayLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'מערכת ניהול ניווטים ותחקור',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 60),

                  // כרטיס כניסה
                  Card(
                    elevation: 8,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'התחבר למערכת',
                              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'הזן את המספר האישי שלך',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 32),

                            // שדה מספר אישי
                            TextFormField(
                              controller: _personalNumberController,
                              decoration: InputDecoration(
                                labelText: 'מספר אישי',
                                hintText: '7 ספרות',
                                prefixIcon: const Icon(Icons.badge),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              keyboardType: TextInputType.number,
                              textDirection: TextDirection.ltr,
                              textAlign: TextAlign.center,
                              maxLength: 7,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              validator: _validatePersonalNumber,
                              enabled: !_isLoading,
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) => _handleLogin(),
                              style: const TextStyle(
                                fontSize: 20,
                                letterSpacing: 4,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 24),

                            // כפתורים
                            if (_isLoading)
                              const Column(
                                children: [
                                  CircularProgressIndicator(),
                                  SizedBox(height: 12),
                                  Text('מחפש משתמש...'),
                                ],
                              )
                            else
                              Column(
                                children: [
                                  // כפתור כניסה
                                  ElevatedButton.icon(
                                    onPressed: _handleLogin,
                                    icon: const Icon(Icons.login),
                                    label: const Text('כניסה'),
                                    style: ElevatedButton.styleFrom(
                                      minimumSize: const Size(double.infinity, 50),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  // כפתור הרשמה
                                  OutlinedButton.icon(
                                    onPressed: _navigateToRegister,
                                    icon: const Icon(Icons.person_add),
                                    label: const Text('הרשמה'),
                                    style: OutlinedButton.styleFrom(
                                      minimumSize: const Size(double.infinity, 50),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 40),

                  // גרסה
                  Text(
                    'גרסה 1.0.0',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
