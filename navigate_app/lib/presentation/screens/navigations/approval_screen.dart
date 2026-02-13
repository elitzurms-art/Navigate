import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../domain/entities/navigation.dart' as domain;
import '../../../domain/entities/checkpoint.dart';
import '../../../domain/entities/checkpoint_punch.dart';
import '../../../domain/entities/navigation_score.dart';
import '../../../data/repositories/checkpoint_repository.dart';
import '../../../data/repositories/navigation_repository.dart';
import '../../../services/scoring_service.dart';
import '../../../services/auth_service.dart';
import '../../widgets/map_with_selector.dart';
import '../../widgets/map_controls.dart';

/// מסך אישור ניווט וחישוב ציונים
class ApprovalScreen extends StatefulWidget {
  final domain.Navigation navigation;
  final bool isNavigator;

  const ApprovalScreen({
    super.key,
    required this.navigation,
    this.isNavigator = false,
  });

  @override
  State<ApprovalScreen> createState() => _ApprovalScreenState();
}

class _ApprovalScreenState extends State<ApprovalScreen>
    with SingleTickerProviderStateMixin {
  final CheckpointRepository _checkpointRepo = CheckpointRepository();
  final NavigationRepository _navRepo = NavigationRepository();
  final ScoringService _scoringService = ScoringService();

  late TabController _tabController;

  List<Checkpoint> _checkpoints = [];
  Map<String, NavigationScore> _scores = {}; // ציון לכל מנווט
  Map<String, List<CheckpointPunch>> _punches = {}; // דקירות לכל מנווט (סימולציה)
  bool _isLoading = false;
  bool _autoApprovalEnabled = true;

  late domain.Navigation _currentNavigation;

  // למנווט
  final AuthService _authService = AuthService();
  List<Checkpoint> _myCheckpoints = [];
  List<LatLng> _plannedRoute = [];
  List<LatLng> _actualRoute = []; // TODO: לטעון מסלול בפועל מ-GPS tracking

  // מדידה
  bool _measureMode = false;
  final List<LatLng> _measurePoints = [];
  final MapController _navMapController = MapController();

  @override
  void initState() {
    super.initState();
    _currentNavigation = widget.navigation;
    if (!widget.isNavigator) {
      _tabController = TabController(length: 2, vsync: this);
    }
    _loadData();
    if (!widget.isNavigator) {
      _initializePunches();
    } else {
      _loadNavigatorData();
    }
  }

  Future<void> _loadNavigatorData() async {
    setState(() => _isLoading = true);

    try {
      final user = await _authService.getCurrentUser();
      if (user == null) return;

      final route = widget.navigation.routes[user.uid];
      if (route == null) return;

      // טעינת הנקודות אחד אחד
      final List<Checkpoint> checkpoints = [];
      for (final id in route.checkpointIds) {
        final cp = await _checkpointRepo.getById(id);
        if (cp != null) checkpoints.add(cp);
      }

      // יצירת מסלול מתוכנן
      final planned = route.sequence
          .map((id) => checkpoints.firstWhere((c) => c.id == id, orElse: () => checkpoints.first))
          .map((c) => LatLng(c.coordinates.lat, c.coordinates.lng))
          .toList();

      // TODO: טעינת מסלול בפועל מהמסד נתונים
      // בינתיים - מסלול ריק

      setState(() {
        _myCheckpoints = checkpoints;
        _plannedRoute = planned;
        _actualRoute = []; // TODO
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    if (!widget.isNavigator) {
      _tabController.dispose();
    }
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final checkpoints = await _checkpointRepo.getByArea(widget.navigation.areaId);
      setState(() {
        _checkpoints = checkpoints;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _initializePunches() {
    // TODO: בפועל יטען מה-DB
    // בינתיים - סימולציה
    for (final navigatorId in widget.navigation.routes.keys) {
      _punches[navigatorId] = []; // רשימה ריקה
    }
  }

  Future<void> _calculateAllScores() async {
    setState(() => _isLoading = true);

    try {
      for (final navigatorId in widget.navigation.routes.keys) {
        final punches = _punches[navigatorId] ?? [];

        final score = _scoringService.calculateAutomaticScore(
          navigationId: widget.navigation.id,
          navigatorId: navigatorId,
          punches: punches,
          verificationSettings: widget.navigation.verificationSettings,
        );

        _scores[navigatorId] = score;
      }

      setState(() => _isLoading = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ציונים חושבו בהצלחה'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
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

  Future<void> _publishAllScores() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('הפצת ציונים'),
        content: const Text(
          'האם להפיץ את הציונים לכל המנווטים?\n\n'
          'לאחר הפצה, המנווטים יוכלו לצפות בציונים שלהם.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.green),
            child: const Text('הפץ'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    try {
      // הפצה
      for (final entry in _scores.entries) {
        _scores[entry.key] = _scoringService.publishScore(entry.value);
      }

      // TODO: שמירה ב-DB ושליחה למנווטים

      // עדכון סטטוס ניווט
      final updatedNavigation = _currentNavigation.copyWith(
        status: 'review',
        updatedAt: DateTime.now(),
      );
      await _navRepo.update(updatedNavigation);
      _currentNavigation = updatedNavigation;

      setState(() => _isLoading = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('הציונים הופצו בהצלחה!'),
            backgroundColor: Colors.green,
          ),
        );

        // חזרה לרשימה
        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _editScore(String navigatorId) {
    final currentScore = _scores[navigatorId];
    if (currentScore == null) return;

    final TextEditingController scoreController = TextEditingController(
      text: currentScore.totalScore.toString(),
    );
    final TextEditingController notesController = TextEditingController(
      text: currentScore.notes ?? '',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('עריכת ציון - $navigatorId'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: scoreController,
              decoration: const InputDecoration(
                labelText: 'ציון (0-100)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: notesController,
              decoration: const InputDecoration(
                labelText: 'הערות',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () {
              final newScore = int.tryParse(scoreController.text) ?? currentScore.totalScore;
              setState(() {
                _scores[navigatorId] = _scoringService.updateScore(
                  currentScore,
                  newTotalScore: newScore,
                  newNotes: notesController.text,
                );
              });
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.green),
            child: const Text('שמור'),
          ),
        ],
      ),
    );
  }

  Future<void> _returnToPreparation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('חזרה להכנה'),
        content: const Text('האם להחזיר את הניווט למצב הכנה?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            child: const Text('חזרה להכנה'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final updatedNav = _currentNavigation.copyWith(
        status: 'preparation',
        updatedAt: DateTime.now(),
      );
      await _navRepo.update(updatedNav);
      _currentNavigation = updatedNav;
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteNavigation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('מחיקת ניווט'),
        content: const Text('פעולה זו בלתי הפיכה!\nכל נתוני הניווט יימחקו לצמיתות.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('מחק'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _navRepo.delete(_currentNavigation.id);
      if (mounted) Navigator.pop(context, 'deleted');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // תצוגה למנווט
    if (widget.isNavigator) {
      return _buildNavigatorView();
    }

    // תצוגה למפקד
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.navigation.name),
            const Text(
              'אישור ניווט',
              style: TextStyle(fontSize: 14),
            ),
          ],
        ),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.check_circle), text: 'אישור'),
            Tab(icon: Icon(Icons.grade), text: 'ציונים'),
          ],
        ),
        actions: [
          if (_scores.isEmpty)
            IconButton(
              icon: const Icon(Icons.calculate),
              tooltip: 'חשב ציונים',
              onPressed: _calculateAllScores,
            )
          else
            IconButton(
              icon: const Icon(Icons.send),
              tooltip: 'הפץ ציונים',
              onPressed: _publishAllScores,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildApprovalView(),
                _buildScoresView(),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _returnToPreparation,
                  icon: const Icon(Icons.undo),
                  label: const Text('חזרה להכנה'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _deleteNavigation,
                  icon: const Icon(Icons.delete_forever),
                  label: const Text('מחיקת ניווט'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildApprovalView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // הגדרות אישור
        Card(
          color: Colors.blue[50],
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.settings, color: Colors.blue[700]),
                    const SizedBox(width: 12),
                    const Text(
                      'הגדרות אישור',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  title: const Text('אישור אוטומטי'),
                  subtitle: const Text('חישוב ציונים לפי הגדרות הניווט'),
                  value: _autoApprovalEnabled,
                  onChanged: (value) {
                    setState(() => _autoApprovalEnabled = value ?? true);
                  },
                ),
                if (_autoApprovalEnabled) ...[
                  const Divider(),
                  Text(
                    'שיטה: ${widget.navigation.verificationSettings.verificationType ?? "אישור/נכשל"}',
                    style: const TextStyle(fontSize: 14),
                  ),
                  if (widget.navigation.verificationSettings.verificationType == 'approved_failed')
                    Text(
                      'מרחק אישור: ${widget.navigation.verificationSettings.approvalDistance ?? 50}m',
                      style: const TextStyle(fontSize: 14),
                    ),
                ],
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // רשימת מנווטים
        const Text(
          'רשימת מנווטים:',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),

        ...widget.navigation.routes.keys.map((navigatorId) {
          final punches = _punches[navigatorId] ?? [];
          return Card(
            child: ListTile(
              leading: const Icon(Icons.person, color: Colors.blue),
              title: Text(navigatorId),
              subtitle: Text('${punches.length} דקירות'),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () {
                // TODO: הצגת פרטי דקירות
              },
            ),
          );
        }),
      ],
    );
  }

  Widget _buildScoresView() {
    if (_scores.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.calculate, size: 100, color: Colors.grey[300]),
            const SizedBox(height: 20),
            const Text(
              'אין ציונים',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'לחץ על ⚙️ למעלה לחישוב ציונים אוטומטי',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // סיכום
        Card(
          color: Colors.green[50],
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Text(
                  'סיכום ציונים',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  'ממוצע כללי: ${_getAverageScore().toStringAsFixed(1)}',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // רשימת ציונים
        ..._scores.entries.map((entry) {
          final navigatorId = entry.key;
          final score = entry.value;

          return _buildScoreCard(navigatorId, score);
        }),
      ],
    );
  }

  Widget _buildScoreCard(String navigatorId, NavigationScore score) {
    final grade = _scoringService.getGrade(score.totalScore);
    final color = ScoringService.getScoreColor(score.totalScore);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    navigatorId,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: color, width: 2),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${score.totalScore}',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        grade,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // פרטים
            Row(
              children: [
                Icon(Icons.check_circle, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 6),
                Text(
                  '${score.checkpointScores.values.where((s) => s.approved).length}/${score.checkpointScores.length} אושרו',
                  style: TextStyle(color: Colors.grey[700]),
                ),
                const SizedBox(width: 16),
                Icon(Icons.edit, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 6),
                Text(
                  score.isManual ? 'ידני' : 'אוטומטי',
                  style: TextStyle(color: Colors.grey[700]),
                ),
                if (score.isPublished) ...[
                  const SizedBox(width: 16),
                  Icon(Icons.send, size: 16, color: Colors.green[600]),
                  const SizedBox(width: 6),
                  Text(
                    'הופץ',
                    style: TextStyle(color: Colors.green[700]),
                  ),
                ],
              ],
            ),

            if (score.notes != null && score.notes!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'הערות: ${score.notes}',
                  style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                ),
              ),
            ],

            // כפתורים
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _editScore(navigatorId),
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('ערוך'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      // TODO: הצגת פירוט דקירות
                    },
                    icon: const Icon(Icons.info, size: 18),
                    label: const Text('פירוט'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  double _getAverageScore() {
    if (_scores.isEmpty) return 0;
    final total = _scores.values.fold<int>(0, (sum, score) => sum + score.totalScore);
    return total / _scores.length;
  }

  /// תצוגה למנווט - צפייה במסלול ללא ציון
  Widget _buildNavigatorView() {
    if (_myCheckpoints.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.navigation.name),
          backgroundColor: Theme.of(context).primaryColor,
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Text('אין נקודות להצגה'),
        ),
      );
    }

    // חישוב מרכז המפה
    final center = LatLng(
      _myCheckpoints.map((c) => c.coordinates.lat).reduce((a, b) => a + b) / _myCheckpoints.length,
      _myCheckpoints.map((c) => c.coordinates.lng).reduce((a, b) => a + b) / _myCheckpoints.length,
    );

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.navigation.name),
            const Text(
              'ממתין לאישור',
              style: TextStyle(fontSize: 14),
            ),
          ],
        ),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // הודעה
                Card(
                  margin: const EdgeInsets.all(16),
                  color: Colors.amber[50],
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.hourglass_empty, color: Colors.amber[900]),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'הניווט הסתיים - ממתין לאישור המפקד',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // מפה
                Expanded(
                  child: Stack(
                    children: [
                      MapWithTypeSelector(
                    showTypeSelector: false,
                    mapController: _navMapController,
                    options: MapOptions(
                      initialCenter: center,
                      initialZoom: 14.0,
                      onTap: (tapPosition, point) {
                        if (_measureMode) {
                          setState(() => _measurePoints.add(point));
                        }
                      },
                    ),
                    layers: [
                      // מסלול מתוכנן (כחול)
                      if (_plannedRoute.length > 1)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: _plannedRoute,
                              color: Colors.blue,
                              strokeWidth: 3.0,
                            ),
                          ],
                        ),

                      // מסלול בפועל (ירוק)
                      if (_actualRoute.length > 1)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: _actualRoute,
                              color: Colors.green,
                              strokeWidth: 3.0,
                            ),
                          ],
                        ),

                      // נקודות
                      MarkerLayer(
                        markers: _myCheckpoints.asMap().entries.map((entry) {
                          final index = entry.key + 1;
                          final checkpoint = entry.value;
                          return Marker(
                            point: LatLng(checkpoint.coordinates.lat, checkpoint.coordinates.lng),
                            width: 40,
                            height: 40,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.blue,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: Center(
                                child: Text(
                                  '$index',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      ...MapControls.buildMeasureLayers(_measurePoints),
                    ],
                  ),
                      MapControls(
                        mapController: _navMapController,
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
                      ),
                    ],
                  ),
                ),

                // מקרא
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.grey[100],
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 30,
                            height: 3,
                            decoration: BoxDecoration(
                              color: Colors.blue,
                              border: Border.all(color: Colors.blue),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text('מסלול מתוכנן'),
                        ],
                      ),
                      Row(
                        children: [
                          Container(
                            width: 30,
                            height: 3,
                            color: Colors.green,
                          ),
                          const SizedBox(width: 8),
                          const Text('מסלול בפועל'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
