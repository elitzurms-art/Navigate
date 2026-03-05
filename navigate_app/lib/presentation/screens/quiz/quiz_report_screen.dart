import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show Uint8List, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../core/utils/file_export_helper.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/repositories/unit_repository.dart';
import '../../../domain/entities/user.dart';

/// מסך דוח מבחנים — מציג סטטוס מבחנים לכל חברי היחידה (4 חודשים אחרונים)
class QuizReportScreen extends StatefulWidget {
  final String unitId;

  const QuizReportScreen({super.key, required this.unitId});

  @override
  State<QuizReportScreen> createState() => _QuizReportScreenState();
}

class _QuizReportScreenState extends State<QuizReportScreen> {
  final UserRepository _userRepo = UserRepository();
  final UnitRepository _unitRepo = UnitRepository();

  List<User> _users = [];
  bool _isLoading = true;
  String? _error;
  String _unitName = '';

  // סינון סוגי מבחנים
  bool _showSoloQuiz = true;
  bool _showRegularQuiz = true;
  bool _showCommanderQuiz = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final unit = await _unitRepo.getById(widget.unitId);
      _unitName = unit?.name ?? '';

      // טעינת כל המשתמשים ביחידה + יחידות צאצא
      final descendantIds = await _unitRepo.getDescendantIds(widget.unitId);
      final allUnitIds = [widget.unitId, ...descendantIds];

      final users = await _userRepo.getApprovedUsersForUnit(allUnitIds.first);
      final List<User> allUsers = [...users];

      for (final childId in descendantIds) {
        final childUsers = await _userRepo.getApprovedUsersForUnit(childId);
        allUsers.addAll(childUsers);
      }

      // מיון לפי שם
      allUsers.sort((a, b) => a.fullName.compareTo(b.fullName));

