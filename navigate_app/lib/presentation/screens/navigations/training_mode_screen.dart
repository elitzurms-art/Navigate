import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../domain/entities/navigation.dart' as domain;
import '../../../domain/entities/checkpoint.dart';
import '../../../domain/entities/boundary.dart';
import '../../../data/repositories/checkpoint_repository.dart';
import '../../../data/repositories/boundary_repository.dart';
import '../../../data/repositories/navigation_repository.dart';
import '../../../data/repositories/safety_point_repository.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/geometry_utils.dart';
import '../../../domain/entities/safety_point.dart';
import '../../widgets/map_with_selector.dart';
import '../../widgets/map_controls.dart';
import '../../widgets/fullscreen_map_screen.dart';
import '../../../domain/entities/navigation_settings.dart';

/// מסך מצב למידה לניווט
class TrainingModeScreen extends StatefulWidget {
  final domain.Navigation navigation;
  final bool isCommander; // האם המשתמש הנוכחי הוא מפקד

  const TrainingModeScreen({
    super.key,
    required this.navigation,
    this.isCommander = true, // ברירת מחדל למפקד (נשנה לפי הרשאות)
  });

  @override
  State<TrainingModeScreen> createState() => _TrainingModeScreenState();
}

class _TrainingModeScreenState extends State<TrainingModeScreen> with SingleTickerProviderStateMixin {
  final CheckpointRepository _checkpointRepo = CheckpointRepository();
  final BoundaryRepository _boundaryRepo = BoundaryRepository();
  final NavigationRepository _navRepo = NavigationRepository();
  final SafetyPointRepository _safetyPointRepo = SafetyPointRepository();
  final MapController _mapController = MapController();

  late TabController _tabController;
  List<Checkpoint> _checkpoints = [];
  Boundary? _boundary;
  List<SafetyPoint> _safetyPoints = [];
  Map<String, bool> _selectedNavigators = {};
  // _routeApprovals הוסר — סטטוס נגזר מ-approvalStatus ב-AssignedRoute
  bool _isLoading = false;
  bool _learningStarted = false;

  bool _measureMode = false;
  final List<LatLng> _measurePoints = [];

  // שכבות
  bool _showGG = true;
  double _ggOpacity = 1.0;
  bool _showNZ = true;
  double _nzOpacity = 1.0;
  bool _showNB = false;
  double _nbOpacity = 1.0;
  bool _showRoutes = true;
  double _routesOpacity = 1.0;

  // הגדרות למידה
  bool _enableLearningWithPhones = true;
  bool _showAllCheckpoints = false;
  bool _showNavigationDetails = true;
  bool _showLearningRoutes = true;
  bool _allowRouteEditing = true;
  bool _allowRouteNarration = true;
  bool _autoLearningTimes = false;
  DateTime _learningDate = DateTime.now();
  TimeOfDay _learningStartTime = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _learningEndTime = const TimeOfDay(hour: 17, minute: 0);

  // האזנה בזמן אמת לשינויים בניווט (צירים, סטטוסים)
  StreamSubscription<domain.Navigation?>? _navigationListener;
  // polling fallback — למקרה שה-listener לא עובד (Windows threading bug)
  Timer? _navigationPollTimer;

  // טיימרים ללמידה אוטומטית
  Timer? _autoStartTimer;
  Timer? _autoEndTimer;

  // עותק מקומי של הניווט שנשמר ומתעדכן עם כל שינוי
  late domain.Navigation _currentNavigation;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _currentNavigation = widget.navigation;
    _learningStarted = widget.navigation.status == 'learning';
    _initLearningSettings();
    _scheduleAutoLearning();
    _loadData();
    _reloadNavigationFromDb();
    _startNavigationListener();
    _startNavigationPolling();

