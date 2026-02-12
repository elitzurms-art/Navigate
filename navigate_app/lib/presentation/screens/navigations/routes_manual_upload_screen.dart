import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../../../domain/entities/navigation.dart' as domain;
import '../../../data/repositories/navigation_repository.dart';
import 'routes_verification_screen.dart';

/// שלב 2 - טעינה ידנית מקובץ Excel
class RoutesManualUploadScreen extends StatefulWidget {
  final domain.Navigation navigation;

  const RoutesManualUploadScreen({super.key, required this.navigation});

  @override
  State<RoutesManualUploadScreen> createState() => _RoutesManualUploadScreenState();
}

class _RoutesManualUploadScreenState extends State<RoutesManualUploadScreen> {
  final NavigationRepository _navRepo = NavigationRepository();

  String? _selectedFilePath;
  bool _isLoading = false;
  bool _isValidating = false;
  List<String> _validationErrors = [];
  List<String> _validationWarnings = [];

  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
      );

      if (result != null) {
        setState(() {
          _selectedFilePath = result.files.single.path;
          _validationErrors.clear();
          _validationWarnings.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה בבחירת קובץ: $e')),
        );
      }
    }
  }

  Future<void> _validateAndUpload() async {
    if (_selectedFilePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('יש לבחור קובץ')),
      );
      return;
    }

    setState(() {
      _isValidating = true;
      _validationErrors.clear();
      _validationWarnings.clear();
    });

    try {
      // TODO: לממש ניתוח קובץ Excel
      // 1. קריאת הקובץ
      // 2. וידוא משתמשים
      // 3. וידוא נקודות
      // 4. יצירת AssignedRoute לכל מנווט

      await Future.delayed(const Duration(seconds: 2)); // סימולציה

      // סימולציה - יצירת צירים מדומים
      Map<String, domain.AssignedRoute> routes = {
        'navigator1': domain.AssignedRoute(
          checkpointIds: ['cp1', 'cp2', 'cp3'],
          routeLengthKm: 8.5,
          sequence: ['cp1', 'cp2', 'cp3'],
          status: 'optimal',
        ),
        'navigator2': domain.AssignedRoute(
          checkpointIds: ['cp4', 'cp5', 'cp6'],
          routeLengthKm: 12.3,
          sequence: ['cp4', 'cp5', 'cp6'],
          status: 'optimal',
        ),
      };

      // עדכון ניווט
      final updatedNavigation = widget.navigation.copyWith(
        routes: routes,
        routesStage: 'verification',
        routesDistributed: true,
        updatedAt: DateTime.now(),
      );

      await _navRepo.update(updatedNavigation);

      if (mounted) {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => RoutesVerificationScreen(navigation: updatedNavigation),
          ),
        );
        if (result == true && mounted) {
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      setState(() {
        _isValidating = false;
        _validationErrors.add('שגיאה בטעינת הקובץ: $e');
      });
    }
  }

  Future<void> _downloadTemplate() async {
    // TODO: ליצור ולהוריד תבנית Excel
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('בפיתוח - הורדת תבנית')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('טעינה ידנית מקובץ'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // הסבר
            Card(
              color: Colors.blue[50],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue[700]),
                        const SizedBox(width: 8),
                        Text(
                          'הוראות',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[700],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '1. הורד את תבנית קובץ ה-Excel\n'
                      '2. מלא את הנתונים: שמות מנווטים ונקודות ציון\n'
                      '3. שמור את הקובץ\n'
                      '4. העלה את הקובץ כאן',
                      style: TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // הורדת תבנית
            OutlinedButton.icon(
              onPressed: _downloadTemplate,
              icon: const Icon(Icons.download),
              label: const Text('הורד תבנית Excel'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 24),

            // בחירת קובץ
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(8),
                color: _selectedFilePath != null ? Colors.green[50] : Colors.grey[50],
              ),
              child: Column(
                children: [
                  Icon(
                    _selectedFilePath != null ? Icons.check_circle : Icons.upload_file,
                    size: 64,
                    color: _selectedFilePath != null ? Colors.green : Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _selectedFilePath != null
                        ? 'נבחר: ${_selectedFilePath!.split('/').last}'
                        : 'לא נבחר קובץ',
                    style: const TextStyle(fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _pickFile,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('בחר קובץ Excel'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // שגיאות ואזהרות
            if (_validationErrors.isNotEmpty) ...[
              Card(
                color: Colors.red[50],
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.error_outline, color: Colors.red[700]),
                          const SizedBox(width: 8),
                          Text(
                            'שגיאות',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.red[700],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ..._validationErrors.map((error) => Text(
                            '• $error',
                            style: TextStyle(color: Colors.red[700]),
                          )),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            if (_validationWarnings.isNotEmpty) ...[
              Card(
                color: Colors.orange[50],
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.warning_amber, color: Colors.orange[700]),
                          const SizedBox(width: 8),
                          Text(
                            'אזהרות',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.orange[700],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ..._validationWarnings.map((warning) => Text(
                            '• $warning',
                            style: TextStyle(color: Colors.orange[700]),
                          )),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // כפתור טעינה
            SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _selectedFilePath != null && !_isValidating
                    ? _validateAndUpload
                    : null,
                icon: _isValidating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.cloud_upload),
                label: Text(_isValidating ? 'מעלה...' : 'טען ווודא'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
            ),

            const SizedBox(height: 32),

            // מידע נוסף
            Card(
              color: Colors.grey[100],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'מה קורה בתהליך הווידוא?',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '✓ בדיקה שכל המנווטים רשומים במערכת\n'
                      '✓ וידוא שכל נקודות הציון קיימות\n'
                      '✓ חישוב אורכי צירים\n'
                      '✓ זיהוי צירים לא אופטימליים',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
