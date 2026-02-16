import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../../domain/entities/navigation.dart' as domain;
import '../../../domain/entities/user.dart' as app_user;
import '../../../data/repositories/navigation_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/repositories/nav_layer_repository.dart';
import '../../../services/checkpoint_excel_service.dart';
import 'routes_verification_screen.dart';

/// שלב 2 - טעינה ידנית מקובץ Excel
class RoutesManualUploadScreen extends StatefulWidget {
  final domain.Navigation navigation;

  const RoutesManualUploadScreen({super.key, required this.navigation});

  @override
  State<RoutesManualUploadScreen> createState() =>
      _RoutesManualUploadScreenState();
}

class _RoutesManualUploadScreenState extends State<RoutesManualUploadScreen> {
  final NavigationRepository _navRepo = NavigationRepository();
  final UserRepository _userRepo = UserRepository();
  final NavLayerRepository _navLayerRepo = NavLayerRepository();

  String? _selectedFilePath;
  bool _isExporting = false;
  bool _isValidating = false;
  bool _isImporting = false;
  List<String> _validationErrors = [];
  List<String> _validationWarnings = [];
  ExcelImportResult? _importResult;
  List<app_user.User> _participants = [];
  bool _loadingParticipants = true;

  @override
  void initState() {
    super.initState();
    _loadParticipants();
  }

  Future<void> _loadParticipants() async {
    try {
      final allUsers = await _userRepo.getAll();
      final selectedIds = widget.navigation.selectedParticipantIds;
      setState(() {
        if (selectedIds.isNotEmpty) {
          _participants =
              allUsers.where((u) => selectedIds.contains(u.uid)).toList();
        } else {
          _participants = allUsers;
        }
        _loadingParticipants = false;
      });
    } catch (e) {
      setState(() {
        _loadingParticipants = false;
        _validationErrors.add('שגיאה בטעינת משתתפים: $e');
      });
    }
  }

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
          _importResult = null;
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