    // אתחול בחירת מנווטים וסטטוסי אישור מהאובייקט שהתקבל
    for (final navigatorId in widget.navigation.routes.keys) {
      _selectedNavigators[navigatorId] = true;
    }
  }

  @override
  void dispose() {
    _navigationListener?.cancel();
    _navigationPollTimer?.cancel();
    _autoStartTimer?.cancel();
    _autoEndTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  void _initLearningSettings() {
    final ls = _currentNavigation.learningSettings;
    _enableLearningWithPhones = ls.enabledWithPhones;
    _showAllCheckpoints = ls.showAllCheckpoints;
    _showNavigationDetails = ls.showNavigationDetails;
    _showLearningRoutes = ls.showRoutes;
    _allowRouteEditing = ls.allowRouteEditing;
    _allowRouteNarration = ls.allowRouteNarration;
    _autoLearningTimes = ls.autoLearningTimes;
    if (ls.learningDate != null) {
      _learningDate = ls.learningDate!;
    }
    if (ls.learningStartTime != null) {
      final parts = ls.learningStartTime!.split(':');
      if (parts.length == 2) {
        _learningStartTime = TimeOfDay(
          hour: int.tryParse(parts[0]) ?? 8,
          minute: int.tryParse(parts[1]) ?? 0,
        );
      }
    }
    if (ls.learningEndTime != null) {
      final parts = ls.learningEndTime!.split(':');
      if (parts.length == 2) {
        _learningEndTime = TimeOfDay(
          hour: int.tryParse(parts[0]) ?? 17,
          minute: int.tryParse(parts[1]) ?? 0,
        );
      }
    }
  }

  /// תזמון התחלה/סיום אוטומטיים של למידה לפי ההגדרות
  void _scheduleAutoLearning() {
    _autoStartTimer?.cancel();
    _autoEndTimer?.cancel();

    if (!_autoLearningTimes) return;
    if (!widget.isCommander) return;

    final now = DateTime.now();

    // בניית DateTime מלא מתאריך + שעה
    final startDateTime = DateTime(
      _learningDate.year,
      _learningDate.month,
      _learningDate.day,
      _learningStartTime.hour,
      _learningStartTime.minute,
    );
    final endDateTime = DateTime(
      _learningDate.year,
      _learningDate.month,
      _learningDate.day,
      _learningEndTime.hour,
      _learningEndTime.minute,
    );

    // התחלת למידה אוטומטית
    if (!_learningStarted && startDateTime.isAfter(now)) {
      final delay = startDateTime.difference(now);
      _autoStartTimer = Timer(delay, () {
        if (!mounted) return;
        if (_learningStarted) return; // כבר הופעל ידנית
        _startLearning();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('למידה הופעלה אוטומטית לפי הזמן שהוגדר'),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 4),
          ),
        );
      });
    }

    // סיום למידה אוטומטי
    if (endDateTime.isAfter(now)) {
      final delay = endDateTime.difference(now);
      _autoEndTimer = Timer(delay, () {
        if (!mounted) return;
        if (!_learningStarted) return; // הלמידה לא פעילה — אין מה לסיים
        _autoFinishLearning();
      });
    }
  }

  /// סיום למידה אוטומטי — ללא דיאלוג אישור
  Future<void> _autoFinishLearning() async {
    final updatedNav = _currentNavigation.copyWith(
      status: 'preparation',
      trainingStartTime: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await _navRepo.update(updatedNav);
    _currentNavigation = updatedNav;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('למידה הסתיימה אוטומטית לפי הזמן שהוגדר'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 4),
        ),
      );
      Navigator.pop(context, true);
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final checkpoints = await _checkpointRepo.getByArea(widget.navigation.areaId);
      final safetyPoints = await _safetyPointRepo.getByArea(widget.navigation.areaId);

      Boundary? boundary;
      if (widget.navigation.boundaryLayerId != null) {
        boundary = await _boundaryRepo.getById(widget.navigation.boundaryLayerId!);
      }

      setState(() {
        _checkpoints = checkpoints;
        _safetyPoints = safetyPoints;
        _boundary = boundary;
        _isLoading = false;
      });

      // התמקד במרכז הגבול — דחייה עד שהמפה נבנית
      if (boundary != null && boundary.coordinates.isNotEmpty) {
        final center = GeometryUtils.getPolygonCenter(boundary.coordinates);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          try {
            _mapController.move(LatLng(center.lat, center.lng), 13.0);
          } catch (_) {
            // MapController עדיין לא מאותחל — נתעלם
          }
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה בטעינה: $e')),
        );
      }
    }
  }

  /// טעינת הניווט העדכני מה-DB
  Future<void> _reloadNavigationFromDb() async {
    try {
      final fresh = await _navRepo.getById(widget.navigation.id);
      if (fresh != null && mounted) {
        setState(() {
          _currentNavigation = fresh;
        });
      }
    } catch (_) {}
  }

  // ===========================================================================
  // Navigation listener — realtime route/status updates from Firestore
  // ===========================================================================

  void _startNavigationListener() {
    _navigationListener = _navRepo.watchNavigation(widget.navigation.id).listen(
      (nav) {
        if (!mounted || nav == null) return;
        // עדכון רק אם הנתונים באמת השתנו (צירים, סטטוס, הגדרות למידה)
        if (_currentNavigation.routes != nav.routes ||
            _currentNavigation.status != nav.status ||
            _currentNavigation.learningSettings != nav.learningSettings) {
          setState(() {
            _currentNavigation = nav;
            _learningStarted = nav.status == 'learning';
            _initLearningSettings();
          });
        }
      },
      onError: (e) {
        print('DEBUG TrainingMode: navigation listener error: $e');
      },
    );
  }

  // ===========================================================================
  // Navigation polling fallback — direct Firestore .get() every 10 seconds
  // (bypasses Windows threading bug with .snapshots() listeners)
  // ===========================================================================

  void _startNavigationPolling() {
    // שאילתה ראשונית מיידית
    _pollNavigation();
    _navigationPollTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _pollNavigation(),
    );
  }

  Future<void> _pollNavigation() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection(AppConstants.navigationsCollection)
          .doc(widget.navigation.id)
          .get();

      if (!mounted || !snapshot.exists || snapshot.data() == null) return;

      final data = snapshot.data()!;
      data['id'] = snapshot.id;
      final nav = domain.Navigation.fromMap(data);

      // עדכון רק אם הנתונים באמת השתנו (צירים, סטטוס, הגדרות למידה)
      if (_currentNavigation.routes != nav.routes ||
          _currentNavigation.status != nav.status ||
          _currentNavigation.learningSettings != nav.learningSettings) {
        setState(() {
          _currentNavigation = nav;
          _learningStarted = nav.status == 'learning';
          _initLearningSettings();
        });
        // עדכון DB מקומי כדי לשמור על סנכרון Drift
        await _navRepo.updateLocalFromFirestore(nav);
      }
    } catch (e) {
      print('DEBUG TrainingMode: poll error: $e');
    }
  }

  Future<void> _approveRoute(String navigatorId) async {
    final route = _currentNavigation.routes[navigatorId];
    if (route == null || route.approvalStatus != 'pending_approval') return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('אישור ציר'),
        content: Text('האם לאשר את הציר של $navigatorId?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.green),
            child: const Text('אשר'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final updatedRoutes = Map<String, domain.AssignedRoute>.from(_currentNavigation.routes);
      updatedRoutes[navigatorId] = updatedRoutes[navigatorId]!.copyWith(approvalStatus: 'approved');
      final updatedNav = _currentNavigation.copyWith(routes: updatedRoutes, updatedAt: DateTime.now());
      await _navRepo.update(updatedNav);
      setState(() => _currentNavigation = updatedNav);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('הציר של $navigatorId אושר'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Future<void> _rejectRoute(String navigatorId) async {
    final notesController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('פסילת ציר'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('פסילת הציר של $navigatorId.\nרשום הערות ותיקונים למנווט:'),
            const SizedBox(height: 12),
            TextField(
              controller: notesController,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'הערות ותיקונים...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('פסול ציר'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final updatedRoutes = Map<String, domain.AssignedRoute>.from(_currentNavigation.routes);
    updatedRoutes[navigatorId] = updatedRoutes[navigatorId]!.copyWith(
      approvalStatus: 'rejected',
      rejectionNotes: notesController.text.isNotEmpty ? notesController.text : null,
    );
    final updatedNav = _currentNavigation.copyWith(routes: updatedRoutes, updatedAt: DateTime.now());
    await _navRepo.update(updatedNav);
    setState(() => _currentNavigation = updatedNav);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('הציר של $navigatorId נפסל'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }


  Future<void> _startLearning() async {
    final updatedNav = _currentNavigation.copyWith(
      status: 'learning',
      updatedAt: DateTime.now(),
    );
    await _navRepo.update(updatedNav);
    _currentNavigation = updatedNav;

    if (mounted) {
      setState(() => _learningStarted = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('מצב למידה הופעל — המנווטים יראו את המסך שלהם'),
          backgroundColor: Colors.blue,
        ),
      );
    }
  }

  Future<void> _finishLearning() async {
    final allApproved = _currentNavigation.routes.values.every((r) => r.isApproved);

    if (!allApproved) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('לא כל הצירים אושרו'),
          content: const Text('חלק מהצירים עדיין לא אושרו. האם ברצונך לסיים את הלמידה בכל זאת?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('ביטול'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.orange),
              child: const Text('סיים בכל זאת'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
    }

    // עדכון הניווט - סימון שהלמידה הסתיימה + החזרת סטטוס להכנה
    final updatedNav = _currentNavigation.copyWith(
      status: 'preparation',
      trainingStartTime: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await _navRepo.update(updatedNav);
    _currentNavigation = updatedNav;

    if (mounted) {
      Navigator.pop(context, true);
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
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        // הלמידה תמשיך לרוץ ברקע — רק כפתור "סיום למידה" משנה סטטוס
        // Back button לא עושה כלום מלבד לצאת מהמסך
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.navigation.name),
              Text(
                'מצב למידה',
                style: const TextStyle(fontSize: 14),
              ),
            ],
          ),
          backgroundColor: Theme.of(context).primaryColor,
          foregroundColor: Colors.white,
          actions: [
            if (widget.isCommander)
              IconButton(
                icon: const Icon(Icons.delete_forever),
                tooltip: 'מחיקת ניווט',
                onPressed: _deleteNavigation,
              ),
          ],
          bottom: TabBar(
            controller: _tabController,
            labelColor: Colors.white,
            tabs: const [
              Tab(icon: Icon(Icons.settings), text: 'הגדרות'),
              Tab(icon: Icon(Icons.table_chart), text: 'טבלה'),
              Tab(icon: Icon(Icons.map), text: 'מפה'),
            ],
          ),
        ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildSettingsView(),
                _buildTableView(),
                _buildMapView(),
              ],
            ),
      bottomNavigationBar: widget.isCommander
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // כפתור התחלת למידה
                    ElevatedButton.icon(
                      onPressed: _learningStarted ? null : _startLearning,
                      icon: Icon(_learningStarted ? Icons.check : Icons.play_arrow),
                      label: Text(
                        _learningStarted ? 'למידה פעילה' : 'התחלת למידה',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _learningStarted ? Colors.grey : Colors.blue,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // כפתור סיום למידה
                    ElevatedButton.icon(
                      onPressed: _learningStarted ? _finishLearning : null,
                      icon: const Icon(Icons.check_circle),
                      label: const Text(
                        'סיום למידה',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
      ),
    );
  }

  Widget _buildSettingsView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.school, color: Colors.blue[700]),
                  const SizedBox(width: 8),
                  Text(
                    'הגדרות למידה',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              SwitchListTile(
                title: const Text('אפשר למידה עם פלאפונים'),
                value: _enableLearningWithPhones,
                onChanged: (value) {
                  setState(() => _enableLearningWithPhones = value);
                },
              ),

              if (_enableLearningWithPhones) ...[
                SwitchListTile(
                  title: const Text('אפשר לראות את כל הנקודות של כל המנווטים'),
                  value: _showAllCheckpoints,
                  onChanged: (value) {
                    setState(() => _showAllCheckpoints = value);
                  },
                ),
                SwitchListTile(
                  title: const Text('הצגת פרטי ניווט'),
                  value: _showNavigationDetails,
                  onChanged: (value) {
                    setState(() => _showNavigationDetails = value);
                  },
                ),
                SwitchListTile(
                  title: const Text('הצגת צירים'),
                  value: _showLearningRoutes,
                  onChanged: (value) {
                    setState(() => _showLearningRoutes = value);
                  },
                ),
                SwitchListTile(
                  title: const Text('אפשר עריכת צירים'),
                  value: _allowRouteEditing,
                  onChanged: (value) {
                    setState(() => _allowRouteEditing = value);
                  },
                ),
                SwitchListTile(
                  title: const Text('אפשר סיפור דרך'),
                  value: _allowRouteNarration,
                  onChanged: (value) {
                    setState(() => _allowRouteNarration = value);
                  },
                ),
              ],

              const Divider(),

              SwitchListTile(
                title: const Text('הגדר זמני לימוד אוטומטיים'),
                value: _autoLearningTimes,
                onChanged: (value) {
                  setState(() => _autoLearningTimes = value);
                },
              ),

              if (_autoLearningTimes) ...[
                const SizedBox(height: 16),
                ListTile(
                  title: const Text('תאריך לימוד'),
                  subtitle: Text(
                    '${_learningDate.day}/${_learningDate.month}/${_learningDate.year}',
                  ),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: _learningDate,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 60)),
                    );
                    if (date != null) {
                      setState(() => _learningDate = date);
                    }
                  },
                ),
                ListTile(
                  title: const Text('שעת התחלה'),
                  subtitle: Text(_learningStartTime.format(context)),
                  trailing: const Icon(Icons.access_time),
                  onTap: () async {
                    final time = await showTimePicker(
                      context: context,
                      initialTime: _learningStartTime,
                    );
                    if (time != null) {
                      setState(() => _learningStartTime = time);
                    }
                  },
                ),
                ListTile(
                  title: const Text('שעת סיום'),
                  subtitle: Text(_learningEndTime.format(context)),
                  trailing: const Icon(Icons.access_time),
                  onTap: () async {
                    final time = await showTimePicker(
                      context: context,
                      initialTime: _learningEndTime,
                    );
                    if (time != null) {
                      setState(() => _learningEndTime = time);
                    }
                  },
                ),
              ],

              // סטטוס למידה אוטומטית
              if (_autoLearningTimes && _currentNavigation.learningSettings.autoLearningTimes) ...[
                const SizedBox(height: 16),
                Builder(builder: (_) {
                  final now = DateTime.now();
                  final ls = _currentNavigation.learningSettings;
                  DateTime? startDt;
                  DateTime? endDt;
                  if (ls.learningDate != null && ls.learningStartTime != null && ls.learningEndTime != null) {
                    final sp = ls.learningStartTime!.split(':');
                    final ep = ls.learningEndTime!.split(':');
                    if (sp.length == 2 && ep.length == 2) {
                      startDt = DateTime(ls.learningDate!.year, ls.learningDate!.month, ls.learningDate!.day,
                          int.tryParse(sp[0]) ?? 0, int.tryParse(sp[1]) ?? 0);
                      endDt = DateTime(ls.learningDate!.year, ls.learningDate!.month, ls.learningDate!.day,
                          int.tryParse(ep[0]) ?? 0, int.tryParse(ep[1]) ?? 0);
                    }
                  }

                  final String statusText;
                  final Color statusColor;
                  final IconData statusIcon;

                  if (startDt == null || endDt == null) {
                    statusText = 'זמנים לא הוגדרו כראוי';
                    statusColor = Colors.orange;
                    statusIcon = Icons.warning;
                  } else if (endDt.isBefore(now)) {
                    statusText = 'זמן הלמידה האוטומטית עבר';
                    statusColor = Colors.grey;
                    statusIcon = Icons.history;
                  } else if (_learningStarted) {
                    statusText = 'למידה פעילה — סיום אוטומטי ב-${ls.learningEndTime}';
                    statusColor = Colors.blue;
                    statusIcon = Icons.timer;
                  } else if (startDt.isAfter(now)) {
                    statusText = 'התחלה אוטומטית ב-${ls.learningStartTime} (${ls.learningDate!.day}/${ls.learningDate!.month})';
                    statusColor = Colors.green;
                    statusIcon = Icons.schedule;
                  } else {
                    statusText = 'זמן ההתחלה עבר — ניתן להפעיל ידנית';
                    statusColor = Colors.orange;
                    statusIcon = Icons.warning;
                  }

                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: statusColor.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      children: [
                        Icon(statusIcon, color: statusColor, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(statusText,
                            style: TextStyle(color: statusColor, fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],

              const SizedBox(height: 24),

              // כפתור שמירה
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _saveLearningSettings,
                  icon: const Icon(Icons.save),
                  label: const Text(
                    'שמור הגדרות',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 48),
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

  Future<void> _saveLearningSettings() async {
    final newSettings = LearningSettings(
      enabledWithPhones: _enableLearningWithPhones,
      showAllCheckpoints: _showAllCheckpoints,
      showNavigationDetails: _showNavigationDetails,
      showRoutes: _showLearningRoutes,
      allowRouteEditing: _allowRouteEditing,
      allowRouteNarration: _allowRouteNarration,
      autoLearningTimes: _autoLearningTimes,
      learningDate: _autoLearningTimes ? _learningDate : null,
      learningStartTime: _autoLearningTimes
          ? '${_learningStartTime.hour}:${_learningStartTime.minute}'
          : null,
      learningEndTime: _autoLearningTimes
          ? '${_learningEndTime.hour}:${_learningEndTime.minute}'
          : null,
    );

    if (newSettings == _currentNavigation.learningSettings) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('אין שינויים לשמור')),
        );
      }
      return;
    }

    // אזהרה אם הלמידה כבר פעילה
    if (_learningStarted) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('הלמידה כבר פעילה'),
          content: const Text('השינויים ייכנסו לתוקף מיידי. האם להמשיך?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ביטול'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: Colors.orange),
              child: const Text('שמור בכל זאת'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    try {
      final updatedNav = _currentNavigation.copyWith(
        learningSettings: newSettings,
        updatedAt: DateTime.now(),
      );
      await _navRepo.update(updatedNav);
      setState(() => _currentNavigation = updatedNav);
      _scheduleAutoLearning();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('הגדרות הלמידה נשמרו בהצלחה'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בשמירה: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildTableView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // כותרת
          Row(
            children: [
              Icon(Icons.school, color: Colors.blue[700]),
              const SizedBox(width: 8),
              Text(
                'צירי מנווטים - מצב למידה',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'המנווטים עורכים את הצירים. מפקדים יכולים לאשר או לדחות.',
            style: TextStyle(color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),

          // מקרא
          if (widget.isCommander) _buildLegend(),
          const SizedBox(height: 16),

          // טבלת צירים
          ..._currentNavigation.routes.entries.map((entry) {
            final navigatorId = entry.key;
            final route = entry.value;

            return _buildRouteCard(navigatorId, route);
          }),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    return Card(
      color: Colors.grey[100],
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildLegendItem('לא הוגש', Colors.grey),
            _buildLegendItem('ממתין', Colors.orange),
            _buildLegendItem('מאושר', Colors.green),
            _buildLegendItem('נפסל', Colors.red),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  void _viewNavigatorRoute(String navigatorId, domain.AssignedRoute route) {
    // בניית ציר רפרנס: התחלה → נקודות ציון → סיום
    final referencePoints = _buildReferenceRoute(route);

    // ציר שצייר המנווט (אם יש)
    final hasPlannedPath = route.plannedPath.isNotEmpty;
    final plannedPathPoints = hasPlannedPath
        ? route.plannedPath.map((c) => LatLng(c.lat, c.lng)).toList()
        : <LatLng>[];

    // נקודות ציון של המנווט לפי סדר ה-sequence
    final routeCheckpoints = <Checkpoint>[];
    for (final cpId in route.sequence) {
      try {
        routeCheckpoints.add(_checkpoints.firstWhere((cp) => cp.id == cpId));
      } catch (_) {}
    }

    // נקודות התחלה/סיום
    Checkpoint? startCheckpoint;
    Checkpoint? endCheckpoint;
    if (route.startPointId != null) {
      try {
        startCheckpoint = _checkpoints.firstWhere((cp) => cp.id == route.startPointId);
      } catch (_) {}
    }
    if (route.endPointId != null) {
      try {
        endCheckpoint = _checkpoints.firstWhere((cp) => cp.id == route.endPointId);
      } catch (_) {}
    }

    final allPoints = [...referencePoints, ...plannedPathPoints];
    final center = allPoints.isNotEmpty
        ? LatLngBounds.fromPoints(allPoints).center
        : const LatLng(32.0853, 34.7818);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _RouteViewScreen(
          navigatorId: navigatorId,
          referencePoints: referencePoints,
          plannedPathPoints: plannedPathPoints,
          hasPlannedPath: hasPlannedPath,
          center: center,
          routeCheckpoints: routeCheckpoints,
          startCheckpoint: startCheckpoint,
          endCheckpoint: endCheckpoint,
          boundary: _boundary,
          safetyPoints: _safetyPoints,
        ),
      ),
    );
  }

  Widget _buildRouteCard(String navigatorId, domain.AssignedRoute route) {
    final approvalStatus = route.approvalStatus;

    final Color statusColor;
    final IconData statusIcon;
    final String statusText;
    switch (approvalStatus) {
      case 'approved':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        statusText = 'מאושר';
        break;
      case 'pending_approval':
        statusColor = Colors.orange;
        statusIcon = Icons.hourglass_top;
        statusText = 'ממתין לאישור';
        break;
      case 'rejected':
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        statusText = 'נפסל';
        break;
      default: // not_submitted
        statusColor = Colors.grey;
        statusIcon = Icons.radio_button_unchecked;
        statusText = 'לא הוגש';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // שורה עליונה: מנווט + סטטוס
            Row(
              children: [
                Expanded(
                  child: Text(
                    navigatorId,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: statusColor, width: 2),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 16, color: statusColor),
                      const SizedBox(width: 6),
                      Text(
                        statusText,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // פרטי הציר
            Row(
              children: [
                Icon(Icons.route, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 6),
                Text(
                  'אורך ציר: ${route.routeLengthKm.toStringAsFixed(2)} ק"מ',
                  style: TextStyle(color: Colors.grey[700]),
                ),
                const SizedBox(width: 16),
                Icon(Icons.place, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 6),
                Text(
                  '${route.sequence.length} נקודות',
                  style: TextStyle(color: Colors.grey[700]),
                ),
              ],
            ),

            // כפתורי פעולה - רק למפקדים
            if (widget.isCommander) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  // כפתור אישור — פעיל רק אם pending_approval
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: approvalStatus == 'pending_approval'
                          ? () => _approveRoute(navigatorId)
                          : null,
                      icon: const Icon(Icons.check_circle, size: 18),
                      label: const Text('אשר ציר'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.green,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // כפתור פסילת ציר
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: (approvalStatus == 'pending_approval' || approvalStatus == 'approved')
                          ? () => _rejectRoute(navigatorId)
                          : null,
                      icon: const Icon(Icons.cancel, size: 18),
                      label: const Text('פסילת ציר'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // כפתור צפה בציר
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _viewNavigatorRoute(navigatorId, route),
                      icon: const Icon(Icons.visibility, size: 18),
                      label: const Text('צפה בציר'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.blue,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMapView() {
    return Column(
      children: [
        // בורר מנווטים
        Container(
          padding: const EdgeInsets.all(8),
          color: Colors.grey[100],
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _currentNavigation.routes.entries.map((entry) {
                final navigatorId = entry.key;
                final approvalStatus = entry.value.approvalStatus;
                final Color chipColor;
                final IconData chipIcon;
                switch (approvalStatus) {
                  case 'approved':
                    chipColor = Colors.green;
                    chipIcon = Icons.check_circle;
                    break;
                  case 'pending_approval':
                    chipColor = Colors.orange;
                    chipIcon = Icons.hourglass_top;
                    break;
                  case 'rejected':
                    chipColor = Colors.red;
                    chipIcon = Icons.cancel;
                    break;
                  default:
                    chipColor = Colors.grey;
                    chipIcon = Icons.radio_button_unchecked;
                }
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FilterChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(navigatorId),
                        const SizedBox(width: 6),
                        Icon(chipIcon, size: 14, color: chipColor),
                      ],
                    ),
                    selected: _selectedNavigators[navigatorId] ?? false,
                    onSelected: (selected) {
                      setState(() {
                        _selectedNavigators[navigatorId] = selected;
                      });
                    },
                  ),
                );
              }).toList(),
            ),
          ),
        ),

        // מפה
        Expanded(
          child: Stack(
            children: [
              MapWithTypeSelector(
                showTypeSelector: false,
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: widget.navigation.displaySettings.openingLat != null &&
                          widget.navigation.displaySettings.openingLng != null
                      ? LatLng(
                          widget.navigation.displaySettings.openingLat!,
                          widget.navigation.displaySettings.openingLng!,
                        )
                      : const LatLng(32.0853, 34.7818),
                  initialZoom: 13.0,
                  onTap: (tapPosition, point) {
                    if (_measureMode) {
                      setState(() => _measurePoints.add(point));
                      return;
                    }
                  },
                ),
                layers: [
                  // גבול גזרה (שחור)
                  if (_showGG && _boundary != null && _boundary!.coordinates.isNotEmpty)
                    PolygonLayer(
                      polygons: [
                        Polygon(
                          points: _boundary!.coordinates
                              .map((coord) => LatLng(coord.lat, coord.lng))
                              .toList(),
                          color: Colors.black.withValues(alpha: 0.1 * _ggOpacity),
                          borderColor: Colors.black.withValues(alpha: _ggOpacity),
                          borderStrokeWidth: _boundary!.strokeWidth,
                          isFilled: true,
                        ),
                      ],
                    ),

                  // צירי המנווטים
                  if (_showRoutes)
                    ..._buildRoutePolylines(),

                  // נקודות ציון רלוונטיות לניווט בלבד (התחלה/סיום/נקודות מנווטים)
                  if (_showNZ)
                    MarkerLayer(
                      markers: _buildNavigationMarkers().map((m) => Marker(
                        point: m.point,
                        width: m.width,
                        height: m.height,
                        child: Opacity(opacity: _nzOpacity, child: m.child),
                      )).toList(),
                    ),

                  // נת"ב - נקודות
                  if (_showNB && _safetyPoints.where((p) => p.type == 'point').isNotEmpty)
                    MarkerLayer(
                      markers: _safetyPoints
                          .where((p) => p.type == 'point' && p.coordinates != null)
                          .map((point) => Marker(
                                point: LatLng(point.coordinates!.lat, point.coordinates!.lng),
                                width: 30,
                                height: 30,
                                child: Opacity(
                                  opacity: _nbOpacity,
                                  child: const Icon(Icons.warning, color: Colors.red, size: 30),
                                ),
                              ))
                          .toList(),
                    ),
                  // נת"ב - פוליגונים
                  if (_showNB && _safetyPoints.where((p) => p.type == 'polygon').isNotEmpty)
                    PolygonLayer(
                      polygons: _safetyPoints
                          .where((p) => p.type == 'polygon' && p.polygonCoordinates != null)
                          .map((point) => Polygon(
                                points: point.polygonCoordinates!.map((c) => LatLng(c.lat, c.lng)).toList(),
                                color: Colors.red.withValues(alpha: 0.2 * _nbOpacity),
                                borderColor: Colors.red.withValues(alpha: _nbOpacity),
                                borderStrokeWidth: 2,
                                isFilled: true,
                              ))
                          .toList(),
                    ),

                  // שכבות מדידה
                  ...MapControls.buildMeasureLayers(_measurePoints),
                ],
              ),
              MapControls(
                mapController: _mapController,
                onFullscreen: () {
                  final camera = _mapController.camera;
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => FullscreenMapScreen(
                      title: 'מצב אימון',
                      initialCenter: camera.center,
                      initialZoom: camera.zoom,
                      layers: [
                        if (_showGG && _boundary != null && _boundary!.coordinates.isNotEmpty)
                          PolygonLayer(
                            polygons: [
                              Polygon(
                                points: _boundary!.coordinates.map((coord) => LatLng(coord.lat, coord.lng)).toList(),
                                color: Colors.black.withValues(alpha: 0.1 * _ggOpacity),
                                borderColor: Colors.black.withValues(alpha: _ggOpacity),
                                borderStrokeWidth: _boundary!.strokeWidth,
                                isFilled: true,
                              ),
                            ],
                          ),
                        if (_showRoutes) ..._buildRoutePolylines(),
                        if (_showNZ)
                          MarkerLayer(
                            markers: _buildNavigationMarkers().map((m) => Marker(
                              point: m.point,
                              width: m.width,
                              height: m.height,
                              child: Opacity(opacity: _nzOpacity, child: m.child),
                            )).toList(),
                          ),
                        if (_showNB && _safetyPoints.where((p) => p.type == 'point').isNotEmpty)
                          MarkerLayer(
                            markers: _safetyPoints
                                .where((p) => p.type == 'point' && p.coordinates != null)
                                .map((point) => Marker(
                                      point: LatLng(point.coordinates!.lat, point.coordinates!.lng),
                                      width: 30,
                                      height: 30,
                                      child: Opacity(
                                        opacity: _nbOpacity,
                                        child: const Icon(Icons.warning, color: Colors.red, size: 30),
                                      ),
                                    ))
                                .toList(),
                          ),
                        if (_showNB && _safetyPoints.where((p) => p.type == 'polygon').isNotEmpty)
                          PolygonLayer(
                            polygons: _safetyPoints
                                .where((p) => p.type == 'polygon' && p.polygonCoordinates != null)
                                .map((point) => Polygon(
                                      points: point.polygonCoordinates!.map((c) => LatLng(c.lat, c.lng)).toList(),
                                      color: Colors.red.withValues(alpha: 0.2 * _nbOpacity),
                                      borderColor: Colors.red.withValues(alpha: _nbOpacity),
                                      borderStrokeWidth: 2,
                                      isFilled: true,
                                    ))
                                .toList(),
                          ),
                      ],
                    ),
                  ));
                },
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
                    id: 'gg', label: 'גבול גזרה', color: Colors.black,
                    visible: _showGG,
                    onVisibilityChanged: (v) => setState(() => _showGG = v),
                    opacity: _ggOpacity,
                    onOpacityChanged: (v) => setState(() => _ggOpacity = v),
                  ),
                  MapLayerConfig(
                    id: 'nz', label: 'נקודות ציון', color: Colors.blue,
                    visible: _showNZ,
                    onVisibilityChanged: (v) => setState(() => _showNZ = v),
                    opacity: _nzOpacity,
                    onOpacityChanged: (v) => setState(() => _nzOpacity = v),
                  ),
                  MapLayerConfig(
                    id: 'nb', label: 'נקודות בטיחות', color: Colors.red,
                    visible: _showNB,
                    onVisibilityChanged: (v) => setState(() => _showNB = v),
                    opacity: _nbOpacity,
                    onOpacityChanged: (v) => setState(() => _nbOpacity = v),
                  ),
                  MapLayerConfig(
                    id: 'routes', label: 'צירים', color: Colors.orange,
                    visible: _showRoutes,
                    onVisibilityChanged: (v) => setState(() => _showRoutes = v),
                    opacity: _routesOpacity,
                    onOpacityChanged: (v) => setState(() => _routesOpacity = v),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// בניית ציר רפרנס (מנקודות ציון) למנווט
  List<LatLng> _buildReferenceRoute(domain.AssignedRoute route) {
    final points = <LatLng>[];

    if (route.startPointId != null) {
      try {
        final startPoint = _checkpoints.firstWhere((cp) => cp.id == route.startPointId);
        if (!startPoint.isPolygon && startPoint.coordinates != null) {
          points.add(LatLng(startPoint.coordinates!.lat, startPoint.coordinates!.lng));
        }
      } catch (_) {}
    }

    for (final checkpointId in route.sequence) {
      try {
        final checkpoint = _checkpoints.firstWhere((cp) => cp.id == checkpointId);
        if (!checkpoint.isPolygon && checkpoint.coordinates != null) {
          points.add(LatLng(checkpoint.coordinates!.lat, checkpoint.coordinates!.lng));
        }
      } catch (_) {}
    }

    if (route.endPointId != null && route.endPointId != route.startPointId) {
      try {
        final endPoint = _checkpoints.firstWhere((cp) => cp.id == route.endPointId);
        if (!endPoint.isPolygon && endPoint.coordinates != null) {
          points.add(LatLng(endPoint.coordinates!.lat, endPoint.coordinates!.lng));
        }
      } catch (_) {}
    }

    return points;
  }

  /// בניית markers לנקודות רלוונטיות לניווט: התחלה (ירוק H), סיום (אדום S), נקודות מנווטים (כחול ממוספר)
  List<Marker> _buildNavigationMarkers() {
    final startPointIds = <String>{};
    final endPointIds = <String>{};
    final routeCheckpointIds = <String>{};

    for (final route in _currentNavigation.routes.values) {
      if (route.startPointId != null) startPointIds.add(route.startPointId!);
      if (route.endPointId != null) endPointIds.add(route.endPointId!);
      routeCheckpointIds.addAll(route.sequence);
    }

    final markers = <Marker>[];

    // נקודות התחלה (ירוק H)
    for (final spId in startPointIds) {
      try {
        final cp = _checkpoints.firstWhere((c) => c.id == spId);
        if (cp.isPolygon || cp.coordinates == null) continue;
        markers.add(Marker(
          point: LatLng(cp.coordinates!.lat, cp.coordinates!.lng),
          width: 32,
          height: 32,
          child: Tooltip(
            message: 'התחלה: ${cp.name}',
            child: Container(
              decoration: BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Center(
                child: Text('H', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ));
      } catch (_) {}
    }

    // נקודות ציון של המנווטים (כחול ממוספר) — בלי התחלה/סיום
    for (final cpId in routeCheckpointIds) {
      if (startPointIds.contains(cpId) || endPointIds.contains(cpId)) continue;
      try {
        final cp = _checkpoints.firstWhere((c) => c.id == cpId);
        if (cp.isPolygon || cp.coordinates == null) continue;
        markers.add(Marker(
          point: LatLng(cp.coordinates!.lat, cp.coordinates!.lng),
          width: 32,
          height: 32,
          child: Tooltip(
            message: cp.name,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.blue,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Center(
                child: Text(
                  '${cp.sequenceNumber}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ));
      } catch (_) {}
    }

    // נקודות סיום (אדום S)
    for (final epId in endPointIds) {
      if (startPointIds.contains(epId)) continue; // אותה נקודה גם התחלה וגם סיום
      try {
        final cp = _checkpoints.firstWhere((c) => c.id == epId);
        if (cp.isPolygon || cp.coordinates == null) continue;
        markers.add(Marker(
          point: LatLng(cp.coordinates!.lat, cp.coordinates!.lng),
          width: 32,
          height: 32,
          child: Tooltip(
            message: 'סיום: ${cp.name}',
            child: Container(
              decoration: BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Center(
                child: Text('S', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ));
      } catch (_) {}
    }

    return markers;
  }

  List<Widget> _buildRoutePolylines() {
    List<Widget> polylines = [];

    for (final entry in _currentNavigation.routes.entries) {
      final navigatorId = entry.key;
      final route = entry.value;

      if (_selectedNavigators[navigatorId] != true) continue;

      // אם יש ציר מעודכן שהמנווט צייר — מציגים אותו; אחרת רפרנס
      final List<LatLng> points;
      if (route.plannedPath.isNotEmpty) {
        points = route.plannedPath.map((c) => LatLng(c.lat, c.lng)).toList();
      } else {
        points = _buildReferenceRoute(route);
      }

      if (points.isNotEmpty) {
        polylines.add(
          PolylineLayer(
            polylines: [
              Polyline(
                points: points,
                strokeWidth: 3.0,
                color: Colors.blue.withValues(alpha: _routesOpacity),
              ),
            ],
          ),
        );
      }
    }

    return polylines;
  }
}

/// מסך צפייה בציר מנווט — עם נקודות התחלה/סיום ו-MapControls סטנדרטי
class _RouteViewScreen extends StatefulWidget {
  final String navigatorId;
  final List<LatLng> referencePoints;
  final List<LatLng> plannedPathPoints;
  final bool hasPlannedPath;
  final LatLng center;
  final List<Checkpoint> routeCheckpoints;
  final Checkpoint? startCheckpoint;
  final Checkpoint? endCheckpoint;
  final Boundary? boundary;
  final List<SafetyPoint> safetyPoints;

  const _RouteViewScreen({
    required this.navigatorId,
    required this.referencePoints,
    required this.plannedPathPoints,
    required this.hasPlannedPath,
    required this.center,
    required this.routeCheckpoints,
    this.startCheckpoint,
    this.endCheckpoint,
    this.boundary,
    this.safetyPoints = const [],
  });

  @override
  State<_RouteViewScreen> createState() => _RouteViewScreenState();
}

class _RouteViewScreenState extends State<_RouteViewScreen> {
  final MapController _mapController = MapController();
  bool _measureMode = false;
  final List<LatLng> _measurePoints = [];

  // שכבות
  bool _showGG = true;
  double _ggOpacity = 1.0;
  bool _showNZ = true;
  double _nzOpacity = 1.0;
  bool _showNB = false;
  double _nbOpacity = 1.0;
  bool _showRoutes = true;
  double _routesOpacity = 1.0;

  @override
  Widget build(BuildContext context) {
    final allPoints = [...widget.referencePoints, ...widget.plannedPathPoints];
    final bounds = allPoints.length > 1 ? LatLngBounds.fromPoints(allPoints) : null;

    // בניית markers: התחלה (ירוק H), נקודות ציון (כחול ממוספר), סיום (אדום S)
    final markers = <Marker>[];

    if (widget.startCheckpoint != null && !widget.startCheckpoint!.isPolygon && widget.startCheckpoint!.coordinates != null) {
      markers.add(Marker(
        point: widget.startCheckpoint!.coordinates!.toLatLng(),
        width: 32,
        height: 32,
        child: Tooltip(
          message: 'התחלה: ${widget.startCheckpoint!.name}',
          child: Container(
            decoration: BoxDecoration(
              color: Colors.green,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: const Center(
              child: Text('H', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      ));
    }

    for (var i = 0; i < widget.routeCheckpoints.length; i++) {
      final cp = widget.routeCheckpoints[i];
      if (cp.isPolygon || cp.coordinates == null) continue;
      markers.add(Marker(
        point: cp.coordinates!.toLatLng(),
        width: 32,
        height: 32,
        child: Tooltip(
          message: cp.name,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.blue,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: Center(
              child: Text(
                '${i + 1}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ));
    }

    if (widget.endCheckpoint != null && !widget.endCheckpoint!.isPolygon && widget.endCheckpoint!.coordinates != null) {
      markers.add(Marker(
        point: widget.endCheckpoint!.coordinates!.toLatLng(),
        width: 32,
        height: 32,
        child: Tooltip(
          message: 'סיום: ${widget.endCheckpoint!.name}',
          child: Container(
            decoration: BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: const Center(
              child: Text('S', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      ));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('ציר של ${widget.navigatorId}'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          MapWithTypeSelector(
            mapController: _mapController,
            showTypeSelector: false,
            options: MapOptions(
              initialCenter: widget.center,
              initialZoom: 14.0,
              initialCameraFit: bounds != null
                  ? CameraFit.bounds(
                      bounds: bounds,
                      padding: const EdgeInsets.all(50),
                    )
                  : null,
              onTap: (tapPosition, point) {
                if (_measureMode) {
                  setState(() => _measurePoints.add(point));
                }
              },
            ),
            layers: [
              // גבול גזרה (שחור)
              if (_showGG && widget.boundary != null && widget.boundary!.coordinates.isNotEmpty)
                PolygonLayer(
                  polygons: [
                    Polygon(
                      points: widget.boundary!.coordinates
                          .map((coord) => LatLng(coord.lat, coord.lng))
                          .toList(),
                      color: Colors.black.withValues(alpha: 0.1 * _ggOpacity),
                      borderColor: Colors.black.withValues(alpha: _ggOpacity),
                      borderStrokeWidth: widget.boundary!.strokeWidth,
                      isFilled: true,
                    ),
                  ],
                ),
              // ציר רפרנס (כחול בהיר)
              if (_showRoutes && widget.referencePoints.length > 1)
                PolylineLayer(polylines: [
                  Polyline(
                    points: widget.referencePoints,
                    color: Colors.blue.withValues(alpha: 0.3 * _routesOpacity),
                    strokeWidth: 2.0,
                  ),
                ]),
              // ציר שצייר המנווט (כחול)
              if (_showRoutes && widget.hasPlannedPath && widget.plannedPathPoints.isNotEmpty)
                PolylineLayer(polylines: [
                  Polyline(
                    points: widget.plannedPathPoints,
                    color: Colors.blue.withValues(alpha: _routesOpacity),
                    strokeWidth: 3.0,
                  ),
                ]),
              // נת"ב - נקודות
              if (_showNB && widget.safetyPoints.where((p) => p.type == 'point').isNotEmpty)
                MarkerLayer(
                  markers: widget.safetyPoints
                      .where((p) => p.type == 'point' && p.coordinates != null)
                      .map((point) => Marker(
                            point: LatLng(point.coordinates!.lat, point.coordinates!.lng),
                            width: 30,
                            height: 30,
                            child: Opacity(
                              opacity: _nbOpacity,
                              child: const Icon(Icons.warning, color: Colors.red, size: 30),
                            ),
                          ))
                      .toList(),
                ),
              // נת"ב - פוליגונים
              if (_showNB && widget.safetyPoints.where((p) => p.type == 'polygon').isNotEmpty)
                PolygonLayer(
                  polygons: widget.safetyPoints
                      .where((p) => p.type == 'polygon' && p.polygonCoordinates != null)
                      .map((point) => Polygon(
                            points: point.polygonCoordinates!.map((c) => LatLng(c.lat, c.lng)).toList(),
                            color: Colors.red.withValues(alpha: 0.2 * _nbOpacity),
                            borderColor: Colors.red.withValues(alpha: _nbOpacity),
                            borderStrokeWidth: 2,
                            isFilled: true,
                          ))
                      .toList(),
                ),
              // נקודות ציון
              if (_showNZ)
                MarkerLayer(markers: markers.map((m) => Marker(
                  point: m.point,
                  width: m.width,
                  height: m.height,
                  child: Opacity(opacity: _nzOpacity, child: m.child),
                )).toList()),
              ...MapControls.buildMeasureLayers(_measurePoints),
            ],
          ),
          MapControls(
            mapController: _mapController,
            onFullscreen: () {
              final camera = _mapController.camera;
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => FullscreenMapScreen(
                  title: 'מצב אימון',
                  initialCenter: camera.center,
                  initialZoom: camera.zoom,
                  layers: [
                    if (_showGG && widget.boundary != null && widget.boundary!.coordinates.isNotEmpty)
                      PolygonLayer(
                        polygons: [
                          Polygon(
                            points: widget.boundary!.coordinates.map((coord) => LatLng(coord.lat, coord.lng)).toList(),
                            color: Colors.black.withValues(alpha: 0.1 * _ggOpacity),
                            borderColor: Colors.black.withValues(alpha: _ggOpacity),
                            borderStrokeWidth: widget.boundary!.strokeWidth,
                            isFilled: true,
                          ),
                        ],
                      ),
                    if (_showRoutes && widget.referencePoints.length > 1)
                      PolylineLayer(polylines: [
                        Polyline(
                          points: widget.referencePoints,
                          color: Colors.blue.withValues(alpha: 0.3 * _routesOpacity),
                          strokeWidth: 2.0,
                        ),
                      ]),
                    if (_showRoutes && widget.hasPlannedPath && widget.plannedPathPoints.isNotEmpty)
                      PolylineLayer(polylines: [
                        Polyline(
                          points: widget.plannedPathPoints,
                          color: Colors.blue.withValues(alpha: _routesOpacity),
                          strokeWidth: 3.0,
                        ),
                      ]),
                    if (_showNB && widget.safetyPoints.where((p) => p.type == 'point').isNotEmpty)
                      MarkerLayer(
                        markers: widget.safetyPoints
                            .where((p) => p.type == 'point' && p.coordinates != null)
                            .map((point) => Marker(
                                  point: LatLng(point.coordinates!.lat, point.coordinates!.lng),
                                  width: 30,
                                  height: 30,
                                  child: Opacity(
                                    opacity: _nbOpacity,
                                    child: const Icon(Icons.warning, color: Colors.red, size: 30),
                                  ),
                                ))
                            .toList(),
                      ),
                    if (_showNB && widget.safetyPoints.where((p) => p.type == 'polygon').isNotEmpty)
                      PolygonLayer(
                        polygons: widget.safetyPoints
                            .where((p) => p.type == 'polygon' && p.polygonCoordinates != null)
                            .map((point) => Polygon(
                                  points: point.polygonCoordinates!.map((c) => LatLng(c.lat, c.lng)).toList(),
                                  color: Colors.red.withValues(alpha: 0.2 * _nbOpacity),
                                  borderColor: Colors.red.withValues(alpha: _nbOpacity),
                                  borderStrokeWidth: 2,
                                  isFilled: true,
                                ))
                            .toList(),
                      ),
                    if (_showNZ)
                      MarkerLayer(markers: markers.map((m) => Marker(
                        point: m.point,
                        width: m.width,
                        height: m.height,
                        child: Opacity(opacity: _nzOpacity, child: m.child),
                      )).toList()),
                  ],
                ),
              ));
            },
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
                id: 'gg', label: 'גבול גזרה', color: Colors.black,
                visible: _showGG,
                onVisibilityChanged: (v) => setState(() => _showGG = v),
                opacity: _ggOpacity,
                onOpacityChanged: (v) => setState(() => _ggOpacity = v),
              ),
              MapLayerConfig(
                id: 'nz', label: 'נקודות ציון', color: Colors.blue,
                visible: _showNZ,
                onVisibilityChanged: (v) => setState(() => _showNZ = v),
                opacity: _nzOpacity,
                onOpacityChanged: (v) => setState(() => _nzOpacity = v),
              ),
              MapLayerConfig(
                id: 'nb', label: 'נקודות בטיחות', color: Colors.red,
                visible: _showNB,
                onVisibilityChanged: (v) => setState(() => _showNB = v),
                opacity: _nbOpacity,
                onOpacityChanged: (v) => setState(() => _nbOpacity = v),
              ),
              MapLayerConfig(
                id: 'routes', label: 'צירים', color: Colors.orange,
                visible: _showRoutes,
                onVisibilityChanged: (v) => setState(() => _showRoutes = v),
                opacity: _routesOpacity,
                onOpacityChanged: (v) => setState(() => _routesOpacity = v),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
