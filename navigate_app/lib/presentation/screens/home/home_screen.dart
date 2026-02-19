import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../services/auth_service.dart';
import '../../../services/session_service.dart';
import '../../../domain/entities/hat_type.dart';
import '../dashboard/dashboard_screen.dart';
import '../areas/areas_list_screen.dart';
import '../navigations/create_navigation_screen.dart';
import '../navigations/navigations_list_screen.dart';
import '../settings/settings_screen.dart';

import '../units/units_list_screen.dart';
import '../units/unit_members_screen.dart';
import '../onboarding/pending_approvals_screen.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/repositories/unit_repository.dart';

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
  String _userName = '';
  String _unitName = '';
  String _userRole = '';
  HatInfo? _currentHat;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    // טעינת כובע נוכחי מ-session
    final hat = await _sessionService.getSavedSession();
    _currentHat = hat;

    final user = await _authService.getCurrentUser();
    if (user != null && mounted) {
      setState(() {
        _userName = user.fullName;
        _unitName = hat?.unitName ?? '';
        _userRole = user.role;
      });
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
                leading: const Icon(Icons.navigation),
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
                leading: const Icon(Icons.map),
                title: const Text('אזורים'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const AreasListScreen()),
                  );
                },
              ),
            // אישור מנווטים / ניהול חברים — מפקד/מנהל/מפתח
            if (_currentHat?.type == HatType.admin ||
                _currentHat?.type == HatType.commander ||
                _userRole == 'developer' ||
                _userRole == 'unit_admin')
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
            // יחידות — מפתח בלבד
            if (_userRole == 'developer')
              ListTile(
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
              leading: const Icon(Icons.logout),
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
