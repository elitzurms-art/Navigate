import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:latlong2/latlong.dart';
import '../../../services/auth_service.dart';
import '../../../services/session_service.dart';
import '../../../services/notification_service.dart';
import '../../../domain/entities/hat_type.dart';
import '../dashboard/dashboard_screen.dart';
import '../areas/areas_list_screen.dart';
import '../navigations/create_navigation_screen.dart';
import '../navigations/navigations_list_screen.dart';
import '../settings/settings_screen.dart';

import '../units/units_list_screen.dart';
import '../units/unit_members_screen.dart';
import '../units/checklist_management_screen.dart';
import '../onboarding/pending_approvals_screen.dart';
import '../admin/lost_users_screen.dart';
import '../navigations/solo_quiz_screen.dart';
import '../quiz/quiz_report_screen.dart';
import '../terrain/terrain_analysis_screen.dart';
import '../../../services/terrain/terrain_analysis_service.dart' show terrainIsSupported;
import '../../../data/repositories/user_repository.dart';
import '../../../data/repositories/unit_repository.dart';
import '../../../data/repositories/navigation_repository.dart';
import '../../../data/repositories/boundary_repository.dart';
import '../../../domain/entities/user.dart';
import '../../../domain/entities/unit.dart' as domain;
import '../../../domain/entities/boundary.dart';

