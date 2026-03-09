import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/map_config.dart';
import '../../../domain/entities/area.dart';
import '../../../domain/entities/boundary.dart';
import '../../../domain/entities/checkpoint.dart';
import '../../../data/repositories/checkpoint_repository.dart';
import '../../../data/repositories/boundary_repository.dart';
import '../../../services/auth_service.dart';
import '../../../services/checkpoint_import_service.dart';
import '../../widgets/fullscreen_map_screen.dart';

/// מסך ייבוא נקודות ציון מקובץ CSV/XLSX
class CheckpointImportScreen extends StatefulWidget {
  final Area area;

  const CheckpointImportScreen({super.key, required this.area});

  @override
  State<CheckpointImportScreen> createState() => _CheckpointImportScreenState();
}

class _CheckpointImportScreenState extends State<CheckpointImportScreen> {
  final CheckpointRepository _checkpointRepo = CheckpointRepository();
  final BoundaryRepository _boundaryRepo = BoundaryRepository();

  // קובץ
  String? _selectedFilePath;
  Uint8List? _fileBytes;
  String? _selectedSheetName;

  // גבולות
  List<Boundary> _boundaries = [];
  Boundary? _selectedBoundary;
  bool _loadingBoundaries = true;

  // תוצאות ניתוח
  CheckpointImportResult? _parseResult;
  List<Checkpoint> _existingCheckpoints = [];

  // אפשרויות
  bool _autoNumbering = false;

  // התנגשויות
  final Map<int, ConflictResolution> _conflictResolutions = {};
  bool _applyToAll = false;
  ConflictResolution _applyToAllResolution = ConflictResolution.replaceExisting;

  // בדיקת גבול
  List<BoundaryCheckResult> _boundaryResults = [];
  final Set<int> _removedOutsideBoundary = {};

  // מצב
  bool _isParsing = false;
  bool _isImporting = false;

  // undo
  List<String> _lastImportedIds = [];
  List<Checkpoint> _replacedCheckpoints = [];
  List<Checkpoint> _renumberedOriginals = [];

  @override
  void initState() {
    super.initState();
    _loadBoundaries();
  }

  Future<void> _loadBoundaries() async {
    final boundaries = await _boundaryRepo.getByArea(widget.area.id);
    if (mounted) {
      setState(() {
        _boundaries = boundaries;
        _selectedBoundary = boundaries.isNotEmpty ? boundaries.first : null;
        _loadingBoundaries = false;
      });
    }
  }

