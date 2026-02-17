import 'dart:async';
import 'package:flutter/material.dart';
import '../../../services/auth_service.dart';
import '../../../services/session_service.dart';
import '../../../services/scoring_service.dart';
import '../../../domain/entities/user.dart';
import '../../../domain/entities/navigation.dart' as domain;
import '../../../domain/entities/navigation_score.dart';
import '../../../domain/entities/coordinate.dart';
import '../../../domain/entities/checkpoint_punch.dart';
import '../../../data/repositories/navigation_repository.dart';
import '../../../data/repositories/navigation_track_repository.dart';
import '../../../data/repositories/navigator_alert_repository.dart';
import 'navigator_state.dart';
import 'navigator_views/learning_view.dart';
import 'navigator_views/system_check_view.dart';
import 'navigator_views/active_view.dart';
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

  final ScoringService _scoringService = ScoringService();

  NavigatorScreenState _state = NavigatorScreenState.loading;
  domain.Navigation? _currentNavigation;
  User? _currentUser;
  String? _error;
  NavigationScore? _navigatorScore;

  // דריסות מפה פר-מנווט (מהמפקד)
  bool _perNavigatorAllowOpenMap = false;
  bool _perNavigatorShowSelfLocation = false;
  bool _perNavigatorShowRouteOnMap = false;

  Timer? _pollTimer;
  Timer? _scorePollTimer;
  StreamSubscription<domain.Navigation?>? _navigationListener;

  @override
  void initState() {
    super.initState();
    _loadState();
    // סקר כל 60 שניות כ-fallback (Firestore listener הוא העיקרי)
    _pollTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _loadState(silent: true);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _scorePollTimer?.cancel();
    _navigationListener?.cancel();
    super.dispose();
  }

  /// התחלת האזנה בזמן אמת למסמך ניווט ב-Firestore
  void _startNavigationListener(String navigationId) {
    // ביטול listener קודם אם קיים
    _navigationListener?.cancel();
    _navigationListener = _navigationRepo.watchNavigation(navigationId).listen(
      (nav) {
        if (!mounted) return;
        if (nav == null) {
          // הניווט נמחק — טעינה מחדש
          _loadState(silent: true);
          return;
        }
        // עדכון local DB בלי sync חזרה
        _navigationRepo.updateLocalFromFirestore(nav);
        // עדכון UI אם הסטטוס או הנתונים השתנו
        if (_currentNavigation == null ||
            _currentNavigation!.status != nav.status ||
            _currentNavigation!.updatedAt != nav.updatedAt) {
          setState(() {
            _currentNavigation = nav;
            _state = statusToScreenState(nav.status);
          });
          _loadNavigatorScore();
        }
      },
      onError: (e) {
        print('DEBUG: Navigation listener error: $e');
      },
    );
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
        _navigationListener?.cancel();
        _navigationListener = null;
        setState(() {
          _state = NavigatorScreenState.noActiveNavigation;
          _currentNavigation = null;
        });
        return;
      }

      // התחלת listener בזמן אמת אם הניווט השתנה
      if (_currentNavigation?.id != bestNav.id) {
        _startNavigationListener(bestNav.id);
      }

      setState(() {
        _currentNavigation = bestNav;
        _state = statusToScreenState(bestNav!.status);
      });

      // טעינת ציון אם בשלב תחקור/אישור
      _loadNavigatorScore();
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = NavigatorScreenState.error;
          _error = e.toString();
        });
      }
    }
  }

  /// טעינת ציון מנווט מ-Firestore (אם בשלב תחקור/אישור)
  Future<void> _loadNavigatorScore() async {
    final nav = _currentNavigation;
    final user = _currentUser;
    if (nav == null || user == null) return;

    final status = nav.status;
    if (status != 'approval' && status != 'review') {
      _scorePollTimer?.cancel();
      _scorePollTimer = null;
      if (_navigatorScore != null) {
        setState(() => _navigatorScore = null);
      }
      return;
    }

    try {
      final scores = await _navigationRepo.fetchScoresFromFirestore(nav.id);
      final myScores =
          scores.where((s) => s['navigatorId'] == user.uid).toList();
      if (!mounted) return;
      if (myScores.isNotEmpty) {
        final score = NavigationScore.fromMap(myScores.first);
        setState(() => _navigatorScore = score);
        // ציון הגיע — ביטול טיימר סקירה מהירה
        _scorePollTimer?.cancel();
        _scorePollTimer = null;
      } else {
        setState(() => _navigatorScore = null);
        // ציון עדיין לא הגיע — התחלת סקירה מהירה כל 15 שניות
        _startScorePollIfNeeded();
      }
    } catch (_) {
      // שקט — לא חוסם
      _startScorePollIfNeeded();
    }
  }

  /// התחלת טיימר סקירת ציון מהירה (כל 15 שניות) אם בשלב תחקור וציון לא הגיע
  void _startScorePollIfNeeded() {
    if (_scorePollTimer != null) return; // כבר רץ
    final status = _currentNavigation?.status;
    if (status != 'approval' && status != 'review') return;
    if (_navigatorScore != null) return;

    _scorePollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _loadNavigatorScore();
    });
  }

  /// התנתקות
  Future<void> _logout() async {
    // בדיקה אם יש ניווט פעיל — אזהרה + סיום מיידי
    final isActiveNav = _state == NavigatorScreenState.active ||
        _state == NavigatorScreenState.waiting;

    if (isActiveNav && _currentNavigation != null && _currentUser != null) {
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          final controller = TextEditingController();
          final isValid = ValueNotifier<bool>(false);
          controller.addListener(() {
            isValid.value = controller.text.trim() == 'התנתקות';
          });
          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.red[700], size: 28),
                const SizedBox(width: 8),
                const Text('אזהרה'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'התנתקות בזמן ניווט תגרור את סיום הניווט ודיווח למפקדים.',
                ),
                const SizedBox(height: 16),
                const Text(
                  'כדי להתנתק, הקלד "התנתקות":',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  textDirection: TextDirection.rtl,
                  decoration: const InputDecoration(
                    hintText: 'התנתקות',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('ביטול'),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: isValid,
                builder: (_, enabled, __) => ElevatedButton(
                  onPressed: enabled ? () => Navigator.pop(ctx, true) : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    disabledBackgroundColor: Colors.grey[300],
                  ),
                  child: Text(
                    'התנתק',
                    style: TextStyle(color: enabled ? Colors.white : Colors.grey[500]),
                  ),
                ),
              ),
            ],
          );
        },
      );

      if (confirmed != true) return;

      // סיום מיידי של הניווט + דיווח למפקדים
      await _forceEndNavigationAndAlert();
    }

    await _sessionService.clearSession();
    await _authService.signOut();
    if (mounted) {
      Navigator.of(context).pushReplacementNamed('/');
    }
  }

  /// סיום מיידי של ניווט פעיל + שליחת התראה למפקדים
  Future<void> _forceEndNavigationAndAlert() async {
    final nav = _currentNavigation;
    final user = _currentUser;
    if (nav == null || user == null) return;

    final trackRepo = NavigationTrackRepository();
    final alertRepo = NavigatorAlertRepository();

    try {
      // מציאת ה-track הפעיל
      final track = await trackRepo.getByNavigatorAndNavigation(
        user.uid,
        nav.id,
      );

      if (track != null && track.isActive) {
        // סיום הניווט
        await trackRepo.endNavigation(track.id);

        // פסילת הניווט — כמו פריצת אבטחה
        await trackRepo.disqualifyNavigator(track.id);

        // סנכרון ל-Firestore
        final updatedTrack = await trackRepo.getById(track.id);
        await trackRepo.syncTrackToFirestore(updatedTrack);
      }

      // שליחת התראת אבטחה למפקד
      final alert = NavigatorAlert(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        navigationId: nav.id,
        navigatorId: user.uid,
        type: AlertType.securityBreach,
        location: const Coordinate(lat: 0, lng: 0, utm: ''),
        timestamp: DateTime.now(),
        navigatorName: user.fullName,
      );
      await alertRepo.create(alert);
    } catch (e) {
      print('DEBUG NavigatorHome: force end error: $e');
    }
  }

  /// פתיחת מסך מפה מהתפריט
  void _openMapScreen({bool showSelfLocation = false, bool showRoute = false}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => NavigatorMapScreen(
          navigation: _currentNavigation!,
          currentUser: _currentUser!,
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

            // ציונים — לא מוצג במצב ניווט פעיל
            if (!isActive)
              _buildScoresDrawerItem(),

            // היסטוריית ניווטים — לא מוצג במצב ניווט פעיל
            if (!isActive) ListTile(
              leading: const Icon(Icons.history, color: Colors.grey),
              title: const Text('היסטוריית ניווטים'),
              subtitle: const Text('בפיתוח'),
              enabled: false,
            ),

            // מפה פתוחה — רק במצב active + (allowOpenMap ברמת ניווט או דריסה פר-מנווט)
            if (isActive && nav != null && (nav.allowOpenMap || _perNavigatorAllowOpenMap)) ...[
              const Divider(),
              ListTile(
                leading: const Icon(Icons.map, color: Colors.blue),
                title: const Text('מפה פתוחה'),
                onTap: () {
                  Navigator.pop(context);
                  _openMapScreen();
                },
              ),

              // ניווט עם מיקום — רק אם showSelfLocation (ברמת ניווט או דריסה)
              if (nav.showSelfLocation || _perNavigatorShowSelfLocation)
                ListTile(
                  leading: const Icon(Icons.my_location, color: Colors.green),
                  title: const Text('ניווט עם מיקום'),
                  onTap: () {
                    Navigator.pop(context);
                    _openMapScreen(showSelfLocation: true);
                  },
                ),

              // ציר ניווט — רק אם showSelfLocation + showRouteOnMap (ברמת ניווט או דריסה)
              if ((nav.showSelfLocation || _perNavigatorShowSelfLocation) &&
                  (nav.showRouteOnMap || _perNavigatorShowRouteOnMap))
                ListTile(
                  leading: const Icon(Icons.route, color: Colors.orange),
                  title: const Text('ציר ניווט'),
                  onTap: () {
                    Navigator.pop(context);
                    _openMapScreen(
                      showSelfLocation: nav.showSelfLocation || _perNavigatorShowSelfLocation,
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
  // Scores Drawer Item
  // ==========================================================================

  Widget _buildScoresDrawerItem() {
    final nav = _currentNavigation;
    final inReviewPhase = nav != null &&
        (nav.status == 'approval' || nav.status == 'review');

    // לא בשלב תחקור — אפור
    if (!inReviewPhase) {
      return const ListTile(
        leading: Icon(Icons.assessment, color: Colors.grey),
        title: Text('ציונים'),
        enabled: false,
      );
    }

    // בשלב תחקור אבל אין ציון / ציון לא פורסם
    if (_navigatorScore == null || !_navigatorScore!.isPublished) {
      return ListTile(
        leading: const Icon(Icons.assessment, color: Colors.orange),
        title: const Text('ציונים'),
        subtitle: const Text('ממתין לאישור מפקד'),
        enabled: false,
      );
    }

    // ציון פורסם
    final score = _navigatorScore!;
    final color = ScoringService.getScoreColor(score.totalScore);
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Center(
          child: Text(
            '${score.totalScore}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
      title: const Text('ציונים'),
      subtitle: Text(
        _scoringService.getGrade(score.totalScore),
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
      onTap: () {
        Navigator.pop(context);
        _showScoreBottomSheet();
      },
    );
  }

  void _showScoreBottomSheet() {
    final score = _navigatorScore;
    if (score == null) return;

    final color = ScoringService.getScoreColor(score.totalScore);
    final grade = _scoringService.getGrade(score.totalScore);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.85,
          expand: false,
          builder: (_, scrollController) {
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(20),
              children: [
                // ידית גרירה
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // כותרת + עיגול ציון
                Row(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('${score.totalScore}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold)),
                          Text(grade,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('הציון שלך',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(
                            score.totalScore >= 80
                                ? 'כל הכבוד! ביצוע מעולה'
                                : score.totalScore >= 60
                                    ? 'ביצוע טוב'
                                    : 'נדרש שיפור',
                            style: TextStyle(color: color, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // הערות מפקד
                if (score.notes != null && score.notes!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.comment, size: 18, color: Colors.grey[600]),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(score.notes!,
                              style: const TextStyle(fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                ],

                // פירוט לפי נקודה
                if (score.checkpointScores.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Text('פירוט לפי נקודה:',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 8),
                  ...score.checkpointScores.entries.map((entry) {
                    final cpScore = entry.value;
                    final cpColor =
                        ScoringService.getScoreColor(cpScore.score);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Icon(
                            cpScore.approved
                                ? Icons.check_circle
                                : Icons.cancel,
                            color: cpScore.approved
                                ? Colors.green
                                : Colors.red,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(cpScore.checkpointId,
                                style: const TextStyle(fontSize: 13)),
                          ),
                          Text(
                              '${cpScore.distanceMeters.toStringAsFixed(0)}מ\'',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.grey)),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: cpColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text('${cpScore.score}',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: cpColor,
                                    fontSize: 13)),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            );
          },
        );
      },
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
          key: ValueKey('active_${_currentNavigation!.id}'),
          navigation: _currentNavigation!,
          currentUser: _currentUser!,
          onNavigationUpdated: _onNavigationUpdated,
          onMapPermissionsChanged: (allowOpenMap, showSelfLocation, showRouteOnMap) {
            if (mounted) {
              setState(() {
                _perNavigatorAllowOpenMap = allowOpenMap;
                _perNavigatorShowSelfLocation = showSelfLocation;
                _perNavigatorShowRouteOnMap = showRouteOnMap;
              });
            }
          },
        );
      case NavigatorScreenState.review:
        return ReviewView(
          navigation: _currentNavigation!,
          currentUser: _currentUser!,
          initialScore: _navigatorScore,
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
      case NavigatorScreenState.review:
        return 'תחקור';
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
