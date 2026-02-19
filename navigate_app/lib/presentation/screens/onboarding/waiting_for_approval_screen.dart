import 'dart:async';
import 'package:flutter/material.dart';
import '../../../services/auth_service.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/sync/sync_manager.dart';
import 'choose_unit_screen.dart';

/// מסך המתנה לאישור — המנווט ממתין לאישור מפקד
class WaitingForApprovalScreen extends StatefulWidget {
  final String unitName;

  const WaitingForApprovalScreen({
    super.key,
    required this.unitName,
  });

  @override
  State<WaitingForApprovalScreen> createState() => _WaitingForApprovalScreenState();
}

class _WaitingForApprovalScreenState extends State<WaitingForApprovalScreen> {
  final AuthService _authService = AuthService();
  final UserRepository _userRepo = UserRepository();
  final SyncManager _syncManager = SyncManager();

  StreamSubscription<String>? _syncSubscription;
  Timer? _pollTimer;
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    // האזנה לשינויי סנכרון — כשנתוני users מתעדכנים, בדיקה אם אושר
    _syncSubscription = _syncManager.onDataChanged.listen((collection) {
      if (collection == 'users') {
        _checkApprovalStatus();
      }
    });
    // poll כל 30 שניות כ-fallback
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkApprovalStatus();
    });
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkApprovalStatus() async {
    final user = await _authService.getCurrentUser();
    if (user == null || !mounted) return;

    if (user.isApproved) {
      // אושר — מעבר למסך הבית
      Navigator.of(context).pushReplacementNamed('/home');
    } else if (user.unitId == null || user.unitId!.isEmpty) {
      // נדחה (unitId נמחק) — חזרה לבחירת יחידה
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ChooseUnitScreen()),
      );
    }
  }

  Future<void> _cancelRequest() async {
    if (_cancelling) return;
    setState(() => _cancelling = true);

    try {
      final user = await _authService.getCurrentUser();
      if (user == null) return;

      await _userRepo.rejectUser(user.uid);

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ChooseUnitScreen()),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _cancelling = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('שגיאה בביטול הבקשה')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ממתין לאישור'),
        centerTitle: true,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'התנתקות',
            onPressed: () async {
              await _authService.signOut();
              if (mounted) {
                Navigator.of(context).pushReplacementNamed('/');
              }
            },
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.hourglass_empty,
                size: 80,
                color: Colors.orange[300],
              ),
              const SizedBox(height: 24),
              const Text(
                'ממתין לאישור',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'בקשתך להצטרף ליחידה "${widget.unitName}" ממתינה לאישור מפקד',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'המסך יתעדכן אוטומטית כשהבקשה תאושר',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[400],
                ),
              ),
              const SizedBox(height: 32),
              const SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(height: 40),
              OutlinedButton.icon(
                onPressed: _cancelling ? null : _cancelRequest,
                icon: const Icon(Icons.close),
                label: Text(_cancelling ? 'מבטל...' : 'ביטול בקשה'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
