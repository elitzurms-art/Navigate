import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' hide User;
import '../../../services/auth_service.dart';
import '../../../data/repositories/user_repository.dart';
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

  StreamSubscription<DocumentSnapshot>? _firestoreListener;
  Timer? _retryTimer;
  Timer? _fallbackTimer;
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    // Firestore snapshot listener — יורה רק כשמסמך המשתמש משתנה (לא polling)
    _startFirestoreListener();
  }

  /// התחלת listener ישיר למסמך המשתמש ב-Firestore — יורה רק בשינוי
  /// אם נכשל (permission-denied לפני claims), מנסה שוב אחרי 5 שניות
  Future<void> _startFirestoreListener() async {
    final user = await _authService.getCurrentUser();
    if (user == null || !mounted) return;

    _firestoreListener?.cancel();
    _firestoreListener = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen((snapshot) async {
      if (!mounted) return;
      if (!snapshot.exists || snapshot.data() == null) return;

      final data = snapshot.data()!;
      _handleUserData(data);
    }, onError: (e) {
      print('DEBUG WaitingForApproval: Firestore listener error: $e — retrying in 5s');
      // ניסיון חוזר אחרי 5 שניות — claims עשויים להתעדכן
      _retryTimer?.cancel();
      _retryTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) _startFirestoreListener();
      });
    });

    // fallback: בדיקה ישירה כל 10 שניות — למקרה שה-listener מת
    _fallbackTimer?.cancel();
    _fallbackTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (!mounted) return;
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get()
            .timeout(const Duration(seconds: 5));
        if (doc.exists && doc.data() != null && mounted) {
          _handleUserData(doc.data()!);
        }
      } catch (_) {}
    });
  }

  /// טיפול בנתוני משתמש שהתקבלו מ-Firestore (listener או fallback)
  Future<void> _handleUserData(Map<String, dynamic> data) async {
    final rawApproval = data['isApproved'];
    final firestoreUnitId = data['unitId'] as String?;

    if (rawApproval == true) {
      // אושר — עדכון DB מקומי + רענון token לקבלת claims חדשים + מעבר למסך הבית
      final currentUser = await _authService.getCurrentUser();
      if (currentUser != null) {
        await _userRepo.saveUserLocally(
          currentUser.copyWith(approvalStatus: 'approved', updatedAt: DateTime.now()),
          queueSync: false,
        );
        // רענון token כדי שה-claims החדשים (isApproved=true) ייכנסו לתוקף מיד
        await FirebaseAuth.instance.currentUser?.getIdToken(true);
      }
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/home');
      }
    } else if (rawApproval == false) {
      // נדחה — הצגת דיאלוג דחייה עם אפשרויות
      if (mounted) _showRejectionDialog();
    } else if (firestoreUnitId == null || firestoreUnitId.isEmpty) {
      // הוסר מיחידה — חזרה למסך בחירת יחידה
      final currentUser = await _authService.getCurrentUser();
      if (currentUser != null) {
        await _userRepo.saveUserLocally(
          currentUser.copyWith(unitId: '', clearApprovalStatus: true, updatedAt: DateTime.now()),
          queueSync: false,
        );
      }
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ChooseUnitScreen()),
        );
      }
    }
    // else: still "pending", do nothing
  }

  bool _rejectionDialogShowing = false;

  void _showRejectionDialog() {
    if (_rejectionDialogShowing) return;
    _rejectionDialogShowing = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('בקשתך נדחתה'),
        content: Text('בקשתך להצטרף ליחידה "${widget.unitName}" נדחתה.\nמה ברצונך לעשות?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _rejectionDialogShowing = false;
              _requestAgain();
            },
            child: const Text('בקש שוב'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _rejectionDialogShowing = false;
              _chooseOtherUnit();
            },
            child: const Text('בחר יחידה אחרת'),
          ),
        ],
      ),
    );
  }

  Future<void> _requestAgain() async {
    final user = await _authService.getCurrentUser();
    if (user == null) return;
    await _userRepo.requestAgain(user.uid);
    // listener יורה — יראה "pending", לא יעשה כלום — נשארים על המסך
  }

  Future<void> _chooseOtherUnit() async {
    final user = await _authService.getCurrentUser();
    if (user == null) return;
    await _userRepo.cancelAndChooseNewUnit(user.uid);
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ChooseUnitScreen()),
      );
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _fallbackTimer?.cancel();
    _firestoreListener?.cancel();
    super.dispose();
  }

  Future<void> _cancelRequest() async {
    if (_cancelling) return;
    setState(() => _cancelling = true);

    try {
      final user = await _authService.getCurrentUser();
      if (user == null) return;

      await _userRepo.cancelAndChooseNewUnit(user.uid);

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
