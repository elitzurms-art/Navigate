import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import '../../../core/utils/file_export_helper.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../domain/entities/navigation.dart' as domain;
import '../../../domain/entities/checkpoint.dart';
import '../../../domain/entities/boundary.dart';
import '../../../domain/entities/safety_point.dart';
import '../../../domain/entities/cluster.dart';
import '../../../data/repositories/checkpoint_repository.dart';
import '../../../data/repositories/boundary_repository.dart';
import '../../../data/repositories/safety_point_repository.dart';
import '../../../data/repositories/cluster_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../core/utils/geometry_utils.dart';
import '../../widgets/map_with_selector.dart';
import '../../widgets/map_controls.dart';
import '../../widgets/fullscreen_map_screen.dart';

/// ייצוא נתונים
class DataExportScreen extends StatefulWidget {
  final domain.Navigation navigation;
  final bool afterLearning;

  const DataExportScreen({
    super.key,
    required this.navigation,
    this.afterLearning = false,
  });

  @override
  State<DataExportScreen> createState() => _DataExportScreenState();
}

class _DataExportScreenState extends State<DataExportScreen> {
  final CheckpointRepository _checkpointRepo = CheckpointRepository();
  final BoundaryRepository _boundaryRepo = BoundaryRepository();
  final SafetyPointRepository _safetyPointRepo = SafetyPointRepository();
  final ClusterRepository _clusterRepo = ClusterRepository();
  final UserRepository _userRepo = UserRepository();

  List<Checkpoint> _checkpoints = [];
  List<SafetyPoint> _safetyPoints = [];
  List<Boundary> _boundaries = [];
  List<Cluster> _clusters = [];
  Boundary? _boundary;
  Map<String, String> _userNames = {};
  bool _isLoading = false;

  String _navigatorName(String uid) => _userNames[uid] ?? uid;

  String _formatUtm(Checkpoint cp) {
    if (cp.coordinates == null) return '';
    final raw = cp.coordinates!.utm.isNotEmpty
        ? cp.coordinates!.utm
        : UTMConverter.convertToUTM(cp.coordinates!.lat, cp.coordinates!.lng);
    // Stored UTM is 12-digit "EEEEEENNNNNN" — format with space
    if (RegExp(r'^\d{12}$').hasMatch(raw)) {
      return '${raw.substring(0, 6)} ${raw.substring(6)}';
    }
    // Calculated UTM is "36R EEEEEE NNNNNN" — strip zone prefix
    final parts = raw.split(' ');
    if (parts.length == 3) return '${parts[1]} ${parts[2]}';
    return raw;
  }

