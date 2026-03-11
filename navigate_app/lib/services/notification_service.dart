import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../data/repositories/user_repository.dart';

/// Top-level background handler — required by firebase_messaging
/// Shows local notification for status change messages when app is in background/terminated
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  final type = message.data['type'];
  if (type != 'statusChange') return;

  final plugin = FlutterLocalNotificationsPlugin();
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidSettings);
  await plugin.initialize(initSettings);

  const androidDetails = AndroidNotificationDetails(
    'status_change_channel',
    'מעבר סטטוס ניווט',
    channelDescription: 'התראות על שינוי סטטוס ניווט',
    importance: Importance.high,
    priority: Priority.high,
    playSound: true,
    enableVibration: true,
  );

  await plugin.show(
    9002,
    message.data['title'] ?? '',
    message.data['body'] ?? '',
    const NotificationDetails(android: androidDetails),
  );
}

/// שירות התראות push — singleton
/// מנהל FCM token, הרשאות, והאזנה להודעות
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final UserRepository _userRepo = UserRepository();

  String? _userId;
  bool _initialized = false;

  static const _commanderRoles = ['commander', 'unit_admin', 'admin', 'developer'];

  // Emergency broadcast stream
  final StreamController<RemoteMessage> _emergencyBroadcastController =
      StreamController<RemoteMessage>.broadcast();
  RemoteMessage? _pendingEmergency;

  Stream<RemoteMessage> get emergencyBroadcastStream =>
      _emergencyBroadcastController.stream;

  RemoteMessage? consumePendingEmergency() {
    final pending = _pendingEmergency;
    _pendingEmergency = null;
    return pending;
  }

  // Join request stream (for commanders)
  final StreamController<RemoteMessage> _joinRequestController =
      StreamController<RemoteMessage>.broadcast();
  RemoteMessage? _pendingJoinRequest;

  Stream<RemoteMessage> get joinRequestStream =>
      _joinRequestController.stream;

  RemoteMessage? consumePendingJoinRequest() {
    final pending = _pendingJoinRequest;
    _pendingJoinRequest = null;
    return pending;
  }

  void dispose() {
    _emergencyBroadcastController.close();
    _joinRequestController.close();
  }

  /// אתחול — skip בפלטפורמות שולחניות
  Future<void> initialize({String? userId}) async {
    if (_initialized) return;
    if (!_isMobilePlatform()) {
      print('DEBUG NotificationService: skipping — not a mobile platform');
      return;
    }

    _userId = userId;
    _initialized = true;

    await _requestPermission();
    await _getAndSaveToken();

    // Background message handler (must be top-level function)
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // האזנה לרענון token
    _messaging.onTokenRefresh.listen(_onTokenRefresh);

    // הודעות בזמן foreground
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // הודעה שנלחצה (אפליקציה ברקע/סגורה)
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageTap);

    // בדיקת הודעה שפתחה את האפליקציה ממצב terminated
    await _initializeTerminatedMessage();

    print('DEBUG NotificationService: initialized for user=$_userId');
  }

  bool _isMobilePlatform() {
    try {
      return Platform.isAndroid || Platform.isIOS;
    } catch (_) {
      return false;
    }
  }

  Future<void> _requestPermission() async {
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        criticalAlert: true,
      );
      print('DEBUG NotificationService: permission=${settings.authorizationStatus}');
    } catch (e) {
      print('DEBUG NotificationService: requestPermission error: $e');
    }
  }

  Future<void> _getAndSaveToken() async {
    try {
      final token = await _messaging.getToken();
      if (token != null && _userId != null) {
        await _userRepo.updateFcmToken(_userId!, token);
        print('DEBUG NotificationService: saved token (${token.substring(0, 20)}...)');
      }
    } catch (e) {
      print('DEBUG NotificationService: getToken error: $e');
    }
  }

  void _onTokenRefresh(String token) async {
    if (_userId == null) return;
    try {
      await _userRepo.updateFcmToken(_userId!, token);

      // עדכון commander_tokens אם קיים
      await _refreshCommanderToken(_userId!, token);

      print('DEBUG NotificationService: token refreshed');
    } catch (e) {
      print('DEBUG NotificationService: token refresh save error: $e');
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    print('DEBUG NotificationService: foreground message: ${message.notification?.title}');
    final type = message.data['type'];
    if (type == 'emergencyBroadcast' || type == 'emergencyCancelled') {
      _emergencyBroadcastController.add(message);
    } else if (type == 'joinRequest') {
      _joinRequestController.add(message);
    }
  }

  void _handleMessageTap(RemoteMessage message) {
    final navigationId = message.data['navigationId'];
    print('DEBUG NotificationService: message tapped, navigationId=$navigationId');
    final type = message.data['type'];
    if (type == 'emergencyBroadcast' || type == 'emergencyCancelled') {
      _pendingEmergency = message;
    } else if (type == 'joinRequest') {
      _pendingJoinRequest = message;
    }
  }

  Future<void> _initializeTerminatedMessage() async {
    try {
      final initial = await _messaging.getInitialMessage();
      if (initial == null) return;
      final type = initial.data['type'];
      if (type == 'emergencyBroadcast' || type == 'emergencyCancelled') {
        _pendingEmergency = initial;
      } else if (type == 'joinRequest') {
        _pendingJoinRequest = initial;
      }
    } catch (e) {
      print('DEBUG NotificationService: getInitialMessage error: $e');
    }
  }

  /// כתיבת/עדכון commander_tokens אם המשתמש בעל תפקיד מפקד+
  Future<void> _updateCommanderToken() async {
    if (_userId == null) return;
    try {
      final user = await _userRepo.getUser(_userId!);
      if (user == null) return;

      if (_commanderRoles.contains(user.role)) {
        final token = await _messaging.getToken();
        if (token == null) return;
        await _firestore.collection('commander_tokens').doc(_userId!).set({
          'token': token,
          'role': user.role,
          'unitId': user.unitId,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        print('DEBUG NotificationService: commander token written for $_userId');
      } else {
        // משתמש שאינו מפקד — מחיקה למקרה שהיה בעבר
        await _deleteCommanderToken(_userId!);
      }
    } catch (e) {
      print('DEBUG NotificationService: _updateCommanderToken error: $e');
    }
  }

  /// מחיקת commander_tokens doc
  Future<void> _deleteCommanderToken(String userId) async {
    try {
      await _firestore.collection('commander_tokens').doc(userId).delete();
      print('DEBUG NotificationService: commander token deleted for $userId');
    } catch (e) {
      print('DEBUG NotificationService: _deleteCommanderToken error: $e');
    }
  }

  /// עדכון token ב-commander_tokens אם המסמך קיים
  Future<void> _refreshCommanderToken(String userId, String token) async {
    try {
      final doc = await _firestore.collection('commander_tokens').doc(userId).get();
      if (doc.exists) {
        await _firestore.collection('commander_tokens').doc(userId).update({
          'token': token,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        print('DEBUG NotificationService: commander token refreshed for $userId');
      }
    } catch (e) {
      print('DEBUG NotificationService: _refreshCommanderToken error: $e');
    }
  }

  /// הגדרת userId אחרי login
  Future<void> setUserId(String userId) async {
    _userId = userId;
    if (!_isMobilePlatform()) return;

    if (!_initialized) {
      await initialize(userId: userId);
    } else {
      await _getAndSaveToken();
    }

    // כתיבת commander_tokens אם המשתמש בעל תפקיד מפקד+
    await _updateCommanderToken();
  }

  /// ניקוי token ב-logout
  Future<void> clearToken() async {
    if (!_isMobilePlatform()) return;
    try {
      // מחיקת commander_tokens לפני ניקוי _userId
      if (_userId != null) {
        await _deleteCommanderToken(_userId!);
      }

      await _messaging.deleteToken();
      if (_userId != null) {
        await _userRepo.updateFcmToken(_userId!, null);
      }
      _userId = null;
      print('DEBUG NotificationService: token cleared');
    } catch (e) {
      print('DEBUG NotificationService: clearToken error: $e');
    }
  }
}
