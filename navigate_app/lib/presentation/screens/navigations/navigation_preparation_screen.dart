import 'package:flutter/material.dart';
import '../../../domain/entities/navigation.dart' as domain;
import '../../../domain/entities/user.dart';
import '../../../data/repositories/navigation_repository.dart';
import '../../../data/repositories/navigation_track_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../services/auth_service.dart';
import 'create_navigation_screen.dart';
import 'routes_setup_screen.dart';
import 'routes_verification_screen.dart';
import 'training_mode_screen.dart';
import 'system_check_screen.dart';
import 'data_export_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _navigation = widget.navigation;
    _loadCurrentUser();
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
    if (result == true) {
      await _reloadNavigation();
    }
  }

  Future<void> _openSystemCheck() async {
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

      final confirmed = await showDialog<bool>(
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
                  'האם להמשיך בכל זאת?',
                  style: TextStyle(color: Colors.red),
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
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('המשך בכל זאת'),
            ),
          ],
        ),
      );

      return confirmed == true;
    } catch (e) {
      print('DEBUG: Error checking navigator conflicts: $e');
      return true;
    }
  }

  // ======== העברה למצב אימון ========

  Future<void> _moveToTrainingMode() async {
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
                        onTap: _openSystemCheck,
                      ),
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

  Widget _buildBottomButton() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
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
