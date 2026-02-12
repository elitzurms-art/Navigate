import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
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
import '../../../data/repositories/navigation_repository.dart';
import '../../../data/repositories/navigation_tree_repository.dart';
import '../../../domain/entities/navigation_tree.dart';
import '../../../core/utils/geometry_utils.dart';
import '../../widgets/map_with_selector.dart';

/// שלב 5 - ייצוא נתונים
class DataExportScreen extends StatefulWidget {
  final domain.Navigation navigation;

  const DataExportScreen({super.key, required this.navigation});

  @override
  State<DataExportScreen> createState() => _DataExportScreenState();
}

class _DataExportScreenState extends State<DataExportScreen> {
  final CheckpointRepository _checkpointRepo = CheckpointRepository();
  final BoundaryRepository _boundaryRepo = BoundaryRepository();
  final SafetyPointRepository _safetyPointRepo = SafetyPointRepository();
  final ClusterRepository _clusterRepo = ClusterRepository();
  final NavigationRepository _navRepo = NavigationRepository();

  List<Checkpoint> _checkpoints = [];
  List<SafetyPoint> _safetyPoints = [];
  List<Boundary> _boundaries = [];
  List<Cluster> _clusters = [];
  Boundary? _boundary;
  bool _isLoading = false;

  // הגדרות ייצוא מפה - כל שכבה עם בהירות משלה
  bool _showNZ = true;
  double _nzOpacity = 1.0;

  bool _showNB = false;
  double _nbOpacity = 0.8;

  bool _showGG = true;
  double _ggOpacity = 0.5;

  bool _showBA = false;
  double _baOpacity = 0.7;

