import 'dart:async';
import 'package:flutter/material.dart';
import '../../../domain/entities/navigation.dart' as domain;
import '../../../domain/entities/navigation_settings.dart';
import '../../../domain/entities/security_violation.dart';
import '../../../domain/entities/area.dart';
import '../../../domain/entities/navigation_tree.dart';
import '../../../domain/entities/boundary.dart';
import '../../../domain/entities/user.dart' as domain_user;
import '../../../data/repositories/area_repository.dart';
import '../../../data/repositories/navigation_tree_repository.dart';
import '../../../data/repositories/boundary_repository.dart';
import '../../../data/repositories/navigation_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/repositories/unit_repository.dart';
import '../../../data/sync/sync_manager.dart';
import '../../../core/constants/app_constants.dart';
import '../../../domain/entities/unit.dart' as domain_unit;
import '../../../services/auth_service.dart';
import '../../../services/navigation_layer_copy_service.dart';
import '../../../core/utils/geometry_utils.dart';
import '../../../core/map_config.dart';
import 'navigation_preparation_screen.dart';

/// מסך יצירת/עריכת ניווט
class CreateNavigationScreen extends StatefulWidget {
  final domain.Navigation? navigation;
  final bool alertsOnlyMode;

  const CreateNavigationScreen({
    super.key,
    this.navigation,
    this.alertsOnlyMode = false,
  });

  @override
  State<CreateNavigationScreen> createState() => _CreateNavigationScreenState();
}