      setState(() {
        _users = allUsers;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'שגיאה בטעינת הנתונים: $e';
        _isLoading = false;
      });
    }
  }

  String _getQuizStatus(DateTime? passedAt, int? score) {
    if (passedAt == null) return 'לא ביצע';
    final fourMonthsAgo = DateTime.now().subtract(const Duration(days: 120));
    if (passedAt.isAfter(fourMonthsAgo)) {
      return 'עבר ($score%)';
    }
    return 'פג תוקף ($score%)';
  }

  Color _getQuizStatusColor(DateTime? passedAt) {
    if (passedAt == null) return Colors.grey;
    final fourMonthsAgo = DateTime.now().subtract(const Duration(days: 120));
    if (passedAt.isAfter(fourMonthsAgo)) return Colors.green;
    return Colors.orange;
  }

  IconData _getQuizStatusIcon(DateTime? passedAt) {
    if (passedAt == null) return Icons.close;
    final fourMonthsAgo = DateTime.now().subtract(const Duration(days: 120));
    if (passedAt.isAfter(fourMonthsAgo)) return Icons.check_circle;
    return Icons.warning;
  }

  int get _activeQuizCount {
    int count = 0;
    if (_showSoloQuiz) count++;
    if (_showRegularQuiz) count++;
    if (_showCommanderQuiz) count++;
    return count;
  }

  List<String> get _activeQuizTypes {
    final types = <String>[];
    if (_showSoloQuiz) types.add('בדד');
    if (_showRegularQuiz) types.add('רגיל');
    if (_showCommanderQuiz) types.add('מפקדים');
    return types;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('דוח מבחנים${_unitName.isNotEmpty ? ' — $_unitName' : ''}'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'ייצוא PDF',
            onPressed: _users.isEmpty ? null : _exportPdf,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterBar(),
          const Divider(height: 1),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Text('הצג: ', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('בדד'),
            selected: _showSoloQuiz,
            onSelected: (v) => setState(() => _showSoloQuiz = v),
            selectedColor: Colors.blue[100],
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('רגיל'),
            selected: _showRegularQuiz,
            onSelected: (v) => setState(() => _showRegularQuiz = v),
            selectedColor: Colors.green[100],
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('מפקדים'),
            selected: _showCommanderQuiz,
            onSelected: (v) => setState(() => _showCommanderQuiz = v),
            selectedColor: Colors.purple[100],
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadData, child: const Text('נסה שוב')),
          ],
        ),
      );
    }
    if (_users.isEmpty) {
      return const Center(child: Text('אין משתמשים ביחידה'));
    }
    if (_activeQuizCount == 0) {
      return const Center(child: Text('בחר לפחות סוג מבחן אחד'));
    }

    final commanders = _users.where((u) => _isCommanderRole(u.role)).toList();
    final navigators = _users.where((u) => !_isCommanderRole(u.role)).toList();

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (commanders.isNotEmpty) ...[
              Text('מפקדים ומנהלים (${commanders.length})',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              _wrapTableForMobile(_buildDataTable(commanders, isCommanderTable: true)),
              const SizedBox(height: 24),
            ],
            if (navigators.isNotEmpty) ...[
              Text('מנווטים (${navigators.length})',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              _wrapTableForMobile(_buildDataTable(navigators, isCommanderTable: false)),
            ],
          ],
        ),
      ),
    );
  }

  bool get _isMobile =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  Widget _wrapTableForMobile(Widget table) {
    if (!_isMobile) return table;
    return LayoutBuilder(
      builder: (context, constraints) {
        final minWidth = [constraints.maxWidth, 200.0 + _activeQuizCount * 150.0].reduce((a, b) => a > b ? a : b);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: minWidth),
            child: table,
          ),
        );
      },
    );
  }

  bool _isCommanderRole(String role) {
    return role == 'commander' || role == 'unit_admin' || role == 'developer' || role == 'admin';
  }

  Map<int, TableColumnWidth> get _columnWidths {
    final widths = <int, TableColumnWidth>{
      0: const FlexColumnWidth(3),
      1: const FlexColumnWidth(2),
    };
    int col = 2;
    if (_showSoloQuiz) widths[col++] = const FlexColumnWidth(2);
    if (_showRegularQuiz) widths[col++] = const FlexColumnWidth(2);
    if (_showCommanderQuiz) widths[col++] = const FlexColumnWidth(2);
    return widths;
  }

  Widget _buildDataTable(List<User> users, {required bool isCommanderTable}) {
    final headerCells = <Widget>[
      _buildHeaderCell('שם'),
      _buildHeaderCell('תפקיד'),
    ];
    if (_showSoloQuiz) headerCells.add(_buildHeaderCell('מבחן בדד'));
    if (_showRegularQuiz) headerCells.add(_buildHeaderCell('מבחן רגיל'));
    if (_showCommanderQuiz) headerCells.add(_buildHeaderCell('מבחן מפקדים'));

    final rows = <TableRow>[
      TableRow(
        decoration: BoxDecoration(color: Colors.grey[100]),
        children: headerCells,
      ),
    ];

    for (final user in users) {
      final cells = <Widget>[
        _buildTableCell(Text(user.fullName.isNotEmpty ? user.fullName : user.uid)),
        _buildTableCell(Text(_getRoleName(user.role))),
      ];
      if (_showSoloQuiz) {
        cells.add(isCommanderTable
            ? _buildDashCell()
            : _buildStatusCell(user.soloQuizPassedAt, user.soloQuizScore));
      }
      if (_showRegularQuiz) {
        cells.add(isCommanderTable
            ? _buildDashCell()
            : _buildStatusCell(null, null));
      }
      if (_showCommanderQuiz) {
        cells.add(isCommanderTable
            ? _buildStatusCell(user.commanderQuizPassedAt, user.commanderQuizScore)
            : _buildDashCell());
      }
      rows.add(TableRow(children: cells));
    }

    return Table(
      columnWidths: _columnWidths,
      border: TableBorder.all(color: Colors.grey[300]!),
      children: rows,
    );
  }

  Widget _buildHeaderCell(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildTableCell(Widget child) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: child,
    );
  }

  Widget _buildDashCell() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text('-', style: TextStyle(color: Colors.grey, fontSize: 13)),
    );
  }

  Widget _buildStatusCell(DateTime? passedAt, int? score) {
    final status = _getQuizStatus(passedAt, score);
    final color = _getQuizStatusColor(passedAt);
    final icon = _getQuizStatusIcon(passedAt);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(status, style: TextStyle(color: color, fontSize: 13)),
        ],
      ),
    );
  }

  String _getRoleName(String role) {
    switch (role) {
      case 'navigator':
        return 'מנווט';
      case 'commander':
        return 'מפקד';
      case 'unit_admin':
        return 'מנהל יחידה';
      case 'developer':
        return 'מפתח';
      case 'admin':
        return 'מנהל מערכת';
      default:
        return role;
    }
  }

  Future<void> _exportPdf() async {
    final pdf = pw.Document();

    // טעינת פונט בסיסי (ללא תמיכה בעברית מלאה — משתמש בברירת מחדל)
    final font = await PdfGoogleFonts.rubikRegular();
    final fontBold = await PdfGoogleFonts.rubikBold();

    final quizTypes = _activeQuizTypes;
    final headerStyle = pw.TextStyle(font: fontBold, fontSize: 10);
    final cellStyle = pw.TextStyle(font: font, fontSize: 9);
    final titleStyle = pw.TextStyle(font: fontBold, fontSize: 16);

    final commanders = _users.where((u) => _isCommanderRole(u.role)).toList();
    final navigators = _users.where((u) => !_isCommanderRole(u.role)).toList();

    final headers = <String>[];
    if (_showCommanderQuiz) headers.add('מבחן מפקדים');
    if (_showRegularQuiz) headers.add('מבחן רגיל');
    if (_showSoloQuiz) headers.add('מבחן בדד');
    headers.addAll(['תפקיד', 'שם']);

    List<List<String>> buildRows(List<User> users, {required bool isCommanderTable}) {
      return users.map((user) {
        final row = <String>[];
        if (_showCommanderQuiz) {
          row.add(_getQuizStatus(user.commanderQuizPassedAt, user.commanderQuizScore));
        }
        if (_showRegularQuiz) {
          row.add(isCommanderTable ? '-' : _getQuizStatus(null, null));
        }
        if (_showSoloQuiz) {
          row.add(isCommanderTable ? '-' : _getQuizStatus(user.soloQuizPassedAt, user.soloQuizScore));
        }
        row.add(_getRoleName(user.role));
        row.add(user.fullName.isNotEmpty ? user.fullName : user.uid);
        return row;
      }).toList();
    }

    // PDF columns are RTL: quiz cols first, then role, then name
    final pdfColumnWidths = <int, pw.TableColumnWidth>{};
    int pdfCol = 0;
    if (_showCommanderQuiz) pdfColumnWidths[pdfCol++] = const pw.FlexColumnWidth(2);
    if (_showRegularQuiz) pdfColumnWidths[pdfCol++] = const pw.FlexColumnWidth(2);
    if (_showSoloQuiz) pdfColumnWidths[pdfCol++] = const pw.FlexColumnWidth(2);
    pdfColumnWidths[pdfCol++] = const pw.FlexColumnWidth(2); // Role
    pdfColumnWidths[pdfCol] = const pw.FlexColumnWidth(3); // Name

    pw.Widget buildPdfTable(String title, List<List<String>> data) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title, style: pw.TextStyle(font: fontBold, fontSize: 12)),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headers: headers,
            data: data,
            columnWidths: pdfColumnWidths,
            headerStyle: headerStyle,
            cellStyle: cellStyle,
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellAlignment: pw.Alignment.centerRight,
            headerAlignment: pw.Alignment.centerRight,
            border: pw.TableBorder.all(color: PdfColors.grey400),
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          ),
        ],
      );
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        textDirection: pw.TextDirection.rtl,
        build: (context) {
          return [
            pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('דוח מבחנים — $_unitName', style: titleStyle),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'סוגי מבחנים: ${quizTypes.join(", ")} | תאריך: ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
                    style: cellStyle,
                  ),
                  pw.SizedBox(height: 12),
                  if (commanders.isNotEmpty) ...[
                    buildPdfTable('מפקדים ומנהלים (${commanders.length})',
                        buildRows(commanders, isCommanderTable: true)),
                    pw.SizedBox(height: 16),
                  ],
                  if (navigators.isNotEmpty)
                    buildPdfTable('מנווטים (${navigators.length})',
                        buildRows(navigators, isCommanderTable: false)),
                  pw.SizedBox(height: 12),
                  pw.Text('סה"כ: ${_users.length} משתמשים', style: cellStyle),
                ],
              ),
            ),
          ];
        },
      ),
    );

    final pdfBytes = Uint8List.fromList(await pdf.save());
    final fileName = 'דוח_מבחנים_${_unitName}_${DateTime.now().millisecondsSinceEpoch}.pdf';

    final result = await saveFileWithBytes(
      dialogTitle: 'שמור דוח מבחנים',
      fileName: fileName,
      bytes: pdfBytes,
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('הדוח נשמר ב-\n$result'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
}
