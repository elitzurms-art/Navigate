import 'dart:async';
import 'package:flutter/material.dart';
import '../../../domain/entities/navigation.dart' as domain;
import '../../../domain/entities/navigation_settings.dart';
import '../../../domain/entities/security_violation.dart';
import '../../../domain/entities/area.dart';
import '../../../domain/entities/navigation_tree.dart';
import '../../../domain/entities/user.dart' as domain_user;
import '../../../data/repositories/area_repository.dart';
import '../../../data/repositories/navigation_tree_repository.dart';
import '../../../data/repositories/navigation_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/repositories/unit_repository.dart';
import '../../../data/sync/sync_manager.dart';
import '../../../core/constants/app_constants.dart';
import '../../../domain/entities/unit.dart' as domain_unit;
import '../../../services/auth_service.dart';
import '../../../services/navigation_layer_copy_service.dart';
import '../../../data/repositories/nav_layer_repository.dart';
import '../../../data/repositories/boundary_repository.dart';
import '../../../domain/entities/boundary.dart' as domain_boundary;
import '../../../core/utils/geometry_utils.dart';
import '../../../core/map_config.dart';
import 'boundary_setup_screen.dart';
import '../../../domain/entities/nav_layer.dart';
import 'navigation_preparation_screen.dart';
import '../../../domain/entities/checkpoint_punch.dart';
import '../../widgets/alert_volume_control.dart';

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
  final _navigationRepository = NavigationRepository();
  final _userRepository = UserRepository();
  final _unitRepository = UnitRepository();
  final _layerCopyService = NavigationLayerCopyService();
  final _navLayerRepo = NavLayerRepository();
  final _boundaryRepo = BoundaryRepository();
  final _authService = AuthService();

  // Data
  List<Area> _areas = [];
  List<NavigationTree> _trees = [];
  List<domain_unit.Unit> _permittedUnits = [];
  bool _isLoading = false;
  bool _isSaving = false;

  // הגדרות שטח ומשתתפים
  double _distanceMin = 5.0;
  double _distanceMax = 8.0;
  String _navigationType = 'regular'; // regular, clusters, star, reverse, parachute, developing
  Area? _selectedArea;
  BoundarySetupResult? _boundaryResult;
  BoundarySetupResult? _originalBoundaryResult; // גבול מקורי (לזיהוי שינוי בעריכה)
  bool _boundaryAdvancedMode = false; // false=ג"ג קיים, true=מתקדם
  List<domain_boundary.Boundary> _areaBoundaries = []; // גבולות גזרה של האזור הנבחר
  String? _selectedSimpleBoundaryId; // ג"ג קיים שנבחר
  int _boundaryDropdownKey = 0; // מאלץ rebuild של dropdown בביטול אזהרה
  domain_unit.Unit? _selectedUnit;
  NavigationTree? _selectedTree;

  // בחירת תתי-מסגרות ומשתתפים
  Set<String> _selectedSubFrameworkIds = {};
  Set<String> _selectedParticipantIds = {};
  Map<String, domain_user.User> _usersCache = {};
  Map<String, List<String>> _subFrameworkUsers = {}; // sfId → userIds (dynamic)
  bool _isLoadingUsers = false;

  // הגדרות נקודות
  String _distributionMethod = 'automatic'; // automatic, manual_app, manual_full
  bool _distributeNow = false;

  // הגדרות ניווט
  int _gpsUpdateInterval = 5; // דינמי ברירת מחדל

  String get _samplingModeDescription {
    if (_gpsUpdateInterval <= 2) return 'GPS רציף + PDR — צריכת סוללה גבוהה';
    if (_gpsUpdateInterval <= 10) return 'איזון מושלם — דגימה כל 5 שניות';
    return 'חיסכון סוללה — דגימה כל 30 שניות, ללא PDR';
  }

  // הגדרות מיקום
  bool _useAllPositionSources = true;
  bool _enableGps = true;
  bool _enableCellTower = true;
  bool _enablePdr = true;
  bool _enablePdrCellHybrid = true;

  bool _autoVerification = true;
  String _verificationType = 'approved_failed'; // approved_failed, score_by_distance
  String _punchMode = 'sequential'; // 'sequential' או 'free'
  int _approvalDistance = 40;
  List<DistanceScoreRange> _scoreRanges = [
    const DistanceScoreRange(maxDistance: 50, scorePercentage: 100),
  ];
  bool _addRangeToggle = false;
  bool _allowOpenMap = false;
  bool _showSelfLocation = false;
  bool _showRouteOnMap = false;
  bool _allowManualPosition = false;
  bool _gpsSpoofingDetectionEnabled = true;
  int _gpsSpoofingMaxDistanceKm = 50;

  // מבחן
  bool _requireCommanderQuiz = false;
  bool _requireSoloQuiz = false;
  String _quizType = 'solo';

  // תקשורת (ווקי טוקי)
  bool _walkieTalkieEnabled = true;

  // חישוב זמנים
  bool _timeCalcEnabled = true;
  bool _isHeavyLoad = false;
  bool _isNightNavigation = true;
  bool _isSummer = true;
  bool _allowExtensionRequests = true;
  String _extensionWindowType = 'all';
  int _extensionWindowHours = 0;
  int _extensionWindowMinutes = 30;

  // הגדרות תצוגה
  String _defaultMapType = 'topographic'; // ברירת מחדל: טופוגרפית
  bool _enableVariablesSheet = true; // מילוי דף משתנים דיגיטלי

  // התראות
  bool _alertsEnabled = true;
  bool _speedAlertEnabled = true;
  int _maxSpeed = 50;
  bool _noMovementAlertEnabled = true;
  int _noMovementMinutes = 10;
  bool _ggAlertEnabled = true;
  int _ggAlertRange = 100;
  bool _routesAlertEnabled = true;
  int _routesAlertRange = 50;
  bool _nbAlertEnabled = true;
  int _nbAlertRange = 50;
  bool _proximityAlertEnabled = true;
  int _proximityDistance = 20;
  int _proximityMinTime = 5;
  bool _batteryAlertEnabled = true;
  int _batteryPercentage = 20;
  bool _noReceptionAlertEnabled = true;
  int _noReceptionMinTime = 30;
  bool _healthCheckEnabled = true;
  int _healthCheckIntervalMinutes = 60;
  Map<String, double> _alertSoundVolumes = {};
  StreamSubscription<String>? _syncSubscription;
  Timer? _autoSaveTimer;
  Timer? _debounceTimer;
  bool _hasUnsavedChanges = false;

  @override
  void initState() {
    super.initState();
    _initializeScreen();
    // האזנה לשינויי סנכרון — רענון כשמשתמשים חדשים מסתנכרנים (עם debounce)
    _syncSubscription = SyncManager().onDataChanged.listen((collection) {
      if (collection == AppConstants.usersCollection && mounted) {
        _debounceTimer?.cancel();
        _debounceTimer = Timer(const Duration(milliseconds: 300), () {
          if (mounted) _loadUsersForSelectedSubFrameworks();
        });
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
          ? _filterPermittedUnits(allUnits, currentUser)
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
      List<domain_unit.Unit> allUnits, domain_user.User currentUser) {
    // מפתח רואה הכל
    if (currentUser.isDeveloper) return allUnits;

    final uid = currentUser.uid;

    // מצא יחידות שהמשתמש מנהל ישירות
    final managedIds = <String>{};
    for (final unit in allUnits) {
      if (unit.managerIds.contains(uid)) {
        managedIds.add(unit.id);
      }
    }

    // הוסף גם את היחידה של המשתמש עצמו
    if (currentUser.unitId != null && currentUser.unitId!.isNotEmpty) {
      managedIds.add(currentUser.unitId!);
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
    } else if (mounted) {
      // Auto-create tree with default fixed sub-frameworks
      // (self-healing: tree may have been lost due to sync failure)
      final currentUser = await _authService.getCurrentUser();
      if (currentUser != null) {
        final now = DateTime.now();
        final treeId = 'tree_${unit.id}';
        final tree = NavigationTree(
          id: treeId,
          name: 'עץ מבנה - ${unit.name}',
          subFrameworks: [
            SubFramework(
              id: '${treeId}_cmd_mgmt',
              name: 'מפקדים ומנהלת - ${unit.name}',
              userIds: const [],
              isFixed: true,
              unitId: unit.id,
            ),
            SubFramework(
              id: '${treeId}_soldiers',
              name: 'חיילים - ${unit.name}',
              userIds: const [],
              isFixed: true,
              unitId: unit.id,
            ),
          ],
          createdBy: currentUser.uid,
          createdAt: now,
          updatedAt: now,
          unitId: unit.id,
        );
        await _treeRepository.create(tree);
        setState(() {
          _selectedTree = tree;
        });
      }
    }
    _onSettingChanged();
  }

  /// כשתת-מסגרת נבחרת/מבוטלת — עדכון המשתתפים
  void _onSubFrameworkToggled(String subFrameworkId, bool selected) {
    setState(() {
      if (selected) {
        _selectedSubFrameworkIds.add(subFrameworkId);
      } else {
        _selectedSubFrameworkIds.remove(subFrameworkId);
        // הסרת משתתפים מתת-מסגרת שבוטלה
        final sfUsers = _subFrameworkUsers[subFrameworkId] ?? [];
        _selectedParticipantIds.removeAll(sfUsers);
      }
    });
    _loadUsersForSelectedSubFrameworks();
    _onSettingChanged();
  }

  /// בחירת/ביטול כל המשתתפים בתת-מסגרת
  void _toggleAllParticipantsInSubFramework(String sfId, bool selectAll) {
    final sfUsers = _subFrameworkUsers[sfId] ?? [];
    setState(() {
      if (selectAll) {
        _selectedParticipantIds.addAll(sfUsers);
      } else {
        _selectedParticipantIds.removeAll(sfUsers);
      }
    });
    _onSettingChanged();
  }

  /// טעינת משתמשים דינמית לפי תפקיד — מפקדים או מנווטים בהתאם לתת-מסגרת
  Future<void> _loadUsersForSelectedSubFrameworks() async {
    if (_selectedTree == null || _selectedUnit == null) return;

    setState(() => _isLoadingUsers = true);
    try {
      final unitId = _selectedUnit!.id;
      for (final sf in _selectedTree!.subFrameworks) {
        if (!_selectedSubFrameworkIds.contains(sf.id)) continue;

        // קביעת סוג משתמשים לפי שם תת-מסגרת
        List<domain_user.User> users;
        if (sf.name.contains('מפקדים') || sf.name.contains('מפקד')) {
          users = await _userRepository.getCommandersForUnit(unitId);
        } else {
          users = await _userRepository.getNavigatorsForUnit(unitId);
        }

        _subFrameworkUsers[sf.id] = users.map((u) => u.uid).toList();

        // עדכון cache שמות
        for (final user in users) {
          _usersCache[user.uid] = user;
        }
      }
    } catch (e) {
      print('DEBUG: Error loading users: $e');
    }
    if (mounted) {
      setState(() => _isLoadingUsers = false);
    }
  }

  /// רשימת כל ה-userIds מתתי-המסגרות הנבחרות (דינמי)
  List<String> get _allSelectedSubFrameworkUserIds {
    if (_selectedTree == null) return [];
    final ids = <String>[];
    for (final sf in _selectedTree!.subFrameworks) {
      if (_selectedSubFrameworkIds.contains(sf.id)) {
        ids.addAll(_subFrameworkUsers[sf.id] ?? []);
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
    _punchMode = nav.verificationSettings.punchMode;
    final loadedRanges = nav.verificationSettings.scoreRanges ?? [];
    _scoreRanges = loadedRanges.isNotEmpty
        ? loadedRanges
        : [const DistanceScoreRange(maxDistance: 50, scorePercentage: 100)];

    // הגדרות מפה
    _allowOpenMap = nav.allowOpenMap;
    _showSelfLocation = nav.showSelfLocation;
    _showRouteOnMap = nav.showRouteOnMap;
    _allowManualPosition = nav.allowManualPosition;
    _gpsSpoofingDetectionEnabled = nav.gpsSpoofingDetectionEnabled;
    _gpsSpoofingMaxDistanceKm = nav.gpsSpoofingMaxDistanceKm;

    // מבחן
    _requireCommanderQuiz = nav.learningSettings.requireCommanderQuiz;
    _requireSoloQuiz = nav.learningSettings.requireSoloQuiz;
    _quizType = nav.learningSettings.quizType;

    // תקשורת
    _walkieTalkieEnabled = nav.communicationSettings.walkieTalkieEnabled;

    // חישוב זמנים
    _timeCalcEnabled = nav.timeCalculationSettings.enabled;
    _isHeavyLoad = nav.timeCalculationSettings.isHeavyLoad;
    _isNightNavigation = nav.timeCalculationSettings.isNightNavigation;
    _isSummer = nav.timeCalculationSettings.isSummer;
    _allowExtensionRequests = nav.timeCalculationSettings.allowExtensionRequests;
    _extensionWindowType = nav.timeCalculationSettings.extensionWindowType;
    final ewm = nav.timeCalculationSettings.extensionWindowMinutes ?? 0;
    _extensionWindowHours = ewm ~/ 60;
    _extensionWindowMinutes = ewm % 60;

    // הגדרות תצוגה
    _defaultMapType = nav.displaySettings.defaultMap ?? 'topographic';
    _enableVariablesSheet = nav.displaySettings.enableVariablesSheet;

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
    _alertSoundVolumes = Map<String, double>.from(nav.alerts.alertSoundVolumes ?? {});

    // טעינת אזור, עץ וגבול
    await _loadAreaTreeAndBoundary();
  }

  Future<void> _loadAreaBoundaries(String areaId) async {
    try {
      final boundaries = await _boundaryRepo.getByArea(areaId);
      if (mounted) {
        setState(() => _areaBoundaries = boundaries);
      }
    } catch (e) {
      print('DEBUG: Error loading area boundaries: $e');
    }
  }

  Future<void> _loadAreaTreeAndBoundary() async {
    final nav = widget.navigation!;

    // חיפוש האזור הנבחר
    _selectedArea = _areas.firstWhere(
      (area) => area.id == nav.areaId,
      orElse: () => _areas.isNotEmpty ? _areas.first : throw Exception('No areas found'),
    );

    // טעינת גבולות גזרה של האזור
    await _loadAreaBoundaries(nav.areaId);

    // טעינת גבול ניווט קיים — מנסה לקרוא NavBoundary מ-DB
    final existingBoundaryIds = nav.boundaryLayerIds.isNotEmpty
        ? nav.boundaryLayerIds
        : (nav.boundaryLayerId != null ? [nav.boundaryLayerId!] : <String>[]);

    if (existingBoundaryIds.isNotEmpty) {
      try {
        final navBoundaries = await _navLayerRepo.getBoundariesByNavigation(nav.id);
        if (navBoundaries.isNotEmpty) {
          final nb = navBoundaries.first;
          _boundaryResult = BoundarySetupResult(
            coordinates: nb.coordinates,
            multiPolygonCoordinates: nb.multiPolygonCoordinates,
            geometryType: nb.geometryType,
            creationMode: nb.creationMode,
            sourceBoundaryIds: nb.sourceBoundaryIds,
            areaId: nb.areaId,
            name: nb.name,
          );
        } else {
          // fallback: שימוש ב-IDs בלבד ללא קואורדינטות (legacy)
          _boundaryResult = BoundarySetupResult(
            coordinates: const [],
            geometryType: 'polygon',
            creationMode: NavBoundaryCreationMode.legacy,
            sourceBoundaryIds: existingBoundaryIds,
            areaId: nav.areaId,
            name: 'גבול ניווט',
          );
        }
      } catch (e) {
        print('DEBUG: Error loading nav boundary: $e');
        _boundaryResult = BoundarySetupResult(
          coordinates: const [],
          geometryType: 'polygon',
          creationMode: NavBoundaryCreationMode.legacy,
          sourceBoundaryIds: existingBoundaryIds,
          areaId: nav.areaId,
          name: 'גבול ניווט',
        );
      }
    }

    // זיהוי מצב פשוט vs מתקדם
    if (_boundaryResult != null) {
      final mode = _boundaryResult!.creationMode;
      if (mode == NavBoundaryCreationMode.legacy &&
          _boundaryResult!.sourceBoundaryIds.length == 1) {
        // ג"ג קיים — מצב פשוט
        _boundaryAdvancedMode = false;
        _selectedSimpleBoundaryId = _boundaryResult!.sourceBoundaryIds.first;
      } else if (mode != NavBoundaryCreationMode.legacy) {
        _boundaryAdvancedMode = true;
      }
      // שמירת גבול מקורי לזיהוי שינוי בעריכה
      _originalBoundaryResult = _boundaryResult;
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
    _debounceTimer?.cancel();
    _autoSaveTimer?.cancel();
    _syncSubscription?.cancel();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (widget.navigation != null) {
          // מצב עריכה: שמירה אוטומטית — תמיד אפשר לחזור
          Navigator.pop(context, true);
        } else if (_hasUnsavedChanges) {
          // מצב יצירה עם שינויים: אזהרה
          _showBackWarning();
        } else {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
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
          else if (widget.navigation == null)
            TextButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('צור', style: TextStyle(color: Colors.white)),
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
                      onChanged: (_) => _onSettingChanged(),
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

                    // הגדרות תצוגה
                    _buildSectionTitle('הגדרות תצוגה'),
                    _buildDisplaySettings(),
                  ],

                  const SizedBox(height: 32),
                ],
              ),
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
                setState(() {
                  _selectedArea = value;
                  // איפוס גבול ניווט כשמחליפים אזור
                  if (_boundaryResult != null && _boundaryResult!.areaId != value?.id) {
                    _boundaryResult = null;
                    _selectedSimpleBoundaryId = null;
                  }
                  _areaBoundaries = [];
                });
                if (value != null) _loadAreaBoundaries(value.id);
                _onSettingChanged();
              },
              validator: (value) => value == null ? 'נא לבחור אזור' : null,
            ),
            const SizedBox(height: 16),

            // גבול ניווט
            const Text('גבול ניווט', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            // בחירה בין ג"ג קיים למתקדם
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('ג"ג קיים')),
                      ButtonSegment(value: true, label: Text('מתקדם')),
                    ],
                    selected: {_boundaryAdvancedMode},
                    onSelectionChanged: _selectedArea == null ? null : (selected) {
                      setState(() => _boundaryAdvancedMode = selected.first);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (!_boundaryAdvancedMode) ...[
              // ===== מצב פשוט — ג"ג קיים =====
              FormField<String>(
                validator: (_) => _boundaryResult == null ? 'נא לבחור גבול גזרה' : null,
                builder: (field) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<String>(
                      key: ValueKey('boundary_dd_$_boundaryDropdownKey'),
                      value: _selectedSimpleBoundaryId,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'בחר גבול גזרה',
                        prefixIcon: Icon(Icons.crop_square),
                        isDense: true,
                      ),
                      items: _areaBoundaries.map((b) {
                        return DropdownMenuItem(
                          value: b.id,
                          child: Text(b.name),
                        );
                      }).toList(),
                      onChanged: _selectedArea == null ? null : (value) {
                        if (value != null) _onSimpleBoundarySelected(value);
                      },
                    ),
                    if (field.hasError)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(field.errorText!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
                      ),
                  ],
                ),
              ),
            ] else ...[
              // ===== מצב מתקדם =====
              if (_boundaryResult != null && _boundaryAdvancedMode) ...[
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.check_circle, color: Colors.green),
                    title: Text(_boundaryResult!.name),
                    subtitle: Text(_boundaryModeLabel(_boundaryResult!.creationMode)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: _openBoundarySetup,
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.red),
                          onPressed: () async {
                            if (!await _confirmBoundaryChange()) return;
                            setState(() {
                              _boundaryResult = null;
                              _selectedSimpleBoundaryId = null;
                            });
                            _onSettingChanged();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.add_location_alt),
                    label: const Text('הגדרת גבול ניווט מתקדם'),
                    onPressed: _selectedArea != null ? _openBoundarySetup : null,
                  ),
                ),
                FormField<String>(
                  validator: (_) => _boundaryResult == null ? 'נא להגדיר גבול ניווט' : null,
                  builder: (field) => field.hasError
                      ? Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(field.errorText!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
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
                final dynamicCount = _subFrameworkUsers[sf.id]?.length;
                return CheckboxListTile(
                  title: Text(sf.name),
                  subtitle: Text(dynamicCount != null
                      ? '$dynamicCount משתמשים'
                      : 'משויך אוטומטית לפי תפקיד'),
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
                  final sfUsers = _subFrameworkUsers[sf.id] ?? [];
                  final allSelected = sfUsers.isNotEmpty && sfUsers.every((uid) => _selectedParticipantIds.contains(uid));
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
                              _toggleAllParticipantsInSubFramework(sf.id, !allSelected);
                            },
                            child: Text(
                              allSelected ? 'בטל הכל' : 'בחר הכל',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      ...sfUsers.map((uid) {
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
                            _onSettingChanged();
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

          ],
        ),
      ),
    );
  }

  /// סימון שינוי בהגדרות — במצב עריכה: שמירה אוטומטית עם debounce
  void _onSettingChanged() {
    _hasUnsavedChanges = true;
    if (widget.navigation != null) {
      _autoSaveTimer?.cancel();
      _autoSaveTimer = Timer(const Duration(seconds: 1), () {
        if (mounted) _performSave(silent: true);
      });
    }
  }

  /// אזהרת חזרה במצב יצירה עם שינויים שלא נשמרו
  Future<void> _showBackWarning() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('שינויים לא נשמרו'),
        content: const Text('יש לך שינויים שלא נשמרו. לצאת בכל זאת?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('יציאה'),
          ),
        ],
      ),
    );
    if (result == true && mounted) {
      Navigator.pop(context);
    }
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
              onChanged: (value) {
                setState(() => _walkieTalkieEnabled = value);
                _onSettingChanged();
              },
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
              onChanged: (v) {
                setState(() => _timeCalcEnabled = v);
                _onSettingChanged();
              },
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
                onSelectionChanged: (v) {
                  setState(() => _isHeavyLoad = v.first);
                  _onSettingChanged();
                },
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
                onSelectionChanged: (v) {
                  setState(() => _isNightNavigation = v.first);
                  _onSettingChanged();
                },
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
                onSelectionChanged: (v) {
                  setState(() => _isSummer = v.first);
                  _onSettingChanged();
                },
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
              const Divider(height: 24),
              // בקשות הארכה
              SwitchListTile(
                title: const Text('אפשר בקשות הארכה'),
                subtitle: const Text('מנווטים יוכלו לבקש זמן נוסף במהלך הניווט'),
                value: _allowExtensionRequests,
                contentPadding: EdgeInsets.zero,
                onChanged: (v) {
                  setState(() => _allowExtensionRequests = v);
                  _onSettingChanged();
                },
              ),
              if (_allowExtensionRequests) ...[
                const SizedBox(height: 8),
                const Text('חלון בקשה', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'all', label: Text('כל הניווט')),
                    ButtonSegment(value: 'timed', label: Text('זמן מוגדר מסיום')),
                  ],
                  selected: {_extensionWindowType},
                  onSelectionChanged: (v) {
                    setState(() => _extensionWindowType = v.first);
                    _onSettingChanged();
                  },
                ),
                if (_extensionWindowType == 'timed') ...[
                  const SizedBox(height: 12),
                  const Text('זמן לפני סיום הניווט שבו ניתן לבקש הארכה:',
                      style: TextStyle(fontSize: 13, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _extensionWindowHours,
                          decoration: const InputDecoration(
                            labelText: 'שעות',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          items: List.generate(5, (i) => DropdownMenuItem(
                            value: i,
                            child: Text('$i'),
                          )),
                          onChanged: (v) {
                            setState(() => _extensionWindowHours = v ?? 0);
                            _onSettingChanged();
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _extensionWindowMinutes,
                          decoration: const InputDecoration(
                            labelText: 'דקות',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          items: List.generate(12, (i) => DropdownMenuItem(
                            value: i * 5,
                            child: Text('${i * 5}'),
                          )),
                          onChanged: (v) {
                            setState(() => _extensionWindowMinutes = v ?? 0);
                            _onSettingChanged();
                          },
                        ),
                      ),
                    ],
                  ),
                  if (_extensionWindowHours == 0 && _extensionWindowMinutes == 0)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        'יש לבחור זמן גדול מ-0',
                        style: TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                ],
              ],
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
            // איכות דגימת מיקום
            ListTile(
              leading: const Icon(Icons.location_searching, color: Colors.blue),
              title: const Text('איכות דגימת מיקום'),
              subtitle: Text(_samplingModeDescription),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 30, label: Text('חסכוני'), icon: Icon(Icons.battery_saver)),
                  ButtonSegment(value: 5, label: Text('דינמי'), icon: Icon(Icons.speed)),
                  ButtonSegment(value: 1, label: Text('מדויק'), icon: Icon(Icons.gps_fixed)),
                ],
                selected: {_gpsUpdateInterval <= 2 ? 1 : _gpsUpdateInterval <= 10 ? 5 : 30},
                onSelectionChanged: (Set<int> sel) {
                  setState(() => _gpsUpdateInterval = sel.first);
                  _onSettingChanged();
                },
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
                _onSettingChanged();
              },
            ),
            if (!_useAllPositionSources) ...[
              SwitchListTile(
                secondary: const Icon(Icons.gps_fixed),
                title: const Text('GPS'),
                value: _enableGps,
                onChanged: (value) {
                  setState(() => _enableGps = value);
                  _onSettingChanged();
                },
              ),
              SwitchListTile(
                secondary: const Icon(Icons.cell_tower),
                title: const Text('אנטנות סלולריות'),
                value: _enableCellTower,
                onChanged: (value) {
                  setState(() => _enableCellTower = value);
                  _onSettingChanged();
                },
              ),
              SwitchListTile(
                secondary: const Icon(Icons.directions_walk),
                title: const Text('PDR — חישוב הליכה'),
                value: _enablePdr,
                onChanged: (value) {
                  setState(() => _enablePdr = value);
                  _onSettingChanged();
                },
              ),
              SwitchListTile(
                secondary: const Icon(Icons.merge_type),
                title: const Text('PDR + אנטנות (משולב)'),
                value: _enablePdrCellHybrid,
                onChanged: (value) {
                  setState(() => _enablePdrCellHybrid = value);
                  _onSettingChanged();
                },
              ),
            ],
            const Divider(),
            SwitchListTile(
              secondary: const Icon(Icons.push_pin, color: Colors.deepPurple),
              title: const Text('אפשר דקירת מיקום עצמי'),
              subtitle: const Text('כאשר אין GPS ואמצעים חלופיים'),
              value: _allowManualPosition,
              onChanged: (value) {
                setState(() => _allowManualPosition = value);
                _onSettingChanged();
              },
            ),
            const Divider(),
            SwitchListTile(
              secondary: const Icon(Icons.security, color: Colors.orange),
              title: const Text('הפעל מענה להטעיית GPS'),
              subtitle: const Text('חסימת מיקומים מזויפים רחוקים מגבול הגזרה'),
              value: _gpsSpoofingDetectionEnabled,
              onChanged: (value) {
                setState(() => _gpsSpoofingDetectionEnabled = value);
                _onSettingChanged();
              },
            ),
            if (_gpsSpoofingDetectionEnabled) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Icon(Icons.straighten, size: 20, color: Colors.grey),
                    const SizedBox(width: 8),
                    const Text('מרחק ממרכז גבול גזרה'),
                    const Spacer(),
                    Text(
                      '$_gpsSpoofingMaxDistanceKm ק״מ',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              Slider(
                value: _gpsSpoofingMaxDistanceKm.toDouble(),
                min: 1,
                max: 1000,
                divisions: 999,
                label: '$_gpsSpoofingMaxDistanceKm ק״מ',
                onChanged: (value) {
                  setState(() => _gpsSpoofingMaxDistanceKm = value.round());
                  _onSettingChanged();
                },
              ),
            ],
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
                title: const Text('הפעל מבחן מפקדים'),
                subtitle: const Text('מפקדים יידרשו לעבור מבחן ידע'),
                value: _requireCommanderQuiz,
                onChanged: (value) {
                  setState(() => _requireCommanderQuiz = value);
                  _onSettingChanged();
                },
              ),
              SwitchListTile(
                title: const Text('הפעל מבחן למנווטים'),
                subtitle: const Text('מנווטים יידרשו לעבור מבחן ידע לפני הניווט'),
                value: _requireSoloQuiz,
                onChanged: (value) {
                  setState(() => _requireSoloQuiz = value);
                  _onSettingChanged();
                },
              ),
              if (_requireSoloQuiz) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'solo', label: Text('ניווט בדד')),
                      ButtonSegment(value: 'regular', label: Text('ניווט רגיל')),
                    ],
                    selected: {_quizType},
                    onSelectionChanged: (selected) {
                      setState(() => _quizType = selected.first);
                      _onSettingChanged();
                    },
                  ),
                ),
              ],
              const Divider(),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text('מצב דקירה', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
              RadioListTile<String>(
                title: const Text('סדרתי — המנווט דוקר לפי סדר הציר'),
                value: 'sequential',
                groupValue: _punchMode,
                onChanged: (value) {
                  setState(() => _punchMode = value!);
                  _onSettingChanged();
                },
              ),
              RadioListTile<String>(
                title: const Text('חופשי — המנווט בוחר איזו נקודה לדקור'),
                value: 'free',
                groupValue: _punchMode,
                onChanged: (value) {
                  setState(() => _punchMode = value!);
                  _onSettingChanged();
                },
              ),
              const Divider(),
              SwitchListTile(
                title: const Text('הפעל אימות נקודות אוטומטי'),
                value: _autoVerification,
                onChanged: (value) {
                  setState(() => _autoVerification = value);
                  _onSettingChanged();
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
                  _onSettingChanged();
                },
              ),
              RadioListTile<String>(
                title: const Text('ציון לפי מרחק'),
                value: 'score_by_distance',
                groupValue: _verificationType,
                onChanged: (value) {
                  setState(() => _verificationType = value!);
                  _onSettingChanged();
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
                      _approvalDistance = int.tryParse(value) ?? 40;
                      _onSettingChanged();
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
                                        _onSettingChanged();
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
                                        _onSettingChanged();
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
                                          _onSettingChanged();
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
                            _onSettingChanged();
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
                  _onSettingChanged();
                },
              ),
            ],

            if (_allowOpenMap && !widget.alertsOnlyMode) ...[
              SwitchListTile(
                title: const Text('אפשר הצגת מיקום עצמי למנווט'),
                value: _showSelfLocation,
                onChanged: (value) {
                  setState(() => _showSelfLocation = value);
                  _onSettingChanged();
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
                _onSettingChanged();
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
                      min: 15,
                      max: 600,
                      divisions: 39,
                      label: _healthCheckIntervalMinutes >= 60
                          ? '${(_healthCheckIntervalMinutes / 60).toStringAsFixed(_healthCheckIntervalMinutes % 60 == 0 ? 0 : 1)} שעות'
                          : '$_healthCheckIntervalMinutes דקות',
                      onChanged: (value) {
                        setState(() => _healthCheckIntervalMinutes = value.round());
                        _onSettingChanged();
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
                _onSettingChanged();
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

  Widget _buildAlertVolumeRow(String alertCode) {
    return AlertVolumeControl(
      volume: _alertSoundVolumes[alertCode] ?? 1.0,
      onVolumeChanged: (v) {
        setState(() {
          if (v == 1.0) {
            _alertSoundVolumes.remove(alertCode);
          } else {
            _alertSoundVolumes[alertCode] = v;
          }
        });
        _onSettingChanged();
      },
    );
  }

  Widget _buildAlertsSettings() {
    return Column(
      children: [
        // התראת מהירות
        Row(
          children: [
            _buildAlertVolumeRow(AlertType.speed.code),
            Expanded(child: SwitchListTile(
              title: const Text('התראת מהירות'),
              value: _speedAlertEnabled,
              onChanged: (value) {
                setState(() => _speedAlertEnabled = value);
                _onSettingChanged();
              },
            )),
          ],
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
                _onSettingChanged();
              },
            ),
          ),

        // התראת חוסר תנועה
        Row(
          children: [
            _buildAlertVolumeRow(AlertType.noMovement.code),
            Expanded(child: SwitchListTile(
              title: const Text('התראת חוסר תנועה'),
              value: _noMovementAlertEnabled,
              onChanged: (value) {
                setState(() => _noMovementAlertEnabled = value);
                _onSettingChanged();
              },
            )),
          ],
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
                _onSettingChanged();
              },
            ),
          ),

        // התראת גבול גזרה
        Row(
          children: [
            _buildAlertVolumeRow(AlertType.boundary.code),
            Expanded(child: SwitchListTile(
              title: const Text('התראת גבול גזרה'),
              value: _ggAlertEnabled,
              onChanged: (value) {
                setState(() => _ggAlertEnabled = value);
                _onSettingChanged();
              },
            )),
          ],
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
                _onSettingChanged();
              },
            ),
          ),

        // התראת נתבים
        Row(
          children: [
            _buildAlertVolumeRow(AlertType.routeDeviation.code),
            Expanded(child: SwitchListTile(
              title: const Text('התראת נתבים'),
              value: _routesAlertEnabled,
              onChanged: (value) {
                setState(() => _routesAlertEnabled = value);
                _onSettingChanged();
              },
            )),
          ],
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
                _onSettingChanged();
              },
            ),
          ),

        // התראת נת"ב
        Row(
          children: [
            _buildAlertVolumeRow(AlertType.safetyPoint.code),
            Expanded(child: SwitchListTile(
              title: const Text('התראת נת"ב'),
              value: _nbAlertEnabled,
              onChanged: (value) {
                setState(() => _nbAlertEnabled = value);
                _onSettingChanged();
              },
            )),
          ],
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
                _onSettingChanged();
              },
            ),
          ),

        // התראת קרבת מנווטים
        Row(
          children: [
            _buildAlertVolumeRow(AlertType.proximity.code),
            Expanded(child: SwitchListTile(
              title: const Text('התראת קרבת מנווטים'),
              value: _proximityAlertEnabled,
              onChanged: (value) {
                setState(() => _proximityAlertEnabled = value);
                _onSettingChanged();
              },
            )),
          ],
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
                    _onSettingChanged();
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
                    _onSettingChanged();
                  },
                ),
              ],
            ),
          ),

        // התראת סוללה
        Row(
          children: [
            _buildAlertVolumeRow(AlertType.battery.code),
            Expanded(child: SwitchListTile(
              title: const Text('התראת סוללה'),
              value: _batteryAlertEnabled,
              onChanged: (value) {
                setState(() => _batteryAlertEnabled = value);
                _onSettingChanged();
              },
            )),
          ],
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
                _onSettingChanged();
              },
            ),
          ),

        // התראת חוסר קליטה
        Row(
          children: [
            _buildAlertVolumeRow(AlertType.noReception.code),
            Expanded(child: SwitchListTile(
              title: const Text('התראת חוסר קליטה'),
              value: _noReceptionAlertEnabled,
              onChanged: (value) {
                setState(() => _noReceptionAlertEnabled = value);
                _onSettingChanged();
              },
            )),
          ],
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
                _onSettingChanged();
              },
            ),
          ),

        // קטגוריות צליל נוספות
        const Divider(),
        _buildCategorySoundRow(
          label: '📋 בקשות הארכה (צליל)',
          alertCode: AlertType.extensionRequest.code,
        ),
        _buildCategorySoundRow(
          label: '⚠️ ברבור (צליל)',
          alertCode: AlertType.barbur.code,
        ),
        _buildCategorySoundRow(
          label: '🚨 חירום מנווט (צליל)',
          alertCode: AlertType.emergency.code,
        ),
      ],
    );
  }

  Widget _buildCategorySoundRow({required String label, required String alertCode}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Row(
        children: [
          AlertVolumeControl(
            volume: _alertSoundVolumes[alertCode] ?? 1.0,
            onVolumeChanged: (v) {
              setState(() {
                if (v == 1.0) {
                  _alertSoundVolumes.remove(alertCode);
                } else {
                  _alertSoundVolumes[alertCode] = v;
                }
              });
              _onSettingChanged();
            },
          ),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 14)),
        ],
      ),
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
                  _onSettingChanged();
                }
              },
            ),

            const SizedBox(height: 16),
            const Text('מיקום פתיחת מפה: מחושב אוטומטית ממרכז הג"ג',
              style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic)),
            const Divider(height: 24),
            SwitchListTile(
              title: const Text('מילוי דף משתנים דיגיטלי'),
              subtitle: const Text('הצגת דף משתנים בשלבי ההכנה'),
              value: _enableVariablesSheet,
              contentPadding: EdgeInsets.zero,
              onChanged: (value) {
                setState(() => _enableVariablesSheet = value);
                _onSettingChanged();
              },
            ),
          ],
        ),
      ),
    );
  }

  String _boundaryModeLabel(NavBoundaryCreationMode mode) {
    switch (mode) {
      case NavBoundaryCreationMode.union:
        return 'איחוד גבולות';
      case NavBoundaryCreationMode.manual:
        return 'ציור ידני';
      case NavBoundaryCreationMode.cloneEdit:
        return 'עריכת גבול קיים';
      case NavBoundaryCreationMode.legacy:
        return 'ג"ג קיים';
    }
  }

  /// האם הגבול השתנה מהמקורי (בעריכת ניווט קיים)?
  bool get _hasBoundaryChanged {
    if (_originalBoundaryResult == null && _boundaryResult == null) return false;
    if (_originalBoundaryResult == null || _boundaryResult == null) return true;
    // השוואה לפי sourceBoundaryIds + creationMode + geometryType
    final orig = _originalBoundaryResult!;
    final curr = _boundaryResult!;
    if (orig.creationMode != curr.creationMode) return true;
    if (orig.geometryType != curr.geometryType) return true;
    if (orig.sourceBoundaryIds.length != curr.sourceBoundaryIds.length) return true;
    for (int i = 0; i < orig.sourceBoundaryIds.length; i++) {
      if (orig.sourceBoundaryIds[i] != curr.sourceBoundaryIds[i]) return true;
    }
    if (orig.coordinates.length != curr.coordinates.length) return true;
    return false;
  }

  /// דיאלוג אזהרה על שינוי גבול (בעריכת ניווט קיים)
  /// מחזיר true אם המשתמש אישר, false אם ביטל
  Future<bool> _confirmBoundaryChange() async {
    // אין אזהרה ביצירת ניווט חדש, או אם אין גבול קודם
    if (widget.navigation == null || _boundaryResult == null) return true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('שינוי גבול ניווט'),
        content: const Text(
          'שינוי הגבול יגרור יצירה מחדש של עותק השכבות הניווטיות '
          '(נ"צ, נת"ב, ב"א) ומחיקת כל המסלולים הקיימים.\n\n'
          'לא ניתן לבטל פעולה זו.\n\n'
          'להמשיך?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('אישור — שנה גבול'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  /// בחירת ג"ג קיים (מצב פשוט)
  Future<void> _onSimpleBoundarySelected(String boundaryId) async {
    // בדיקה: האם זה אותו גבול שכבר נבחר?
    if (_selectedSimpleBoundaryId == boundaryId) return;

    // אזהרה בעריכת ניווט קיים
    if (!await _confirmBoundaryChange()) {
      // DropdownButtonFormField שינה את הערך הפנימי — מאלצים rebuild לחזור לבחירה הקודמת
      setState(() => _boundaryDropdownKey++);
      return;
    }

    final boundary = _areaBoundaries.firstWhere((b) => b.id == boundaryId);
    setState(() {
      _selectedSimpleBoundaryId = boundaryId;
      _boundaryResult = BoundarySetupResult(
        coordinates: boundary.coordinates,
        geometryType: 'polygon',
        creationMode: NavBoundaryCreationMode.legacy,
        sourceBoundaryIds: [boundary.id],
        areaId: boundary.areaId,
        name: boundary.name,
      );
    });
    _onSettingChanged();
  }

  Future<void> _openBoundarySetup() async {
    if (_selectedArea == null) return;

    // אזהרה בעריכת ניווט קיים
    if (!await _confirmBoundaryChange()) return;
    if (!mounted) return;

    final result = await Navigator.push<BoundarySetupResult>(
      context,
      MaterialPageRoute(
        builder: (_) => BoundarySetupScreen(
          areaId: _selectedArea!.id,
          existingBoundaryCoordinates: _boundaryResult?.coordinates,
          existingMultiPolygonCoordinates: _boundaryResult?.multiPolygonCoordinates,
          existingCreationMode: _boundaryResult?.creationMode,
          existingSourceBoundaryIds: _boundaryResult?.sourceBoundaryIds,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _boundaryResult = result;
        _selectedSimpleBoundaryId = null;
      });
      _onSettingChanged();
    }
  }

  Future<void> _save() => _performSave();

  Future<void> _performSave({bool silent = false}) async {
    if (_isSaving) return;

    // Silent mode (auto-save): skip validation, check required fields
    if (silent) {
      if (widget.navigation == null) return;
      if (_nameController.text.isEmpty || _selectedArea == null ||
          _boundaryResult == null || _selectedUnit == null ||
          _selectedTree == null) return;
    } else {
      if (!_formKey.currentState!.validate()) return;
    }

    // Validate score ranges
    if (!silent && _autoVerification && _verificationType == 'score_by_distance') {
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
      final learningSettings = (widget.navigation?.learningSettings ?? const LearningSettings())
          .copyWith(requireCommanderQuiz: _requireCommanderQuiz, requireSoloQuiz: _requireSoloQuiz, quizType: _quizType, quizOpenManually: false);

      const reviewSettings = ReviewSettings();

      final verificationSettings = VerificationSettings(
        autoVerification: _autoVerification,
        verificationType: _autoVerification ? _verificationType : null,
        approvalDistance: _verificationType == 'approved_failed' ? _approvalDistance : null,
        scoreRanges: _verificationType == 'score_by_distance' ? _scoreRanges : null,
        punchMode: _punchMode,
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
        alertSoundVolumes: _alertSoundVolumes.isEmpty ? null : _alertSoundVolumes,
      );

      // חישוב מיקום פתיחת מפה - במרכז הגבול הראשון אם קיים
      double? openingLat;
      double? openingLng;
      if (_boundaryResult != null && _boundaryResult!.coordinates.isNotEmpty) {
        final center = GeometryUtils.getPolygonCenter(_boundaryResult!.coordinates);
        openingLat = center.lat;
        openingLng = center.lng;
      }

      final displaySettings = DisplaySettings(
        defaultMap: _defaultMapType,
        openingLat: openingLat,
        openingLng: openingLng,
        enableVariablesSheet: _enableVariablesSheet,
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
      if (_boundaryResult == null) {
        throw Exception('נא להגדיר גבול ניווט');
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
        layerGgId: _boundaryResult != null && _boundaryResult!.sourceBoundaryIds.isNotEmpty ? _boundaryResult!.sourceBoundaryIds.first : '',
        layerBaId: null,
        distributionMethod: _distributionMethod,
        navigationType: _navigationType,
        executionOrder: null,
        routeLengthKm: domain.RouteLengthRange(min: _distanceMin, max: _distanceMax),
        checkpointsPerNavigator: null,
        startPoint: null,
        endPoint: null,
        waypointSettings: const WaypointSettings(), // ברירת מחדל: ללא נקודות ביניים
        boundaryLayerIds: _boundaryResult?.sourceBoundaryIds ?? [],
        safetyTime: null,
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
        routes: (_hasBoundaryChanged ? const {} : widget.navigation?.routes) ?? const {}, // איפוס צירים בשינוי גבול
        routesStage: _hasBoundaryChanged ? null : widget.navigation?.routesStage,
        routesDistributed: _hasBoundaryChanged ? false : (widget.navigation?.routesDistributed ?? false),
        trainingStartTime: widget.navigation?.trainingStartTime,
        systemCheckStartTime: widget.navigation?.systemCheckStartTime,
        activeStartTime: widget.navigation?.activeStartTime,
        gpsUpdateIntervalSeconds: _gpsUpdateInterval,
        enabledPositionSources: _buildEnabledPositionSources(),
        allowManualPosition: _allowManualPosition,
        gpsSpoofingDetectionEnabled: _gpsSpoofingDetectionEnabled,
        gpsSpoofingMaxDistanceKm: _gpsSpoofingMaxDistanceKm,
        timeCalculationSettings: TimeCalculationSettings(
          enabled: _timeCalcEnabled,
          isHeavyLoad: _isHeavyLoad,
          isNightNavigation: _isNightNavigation,
          isSummer: _isSummer,
          allowExtensionRequests: _allowExtensionRequests,
          extensionWindowType: _extensionWindowType,
          extensionWindowMinutes: _extensionWindowType == 'timed'
              ? (_extensionWindowHours * 60 + _extensionWindowMinutes)
              : null,
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

        // העתקת שכבות לניווט - רק בעת יצירת ניווט חדש עם גבול
        if (_boundaryResult != null && _selectedArea != null) {
          final copyResult = await _layerCopyService.copyLayersWithCustomBoundary(
            navigationId: navigation.id,
            boundaryCoordinates: _boundaryResult!.coordinates,
            multiPolygonCoordinates: _boundaryResult!.multiPolygonCoordinates,
            geometryType: _boundaryResult!.geometryType,
            sourceBoundaryIds: _boundaryResult!.sourceBoundaryIds,
            creationMode: _boundaryResult!.creationMode,
            areaId: _selectedArea!.id,
            createdBy: currentUser.uid,
            boundaryName: _boundaryResult!.name,
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

        // אם הגבול השתנה — מחיקת שכבות ישנות ויצירה מחדש
        if (_hasBoundaryChanged && _boundaryResult != null && _selectedArea != null) {
          await _layerCopyService.deleteLayersForNavigation(navigation.id);
          final copyResult = await _layerCopyService.copyLayersWithCustomBoundary(
            navigationId: navigation.id,
            boundaryCoordinates: _boundaryResult!.coordinates,
            multiPolygonCoordinates: _boundaryResult!.multiPolygonCoordinates,
            geometryType: _boundaryResult!.geometryType,
            sourceBoundaryIds: _boundaryResult!.sourceBoundaryIds,
            creationMode: _boundaryResult!.creationMode,
            areaId: _selectedArea!.id,
            createdBy: currentUser.uid,
            boundaryName: _boundaryResult!.name,
          );

          if (mounted && !copyResult.hasError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'גבול שונה — הועתקו ${copyResult.totalCopied} שכבות מחדש, '
                  'צירים אופסו',
                ),
                backgroundColor: Colors.blue,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
      }

      if (!silent && mounted) {
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
      if (!silent && mounted) {
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
