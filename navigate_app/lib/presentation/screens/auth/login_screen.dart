import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/auth_service.dart' show AuthService, ActiveSessionCheckResult;
import '../../../services/session_service.dart';
import 'sms_verification_screen.dart';
import 'email_code_verification_screen.dart';

/// מצב כניסה — מספר אישי (לבדיקות) או מספר טלפון/מייל
enum _LoginMode { personalNumber, phoneOrEmail }

/// מסך כניסה — הזנת מספר אישי או מספר טלפון
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _authService = AuthService();
  final _formKey = GlobalKey<FormState>();
  final _personalNumberController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  bool _isLoading = false;
  _LoginMode _loginMode = _LoginMode.phoneOrEmail;
  bool _showPersonalNumberOption = false;
  bool _phoneHintAttempted = false;
  final List<DateTime> _navigateTapTimestamps = [];
  Timer? _hidePersonalNumberTimer;

  bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    _checkExistingSession();
    if (!_isDesktop) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _requestPhoneHint());
    }
  }

  @override
  void dispose() {
    _hidePersonalNumberTimer?.cancel();
    _personalNumberController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
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

  Future<void> _requestPhoneHint() async {
    if (_isDesktop || _phoneHintAttempted) return;
    _phoneHintAttempted = true;
    if (_loginMode != _LoginMode.phoneOrEmail) return;

    final phone = await AuthService.requestPhoneNumberHint();
    if (!mounted || phone == null) return;

    _phoneController.text = phone;
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;
    _handlePhoneLogin();
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

  String? _validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'נא להזין מספר טלפון';
    }
    final phoneRegex = RegExp(r'^05\d{8}$');
    if (!phoneRegex.hasMatch(value.trim())) {
      return 'מספר טלפון לא תקין (פורמט: 05XXXXXXXX)';
    }
    return null;
  }

  /// כניסה לפי מספר אישי — ללא אימות SMS (לבדיקות)
  Future<void> _handlePersonalNumberLogin() async {
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

      // בדיקת session פעיל במכשיר אחר
      final sessionCheck = await _authService.checkActiveSession(personalNumber);
      if (!mounted) return;

      if (sessionCheck == ActiveSessionCheckResult.activeSessionExists) {
        setState(() => _isLoading = false);
        final forceLogin = await AuthService.showActiveSessionDialog(context);
        if (!forceLogin || !mounted) return;
        setState(() => _isLoading = true);
      }

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

  /// כניסה לפי מספר טלפון — שליחת SMS ומעבר לאימות
  Future<void> _handlePhoneLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final phone = _phoneController.text.trim();

      // חיפוש משתמש לפי טלפון
      final user = await _authService.loginByPhoneNumber(phone);

      if (!mounted) return;

      if (user == null) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('מספר טלפון לא נמצא במערכת. הירשם תחילה.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // שליחת SMS
      final internationalPhone = _authService.formatPhoneForFirebase(phone);

      await _authService.verifyPhoneNumber(
        phoneNumber: internationalPhone,
        onCodeSent: (verificationId) {
          if (mounted) {
            setState(() => _isLoading = false);
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SmsVerificationScreen(
                  phoneNumber: internationalPhone,
                  verificationId: verificationId,
                  personalNumber: user.uid,
                  purpose: VerificationPurpose.login,
                ),
              ),
            );
          }
        },
        onVerificationFailed: (error) {
          if (mounted) {
            setState(() => _isLoading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('שגיאה בשליחת SMS: $error'),
                backgroundColor: Colors.red,
              ),
            );
          }
        },
        onAutoVerified: (_) {
          // אימות אוטומטי — מעבר ישיר
          if (mounted) {
            setState(() => _isLoading = false);
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SmsVerificationScreen(
                  phoneNumber: internationalPhone,
                  verificationId: '',
                  personalNumber: user.uid,
                  purpose: VerificationPurpose.login,
                  autoVerified: true,
                ),
              ),
            );
          }
        },
      );
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

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'נא להזין כתובת מייל';
    }
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailRegex.hasMatch(value.trim())) {
      return 'כתובת מייל לא תקינה';
    }
    return null;
  }

  /// כניסה לפי מייל — חיפוש משתמש ושליחת קוד אימות (דסקטופ)
  Future<void> _handleEmailLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final email = _emailController.text.trim();
      final user = await _authService.loginByEmail(email);

      if (!mounted) return;

      if (user == null) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('כתובת מייל לא נמצאה במערכת. הירשם תחילה.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // שליחת קוד אימות למייל
      final fallbackCode = await _authService.sendEmailVerificationCode(
        email: email,
        personalNumber: user.uid,
        purpose: 'login',
      );

      if (mounted) {
        setState(() => _isLoading = false);
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => EmailCodeVerificationScreen(
              email: email,
              personalNumber: user.uid,
              purpose: VerificationPurpose.login,
              fallbackCode: fallbackCode,
            ),
          ),
        );
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

  void _onNavigateTitleTap() {
    if (_isDesktop) return;

    final now = DateTime.now();
    _navigateTapTimestamps.removeWhere(
      (t) => now.difference(t).inSeconds > 10,
    );
    _navigateTapTimestamps.add(now);

    if (_navigateTapTimestamps.length > 8) {
      _navigateTapTimestamps.removeRange(0, _navigateTapTimestamps.length - 8);
    }

    if (_navigateTapTimestamps.length >= 6) {
      setState(() {
        _showPersonalNumberOption = true;
        _navigateTapTimestamps.clear();
      });
      _hidePersonalNumberTimer?.cancel();
      _hidePersonalNumberTimer = Timer(const Duration(minutes: 1), () {
        if (mounted) {
          setState(() {
            _showPersonalNumberOption = false;
            _loginMode = _LoginMode.phoneOrEmail;
          });
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('כניסה במספר אישי זמינה לדקה אחת'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Guard: force phoneOrEmail mode if personal number option is hidden on mobile
    if (!_isDesktop && !_showPersonalNumberOption && _loginMode == _LoginMode.personalNumber) {
      _loginMode = _LoginMode.phoneOrEmail;
    }
    final showPersonalNumber = _isDesktop || _showPersonalNumberOption;

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
                  GestureDetector(
                    onTap: _onNavigateTitleTap,
                    child: Text(
                      'Navigate',
                      style: Theme.of(context).textTheme.displayLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
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
                            const SizedBox(height: 24),

                            // טוגל בין מצבי כניסה (מוסתר במובייל עד הפעלה)
                            if (showPersonalNumber) ...[
                              SegmentedButton<_LoginMode>(
                                segments: [
                                  ButtonSegment<_LoginMode>(
                                    value: _LoginMode.phoneOrEmail,
                                    label: Text(_isDesktop ? 'כתובת מייל' : 'מספר טלפון'),
                                    icon: Icon(_isDesktop ? Icons.email : Icons.phone),
                                  ),
                                  const ButtonSegment<_LoginMode>(
                                    value: _LoginMode.personalNumber,
                                    label: Text('מספר אישי'),
                                    icon: Icon(Icons.badge),
                                  ),
                                ],
                                selected: {_loginMode},
                                onSelectionChanged: _isLoading
                                    ? null
                                    : (Set<_LoginMode> newSelection) {
                                        setState(() {
                                          _loginMode = newSelection.first;
                                          _formKey.currentState?.reset();
                                        });
                                      },
                              ),
                              const SizedBox(height: 8),
                            ],
                            Text(
                              _loginMode == _LoginMode.phoneOrEmail
                                  ? (_isDesktop
                                      ? 'הזן כתובת מייל לקבלת קוד אימות'
                                      : 'הזן מספר טלפון לקבלת קוד SMS')
                                  : 'כניסה ישירה למפתחים',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 24),

                            // שדות לפי מצב
                            if (_loginMode == _LoginMode.phoneOrEmail)
                              _isDesktop ? _buildEmailField() : _buildPhoneField()
                            else
                              _buildPersonalNumberField(),

                            const SizedBox(height: 24),

                            // כפתורים
                            if (_isLoading)
                              Column(
                                children: [
                                  const CircularProgressIndicator(),
                                  const SizedBox(height: 12),
                                  Text(_loginMode == _LoginMode.phoneOrEmail
                                      ? 'שולח קוד אימות...'
                                      : 'מחפש משתמש...'),
                                ],
                              )
                            else
                              Column(
                                children: [
                                  // כפתור כניסה
                                  ElevatedButton.icon(
                                    onPressed: _loginMode == _LoginMode.phoneOrEmail
                                        ? (_isDesktop ? _handleEmailLogin : _handlePhoneLogin)
                                        : _handlePersonalNumberLogin,
                                    icon: Icon(_loginMode == _LoginMode.phoneOrEmail
                                        ? (_isDesktop ? Icons.email : Icons.sms)
                                        : Icons.login),
                                    label: Text(_loginMode == _LoginMode.phoneOrEmail
                                        ? 'שלח קוד'
                                        : 'כניסה'),
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

  /// שדה מספר טלפון
  Widget _buildPhoneField() {
    return TextFormField(
      controller: _phoneController,
      decoration: InputDecoration(
        labelText: 'מספר טלפון',
        hintText: '05XXXXXXXX',
        prefixIcon: const Icon(Icons.phone),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      keyboardType: TextInputType.phone,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLength: 10,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
      ],
      validator: _validatePhone,
      enabled: !_isLoading,
      textInputAction: TextInputAction.done,
      onFieldSubmitted: (_) => _handlePhoneLogin(),
      style: const TextStyle(
        fontSize: 20,
        letterSpacing: 2,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  /// שדה כתובת מייל (דסקטופ)
  Widget _buildEmailField() {
    return TextFormField(
      controller: _emailController,
      decoration: InputDecoration(
        labelText: 'כתובת מייל',
        hintText: 'example@mail.com',
        prefixIcon: const Icon(Icons.email),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      keyboardType: TextInputType.emailAddress,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      validator: _validateEmail,
      enabled: !_isLoading,
      textInputAction: TextInputAction.done,
      onFieldSubmitted: (_) => _handleEmailLogin(),
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  /// שדה מספר אישי
  Widget _buildPersonalNumberField() {
    return TextFormField(
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
      onFieldSubmitted: (_) => _handlePersonalNumberLogin(),
      style: const TextStyle(
        fontSize: 20,
        letterSpacing: 4,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}
