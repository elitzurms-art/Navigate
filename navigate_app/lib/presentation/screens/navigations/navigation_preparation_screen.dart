import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/constants/app_constants.dart';
import '../../../domain/entities/navigation.dart' as domain;
import '../../../domain/entities/unit_checklist.dart';
import '../../../domain/entities/user.dart';
import '../../../data/repositories/navigation_repository.dart';
import '../../../data/repositories/navigation_track_repository.dart';
import '../../../data/repositories/unit_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../services/auth_service.dart';
import 'create_navigation_screen.dart';
import 'routes_setup_screen.dart';
import 'routes_verification_screen.dart';
import 'training_mode_screen.dart';
import 'system_check_screen.dart';
import 'data_export_screen.dart';
import 'variables_sheet_screen.dart';

/// מסך הכנת ניווט - צ'קליסט שלבים
class NavigationPreparationScreen extends StatefulWidget {
  final domain.Navigation navigation;

  const NavigationPreparationScreen({
    super.key,
    required this.navigation,
  });

  @override
  State<NavigationPreparationScreen> createState() =>
      _NavigationPreparationScreenState();
}

class _NavigationPreparationScreenState
    extends State<NavigationPreparationScreen> {
  final NavigationRepository _repository = NavigationRepository();
  final UserRepository _userRepository = UserRepository();
  final AuthService _authService = AuthService();

  late domain.Navigation _navigation;
  bool _isLoading = false;
  User? _currentUser;
  List<UnitChecklist> _unitChecklists = [];

  @override
  void initState() {
    super.initState();
    _navigation = widget.navigation;
    _loadCurrentUser();
    _loadUnitChecklists();
  }

  Future<void> _loadCurrentUser() async {
    try {
      final user = await _authService.getCurrentUser();
      if (mounted) {
        setState(() {
          _currentUser = user;
        });
      }
    } catch (e) {
      print('DEBUG: Error loading current user: $e');
    }
  }

  Future<void> _loadUnitChecklists() async {
    try {
      final unitId = _navigation.selectedUnitId;
      if (unitId == null) return;
      final unit = await UnitRepository().getById(unitId);
      if (unit != null && mounted) {
        setState(() => _unitChecklists = unit.checklists);
      }
    } catch (e) {
      print('DEBUG: Error loading unit checklists: $e');
    }
  }

  /// טעינה מחדש של הניווט מהמאגר
  Future<void> _reloadNavigation() async {
    setState(() => _isLoading = true);
    try {
      final updated = await _repository.getById(_navigation.id);
      if (updated != null && mounted) {
        setState(() {
          _navigation = updated;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
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

  // ======== מניעת הפעלה מקבילית ========

  /// בודקת אם יש מצב פעיל ומבקשת אישור לסגירתו
  Future<bool> _confirmStopActiveMode(String targetLabel) async {
    final status = _navigation.status;
    if (status == 'preparation') return true;

    String activeLabel;
    if (status == 'learning') {
      activeLabel = 'מצב למידה';
    } else if (status == 'system_check') {
      activeLabel = 'בדיקת מערכות';
    } else {
      return true;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber, color: Colors.orange, size: 28),
            const SizedBox(width: 8),
            Expanded(child: Text('סיום $activeLabel')),
          ],
        ),
        content: Text(
          'בחירה זו תגרום לסגירת $activeLabel, האם אתה בטוח שברצונך לסיים את $activeLabel?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            child: const Text('סיים והמשך'),
          ),
        ],
      ),
    );

    if (confirmed != true) return false;

    await _stopActiveMode();
    return true;
  }

  /// סוגרת את המצב הפעיל (learning / system_check) ומחזירה ל-preparation
  Future<void> _stopActiveMode() async {
    final status = _navigation.status;

    if (status == 'learning') {
      final updated = _navigation.copyWith(
        status: 'preparation',
        trainingStartTime: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await _repository.update(updated);
    } else if (status == 'system_check') {
      // ניקוי system_status docs מ-Firestore
      try {
        final statusCollection = FirebaseFirestore.instance
            .collection(AppConstants.navigationsCollection)
            .doc(_navigation.id)
            .collection('system_status');
        final snapshot = await statusCollection.get();
        for (final doc in snapshot.docs) {
          await doc.reference.delete();
        }
      } catch (e) {
        print('DEBUG: failed to clean up system_status: $e');
      }

      final updated = _navigation.copyWith(
        status: 'preparation',
        systemCheckStartTime: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await _repository.update(updated);
    }

    await _reloadNavigation();
  }

  // ======== בדיקות השלמה ========

  bool get _isSettingsDone => true; // תמיד מושלם אם הניווט קיים

  bool get _isDistributionDone => _navigation.routesDistributed == true;

  bool get _isVerificationDone {
    if (_navigation.routesStage == 'ready') return true;
    if (_navigation.routes.isNotEmpty &&
        _navigation.routes.values.every((r) => r.isVerified)) {
      return true;
    }
    return false;
  }

  bool get _isLearningDone => _navigation.trainingStartTime != null;

  bool get _isSystemCheckDone => _navigation.systemCheckStartTime != null;

  // ======== פתיחת מסכי שלבים ========

  Future<void> _openSettings() async {
    if (!await _confirmStopActiveMode('הגדרות')) return;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            CreateNavigationScreen(navigation: _navigation),
      ),
    );
    if (result == true) {
      await _reloadNavigation();
    }
  }

  Future<void> _openDistribution() async {
    if (!await _confirmStopActiveMode('חלוקת נקודות')) return;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RoutesSetupScreen(navigation: _navigation),
      ),
    );
    if (result == true) {
      await _reloadNavigation();
    }
  }

  void _openDataExport() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DataExportScreen(navigation: _navigation),
      ),
    );
  }

  void _openUpdatedDataExport() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DataExportScreen(
          navigation: _navigation,
          afterLearning: true,
        ),
      ),
    );
  }

  Future<void> _openVerification() async {
    if (!await _confirmStopActiveMode('עריכת צירים')) return;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            RoutesVerificationScreen(navigation: _navigation),
      ),
    );
    if (result == true) {
      await _reloadNavigation();
    }
  }

  Future<void> _openLearning() async {
    // רק אם המצב האחר פעיל — אם כבר ב-learning, נכנסים ישר
    if (_navigation.status == 'system_check') {
      if (!await _confirmStopActiveMode('למידה')) return;
    }
    // בדיקת התנגשויות מנווטים
    if (!await _checkNavigatorConflicts()) return;
    final isCommander = _currentUser?.hasCommanderPermissions ?? true;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TrainingModeScreen(
          navigation: _navigation,
          isCommander: isCommander,
        ),
      ),
    );
    if (result == 'deleted') {
      if (mounted) Navigator.pop(context, 'deleted');
      return;
    }
    await _reloadNavigation();
  }

  Future<void> _openSystemCheck() async {
    // רק אם המצב האחר פעיל — אם כבר ב-system_check, נכנסים ישר
    if (_navigation.status == 'learning') {
      if (!await _confirmStopActiveMode('בדיקת מערכות')) return;
    }
    // בדיקת התנגשויות מנווטים
    if (!await _checkNavigatorConflicts()) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SystemCheckScreen(
          navigation: _navigation,
          isCommander: true,
          currentUser: _currentUser,
        ),
      ),
    );
    await _reloadNavigation();
  }

  Future<void> _openVariablesSheet() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VariablesSheetScreen(navigation: _navigation),
      ),
    );
    await _reloadNavigation();
  }

  // ======== בדיקת התנגשויות מנווטים ========

  Future<bool> _checkNavigatorConflicts() async {
    try {
      final navigatorUids = _navigation.routes.keys.toSet();
      if (navigatorUids.isEmpty) return true;

      final allNavigations = await _repository.getAll();
      final activeStatuses = {
        'learning',
        'system_check',
        'active',
        'waiting'
      };
      final otherActiveNavigations = allNavigations
          .where((nav) =>
              nav.id != _navigation.id &&
              activeStatuses.contains(nav.status))
          .toList();

      if (otherActiveNavigations.isEmpty) return true;

      final Map<String, List<String>> conflicts = {};

      for (final uid in navigatorUids) {
        for (final otherNav in otherActiveNavigations) {
          if (otherNav.routes.containsKey(uid)) {
            conflicts.putIfAbsent(uid, () => []);
            conflicts[uid]!.add(otherNav.name);
          }
        }
      }

      if (conflicts.isEmpty) return true;

      final Map<String, String> uidToName = {};
      for (final uid in conflicts.keys) {
        try {
          final user = await _userRepository.getUser(uid);
          if (user != null) {
            uidToName[uid] =
                user.fullName.isNotEmpty ? user.fullName : user.personalNumber;
          } else {
            uidToName[uid] = uid;
          }
        } catch (_) {
          uidToName[uid] = uid;
        }
      }

      if (!mounted) return false;

      final conflictLines = conflicts.entries.map((entry) {
        final name = uidToName[entry.key] ?? entry.key;
        final navNames = entry.value.join(', ');
        return '$name  -  $navNames';
      }).join('\n');

      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.orange, size: 28),
              SizedBox(width: 8),
              Text('התנגשות מנווטים'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'המנווטים הבאים כבר משויכים לניווטים פעילים אחרים:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  conflictLines,
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 12),
                const Text(
                  'סיים את הניווטים הפעילים ולאחר מכן נסה שוב.',
                  style: TextStyle(color: Colors.red),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('הבנתי'),
            ),
          ],
        ),
      );

      return false;
    } catch (e) {
      print('DEBUG: Error checking navigator conflicts: $e');
      return true;
    }
  }

  // ======== העברה למצב אימון ========

  Future<void> _moveToTrainingMode() async {
    if (!await _confirmStopActiveMode('מצב אימון')) return;
    // בדיקת שלבים שלא הושלמו
    final List<String> warnings = [];

    if (!_isDistributionDone) {
      warnings.add(
          'לא בוצעה חלוקת נקודות - לא תוכל לבצע אימות נקודות ואישור צירים ממוחשב');
    }
    if (!_isVerificationDone) {
      warnings.add(
          'לא בוצעה עריכת צירים - הצירים חולקו אוטומטית ללא עריכה ויכולות לחול טעויות');
    }
    if (!_isLearningDone) {
      warnings.add(
          'לא בוצעה למידה - לא בוצע אישור צירים ולמידה ממוחשבת');
    }
    if (!_isSystemCheckDone) {
      warnings.add(
          'לא בוצעה בדיקת מערכות - לא וידאת תקינות של כלל המשתתפים ויכולות להיווצר תקלות');
    }

    // בדיקת צ'קליסטים חובה
    final completion = _navigation.checklistCompletion;
    for (final cl in _unitChecklists) {
      if (cl.isMandatory) {
        final isComplete =
            completion?.isChecklistComplete(cl.id, cl) ?? false;
        final isSigned = completion?.getSignature(cl.id) != null;
        if (!isComplete || !isSigned) {
          // חובה — חוסם
          if (!mounted) return;
          await showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.block, color: Colors.red, size: 28),
                  SizedBox(width: 8),
                  Expanded(child: Text('צ\'קליסט חובה לא הושלם')),
                ],
              ),
              content: Text(
                  'הצ\'קליסט "${cl.title}" הוא חובה ולא הושלם/נחתם. יש להשלים ולחתום לפני המעבר לאימון.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('הבנתי'),
                ),
              ],
            ),
          );
          return;
        }
      } else {
        // אופציונלי — אזהרה (לא חוסם)
        final isComplete =
            completion?.isChecklistComplete(cl.id, cl) ?? false;
        if (!isComplete) {
          warnings.add('הצ\'קליסט "${cl.title}" לא הושלם (אופציונלי)');
        }
      }
    }

    if (warnings.isEmpty) {
      // כל השלבים הושלמו - דיאלוג אישור פשוט
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('העברה למצב אימון'),
          content: const Text(
              'כל שלבי ההכנה הושלמו.\nהאם אתה בטוח שברצונך להעביר את הניווט למצב אימון?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('ביטול'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.green),
              child: const Text('העבר לאימון'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
    } else {
      // יש שלבים שלא הושלמו - הצג אזהרה
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.orange, size: 28),
              SizedBox(width: 8),
              Expanded(
                child: Text('לא ביצעת את כל השלבים'),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...warnings.map((warning) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('• ',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16)),
                          Expanded(
                            child: Text(
                              warning,
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                    )),
                const SizedBox(height: 12),
                const Text(
                  'האם אתה בטוח שברצונך להעביר את הניווט למצב אימון?',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('ביטול'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.orange),
              child: const Text('העבר לאימון'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
    }

    // בדיקת התנגשויות מנווטים
    if (!await _checkNavigatorConflicts()) return;

    // ביצוע ההעברה
    await _performMoveToTraining();
  }

  Future<void> _performMoveToTraining() async {
    _showSpinner('מעביר למצב אימון...');

    try {
      // איפוס tracks ישנים (במקרה שהניווט חזר מ-approval/review)
      await NavigationTrackRepository().resetTracksForNavigation(_navigation.id);

      final updatedNavigation = _navigation.copyWith(
        status: 'waiting',
        updatedAt: DateTime.now(),
      );
      await _repository.update(updatedNavigation);

      if (mounted) {
        Navigator.pop(context); // סגירת spinner
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('הניווט הועבר למצב אימון'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true); // חזרה לרשימה עם reload
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // סגירת spinner
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בהעברה: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showSpinner(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(message),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ======== בניית UI ========

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('הכנת ניווט'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _reloadNavigation,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // כותרת - שם ניווט וסטטוס
                _buildHeader(),
                // רשימת שלבים
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildStepCard(
                        stepNumber: 1,
                        title: 'הגדרות',
                        isDone: _isSettingsDone,
                        isMandatory: true,
                        onTap: _openSettings,
                      ),
                      const SizedBox(height: 10),
                      _buildStepCard(
                        stepNumber: 2,
                        title: 'חלוקת נקודות',
                        isDone: _isDistributionDone,
                        isMandatory: false,
                        onTap: _openDistribution,
                        extraButton: _isVerificationDone
                            ? TextButton.icon(
                                onPressed: _openDataExport,
                                icon: const Icon(Icons.file_download, size: 18),
                                label: const Text('ייצוא נתונים'),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.teal,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  textStyle: const TextStyle(fontSize: 13),
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(height: 10),
                      _buildStepCard(
                        stepNumber: 3,
                        title: 'עריכת צירים',
                        isDone: _isVerificationDone,
                        isMandatory: false,
                        onTap: _openVerification,
                      ),
                      const SizedBox(height: 10),
                      _buildStepCard(
                        stepNumber: 4,
                        title: 'למידה',
                        isDone: _isLearningDone,
                        isMandatory: false,
                        isActive: _navigation.status == 'learning',
                        onTap: _openLearning,
                        extraButton: _isLearningDone
                            ? TextButton.icon(
                                onPressed: _openUpdatedDataExport,
                                icon: const Icon(Icons.file_download, size: 18),
                                label: const Text('ייצוא צירים'),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.teal,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  textStyle: const TextStyle(fontSize: 13),
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(height: 10),
                      _buildStepCard(
                        stepNumber: 5,
                        title: 'בדיקת מערכות',
                        isDone: _isSystemCheckDone,
                        isMandatory: false,
                        isActive: _navigation.status == 'system_check',
                        onTap: _openSystemCheck,
                      ),
                      if (_navigation.displaySettings.enableVariablesSheet) ...[
                        const SizedBox(height: 10),
                        _buildStepCard(
                          stepNumber: 6,
                          title: 'דף משתנים',
                          isDone: _navigation.variablesSheet != null,
                          isMandatory: false,
                          onTap: _openVariablesSheet,
                        ),
                      ],
                      // צ'קליסטים מרמת היחידה
                      for (final cl in _unitChecklists) ...[
                        const SizedBox(height: 10),
                        _buildChecklistCard(cl),
                      ],
                    ],
                  ),
                ),
                // כפתור העברה למצב אימון
                _buildBottomButton(),
              ],
            ),
    );
  }

  Widget _buildHeader() {
    final statusColor = _getStatusColor(_navigation.status);
    final statusText = _getStatusText(_navigation.status);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: Border(
          bottom: BorderSide(color: Colors.grey[300]!),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _navigation.name,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              statusText,
              style: TextStyle(
                color: statusColor,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepCard({
    required int stepNumber,
    required String title,
    required bool isDone,
    required bool isMandatory,
    required VoidCallback onTap,
    bool isActive = false,
    Widget? extraButton,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isDone
              ? Colors.green.withOpacity(0.3)
              : Colors.grey.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              // מספר שלב
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isDone
                      ? Colors.green.withOpacity(0.15)
                      : Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(18),
                ),
                alignment: Alignment.center,
                child: Text(
                  '$stepNumber',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: isDone ? Colors.green : Colors.grey[600],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              // שם שלב + תג חובה
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (isMandatory) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: Colors.red.withOpacity(0.3)),
                            ),
                            child: const Text(
                              'חובה',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                        if (isActive) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'פעיל',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (extraButton != null) extraButton,
                  ],
                ),
              ),
              // אייקון השלמה
              Icon(
                isDone
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                color: isDone ? Colors.green : Colors.grey,
                size: 28,
              ),
              const SizedBox(width: 4),
              // חץ
              Icon(
                Icons.chevron_left,
                color: Colors.grey[400],
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChecklistCard(UnitChecklist cl) {
    final completion = _navigation.checklistCompletion;
    final isDone = completion?.isChecklistComplete(cl.id, cl) ?? false;
    final signature = completion?.getSignature(cl.id);
    final completedCount = completion?.completedCount(cl.id) ?? 0;
    final totalItems = cl.totalItems;
    final pct = totalItems > 0 ? (completedCount / totalItems * 100).round() : 0;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isDone && signature != null
              ? Colors.green.withOpacity(0.3)
              : Colors.grey.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _openChecklistSheet(cl),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              // Icon
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isDone && signature != null
                      ? Colors.green.withOpacity(0.15)
                      : Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(18),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.checklist,
                  size: 20,
                  color: isDone && signature != null
                      ? Colors.green
                      : Colors.grey[600],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(cl.title,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis),
                        ),
                        if (cl.isMandatory) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: Colors.red.withOpacity(0.3)),
                            ),
                            child: const Text('חובה',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          '$completedCount/$totalItems · $pct%',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[600]),
                        ),
                        if (signature != null) ...[
                          const SizedBox(width: 8),
                          Icon(Icons.verified, size: 14, color: Colors.green[600]),
                          const SizedBox(width: 2),
                          Text(
                            'נחתם ע"י ${signature.completedByName}',
                            style: TextStyle(
                                fontSize: 11, color: Colors.green[700]),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Icon(
                isDone && signature != null
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                color: isDone && signature != null
                    ? Colors.green
                    : Colors.grey,
                size: 28,
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_left, color: Colors.grey[400], size: 24),
            ],
          ),
        ),
      ),
    );
  }

  void _openChecklistSheet(UnitChecklist cl) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final completion =
                _navigation.checklistCompletion ?? const ChecklistCompletion();
            final completedCount = completion.completedCount(cl.id);
            final totalItems = cl.totalItems;
            final pct =
                totalItems > 0 ? (completedCount / totalItems * 100).round() : 0;
            final allDone = completion.isChecklistComplete(cl.id, cl);
            final signature = completion.getSignature(cl.id);

            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.75,
              minChildSize: 0.4,
              maxChildSize: 0.95,
              builder: (_, scrollController) {
                return Directionality(
                  textDirection: TextDirection.rtl,
                  child: Column(
                    children: [
                      // Handle
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      // Header
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(cl.title,
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold)),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: allDone
                                    ? Colors.green[50]
                                    : Colors.orange[50],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '$completedCount/$totalItems · $pct%',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: allDone
                                      ? Colors.green[700]
                                      : Colors.orange[700],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (signature != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              Icon(Icons.verified,
                                  size: 16, color: Colors.green[600]),
                              const SizedBox(width: 4),
                              Text(
                                'נחתם ע"י ${signature.completedByName}',
                                style: TextStyle(
                                    fontSize: 13, color: Colors.green[700]),
                              ),
                            ],
                          ),
                        ),
                      const Divider(),
                      // Items list
                      Expanded(
                        child: ListView(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          children: [
                            for (final section in cl.sections) ...[
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                    8, 12, 8, 4),
                                child: Text(
                                  section.title,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15),
                                ),
                              ),
                              const Divider(height: 1),
                              for (final item in section.items)
                                CheckboxListTile(
                                  title: Text(item.title,
                                      style: const TextStyle(fontSize: 14)),
                                  value: completion
                                          .completions[cl.id]?[item.id] ??
                                      false,
                                  dense: true,
                                  onChanged: (val) async {
                                    final updated =
                                        completion.toggleItem(cl.id, item.id);
                                    final updatedNav = _navigation.copyWith(
                                      checklistCompletion: updated,
                                      updatedAt: DateTime.now(),
                                    );
                                    await _repository.update(updatedNav);
                                    setState(() => _navigation = updatedNav);
                                    setSheetState(() {});
                                  },
                                ),
                            ],
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                      // Sign button
                      if (signature == null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: allDone && _currentUser != null
                                  ? () async {
                                      final signed = completion.signChecklist(
                                          cl.id, _currentUser!);
                                      final updatedNav =
                                          _navigation.copyWith(
                                        checklistCompletion: signed,
                                        updatedAt: DateTime.now(),
                                      );
                                      await _repository.update(updatedNav);
                                      setState(
                                          () => _navigation = updatedNav);
                                      setSheetState(() {});
                                    }
                                  : null,
                              icon: const Icon(Icons.verified),
                              label: const Text('אשר צ\'קליסט'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                        ),
                    SizedBox(height: MediaQuery.of(context).padding.bottom),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildBottomButton() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 16 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        onPressed: _moveToTrainingMode,
        icon: const Icon(Icons.play_arrow),
        label: const Text(
          'העבר למצב אימון',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }

  // ======== עזרים ========

  String _getStatusText(String status) {
    switch (status) {
      case 'preparation':
        return 'הכנה';
      case 'ready':
        return 'מוכן';
      case 'learning':
        return 'למידה';
      case 'waiting':
        return 'ממתין';
      case 'system_check':
        return 'בדיקת מערכת';
      case 'active':
        return 'פעיל';
      default:
        return status;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'preparation':
        return Colors.orange;
      case 'ready':
        return Colors.teal;
      case 'learning':
        return Colors.blue;
      case 'waiting':
        return Colors.cyan;
      case 'system_check':
        return Colors.purple;
      case 'active':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }
}