  Future<void> _pickFile() async {
    final picked = await CheckpointImportService.pickFile();
    if (picked == null) return;

    // בחירת גיליון אם יש יותר מאחד בקובץ XLSX
    String? sheetName;
    final lowerPath = picked.path.toLowerCase();
    if (lowerPath.endsWith('.xlsx') || lowerPath.endsWith('.xls')) {
      final sheets = CheckpointImportService.getSheetNames(picked.bytes);
      if (sheets.length > 1 && mounted) {
        sheetName = await showDialog<String>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: const Text('בחר גיליון'),
            children: sheets.map((name) => SimpleDialogOption(
              child: Text(name),
              onPressed: () => Navigator.pop(ctx, name),
            )).toList(),
          ),
        );
        if (sheetName == null) return; // המשתמש ביטל
      }
    }

    setState(() {
      _selectedFilePath = picked.path;
      _fileBytes = picked.bytes;
      _selectedSheetName = sheetName;
      _parseResult = null;
      _boundaryResults = [];
      _conflictResolutions.clear();
      _removedOutsideBoundary.clear();
    });
  }

  Future<void> _parseAndValidate() async {
    if (_selectedFilePath == null || _fileBytes == null) return;

    setState(() => _isParsing = true);

    try {
      final result = CheckpointImportService.parseFile(
          _selectedFilePath!, _fileBytes!, sheetName: _selectedSheetName);

      // טעינת נקודות קיימות לבדיקת התנגשויות
      final existing = await _checkpointRepo.getByArea(widget.area.id);

      if (!_autoNumbering) {
        CheckpointImportService.checkConflicts(
            result.parsedRows, existing, boundaryId: _selectedBoundary?.id);
      }

      // בדיקת גבול
      List<BoundaryCheckResult> boundaryResults = [];
      if (_selectedBoundary != null && result.parsedRows.isNotEmpty) {
        boundaryResults = CheckpointImportService.checkBoundary(
            result.parsedRows, _selectedBoundary!);
      }

      setState(() {
        _parseResult = result;
        _existingCheckpoints = existing;
        _boundaryResults = boundaryResults;
        _conflictResolutions.clear();
        _removedOutsideBoundary.clear();
        _isParsing = false;
      });
    } catch (e) {
      setState(() => _isParsing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה בניתוח: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  List<ParsedCheckpointRow> get _validRows {
    if (_parseResult == null) return [];
    return _parseResult!.parsedRows
        .where((r) => !_removedOutsideBoundary.contains(r.sequenceNumber))
        .toList();
  }

  bool get _hasUnresolvedConflicts {
    if (_autoNumbering) return false;
    return _validRows.any((r) =>
        r.hasConflict && !_conflictResolutions.containsKey(r.sequenceNumber));
  }

  bool get _canImport {
    return _parseResult != null &&
        _parseResult!.isSuccess &&
        !_hasUnresolvedConflicts &&
        _validRows.isNotEmpty &&
        !_isImporting;
  }

  Future<void> _doImport() async {
    if (!_canImport) return;
    final user = await AuthService().getCurrentUser();
    if (user == null) return;

    setState(() => _isImporting = true);

    try {
      final rows = _validRows;

      // בניית נקודות חדשות
      final newCheckpoints = CheckpointImportService.buildCheckpoints(
        rows: rows,
        areaId: widget.area.id,
        createdBy: user.uid,
        conflictResolutions: _conflictResolutions,
        existingCheckpoints: _existingCheckpoints,
        autoNumber: _autoNumbering,
        boundaryId: _selectedBoundary?.id,
      );

      // טיפול בהתנגשויות
      final replacedBackup = <Checkpoint>[];
      final renumberedBackup = <Checkpoint>[];

      if (!_autoNumbering) {
        // החלפת קיימות
        for (final row in rows) {
          if (!row.hasConflict || row.conflictingCheckpoint == null) continue;
          final resolution = _conflictResolutions[row.sequenceNumber];
          if (resolution == ConflictResolution.replaceExisting) {
            replacedBackup.add(row.conflictingCheckpoint!);
            await _checkpointRepo.delete(
                row.conflictingCheckpoint!.id, areaId: widget.area.id);
          }
        }

        // שינוי מספור קיימות
        final renumbered = CheckpointImportService.buildRenumberedExisting(
          rows: rows,
          conflictResolutions: _conflictResolutions,
          existingCheckpoints: _existingCheckpoints,
        );
        for (final cp in renumbered) {
          // גיבוי המקור
          renumberedBackup.add(
              _existingCheckpoints.firstWhere((e) => e.id == cp.id));
          await _checkpointRepo.update(cp);
        }
      }

      // יצירת הנקודות החדשות
      final importedIds = <String>[];
      for (final cp in newCheckpoints) {
        final created = await _checkpointRepo.create(cp);
        importedIds.add(created.id);
      }

      setState(() {
        _lastImportedIds = importedIds;
        _replacedCheckpoints = replacedBackup;
        _renumberedOriginals = renumberedBackup;
        _isImporting = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('יובאו ${newCheckpoints.length} נקודות ציון'),
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: 'בטל',
              onPressed: _undoImport,
            ),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() => _isImporting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה בייבוא: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _undoImport() async {
    try {
      // מחיקת הנקודות שיובאו
      if (_lastImportedIds.isNotEmpty) {
        await _checkpointRepo.deleteMany(
            _lastImportedIds, areaId: widget.area.id);
      }

      // שחזור נקודות שהוחלפו
      for (final cp in _replacedCheckpoints) {
        await _checkpointRepo.create(cp);
      }

      // שחזור מספור מקורי
      for (final cp in _renumberedOriginals) {
        await _checkpointRepo.update(cp);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('הייבוא בוטל בהצלחה'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה בביטול: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ייבוא נקודות ציון'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body: _loadingBoundaries
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildInstructionsCard(),
                  const SizedBox(height: 16),
                  _buildTemplateDownload(),
                  const SizedBox(height: 16),
                  _buildFilePickerSection(),
                  const SizedBox(height: 16),
                  _buildBoundaryAndOptions(),
                  const SizedBox(height: 16),
                  _buildParseButton(),
                  if (_parseResult != null) ...[
                    const SizedBox(height: 16),
                    _buildFormatInfo(),
                    if (_parseResult!.errors.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildMessagesCard(
                        title: 'שגיאות',
                        messages: _parseResult!.errors,
                        icon: Icons.error_outline,
                        color: Colors.red,
                      ),
                    ],
                    if (_parseResult!.warnings.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildMessagesCard(
                        title: 'אזהרות',
                        messages: _parseResult!.warnings,
                        icon: Icons.warning_amber,
                        color: Colors.orange,
                      ),
                    ],
                    if (_parseResult!.parsedRows.isNotEmpty) ...[
                      if (_conflictRows.isNotEmpty && !_autoNumbering) ...[
                        const SizedBox(height: 16),
                        _buildConflictSection(),
                      ],
                      if (_outsideBoundaryResults.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _buildBoundaryCheckSection(),
                      ],
                      const SizedBox(height: 16),
                      _buildMapPreview(),
                      const SizedBox(height: 16),
                      _buildSummaryCard(),
                      const SizedBox(height: 16),
                      _buildImportButton(),
                    ],
                  ],
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  // ──────── שלב 1: הוראות ────────

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
                  'הוראות ייבוא',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              '1. הורד תבנית CSV (או צור קובץ CSV/XLSX)\n'
              '2. מלא: מס"ד | קואורדינטות UTM | תיאור\n'
              '3. פורמטים נתמכים:\n'
              '   • 3 עמודות: מס"ד | UTM 12 ספרות | תיאור\n'
              '   • 4 עמודות: מס"ד | מזרח (6) | צפון (6) | תיאור\n'
              '   • קואורדינטות גאוגרפיות (lat/lng)\n'
              '4. סיווג אוטומטי: נ.ה.=התחלה, מ.ח=חובה, נ.ס.=סיום',
              style: TextStyle(fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  // ──────── שלב 1: הורדת תבנית ────────

  Widget _buildTemplateDownload() {
    return OutlinedButton.icon(
      onPressed: () async {
        final path = await CheckpointImportService.exportTemplate();
        if (mounted && path != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('התבנית נשמרה: ${path.split(RegExp(r'[/\\]')).last}')),
          );
        }
      },
      icon: const Icon(Icons.download),
      label: const Text('הורד תבנית CSV'),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.all(16),
      ),
    );
  }

  // ──────── שלב 1: בחירת קובץ ────────

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
            label: const Text('בחר קובץ CSV / XLSX'),
          ),
        ],
      ),
    );
  }

  // ──────── שלב 2: גבול ואפשרויות ────────

  Widget _buildBoundaryAndOptions() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('גבול גזרה', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _selectedBoundary?.id,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'בחר גבול גזרה',
              ),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('ללא גבול (לא תיבדק חריגה)'),
                ),
                ..._boundaries.map((b) => DropdownMenuItem(
                      value: b.id,
                      child: Text(b.name),
                    )),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedBoundary = value == null
                      ? null
                      : _boundaries.firstWhere((b) => b.id == value);
                  // איפוס תוצאות ניתוח אם שינו גבול
                  if (_parseResult != null) {
                    _boundaryResults = [];
                    _removedOutsideBoundary.clear();
                  }
                });
              },
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('מספור אוטומטי'),
              subtitle: const Text('התעלם ממספרי הסדר בקובץ — מספר ברצף'),
              value: _autoNumbering,
              onChanged: (value) {
                setState(() {
                  _autoNumbering = value;
                  _conflictResolutions.clear();
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  // ──────── שלב 3: כפתור ניתוח ────────

  Widget _buildParseButton() {
    return SizedBox(
      height: 50,
      child: ElevatedButton.icon(
        onPressed: _selectedFilePath != null && !_isParsing ? _parseAndValidate : null,
        icon: _isParsing
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Icon(Icons.check_circle_outline),
        label: Text(_isParsing ? 'מנתח...' : 'נתח ואמת'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
        ),
      ),
    );
  }

  // ──────── מידע על פורמט שזוהה ────────

  Widget _buildFormatInfo() {
    final result = _parseResult!;
    return Card(
      color: Colors.indigo[50],
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.analytics, color: Colors.indigo[700]),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'זוהה: ${CheckpointImportService.formatDescription(result.detectedFormat)}, '
                '${result.columnCount} עמודות, '
                '${result.parsedRows.length} שורות תקינות',
                style: TextStyle(color: Colors.indigo[700]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ──────── הודעות שגיאה/אזהרה ────────

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

  // ──────── שלב 4: התנגשויות ────────

  List<ParsedCheckpointRow> get _conflictRows =>
      _validRows.where((r) => r.hasConflict).toList();

  Widget _buildConflictSection() {
    final conflicts = _conflictRows;
    return Card(
      color: Colors.amber[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning, color: Colors.amber[800]),
                const SizedBox(width: 8),
                Text(
                  'התנגשויות מספר סידורי (${conflicts.length})',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.amber[800],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // אפשרות "החל על הכול"
            CheckboxListTile(
              title: const Text('החל על הכול'),
              value: _applyToAll,
              onChanged: (value) {
                setState(() {
                  _applyToAll = value ?? false;
                  if (_applyToAll) {
                    for (final row in conflicts) {
                      _conflictResolutions[row.sequenceNumber] = _applyToAllResolution;
                    }
                  }
                });
              },
            ),
            if (_applyToAll)
              Padding(
                padding: const EdgeInsets.only(right: 16, bottom: 12),
                child: Column(
                  children: [
                    _conflictRadio(ConflictResolution.replaceExisting, 'החלף קיימת'),
                    _conflictRadio(ConflictResolution.renumberExisting, 'שנה מס"ד לקיימת'),
                    _conflictRadio(ConflictResolution.renumberNew, 'שנה מס"ד לחדשה'),
                  ],
                ),
              ),

            const Divider(),

            // רשימת התנגשויות בודדות
            ...conflicts.map((row) {
              final existing = row.conflictingCheckpoint!;
              return _buildConflictCard(row, existing);
            }),
          ],
        ),
      ),
    );
  }

  Widget _conflictRadio(ConflictResolution value, String label) {
    return RadioListTile<ConflictResolution>(
      title: Text(label, style: const TextStyle(fontSize: 14)),
      value: value,
      groupValue: _applyToAllResolution,
      dense: true,
      onChanged: (v) {
        setState(() {
          _applyToAllResolution = v!;
          if (_applyToAll) {
            for (final row in _conflictRows) {
              _conflictResolutions[row.sequenceNumber] = v;
            }
          }
        });
      },
    );
  }

  Widget _buildConflictCard(ParsedCheckpointRow row, Checkpoint existing) {
    final resolution = _conflictResolutions[row.sequenceNumber];
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'מס"ד ${row.sequenceNumber}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text('קיימת: ${existing.description} (UTM: ${existing.coordinates?.utm ?? "—"})'),
            Text('חדשה: ${row.description} (UTM: ${row.coordinate.utm})'),
            if (!_applyToAll) ...[
              const SizedBox(height: 8),
              SegmentedButton<ConflictResolution>(
                segments: const [
                  ButtonSegment(
                    value: ConflictResolution.replaceExisting,
                    label: Text('החלף', style: TextStyle(fontSize: 12)),
                  ),
                  ButtonSegment(
                    value: ConflictResolution.renumberExisting,
                    label: Text('שנה קיימת', style: TextStyle(fontSize: 12)),
                  ),
                  ButtonSegment(
                    value: ConflictResolution.renumberNew,
                    label: Text('שנה חדשה', style: TextStyle(fontSize: 12)),
                  ),
                ],
                emptySelectionAllowed: true,
                selected: resolution != null ? {resolution} : {},
                onSelectionChanged: (selected) {
                  setState(() {
                    _conflictResolutions[row.sequenceNumber] = selected.first;
                  });
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ──────── שלב 5: בדיקת גבול ────────

  List<BoundaryCheckResult> get _outsideBoundaryResults =>
      _boundaryResults.where((r) => !r.isInside).toList();

  Widget _buildBoundaryCheckSection() {
    final outside = _outsideBoundaryResults;
    return Card(
      color: Colors.orange[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.location_off, color: Colors.orange[800]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'נקודות מחוץ לגבול (${outside.length})',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.orange[800],
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      for (final r in outside) {
                        _removedOutsideBoundary.add(r.sequenceNumber);
                      }
                    });
                  },
                  icon: const Icon(Icons.remove_circle_outline, size: 18),
                  label: const Text('הסר הכול', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(foregroundColor: Colors.red[700]),
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      for (final r in outside) {
                        _removedOutsideBoundary.remove(r.sequenceNumber);
                      }
                    });
                  },
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('השאר הכול', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(foregroundColor: Colors.green[700]),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...outside.map((result) {
              final isRemoved = _removedOutsideBoundary.contains(result.sequenceNumber);
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                color: isRemoved ? Colors.red[50] : null,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isRemoved ? Colors.red : Colors.orange,
                    child: Text(
                      '${result.sequenceNumber}',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                  title: Text('מס"ד ${result.sequenceNumber}'),
                  subtitle: Text(
                    'במרחק ${result.distanceMeters?.round() ?? "?"} מ\' מגבול הגזרה',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _removedOutsideBoundary.remove(result.sequenceNumber);
                          });
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: isRemoved ? Colors.grey : Colors.green,
                        ),
                        child: const Text('השאר'),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _removedOutsideBoundary.add(result.sequenceNumber);
                          });
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: isRemoved ? Colors.red : Colors.grey,
                        ),
                        child: const Text('הסר'),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ──────── שלב 6: תצוגת מפה ────────

  Widget _buildMapPreview() {
    final rows = _validRows;
    if (rows.isEmpty) return const SizedBox.shrink();

    // חישוב bounds
    final allPoints = <LatLng>[];
    for (final r in rows) {
      allPoints.add(r.coordinate.toLatLng());
    }
    if (_selectedBoundary != null) {
      for (final c in _selectedBoundary!.coordinates) {
        allPoints.add(c.toLatLng());
      }
    }

    final bounds = LatLngBounds.fromPoints(allPoints);
    final mapConfig = MapConfig();
    final mapType = mapConfig.currentType;

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text('תצוגה מקדימה', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  icon: const Icon(Icons.fullscreen),
                  tooltip: 'מסך מלא',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FullscreenMapScreen(
                          title: 'תצוגה מקדימה',
                          initialCenter: bounds.center,
                          initialCameraFit: CameraFit.bounds(
                            bounds: bounds,
                            padding: const EdgeInsets.all(40),
                          ),
                          layers: [
                            if (_selectedBoundary != null)
                              PolygonLayer(
                                polygons: [
                                  Polygon(
                                    points: _selectedBoundary!.coordinates
                                        .map((c) => c.toLatLng())
                                        .toList(),
                                    color: Colors.black.withValues(alpha: 0.05),
                                    borderColor: Colors.black,
                                    borderStrokeWidth: 2,
                                  ),
                                ],
                              ),
                            MarkerLayer(
                              markers: rows.map((row) {
                                final isOutside = _boundaryResults.any(
                                    (b) => b.sequenceNumber == row.sequenceNumber && !b.isInside);
                                final color = isOutside
                                    ? Colors.orange
                                    : Checkpoint.flutterColorForType(row.detectedType);
                                return Marker(
                                  point: row.coordinate.toLatLng(),
                                  width: 30,
                                  height: 30,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: color,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 2),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.3),
                                          blurRadius: 4,
                                        ),
                                      ],
                                    ),
                                    child: Center(
                                      child: Text(
                                        '${row.sequenceNumber}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          SizedBox(
            height: 300,
            child: FlutterMap(
              options: MapOptions(
                initialCameraFit: CameraFit.bounds(
                  bounds: bounds,
                  padding: const EdgeInsets.all(40),
                ),
                maxZoom: 18,
              ),
              children: [
                TileLayer(
                  urlTemplate: mapConfig.urlTemplate(mapType),
                  userAgentPackageName: MapConfig.userAgentPackageName,
                  maxZoom: mapConfig.maxZoom(mapType),
                ),
                // גבול גזרה
                if (_selectedBoundary != null)
                  PolygonLayer(
                    polygons: [
                      Polygon(
                        points: _selectedBoundary!.coordinates
                            .map((c) => c.toLatLng())
                            .toList(),
                        color: Colors.black.withValues(alpha: 0.05),
                        borderColor: Colors.black,
                        borderStrokeWidth: 2,
                      ),
                    ],
                  ),
                // נקודות
                MarkerLayer(
                  markers: rows.map((row) {
                    final isOutside = _boundaryResults.any(
                        (b) => b.sequenceNumber == row.sequenceNumber && !b.isInside);
                    final color = isOutside
                        ? Colors.orange
                        : Checkpoint.flutterColorForType(row.detectedType);
                    return Marker(
                      point: row.coordinate.toLatLng(),
                      width: 30,
                      height: 30,
                      child: Container(
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            '${row.sequenceNumber}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ──────── שלב 7: סיכום ────────

  Widget _buildSummaryCard() {
    final rows = _validRows;
    final startCount = rows.where((r) => r.detectedType == 'start').length;
    final endCount = rows.where((r) => r.detectedType == 'end').length;
    final mandatoryCount = rows.where((r) => r.detectedType == 'mandatory_passage').length;
    final checkpointCount = rows.where((r) => r.detectedType == 'checkpoint').length;
    final conflictCount = _autoNumbering ? 0 : _conflictRows.length;
    final removedCount = _removedOutsideBoundary.length;

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
                  'סיכום ייבוא',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _summaryRow('סה"כ לייבוא', '${rows.length}'),
            if (startCount > 0) _summaryRow('נקודות התחלה', '$startCount', Colors.green),
            if (endCount > 0) _summaryRow('נקודות סיום', '$endCount', Colors.red),
            if (mandatoryCount > 0) _summaryRow('מעבר חובה', '$mandatoryCount', Colors.amber),
            if (checkpointCount > 0) _summaryRow('נקודות ציון', '$checkpointCount', Colors.blue),
            if (conflictCount > 0) _summaryRow('התנגשויות מטופלות', '$conflictCount'),
            if (removedCount > 0) _summaryRow('נקודות שהוסרו (מחוץ לגבול)', '$removedCount'),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value, [Color? color]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              if (color != null) ...[
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
              ],
              Text(label, style: const TextStyle(fontSize: 14)),
            ],
          ),
          Text(value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // ──────── שלב 8: כפתור ייבוא ────────

  Widget _buildImportButton() {
    return SizedBox(
      height: 50,
      child: ElevatedButton.icon(
        onPressed: _canImport ? _doImport : null,
        icon: _isImporting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Icon(Icons.file_download),
        label: Text(_isImporting
            ? 'מייבא...'
            : _hasUnresolvedConflicts
                ? 'יש לפתור את כל ההתנגשויות'
                : 'ייבא ${_validRows.length} נקודות'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey[300],
        ),
      ),
    );
  }
}
