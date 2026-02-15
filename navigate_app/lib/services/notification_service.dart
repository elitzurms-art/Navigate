import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../data/repositories/user_repository.dart';

/// שירות התראות push — singleton
/// מנהל FCM token, הרשאות, והאזנה להודעות
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final UserRepository _userRepo = UserRepository();

  String? _userId;
  bool _initialized = false;

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

    // האזנה לרענון token
    _messaging.onTokenRefresh.listen(_onTokenRefresh);

    // הודעות בזמן foreground
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // הודעה שנלחצה (אפליקציה ברקע/סגורה)
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageTap);

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
      print('DEBUG NotificationService: token refreshed');
    } catch (e) {
      print('DEBUG NotificationService: token refresh save error: $e');
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    print('DEBUG NotificationService: foreground message: ${message.notification?.title}');
  }

  void _handleMessageTap(RemoteMessage message) {
    final navigationId = message.data['navigationId'];
    print('DEBUG NotificationService: message tapped, navigationId=$navigationId');
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
  }

  /// ניקוי token ב-logout
  Future<void> clearToken() async {
    if (!_isMobilePlatform()) return;
    try {
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
