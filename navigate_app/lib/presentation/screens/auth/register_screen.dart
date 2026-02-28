import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/auth_service.dart';
import 'sms_verification_screen.dart';
import 'email_code_verification_screen.dart';

/// מסך רישום משתמש חדש — ללא בחירת מסגרת
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final AuthService _authService = AuthService();

  final _personalNumberController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();

  bool _isLoading = false;

  bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  void dispose() {
    _personalNumberController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  // ─── ולידציות ───

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

  String? _validateHebrewName(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return 'נא להזין $fieldName';
    }
    if (value.trim().length < 2) {
      return '$fieldName חייב להכיל לפחות 2 תווים';
    }
    final hebrewRegex = RegExp(r'^[\u0590-\u05FF\s\-]+$');
    if (!hebrewRegex.hasMatch(value.trim())) {
      return '$fieldName חייב להיות בעברית בלבד';
    }
    return null;
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

  String? _validatePhone(String? value) {
    // בדסקטופ — מספר טלפון אופציונלי
    if (_isDesktop && (value == null || value.trim().isEmpty)) {
      return null;
    }
    if (value == null || value.trim().isEmpty) {
      return 'נא להזין מספר טלפון';
    }
    final phoneRegex = RegExp(r'^05\d{8}$');
    if (!phoneRegex.hasMatch(value.trim())) {
      return 'מספר טלפון לא תקין (פורמט: 05XXXXXXXX)';
    }
    return null;
  }

  // ─── הרשמה ───

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final personalNumber = _personalNumberController.text.trim();

      // בדיקת כפילות מספר אישי
      final isTaken = await _authService.isPersonalNumberRegistered(personalNumber);
      if (isTaken) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('מספר אישי זה כבר רשום במערכת'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // נתוני הרשמה
      final phone = _phoneController.text.trim();
      final email = _emailController.text.trim();
      final registrationData = {
        'personalNumber': personalNumber,
        'firstName': _firstNameController.text.trim(),
        'lastName': _lastNameController.text.trim(),
        'email': email,
        'phoneNumber': phone,
      };

      if (!mounted) return;

      if (_isDesktop) {
        // דסקטופ — אימות באמצעות קוד מייל
        final fallbackCode = await _authService.sendEmailVerificationCode(
          email: email,
          personalNumber: personalNumber,
          purpose: 'registration',
        );

        if (mounted) {
          setState(() => _isLoading = false);
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => EmailCodeVerificationScreen(
                email: email,
                personalNumber: personalNumber,
                purpose: VerificationPurpose.registration,
                registrationData: registrationData,
                fallbackCode: fallbackCode,
              ),
            ),
          );
        }
      } else {
        // מובייל — שליחת SMS לאימות מספר טלפון
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
                    personalNumber: personalNumber,
                    purpose: VerificationPurpose.registration,
                    registrationData: registrationData,
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
                    personalNumber: personalNumber,
                    purpose: VerificationPurpose.registration,
                    registrationData: registrationData,
                    autoVerified: true,
                  ),
                ),
              );
            }
          },
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('רישום משתמש חדש'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // הסבר
              Card(
                color: Colors.blue[50],
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue[700]),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'הרשמה למערכת',
                              style: TextStyle(
                                color: Colors.blue[700],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _isDesktop
                                  ? 'מלא את הפרטים הבאים. קוד אימות יישלח לכתובת המייל.'
                                  : 'מלא את הפרטים הבאים. קוד אימות יישלח למספר הטלפון.',
                              style: TextStyle(color: Colors.blue[700]),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // מספר אישי
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
                maxLength: 7,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                validator: _validatePersonalNumber,
                textInputAction: TextInputAction.next,
                enabled: !_isLoading,
              ),
              const SizedBox(height: 16),

              // שם פרטי
              TextFormField(
                controller: _firstNameController,
                decoration: InputDecoration(
                  labelText: 'שם פרטי',
                  prefixIcon: const Icon(Icons.person_outline),
                  hintText: 'בעברית בלבד',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (v) => _validateHebrewName(v, 'שם פרטי'),
                textInputAction: TextInputAction.next,
                enabled: !_isLoading,
              ),
              const SizedBox(height: 16),

              // שם משפחה
              TextFormField(
                controller: _lastNameController,
                decoration: InputDecoration(
                  labelText: 'שם משפחה',
                  prefixIcon: const Icon(Icons.person),
                  hintText: 'בעברית בלבד',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (v) => _validateHebrewName(v, 'שם משפחה'),
                textInputAction: TextInputAction.next,
                enabled: !_isLoading,
              ),
              const SizedBox(height: 16),

              // כתובת מייל
              TextFormField(
                controller: _emailController,
                decoration: InputDecoration(
                  labelText: 'כתובת מייל',
                  prefixIcon: const Icon(Icons.email),
                  hintText: 'example@mail.com',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                keyboardType: TextInputType.emailAddress,
                textDirection: TextDirection.ltr,
                validator: _validateEmail,
                textInputAction: TextInputAction.next,
                enabled: !_isLoading,
              ),
              const SizedBox(height: 16),

              // מספר טלפון
              TextFormField(
                controller: _phoneController,
                decoration: InputDecoration(
                  labelText: _isDesktop ? 'מספר טלפון (אופציונלי)' : 'מספר טלפון',
                  prefixIcon: const Icon(Icons.phone),
                  hintText: '05XXXXXXXX',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.ltr,
                maxLength: 10,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                validator: _validatePhone,
                textInputAction: TextInputAction.done,
                enabled: !_isLoading,
              ),
              const SizedBox(height: 8),

              // הערה על תפקיד ברירת מחדל
              Card(
                color: Colors.grey[100],
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.grey[600], size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'תפקיד ברירת מחדל: מנווט. מנהל המערכת יוכל לשנות את התפקיד לאחר הרישום.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // כפתור רישום
              if (_isLoading)
                const Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text('שולח קוד אימות...'),
                    ],
                  ),
                )
              else
                ElevatedButton.icon(
                  onPressed: _handleRegister,
                  icon: const Icon(Icons.person_add),
                  label: const Text('הרשמה'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),

              const SizedBox(height: 16),

              // כפתור חזרה
              Center(
                child: TextButton(
                  onPressed: _isLoading
                      ? null
                      : () {
                          Navigator.of(context).pop();
                        },
                  child: const Text('חזרה למסך ההתחברות'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