class _CreateNavigationScreenState extends State<CreateNavigationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  // Repositories
  final _areaRepository = AreaRepository();
  final _treeRepository = NavigationTreeRepository();
  final _boundaryRepository = BoundaryRepository();
  final _navigationRepository = NavigationRepository();
  final _userRepository = UserRepository();
  final _unitRepository = UnitRepository();
  final _layerCopyService = NavigationLayerCopyService();
  final _authService = AuthService();

  // Data
  List<Area> _areas = [];
  List<NavigationTree> _trees = [];
  List<Boundary> _boundaries = [];
  List<domain_unit.Unit> _permittedUnits = [];
  bool _isLoading = false;
  bool _isSaving = false;

  // הגדרות שטח ומשתתפים
  double _distanceMin = 5.0;
  double _distanceMax = 8.0;
  String _navigationType = 'regular'; // regular, clusters, star, reverse, parachute, developing
  Area? _selectedArea;
  String? _selectedBoundaryId;
  domain_unit.Unit? _selectedUnit;
  NavigationTree? _selectedTree;

  // בחירת תתי-מסגרות ומשתתפים
  Set<String> _selectedSubFrameworkIds = {};
  Set<String> _selectedParticipantIds = {};
  Map<String, domain_user.User> _usersCache = {};
  bool _isLoadingUsers = false;
  String _safetyTimeType = 'hours'; // hours, after_last_mission
  int _safetyHours = 2;
  int _hoursAfterMission = 1;

  // הגדרות נקודות
  String _distributionMethod = 'automatic'; // automatic, manual_app, manual_full
  bool _distributeNow = false;

  // הגדרות תחקיר
  bool _showScoresAfterApproval = true;

  // הגדרות ניווט
  int _gpsUpdateInterval = 30; // שניות

  // הגדרות מיקום
  bool _useAllPositionSources = true;
  bool _enableGps = true;
  bool _enableCellTower = true;
  bool _enablePdr = true;
  bool _enablePdrCellHybrid = true;

  bool _autoVerification = false;
  String _verificationType = 'approved_failed'; // approved_failed, score_by_distance
  int _approvalDistance = 20;
  List<DistanceScoreRange> _scoreRanges = [
    const DistanceScoreRange(maxDistance: 50, scorePercentage: 100),
  ];
  bool _addRangeToggle = false;
  bool _allowOpenMap = false;
  bool _showSelfLocation = false;
  bool _showRouteOnMap = false;
  bool _allowManualPosition = false;

  // תקשורת (ווקי טוקי)
  bool _walkieTalkieEnabled = false;

  // חישוב זמנים
  bool _timeCalcEnabled = true;
  bool _isHeavyLoad = false;
  bool _isNightNavigation = false;
  bool _isSummer = true;

  // הגדרות תצוגה
  String _defaultMapType = 'topographic'; // ברירת מחדל: טופוגרפית

  // התראות
  bool _alertsEnabled = true;
  bool _speedAlertEnabled = false;
  int _maxSpeed = 50;
  bool _noMovementAlertEnabled = false;
  int _noMovementMinutes = 10;
  bool _ggAlertEnabled = false;
  int _ggAlertRange = 100;
  bool _routesAlertEnabled = false;
  int _routesAlertRange = 50;
  bool _nbAlertEnabled = false;
  int _nbAlertRange = 50;
  bool _proximityAlertEnabled = false;
  int _proximityDistance = 20;
  int _proximityMinTime = 5;
  bool _batteryAlertEnabled = false;
  int _batteryPercentage = 20;
  bool _noReceptionAlertEnabled = false;
  int _noReceptionMinTime = 30;
  bool _healthCheckEnabled = true;
  int _healthCheckIntervalMinutes = 60;
  StreamSubscription<String>? _syncSubscription;

  @override
  void initState() {
    super.initState();
    _initializeScreen();
    // האזנה לשינויי סנכרון — רענון כשמשתמשים חדשים מסתנכרנים
    _syncSubscription = SyncManager().onDataChanged.listen((collection) {
      if (collection == AppConstants.usersCollection && mounted) {
        _loadUsersForSelectedSubFrameworks();
      }
    });
  }

  Future<void> _initializeScreen() async {
    await _loadData();
    if (widget.navigation != null) {
      await _loadNavigationData();
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final areas = await _areaRepository.getAll();
      final trees = await _treeRepository.getAll();
      final allUnits = await _unitRepository.getAll();
      final currentUser = await _authService.getCurrentUser();
      final permittedUnits = currentUser != null
          ? _filterPermittedUnits(allUnits, currentUser.uid)
          : <domain_unit.Unit>[];
      setState(() {
        _areas = areas;
        _trees = trees;
        _permittedUnits = permittedUnits;
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

  /// סינון יחידות שהמשתמש מורשה לנהל
  List<domain_unit.Unit> _filterPermittedUnits(
      List<domain_unit.Unit> allUnits, String uid) {
    // מצא יחידות שהמשתמש מנהל ישירות
    final managedIds = <String>{};
    for (final unit in allUnits) {
      if (unit.managerIds.contains(uid)) {
        managedIds.add(unit.id);
      }
    }

    // הוסף רקורסיבית יחידות ילדים
    final permittedIds = <String>{...managedIds};
    void addChildren(String parentId) {
      for (final unit in allUnits) {
        if (unit.parentUnitId == parentId && !permittedIds.contains(unit.id)) {
          permittedIds.add(unit.id);
          addChildren(unit.id);
        }
      }
    }
    for (final id in managedIds) {
      addChildren(id);
    }

    return allUnits.where((u) => permittedIds.contains(u.id)).toList();
  }

  Future<void> _loadBoundaries(String areaId) async {
    try {
      final boundaries = await _boundaryRepository.getByArea(areaId);
      setState(() {
        _boundaries = boundaries;
        // רק אפס אם הגבול הנוכחי לא ברשימה החדשה
        if (_selectedBoundaryId != null &&
            !boundaries.any((b) => b.id == _selectedBoundaryId)) {
          _selectedBoundaryId = null;
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה בטעינת גבולות: $e')),
        );
      }
    }
  }

  /// כשיחידה נבחרת — חיפוש עץ ואיפוס תתי-מסגרות ומשתתפים
  Future<void> _onUnitSelected(domain_unit.Unit? unit) async {
    if (unit == null) {
      setState(() {
        _selectedUnit = null;
        _selectedTree = null;
        _selectedSubFrameworkIds.clear();
        _selectedParticipantIds.clear();
        _usersCache.clear();
      });
      return;
    }

    setState(() {
      _selectedUnit = unit;
      _selectedTree = null;
      _selectedSubFrameworkIds.clear();
      _selectedParticipantIds.clear();
      _usersCache.clear();
    });

    // חיפוש עץ ניווט לפי יחידה
    final trees = await _treeRepository.getByUnitId(unit.id);
    if (trees.isNotEmpty && mounted) {
      setState(() {
        _selectedTree = trees.first;
      });
    }
  }

  /// כשתת-מסגרת נבחרת/מבוטלת — עדכון המשתתפים
  void _onSubFrameworkToggled(String subFrameworkId, bool selected) {
    setState(() {
      if (selected) {
        _selectedSubFrameworkIds.add(subFrameworkId);
      } else {
        _selectedSubFrameworkIds.remove(subFrameworkId);
        // הסרת משתתפים מתת-מסגרת שבוטלה
        if (_selectedTree != null) {
          final sf = _selectedTree!.subFrameworks
              .where((s) => s.id == subFrameworkId)
              .firstOrNull;
          if (sf != null) {
            _selectedParticipantIds.removeAll(sf.userIds);
          }
        }
      }
    });
    _loadUsersForSelectedSubFrameworks();
  }

  /// בחירת/ביטול כל המשתתפים בתת-מסגרת
  void _toggleAllParticipantsInSubFramework(SubFramework sf, bool selectAll) {
    setState(() {
      if (selectAll) {
        _selectedParticipantIds.addAll(sf.userIds);
      } else {
        _selectedParticipantIds.removeAll(sf.userIds);
      }
    });
  }

  /// טעינת פרטי משתמשים עבור תתי-המסגרות הנבחרות
  Future<void> _loadUsersForSelectedSubFrameworks() async {
    if (_selectedTree == null) return;

    final allUserIds = <String>{};
    for (final sf in _selectedTree!.subFrameworks) {
      if (_selectedSubFrameworkIds.contains(sf.id)) {
        allUserIds.addAll(sf.userIds);
      }
    }

    final missingIds = allUserIds.where((id) => !_usersCache.containsKey(id)).toList();
    if (missingIds.isEmpty) return;

    setState(() => _isLoadingUsers = true);
    try {
      for (final uid in missingIds) {
        final user = await _userRepository.getUser(uid);
        if (user != null) {
          _usersCache[uid] = user;
        }
      }
    } catch (e) {
      print('DEBUG: Error loading users: $e');
    }
    if (mounted) {
      setState(() => _isLoadingUsers = false);
    }
  }

  /// רשימת כל ה-userIds מתתי-המסגרות הנבחרות
  List<String> get _allSelectedSubFrameworkUserIds {
    if (_selectedTree == null) return [];
    final ids = <String>[];
    for (final sf in _selectedTree!.subFrameworks) {
      if (_selectedSubFrameworkIds.contains(sf.id)) {
        ids.addAll(sf.userIds);
      }
    }
    return ids;
  }

  Future<void> _loadNavigationData() async {
    final nav = widget.navigation!;

    // שם
    _nameController.text = nav.name;

    // סוג ניווט ושיטת חלוקה
    _navigationType = nav.navigationType ?? 'regular';
    _distributionMethod = nav.distributionMethod;
    _distributeNow = nav.distributeNow;

    // טווח מרחק
    if (nav.routeLengthKm != null) {
      _distanceMin = nav.routeLengthKm!.min;
      _distanceMax = nav.routeLengthKm!.max;
    }

    // זמן בטיחות
    if (nav.safetyTime != null) {
      _safetyTimeType = nav.safetyTime!.type;
      _safetyHours = nav.safetyTime!.hours ?? 2;
      _hoursAfterMission = nav.safetyTime!.hoursAfterMission ?? 1;
    }

    // הגדרות תחקיר
    _showScoresAfterApproval = nav.reviewSettings.showScoresAfterApproval;

    // הגדרות GPS
    _gpsUpdateInterval = nav.gpsUpdateIntervalSeconds;

    // הגדרות מיקום
    final sources = nav.enabledPositionSources;
    _enableGps = sources.contains('gps');
    _enableCellTower = sources.contains('cellTower');
    _enablePdr = sources.contains('pdr');
    _enablePdrCellHybrid = sources.contains('pdrCellHybrid');
    _useAllPositionSources = _enableGps && _enableCellTower && _enablePdr && _enablePdrCellHybrid;

    // הגדרות אימות
    _autoVerification = nav.verificationSettings.autoVerification;
    _verificationType = nav.verificationSettings.verificationType ?? 'approved_failed';
    _approvalDistance = nav.verificationSettings.approvalDistance ?? 50;
    final loadedRanges = nav.verificationSettings.scoreRanges ?? [];
    _scoreRanges = loadedRanges.isNotEmpty
        ? loadedRanges
        : [const DistanceScoreRange(maxDistance: 50, scorePercentage: 100)];

    // הגדרות מפה
    _allowOpenMap = nav.allowOpenMap;
    _showSelfLocation = nav.showSelfLocation;
    _showRouteOnMap = nav.showRouteOnMap;
    _allowManualPosition = nav.allowManualPosition;

    // תקשורת
    _walkieTalkieEnabled = nav.communicationSettings.walkieTalkieEnabled;

    // חישוב זמנים
    _timeCalcEnabled = nav.timeCalculationSettings.enabled;
    _isHeavyLoad = nav.timeCalculationSettings.isHeavyLoad;
    _isNightNavigation = nav.timeCalculationSettings.isNightNavigation;
    _isSummer = nav.timeCalculationSettings.isSummer;

    // הגדרות תצוגה
    _defaultMapType = nav.displaySettings.defaultMap ?? 'topographic';

    // התראות
    _alertsEnabled = nav.alerts.enabled;
    _speedAlertEnabled = nav.alerts.speedAlertEnabled;
    _maxSpeed = nav.alerts.maxSpeed ?? 80;
    _noMovementAlertEnabled = nav.alerts.noMovementAlertEnabled;
    _noMovementMinutes = nav.alerts.noMovementMinutes ?? 5;
    _ggAlertEnabled = nav.alerts.ggAlertEnabled;
    _ggAlertRange = nav.alerts.ggAlertRange ?? 100;
    _routesAlertEnabled = nav.alerts.routesAlertEnabled;
    _routesAlertRange = nav.alerts.routesAlertRange ?? 100;
    _nbAlertEnabled = nav.alerts.nbAlertEnabled;
    _nbAlertRange = nav.alerts.nbAlertRange ?? 100;
    _proximityAlertEnabled = nav.alerts.navigatorProximityAlertEnabled;
    _proximityDistance = nav.alerts.proximityDistance ?? 50;
    _proximityMinTime = nav.alerts.proximityMinTime ?? 5;
    _batteryAlertEnabled = nav.alerts.batteryAlertEnabled;
    _batteryPercentage = nav.alerts.batteryPercentage ?? 20;
    _noReceptionAlertEnabled = nav.alerts.noReceptionAlertEnabled;
    _noReceptionMinTime = nav.alerts.noReceptionMinTime ?? 60;
    _healthCheckEnabled = nav.alerts.healthCheckEnabled;
    _healthCheckIntervalMinutes = nav.alerts.healthCheckIntervalMinutes;

    // טעינת אזור, עץ וגבול
    await _loadAreaTreeAndBoundary();
  }

  Future<void> _loadAreaTreeAndBoundary() async {
    final nav = widget.navigation!;

    // חיפוש האזור הנבחר
    _selectedArea = _areas.firstWhere(
      (area) => area.id == nav.areaId,
      orElse: () => _areas.isNotEmpty ? _areas.first : throw Exception('No areas found'),
    );

    // טעינת גבולות האזור
    await _loadBoundaries(nav.areaId);

    // בחירת הגבול
    if (nav.boundaryLayerId != null) {
      _selectedBoundaryId = nav.boundaryLayerId;
    }

    // חיפוש העץ הנבחר
    _selectedTree = _trees.firstWhere(
      (tree) => tree.id == nav.treeId,
      orElse: () => _trees.isNotEmpty ? _trees.first : throw Exception('No trees found'),
    );

    // חיפוש היחידה הנבחרת
    if (nav.selectedUnitId != null) {
      _selectedUnit = _permittedUnits
          .where((u) => u.id == nav.selectedUnitId)
          .firstOrNull;
      // אם היחידה לא ברשימת המורשות — נסה לטעון אותה
      if (_selectedUnit == null) {
        final unit = await _unitRepository.getById(nav.selectedUnitId!);
        if (unit != null) {
          _permittedUnits = [..._permittedUnits, unit];
          _selectedUnit = unit;
        }
      }
    } else if (_selectedTree?.unitId != null) {
      // fallback: שלוף יחידה מהעץ
      _selectedUnit = _permittedUnits
          .where((u) => u.id == _selectedTree!.unitId)
          .firstOrNull;
    }

    // טעינת תתי-מסגרות נבחרות
    if (nav.selectedSubFrameworkIds.isNotEmpty) {
      _selectedSubFrameworkIds = Set.from(nav.selectedSubFrameworkIds);
    }

    // טעינת משתתפים נבחרים
    if (nav.selectedParticipantIds.isNotEmpty) {
      _selectedParticipantIds = Set.from(nav.selectedParticipantIds);
    }

    // טעינת פרטי משתמשים
    await _loadUsersForSelectedSubFrameworks();

    setState(() {});
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.alertsOnlyMode
              ? 'עריכת התראות'
              : (widget.navigation == null ? 'ניווט חדש' : 'עריכת ניווט')
        ),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _save,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // הודעה במצב עריכת התראות בלבד
                  if (widget.alertsOnlyMode) ...[
                    Card(
                      color: Colors.blue[50],
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(Icons.info, color: Colors.blue[700]),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'מצב עריכת התראות בלבד - ניתן לערוך רק את ההתראות',
                                style: TextStyle(
                                  color: Colors.blue[900],
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // שם הניווט
                  if (!widget.alertsOnlyMode) ...[
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'שם הניווט',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.navigation),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'נא להזין שם';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                  ],

                  // הגדרות שטח ומשתתפים
                  if (!widget.alertsOnlyMode) ...[
                    _buildSectionTitle('הגדרות שטח ומשתתפים'),
                    _buildFieldAndParticipantsSettings(),
                    const SizedBox(height: 24),
                  ],

                  // הגדרות ניווט (כולל התראות)
                  _buildSectionTitle(widget.alertsOnlyMode ? 'התראות' : 'הגדרות ניווט'),
                  _buildNavigationSettings(),

                  if (!widget.alertsOnlyMode) ...[
                    const SizedBox(height: 24),

                    // חישוב זמנים
                    _buildSectionTitle('חישוב זמנים'),
                    _buildTimeCalculationSettings(),
                    const SizedBox(height: 24),

                    // הגדרות מיקום
                    _buildSectionTitle('הגדרות מיקום'),
                    _buildLocationSettings(),
                    const SizedBox(height: 24),

                    // תקשורת
                    _buildSectionTitle('תקשורת'),
                    _buildCommunicationSettings(),
                    const SizedBox(height: 24),

                    // הגדרות תחקיר
                    _buildSectionTitle('הגדרות תחקיר'),
                    _buildReviewSettings(),
                    const SizedBox(height: 24),

                    // הגדרות תצוגה
                    _buildSectionTitle('הגדרות תצוגה'),
                    _buildDisplaySettings(),
                  ],

                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.blue,
        ),
      ),
    );
  }

  Widget _buildFieldAndParticipantsSettings() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // אזור ניווט
            const Text('אזור ניווט', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonFormField<Area>(
              value: _selectedArea,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'בחר אזור',
              ),
              items: _areas.map((area) {
                return DropdownMenuItem(
                  value: area,
                  child: Text(area.name),
                );
              }).toList(),
              onChanged: (value) {
                setState(() => _selectedArea = value);
                if (value != null) {
                  _loadBoundaries(value.id);
                }
              },
              validator: (value) => value == null ? 'נא לבחור אזור' : null,
            ),
            const SizedBox(height: 16),

            // גבול גזרה
            const Text('גבול גזרה', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _boundaries.any((b) => b.id == _selectedBoundaryId)
                  ? _selectedBoundaryId
                  : null,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'בחר גבול גזרה',
              ),
              items: _boundaries.map((boundary) {
                return DropdownMenuItem(
                  value: boundary.id,
                  child: Text(boundary.name),
                );
              }).toList(),
              onChanged: (value) {
                setState(() => _selectedBoundaryId = value);
              },
              validator: (value) => value == null ? 'נא לבחור גבול גזרה' : null,
            ),

            // הודעה על העתקת שכבות ניווטיות
            if (_selectedBoundaryId != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.layers, color: Colors.blue[700], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.navigation == null
                                ? 'בעת יצירת הניווט, יועתקו כל השכבות בתוך הגבול הנבחר'
                                : 'שכבות ניווטיות הועתקו - ניתנות לעריכה בשלב הכנה',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue[900],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'נ"צ, נת"ב וב"א בתוך הג"ג יועתקו כעותקים עצמאיים',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.blue[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),

            // בחירת מסגרת מנווטת
            const Text('מסגרת מנווטת', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonFormField<domain_unit.Unit>(
              value: _selectedUnit,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'בחר מסגרת מנווטת',
              ),
              items: _permittedUnits.map((unit) {
                return DropdownMenuItem(
                  value: unit,
                  child: Text(unit.name),
                );
              }).toList(),
              onChanged: _onUnitSelected,
              validator: (value) => value == null ? 'נא לבחור מסגרת מנווטת' : null,
            ),
            const SizedBox(height: 16),

            // בחירת תתי-מסגרות
            if (_selectedTree != null &&
                _selectedTree!.subFrameworks.isNotEmpty) ...[
              const Text('תתי-מסגרות משתתפות', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                'בחר אילו תתי-מסגרות ישתתפו בניווט',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 8),
              ..._selectedTree!.subFrameworks.map((sf) {
                return CheckboxListTile(
                  title: Text(sf.name),
                  subtitle: Text('${sf.userIds.length} משתמשים'),
                  value: _selectedSubFrameworkIds.contains(sf.id),
                  onChanged: (value) {
                    _onSubFrameworkToggled(sf.id, value ?? false);
                  },
                  dense: true,
                );
              }),
              const SizedBox(height: 16),
            ],

            // בחירת משתתפים
            if (_selectedSubFrameworkIds.isNotEmpty) ...[
              const Text('משתתפים', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                'בחר משתתפים מתוך תתי-המסגרות הנבחרות (אם לא תבחר — כולם ישתתפו)',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 8),
              if (_isLoadingUsers)
                const Center(child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(strokeWidth: 2),
                )),
              if (!_isLoadingUsers)
                ..._selectedTree!.subFrameworks
                    .where((sf) => _selectedSubFrameworkIds.contains(sf.id))
                    .map((sf) {
                  final allSelected = sf.userIds.every((uid) => _selectedParticipantIds.contains(uid));
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // כותרת תת-מסגרת עם כפתור בחר/בטל הכל
                      Row(
                        children: [
                          Text(
                            sf.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: Colors.blue,
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () {
                              _toggleAllParticipantsInSubFramework(sf, !allSelected);
                            },
                            child: Text(
                              allSelected ? 'בטל הכל' : 'בחר הכל',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      ...sf.userIds.map((uid) {
                        final user = _usersCache[uid];
                        final displayName = user?.fullName ?? uid;
                        return CheckboxListTile(
                          title: Text(displayName),
                          subtitle: user != null ? Text(user.personalNumber) : null,
                          value: _selectedParticipantIds.contains(uid),
                          onChanged: (value) {
                            setState(() {
                              if (value == true) {
                                _selectedParticipantIds.add(uid);
                              } else {
                                _selectedParticipantIds.remove(uid);
                              }
                            });
                          },
                          dense: true,
                        );
                      }),
                      const Divider(),
                    ],
                  );
                }),
              const SizedBox(height: 8),
              // סיכום
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.people, color: Colors.green[700], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _selectedParticipantIds.isEmpty
                            ? 'כל ${_allSelectedSubFrameworkUserIds.length} המשתמשים מתתי-המסגרות הנבחרות ישתתפו'
                            : '${_selectedParticipantIds.length} משתתפים נבחרו מתוך ${_allSelectedSubFrameworkUserIds.length}',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.green[900],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // זמן בטיחות
            const Text('זמן בטיחות', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            RadioListTile<String>(
              title: const Text('שעות קבועות'),
              value: 'hours',
              groupValue: _safetyTimeType,
              onChanged: (value) {
                setState(() => _safetyTimeType = value!);
              },
            ),
            if (_safetyTimeType == 'hours')
              Padding(
                padding: const EdgeInsets.only(right: 32),
                child: TextFormField(
                  initialValue: _safetyHours.toString(),
                  decoration: const InputDecoration(
                    labelText: 'מספר שעות',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (value) {
                    _safetyHours = int.tryParse(value) ?? 2;
                  },
                ),
              ),
            RadioListTile<String>(
              title: const Text('שעה אחרי זמן משימה אחרון'),
              value: 'after_last_mission',
              groupValue: _safetyTimeType,
              onChanged: (value) {
                setState(() => _safetyTimeType = value!);
              },
            ),
            if (_safetyTimeType == 'after_last_mission')
              Padding(
                padding: const EdgeInsets.only(right: 32),
                child: TextFormField(
                  initialValue: _hoursAfterMission.toString(),
                  decoration: const InputDecoration(
                    labelText: 'שעות אחרי',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (value) {
                    _hoursAfterMission = int.tryParse(value) ?? 1;
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<String> _buildEnabledPositionSources() {
    if (_useAllPositionSources) {
      return const ['gps', 'cellTower', 'pdr', 'pdrCellHybrid'];
    }
    final sources = <String>[];
    if (_enableGps) sources.add('gps');
    if (_enableCellTower) sources.add('cellTower');
    if (_enablePdr) sources.add('pdr');
    if (_enablePdrCellHybrid) sources.add('pdrCellHybrid');
    // לפחות GPS חייב להיות דלוק
    if (sources.isEmpty) sources.add('gps');
    return sources;
  }

  Widget _buildCommunicationSettings() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              title: const Text('ווקי טוקי'),
              subtitle: const Text('הפעלת מערכת קשר קולי בזמן אמת'),
              value: _walkieTalkieEnabled,
              contentPadding: EdgeInsets.zero,
              onChanged: (value) => setState(() => _walkieTalkieEnabled = value),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeCalculationSettings() {
    final speedKmh = const TimeCalculationSettings().copyWith(
      isHeavyLoad: _isHeavyLoad,
      isNightNavigation: _isNightNavigation,
    ).walkingSpeedKmh;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              title: const Text('חישוב זמנים אוטומטי'),
              subtitle: const Text('חישוב זמני ניווט לפי מהירות הליכה, הפסקות ושעת בטיחות'),
              value: _timeCalcEnabled,
              onChanged: (v) => setState(() => _timeCalcEnabled = v),
            ),
            if (_timeCalcEnabled) ...[
              const Divider(),
              const SizedBox(height: 8),
              const Text('משקל', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('עד 40% משקל גוף')),
                  ButtonSegment(value: true, label: Text('מעל 40%')),
                ],
                selected: {_isHeavyLoad},
                onSelectionChanged: (v) => setState(() => _isHeavyLoad = v.first),
              ),
              const SizedBox(height: 16),
              const Text('זמן', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('יום')),
                  ButtonSegment(value: true, label: Text('לילה')),
                ],
                selected: {_isNightNavigation},
                onSelectionChanged: (v) => setState(() => _isNightNavigation = v.first),
              ),
              const SizedBox(height: 16),
              const Text('עונה', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('קיץ')),
                  ButtonSegment(value: false, label: Text('חורף')),
                ],
                selected: {_isSummer},
                onSelectionChanged: (v) => setState(() => _isSummer = v.first),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.speed, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'קצב הליכה: ${speedKmh.toStringAsFixed(1)} קמ"ש',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLocationSettings() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // מרווח דגימת GPS
            ListTile(
              leading: const Icon(Icons.timer, color: Colors.blue),
              title: const Text('מרווח דגימת GPS'),
              subtitle: Text('$_gpsUpdateInterval שניות'),
              trailing: SizedBox(
                width: 120,
                child: Slider(
                  value: _gpsUpdateInterval.toDouble(),
                  min: 1,
                  max: 120,
                  divisions: 119,
                  label: '$_gpsUpdateInterval שניות',
                  onChanged: (value) {
                    setState(() => _gpsUpdateInterval = value.round());
                  },
                ),
              ),
            ),
            const Divider(),
            // בחירת אמצעי מיקום
            SwitchListTile(
              title: const Text('בחר את כל אמצעי המיקום'),
              subtitle: const Text('כולל GPS, אנטנות, PDR ומשולב'),
              value: _useAllPositionSources,
              onChanged: (value) {
                setState(() {
                  _useAllPositionSources = value;
                  if (value) {
                    _enableGps = true;
                    _enableCellTower = true;
                    _enablePdr = true;
                    _enablePdrCellHybrid = true;
                  }
                });
              },
            ),
            if (!_useAllPositionSources) ...[
              SwitchListTile(
                secondary: const Icon(Icons.gps_fixed),
                title: const Text('GPS'),
                value: _enableGps,
                onChanged: (value) {
                  setState(() => _enableGps = value);
                },
              ),
              SwitchListTile(
                secondary: const Icon(Icons.cell_tower),
                title: const Text('אנטנות סלולריות'),
                value: _enableCellTower,
                onChanged: (value) {
                  setState(() => _enableCellTower = value);
                },
              ),
              SwitchListTile(
                secondary: const Icon(Icons.directions_walk),
                title: const Text('PDR — חישוב הליכה'),
                value: _enablePdr,
                onChanged: (value) {
                  setState(() => _enablePdr = value);
                },
              ),
              SwitchListTile(
                secondary: const Icon(Icons.merge_type),
                title: const Text('PDR + אנטנות (משולב)'),
                value: _enablePdrCellHybrid,
                onChanged: (value) {
                  setState(() => _enablePdrCellHybrid = value);
                },
              ),
            ],
            const Divider(),
            SwitchListTile(
              secondary: const Icon(Icons.push_pin, color: Colors.deepPurple),
              title: const Text('אפשר דקירת מיקום עצמי'),
              subtitle: const Text('כאשר אין GPS ואמצעים חלופיים'),
              value: _allowManualPosition,
              onChanged: (value) => setState(() => _allowManualPosition = value),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReviewSettings() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              title: const Text('הצג ציונים לאחר אישרור'),
              value: _showScoresAfterApproval,
              onChanged: (value) {
                setState(() => _showScoresAfterApproval = value);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavigationSettings() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!widget.alertsOnlyMode) ...[
              SwitchListTile(
                title: const Text('הפעל אימות נקודות אוטומטי'),
                value: _autoVerification,
                onChanged: (value) {
                  setState(() => _autoVerification = value);
                },
              ),
            ],

            if (_autoVerification && !widget.alertsOnlyMode) ...[
              const SizedBox(height: 8),
              RadioListTile<String>(
                title: const Text('אושר / נפסל'),
                value: 'approved_failed',
                groupValue: _verificationType,
                onChanged: (value) {
                  setState(() => _verificationType = value!);
                },
              ),
              RadioListTile<String>(
                title: const Text('ציון לפי מרחק'),
                value: 'score_by_distance',
                groupValue: _verificationType,
                onChanged: (value) {
                  setState(() => _verificationType = value!);
                },
              ),

              if (_verificationType == 'approved_failed') ...[
                Padding(
                  padding: const EdgeInsets.only(right: 32, top: 8),
                  child: TextFormField(
                    initialValue: _approvalDistance.toString(),
                    decoration: const InputDecoration(
                      labelText: 'מרחק לאישור (מטרים)',
                      border: OutlineInputBorder(),
                      helperText: '5-50 מטר',
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (value) {
                      _approvalDistance = int.tryParse(value) ?? 20;
                    },
                  ),
                ),
              ],

              if (_verificationType == 'score_by_distance') ...[
                Padding(
                  padding: const EdgeInsets.only(right: 32, top: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('טווחי מרחק וציון:', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      // Header row
                      Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                        child: const Row(
                          children: [
                            Expanded(flex: 2, child: Text('טווח (מ\')', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                            Expanded(flex: 3, child: Text('עד טווח (מ\')', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                            Expanded(flex: 3, child: Text('אחוז ציון (%)', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                            SizedBox(width: 40),
                          ],
                        ),
                      ),
                      // Data rows
                      ...List.generate(_scoreRanges.length, (index) {
                        final fromDistance = index == 0 ? 0 : _scoreRanges[index - 1].maxDistance;
                        return Container(
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: Colors.grey.shade300),
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                          child: Row(
                            children: [
                              // From distance (read-only)
                              Expanded(
                                flex: 2,
                                child: Text(
                                  '$fromDistance',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 15, color: Colors.grey.shade700),
                                ),
                              ),
                              // Max distance (editable)
                              Expanded(
                                flex: 3,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  child: TextFormField(
                                    key: ValueKey('maxDist_${index}_${_scoreRanges.length}'),
                                    initialValue: _scoreRanges[index].maxDistance.toString(),
                                    decoration: const InputDecoration(
                                      border: OutlineInputBorder(),
                                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                      isDense: true,
                                    ),
                                    textAlign: TextAlign.center,
                                    keyboardType: TextInputType.number,
                                    onChanged: (value) {
                                      final distance = int.tryParse(value);
                                      if (distance != null) {
                                        setState(() {
                                          _scoreRanges[index] = DistanceScoreRange(
                                            maxDistance: distance,
                                            scorePercentage: _scoreRanges[index].scorePercentage,
                                          );
                                        });
                                      }
                                    },
                                  ),
                                ),
                              ),
                              // Score percentage (editable)
                              Expanded(
                                flex: 3,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  child: TextFormField(
                                    key: ValueKey('scorePct_${index}_${_scoreRanges.length}'),
                                    initialValue: _scoreRanges[index].scorePercentage.toString(),
                                    decoration: const InputDecoration(
                                      border: OutlineInputBorder(),
                                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                      isDense: true,
                                    ),
                                    textAlign: TextAlign.center,
                                    keyboardType: TextInputType.number,
                                    onChanged: (value) {
                                      final percentage = int.tryParse(value);
                                      if (percentage != null) {
                                        setState(() {
                                          _scoreRanges[index] = DistanceScoreRange(
                                            maxDistance: _scoreRanges[index].maxDistance,
                                            scorePercentage: percentage,
                                          );
                                        });
                                      }
                                    },
                                  ),
                                ),
                              ),
                              // Delete button (not for first row)
                              SizedBox(
                                width: 40,
                                child: index > 0
                                    ? IconButton(
                                        icon: const Icon(Icons.close, size: 20),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        color: Colors.red,
                                        onPressed: () {
                                          setState(() {
                                            _scoreRanges.removeAt(index);
                                          });
                                        },
                                      )
                                    : null,
                              ),
                            ],
                          ),
                        );
                      }),
                      // Add range toggle
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('טווח נוסף'),
                        value: _addRangeToggle,
                        onChanged: (value) {
                          if (value) {
                            setState(() {
                              final lastMax = _scoreRanges.isNotEmpty ? _scoreRanges.last.maxDistance : 0;
                              _scoreRanges.add(DistanceScoreRange(
                                maxDistance: lastMax + 20,
                                scorePercentage: 0,
                              ));
                              _addRangeToggle = false;
                            });
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ],

            if (!widget.alertsOnlyMode) ...[
              const Divider(),

              SwitchListTile(
                title: const Text('אפשר ניווט עם מפה פתוחה'),
                value: _allowOpenMap,
                onChanged: (value) {
                  setState(() => _allowOpenMap = value);
                },
              ),
            ],

            if (_allowOpenMap && !widget.alertsOnlyMode) ...[
              SwitchListTile(
                title: const Text('אפשר הצגת מיקום עצמי למנווט'),
                value: _showSelfLocation,
                onChanged: (value) {
                  setState(() => _showSelfLocation = value);
                },
              ),
              if (_showSelfLocation)
                SwitchListTile(
                  title: const Text('הצג ציר ניווט על המפה'),
                  value: _showRouteOnMap,
                  onChanged: (value) {
                    setState(() => _showRouteOnMap = value);
                  },
                ),
            ],

            // בדיקת תקינות מנווטים
            SwitchListTile(
              title: const Text('בדיקת תקינות'),
              subtitle: const Text('דרוש דיווח תקינות תקופתי ממנווטים'),
              value: _healthCheckEnabled,
              onChanged: (value) {
                setState(() => _healthCheckEnabled = value);
              },
            ),
            if (_healthCheckEnabled) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _healthCheckIntervalMinutes >= 60
                          ? 'זמן בין בדיקות: ${(_healthCheckIntervalMinutes / 60).toStringAsFixed(_healthCheckIntervalMinutes % 60 == 0 ? 0 : 1)} שעות'
                          : 'זמן בין בדיקות: $_healthCheckIntervalMinutes דקות',
                      style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                    ),
                    Slider(
                      value: _healthCheckIntervalMinutes.toDouble(),
                      min: 30,
                      max: 600,
                      divisions: 19,
                      label: _healthCheckIntervalMinutes >= 60
                          ? '${(_healthCheckIntervalMinutes / 60).toStringAsFixed(_healthCheckIntervalMinutes % 60 == 0 ? 0 : 1)} שעות'
                          : '$_healthCheckIntervalMinutes דקות',
                      onChanged: (value) {
                        setState(() => _healthCheckIntervalMinutes = value.round());
                      },
                    ),
                  ],
                ),
              ),
            ],
            const Divider(),

            SwitchListTile(
              title: const Text('הפעל התראות'),
              value: _alertsEnabled,
              onChanged: (value) {
                setState(() => _alertsEnabled = value);
              },
            ),

            if (_alertsEnabled) ...[
              _buildAlertsSettings(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAlertsSettings() {
    return Column(
      children: [
        // התראת מהירות
        SwitchListTile(
          title: const Text('התראת מהירות'),
          value: _speedAlertEnabled,
          onChanged: (value) {
            setState(() => _speedAlertEnabled = value);
          },
        ),
        if (_speedAlertEnabled)
          Padding(
            padding: const EdgeInsets.only(right: 32, bottom: 8),
            child: TextFormField(
              initialValue: _maxSpeed.toString(),
              decoration: const InputDecoration(
                labelText: 'מהירות מקסימלית (קמ"ש)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              onChanged: (value) {
                _maxSpeed = int.tryParse(value) ?? 50;
              },
            ),
          ),

        // התראת חוסר תנועה
        SwitchListTile(
          title: const Text('התראת חוסר תנועה'),
          value: _noMovementAlertEnabled,
          onChanged: (value) {
            setState(() => _noMovementAlertEnabled = value);
          },
        ),
        if (_noMovementAlertEnabled)
          Padding(
            padding: const EdgeInsets.only(right: 32, bottom: 8),
            child: TextFormField(
              initialValue: _noMovementMinutes.toString(),
              decoration: const InputDecoration(
                labelText: 'זמן (דקות)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              onChanged: (value) {
                _noMovementMinutes = int.tryParse(value) ?? 10;
              },
            ),
          ),

        // התראת גבול גזרה
        SwitchListTile(
          title: const Text('התראת גבול גזרה'),
          value: _ggAlertEnabled,
          onChanged: (value) {
            setState(() => _ggAlertEnabled = value);
          },
        ),
        if (_ggAlertEnabled)
          Padding(
            padding: const EdgeInsets.only(right: 32, bottom: 8),
            child: TextFormField(
              initialValue: _ggAlertRange.toString(),
              decoration: const InputDecoration(
                labelText: 'טווח התראה (מטרים)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              onChanged: (value) {
                _ggAlertRange = int.tryParse(value) ?? 100;
              },
            ),
          ),

        // התראת נתבים
        SwitchListTile(
          title: const Text('התראת נתבים'),
          value: _routesAlertEnabled,
          onChanged: (value) {
            setState(() => _routesAlertEnabled = value);
          },
        ),
        if (_routesAlertEnabled)
          Padding(
            padding: const EdgeInsets.only(right: 32, bottom: 8),
            child: TextFormField(
              initialValue: _routesAlertRange.toString(),
              decoration: const InputDecoration(
                labelText: 'טווח התראה (מטרים)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              onChanged: (value) {
                _routesAlertRange = int.tryParse(value) ?? 50;
              },
            ),
          ),

        // התראת נת"ב
        SwitchListTile(
          title: const Text('התראת נת"ב'),
          value: _nbAlertEnabled,
          onChanged: (value) {
            setState(() => _nbAlertEnabled = value);
          },
        ),
        if (_nbAlertEnabled)
          Padding(
            padding: const EdgeInsets.only(right: 32, bottom: 8),
            child: TextFormField(
              initialValue: _nbAlertRange.toString(),
              decoration: const InputDecoration(
                labelText: 'טווח התראה (מטרים)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              onChanged: (value) {
                _nbAlertRange = int.tryParse(value) ?? 50;
              },
            ),
          ),

        // התראת קרבת מנווטים
        SwitchListTile(
          title: const Text('התראת קרבת מנווטים'),
          value: _proximityAlertEnabled,
          onChanged: (value) {
            setState(() => _proximityAlertEnabled = value);
          },
        ),
        if (_proximityAlertEnabled)
          Padding(
            padding: const EdgeInsets.only(right: 32, bottom: 8),
            child: Column(
              children: [
                TextFormField(
                  initialValue: _proximityDistance.toString(),
                  decoration: const InputDecoration(
                    labelText: 'מרחק (מטרים)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (value) {
                    _proximityDistance = int.tryParse(value) ?? 20;
                  },
                ),
                const SizedBox(height: 8),
                TextFormField(
                  initialValue: _proximityMinTime.toString(),
                  decoration: const InputDecoration(
                    labelText: 'זמן מינימום (דקות)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (value) {
                    _proximityMinTime = int.tryParse(value) ?? 5;
                  },
                ),
              ],
            ),
          ),

        // התראת סוללה
        SwitchListTile(
          title: const Text('התראת סוללה'),
          value: _batteryAlertEnabled,
          onChanged: (value) {
            setState(() => _batteryAlertEnabled = value);
          },
        ),
        if (_batteryAlertEnabled)
          Padding(
            padding: const EdgeInsets.only(right: 32, bottom: 8),
            child: TextFormField(
              initialValue: _batteryPercentage.toString(),
              decoration: const InputDecoration(
                labelText: 'אחוז סוללה',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              onChanged: (value) {
                _batteryPercentage = int.tryParse(value) ?? 20;
              },
            ),
          ),

        // התראת חוסר קליטה
        SwitchListTile(
          title: const Text('התראת חוסר קליטה'),
          value: _noReceptionAlertEnabled,
          onChanged: (value) {
            setState(() => _noReceptionAlertEnabled = value);
          },
        ),
        if (_noReceptionAlertEnabled)
          Padding(
            padding: const EdgeInsets.only(right: 32, bottom: 8),
            child: TextFormField(
              initialValue: _noReceptionMinTime.toString(),
              decoration: const InputDecoration(
                labelText: 'זמן מינימום (שניות)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              onChanged: (value) {
                _noReceptionMinTime = int.tryParse(value) ?? 30;
              },
            ),
          ),
      ],
    );
  }

  Widget _buildDisplaySettings() {
    final mapConfig = MapConfig();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('מפת ברירת מחדל', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _defaultMapType,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: MapType.values.map((type) {
                return DropdownMenuItem<String>(
                  value: type.name,
                  child: Text(mapConfig.label(type)),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _defaultMapType = value);
                }
              },
            ),

            const SizedBox(height: 16),
            const Text('מיקום פתיחת מפה: מחושב אוטומטית ממרכז הג"ג',
              style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic)),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    // Validate score ranges
    if (_autoVerification && _verificationType == 'score_by_distance') {
      for (int i = 0; i < _scoreRanges.length; i++) {
        // Validate percentage 0-100
        if (_scoreRanges[i].scorePercentage < 0 || _scoreRanges[i].scorePercentage > 100) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('שורה ${i + 1}: אחוז ציון חייב להיות בין 0 ל-100'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
        // Validate that maxDistance > fromDistance
        final from = i == 0 ? 0 : _scoreRanges[i - 1].maxDistance;
        if (_scoreRanges[i].maxDistance <= from) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('שורה ${i + 1}: "עד טווח" חייב להיות גדול מ-$from'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }
    }

    setState(() => _isSaving = true);

    try {
      // יצירת ההגדרות
      final safetyTime = SafetyTimeSettings(
        type: _safetyTimeType,
        hours: _safetyTimeType == 'hours' ? _safetyHours : null,
        hoursAfterMission: _safetyTimeType == 'after_last_mission' ? _hoursAfterMission : null,
      );

      final learningSettings = widget.navigation?.learningSettings ?? const LearningSettings();

      final reviewSettings = ReviewSettings(
        showScoresAfterApproval: _showScoresAfterApproval,
      );

      final verificationSettings = VerificationSettings(
        autoVerification: _autoVerification,
        verificationType: _autoVerification ? _verificationType : null,
        approvalDistance: _verificationType == 'approved_failed' ? _approvalDistance : null,
        scoreRanges: _verificationType == 'score_by_distance' ? _scoreRanges : null,
      );

      final alerts = NavigationAlerts(
        enabled: _alertsEnabled,
        speedAlertEnabled: _speedAlertEnabled,
        maxSpeed: _speedAlertEnabled ? _maxSpeed : null,
        noMovementAlertEnabled: _noMovementAlertEnabled,
        noMovementMinutes: _noMovementAlertEnabled ? _noMovementMinutes : null,
        ggAlertEnabled: _ggAlertEnabled,
        ggAlertRange: _ggAlertEnabled ? _ggAlertRange : null,
        routesAlertEnabled: _routesAlertEnabled,
        routesAlertRange: _routesAlertEnabled ? _routesAlertRange : null,
        nbAlertEnabled: _nbAlertEnabled,
        nbAlertRange: _nbAlertEnabled ? _nbAlertRange : null,
        navigatorProximityAlertEnabled: _proximityAlertEnabled,
        proximityDistance: _proximityAlertEnabled ? _proximityDistance : null,
        proximityMinTime: _proximityAlertEnabled ? _proximityMinTime : null,
        batteryAlertEnabled: _batteryAlertEnabled,
        batteryPercentage: _batteryAlertEnabled ? _batteryPercentage : null,
        noReceptionAlertEnabled: _noReceptionAlertEnabled,
        noReceptionMinTime: _noReceptionAlertEnabled ? _noReceptionMinTime : null,
        healthCheckEnabled: _healthCheckEnabled,
        healthCheckIntervalMinutes: _healthCheckIntervalMinutes,
      );

      // חישוב מיקום פתיחת מפה - במרכז הגבול אם קיים
      double? openingLat;
      double? openingLng;
      if (_selectedBoundaryId != null) {
        final boundary = _boundaries.firstWhere(
          (b) => b.id == _selectedBoundaryId,
          orElse: () => _boundaries.first,
        );
        if (boundary.coordinates.isNotEmpty) {
          final center = GeometryUtils.getPolygonCenter(boundary.coordinates);
          openingLat = center.lat;
          openingLng = center.lng;
        }
      }

      final displaySettings = DisplaySettings(
        defaultMap: _defaultMapType,
        openingLat: openingLat,
        openingLng: openingLng,
      );

      // קבלת משתמש נוכחי
      final currentUser = await _authService.getCurrentUser();
      if (currentUser == null) {
        throw Exception('משתמש לא מחובר');
      }

      // בדיקת שדות חובה
      if (_selectedArea == null) {
        throw Exception('נא לבחור אזור');
      }
      if (_selectedBoundaryId == null) {
        throw Exception('נא לבחור גבול גזרה');
      }
      if (_selectedUnit == null) {
        throw Exception('נא לבחור מסגרת מנווטת');
      }
      if (_selectedTree == null) {
        throw Exception('לא נמצא עץ ניווט עבור המסגרת שנבחרה');
      }

      // יצירת ניווט
      final now = DateTime.now();
      final navigation = domain.Navigation(
        id: widget.navigation?.id ?? now.millisecondsSinceEpoch.toString(),
        name: _nameController.text,
        status: widget.navigation?.status ?? 'preparation', // שמירת הסטטוס הנוכחי בעריכה
        createdBy: widget.navigation?.createdBy ?? currentUser.uid,
        treeId: _selectedTree!.id,
        areaId: _selectedArea!.id,
        selectedUnitId: _selectedUnit?.id,
        selectedSubFrameworkIds: _selectedSubFrameworkIds.toList(),
        selectedParticipantIds: _selectedParticipantIds.toList(),
        layerNzId: '', // TODO: צריך לטעון מהאזור
        layerNbId: '', // TODO: צריך לטעון מהאזור
        layerGgId: _selectedBoundaryId ?? '',
        layerBaId: null,
        distributionMethod: _distributionMethod,
        navigationType: _navigationType,
        executionOrder: null,
        routeLengthKm: domain.RouteLengthRange(min: _distanceMin, max: _distanceMax),
        checkpointsPerNavigator: null,
        startPoint: null,
        endPoint: null,
        waypointSettings: const WaypointSettings(), // ברירת מחדל: ללא נקודות ביניים
        boundaryLayerId: _selectedBoundaryId,
        safetyTime: safetyTime,
        distributeNow: _distributeNow,
        learningSettings: learningSettings,
        verificationSettings: verificationSettings,
        allowOpenMap: _allowOpenMap,
        showSelfLocation: _showSelfLocation,
        showRouteOnMap: _showRouteOnMap,
        alerts: alerts,
        securitySettings: const SecuritySettings(), // ברירת מחדל
        communicationSettings: CommunicationSettings(walkieTalkieEnabled: _walkieTalkieEnabled),
        reviewSettings: reviewSettings,
        displaySettings: displaySettings,
        routes: widget.navigation?.routes ?? const {}, // שמירת הצירים הקיימים
        routesStage: widget.navigation?.routesStage, // שמירת שלב הצירים
        routesDistributed: widget.navigation?.routesDistributed ?? false, // שמירת סטטוס חלוקה
        trainingStartTime: widget.navigation?.trainingStartTime,
        systemCheckStartTime: widget.navigation?.systemCheckStartTime,
        activeStartTime: widget.navigation?.activeStartTime,
        gpsUpdateIntervalSeconds: _gpsUpdateInterval,
        enabledPositionSources: _buildEnabledPositionSources(),
        allowManualPosition: _allowManualPosition,
        timeCalculationSettings: TimeCalculationSettings(
          enabled: _timeCalcEnabled,
          isHeavyLoad: _isHeavyLoad,
          isNightNavigation: _isNightNavigation,
          isSummer: _isSummer,
        ),
        permissions: widget.navigation?.permissions ?? domain.NavigationPermissions(
          managers: [currentUser.uid],
          viewers: [],
        ),
        createdAt: widget.navigation?.createdAt ?? now,
        updatedAt: now,
      );

      // שמירה במאגר
      if (widget.navigation == null) {
        await _navigationRepository.create(navigation);

        // העתקת שכבות לניווט - רק בעת יצירת ניווט חדש עם גבול גזרה
        if (_selectedBoundaryId != null && _selectedArea != null) {
          final copyResult = await _layerCopyService.copyLayersForNavigation(
            navigationId: navigation.id,
            boundaryId: _selectedBoundaryId!,
            areaId: _selectedArea!.id,
            createdBy: currentUser.uid,
          );

          if (mounted && !copyResult.hasError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'הועתקו ${copyResult.totalCopied} שכבות לניווט '
                  '(${copyResult.checkpointsCopied} נ"צ, '
                  '${copyResult.safetyPointsCopied} נת"ב, '
                  '${copyResult.clustersCopied} ב"א)',
                ),
                backgroundColor: Colors.blue,
                duration: const Duration(seconds: 4),
              ),
            );
          } else if (mounted && copyResult.hasError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('אזהרה: ${copyResult.error}'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      } else {
        await _navigationRepository.update(navigation);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.navigation == null
                  ? 'ניווט נוצר בהצלחה'
                  : 'ניווט עודכן בהצלחה',
            ),
            backgroundColor: Colors.green,
          ),
        );

        // אם זה ניווט חדש - נווט למסך הכנת ניווט
        if (widget.navigation == null) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => NavigationPreparationScreen(navigation: navigation),
            ),
          );
        } else {
          // אם זו עריכה - חזור למסך הקודם
          Navigator.pop(context, true);
        }
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
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }
}
