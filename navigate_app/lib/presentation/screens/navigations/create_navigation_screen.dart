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
import '../../../domain/entities/unit.dart' as domain_unit;
import '../../../services/auth_service.dart';
import '../../../services/navigation_layer_copy_service.dart';
import '../../../core/utils/geometry_utils.dart';
import 'routes_verification_screen.dart';
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

  // הגדרות למידה
  bool _enableLearningWithPhones = true;
  bool _showAllCheckpoints = false;
  bool _showNavigationDetails = true;
  bool _showRoutes = true;
  bool _allowRouteEditing = true;
  bool _allowRouteNarration = true;
  bool _autoLearningTimes = false;

  // הגדרות תחקיר
  bool _showScoresAfterApproval = true;
  DateTime _learningDate = DateTime.now();
  TimeOfDay _learningStartTime = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _learningEndTime = const TimeOfDay(hour: 17, minute: 0);

  // הגדרות ניווט
  int _gpsUpdateInterval = 30; // שניות
  bool _autoVerification = false;
  String _verificationType = 'approved_failed'; // approved_failed, score_by_distance
  int _approvalDistance = 20;
  List<DistanceScoreRange> _scoreRanges = [
    const DistanceScoreRange(maxDistance: 10, scorePercentage: 100),
    const DistanceScoreRange(maxDistance: 20, scorePercentage: 80),
    const DistanceScoreRange(maxDistance: 30, scorePercentage: 60),
  ];
  bool _allowOpenMap = false;
  bool _showSelfLocation = false;
  bool _showRouteOnMap = false;

  // התראות
  bool _alertsEnabled = false;
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

  @override
  void initState() {
    super.initState();
    _initializeScreen();
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

    // הגדרות למידה
    _enableLearningWithPhones = nav.learningSettings.enabledWithPhones;
    _showAllCheckpoints = nav.learningSettings.showAllCheckpoints;
    _showNavigationDetails = nav.learningSettings.showNavigationDetails;
    _showRoutes = nav.learningSettings.showRoutes;
    _allowRouteEditing = nav.learningSettings.allowRouteEditing;
    _allowRouteNarration = nav.learningSettings.allowRouteNarration;
    _autoLearningTimes = nav.learningSettings.autoLearningTimes;

    // הגדרות תחקיר
    _showScoresAfterApproval = nav.reviewSettings.showScoresAfterApproval;
    if (nav.learningSettings.learningDate != null) {
      _learningDate = nav.learningSettings.learningDate!;
    }
    if (nav.learningSettings.learningStartTime != null) {
      final parts = nav.learningSettings.learningStartTime!.split(':');
      _learningStartTime = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    }
    if (nav.learningSettings.learningEndTime != null) {
      final parts = nav.learningSettings.learningEndTime!.split(':');
      _learningEndTime = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    }

    // הגדרות GPS
    _gpsUpdateInterval = nav.gpsUpdateIntervalSeconds;

    // הגדרות אימות
    _autoVerification = nav.verificationSettings.autoVerification;
    _verificationType = nav.verificationSettings.verificationType ?? 'approved_failed';
    _approvalDistance = nav.verificationSettings.approvalDistance ?? 50;
    _scoreRanges = nav.verificationSettings.scoreRanges ?? [];

    // הגדרות מפה
    _allowOpenMap = nav.allowOpenMap;
    _showSelfLocation = nav.showSelfLocation;
    _showRouteOnMap = nav.showRouteOnMap;

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

                    // הגדרות נקודות
                    _buildSectionTitle('הגדרות נקודות'),
                    _buildCheckpointSettings(),
                    const SizedBox(height: 24),

                    // הגדרות למידה
                    _buildSectionTitle('הגדרות למידה'),
                    _buildLearningSettings(),
                    const SizedBox(height: 24),
                  ],

                  // הגדרות ניווט (כולל התראות)
                  _buildSectionTitle(widget.alertsOnlyMode ? 'התראות' : 'הגדרות ניווט'),
                  _buildNavigationSettings(),

                  if (!widget.alertsOnlyMode) ...[
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

  Widget _buildCheckpointSettings() {
    // אם הצירים כבר חולקו ואושרו - הצג אופציה לעריכה
    final routesDistributed = widget.navigation?.routesDistributed ?? false;
    final routesReady = widget.navigation?.routesStage == 'ready' ||
                        widget.navigation?.routesStage == 'verification';

    if (routesDistributed && routesReady) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'הגדרת נקודות',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'הושלם',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'הצירים חולקו ואושרו (${widget.navigation!.routes.length} צירים)',
                style: TextStyle(color: Colors.grey[600]),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => RoutesVerificationScreen(
                          navigation: widget.navigation!,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.edit),
                  label: const Text('עריכת נקודות'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.blue,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // אחרת - הצג את האופציות הרגילות
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('חלוקת נקודות', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            RadioListTile<String>(
              title: const Text('אוטומטי'),
              value: 'automatic',
              groupValue: _distributionMethod,
              onChanged: (value) {
                setState(() => _distributionMethod = value!);
              },
            ),
            RadioListTile<String>(
              title: const Text('העלאת קובץ ידני'),
              value: 'manual_full',
              groupValue: _distributionMethod,
              onChanged: (value) {
                setState(() => _distributionMethod = value!);
              },
            ),
            RadioListTile<String>(
              title: Row(
                children: [
                  const Text('ידני באפליקציה'),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'בפיתוח',
                      style: TextStyle(fontSize: 10, color: Colors.orange),
                    ),
                  ),
                ],
              ),
              value: 'manual_app',
              groupValue: _distributionMethod,
              onChanged: null, // disabled
            ),

          ],
        ),
      ),
    );
  }

  Widget _buildLearningSettings() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                value: _showRoutes,
                onChanged: (value) {
                  setState(() => _showRoutes = value);
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
                const Padding(
                  padding: EdgeInsets.only(right: 32, top: 8),
                  child: Text('טווחי מרחק וציון:', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                ...List.generate(_scoreRanges.length, (index) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 32, top: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            initialValue: _scoreRanges[index].maxDistance.toString(),
                            decoration: InputDecoration(
                              labelText: 'טווח ${index + 1} - מרחק מקס (מ\')',
                              border: const OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (value) {
                              final distance = int.tryParse(value) ?? _scoreRanges[index].maxDistance;
                              setState(() {
                                _scoreRanges[index] = DistanceScoreRange(
                                  maxDistance: distance,
                                  scorePercentage: _scoreRanges[index].scorePercentage,
                                );
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            initialValue: _scoreRanges[index].scorePercentage.toString(),
                            decoration: InputDecoration(
                              labelText: 'ציון (%)',
                              border: const OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (value) {
                              final percentage = int.tryParse(value) ?? _scoreRanges[index].scorePercentage;
                              setState(() {
                                _scoreRanges[index] = DistanceScoreRange(
                                  maxDistance: _scoreRanges[index].maxDistance,
                                  scorePercentage: percentage,
                                );
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                }),
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
              CheckboxListTile(
                title: const Text('אפשר הצגת מיקום עצמי למנווט'),
                value: _showSelfLocation,
                onChanged: (value) {
                  setState(() => _showSelfLocation = value ?? false);
                },
              ),
              if (_showSelfLocation)
                CheckboxListTile(
                  title: const Text('הצג ציר ניווט על המפה'),
                  value: _showRouteOnMap,
                  onChanged: (value) {
                    setState(() => _showRouteOnMap = value ?? false);
                  },
                ),
            ],

            if (!widget.alertsOnlyMode) ...[
              const Divider(),

              // הגדרות GPS
              ListTile(
                leading: const Icon(Icons.timer, color: Colors.blue),
                title: const Text('מרווח דגימת GPS'),
                subtitle: Text('$_gpsUpdateInterval שניות'),
                trailing: SizedBox(
                  width: 120,
                  child: Slider(
                    value: _gpsUpdateInterval.toDouble(),
                    min: 5,
                    max: 120,
                    divisions: 23,
                    label: '$_gpsUpdateInterval שניות',
                    onChanged: (value) {
                      setState(() => _gpsUpdateInterval = value.round());
                    },
                  ),
                ),
              ),

              const Divider(),
            ],

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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('מפת ברירת מחדל', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('(בפיתוח)', style: TextStyle(color: Colors.grey)),

            const SizedBox(height: 16),
            const Text('מיקום פתיחת מפה: מחושב אוטומטית ממרכז הג"ג',
              style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic)),

            const SizedBox(height: 16),
            const Text('בחירת שכבות', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('(בפיתוח)', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      // יצירת ההגדרות
      final safetyTime = SafetyTimeSettings(
        type: _safetyTimeType,
        hours: _safetyTimeType == 'hours' ? _safetyHours : null,
        hoursAfterMission: _safetyTimeType == 'after_last_mission' ? _hoursAfterMission : null,
      );

      final learningSettings = LearningSettings(
        enabledWithPhones: _enableLearningWithPhones,
        showAllCheckpoints: _showAllCheckpoints,
        showNavigationDetails: _showNavigationDetails,
        showRoutes: _showRoutes,
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
        reviewSettings: reviewSettings,
        displaySettings: displaySettings,
        routes: widget.navigation?.routes ?? const {}, // שמירת הצירים הקיימים
        routesStage: widget.navigation?.routesStage, // שמירת שלב הצירים
        routesDistributed: widget.navigation?.routesDistributed ?? false, // שמירת סטטוס חלוקה
        trainingStartTime: widget.navigation?.trainingStartTime,
        systemCheckStartTime: widget.navigation?.systemCheckStartTime,
        activeStartTime: widget.navigation?.activeStartTime,
        gpsUpdateIntervalSeconds: _gpsUpdateInterval,
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
