import 'dart:async';
import 'package:flutter/material.dart';
import '../../../services/auth_service.dart';
import '../../../services/session_service.dart';
import '../../../domain/entities/user.dart';
import '../../../domain/entities/navigation.dart' as domain;
import '../../../data/repositories/navigation_repository.dart';
import 'navigator_state.dart';
import 'navigator_views/learning_view.dart';
import 'navigator_views/system_check_view.dart';
import 'navigator_views/active_view.dart';
import 'navigator_views/approval_view.dart';
import 'navigator_views/review_view.dart';
import 'navigator_views/navigator_map_screen.dart';

/// מסך בית למנווט — container screen עם drawer ותוכן inline
class NavigatorHomeScreen extends StatefulWidget {
  const NavigatorHomeScreen({super.key});

  @override
  State<NavigatorHomeScreen> createState() => _NavigatorHomeScreenState();
}

class _NavigatorHomeScreenState extends State<NavigatorHomeScreen> {
  final AuthService _authService = AuthService();
  final SessionService _sessionService = SessionService();
  final NavigationRepository _navigationRepo = NavigationRepository();

  NavigatorScreenState _state = NavigatorScreenState.loading;
  domain.Navigation? _currentNavigation;
  User? _currentUser;
  String? _error;

  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadState();
    // סקר כל 30 שניות לשינויי סטטוס
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _loadState(silent: true);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  /// טעינת מצב — silent=true לא מציג loading spinner
  Future<void> _loadState({bool silent = false}) async {
    try {
      if (!silent && mounted) {
        setState(() {
          _state = NavigatorScreenState.loading;
          _error = null;
        });
      }

      // קבלת המשתמש הנוכחי
      final user = await _authService.getCurrentUser();
      if (user == null || !mounted) return;
      _currentUser = user;

      // בדיקת session — האם משויך למסגרת
      final session = await _sessionService.getSavedSession();
      if (session == null || session.unitId.isEmpty) {
        if (mounted) {
          setState(() {
            _state = NavigatorScreenState.notAssigned;
            _currentNavigation = null;
          });
        }
        return;
      }

      // טעינת כל הניווטים ומציאת הניווט הרלוונטי
      final navigations = await _navigationRepo.getAll();
      if (!mounted) return;

      domain.Navigation? bestNav;
      int bestPriority = -1;

      for (final nav in navigations) {
        if (!nav.routes.containsKey(user.uid)) continue;

        final priority = navigationStatusPriority(nav.status);
        if (priority <= 0) continue;

        if (priority > bestPriority ||
            (priority == bestPriority &&
                bestNav != null &&
                nav.updatedAt.isAfter(bestNav.updatedAt))) {
          bestNav = nav;
          bestPriority = priority;
        }
      }

      if (!mounted) return;

      if (bestNav == null) {
        setState(() {
          _state = NavigatorScreenState.noActiveNavigation;
          _currentNavigation = null;
        });
        return;
      }

      setState(() {
        _currentNavigation = bestNav;
        _state = statusToScreenState(bestNav!.status);
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = NavigatorScreenState.error;
          _error = e.toString();
        });
      }
    }
  }

  /// התנתקות
  Future<void> _logout() async {
    await _sessionService.clearSession();
    await _authService.signOut();
    if (mounted) {
      Navigator.of(context).pushReplacementNamed('/');
    }
  }

  /// פתיחת מסך מפה מהתפריט
  void _openMapScreen({bool showSelfLocation = false, bool showRoute = false}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => NavigatorMapScreen(
          navigation: _currentNavigation!,
          showSelfLocation: showSelfLocation,
          showRoute: showRoute,
        ),
      ),
    );
  }

  /// עדכון navigation מקומי אחרי שמירה (דפוס _currentNavigation)
  void _onNavigationUpdated(domain.Navigation updated) {
    if (mounted) {
      setState(() {
        _currentNavigation = updated;
        _state = statusToScreenState(updated.status);
      });
    }
  }

  // ==========================================================================
  // Drawer
  // ==========================================================================

  Widget _buildDrawer() {
    final nav = _currentNavigation;
    final isActive = _state == NavigatorScreenState.active;

    return Drawer(
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
                const Icon(Icons.navigation, size: 40, color: Colors.white),
                const SizedBox(height: 8),
                Text(
                  _currentUser?.fullName ?? '',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (nav != null)
                  Text(
                    nav.name,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
              ],
            ),
          ),

          // התנתקות — תמיד
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('התנתקות'),
            onTap: () {
              Navigator.pop(context);
              _logout();
            },
          ),

          if (_state != NavigatorScreenState.notAssigned) ...[
            const Divider(),

            // ציונים — בפיתוח
            ListTile(
              leading: const Icon(Icons.assessment, color: Colors.grey),
              title: const Text('ציונים'),
              subtitle: const Text('בפיתוח'),
              enabled: false,
            ),

            // היסטוריית ניווטים — בפיתוח
            ListTile(
              leading: const Icon(Icons.history, color: Colors.grey),
              title: const Text('היסטוריית ניווטים'),
              subtitle: const Text('בפיתוח'),
              enabled: false,
            ),

            // מפה פתוחה — רק במצב active + allowOpenMap
            if (isActive && nav != null && nav.allowOpenMap) ...[
              const Divider(),
              ListTile(
                leading: const Icon(Icons.map, color: Colors.blue),
                title: const Text('מפה פתוחה'),
                onTap: () {
                  Navigator.pop(context);
                  _openMapScreen();
                },
              ),

              // ניווט עם מיקום — רק אם showSelfLocation
              if (nav.showSelfLocation)
                ListTile(
                  leading: const Icon(Icons.my_location, color: Colors.green),
                  title: const Text('ניווט עם מיקום'),
                  onTap: () {
                    Navigator.pop(context);
                    _openMapScreen(showSelfLocation: true);
                  },
                ),

              // ציר ניווט — רק אם showRouteOnMap
              if (nav.showRouteOnMap)
                ListTile(
                  leading: const Icon(Icons.route, color: Colors.orange),
                  title: const Text('ציר ניווט'),
                  onTap: () {
                    Navigator.pop(context);
                    _openMapScreen(
                      showSelfLocation: nav.showSelfLocation,
                      showRoute: true,
                    );
                  },
                ),
            ],
          ],
        ],
      ),
    );
  }

  // ==========================================================================
  // Body — switch on state
  // ==========================================================================

  Widget _buildBody() {
    switch (_state) {
      case NavigatorScreenState.loading:
        return _buildLoadingView();
      case NavigatorScreenState.error:
        return _buildErrorView();
      case NavigatorScreenState.notAssigned:
        return _buildNotAssignedView();
      case NavigatorScreenState.noActiveNavigation:
        return _buildNoActiveNavigationView();
      case NavigatorScreenState.preparation:
        return _buildPreparationView();
      case NavigatorScreenState.waiting:
        return _buildWaitingView();
      case NavigatorScreenState.learning:
        return LearningView(
          navigation: _currentNavigation!,
          currentUser: _currentUser!,
          onNavigationUpdated: _onNavigationUpdated,
        );
      case NavigatorScreenState.systemCheck:
        return SystemCheckView(
          navigation: _currentNavigation!,
          currentUser: _currentUser!,
        );
      case NavigatorScreenState.active:
        return ActiveView(
          navigation: _currentNavigation!,
          currentUser: _currentUser!,
          onNavigationUpdated: _onNavigationUpdated,
        );
      case NavigatorScreenState.approval:
        return ApprovalView(
          navigation: _currentNavigation!,
          currentUser: _currentUser!,
        );
      case NavigatorScreenState.review:
        return ReviewView(
          navigation: _currentNavigation!,
          currentUser: _currentUser!,
        );
    }
  }

  // ==========================================================================
  // Simple inline views
  // ==========================================================================

  Widget _buildLoadingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Text(
            'בודק ניווטים פעילים...',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.grey[600],
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text(
            'שגיאה בטעינת נתונים',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              _error ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loadState,
            icon: const Icon(Icons.refresh),
            label: const Text('נסה שוב'),
          ),
        ],
      ),
    );
  }

  Widget _buildNotAssignedView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.person_off,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 24),
          Text(
            'אינך משוייך למסגרת',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          Text(
            'פנה למפקד שלך לשיוך למסגרת ניווט',
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildNoActiveNavigationView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.explore_off,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 24),
          Text(
            'אין ניווטים פעילים',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          Text(
            'כשתשובץ לניווט, המסך יתעדכן אוטומטית',
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          OutlinedButton.icon(
            onPressed: _loadState,
            icon: const Icon(Icons.refresh),
            label: const Text('רענון'),
          ),
        ],
      ),
    );
  }

  Widget _buildPreparationView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.construction,
            size: 80,
            color: Colors.orange[400],
          ),
          const SizedBox(height: 24),
          Text(
            'ניווט בהכנה',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          Text(
            _currentNavigation?.name ?? '',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.grey[600],
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'הניווט בשלבי הכנה. המתן להודעה מהמפקד',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildWaitingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.hourglass_top,
            size: 80,
            color: Colors.blue[400],
          ),
          const SizedBox(height: 24),
          Text(
            'ממתין לתחילת ניווט',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          Text(
            _currentNavigation?.name ?? '',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.grey[600],
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'בדיקת המערכות הושלמה. ממתין להפעלת הניווט',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          const CircularProgressIndicator(),
        ],
      ),
    );
  }

  // ==========================================================================
  // Build
  // ==========================================================================

  String _appBarTitle() {
    switch (_state) {
      case NavigatorScreenState.loading:
        return 'Navigate';
      case NavigatorScreenState.notAssigned:
      case NavigatorScreenState.noActiveNavigation:
        return 'Navigate';
      case NavigatorScreenState.preparation:
        return 'הכנה';
      case NavigatorScreenState.learning:
        return 'למידה';
      case NavigatorScreenState.systemCheck:
        return 'בדיקת מערכות';
      case NavigatorScreenState.waiting:
        return 'המתנה';
      case NavigatorScreenState.active:
        return 'ניווט פעיל';
      case NavigatorScreenState.approval:
        return 'אישרור';
      case NavigatorScreenState.review:
        return 'תחקיר';
      case NavigatorScreenState.error:
        return 'Navigate';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_appBarTitle()),
        centerTitle: true,
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          if (_state != NavigatorScreenState.loading)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadState,
            ),
        ],
      ),
      drawer: _buildDrawer(),
      body: _buildBody(),
    );
  }
}