  Future<String?> _showFormatPicker() async {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('בחר פורמט'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.table_chart, color: Colors.green),
            title: const Text('CSV'),
            subtitle: const Text('טבלת נתונים לפתיחה ב-Excel'),
            onTap: () => Navigator.pop(ctx, 'csv'),
          ),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
            title: const Text('PDF'),
            subtitle: const Text('מסמך PDF מעוצב'),
            onTap: () => Navigator.pop(ctx, 'pdf'),
          ),
        ]),
      ),
    );
  }

  // הגדרות ייצוא מפה - כל שכבה עם בהירות משלה
  bool _showNZ = true;
  double _nzOpacity = 1.0;

  bool _showNB = true;
  double _nbOpacity = 0.8;

  bool _showGG = true;
  double _ggOpacity = 0.5;

  bool _showBA = false;
  double _baOpacity = 0.7;

  // סינון נקודות ציון
  bool _showDistributedOnly = true;

  Set<String> get _distributedCheckpointIds {
    final ids = <String>{};
    for (final route in widget.navigation.routes.values) {
      ids.addAll(route.checkpointIds);
      if (route.startPointId != null) ids.add(route.startPointId!);
      if (route.endPointId != null) ids.add(route.endPointId!);
    }
    return ids;
  }

  List<Checkpoint> get _filteredCheckpoints {
    var cps = _checkpoints.where((cp) => !cp.isPolygon && cp.coordinates != null).toList();
    if (_boundary != null && _boundary!.coordinates.isNotEmpty) {
      cps = GeometryUtils.filterPointsInPolygon(
        points: cps,
        getCoordinate: (cp) => cp.coordinates!,
        polygon: _boundary!.coordinates,
      );
    }
    if (_showDistributedOnly) {
      final ids = _distributedCheckpointIds;
      cps = cps.where((cp) => ids.contains(cp.id)).toList();
    }
    return cps;
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // Load all layer data in parallel
      final results = await Future.wait([
        _checkpointRepo.getByArea(widget.navigation.areaId),
        _safetyPointRepo.getByArea(widget.navigation.areaId),
        _boundaryRepo.getByArea(widget.navigation.areaId),
        _clusterRepo.getByArea(widget.navigation.areaId),
      ]);

      Boundary? boundary;
      if (widget.navigation.boundaryLayerId != null) {
        boundary = await _boundaryRepo.getById(widget.navigation.boundaryLayerId!);
      }

      // טעינת שמות משתמשים למיפוי uid → שם מלא
      final users = await _userRepo.getAll();
      final names = <String, String>{};
      for (final u in users) {
        names[u.uid] = u.fullName;
      }

      setState(() {
        _checkpoints = results[0] as List<Checkpoint>;
        _safetyPoints = results[1] as List<SafetyPoint>;
        _boundaries = results[2] as List<Boundary>;
        _clusters = results[3] as List<Cluster>;
        _boundary = boundary;
        _userNames = names;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה בטעינה: $e')),
        );
      }
    }
  }

  Future<void> _exportRoutesTable() async {
    final format = await _showFormatPicker();
    if (format == null) return;

    if (format == 'pdf') {
      await _exportRoutesTablePdf();
      return;
    }

    try {
      List<List<dynamic>> rows = [];

      List<dynamic> header = ['שם מנווט'];
      int maxCheckpoints = 0;

      for (final route in widget.navigation.routes.values) {
        if (route.sequence.length > maxCheckpoints) {
          maxCheckpoints = route.sequence.length;
        }
      }

      // 3 columns per checkpoint: name, description, UTM
      for (int i = 1; i <= maxCheckpoints; i++) {
        header.add('נ.צ $i');
        header.add('תיאור $i');
        header.add('UTM $i');
      }
      header.add('אורך ציר (ק"מ)');
      if (widget.navigation.timeCalculationSettings.enabled) {
        header.add('זמן ניווט');
      }
      rows.add(widget.afterLearning ? header : header.reversed.toList());

      for (final entry in widget.navigation.routes.entries) {
        final navigatorId = entry.key;
        final route = entry.value;

        List<dynamic> row = [_navigatorName(navigatorId)];

        for (final checkpointId in route.sequence) {
          final checkpoint = _checkpoints.firstWhere(
            (cp) => cp.id == checkpointId,
            orElse: () => _checkpoints.first,
          );

          row.add('${checkpoint.name} (${checkpoint.sequenceNumber})');
          row.add(checkpoint.description);
          row.add(_formatUtm(checkpoint));
        }

        // Pad empty cells: 3 cols per missing checkpoint + 1 for name
        while (row.length < (maxCheckpoints * 3) + 1) {
          row.add('');
        }

        row.add(route.routeLengthKm.toStringAsFixed(2));
        if (widget.navigation.timeCalculationSettings.enabled) {
          final totalMinutes = GeometryUtils.calculateNavigationTimeMinutes(
            routeLengthKm: route.routeLengthKm,
            settings: widget.navigation.timeCalculationSettings,
          );
          row.add(GeometryUtils.formatNavigationTime(totalMinutes));
        }
        rows.add(widget.afterLearning ? row : row.reversed.toList());
      }

      final csv = const ListToCsvConverter().convert(rows);
      final utf8Bom = '\uFEFF';
      final csvWithBom = utf8Bom + csv;

      final fileName = 'טבלת_צירים_${widget.navigation.name}_${DateTime.now().millisecondsSinceEpoch}.csv';
      final fileBytes = Uint8List.fromList(utf8.encode(csvWithBom));
      final result = await saveFileWithBytes(
        dialogTitle: 'שמור טבלת צירים',
        fileName: fileName,
        bytes: fileBytes,
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('טבלת הצירים נשמרה ב-\n$result'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה בייצוא: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _exportRoutesTablePdf() async {
    try {
      final regularFont = await PdfGoogleFonts.rubikRegular();
      final boldFont = await PdfGoogleFonts.rubikBold();

      int maxCheckpoints = 0;
      for (final route in widget.navigation.routes.values) {
        if (route.sequence.length > maxCheckpoints) {
          maxCheckpoints = route.sequence.length;
        }
      }

      final pdf = pw.Document(
        theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont),
      );

      // Build header row
      final headerCells = <pw.Widget>[_pdfCell('שם מנווט', bold: true, fontSize: 7)];
      for (int i = 1; i <= maxCheckpoints; i++) {
        headerCells.add(_pdfCell('נ.צ $i', bold: true, fontSize: 7));
        headerCells.add(_pdfCell('תיאור $i', bold: true, fontSize: 7));
        headerCells.add(_pdfCell('UTM $i', bold: true, fontSize: 7));
      }
      headerCells.add(_pdfCell('אורך (ק"מ)', bold: true, fontSize: 7));
      if (widget.navigation.timeCalculationSettings.enabled) {
        headerCells.add(_pdfCell('זמן ניווט', bold: true, fontSize: 7));
      }

      // Build column widths
      final colWidths = <int, pw.TableColumnWidth>{
        0: const pw.FlexColumnWidth(0.8),
      };
      for (int i = 0; i < maxCheckpoints; i++) {
        colWidths[1 + i * 3] = const pw.FlexColumnWidth(1.5);
        colWidths[2 + i * 3] = const pw.FlexColumnWidth(1.2);
        colWidths[3 + i * 3] = const pw.FlexColumnWidth(1.2);
      }
      colWidths[1 + maxCheckpoints * 3] = const pw.FlexColumnWidth(1.5);
      if (widget.navigation.timeCalculationSettings.enabled) {
        colWidths[2 + maxCheckpoints * 3] = const pw.FlexColumnWidth(1.2);
      }

      // Build data rows
      final dataRows = <pw.TableRow>[];
      for (final entry in widget.navigation.routes.entries) {
        final navigatorId = entry.key;
        final route = entry.value;
        final cells = <pw.Widget>[_pdfCell(_navigatorName(navigatorId), fontSize: 7)];

        for (final checkpointId in route.sequence) {
          final checkpoint = _checkpoints.firstWhere(
            (cp) => cp.id == checkpointId,
            orElse: () => _checkpoints.first,
          );
          cells.add(_pdfCell('${checkpoint.name} (${checkpoint.sequenceNumber})', fontSize: 7));
          cells.add(_pdfCell(checkpoint.description, fontSize: 7));
          cells.add(_pdfCell(_formatUtm(checkpoint), fontSize: 7));
        }

        // Pad empty cells
        while (cells.length < (maxCheckpoints * 3) + 1) {
          cells.add(_pdfCell('', fontSize: 7));
        }
        cells.add(_pdfCell(route.routeLengthKm.toStringAsFixed(2), fontSize: 7));
        if (widget.navigation.timeCalculationSettings.enabled) {
          final totalMinutes = GeometryUtils.calculateNavigationTimeMinutes(
            routeLengthKm: route.routeLengthKm,
            settings: widget.navigation.timeCalculationSettings,
          );
          cells.add(_pdfCell(GeometryUtils.formatNavigationTime(totalMinutes), fontSize: 7));
        }
        dataRows.add(pw.TableRow(children: cells.reversed.toList()));
      }

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          textDirection: pw.TextDirection.rtl,
          margin: const pw.EdgeInsets.all(16),
          header: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                '${widget.navigation.name} — טבלת צירים',
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 6),
            ],
          ),
          build: (context) => [
            pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey400),
                columnWidths: colWidths,
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: headerCells.reversed.toList(),
                  ),
                  ...dataRows,
                ],
              ),
            ),
          ],
        ),
      );

      final pdfBytes = Uint8List.fromList(await pdf.save());
      final fileName = 'טבלת_צירים_${widget.navigation.name}_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final result = await saveFileWithBytes(
        dialogTitle: 'שמור טבלת צירים',
        fileName: fileName,
        bytes: pdfBytes,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('טבלת הצירים נשמרה ב-\n$result'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה בייצוא: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _exportCheckpointsLayer() async {
    final format = await _showFormatPicker();
    if (format == null) return;

    if (format == 'pdf') {
      await _exportCheckpointsLayerPdf();
      return;
    }

    try {
      List<Checkpoint> checkpointsToExport = _filteredCheckpoints;

      List<List<dynamic>> rows = [];

      rows.add([
        'UTM',
        'צבע',
        'סוג',
        'תיאור',
        'שם',
        'מספר סידורי',
      ]);

      for (final cp in checkpointsToExport) {
        rows.add([
          _formatUtm(cp),
          cp.color,
          cp.type,
          cp.description,
          cp.name,
          cp.sequenceNumber,
        ]);
      }

      final csv = const ListToCsvConverter().convert(rows);
      final utf8Bom = '\uFEFF';
      final csvWithBom = utf8Bom + csv;

      final fileName = 'נקודות_ציון_${widget.navigation.name}_${DateTime.now().millisecondsSinceEpoch}.csv';
      final fileBytes = Uint8List.fromList(utf8.encode(csvWithBom));
      final result = await saveFileWithBytes(
        dialogTitle: 'שמור שכבת נ.צ.',
        fileName: fileName,
        bytes: fileBytes,
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('שכבת נ.צ. נשמרה (${checkpointsToExport.length} נקודות)\n$result'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בייצוא: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _exportCheckpointsLayerPdf() async {
    try {
      final checkpointsToExport = _filteredCheckpoints;
      final regularFont = await PdfGoogleFonts.rubikRegular();
      final boldFont = await PdfGoogleFonts.rubikBold();

      final pdf = pw.Document(
        theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont),
      );

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          textDirection: pw.TextDirection.rtl,
          margin: const pw.EdgeInsets.all(20),
          header: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                '${widget.navigation.name} — שכבת נ.צ. (${checkpointsToExport.length})',
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 8),
            ],
          ),
          build: (context) => [
            pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey400),
                columnWidths: {
                  0: const pw.FlexColumnWidth(2),
                  1: const pw.FlexColumnWidth(1),
                  2: const pw.FlexColumnWidth(1.2),
                  3: const pw.FlexColumnWidth(2),
                  4: const pw.FlexColumnWidth(2),
                  5: const pw.FixedColumnWidth(35),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      _pdfCell('UTM', bold: true),
                      _pdfCell('צבע', bold: true),
                      _pdfCell('סוג', bold: true),
                      _pdfCell('תיאור', bold: true),
                      _pdfCell('שם', bold: true),
                      _pdfCell('#', bold: true),
                    ],
                  ),
                  ...checkpointsToExport.map((cp) => pw.TableRow(
                    children: [
                      _pdfCell(_formatUtm(cp)),
                      _pdfCell(cp.color),
                      _pdfCell(cp.type),
                      _pdfCell(cp.description),
                      _pdfCell(cp.name),
                      _pdfCell('${cp.sequenceNumber}'),
                    ],
                  )),
                ],
              ),
            ),
          ],
        ),
      );

      final pdfBytes = Uint8List.fromList(await pdf.save());
      final fileName = 'נקודות_ציון_${widget.navigation.name}_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final result = await saveFileWithBytes(
        dialogTitle: 'שמור שכבת נ.צ.',
        fileName: fileName,
        bytes: pdfBytes,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שכבת נ.צ. נשמרה (${checkpointsToExport.length} נקודות)\n$result'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה בייצוא: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  pw.Widget _pdfCell(String text, {bool bold = false, double fontSize = 9}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: fontSize,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  Future<void> _exportMap() async {
    // בחירת פורמט
    final format = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('בחר פורמט ייצוא'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
              title: const Text('PDF'),
              subtitle: const Text('מסמך PDF איכותי'),
              onTap: () => Navigator.pop(context, 'pdf'),
            ),
            ListTile(
              leading: const Icon(Icons.image, color: Colors.blue),
              title: const Text('JPG'),
              subtitle: const Text('תמונה JPG (בפיתוח)'),
              onTap: () => Navigator.pop(context, 'jpg'),
            ),
          ],
        ),
      ),
    );

    if (format == null) return;

    try {
      if (format == 'pdf') {
        await _exportMapToPdf();
      } else {
        // JPG - בפיתוח
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('ייצוא ל-JPG בפיתוח'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _exportMapToPdf() async {
    if (_checkpoints.isEmpty && _boundaries.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('אין נתונים להצגה במפה'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _MapPreviewScreen(
          navigation: widget.navigation,
          checkpoints: _checkpoints,
          safetyPoints: _safetyPoints,
          boundaries: _boundaries,
          clusters: _clusters,
          boundary: _boundary,
          initialShowNZ: _showNZ,
          initialNzOpacity: _nzOpacity,
          initialShowNB: _showNB,
          initialNbOpacity: _nbOpacity,
          initialShowGG: _showGG,
          initialGgOpacity: _ggOpacity,
          initialShowBA: _showBA,
          initialBaOpacity: _baOpacity,
          initialShowDistributedOnly: _showDistributedOnly,
          afterLearning: widget.afterLearning,
          userNames: _userNames,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.afterLearning ? 'ייצוא צירים' : 'ייצוא נתונים'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'ייצוא נתונים',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'ניווט: ${widget.navigation.name}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.grey[600],
                        ),
                  ),
                  const SizedBox(height: 32),

                  // 1. טבלת צירים
                  _buildExportCard(
                    title: 'טבלת צירים',
                    description: 'ייצא טבלת צירים עם שמות מנווטים, נקודות ציון ואורכי צירים',
                    icon: Icons.table_chart,
                    color: Colors.blue,
                    onTap: _exportRoutesTable,
                  ),

                  const SizedBox(height: 16),

                  // 2. שכבת נ.צ.
                  _buildExportCard(
                    title: 'שכבת נ.צ.',
                    description: 'ייצא את כל נקודות הציון בג.ג כולל מסד ותיאור',
                    icon: Icons.place,
                    color: Colors.green,
                    onTap: _exportCheckpointsLayer,
                  ),

                  const SizedBox(height: 16),

                  // 3. מפה
                  _buildMapExportCard(),

                  const SizedBox(height: 32),

                  // כפתור חזרה לתפריט
                  SizedBox(
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back, size: 28),
                      label: const Text(
                        'חזרה לתפריט',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildExportCard({
    required String title,
    required String description,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 32, color: color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMapExportCard() {
    return _buildExportCard(
      title: 'ייצא מפה',
      description: 'ייצא מפה עם שכבות (נ.צ, ג.ג, נ.ב, ב.א) לקובץ PDF',
      icon: Icons.map,
      color: Colors.orange,
      onTap: _exportMap,
    );
  }

}

/// Get color based on safety point severity — always red
Color _getSeverityColor(String severity) {
  return Colors.red;
}

/// Full-screen interactive map preview for PDF export.
/// The user can pan/zoom the map, toggle layers and opacity,
/// then export when ready.
class _MapPreviewScreen extends StatefulWidget {
  final domain.Navigation navigation;
  final List<Checkpoint> checkpoints;
  final List<SafetyPoint> safetyPoints;
  final List<Boundary> boundaries;
  final List<Cluster> clusters;
  final Boundary? boundary;
  final bool initialShowNZ;
  final double initialNzOpacity;
  final bool initialShowNB;
  final double initialNbOpacity;
  final bool initialShowGG;
  final double initialGgOpacity;
  final bool initialShowBA;
  final double initialBaOpacity;
  final bool initialShowDistributedOnly;
  final bool afterLearning;
  final Map<String, String> userNames;

  const _MapPreviewScreen({
    required this.navigation,
    required this.checkpoints,
    required this.safetyPoints,
    required this.boundaries,
    required this.clusters,
    required this.initialShowNZ,
    required this.initialNzOpacity,
    required this.initialShowNB,
    required this.initialNbOpacity,
    required this.initialShowGG,
    required this.initialGgOpacity,
    required this.initialShowBA,
    required this.initialBaOpacity,
    required this.initialShowDistributedOnly,
    this.boundary,
    this.afterLearning = false,
    this.userNames = const {},
  });

  @override
  State<_MapPreviewScreen> createState() => _MapPreviewScreenState();
}

class _MapPreviewScreenState extends State<_MapPreviewScreen> {
  final GlobalKey _mapRepaintBoundaryKey = GlobalKey();
  final MapController _mapController = MapController();

  late bool _showNZ;
  late double _nzOpacity;
  late bool _showNB;
  late double _nbOpacity;
  late bool _showGG;
  late double _ggOpacity;
  late bool _showBA;
  late double _baOpacity;
  late bool _showDistributedOnly;

  bool _isExporting = false;

  bool _measureMode = false;
  final List<LatLng> _measurePoints = [];

  String _formatUtm(Checkpoint cp) {
    if (cp.coordinates == null) return '';
    final raw = cp.coordinates!.utm.isNotEmpty
        ? cp.coordinates!.utm
        : UTMConverter.convertToUTM(cp.coordinates!.lat, cp.coordinates!.lng);
    if (RegExp(r'^\d{12}$').hasMatch(raw)) {
      return '${raw.substring(0, 6)} ${raw.substring(6)}';
    }
    final parts = raw.split(' ');
    if (parts.length == 3) return '${parts[1]} ${parts[2]}';
    return raw;
  }

  pw.Widget _pdfCell(String text, {bool bold = false, double fontSize = 9}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: fontSize,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  late LatLng _initialCenter;
  late double _initialZoom;

  @override
  void initState() {
    super.initState();
    _showNZ = widget.initialShowNZ;
    _nzOpacity = widget.initialNzOpacity;
    _showNB = widget.initialShowNB;
    _nbOpacity = widget.initialNbOpacity;
    _showGG = widget.initialShowGG;
    _ggOpacity = widget.initialGgOpacity;
    _showBA = widget.initialShowBA;
    _baOpacity = widget.initialBaOpacity;
    _showDistributedOnly = widget.initialShowDistributedOnly;

    final mapParams = _calculateMapCenterAndZoom();
    _initialCenter = mapParams?.center ?? const LatLng(31.5, 34.75);
    _initialZoom = mapParams?.zoom ?? 12.0;
  }

  Set<String> get _distributedCheckpointIds {
    final ids = <String>{};
    for (final route in widget.navigation.routes.values) {
      ids.addAll(route.checkpointIds);
      if (route.startPointId != null) ids.add(route.startPointId!);
      if (route.endPointId != null) ids.add(route.endPointId!);
    }
    return ids;
  }

  List<Checkpoint> get _filteredCheckpoints {
    var cps = widget.checkpoints.where((cp) => !cp.isPolygon && cp.coordinates != null).toList();
    if (widget.boundary != null && widget.boundary!.coordinates.isNotEmpty) {
      cps = GeometryUtils.filterPointsInPolygon(
        points: cps,
        getCoordinate: (cp) => cp.coordinates!,
        polygon: widget.boundary!.coordinates,
      );
    }
    if (_showDistributedOnly) {
      final ids = _distributedCheckpointIds;
      cps = cps.where((cp) => ids.contains(cp.id)).toList();
    }
    return cps;
  }

  ({LatLng center, double zoom})? _calculateMapCenterAndZoom() {
    final List<LatLng> allPoints = [];

    if (_showNZ) {
      for (final cp in _filteredCheckpoints) {
        if (cp.coordinates != null) {
          allPoints.add(LatLng(cp.coordinates!.lat, cp.coordinates!.lng));
        }
      }
    }

    if (_showNB) {
      for (final sp in widget.safetyPoints) {
        if (sp.type == 'point' && sp.coordinates != null) {
          allPoints.add(LatLng(sp.coordinates!.lat, sp.coordinates!.lng));
        }
        if (sp.type == 'polygon' && sp.polygonCoordinates != null) {
          for (final c in sp.polygonCoordinates!) {
            allPoints.add(LatLng(c.lat, c.lng));
          }
        }
      }
    }

    if (_showGG) {
      for (final b in widget.boundaries) {
        for (final c in b.coordinates) {
          allPoints.add(LatLng(c.lat, c.lng));
        }
      }
    }

    if (_showBA) {
      for (final cl in widget.clusters) {
        for (final c in cl.coordinates) {
          allPoints.add(LatLng(c.lat, c.lng));
        }
      }
    }

    // Fallback: use all checkpoints with coordinates
    if (allPoints.isEmpty) {
      for (final cp in widget.checkpoints) {
        if (!cp.isPolygon && cp.coordinates != null) {
          allPoints.add(LatLng(cp.coordinates!.lat, cp.coordinates!.lng));
        }
      }
    }

    if (allPoints.isEmpty) return null;

    double minLat = allPoints.first.latitude;
    double maxLat = allPoints.first.latitude;
    double minLng = allPoints.first.longitude;
    double maxLng = allPoints.first.longitude;

    for (final p in allPoints) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    final latPad = (maxLat - minLat) * 0.1;
    final lngPad = (maxLng - minLng) * 0.1;

    final center = LatLng(
      (minLat + maxLat) / 2,
      (minLng + maxLng) / 2,
    );

    final latSpan = (maxLat - minLat) + 2 * latPad;
    final lngSpan = (maxLng - minLng) + 2 * lngPad;
    final maxSpan = latSpan > lngSpan ? latSpan : lngSpan;

    double zoom = 14.0;
    if (maxSpan > 1.0) {
      zoom = 8.0;
    } else if (maxSpan > 0.5) {
      zoom = 10.0;
    } else if (maxSpan > 0.2) {
      zoom = 11.0;
    } else if (maxSpan > 0.1) {
      zoom = 12.0;
    } else if (maxSpan > 0.05) {
      zoom = 13.0;
    } else if (maxSpan > 0.02) {
      zoom = 14.0;
    } else {
      zoom = 15.0;
    }

    return (center: center, zoom: zoom);
  }

  Widget _buildMap() {
    final checkpointsToShow = _filteredCheckpoints;

    return MapWithTypeSelector(
      mapController: _mapController,
      showTypeSelector: false,
      options: MapOptions(
        initialCenter: _initialCenter,
        initialZoom: _initialZoom,
        onTap: (tapPosition, point) {
          if (_measureMode) {
            setState(() => _measurePoints.add(point));
            return;
          }
        },
      ),
      layers: [
        // NZ layer - checkpoints with role-based colors
        if (_showNZ && checkpointsToShow.isNotEmpty)
          MarkerLayer(
            markers: checkpointsToShow.map((checkpoint) {
              // זיהוי סוג הנקודה: התחלה / סיום / ביניים / מנווט
              final startPointIds = <String>{};
              final endPointIds = <String>{};
              for (final route in widget.navigation.routes.values) {
                if (route.startPointId != null) startPointIds.add(route.startPointId!);
                if (route.endPointId != null) endPointIds.add(route.endPointId!);
              }
              final waypointIds = <String>{};
              if (widget.navigation.waypointSettings.enabled) {
                for (final wp in widget.navigation.waypointSettings.waypoints) {
                  waypointIds.add(wp.checkpointId);
                }
              }

              final Color markerColor;
              final String markerLabel;
              if (startPointIds.contains(checkpoint.id)) {
                markerColor = Colors.green;
                markerLabel = 'H';
              } else if (endPointIds.contains(checkpoint.id)) {
                markerColor = Colors.red;
                markerLabel = 'S';
              } else if (waypointIds.contains(checkpoint.id)) {
                markerColor = Colors.amber;
                markerLabel = 'B';
              } else {
                markerColor = Colors.blue;
                markerLabel = '${checkpoint.sequenceNumber}';
              }

              return Marker(
                point: LatLng(
                  checkpoint.coordinates!.lat,
                  checkpoint.coordinates!.lng,
                ),
                width: 36,
                height: 36,
                child: Opacity(
                  opacity: _nzOpacity,
                  child: Container(
                    decoration: BoxDecoration(
                      color: markerColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: Center(
                      child: Text(
                        markerLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

        // NB layer - safety points (markers)
        if (_showNB && widget.safetyPoints.where((p) => p.type == 'point').isNotEmpty)
          MarkerLayer(
            markers: widget.safetyPoints
                .where((p) => p.type == 'point' && p.coordinates != null)
                .map((point) {
              return Marker(
                point: LatLng(
                  point.coordinates!.lat,
                  point.coordinates!.lng,
                ),
                width: 40,
                height: 50,
                child: Opacity(
                  opacity: _nbOpacity,
                  child: Column(
                    children: [
                      Icon(
                        Icons.warning,
                        color: _getSeverityColor(point.severity),
                        size: 32,
                      ),
                      Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${point.sequenceNumber}',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),

        // NB layer - safety points (polygons)
        if (_showNB && widget.safetyPoints.where((p) => p.type == 'polygon').isNotEmpty)
          PolygonLayer(
            polygons: widget.safetyPoints
                .where((p) => p.type == 'polygon' && p.polygonCoordinates != null)
                .map((point) {
              return Polygon(
                points: point.polygonCoordinates!
                    .map((c) => LatLng(c.lat, c.lng))
                    .toList(),
                color: _getSeverityColor(point.severity).withOpacity(_nbOpacity * 0.3),
                borderColor: _getSeverityColor(point.severity).withOpacity(_nbOpacity),
                borderStrokeWidth: 3,
                isFilled: true,
              );
            }).toList(),
          ),

        // GG layer - boundaries
        if (_showGG && widget.boundaries.isNotEmpty)
          PolygonLayer(
            polygons: widget.boundaries.map((boundary) {
              return Polygon(
                points: boundary.coordinates.map((c) => LatLng(c.lat, c.lng)).toList(),
                color: Colors.black.withOpacity(0.1 * _ggOpacity),
                borderColor: Colors.black.withOpacity(_ggOpacity),
                borderStrokeWidth: boundary.strokeWidth,
                isFilled: true,
              );
            }).toList(),
          ),

        // BA layer - clusters
        if (_showBA && widget.clusters.isNotEmpty)
          PolygonLayer(
            polygons: widget.clusters.map((cluster) {
              return Polygon(
                points: cluster.coordinates.map((c) => LatLng(c.lat, c.lng)).toList(),
                color: Colors.green.withOpacity(cluster.fillOpacity * _baOpacity),
                borderColor: Colors.green.withOpacity(_baOpacity),
                borderStrokeWidth: cluster.strokeWidth,
                isFilled: true,
              );
            }).toList(),
          ),
        ...MapControls.buildMeasureLayers(_measurePoints),
        // שכבת צירים מעודכנים (afterLearning)
        if (widget.afterLearning)
          PolylineLayer(
            polylines: widget.navigation.routes.entries
                .where((e) => e.value.plannedPath.isNotEmpty)
                .map((entry) {
              final route = entry.value;
              final color = Colors.primaries[
                  entry.key.hashCode.abs() % Colors.primaries.length];
              return Polyline(
                points: route.plannedPath
                    .map((c) => LatLng(c.lat, c.lng))
                    .toList(),
                strokeWidth: 3.0,
                color: color.withOpacity(0.8),
              );
            }).toList(),
          ),
      ],
    );
  }

  Future<void> _exportToPdf() async {
    setState(() => _isExporting = true);

    // Wait for tiles to load after any recent pan/zoom
    await Future.delayed(const Duration(seconds: 3));

    if (!mounted) return;

    try {
      // Load Hebrew-supporting fonts for PDF
      final regularFont = await PdfGoogleFonts.rubikRegular();
      final boldFont = await PdfGoogleFonts.rubikBold();

      final boundary = _mapRepaintBoundaryKey.currentContext
          ?.findRenderObject() as RenderRepaintBoundary?;

      if (boundary == null) {
        throw Exception('לא ניתן ללכוד את המפה');
      }

      // Capture at 3x pixel ratio for high quality PDF output
      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData == null) {
        throw Exception('שגיאה ביצירת תמונה');
      }

      final Uint8List imageBytes = byteData.buffer.asUint8List();
      final filteredCps = _filteredCheckpoints;

      // Build the PDF with Hebrew font support
      final pdf = pw.Document(
        theme: pw.ThemeData.withFont(
          base: regularFont,
          bold: boldFont,
        ),
      );
      final mapImage = pw.MemoryImage(imageBytes);

      // Page 1: Map image
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          textDirection: pw.TextDirection.rtl,
          margin: const pw.EdgeInsets.all(20),
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                widget.navigation.name,
                style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 8),
              pw.Directionality(
                textDirection: pw.TextDirection.ltr,
                child: pw.Row(
                  children: [
                    if (_showNZ) pw.Text('NZ ', style: pw.TextStyle(font: regularFont, fontSize: 9, color: PdfColors.blue)),
                    if (_showNB) pw.Text('NB ', style: pw.TextStyle(font: regularFont, fontSize: 9, color: PdfColors.red)),
                    if (_showGG) pw.Text('GG ', style: pw.TextStyle(font: regularFont, fontSize: 9, color: PdfColors.black)),
                    if (_showBA) pw.Text('BA ', style: pw.TextStyle(font: regularFont, fontSize: 9, color: PdfColors.green)),
                    pw.Text(
                      '  |  ${widget.navigation.createdAt.toString().split(' ')[0]}',
                      style: pw.TextStyle(font: regularFont, fontSize: 9, color: PdfColors.grey700),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 10),
              pw.Expanded(
                child: pw.Center(
                  child: pw.Image(mapImage, fit: pw.BoxFit.contain),
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                'Navigate App',
                style: pw.TextStyle(font: regularFont, fontSize: 7, color: PdfColors.grey),
              ),
            ],
          ),
        ),
      );

      // Page 2+: Routes pivot table OR simple checkpoint list
      if (_showNZ && filteredCps.isNotEmpty) {
        if (widget.navigation.routes.isNotEmpty) {
          // Pivot table: routes × checkpoints
          int maxCheckpoints = 0;
          for (final route in widget.navigation.routes.values) {
            if (route.sequence.length > maxCheckpoints) {
              maxCheckpoints = route.sequence.length;
            }
          }

          final timeEnabled = widget.navigation.timeCalculationSettings.enabled;

          final pivotHeaderCells = <pw.Widget>[_pdfCell('שם מנווט', bold: true, fontSize: 7)];
          for (int i = 1; i <= maxCheckpoints; i++) {
            pivotHeaderCells.add(_pdfCell('נ.צ $i', bold: true, fontSize: 7));
            pivotHeaderCells.add(_pdfCell('תיאור $i', bold: true, fontSize: 7));
            pivotHeaderCells.add(_pdfCell('UTM $i', bold: true, fontSize: 7));
          }
          pivotHeaderCells.add(_pdfCell('אורך (ק"מ)', bold: true, fontSize: 7));
          if (timeEnabled) {
            pivotHeaderCells.add(_pdfCell('זמן ניווט', bold: true, fontSize: 7));
          }

          final pivotColWidths = <int, pw.TableColumnWidth>{
            0: const pw.FlexColumnWidth(0.8),
          };
          for (int i = 0; i < maxCheckpoints; i++) {
            pivotColWidths[1 + i * 3] = const pw.FlexColumnWidth(1.5);
            pivotColWidths[2 + i * 3] = const pw.FlexColumnWidth(1.2);
            pivotColWidths[3 + i * 3] = const pw.FlexColumnWidth(1.2);
          }
          pivotColWidths[1 + maxCheckpoints * 3] = const pw.FlexColumnWidth(1.5);
          if (timeEnabled) {
            pivotColWidths[2 + maxCheckpoints * 3] = const pw.FlexColumnWidth(1.2);
          }

          // שמות מנווטים — טעינה מ-_userNames דרך ה-parent
          final userNames = widget.userNames;

          final pivotDataRows = <pw.TableRow>[];
          for (final entry in widget.navigation.routes.entries) {
            final navigatorId = entry.key;
            final route = entry.value;
            final navigatorName = userNames[navigatorId] ?? navigatorId;
            final cells = <pw.Widget>[_pdfCell(navigatorName, fontSize: 7)];

            for (final checkpointId in route.sequence) {
              final checkpoint = widget.checkpoints.firstWhere(
                (cp) => cp.id == checkpointId,
                orElse: () => widget.checkpoints.first,
              );
              cells.add(_pdfCell('${checkpoint.name} (${checkpoint.sequenceNumber})', fontSize: 7));
              cells.add(_pdfCell(checkpoint.description, fontSize: 7));
              cells.add(_pdfCell(_formatUtm(checkpoint), fontSize: 7));
            }

            while (cells.length < (maxCheckpoints * 3) + 1) {
              cells.add(_pdfCell('', fontSize: 7));
            }
            cells.add(_pdfCell(route.routeLengthKm.toStringAsFixed(2), fontSize: 7));
            if (timeEnabled) {
              final totalMinutes = GeometryUtils.calculateNavigationTimeMinutes(
                routeLengthKm: route.routeLengthKm,
                settings: widget.navigation.timeCalculationSettings,
              );
              cells.add(_pdfCell(GeometryUtils.formatNavigationTime(totalMinutes), fontSize: 7));
            }
            pivotDataRows.add(pw.TableRow(children: cells.reversed.toList()));
          }

          pdf.addPage(
            pw.MultiPage(
              pageFormat: PdfPageFormat.a4.landscape,
              textDirection: pw.TextDirection.rtl,
              margin: const pw.EdgeInsets.all(16),
              header: (context) => pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    '${widget.navigation.name} — טבלת צירים',
                    style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.SizedBox(height: 6),
                ],
              ),
              build: (context) => [
                pw.Directionality(
                  textDirection: pw.TextDirection.rtl,
                  child: pw.Table(
                    border: pw.TableBorder.all(color: PdfColors.grey400),
                    columnWidths: pivotColWidths,
                    children: [
                      pw.TableRow(
                        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                        children: pivotHeaderCells.reversed.toList(),
                      ),
                      ...pivotDataRows,
                    ],
                  ),
                ),
              ],
            ),
          );
        } else {
          // Fallback: simple checkpoint list when no routes
          pdf.addPage(
            pw.MultiPage(
              pageFormat: PdfPageFormat.a4,
              textDirection: pw.TextDirection.rtl,
              margin: const pw.EdgeInsets.all(20),
              header: (context) => pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    '${widget.navigation.name} — נ.צ (${filteredCps.length})',
                    style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.SizedBox(height: 12),
                ],
              ),
              build: (context) => [
                pw.Directionality(
                  textDirection: pw.TextDirection.rtl,
                  child: pw.Table(
                    border: pw.TableBorder.all(color: PdfColors.grey400),
                    columnWidths: {
                      0: const pw.FixedColumnWidth(40),
                      1: const pw.FlexColumnWidth(2),
                      2: const pw.FlexColumnWidth(3),
                    },
                    children: [
                      pw.TableRow(
                        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                        children: [
                          _pdfCell('#', bold: true, fontSize: 10),
                          _pdfCell('שם', bold: true, fontSize: 10),
                          _pdfCell('UTM', bold: true, fontSize: 10),
                        ],
                      ),
                      ...filteredCps.map((cp) {
                        return pw.TableRow(
                          children: [
                            _pdfCell('${cp.sequenceNumber}'),
                            _pdfCell(cp.name),
                            _pdfCell(_formatUtm(cp)),
                          ],
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ),
          );
        }
      }

      // Save
      final pdfBytes = Uint8List.fromList(await pdf.save());
      final fileName = 'map_${widget.navigation.name}_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final result = await saveFileWithBytes(
        dialogTitle: 'שמור מפה',
        fileName: fileName,
        bytes: pdfBytes,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('המפה נשמרה ב-PDF\n$result'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
          Navigator.pop(context);
        }
      } else {
        if (mounted) {
          setState(() => _isExporting = false);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isExporting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בייצוא PDF: $e'),
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
        title: const Text('תצוגה מקדימה'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          // Map fills the screen
          RepaintBoundary(
            key: _mapRepaintBoundaryKey,
            child: _buildMap(),
          ),

          // בקרי מפה
          MapControls(
            mapController: _mapController,
            measureMode: _measureMode,
            onMeasureModeChanged: (v) => setState(() {
              _measureMode = v;
              if (!v) _measurePoints.clear();
            }),
            measurePoints: _measurePoints,
            onMeasureClear: () => setState(() => _measurePoints.clear()),
            onMeasureUndo: () => setState(() {
              if (_measurePoints.isNotEmpty) _measurePoints.removeLast();
            }),
            layers: [
              MapLayerConfig(
                id: 'nz', label: 'נ.צ', color: Colors.blue,
                visible: _showNZ, opacity: _nzOpacity,
                onVisibilityChanged: (v) => setState(() => _showNZ = v),
                onOpacityChanged: (v) => setState(() => _nzOpacity = v),
              ),
              MapLayerConfig(
                id: 'nb', label: 'נ.ב', color: Colors.red,
                visible: _showNB, opacity: _nbOpacity,
                onVisibilityChanged: (v) => setState(() => _showNB = v),
                onOpacityChanged: (v) => setState(() => _nbOpacity = v),
              ),
              MapLayerConfig(
                id: 'gg', label: 'ג.ג', color: Colors.black,
                visible: _showGG, opacity: _ggOpacity,
                onVisibilityChanged: (v) => setState(() => _showGG = v),
                onOpacityChanged: (v) => setState(() => _ggOpacity = v),
              ),
              MapLayerConfig(
                id: 'ba', label: 'ב.א', color: Colors.green,
                visible: _showBA, opacity: _baOpacity,
                onVisibilityChanged: (v) => setState(() => _showBA = v),
                onOpacityChanged: (v) => setState(() => _baOpacity = v),
              ),
            ],
            onFullscreen: () {
              final camera = _mapController.camera;
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => FullscreenMapScreen(
                  title: 'ייצוא נתונים',
                  initialCenter: camera.center,
                  initialZoom: camera.zoom,
                  layerConfigs: [
                    MapLayerConfig(id: 'nz', label: 'נ.צ', color: Colors.blue, visible: _showNZ, opacity: _nzOpacity, onVisibilityChanged: (_) {}, onOpacityChanged: (_) {}),
                    MapLayerConfig(id: 'nb', label: 'נ.ב', color: Colors.red, visible: _showNB, opacity: _nbOpacity, onVisibilityChanged: (_) {}, onOpacityChanged: (_) {}),
                    MapLayerConfig(id: 'gg', label: 'ג.ג', color: Colors.black, visible: _showGG, opacity: _ggOpacity, onVisibilityChanged: (_) {}, onOpacityChanged: (_) {}),
                    MapLayerConfig(id: 'ba', label: 'ב.א', color: Colors.green, visible: _showBA, opacity: _baOpacity, onVisibilityChanged: (_) {}, onOpacityChanged: (_) {}),
                  ],
                  layerBuilder: (visibility, opacity) => [
                    if (visibility['gg'] == true && widget.boundary != null && widget.boundary!.coordinates.isNotEmpty)
                      PolygonLayer(
                        polygons: [
                          Polygon(
                            points: widget.boundary!.coordinates
                                .map((coord) => LatLng(coord.lat, coord.lng))
                                .toList(),
                            color: Colors.black.withValues(alpha: 0.1 * (opacity['gg'] ?? 1.0)),
                            borderColor: Colors.black.withValues(alpha: (opacity['gg'] ?? 1.0)),
                            borderStrokeWidth: widget.boundary!.strokeWidth,
                            isFilled: true,
                          ),
                        ],
                      ),
                    if (visibility['nz'] == true && _filteredCheckpoints.isNotEmpty)
                      MarkerLayer(
                        markers: _filteredCheckpoints.map((checkpoint) {
                          return Marker(
                            point: LatLng(checkpoint.coordinates!.lat, checkpoint.coordinates!.lng),
                            width: 36,
                            height: 36,
                            child: Opacity(
                              opacity: (opacity['nz'] ?? 1.0),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.blue,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                ),
                                child: Center(
                                  child: Text(
                                    '${checkpoint.sequenceNumber}',
                                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    if (visibility['nb'] == true && widget.safetyPoints.where((p) => p.type == 'point' && p.coordinates != null).isNotEmpty)
                      MarkerLayer(
                        markers: widget.safetyPoints
                            .where((p) => p.type == 'point' && p.coordinates != null)
                            .map((point) => Marker(
                                  point: LatLng(point.coordinates!.lat, point.coordinates!.lng),
                                  width: 30,
                                  height: 30,
                                  child: Opacity(
                                    opacity: (opacity['nb'] ?? 1.0),
                                    child: Icon(Icons.warning, color: Colors.orange, size: 28),
                                  ),
                                ))
                            .toList(),
                      ),
                  ],
                ),
              ));
            },
          ),

          // Distributed-only toggle chip
          if (widget.navigation.routes.isNotEmpty)
            Positioned(
              bottom: 80,
              left: 16,
              child: Card(
                elevation: 3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => setState(() => _showDistributedOnly = !_showDistributedOnly),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _showDistributedOnly ? Icons.filter_alt : Icons.filter_alt_off,
                          size: 18,
                          color: _showDistributedOnly ? Colors.blue : Colors.grey,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _showDistributedOnly
                              ? 'נ.צ מחולקות (${_filteredCheckpoints.length})'
                              : 'כל הנ.צ (${_filteredCheckpoints.length})',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _showDistributedOnly ? Colors.blue : Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Loading overlay during export
          if (_isExporting)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text(
                      'מייצא PDF...',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: _isExporting
          ? null
          : FloatingActionButton.extended(
              onPressed: _exportToPdf,
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('ייצא PDF'),
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
    );
  }
}