  // סינון נקודות ציון
  bool _showDistributedOnly = false;

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
    var cps = _checkpoints;
    if (_boundary != null && _boundary!.coordinates.isNotEmpty) {
      cps = GeometryUtils.filterPointsInPolygon(
        points: cps,
        getCoordinate: (cp) => cp.coordinates,
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

      setState(() {
        _checkpoints = results[0] as List<Checkpoint>;
        _safetyPoints = results[1] as List<SafetyPoint>;
        _boundaries = results[2] as List<Boundary>;
        _clusters = results[3] as List<Cluster>;
        _boundary = boundary;
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
    try {
      // טעינת עץ מבנה לקבלת שמות מנווטים
      final treeRepo = NavigationTreeRepository();
      final tree = await treeRepo.getById(widget.navigation.treeId);

      // בניית נתוני הטבלה
      List<List<dynamic>> rows = [];

      // כותרת
      List<dynamic> header = ['שם מנווט'];
      int maxCheckpoints = 0;

      // מציאת המספר המקסימלי של נקודות
      for (final route in widget.navigation.routes.values) {
        if (route.sequence.length > maxCheckpoints) {
          maxCheckpoints = route.sequence.length;
        }
      }

      // הוספת כותרות נקודות + UTM
      for (int i = 1; i <= maxCheckpoints; i++) {
        header.add('נ.צ $i');
        header.add('UTM $i');
      }
      header.add('אורך ציר (ק"מ)');
      rows.add(header);

      // שורות נתונים
      for (final entry in widget.navigation.routes.entries) {
        final navigatorId = entry.key;
        final route = entry.value;

        List<dynamic> row = [navigatorId];

        // נקודות הציון + UTM
        for (final checkpointId in route.sequence) {
          final checkpoint = _checkpoints.firstWhere(
            (cp) => cp.id == checkpointId,
            orElse: () => _checkpoints.first,
          );

          // שם הנקודה
          row.add('${checkpoint.name} (${checkpoint.sequenceNumber})');

          // UTM
          final utm = checkpoint.coordinates.utm.isNotEmpty
              ? checkpoint.coordinates.utm
              : UTMConverter.convertToUTM(checkpoint.coordinates.lat, checkpoint.coordinates.lng);
          row.add(utm);
        }

        // מילוי תאים ריקים אם צריך (שם + UTM לכל נקודה חסרה)
        while (row.length < (maxCheckpoints * 2) + 1) {
          row.add('');
        }

        // אורך ציר
        row.add(route.routeLengthKm.toStringAsFixed(2));

        rows.add(row);
      }

      // המרה ל-CSV
      final csv = const ListToCsvConverter().convert(rows);

      // הוספת BOM של UTF-8 לתמיכה בעברית ב-Excel
      final utf8Bom = '\uFEFF';
      final csvWithBom = utf8Bom + csv;

      // בחירת מיקום שמירה
      final fileName = 'טבלת_צירים_${widget.navigation.name}_${DateTime.now().millisecondsSinceEpoch}.csv';
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'שמור טבלת צירים',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result != null) {
        final file = File(result);
        await file.writeAsString(csvWithBom, encoding: utf8);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('טבלת הצירים נשמרה ב-\n$result'),
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

  Future<void> _exportCheckpointsLayer() async {
    try {
      // סינון נקודות לפי גבול ומסנן חלוקה
      List<Checkpoint> checkpointsToExport = _filteredCheckpoints;

      // בניית טבלה
      List<List<dynamic>> rows = [];

      // כותרת
      rows.add([
        'מספר סידורי',
        'שם',
        'תיאור',
        'סוג',
        'צבע',
        'UTM',
      ]);

      // נתונים - רק UTM (לא lat/lng)
      for (final cp in checkpointsToExport) {
        // חישוב UTM אם ריק
        final utm = cp.coordinates.utm.isNotEmpty
            ? cp.coordinates.utm
            : UTMConverter.convertToUTM(cp.coordinates.lat, cp.coordinates.lng);

        rows.add([
          cp.sequenceNumber,
          cp.name,
          cp.description,
          cp.type,
          cp.color,
          utm,
        ]);
      }

      // המרה ל-CSV עם BOM
      final csv = const ListToCsvConverter().convert(rows);
      final utf8Bom = '\uFEFF';
      final csvWithBom = utf8Bom + csv;

      // שמירה
      final fileName = 'נקודות_ציון_${widget.navigation.name}_${DateTime.now().millisecondsSinceEpoch}.csv';
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'שמור שכבת נ.צ.',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result != null) {
        final file = File(result);
        await file.writeAsString(csvWithBom, encoding: utf8);

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
        ),
      ),
    );
  }

  String _getSelectedLayers() {
    List<String> layers = [];
    if (_showNZ) layers.add('נ.צ');
    if (_showNB) layers.add('נ.ב');
    if (_showGG) layers.add('ג.ג');
    if (_showBA) layers.add('ב.א');
    return layers.join(', ');
  }

  Future<void> _finishPreparation() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('סיום הכנות'),
        content: const Text(
          'האם לסיים את ההכנות ולשנות את הסטטוס ל"מוכן"?\n\n'
          'לאחר מכן תוכל להפעיל מצב "למידה לניווט".'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.green),
            child: const Text('סיים הכנות'),
          ),
        ],
      ),
    );

    if (result == true) {
      setState(() => _isLoading = true);

      final updatedNavigation = widget.navigation.copyWith(
        status: 'ready',
        updatedAt: DateTime.now(),
      );
      await _navRepo.update(updatedNavigation);

      if (mounted) {
        Navigator.popUntil(context, (route) => route.isFirst);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ההכנות הושלמו! הניווט מוכן להפעלה.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ייצוא נתונים'),
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
                    'שלב 5 - ייצוא נתונים',
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

                  // כפתור סיום הכנות
                  SizedBox(
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _finishPreparation,
                      icon: const Icon(Icons.check_circle, size: 28),
                      label: const Text(
                        'סיום הכנות ושמירה',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // הסבר על השלב הבא
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
                                'השלב הבא:',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue[700],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'לאחר סיום ההכנות, הניווט ישונה לסטטוס "מוכן" '
                            'ותוכל להפעיל מצב "למידה לניווט" או לתזמן הפעלה אוטומטית.',
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.map, size: 32, color: Colors.orange),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Text(
                    'מפה עם שכבות',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // שכבות עם בהירות נפרדת
            const Text('שכבות ובהירות:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),

            // סינון נ.צ - רק מחולקות
            if (widget.navigation.routes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SwitchListTile(
                  title: const Text('רק נ.צ מחולקות'),
                  subtitle: Text(
                    _showDistributedOnly
                        ? 'מציג ${_filteredCheckpoints.length} נ.צ (כולל התחלה/סיום)'
                        : 'מציג את כל הנ.צ בג.ג (${_filteredCheckpoints.length})',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  value: _showDistributedOnly,
                  dense: true,
                  onChanged: (v) => setState(() => _showDistributedOnly = v),
                  activeColor: Colors.blue,
                ),
              ),

            // נ.צ - נקודות ציון (כחול - צבע מקורי)
            _buildLayerControl(
              title: 'נ.צ (נקודות ציון)',
              enabled: _showNZ,
              opacity: _nzOpacity,
              onEnabledChanged: (value) => setState(() => _showNZ = value),
              onOpacityChanged: (value) => setState(() => _nzOpacity = value),
              color: const Color(0xFF2196F3), // כחול מקורי
            ),

            const SizedBox(height: 12),

            // נ.ב - נקודות בטיחות (ירוק - צבע מקורי)
            _buildLayerControl(
              title: 'נ.ב (נקודות בטיחות)',
              enabled: _showNB,
              opacity: _nbOpacity,
              onEnabledChanged: (value) => setState(() => _showNB = value),
              onOpacityChanged: (value) => setState(() => _nbOpacity = value),
              color: const Color(0xFF4CAF50), // ירוק מקורי
            ),

            const SizedBox(height: 12),

            // ג.ג - גבולות גזרה (שחור - צבע מקורי)
            _buildLayerControl(
              title: 'ג.ג (גבולות גזרה)',
              enabled: _showGG,
              opacity: _ggOpacity,
              onEnabledChanged: (value) => setState(() => _showGG = value),
              onOpacityChanged: (value) => setState(() => _ggOpacity = value),
              color: const Color(0xFF000000), // שחור מקורי
            ),

            const SizedBox(height: 12),

            // ב.א - ביצי אשכולות (אדום - צבע מקורי)
            _buildLayerControl(
              title: 'ב.א (ביצי אשכולות)',
              enabled: _showBA,
              opacity: _baOpacity,
              onEnabledChanged: (value) => setState(() => _showBA = value),
              onOpacityChanged: (value) => setState(() => _baOpacity = value),
              color: const Color(0xFFF44336), // אדום מקורי
            ),

            const SizedBox(height: 16),

            // כפתור ייצוא
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _exportMap,
                icon: const Icon(Icons.download),
                label: const Text('ייצא מפה'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLayerControl({
    required String title,
    required bool enabled,
    required double opacity,
    required ValueChanged<bool> onEnabledChanged,
    required ValueChanged<double> onOpacityChanged,
    required Color color,
  }) {
    return Card(
      color: enabled ? color.withOpacity(0.05) : Colors.grey[100],
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // שורה עליונה: checkbox + כותרת
            Row(
              children: [
                Checkbox(
                  value: enabled,
                  onChanged: (value) => onEnabledChanged(value ?? false),
                  activeColor: color,
                ),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: enabled ? Colors.black : Colors.grey,
                    ),
                  ),
                ),
                if (enabled)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${(opacity * 100).toInt()}%',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ),
              ],
            ),

            // slider בהירות (רק אם מופעל)
            if (enabled) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const SizedBox(width: 12),
                  Expanded(
                    child: Slider(
                      value: opacity,
                      min: 0.0,
                      max: 1.0,
                      divisions: 10,
                      activeColor: color,
                      onChanged: onOpacityChanged,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Get color based on safety point severity
Color _getSeverityColor(String severity) {
  switch (severity) {
    case 'low':
      return Colors.orange;
    case 'medium':
      return Colors.red;
    case 'high':
      return Colors.red.shade700;
    case 'critical':
      return Colors.red.shade900;
    default:
      return Colors.red;
  }
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
  bool _showLayerPanel = true;

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fitBounds();
    });
  }

  void _fitBounds() {
    final mapParams = _calculateMapCenterAndZoom();
    if (mapParams != null) {
      try {
        _mapController.move(mapParams.center, mapParams.zoom);
      } catch (_) {
        // Map controller might not be ready yet
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            try {
              _mapController.move(mapParams.center, mapParams.zoom);
            } catch (_) {}
          }
        });
      }
    }
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
    var cps = widget.checkpoints;
    if (widget.boundary != null && widget.boundary!.coordinates.isNotEmpty) {
      cps = GeometryUtils.filterPointsInPolygon(
        points: cps,
        getCoordinate: (cp) => cp.coordinates,
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
        allPoints.add(LatLng(cp.coordinates.lat, cp.coordinates.lng));
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

    // Fallback: use all checkpoints
    if (allPoints.isEmpty) {
      for (final cp in widget.checkpoints) {
        allPoints.add(LatLng(cp.coordinates.lat, cp.coordinates.lng));
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
      options: const MapOptions(
        initialCenter: LatLng(31.5, 34.75),
        initialZoom: 12,
      ),
      layers: [
        // NZ layer - checkpoints
        if (_showNZ && checkpointsToShow.isNotEmpty)
          MarkerLayer(
            markers: checkpointsToShow.map((checkpoint) {
              return Marker(
                point: LatLng(
                  checkpoint.coordinates.lat,
                  checkpoint.coordinates.lng,
                ),
                width: 40,
                height: 50,
                child: Opacity(
                  opacity: _nzOpacity,
                  child: Column(
                    children: [
                      Icon(
                        Icons.place,
                        color: checkpoint.color == 'blue'
                            ? Colors.blue
                            : Colors.green,
                        size: 32,
                      ),
                      Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${checkpoint.sequenceNumber}',
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
                color: Colors.transparent,
                borderColor: Colors.black.withOpacity(_ggOpacity),
                borderStrokeWidth: boundary.strokeWidth,
                isFilled: false,
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

      // Page 2: Checkpoints table (if NZ layer is shown)
      if (_showNZ && filteredCps.isNotEmpty) {
        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            textDirection: pw.TextDirection.rtl,
            margin: const pw.EdgeInsets.all(20),
            build: (context) => pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  '${widget.navigation.name} - NZ (${filteredCps.length})',
                  style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 12),
                pw.Directionality(
                  textDirection: pw.TextDirection.ltr,
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
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(4),
                            child: pw.Text('#', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(4),
                            child: pw.Text('שם', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(4),
                            child: pw.Text('UTM', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                          ),
                        ],
                      ),
                      ...filteredCps.take(40).map((cp) {
                        final utm = cp.coordinates.utm.isNotEmpty
                            ? cp.coordinates.utm
                            : UTMConverter.convertToUTM(cp.coordinates.lat, cp.coordinates.lng);
                        return pw.TableRow(
                          children: [
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(4),
                              child: pw.Text('${cp.sequenceNumber}', style: const pw.TextStyle(fontSize: 9)),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(4),
                              child: pw.Text(cp.name, style: const pw.TextStyle(fontSize: 9)),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(4),
                              child: pw.Text(utm, style: const pw.TextStyle(fontSize: 9)),
                            ),
                          ],
                        );
                      }),
                    ],
                  ),
                ),
                if (filteredCps.length > 40)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 8),
                    child: pw.Text(
                      '... +${filteredCps.length - 40}',
                      style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey),
                    ),
                  ),
              ],
            ),
          ),
        );
      }

      // Save
      final fileName = 'map_${widget.navigation.name}_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'שמור מפה',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result != null) {
        final file = File(result);
        await file.writeAsBytes(await pdf.save());

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

  Widget _buildLayerPanel() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('שכבות', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: () => setState(() => _showLayerPanel = false),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        const Divider(),
        // Checkpoint filter toggle
        if (widget.navigation.routes.isNotEmpty) ...[
          SwitchListTile(
            title: const Text('רק נ.צ מחולקות', style: TextStyle(fontSize: 13)),
            subtitle: Text(
              _showDistributedOnly
                  ? '${_filteredCheckpoints.length} נ.צ (כולל התחלה/סיום)'
                  : 'כל הנ.צ בג.ג (${_filteredCheckpoints.length})',
              style: const TextStyle(fontSize: 11),
            ),
            value: _showDistributedOnly,
            dense: true,
            onChanged: (v) => setState(() => _showDistributedOnly = v),
          ),
          const Divider(),
        ],
        // Layer controls
        _buildCompactLayerControl('נ.צ', _showNZ, _nzOpacity, Colors.blue,
          (v) => setState(() => _showNZ = v),
          (v) => setState(() => _nzOpacity = v),
        ),
        _buildCompactLayerControl('נ.ב', _showNB, _nbOpacity, Colors.red,
          (v) => setState(() => _showNB = v),
          (v) => setState(() => _nbOpacity = v),
        ),
        _buildCompactLayerControl('ג.ג', _showGG, _ggOpacity, Colors.black,
          (v) => setState(() => _showGG = v),
          (v) => setState(() => _ggOpacity = v),
        ),
        _buildCompactLayerControl('ב.א', _showBA, _baOpacity, Colors.green,
          (v) => setState(() => _showBA = v),
          (v) => setState(() => _baOpacity = v),
        ),
      ],
    );
  }

  Widget _buildCompactLayerControl(
    String label,
    bool enabled,
    double opacity,
    Color color,
    ValueChanged<bool> onEnabledChanged,
    ValueChanged<double> onOpacityChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              value: enabled,
              onChanged: (v) => onEnabledChanged(v ?? false),
              activeColor: color,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: enabled ? color : Colors.grey,
          )),
          if (enabled) ...[
            Expanded(
              child: Slider(
                value: opacity,
                min: 0.0,
                max: 1.0,
                divisions: 10,
                activeColor: color,
                onChanged: onOpacityChanged,
              ),
            ),
            SizedBox(
              width: 36,
              child: Text(
                '${(opacity * 100).toInt()}%',
                style: TextStyle(fontSize: 11, color: color),
              ),
            ),
          ] else
            const Spacer(),
        ],
      ),
    );
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
        actions: [
          IconButton(
            icon: Icon(_showLayerPanel ? Icons.layers : Icons.layers_outlined),
            onPressed: () => setState(() => _showLayerPanel = !_showLayerPanel),
            tooltip: 'שכבות',
          ),
        ],
      ),
      body: Stack(
        children: [
          // Map fills the screen
          RepaintBoundary(
            key: _mapRepaintBoundaryKey,
            child: _buildMap(),
          ),

          // Layer panel (collapsible)
          if (_showLayerPanel)
            Positioned(
              top: 8,
              right: 8,
              width: 280,
              child: Card(
                elevation: 4,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(8),
                  child: _buildLayerPanel(),
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
