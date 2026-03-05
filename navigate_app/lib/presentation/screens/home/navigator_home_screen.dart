import 'dart:async';
import 'dart:io' show Platform;
import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../data/sync/sync_manager.dart';
import '../../../services/auth_service.dart';
import '../../../services/notification_service.dart';
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
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/repositories/unit_repository.dart';
import '../onboarding/choose_unit_screen.dart';
import '../onboarding/waiting_for_approval_screen.dart';
import 'navigator_state.dart';
import '../navigations/solo_quiz_screen.dart';
import 'navigator_views/learning_view.dart';
import 'navigator_views/system_check_view.dart';
import 'navigator_views/active_view.dart';
import 'navigator_views/review_view.dart';
import 'navigator_views/navigator_map_screen.dart';
import 'navigation_history_list_screen.dart';

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
  final SyncManager _syncManager = SyncManager();

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

  /// אתחול דגלי מפה פר-מנווט מערכי הניווט הגלובליים
  void _initPerNavigatorFlags(domain.Navigation nav) {
    _perNavigatorAllowOpenMap = nav.allowOpenMap;
    _perNavigatorShowSelfLocation = nav.showSelfLocation;
    _perNavigatorShowRouteOnMap = nav.showRouteOnMap;
  }

  // מעקב אחרי מצב מסך מפה פתוח
  bool _isMapScreenOpen = false;
  bool _mapScreenShowSelfLocation = false;
  bool _mapScreenOpenedFromEmergency = false;

  bool _reverseRevealShown = false;

  // מבחן ניווט — בדיקת passed מ-Firestore
  bool? _quizPassed;

  // שידור חירום
  AudioPlayer? _emergencyPlayer;
  StreamSubscription<RemoteMessage>? _emergencySubscription;
  StreamSubscription<DocumentSnapshot>? _emergencyFirestoreListener;
  Timer? _vibrationTimer;
  bool _emergencyDialogShowing = false;
  bool _routineDialogShowing = false;
  bool _wasInEmergency = false;
  String? _currentBroadcastId;
  String? _lastShownBroadcastId;

  Timer? _pollTimer;
  StreamSubscription<List<Map<String, dynamic>>>? _scoreSubscription;
  Timer? _debounceTimer;
  StreamSubscription<domain.Navigation?>? _navigationListener;
  StreamSubscription<String>? _syncSubscription;
  StreamSubscription<QuerySnapshot>? _allNavigationsWatcher;

  @override
  void initState() {
    super.initState();
    _loadState();
    _initEmergencyAlarm();
    // האזנה לשינויים מ-SyncManager (כשניווט חדש מגיע מ-Firestore) — עם debounce
    _syncSubscription = _syncManager.onDataChanged.listen((collection) {
      if ((collection == 'navigations' || collection == 'users') && mounted) {
        _debounceTimer?.cancel();
        _debounceTimer = Timer(const Duration(milliseconds: 300), () {
          if (mounted) _loadState(silent: true);
        });
      }
    });
    // סקר כל 60 שניות כ-fallback (Firestore listener הוא העיקרי)
    _pollTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _loadState(silent: true);
    });
  }

  void _initEmergencyAlarm() {
    _emergencyPlayer = AudioPlayer();
    _emergencyPlayer!.setAudioContext(AudioContext(
      android: AudioContextAndroid(
        usageType: AndroidUsageType.alarm,
        contentType: AndroidContentType.sonification,
        audioFocus: AndroidAudioFocus.gainTransient,
      ),
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.playback,
        options: {AVAudioSessionOptions.duckOthers},
      ),
    ));

    // האזנה לשידורי חירום foreground (FCM) — לא נתמך ב-Windows
    if (!Platform.isWindows) {
      _emergencySubscription = NotificationService().emergencyBroadcastStream
          .listen(_handleEmergencyFCM);

      // טיפול בהודעה שנפתחה מרקע/terminated
      final pending = NotificationService().consumePendingEmergency();
      if (pending != null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _handleEmergencyFCM(pending),
        );
      }
    }
  }

  /// Firestore listener — fallback אמין למצב חירום (עובד גם עם מסך כבוי)
  void _startEmergencyFirestoreListener(String navigationId) {
    _emergencyFirestoreListener?.cancel();
    _emergencyFirestoreListener = FirebaseFirestore.instance
        .collection(AppConstants.navigationsCollection)
        .doc(navigationId)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final active = snap.data()?['emergencyActive'] == true;
      final broadcastId = snap.data()?['activeBroadcastId'] as String?;
      final mode = snap.data()?['emergencyMode'] as int? ?? 0;
      final cancelId = snap.data()?['cancelBroadcastId'] as String?;

      if (active && !_emergencyDialogShowing && broadcastId != null && broadcastId != _lastShownBroadcastId) {
        // חירום חדש — fallback: השהייה 2 שניות לתת ל-FCM להגיע ראשון
        _currentBroadcastId = broadcastId;
        Future.delayed(const Duration(seconds: 2), () {
          if (!mounted || _emergencyDialogShowing || _routineDialogShowing) return;
          if (broadcastId == _lastShownBroadcastId) return;
          FirebaseFirestore.instance
              .collection(AppConstants.navigationsCollection)
              .doc(navigationId)
              .collection('emergency_broadcasts')
              .doc(broadcastId)
              .get()
              .then((doc) {
            if (!mounted || _emergencyDialogShowing || _routineDialogShowing) return;
            if (broadcastId == _lastShownBroadcastId) return;
            final data = doc.data() ?? {};
            _showEmergencyDialog(
              message: data['message'] as String? ?? '',
              instructions: data['instructions'] as String? ?? '',
              emergencyMode: mode,
              broadcastId: broadcastId,
            );
          });
        });
      } else if (!active && _wasInEmergency) {
        // חירום בוטל — קריאת cancelBroadcastId ישירות מה-snapshot (ללא query)
        _wasInEmergency = false;
        Future.delayed(const Duration(seconds: 2), () {
          if (!mounted || _routineDialogShowing) return;
          _showReturnToRoutineDialog(cancelBroadcastId: cancelId);
        });
      }
    });
  }

  /// טיפול בהודעת FCM — חירום או ביטול
  void _handleEmergencyFCM(RemoteMessage message) {
    if (!mounted) return;
    final type = message.data['type'] ?? '';
    if (type == 'emergencyCancelled') {
      // ביטול חירום הגיע דרך FCM
      if (_wasInEmergency) {
        _wasInEmergency = false;
        final broadcastId = message.data['broadcastId'] as String?;
        _showReturnToRoutineDialog(cancelBroadcastId: broadcastId);
      }
      return;
    }
    // emergencyBroadcast
    if (_emergencyDialogShowing || _routineDialogShowing) return;
    final broadcastId = message.data['broadcastId'] as String?;
    if (broadcastId != null && broadcastId == _lastShownBroadcastId) return;
    _currentBroadcastId = broadcastId;
    final emergencyMode = int.tryParse(message.data['emergencyMode'] ?? '') ?? 0;
    _showEmergencyDialog(
      message: message.data['message'] ?? '',
      instructions: message.data['instructions'] ?? '',
      emergencyMode: emergencyMode,
      broadcastId: broadcastId,
    );
  }

  /// דיאלוג חירום — מוצג גם מ-FCM וגם מ-Firestore listener
  void _showEmergencyDialog({
    required String message,
    required String instructions,
    required int emergencyMode,
    String? broadcastId,
  }) {
    if (_emergencyDialogShowing || _routineDialogShowing) return;
    _emergencyDialogShowing = true;
    _wasInEmergency = true;
    _lastShownBroadcastId = broadcastId;

    // הפעלת אזעקה
    _emergencyPlayer?.setReleaseMode(ReleaseMode.loop);
    _emergencyPlayer?.play(AssetSource('sounds/alert_beep.wav'));

    // רטט כל 2 שניות
    _vibrationTimer?.cancel();
    _vibrationTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      HapticFeedback.heavyImpact();
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: Colors.red[50],
          icon: const Icon(Icons.campaign, color: Colors.red, size: 48),
          title: const Text(
            'שידור חירום',
            style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(message, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              if (instructions.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    border: Border.all(color: Colors.orange),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline, color: Colors.orange, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(instructions, style: const TextStyle(fontSize: 14)),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.check_circle),
                label: const Text('אישור והבנתי'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () {
                  _emergencyPlayer?.stop();
                  _vibrationTimer?.cancel();
                  _emergencyDialogShowing = false;
                  Navigator.of(ctx).pop();

                  // כתיבת אישור קבלה
                  if (broadcastId != null && _currentNavigation != null && _currentUser != null) {
                    FirebaseFirestore.instance
                        .collection(AppConstants.navigationsCollection)
                        .doc(_currentNavigation!.id)
                        .collection('emergency_broadcasts')
                        .doc(broadcastId)
                        .update({'acknowledgedBy': FieldValue.arrayUnion([_currentUser!.uid])});
                  }

                  // פתיחת מפה לפי מצב
                  if (_currentNavigation != null && _currentUser != null) {
                    if (emergencyMode == 1) {
                      _openMapScreen(showSelfLocation: true);
                    } else if (emergencyMode >= 2) {
                      _openMapScreen(showSelfLocation: true, openedFromEmergency: true);
                    }
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// דיאלוג חזרה לשגרה
  void _showReturnToRoutineDialog({String? cancelBroadcastId}) {
    if (_routineDialogShowing) return;

    // סגירת דיאלוג חירום אם עדיין פתוח
    if (_emergencyDialogShowing) {
      _emergencyPlayer?.stop();
      _vibrationTimer?.cancel();
      _emergencyDialogShowing = false;
      Navigator.of(context).pop();
    }

    _routineDialogShowing = true;

    // הפעלת אזעקה
    _emergencyPlayer?.setReleaseMode(ReleaseMode.loop);
    _emergencyPlayer?.play(AssetSource('sounds/alert_beep.wav'));

    // רטט כל 2 שניות
    _vibrationTimer?.cancel();
    _vibrationTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      HapticFeedback.heavyImpact();
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: Colors.green[50],
          icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
          title: const Text(
            'חזרה לשגרה',
            style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          content: const Text(
            'חזרה לשגרה — המשך בניווט',
            style: TextStyle(fontSize: 16),
            textAlign: TextAlign.center,
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.check_circle),
                label: const Text('אישור'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () {
                  _emergencyPlayer?.stop();
                  _vibrationTimer?.cancel();
                  _routineDialogShowing = false;
                  Navigator.of(ctx).pop();

                  // כתיבת אישור קבלה לביטול
                  if (cancelBroadcastId != null && _currentNavigation != null && _currentUser != null) {
                    FirebaseFirestore.instance
                        .collection(AppConstants.navigationsCollection)
                        .doc(_currentNavigation!.id)
                        .collection('emergency_broadcasts')
                        .doc(cancelBroadcastId)
                        .update({'acknowledgedBy': FieldValue.arrayUnion([_currentUser!.uid])});
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _pollTimer?.cancel();
    _scoreSubscription?.cancel();
    _navigationListener?.cancel();
    _syncSubscription?.cancel();
    _allNavigationsWatcher?.cancel();
    _emergencySubscription?.cancel();
    _emergencyFirestoreListener?.cancel();
    _emergencyPlayer?.dispose();
    _vibrationTimer?.cancel();
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
        _navigationRepo.upsertLocalFromFirestore(nav);
        // עדכון UI אם הסטטוס או הנתונים השתנו
        if (_currentNavigation == null ||
            _currentNavigation!.status != nav.status ||
            _currentNavigation!.updatedAt != nav.updatedAt) {
          final previousStatus = _currentNavigation?.status;
          setState(() {
            _currentNavigation = nav;
            _state = statusToScreenState(nav.status);
          });
          _loadNavigatorScore();

          // ניווט הפוך — הצגת דיאלוג חשיפה במעבר ל-waiting
          if (nav.navigationType == 'reverse' &&
              nav.status == 'waiting' &&
              previousStatus != 'waiting' &&
              previousStatus != 'active' &&
              !_reverseRevealShown) {
            _reverseRevealShown = true;
            _showReverseRevealDialog();
          }
        }
      },
      onError: (e) {
        print('DEBUG: Navigation listener error: $e');
      },
    );
  }

  /// האזנה לכל הניווטים של המשתמש — לזיהוי מעבר ניווט אחר לסטטוס פעיל
  void _startAllNavigationsWatcher() {
    if (_allNavigationsWatcher != null) return; // already running
    final userId = _currentUser?.uid;
    if (userId == null) return;

    _allNavigationsWatcher = FirebaseFirestore.instance
        .collection(AppConstants.navigationsCollection)
        .where('participants', arrayContains: userId)
        .snapshots()
        .listen(
      (snapshot) async {
        if (!mounted) return;

        final currentPriority = _currentNavigation != null
            ? navigationStatusPriority(_currentNavigation!.status)
            : 0;

        for (final change in snapshot.docChanges) {
          if (change.type == DocumentChangeType.removed) continue;
          if (change.doc.id == _currentNavigation?.id) continue;
          final data = change.doc.data();
          if (data == null) continue;
          final status = data['status'] as String? ?? '';
          if (navigationStatusPriority(status) > currentPriority) {
            // Found a higher-priority navigation — upsert locally, then reload
            final navData = Map<String, dynamic>.from(data);
            navData['id'] = change.doc.id;
            try {
              final nav = domain.Navigation.fromMap(navData);
              await _navigationRepo.upsertLocalFromFirestore(nav);
            } catch (_) {}
            if (mounted) _loadState(silent: true);
            return;
          }
        }
      },
      onError: (e) {
        print('DEBUG: All navigations watcher error: $e');
      },
    );
  }

  /// עצירת האזנה לכל הניווטים
  void _stopAllNavigationsWatcher() {
    _allNavigationsWatcher?.cancel();
    _allNavigationsWatcher = null;
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

      // safety net — בדיקת onboarding
      if (!user.bypassesOnboarding) {
        if (user.needsUnitSelection) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const ChooseUnitScreen()),
          );
          return;
        }
        if (user.isAwaitingApproval) {
          String unitName = '';
          try {
            final unit = await UnitRepository().getById(user.unitId!);
            unitName = unit?.name ?? '';
          } catch (_) {}
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => WaitingForApprovalScreen(unitName: unitName),
            ),
          );
          return;
        }
      }

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

      // Diagnostic: log navigation search results
      final myNavs = navigations.where((n) =>
          n.routes.containsKey(user.uid) || n.selectedParticipantIds.contains(user.uid)).toList();
      print('DEBUG _loadState: uid=${user.uid}, total navigations=${navigations.length}, '
          'matching=${myNavs.length}, statuses=${myNavs.map((n) => "${n.id}:${n.status}").toList()}');

      domain.Navigation? bestNav;
      int bestPriority = -1;

      for (final nav in navigations) {
        if (!nav.routes.containsKey(user.uid) &&
            !nav.selectedParticipantIds.contains(user.uid)) continue;

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
        _startAllNavigationsWatcher();
        return;
      }

      // התחלת listener בזמן אמת אם הניווט השתנה
      if (_currentNavigation?.id != bestNav.id) {
        _startNavigationListener(bestNav.id);
        _startEmergencyFirestoreListener(bestNav.id);
      }

      if (!mounted) return;
      final isNewNav = _currentNavigation?.id != bestNav!.id;
      setState(() {
        _currentNavigation = bestNav;
        if (isNewNav) _initPerNavigatorFlags(bestNav);
        _state = statusToScreenState(bestNav.status);
      });

      // Start/stop all-navigations watcher: active only on passive screens
      if (_state == NavigatorScreenState.preparation ||
          _state == NavigatorScreenState.waiting ||
          _state == NavigatorScreenState.noActiveNavigation) {
        _startAllNavigationsWatcher();
      } else {
        _stopAllNavigationsWatcher();
      }

      // ניווט הפוך — חשיפה אם נפתח ישירות ב-waiting (cold start)
      if (bestNav.navigationType == 'reverse' &&
          bestNav.status == 'waiting' &&
          !_reverseRevealShown) {
        _reverseRevealShown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showReverseRevealDialog();
        });
      }

      // בדיקת מבחן ניווט מ-Firestore
      _loadQuizStatus();

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

  /// בדיקת סטטוס מבחן ניווט מ-Firestore
  Future<void> _loadQuizStatus() async {
    final nav = _currentNavigation;
    final user = _currentUser;
    if (nav == null || user == null || !nav.learningSettings.requireSoloQuiz) {
      _quizPassed = null;
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('navigations')
          .doc(nav.id)
          .collection('quiz_answers')
          .doc(user.uid)
          .get();
      if (mounted) {
        setState(() {
          _quizPassed = doc.exists && doc.data()?['passed'] == true;
        });
      }
    } catch (_) {
      // שקט — לא חוסם
    }
  }

  /// טעינת ציון מנווט מ-Firestore (אם בשלב תחקור/אישור)
  /// משתמשת ב-Firestore realtime listener במקום polling
  void _loadNavigatorScore() {
    final nav = _currentNavigation;
    final user = _currentUser;
    if (nav == null || user == null) return;

    final status = nav.status;
    if (status != 'approval' && status != 'review') {
      _scoreSubscription?.cancel();
      _scoreSubscription = null;
      if (_navigatorScore != null) {
        setState(() => _navigatorScore = null);
      }
      return;
    }

    // כבר מאזינים לניווט הזה — לא צריך listener חדש
    if (_scoreSubscription != null) return;

    _scoreSubscription = _navigationRepo
        .watchScoresFromFirestore(nav.id)
        .listen((scores) {
      if (!mounted) return;
      final myScores =
          scores.where((s) => s['navigatorId'] == user.uid).toList();
      if (myScores.isNotEmpty) {
        final score = NavigationScore.fromMap(myScores.first);
        setState(() => _navigatorScore = score);
      } else {
        setState(() => _navigatorScore = null);
      }
    }, onError: (_) {
      // שקט — לא חוסם
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
  ///
  /// מבצע שלושה דברים:
  /// 1. סיום הניווט (סטטוס אישי = סיים)
  /// 2. פסילת הניווט
  /// 3. כתיבה ישירה ל-Firestore (לא דרך queue — כי signOut מיד אחרי)
  Future<void> _forceEndNavigationAndAlert() async {
    final nav = _currentNavigation;
    final user = _currentUser;
    if (nav == null || user == null) return;

    final trackRepo = NavigationTrackRepository();
    final alertRepo = NavigatorAlertRepository();

    try {
      // מציאת track קיים (פעיל או לא)
      var track = await trackRepo.getByNavigatorAndNavigation(
        user.uid,
        nav.id,
      );

      // אם אין track — ייצור אחד (מנווט ב-waiting שטרם התחיל)
      if (track == null) {
        track = await trackRepo.startNavigation(
          navigatorUserId: user.uid,
          navigationId: nav.id,
        );
      }

      // סיום הניווט (אם עדיין פעיל)
      if (track.isActive) {
        await trackRepo.endNavigation(track.id);
      }

      // פסילת הניווט
      if (!track.isDisqualified) {
        await trackRepo.disqualifyNavigator(track.id);
      }

      // כתיבה ישירה ל-Firestore — לא דרך queue, כי signOut קורה מיד
      // ואחריו Firebase Auth כבר לא מאומת
      try {
        final updatedTrack = await trackRepo.getById(track.id);
        await FirebaseFirestore.instance
            .collection(AppConstants.navigationTracksCollection)
            .doc(track.id)
            .set({
          'id': updatedTrack.id,
          'navigationId': updatedTrack.navigationId,
          'navigatorUserId': updatedTrack.navigatorUserId,
          'trackPointsJson': updatedTrack.trackPointsJson,
          'stabbingsJson': updatedTrack.stabbingsJson,
          'startedAt': updatedTrack.startedAt.toIso8601String(),
          'endedAt': updatedTrack.endedAt?.toIso8601String(),
          'isActive': updatedTrack.isActive,
          'isDisqualified': updatedTrack.isDisqualified,
          'manualPositionUsed': updatedTrack.manualPositionUsed,
          'manualPositionUsedAt': updatedTrack.manualPositionUsedAt?.toIso8601String(),
        }, SetOptions(merge: true));
      } catch (_) {
        // Firestore לא זמין — הנתונים נשמרו מקומית לפחות
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
  void _openMapScreen({
    bool showSelfLocation = false,
    bool showRoute = false,
    bool openedFromEmergency = false,
  }) {
    _isMapScreenOpen = true;
    _mapScreenShowSelfLocation = showSelfLocation;
    _mapScreenOpenedFromEmergency = openedFromEmergency;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => NavigatorMapScreen(
          navigation: _currentNavigation!,
          currentUser: _currentUser!,
          showSelfLocation: showSelfLocation,
          showRoute: showRoute,
          openedFromEmergency: openedFromEmergency,
        ),
      ),
    ).then((_) {
      if (mounted) {
        setState(() {
          _isMapScreenOpen = false;
          _mapScreenShowSelfLocation = false;
          _mapScreenOpenedFromEmergency = false;
        });
      }
    });
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

            // מבחן ניווט בדד — כשהמבחן פתוח
            if (!isActive && nav != null && nav.learningSettings.isQuizCurrentlyOpen)
              _buildQuizDrawerItem(),

            // היסטוריית ניווטים — רק כשאין ניווט פעיל או בהכנה
            if (_state == NavigatorScreenState.noActiveNavigation ||
                _state == NavigatorScreenState.preparation)
              ListTile(
                leading: const Icon(Icons.history, color: Colors.blue),
                title: const Text('היסטוריית ניווטים'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => NavigationHistoryListScreen(
                        currentUser: _currentUser!,
                      ),
                    ),
                  );
                },
              ),

            // מפה פתוחה — רק במצב active + (allowOpenMap ברמת ניווט או דריסה פר-מנווט)
            if (isActive && nav != null && _perNavigatorAllowOpenMap) ...[
              const Divider(),
              // אפשרות 1: מפה פתוחה (שכבות + ציר, ללא מיקום עצמי)
              ListTile(
                leading: const Icon(Icons.map, color: Colors.blue),
                title: const Text('מפה פתוחה'),
                onTap: () {
                  Navigator.pop(context);
                  _openMapScreen(showRoute: true);
                },
              ),

              // אפשרות 2: מפה + מיקום עצמי (רק אם showSelfLocation ברמת ניווט או דריסה)
              if (_perNavigatorShowSelfLocation)
                ListTile(
                  leading: const Icon(Icons.my_location, color: Colors.green),
                  title: const Text('מפה + מיקום עצמי'),
                  onTap: () {
                    Navigator.pop(context);
                    _openMapScreen(showSelfLocation: true, showRoute: true);
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

  Widget _buildQuizDrawerItem() {
    final user = _currentUser;
    final nav = _currentNavigation;
    if (user == null || nav == null) return const SizedBox.shrink();

    final quizType = nav.learningSettings.quizType;
    final quizLabel = quizType == 'regular' ? 'מבחן ניווט' : 'מבחן ניווט בדד';

    if (_quizPassed == true) {
      return ListTile(
        leading: const Icon(Icons.quiz, color: Colors.green),
        title: Text('$quizLabel — בוצע בהצלחה'),
        enabled: false,
      );
    }

    return ListTile(
      leading: const Icon(Icons.quiz, color: Colors.purple),
      title: Text(quizLabel),
      onTap: () {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SoloQuizScreen(
              navigation: nav,
              currentUser: user,
              quizType: quizType,
            ),
          ),
        ).then((_) {
          _loadState(silent: true);
        });
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
            // סגירת מסך מפה פתוח אם הרשאות בוטלו
            if (_isMapScreenOpen && !_mapScreenOpenedFromEmergency) {
              if (!allowOpenMap) {
                if (mounted && Navigator.of(context).canPop()) {
                  Navigator.of(context).maybePop();
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('הרשאת מפה בוטלה')),
                );
              } else if (_mapScreenShowSelfLocation && !showSelfLocation) {
                if (mounted && Navigator.of(context).canPop()) {
                  Navigator.of(context).maybePop();
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('הרשאת מיקום בוטלה')),
                );
              }
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
    final isReverse = _currentNavigation?.navigationType == 'reverse';
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
          if (isReverse) ...[
            const SizedBox(height: 16),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 32),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange[300]!),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.swap_vert, color: Colors.orange[700], size: 20),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'ניווט הפוך — הציר האמיתי הפוך מהלמידה',
                      style: TextStyle(
                        color: Colors.orange[800],
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
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

  /// דיאלוג חשיפת ניווט הפוך — מוצג במעבר ל-waiting
  void _showReverseRevealDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.swap_vert, color: Colors.orange[700], size: 28),
            const SizedBox(width: 8),
            const Text('ניווט הפוך'),
          ],
        ),
        content: const Text(
          'הציר שהוצג לך בשלב הלמידה היה בסדר הפוך.\n\n'
          'הסדר האמיתי של הנקודות הוא הפוך ממה שלמדת — '
          'כלומר, הנקודה האחרונה שראית היא הראשונה, והראשונה היא האחרונה.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('הבנתי'),
          ),
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