/// מסך ראשי עם מפה
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final MapController _mapController = MapController();
  final AuthService _authService = AuthService();
  final SessionService _sessionService = SessionService();
  final NotificationService _notificationService = NotificationService();
  String _userName = '';
  String _unitName = '';
  String _userRole = '';
  HatInfo? _currentHat;
  User? _currentUser;
  bool? _commanderQuizPassed;
  dynamic _commanderQuizNavigation; // ניווט עם מבחן מפקדים מופעל
  StreamSubscription<RemoteMessage>? _joinRequestSubscription;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
    _setupJoinRequestListener();
  }

  @override
  void dispose() {
    _joinRequestSubscription?.cancel();
    super.dispose();
  }

  void _setupJoinRequestListener() {
    // האזנה להתראות joinRequest בזמן אמת
    _joinRequestSubscription =
        _notificationService.joinRequestStream.listen((_) {
      if (!mounted) return;
      _showJoinRequestSnackBar();
    });

    // בדיקת התראה שהמתינה (מ-terminated state)
    final pending = _notificationService.consumePendingJoinRequest();
    if (pending != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showJoinRequestSnackBar();
      });
    }
  }

  void _showJoinRequestSnackBar() {
    // רענון ה-badge של ממתינים ב-drawer
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('בקשת הצטרפות חדשה'),
        backgroundColor: Colors.orange,
        action: SnackBarAction(
          label: 'צפה',
          textColor: Colors.white,
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const PendingApprovalsScreen(),
              ),
            );
          },
        ),
      ),
    );
  }

  /// פתיחת מסך ניתוח שטח — דיאלוג בחירת גבול גזרה
  void _openTerrainAnalysis() async {
    // טעינת גבולות גזרה מ-DB
    List<Boundary> boundaries;
    try {
      boundaries = await BoundaryRepository().getAll();
    } catch (_) {
      boundaries = [];
    }

    if (!mounted) return;

    if (boundaries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('לא נמצאו גבולות גזרה — צור אזור עם גבול גזרה תחילה'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    Boundary? selectedBoundary = boundaries.first;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('בחירת גבול גזרה לניתוח'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('בחר גבול גזרה לביצוע ניתוח שטח:'),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<Boundary>(
                    value: selectedBoundary,
                    decoration: const InputDecoration(
                      labelText: 'גבול גזרה',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.map_outlined),
                    ),
                    isExpanded: true,
                    items: boundaries.map((b) {
                      return DropdownMenuItem(
                        value: b,
                        child: Text(
                          b.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (v) => setDialogState(() => selectedBoundary = v),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('ביטול'),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.terrain),
                  label: const Text('פתח'),
                  onPressed: selectedBoundary != null
                      ? () {
                          Navigator.pop(ctx);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => TerrainAnalysisScreen(
                                boundary: selectedBoundary!,
                              ),
                            ),
                          );
                        }
                      : null,
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _loadUserInfo() async {
    // טעינת כובע נוכחי מ-session
    final hat = await _sessionService.getSavedSession();
    _currentHat = hat;

    final user = await _authService.getCurrentUser();
    if (user != null && mounted) {
      setState(() {
        _currentUser = user;
        _userName = user.fullName;
        _unitName = hat?.unitName ?? '';
        _userRole = user.role;
      });
      _loadCommanderQuizStatus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Navigate'),
        centerTitle: true,
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications),
            onPressed: () {
              // TODO: הודעות
            },
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.white,
                    child: Icon(Icons.person, size: 28, color: Colors.blue),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _userName.isEmpty ? 'משתמש' : _userName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    _currentHat?.typeName ?? '',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                    ),
                  ),
                  if (_unitName.isNotEmpty)
                    Text(
                      _unitName,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 11,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const Divider(),

            // ניווטים — admin, commander
            if (_currentHat?.type == HatType.admin ||
                _currentHat?.type == HatType.commander ||
                _currentHat == null)
              ListTile(
                leading: const Icon(Icons.navigation, color: Colors.lightGreen),
                title: const Text('ניווטים'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const NavigationsListScreen()),
                  );
                },
              ),
            // אזורים — admin, commander
            if (_currentHat?.type == HatType.admin ||
                _currentHat?.type == HatType.commander ||
                _currentHat == null)
              ListTile(
                leading: const Icon(Icons.map, color: Colors.blue),
                title: const Text('שכבות'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const AreasListScreen()),
                  );
                },
              ),
            // אישור מנווטים / ניהול חברים — מפקד/מנהל (לא מפתח — אצלו בתת-תפריט)
            if (_userRole != 'developer' &&
                (_currentHat?.type == HatType.admin ||
                 _currentHat?.type == HatType.commander ||
                 _userRole == 'unit_admin'))
              ListTile(
                leading: Icon(
                  _userRole == 'unit_admin' ? Icons.people : Icons.person_add_alt_1,
                  color: Colors.orange,
                ),
                title: Text(_userRole == 'unit_admin' ? 'ניהול חברי יחידה' : 'אישור מנווטים'),
                trailing: FutureBuilder<int>(
                  future: _getPendingCount(),
                  builder: (context, snapshot) {
                    final count = snapshot.data ?? 0;
                    if (count == 0) return const SizedBox.shrink();
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$count',
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    );
                  },
                ),
                onTap: () async {
                  Navigator.pop(context);
                  // מנהל יחידה — מסך חברי יחידה עם ממתינים + שינוי תפקידים
                  if (_userRole == 'unit_admin') {
                    final user = await _authService.getCurrentUser();
                    if (user?.unitId != null && user!.unitId!.isNotEmpty) {
                      final unit = await UnitRepository().getById(user.unitId!);
                      if (unit != null && mounted) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => UnitMembersScreen(unit: unit),
                          ),
                        );
                      }
                    }
                  } else {
                    // מפקד רגיל — מסך אישורים
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const PendingApprovalsScreen(),
                      ),
                    );
                  }
                },
              ),
            // ניהול משתמשים ויחידות — מפתח (תת-תפריט)
            if (_userRole == 'developer')
              ExpansionTile(
                leading: const Icon(Icons.admin_panel_settings, color: Colors.purple),
                title: const Text('ניהול משתמשים ויחידות'),
                children: [
                  ListTile(
                    contentPadding: const EdgeInsetsDirectional.only(start: 28),
                    leading: const Icon(Icons.person_add_alt_1, color: Colors.orange),
                    title: const Text('אישור מנווטים'),
                    trailing: FutureBuilder<int>(
                      future: _getPendingCount(),
                      builder: (context, snapshot) {
                        final count = snapshot.data ?? 0;
                        if (count == 0) return const SizedBox.shrink();
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$count',
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        );
                      },
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const PendingApprovalsScreen(),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    contentPadding: const EdgeInsetsDirectional.only(start: 28),
                    leading: const Icon(Icons.military_tech, color: Colors.purple),
                    title: const Text('יחידות'),
                    subtitle: const Text('צפה גם ביחידות משנה', style: TextStyle(fontSize: 11)),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const UnitsListScreen()),
                      );
                    },
                  ),
                  ListTile(
                    contentPadding: const EdgeInsetsDirectional.only(start: 28),
                    leading: const Icon(Icons.person_off, color: Colors.red),
                    title: const Text('משתמשים אבודים'),
                    trailing: FutureBuilder<int>(
                      future: _getLostUsersCount(),
                      builder: (context, snapshot) {
                        final count = snapshot.data ?? 0;
                        if (count == 0) return const SizedBox.shrink();
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$count',
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        );
                      },
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const LostUsersScreen()),
                      );
                    },
                  ),
                ],
              ),
            // ניהול צ'קליסטים — מנהלי יחידות ומפתחים
            if (_userRole == 'unit_admin' || _userRole == 'developer' || _userRole == 'admin')
              ListTile(
                leading: const Icon(Icons.checklist, color: Colors.teal),
                title: const Text('ניהול צ\'קליסטים'),
                onTap: () async {
                  Navigator.pop(context);
                  final user = await _authService.getCurrentUser();
                  if (user?.unitId != null && user!.unitId!.isNotEmpty && mounted) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            ChecklistManagementScreen(unitId: user.unitId!),
                      ),
                    );
                  }
                },
              ),
            // מבחנים — מפקדים/מנהלים (תת-תפריט)
            if (_userRole != 'developer' &&
                (_currentHat?.type == HatType.admin ||
                 _currentHat?.type == HatType.commander ||
                 _userRole == 'unit_admin'))
              ExpansionTile(
                leading: const Icon(Icons.quiz, color: Colors.purple),
                title: const Text('מבחנים'),
                children: [
                  if ((_commanderQuizNavigation != null || _commanderQuizPassed == true) &&
                      (_currentHat?.type == HatType.admin ||
                       _currentHat?.type == HatType.commander ||
                       _currentHat == null))
                    ListTile(
                      contentPadding: const EdgeInsetsDirectional.only(start: 28),
                      leading: Icon(
                        Icons.quiz,
                        color: _commanderQuizPassed == true ? Colors.green : Colors.purple,
                      ),
                      title: Text(_commanderQuizPassed == true
                          ? 'מבחן מפקדים — בוצע בהצלחה'
                          : 'מבחן מפקדים'),
                      enabled: _commanderQuizPassed != true,
                      onTap: () async {
                        Navigator.pop(context);
                        final nav = _commanderQuizNavigation;
                        if (nav == null || _currentUser == null) return;
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SoloQuizScreen(
                              navigation: nav,
                              currentUser: _currentUser!,
                              quizType: 'commander',
                            ),
                          ),
                        );
                        _loadUserInfo();
                      },
                    ),
                  ListTile(
                    contentPadding: const EdgeInsetsDirectional.only(start: 28),
                    leading: const Icon(Icons.assessment, color: Colors.blue),
                    title: const Text('דוח מבחנים'),
                    onTap: () async {
                      Navigator.pop(context);
                      final user = _currentUser;
                      if (user?.unitId != null && user!.unitId!.isNotEmpty && mounted) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => QuizReportScreen(unitId: user.unitId!),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            // דוח מבחנים — מפתח (תת-תפריט לפי יחידות)
            if (_userRole == 'developer')
              ExpansionTile(
                leading: const Icon(Icons.assessment, color: Colors.blue),
                title: const Text('דוח מבחנים'),
                children: [
                  FutureBuilder<List<domain.Unit>>(
                    future: UnitRepository().getAll(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final units = snapshot.data ?? [];
                      if (units.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('לא נמצאו יחידות', style: TextStyle(color: Colors.grey)),
                        );
                      }
                      return Column(
                        children: units.map<Widget>((unit) {
                          return ListTile(
                            contentPadding: const EdgeInsetsDirectional.only(start: 28),
                            leading: const Icon(Icons.military_tech, color: Colors.purple),
                            title: Text(unit.name),
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => QuizReportScreen(unitId: unit.id),
                                ),
                              );
                            },
                          );
                        }).toList(),
                      );
                    },
                  ),
                ],
              ),
            // ניתוח שטח — מפתח ומנהל יחידה
            if (terrainIsSupported && (_userRole == 'developer' || _userRole == 'unit_admin' || _userRole == 'admin'))
              ListTile(
                leading: const Icon(Icons.terrain, color: Colors.teal),
                title: const Text('ניתוח שטח'),
                onTap: () {
                  Navigator.pop(context);
                  _openTerrainAnalysis();
                },
              ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('הגדרות'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SettingsScreen()),
                );
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('התנתקות'),
              onTap: () async {
                await _authService.signOut();
                if (mounted) {
                  Navigator.of(context).pushReplacementNamed('/');
                }
              },
            ),
          ],
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.navigation,
                size: 120,
                color: Theme.of(context).primaryColor.withOpacity(0.5),
              ),
              const SizedBox(height: 24),
              const Text(
                'ברוכים הבאים למערכת ניווט',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                'בחר מהתפריט את הפעולה הרצויה',
                style: TextStyle(fontSize: 18, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// בדיקת סטטוס מבחן מפקדים — טעינת ניווט עם מבחן מפקדים + בדיקת תוקף
  Future<void> _loadCommanderQuizStatus() async {
    final user = _currentUser;
    if (user == null) return;

    try {
      _commanderQuizPassed = user.hasCommanderQuizValid;

      // חיפוש ניווט עם מבחן מפקדים מופעל
      final navRepo = NavigationRepository();
      final navigations = await navRepo.getAll();
      dynamic foundNav;
      for (final nav in navigations) {
        if (nav.learningSettings.isCommanderQuizCurrentlyOpen &&
            nav.status != 'review') {
          foundNav = nav;
          break;
        }
      }

      if (mounted) {
        setState(() {
          _commanderQuizNavigation = foundNav;
        });
      }
    } catch (_) {
      // שקט
    }
  }

  Future<int> _getPendingCount() async {
    try {
      // מפתח רואה את כל הממתינים בכל היחידות
      if (_userRole == 'developer') {
        final pending = await UserRepository().getAllPendingApprovalUsers();
        return pending.length;
      }
      final unitId = _currentHat?.unitId;
      if (unitId == null || unitId.isEmpty) return 0;
      final unitRepo = UnitRepository();
      final descendantIds = await unitRepo.getDescendantIds(unitId);
      final allUnitIds = [unitId, ...descendantIds];
      final pending = await UserRepository().getPendingApprovalUsers(allUnitIds);
      return pending.length;
    } catch (_) {
      return 0;
    }
  }

  Future<int> _getLostUsersCount() async {
    try {
      final lost = await UserRepository().getLostUsers();
      return lost.length;
    } catch (_) {
      return 0;
    }
  }

  void _showNavigationSubmenu() {
    showModalBottomSheet(
      context: context,
      builder: (context) => ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            leading: const Icon(Icons.add_circle),
            title: const Text('ניווט חדש'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CreateNavigationScreen(),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.list),
            title: const Text('כל הניווטים'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const NavigationsListScreen(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showQuickActions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            leading: const Icon(Icons.navigation),
            title: const Text('ניווט חדש'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CreateNavigationScreen(),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.map),
            title: const Text('אזור חדש'),
            onTap: () {
              Navigator.pop(context);
              // TODO: יצירת אזור
            },
          ),
          ListTile(
            leading: const Icon(Icons.place),
            title: const Text('נקודת ציון חדשה'),
            onTap: () {
              Navigator.pop(context);
              // TODO: יצירת נקודה
            },
          ),
        ],
      ),
    );
  }
}
