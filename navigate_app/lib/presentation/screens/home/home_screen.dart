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

import '../auth/hat_selection_screen.dart';
import '../units/units_list_screen.dart';
import '../navigation_trees/unit_admin_frameworks_screen.dart';

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
                _currentHat?.type == HatType.management ||
                _currentHat?.type == HatType.observer ||
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
            // ניהול מסגרות — admin
            if (_currentHat?.type == HatType.admin)
              ListTile(
                leading: const Icon(Icons.account_tree_outlined, color: Colors.teal),
                title: const Text('ניהול מסגרות'),
                subtitle: const Text('יצירה וניהול מסגרות משנה', style: TextStyle(fontSize: 11)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const UnitAdminFrameworksScreen()),
                  );
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
            // כניסה בתור
            ListTile(
              leading: const Icon(Icons.swap_horiz, color: Colors.purple),
              title: const Text('כניסה בתור'),
              subtitle: Text(
                _currentHat?.description ?? '',
                style: const TextStyle(fontSize: 11),
              ),
              onTap: () => _switchHat(),
            ),
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

  Future<void> _switchHat() async {
    Navigator.pop(context); // סגירת drawer
    final user = await _authService.getCurrentUser();
    if (user == null) return;

    final unitHats = await _sessionService.scanUserHats(user.uid);
    final totalHats = unitHats.fold<int>(0, (sum, u) => sum + u.hats.length);

    if (!mounted) return;

    if (totalHats <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('אין כובעים נוספים')),
      );
      return;
    }

    await _sessionService.clearSession();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => HatSelectionScreen(
          unitHats: unitHats,
          isSwitch: true,
        ),
      ),
      (route) => false,
    );
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
