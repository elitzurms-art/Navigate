import 'package:flutter/material.dart';
import '../../../domain/entities/navigation.dart' as domain;
import '../../../domain/entities/navigation_settings.dart';
import '../../../domain/entities/checkpoint.dart';
import '../../../data/repositories/nav_layer_repository.dart';
import '../../../data/repositories/navigation_repository.dart';
import '../../../data/repositories/navigation_tree_repository.dart';
import '../../../data/repositories/checkpoint_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../domain/entities/navigation_tree.dart';
import '../../../domain/entities/boundary.dart';
import '../../../data/repositories/boundary_repository.dart';
import '../../../services/routes_distribution_service.dart';
import '../../../services/navigation_layer_copy_service.dart';
import 'checkpoint_map_picker_screen.dart';
import 'routes_verification_screen.dart';

/// שלב 2 - הגדרות חלוקה אוטומטית
class RoutesAutomaticSetupScreen extends StatefulWidget {
  final domain.Navigation navigation;

  const RoutesAutomaticSetupScreen({super.key, required this.navigation});

  @override
  State<RoutesAutomaticSetupScreen> createState() => _RoutesAutomaticSetupScreenState();
}

class _RoutesAutomaticSetupScreenState extends State<RoutesAutomaticSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final NavLayerRepository _navLayerRepo = NavLayerRepository();
  final NavigationRepository _navRepo = NavigationRepository();
  final NavigationTreeRepository _treeRepo = NavigationTreeRepository();
  final CheckpointRepository _checkpointRepo = CheckpointRepository();
  final NavigationLayerCopyService _layerCopyService = NavigationLayerCopyService();
  final RoutesDistributionService _distributionService = RoutesDistributionService();
  final UserRepository _userRepo = UserRepository();

  List<Checkpoint> _checkpoints = [];
  NavigationTree? _tree;
  Boundary? _boundary;
  bool _isLoading = false;

  // הגדרות
  String _navigationType = 'regular';
  String _executionOrder = 'sequential';
  double _minRouteLength = 5.0;
  double _maxRouteLength = 15.0;
  int _checkpointsPerNavigator = 5;
  String? _startPointId;
  String? _endPointId;

  // נקודות ביניים
  bool _waypointsEnabled = false;
  List<WaypointCheckpoint> _waypoints = [];

  // קריטריון ניקוד
  String _scoringCriterion = 'fairness';

  // הרכב הכוח
  String _forceComposition = 'solo';
  String? _swapPointId;
  Map<String, List<String>> _manualGroups = {};
  List<String> _navigatorsList = [];

  // Progress
  bool _isDistributing = false;
  int _progressCurrent = 0;
  int _progressTotal = 1000;

  @override
  void initState() {
    super.initState();
    _initializeFromNavigation(widget.navigation);
    _loadData();
  }

  void _initializeFromNavigation(domain.Navigation nav) {
    setState(() {
      _navigationType = nav.navigationType ?? 'regular';
      _executionOrder = nav.executionOrder ?? 'sequential';
      if (nav.routeLengthKm != null) {
        _minRouteLength = nav.routeLengthKm!.min;
        _maxRouteLength = nav.routeLengthKm!.max;
      }
      _checkpointsPerNavigator = nav.checkpointsPerNavigator ?? 5;
      _startPointId = nav.startPoint;
      _endPointId = nav.endPoint;

      // נקודות ביניים
      _waypointsEnabled = nav.waypointSettings.enabled;
      _waypoints = List.from(nav.waypointSettings.waypoints);

      // קריטריון חלוקה
      _scoringCriterion = nav.scoringCriterion ?? 'fairness';

      // הרכב הכוח
      _forceComposition = nav.forceComposition.type;
      _swapPointId = nav.forceComposition.swapPointId;
      _manualGroups = Map.from(nav.forceComposition.manualGroups.map(
        (k, v) => MapEntry(k, List<String>.from(v)),
      ));
    });
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // טעינת ניווט עדכני מה-DB (ולא widget.navigation שעלול להיות ישן)
      final freshNav = await _navRepo.getById(widget.navigation.id);
      if (freshNav != null) {
        _initializeFromNavigation(freshNav);
      }

      // טעינת נקודות ציון מהשכבות הניווטיות (כבר מסוננות לפי גבול גזרה)
      var navCheckpoints = await _navLayerRepo.getCheckpointsByNavigation(
        widget.navigation.id,
      );

      // אם אין נקודות ניווטיות — ננסה להעתיק שכבות מהשטח
      if (navCheckpoints.isEmpty) {
        await _layerCopyService.copyLayersForNavigation(
          navigationId: widget.navigation.id,
          boundaryId: widget.navigation.boundaryLayerId ?? '',
          areaId: widget.navigation.areaId,
          createdBy: '',
        );
        // ניסיון חוזר לטעינה
        navCheckpoints = await _navLayerRepo.getCheckpointsByNavigation(
          widget.navigation.id,
        );
      }

      // אם עדיין אין — טעינה ישירה מנקודות השטח
      List<Checkpoint> checkpoints;
      if (navCheckpoints.isEmpty) {
        checkpoints = await _checkpointRepo.getByArea(widget.navigation.areaId);
      } else {
        // המרה ל-Checkpoint עם sourceId כ-ID (תאימות לאחור)
        checkpoints = navCheckpoints.map((nc) => Checkpoint(
          id: nc.sourceId,
          areaId: nc.areaId,
          name: nc.name,
          description: nc.description,
          type: nc.type,
          color: nc.color,
          coordinates: nc.coordinates,
          sequenceNumber: nc.sequenceNumber,
          labels: nc.labels,
          createdBy: nc.createdBy,
          createdAt: nc.createdAt,
        )).toList();
      }

      // טעינת עץ מבנה
      final tree = await _treeRepo.getById(widget.navigation.treeId);

      // טעינת רשימת מנווטים
      final navigatorsList = await _loadNavigatorsList(tree);

      // טעינת גבול גזרה (לשימוש במפת בחירת נקודות)
      Boundary? boundary;
      if (widget.navigation.boundaryLayerId != null) {
        boundary = await BoundaryRepository().getById(widget.navigation.boundaryLayerId!);
      }

      setState(() {
        _checkpoints = checkpoints;
        _tree = tree;
        _boundary = boundary;
        _navigatorsList = navigatorsList;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה בטעינת נתונים: $e')),
        );
      }
    }
  }

  Future<List<String>> _loadNavigatorsList(NavigationTree? tree) async {
    if (tree == null) return [];
    final nav = widget.navigation;
    // אם נבחרו משתתפים ספציפיים
    if (nav.selectedParticipantIds.isNotEmpty) {
      final result = <String>[];
      for (final uid in nav.selectedParticipantIds) {
        final user = await _userRepo.getUser(uid);
        if (user != null && user.role == 'navigator') result.add(uid);
      }
      return result;
    }
    // fallback: מנווטים מהיחידה
    final unitId = nav.selectedUnitId ?? tree.unitId;
    if (unitId == null) return [];
    final users = await _userRepo.getNavigatorsForUnit(unitId);
    return users.map((u) => u.uid).toList();
  }

  Future<void> _saveSettings() async {
    final settingsNav = widget.navigation.copyWith(
      navigationType: _navigationType,
      executionOrder: _executionOrder,
      routeLengthKm: domain.RouteLengthRange(min: _minRouteLength, max: _maxRouteLength),
      checkpointsPerNavigator: _checkpointsPerNavigator,
      startPoint: _startPointId,
      endPoint: _endPointId,
      waypointSettings: WaypointSettings(enabled: _waypointsEnabled, waypoints: _waypoints),
      scoringCriterion: _scoringCriterion,
      forceComposition: ForceComposition(
        type: _forceComposition,
        swapPointId: _swapPointId,
        manualGroups: _manualGroups,
      ),
      updatedAt: DateTime.now(),
    );
    await _navRepo.update(settingsNav);
  }

  Future<void> _distribute() async {
    if (!_formKey.currentState!.validate()) return;
    if (_tree == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('לא נטען עץ מבנה')),
      );
      return;
    }

    // חובה לבחור נקודת התחלה וסיום
    if (_startPointId == null || _endPointId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('חובה לבחור נקודת התחלה ונקודת סיום'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // וידוא נקודות התחלה וסיום
    if (_navigationType == 'star') {
      if (_startPointId == null || _endPointId == null || _startPointId != _endPointId) {
        final result = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('ניווט כוכב'),
            content: const Text(
              'בניווט כוכב, נקודת ההתחלה והסיום צריכות להיות זהות.\n'
              'האם לקבוע את נקודת ההתחלה גם כנקודת סיום?'
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('ביטול'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('אישור'),
              ),
            ],
          ),
        );

        if (result != true) return;
        setState(() => _endPointId = _startPointId);
      }
    }

    // ולידציות הרכב הכוח (לפני _isDistributing)
    if (_forceComposition != 'solo') {
      if (_navigatorsList.length < 2) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('נדרשים לפחות 2 מנווטים להרכב לא-בדד')),
        );
        return;
      }
      if (_forceComposition == 'squad' && _navigatorsList.length < 4) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('נדרשים לפחות 4 מנווטים להרכב חוליה')),
        );
        return;
      }

      // שיבוץ אוטומטי אם לא הוגדרו קבוצות עדיין
      if (_manualGroups.isEmpty) {
        _autoAssignGroups();
      }

      // ולידציה: בדיקה שאין קבוצה שחורגת מהגודל המקסימלי
      final maxSize = ForceComposition(type: _forceComposition).maxGroupSize;
      final oversizedGroups = _manualGroups.entries
          .where((e) => e.value.length > maxSize)
          .toList();
      if (oversizedGroups.isNotEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('יש קבוצות עם יותר מ-$maxSize חברים — יש לאזן לפני החלוקה')),
        );
        return;
      }
    }

    // שמירת הגדרות לפני החלוקה — כך שהן נשמרות גם אם החלוקה נכשלת או בוטלה
    await _saveSettings();

    setState(() {
      _isDistributing = true;
      _progressCurrent = 0;
      _progressTotal = 1000;
    });

    final composition = ForceComposition(
      type: _forceComposition,
      swapPointId: _swapPointId,
      manualGroups: _manualGroups,
    );

    try {
      final distributionResult = await _distributionService.distributeAutomatically(
        navigation: widget.navigation,
        tree: _tree!,
        checkpoints: _checkpoints,
        boundary: null,
        startPointId: _startPointId,
        endPointId: _endPointId,
        waypoints: _waypointsEnabled ? _waypoints : [],
        executionOrder: _executionOrder,
        checkpointsPerNavigator: _checkpointsPerNavigator,
        minRouteLength: _minRouteLength,
        maxRouteLength: _maxRouteLength,
        scoringCriterion: _scoringCriterion,
        forceComposition: composition,
        onProgress: (current, total) {
          if (mounted) {
            setState(() {
              _progressCurrent = current;
              _progressTotal = total;
            });
          }
        },
      );

      setState(() => _isDistributing = false);

      // --- טיפול בתוצאה ---
      if (distributionResult.needsApproval) {
        final approved = await _showApprovalDialog(distributionResult);
        if (approved == null) return; // ביטל

        if (approved == 'accept_best') {
          // אישור החלוקה הטובה ביותר כמו שהיא
          await _saveAndNavigate(distributionResult.routes, distributionResult);
        } else if (approved == 'expand_range') {
          // הרצה מחדש עם טווח מורחב
          final option = distributionResult.approvalOptions
              .firstWhere((o) => o.type == 'expand_range');
          setState(() {
            _minRouteLength = option.expandedMin!;
            _maxRouteLength = option.expandedMax!;
          });
          await _distribute(); // הרצה מחדש
        } else if (approved == 'reduce_checkpoints') {
          // הרצה מחדש עם פחות נקודות
          final option = distributionResult.approvalOptions
              .firstWhere((o) => o.type == 'reduce_checkpoints');
          setState(() {
            _checkpointsPerNavigator = option.reducedCheckpoints!;
          });
          await _distribute(); // הרצה מחדש
        }
      } else {
        // הצלחה — שמירה ומעבר לוידוא
        await _saveAndNavigate(distributionResult.routes, distributionResult);
      }
    } catch (e) {
      setState(() => _isDistributing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה בחלוקה: $e')),
        );
      }
    }
  }

  Future<String?> _showApprovalDialog(domain.DistributionResult result) async {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        // סיכום צירים חורגים
        final outOfRange = result.routes.values.where((r) => r.status != 'optimal').length;
        final total = result.routes.length;

        return AlertDialog(
          title: const Text('חלוקה חורגת מהטווח'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$outOfRange מתוך $total צירים חורגים מטווח '
                '${_minRouteLength.toStringAsFixed(1)} — ${_maxRouteLength.toStringAsFixed(1)} ק"מ',
                style: const TextStyle(fontSize: 14),
              ),
              if (result.hasSharedCheckpoints) ...[
                const SizedBox(height: 8),
                Text(
                  '${result.sharedCheckpointCount} נקודות משותפות בין מנווטים',
                  style: TextStyle(fontSize: 13, color: Colors.orange[700]),
                ),
              ],
              const SizedBox(height: 16),
              const Text(
                'בחר פעולה:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...result.approvalOptions.map((option) {
                IconData icon;
                Color color;
                switch (option.type) {
                  case 'expand_range':
                    icon = Icons.open_in_full;
                    color = Colors.blue;
                    break;
                  case 'reduce_checkpoints':
                    icon = Icons.remove_circle_outline;
                    color = Colors.orange;
                    break;
                  case 'accept_best':
                    icon = Icons.check_circle_outline;
                    color = Colors.green;
                    break;
                  default:
                    icon = Icons.help_outline;
                    color = Colors.grey;
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context, option.type),
                    icon: Icon(icon, color: color),
                    label: Text(option.label),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: color,
                      minimumSize: const Size(double.infinity, 44),
                      alignment: Alignment.centerRight,
                    ),
                  ),
                );
              }),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('ביטול'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveAndNavigate(
    Map<String, domain.AssignedRoute> routes,
    domain.DistributionResult distributionResult,
  ) async {
    // הצגת הודעה על שיתוף אם יש
    if (distributionResult.hasSharedCheckpoints && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'שים לב: ${distributionResult.sharedCheckpointCount} נקודות משותפות בין מנווטים',
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );
    }

    // שמירת הגדרות + צירים + סטטוס חלוקה
    await _saveSettings();
    final updatedNavigation = widget.navigation.copyWith(
      routes: routes,
      routesStage: 'verification',
      routesDistributed: true,
      navigationType: _navigationType,
      executionOrder: _executionOrder,
      routeLengthKm: domain.RouteLengthRange(
        min: _minRouteLength,
        max: _maxRouteLength,
      ),
      checkpointsPerNavigator: _checkpointsPerNavigator,
      startPoint: _startPointId,
      endPoint: _endPointId,
      waypointSettings: WaypointSettings(
        enabled: _waypointsEnabled,
        waypoints: _waypoints,
      ),
      forceComposition: distributionResult.forceComposition ?? ForceComposition(
        type: _forceComposition,
        swapPointId: _swapPointId,
        manualGroups: _manualGroups,
      ),
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
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _saveSettings();
        if (context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('חלוקה אוטומטית'),
          backgroundColor: Theme.of(context).primaryColor,
          foregroundColor: Colors.white,
        ),
        body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _isDistributing
              ? _buildProgressView()
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'הגדרות חלוקה',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 24),

                        // סוג ניווט
                        _buildNavigationTypeSection(),
                        const SizedBox(height: 16),

                        // הרכב הכוח
                        _buildForceCompositionSection(),
                        const SizedBox(height: 16),

                        // שיבוץ קבוצות (רק כשהרכב ≠ בדד)
                        if (_forceComposition != 'solo') ...[
                          _buildGroupsSection(),
                          const SizedBox(height: 16),
                        ],

                        // אופן ביצוע
                        _buildExecutionOrderSection(),
                        const SizedBox(height: 16),

                        // טווח אורך ציר
                        _buildRouteLengthSection(),
                        const SizedBox(height: 16),

                        // כמות נקודות למנווט
                        _buildCheckpointsPerNavigatorSection(),
                        const SizedBox(height: 16),

                        // נקודות התחלה וסיום
                        _buildStartEndPointsSection(),
                        const SizedBox(height: 16),

                        // נקודות ביניים
                        _buildWaypointsSection(),
                        const SizedBox(height: 16),

                        // קריטריון ניקוד
                        _buildScoringCriterionSection(),
                        const SizedBox(height: 24),

                        // אשכולות/ביצים (בפיתוח)
                        if (_navigationType == 'clusters' || _navigationType == 'eggs')
                          _buildClustersSection(),

                        const SizedBox(height: 32),

                        // כפתור חלוקה
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton.icon(
                            onPressed: _distribute,
                            icon: const Icon(Icons.auto_awesome),
                            label: const Text('חלק אוטומטית'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                        SizedBox(height: MediaQuery.of(context).padding.bottom),
                      ],
                    ),
                  ),
                ),
      ),
    );
  }

  Widget _buildProgressView() {
    final progress = _progressTotal > 0 ? _progressCurrent / _progressTotal : 0.0;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.auto_awesome, size: 64, color: Colors.blue),
            const SizedBox(height: 24),
            const Text(
              'מחלק צירים...',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 12,
                backgroundColor: Colors.grey[200],
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'בודק אופציה $_progressCurrent / $_progressTotal',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              '${(progress * 100).toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blue),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScoringCriterionSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'קריטריון חלוקה',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: 'איך האלגוריתם בוחר את החלוקה הטובה ביותר',
                  child: Icon(Icons.info_outline, size: 18, color: Colors.grey[600]),
                ),
              ],
            ),
            const SizedBox(height: 12),
            RadioListTile<String>(
              title: const Text('הוגנות'),
              subtitle: const Text('אורך צירים אחיד ככל האפשר'),
              value: 'fairness',
              groupValue: _scoringCriterion,
              onChanged: (value) => setState(() => _scoringCriterion = value!),
            ),
            RadioListTile<String>(
              title: const Text('קרבה לאמצע הטווח'),
              subtitle: const Text('כל הצירים קרובים לאמצע הטווח'),
              value: 'midpoint',
              groupValue: _scoringCriterion,
              onChanged: (value) => setState(() => _scoringCriterion = value!),
            ),
            RadioListTile<String>(
              title: const Text('מקסימום ייחודיות'),
              subtitle: const Text('כמה שפחות נקודות משותפות בין מנווטים'),
              value: 'uniqueness',
              groupValue: _scoringCriterion,
              onChanged: (value) => setState(() => _scoringCriterion = value!),
            ),
            RadioListTile<String>(
              title: const Text('אימות כפול'),
              subtitle: const Text('כל נקודה נבדקת ע"י 2 מנווטים שונים'),
              value: 'doubleCheck',
              groupValue: _scoringCriterion,
              onChanged: (value) => setState(() => _scoringCriterion = value!),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavigationTypeSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'סוג ניווט',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _navigationType,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'בחר סוג',
              ),
              items: const [
                DropdownMenuItem(value: 'regular', child: Text('רגיל')),
                DropdownMenuItem(value: 'star', child: Text('כוכב')),
                DropdownMenuItem(value: 'reverse', child: Text('הפוך')),
                DropdownMenuItem(value: 'parachute', child: Text('צנחנים')),
                DropdownMenuItem(value: 'clusters', child: Text('אשכולות')),
                DropdownMenuItem(value: 'developing', child: Text('מפתח')),
              ],
              onChanged: (value) {
                setState(() => _navigationType = value!);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExecutionOrderSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'אופן ביצוע',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            RadioListTile<String>(
              title: const Text('לפי סדר הנקודות'),
              subtitle: const Text('המנווט חייב לעבור בנקודות לפי הסדר'),
              value: 'sequential',
              groupValue: _executionOrder,
              onChanged: (value) {
                setState(() => _executionOrder = value!);
              },
            ),
            RadioListTile<String>(
              title: const Text('לפי בחירת המנווט'),
              subtitle: const Text('המנווט יכול לבחור את סדר הנקודות'),
              value: 'navigator_choice',
              groupValue: _executionOrder,
              onChanged: (value) {
                setState(() => _executionOrder = value!);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRouteLengthSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'טווח אורך ציר (ק"מ)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: _minRouteLength.toString(),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'מינימום',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) return 'שדה חובה';
                      final num = double.tryParse(value);
                      if (num == null || num <= 0) return 'מספר חיובי';
                      return null;
                    },
                    onChanged: (value) {
                      _minRouteLength = double.tryParse(value) ?? _minRouteLength;
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    initialValue: _maxRouteLength.toString(),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'מקסימום',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) return 'שדה חובה';
                      final num = double.tryParse(value);
                      if (num == null || num <= 0) return 'מספר חיובי';
                      if (num < _minRouteLength) return 'גדול ממינימום';
                      return null;
                    },
                    onChanged: (value) {
                      _maxRouteLength = double.tryParse(value) ?? _maxRouteLength;
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckpointsPerNavigatorSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'כמות נקודות ציון למנווט',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: _checkpointsPerNavigator.toString(),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'מספר נקודות (1-10)',
                helperText: 'כל מנווט יקבל אותו מספר נקודות',
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value == null || value.isEmpty) return 'שדה חובה';
                final num = int.tryParse(value);
                if (num == null || num < 1 || num > 10) return 'בין 1 ל-10';
                return null;
              },
              onChanged: (value) {
                _checkpointsPerNavigator = int.tryParse(value) ?? _checkpointsPerNavigator;
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStartEndPointsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'נקודות התחלה וסיום',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: 'נקודות משותפות לכל המנווטים',
                  child: Icon(Icons.info_outline, size: 18, color: Colors.grey[600]),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // נקודת התחלה
            DropdownButtonFormField<String>(
              value: _startPointId,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'נקודת התחלה (משותפת) *',
              ),
              items: [
                DropdownMenuItem(
                  value: '__pick_on_map__',
                  child: Row(
                    children: [
                      Icon(Icons.map, size: 18, color: Colors.blue),
                      SizedBox(width: 8),
                      Text('בחר במפה'),
                    ],
                  ),
                ),
                ..._checkpoints.map((cp) => DropdownMenuItem(
                  value: cp.id,
                  child: Text(cp.displayLabel),
                )),
              ],
              validator: (value) {
                if (value == null) return 'חובה לבחור נקודת התחלה';
                return null;
              },
              onChanged: (value) async {
                if (value == '__pick_on_map__') {
                  final selectedId = await Navigator.push<String>(context,
                    MaterialPageRoute(builder: (_) => CheckpointMapPickerScreen(
                      checkpoints: _checkpoints,
                      boundary: _boundary,
                    )));
                  if (selectedId != null) setState(() => _startPointId = selectedId);
                  return;
                }
                setState(() => _startPointId = value);
              },
            ),
            const SizedBox(height: 12),

            // נקודת סיום
            DropdownButtonFormField<String>(
              value: _endPointId,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'נקודת סיום (משותפת) *',
              ),
              items: [
                DropdownMenuItem(
                  value: '__pick_on_map__',
                  child: Row(
                    children: [
                      Icon(Icons.map, size: 18, color: Colors.blue),
                      SizedBox(width: 8),
                      Text('בחר במפה'),
                    ],
                  ),
                ),
                ..._checkpoints.map((cp) => DropdownMenuItem(
                  value: cp.id,
                  child: Text(cp.displayLabel),
                )),
              ],
              validator: (value) {
                if (value == null) return 'חובה לבחור נקודת סיום';
                return null;
              },
              onChanged: (value) async {
                if (value == '__pick_on_map__') {
                  final selectedId = await Navigator.push<String>(context,
                    MaterialPageRoute(builder: (_) => CheckpointMapPickerScreen(
                      checkpoints: _checkpoints,
                      boundary: _boundary,
                    )));
                  if (selectedId != null) setState(() => _endPointId = selectedId);
                  return;
                }
                setState(() => _endPointId = value);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWaypointsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'נקודות ביניים (נ.צ. משותפות)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Switch(
                  value: _waypointsEnabled,
                  onChanged: (value) {
                    setState(() => _waypointsEnabled = value);
                  },
                ),
              ],
            ),
            if (_waypointsEnabled) ...[
              const SizedBox(height: 8),
              Text(
                'נקודות ציון שכל המנווטים יעברו בהן',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 16),

              // רשימת נקודות ביניים
              ..._waypoints.asMap().entries.map((entry) {
                final index = entry.key;
                final waypoint = entry.value;
                return _buildWaypointCard(index, waypoint);
              }),

              const SizedBox(height: 12),

              // כפתור הוספת נקודת ביניים
              OutlinedButton.icon(
                onPressed: _addWaypoint,
                icon: const Icon(Icons.add),
                label: const Text('הוסף נקודת ביניים'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.blue,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildWaypointCard(int index, WaypointCheckpoint waypoint) {
    return Card(
      color: Colors.blue[50],
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'נקודת ביניים ${index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete, size: 20),
                  onPressed: () => _removeWaypoint(index),
                  color: Colors.red,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // בחירת נקודת ציון
            DropdownButtonFormField<String>(
              value: waypoint.checkpointId,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'בחר נקודת ציון',
                filled: true,
                fillColor: Colors.white,
              ),
              items: [
                DropdownMenuItem(
                  value: '__pick_on_map__',
                  child: Row(
                    children: [
                      Icon(Icons.map, size: 18, color: Colors.blue),
                      SizedBox(width: 8),
                      Text('בחר במפה'),
                    ],
                  ),
                ),
                ..._checkpoints.map((cp) => DropdownMenuItem(
                  value: cp.id,
                  child: Text(cp.displayLabel),
                )),
              ],
              onChanged: (value) async {
                if (value == '__pick_on_map__') {
                  final selectedId = await Navigator.push<String>(context,
                    MaterialPageRoute(builder: (_) => CheckpointMapPickerScreen(
                      checkpoints: _checkpoints,
                      boundary: _boundary,
                    )));
                  if (selectedId != null) _updateWaypointCheckpoint(index, selectedId);
                  return;
                }
                if (value != null) {
                  _updateWaypointCheckpoint(index, value);
                }
              },
            ),
            const SizedBox(height: 12),

            // סוג מיקום לבניית צירים
            DropdownButtonFormField<String>(
              value: waypoint.placementType,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'הגדרות לבניית צירים',
                filled: true,
                fillColor: Colors.white,
              ),
              items: const [
                DropdownMenuItem(
                  value: 'distance',
                  child: Text('לפי מרחק'),
                ),
                DropdownMenuItem(
                  value: 'between_checkpoints',
                  child: Text('בין נקודות ספציפיות'),
                ),
              ],
              onChanged: (value) => _updateWaypointPlacementType(index, value!),
            ),
            const SizedBox(height: 12),

            // שדות לפי סוג
            if (waypoint.placementType == 'distance') ...[
              Text(
                'לעבור בה אחרי ${waypoint.afterDistanceMinKm?.toStringAsFixed(1) ?? "2.0"}-${waypoint.afterDistanceMaxKm?.toStringAsFixed(1) ?? "5.0"} ק"מ',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              RangeSlider(
                min: 0.0,
                max: _maxRouteLength,
                divisions: (_maxRouteLength * 10).toInt().clamp(1, 1000),
                values: RangeValues(
                  (waypoint.afterDistanceMinKm ?? 2.0).clamp(0.0, _maxRouteLength),
                  (waypoint.afterDistanceMaxKm ?? 5.0).clamp(0.0, _maxRouteLength),
                ),
                labels: RangeLabels(
                  (waypoint.afterDistanceMinKm ?? 2.0).toStringAsFixed(1),
                  (waypoint.afterDistanceMaxKm ?? 5.0).toStringAsFixed(1),
                ),
                onChanged: (values) {
                  _updateWaypointDistanceRange(index, values.start, values.end);
                },
              ),
            ] else if (waypoint.placementType == 'between_checkpoints')
              DropdownButtonFormField<int>(
                value: (waypoint.afterCheckpointIndex ?? -1).clamp(-1, _checkpointsPerNavigator - 1),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'מיקום',
                  filled: true,
                  fillColor: Colors.white,
                ),
                items: List.generate(_checkpointsPerNavigator + 1, (i) {
                  final gapIndex = i - 1; // -1..K-1
                  final String label;
                  if (gapIndex == -1) {
                    label = 'בין התחלה לנקודה 1';
                  } else if (gapIndex == _checkpointsPerNavigator - 1) {
                    label = 'בין נקודה $_checkpointsPerNavigator לסיום';
                  } else {
                    label = 'בין נקודה ${gapIndex + 1} לנקודה ${gapIndex + 2}';
                  }
                  return DropdownMenuItem(
                    value: gapIndex,
                    child: Text(label),
                  );
                }),
                onChanged: (value) {
                  if (value != null) {
                    _updateWaypointGap(index, value);
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  void _addWaypoint() {
    if (_checkpoints.isEmpty) return;
    setState(() {
      _waypoints.add(WaypointCheckpoint(
        checkpointId: _checkpoints.first.id,
        placementType: 'distance',
        afterDistanceMinKm: 2.0,
        afterDistanceMaxKm: 5.0,
      ));
    });
  }

  void _removeWaypoint(int index) {
    setState(() {
      _waypoints.removeAt(index);
    });
  }

  void _updateWaypointCheckpoint(int index, String checkpointId) {
    setState(() {
      final current = _waypoints[index];
      _waypoints[index] = current.copyWith(checkpointId: checkpointId);
    });
  }

  void _updateWaypointPlacementType(int index, String type) {
    setState(() {
      final current = _waypoints[index];
      _waypoints[index] = WaypointCheckpoint(
        checkpointId: current.checkpointId,
        placementType: type,
        afterDistanceMinKm: type == 'distance' ? (current.afterDistanceMinKm ?? 2.0) : null,
        afterDistanceMaxKm: type == 'distance' ? (current.afterDistanceMaxKm ?? 5.0) : null,
        afterCheckpointIndex: type == 'between_checkpoints' ? (current.afterCheckpointIndex ?? -1) : null,
      );
    });
  }

  void _updateWaypointDistanceRange(int index, double minKm, double maxKm) {
    setState(() {
      final current = _waypoints[index];
      _waypoints[index] = current.copyWith(
        afterDistanceMinKm: minKm,
        afterDistanceMaxKm: maxKm,
      );
    });
  }

  void _updateWaypointGap(int index, int gapIndex) {
    setState(() {
      final current = _waypoints[index];
      _waypoints[index] = current.copyWith(afterCheckpointIndex: gapIndex);
    });
  }

  void _autoAssignGroups() {
    final baseSize = ForceComposition(type: _forceComposition).baseGroupSize;
    final groups = RoutesDistributionService.autoGroupNavigators(
      navigators: _navigatorsList,
      baseGroupSize: baseSize,
      compositionType: _forceComposition,
    );
    setState(() => _manualGroups = groups);
  }

  Widget _buildForceCompositionSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'הרכב הכוח',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _forceComposition,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'בחר הרכב',
              ),
              items: const [
                DropdownMenuItem(value: 'solo', child: Text('בדד')),
                DropdownMenuItem(value: 'guard', child: Text('מאבטח')),
                DropdownMenuItem(value: 'pair', child: Text('צמד')),
                DropdownMenuItem(value: 'squad', child: Text('חוליה')),
              ],
              onChanged: (value) {
                setState(() {
                  _forceComposition = value!;
                  _manualGroups = {};
                  if (value != 'guard') _swapPointId = null;
                });
              },
            ),
            const SizedBox(height: 8),
            Text(
              switch (_forceComposition) {
                'solo' => 'כל מנווט מקבל ציר עצמאי',
                'guard' => 'זוגות מנווטים — כל אחד מקבל חצי ציר עם נקודת החלפה',
                'pair' => 'צמדי מנווטים — כל צמד מקבל ציר משותף',
                'squad' => 'חוליות של 4 מנווטים — כל חוליה מקבלת ציר משותף',
                _ => '',
              },
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),

            // בורר נקודת החלפה — רק למאבטח
            if (_forceComposition == 'guard') ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _swapPointId,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'נקודת החלפה גלובלית',
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('אוטומטי (אמצע הציר)')),
                  DropdownMenuItem(
                    value: '__pick_on_map__',
                    child: Row(
                      children: [
                        Icon(Icons.map, size: 18, color: Colors.blue),
                        SizedBox(width: 8),
                        Text('בחר במפה'),
                      ],
                    ),
                  ),
                  ..._checkpoints.map((cp) => DropdownMenuItem(
                    value: cp.id,
                    child: Text(cp.displayLabel),
                  )),
                ],
                onChanged: (value) async {
                  if (value == '__pick_on_map__') {
                    final selectedId = await Navigator.push<String>(context,
                      MaterialPageRoute(builder: (_) => CheckpointMapPickerScreen(
                        checkpoints: _checkpoints,
                        boundary: _boundary,
                      )));
                    if (selectedId != null) setState(() => _swapPointId = selectedId);
                    return;
                  }
                  setState(() => _swapPointId = value);
                },
              ),
              const SizedBox(height: 4),
              Text(
                'כל הזוגות יחליפו באותה נקודה',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGroupsSection() {
    final baseSize = ForceComposition(type: _forceComposition).baseGroupSize;
    final compositionLabel = switch (_forceComposition) {
      'guard' => 'זוג',
      'pair' => 'צמד',
      'squad' => 'חוליה',
      _ => 'קבוצה',
    };
    final compositionLabelPlural = switch (_forceComposition) {
      'guard' => 'זוגות',
      'pair' => 'צמדים',
      'squad' => 'חוליות',
      _ => 'קבוצות',
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'שיבוץ $compositionLabelPlural',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _autoAssignGroups,
                  icon: const Icon(Icons.shuffle, size: 18),
                  label: Text(_manualGroups.isEmpty ? 'שיבוץ אוטומטי' : 'ערבב מחדש'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${_navigatorsList.length} מנווטים, גודל בסיס: $baseSize',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),

            if (_manualGroups.isEmpty) ...[
              const SizedBox(height: 16),
              Center(
                child: Text(
                  'לחץ "שיבוץ אוטומטי" או שהחלוקה תבוצע אוטומטית',
                  style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                ),
              ),
            ] else ...[
              const SizedBox(height: 12),
              ..._manualGroups.entries.toList().asMap().entries.map((entry) {
                final groupIndex = entry.key;
                final groupId = entry.value.key;
                final members = entry.value.value;
                final sizeLabel = members.length == 1
                    ? ' (בדד)'
                    : members.length == 3 && baseSize == 2
                        ? ' (שלישייה)'
                        : members.length != baseSize
                            ? ' (${members.length} חברים)'
                            : '';

                return Card(
                  color: Colors.blue[50],
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$compositionLabel ${groupIndex + 1}$sizeLabel',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        ...members.asMap().entries.map((memberEntry) {
                          final memberId = memberEntry.value;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              children: [
                                const Icon(Icons.person, size: 18, color: Colors.blueGrey),
                                const SizedBox(width: 8),
                                Expanded(child: Text(memberId, style: const TextStyle(fontSize: 13))),
                                // Dropdown לשינוי קבוצה
                                DropdownButton<String>(
                                  value: groupId,
                                  underline: const SizedBox(),
                                  isDense: true,
                                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                                  items: [
                                    ..._manualGroups.keys.toList().asMap().entries.map((gEntry) {
                                      final targetSize = _manualGroups[gEntry.value]!.length;
                                      final maxSize = ForceComposition(type: _forceComposition).maxGroupSize;
                                      final isFull = targetSize >= maxSize;
                                      return DropdownMenuItem(
                                        value: gEntry.value,
                                        enabled: !isFull || gEntry.value == groupId,
                                        child: Text(
                                          '$compositionLabel ${gEntry.key + 1}${isFull && gEntry.value != groupId ? " (מלא)" : ""}',
                                          style: isFull && gEntry.value != groupId
                                              ? TextStyle(color: Colors.grey[400])
                                              : null,
                                        ),
                                      );
                                    }),
                                    DropdownMenuItem(
                                      value: '__new_group__',
                                      child: Text('+ $compositionLabel חדש'),
                                    ),
                                  ],
                                  onChanged: (newGroupId) {
                                    if (newGroupId == null || newGroupId == groupId) return;
                                    setState(() {
                                      _manualGroups[groupId]!.remove(memberId);
                                      if (newGroupId == '__new_group__') {
                                        final newId = 'group_${DateTime.now().millisecondsSinceEpoch}';
                                        _manualGroups[newId] = [memberId];
                                      } else {
                                        _manualGroups[newGroupId]!.add(memberId);
                                      }
                                      _manualGroups.removeWhere((_, v) => v.isEmpty);
                                    });
                                  },
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildClustersSection() {
    return Card(
      color: Colors.amber[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(Icons.construction, size: 48, color: Colors.amber[700]),
            const SizedBox(height: 8),
            const Text(
              'אשכולות / ביצים',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'תכונה בפיתוח',
              style: TextStyle(color: Colors.amber[700]),
            ),
          ],
        ),
      ),
    );
  }
}