  Future<void> _downloadTemplate() async {
    if (_loadingParticipants) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ממתין לטעינת משתתפים...')),
      );
      return;
    }

    setState(() => _isExporting = true);

    try {
      final path = await CheckpointExcelService.exportTemplate(
        navigation: widget.navigation,
        participants: _participants,
      );

      if (mounted) {
        if (path != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('התבנית נשמרה: ${path.split('/').last}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה בייצוא תבנית: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _validateFile() async {
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
      _importResult = null;
    });

    try {
      final result = await CheckpointExcelService.importFromExcel(
        filePath: _selectedFilePath!,
        navigation: widget.navigation,
        participants: _participants,
      );

      setState(() {
        _isValidating = false;
        _importResult = result;
        _validationErrors = List.from(result.errors);
        _validationWarnings = List.from(result.warnings);
      });
    } catch (e) {
      setState(() {
        _isValidating = false;
        _validationErrors.add('שגיאה בניתוח הקובץ: $e');
      });
    }
  }

  Future<void> _applyImport() async {
    if (_importResult == null || !_importResult!.isSuccess) return;

    setState(() => _isImporting = true);

    try {
      // שמירת נקודות הציון שנוצרו ב-DB
      if (_importResult!.createdCheckpoints.isNotEmpty) {
        await _navLayerRepo
            .addCheckpointsBatch(_importResult!.createdCheckpoints);
      }

      // עדכון הניווט עם הצירים
      final updatedNavigation = widget.navigation.copyWith(
        routes: _importResult!.routes,
        startPoint: _importResult!.startPointId,
        endPoint: _importResult!.endPointId,
        routesStage: 'verification',
        routesDistributed: true,
        updatedAt: DateTime.now(),
      );

      await _navRepo.update(updatedNavigation);

      if (mounted) {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                RoutesVerificationScreen(navigation: updatedNavigation),
          ),
        );
        if (result == true && mounted) {
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      setState(() {
        _isImporting = false;
        _validationErrors.add('שגיאה בשמירת הנתונים: $e');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('טעינה ידנית מקובץ'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body: _loadingParticipants
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // הוראות
                  _buildInstructionsCard(),
                  const SizedBox(height: 24),

                  // הורדת תבנית
                  OutlinedButton.icon(
                    onPressed: _isExporting ? null : _downloadTemplate,
                    icon: _isExporting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download),
                    label: Text(_isExporting
                        ? 'מייצא תבנית...'
                        : 'הורד תבנית Excel (${_participants.length} מנווטים)'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.all(16),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // בחירת קובץ
                  _buildFilePickerSection(),
                  const SizedBox(height: 24),

                  // תוצאות ניתוח
                  if (_validationErrors.isNotEmpty) ...[
                    _buildMessagesCard(
                      title: 'שגיאות',
                      messages: _validationErrors,
                      icon: Icons.error_outline,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                  ],

                  if (_validationWarnings.isNotEmpty) ...[
                    _buildMessagesCard(
                      title: 'אזהרות',
                      messages: _validationWarnings,
                      icon: Icons.warning_amber,
                      color: Colors.orange,
                    ),
                    const SizedBox(height: 16),
                  ],

                  // תצוגה מקדימה
                  if (_importResult != null && _importResult!.isSuccess) ...[
                    _buildPreviewCard(),
                    const SizedBox(height: 16),
                  ],

                  // כפתורי פעולה
                  _buildActionButtons(),

                  const SizedBox(height: 32),

                  // מידע נוסף
                  _buildInfoCard(),
                ],
              ),
            ),
    );
  }

  Widget _buildInstructionsCard() {
    return Card(
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
              '2. מלא נ.צ. בפורמט UTM — 12 ספרות בעמודה אחת, או 6+6 בשתי עמודות\n'
              '3. בגיליון "כללי" — מלא נקודת התחלה (חובה), סיום וביניים\n'
              '4. שמור את הקובץ והעלה אותו כאן',
              style: TextStyle(fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilePickerSection() {
    return Container(
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
                ? 'נבחר: ${_selectedFilePath!.split(RegExp(r'[/\\]')).last}'
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
    );
  }

  Widget _buildMessagesCard({
    required String title,
    required List<String> messages,
    required IconData icon,
    required MaterialColor color,
  }) {
    return Card(
      color: color[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color[700]),
                const SizedBox(width: 8),
                Text(
                  '$title (${messages.length})',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: color[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...messages.map((msg) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '\u2022 $msg',
                    style: TextStyle(color: color[700]),
                  ),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewCard() {
    final result = _importResult!;
    return Card(
      color: Colors.green[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.preview, color: Colors.green[700]),
                const SizedBox(width: 8),
                Text(
                  'תצוגה מקדימה',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _previewRow(
                'מנווטים עם צירים', '${result.routes.length}'),
            _previewRow(
                'נקודות ציון שנוצרו', '${result.createdCheckpoints.length}'),
            _previewRow(
                'נקודת התחלה', result.startPointId != null ? 'כן' : 'לא'),
            _previewRow(
                'נקודת סיום', result.endPointId != null ? 'כן' : 'לא'),
            _previewRow(
                'נקודות ביניים', '${result.waypoints.length}'),
            const Divider(),
            // פירוט לכל מנווט
            ...result.routes.entries.map((entry) {
              final user = _participants
                  .where((u) => u.uid == entry.key)
                  .firstOrNull;
              final name = user?.fullName ?? entry.key;
              final cpCount = entry.value.checkpointIds.length;
              final length =
                  entry.value.routeLengthKm.toStringAsFixed(1);
              return _previewRow(
                  name, '$cpCount נ.צ. ($length ק"מ)');
            }),
          ],
        ),
      ),
    );
  }

  Widget _previewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 14)),
          Text(value,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    final hasValidResult = _importResult != null && _importResult!.isSuccess;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // כפתור ניתוח
        if (!hasValidResult)
          SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              onPressed:
                  _selectedFilePath != null && !_isValidating
                      ? _validateFile
                      : null,
              icon: _isValidating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.check_circle_outline),
              label: Text(_isValidating ? 'מנתח קובץ...' : 'נתח ווודא'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          ),

        // כפתור אישור ויבוא
        if (hasValidResult) ...[
          SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _isImporting ? null : _applyImport,
              icon: _isImporting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.check),
              label: Text(_isImporting ? 'מייבא...' : 'אשר ויבא נתונים'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 8),
          // כפתור ניתוח מחדש
          TextButton.icon(
            onPressed: _isImporting ? null : _validateFile,
            icon: const Icon(Icons.refresh),
            label: const Text('נתח מחדש'),
          ),
        ],
      ],
    );
  }

  Widget _buildInfoCard() {
    return Card(
      color: Colors.grey[100],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'פורמט נ.צ. נתמך',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '\u2713 12 ספרות UTM בעמודה אחת (למשל: 123456789012)\n'
              '\u2713 6 ספרות מזרח + 6 ספרות צפון בשתי עמודות\n'
              '\u2713 תאים ריקים = נקודה לא מוגדרת (דילוג)\n'
              '\u2713 אזור UTM: 36 (ישראל)',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
