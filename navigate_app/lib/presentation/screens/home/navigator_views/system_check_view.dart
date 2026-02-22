import 'dart:async';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../domain/entities/navigation.dart' as domain;
import '../../../../domain/entities/user.dart';
import 'package:latlong2/latlong.dart';
import '../../../../services/gps_service.dart';
import '../../../../services/voice_service.dart';
import '../../../widgets/voice_messages_panel.dart';

/// תצוגת בדיקת מערכות למנווט
class SystemCheckView extends StatefulWidget {
  final domain.Navigation navigation;
  final User currentUser;

  const SystemCheckView({
    super.key,
    required this.navigation,
    required this.currentUser,
  });

  @override
  State<SystemCheckView> createState() => _SystemCheckViewState();
}

class _SystemCheckViewState extends State<SystemCheckView> {
  final Battery _battery = Battery();
  final GpsService _gpsService = GpsService();
  VoiceService? _voiceService;

  int _batteryLevel = -1; // -1 = לא זמין
  bool _isCheckingBattery = true;
  ConnectivityResult? _connectivity;
  bool _isCheckingConnectivity = true;

  bool _hasGpsPermission = false;
  bool _hasLocationService = false;
  bool _isCheckingGps = true;
  double _gpsAccuracy = -1;
  LatLng? _currentPosition;

  Map<String, PermissionStatus> _permissions = {};
  bool _isCheckingPermissions = true;

  Timer? _periodicTimer;
  int _checkCount = 0; // סופר בדיקות — דיווח ל-Firestore כל 5 בדיקות (15 שניות)

  @override
  void initState() {
    super.initState();
    _runChecks();
  }

  @override
  void dispose() {
    _periodicTimer?.cancel();
    _gpsService.dispose();
    _voiceService?.dispose();
    super.dispose();
  }

  Future<void> _runChecks() async {
    // בדיקת קישוריות
    try {
      final result = await Connectivity().checkConnectivity();
      if (mounted) {
        setState(() {
          _connectivity = result;
          _isCheckingConnectivity = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isCheckingConnectivity = false);
    }

    // בדיקת סוללה
    try {
      final level = await _battery.batteryLevel;
      if (mounted) {
        setState(() {
          _batteryLevel = level;
          _isCheckingBattery = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _batteryLevel = -1;
          _isCheckingBattery = false;
        });
      }
    }

    // בדיקת GPS
    try {
      _hasLocationService = await _gpsService.isGpsAvailable();
      _hasGpsPermission = await _gpsService.checkPermissions();
      if (_hasGpsPermission && _hasLocationService) {
        _gpsAccuracy = await _gpsService.getCurrentAccuracy();
      }
      // תמיד מנסה לקבל מיקום — גם דרך אנטנות אם GPS כבוי
      _currentPosition = await _gpsService.getCurrentPosition();
      if (mounted) setState(() => _isCheckingGps = false);
    } catch (_) {
      if (mounted) setState(() => _isCheckingGps = false);
    }

    // בדיקת הרשאות מכשיר
    try {
      final perms = {
        'location': await Permission.location.status,
        'locationAlways': await Permission.locationAlways.status,
        'notification': await Permission.notification.status,
        'microphone': await Permission.microphone.status,
        'phone': await Permission.phone.status,
      };
      if (mounted) {
        setState(() {
          _permissions = perms;
          _isCheckingPermissions = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isCheckingPermissions = false);
    }

    // דיווח סטטוס ל-Firestore כדי שהמפקד יראה
    _reportStatusToFirestore();

    // הפעלת בדיקה מחזורית כל 3 שניות (דיווח Firestore כל 5 בדיקות ≈ 15 שניות)
    _periodicTimer ??= Timer.periodic(
      const Duration(seconds: 3),
      (_) => _checkAndReport(),
    );
  }

  /// בדיקה מחזורית (כל 3 שניות) ודיווח ל-Firestore (כל ~15 שניות)
  Future<void> _checkAndReport() async {
    if (!mounted) return;
    try {
      _hasLocationService = await _gpsService.isGpsAvailable();
      _hasGpsPermission = await _gpsService.checkPermissions();

      if (_hasGpsPermission && _hasLocationService) {
        _gpsAccuracy = await _gpsService.getCurrentAccuracy();
      }

      // תמיד מנסה לקבל מיקום — גם דרך אנטנות אם GPS כבוי
      _currentPosition = await _gpsService.getCurrentPosition();
      print('DEBUG SystemCheckView: perm=$_hasGpsPermission svc=$_hasLocationService pos=$_currentPosition accuracy=$_gpsAccuracy source=${_gpsService.lastPositionSource}');

      try {
        _batteryLevel = await _battery.batteryLevel;
      } catch (_) {
        _batteryLevel = -1;
      }

      try {
        final result = await Connectivity().checkConnectivity();
        _connectivity = result;
      } catch (_) {}

      if (mounted) setState(() {});

      // דיווח ל-Firestore כל 5 בדיקות (~15 שניות) כדי לא להעמיס
      _checkCount++;
      if (_checkCount % 5 == 0) {
        _reportStatusToFirestore();
      }
    } catch (e) {
      print('DEBUG SystemCheckView: _checkAndReport error: $e');
    }
  }

  /// כתיבת סטטוס בדיקת מערכות ל-Firestore (מנווט → מפקד)
  Future<void> _reportStatusToFirestore() async {
    final uid = widget.currentUser.uid;
    try {
      final docRef = FirebaseFirestore.instance
          .collection(AppConstants.navigationsCollection)
          .doc(widget.navigation.id)
          .collection('system_status')
          .doc(uid);

      final data = <String, dynamic>{
        'navigatorId': uid,
        'navigatorName': widget.currentUser.fullName,
        'isConnected': _currentPosition != null,
        'batteryLevel': _batteryLevel,
        'hasGPS': _hasGpsPermission && _hasLocationService,
        'gpsAccuracy': _gpsAccuracy,
        'receptionLevel': _estimateReceptionLevel(),
        'positionSource': _gpsService.lastPositionSource.name,
        'hasMicrophonePermission': _permissions['microphone']?.isGranted ?? false,
        'hasPhonePermission': _permissions['phone']?.isGranted ?? false,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      // רק מעדכן מיקום כשיש — לא דורס עם null
      if (_currentPosition != null) {
        data['latitude'] = _currentPosition!.latitude;
        data['longitude'] = _currentPosition!.longitude;
        data['positionUpdatedAt'] = FieldValue.serverTimestamp();
      }
      await docRef.set(data, SetOptions(merge: true));
    } catch (e) {
      print('DEBUG SystemCheckView: failed to report status: $e');
    }
  }

  /// הערכת רמת קליטה לפי דיוק GPS
  int _estimateReceptionLevel() {
    if (!_hasGpsPermission || !_hasLocationService) return 0;
    if (_gpsAccuracy < 0) return 0;
    if (_gpsAccuracy <= 10) return 4; // מצוין
    if (_gpsAccuracy <= 30) return 3; // טוב
    if (_gpsAccuracy <= 50) return 2; // בינוני
    if (_gpsAccuracy <= 100) return 1; // חלש
    return 0;
  }

  Color _batteryColor() {
    if (_batteryLevel < 0) return Colors.grey;
    if (_batteryLevel < 20) return Colors.red;
    if (_batteryLevel < 50) return Colors.orange;
    return Colors.green;
  }

  String _batteryText() {
    if (_batteryLevel < 0) return 'לא זמין';
    return '$_batteryLevel%';
  }

  Color _connectivityColor(ConnectivityResult? result) {
    if (result == null) return Colors.grey;
    switch (result) {
      case ConnectivityResult.mobile:
      case ConnectivityResult.wifi:
      case ConnectivityResult.ethernet:
        return Colors.green;
      case ConnectivityResult.none:
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  String _connectivityLabel(ConnectivityResult? result) {
    if (result == null) return 'בודק...';
    switch (result) {
      case ConnectivityResult.mobile:
        return 'סלולרי';
      case ConnectivityResult.wifi:
        return 'WiFi';
      case ConnectivityResult.ethernet:
        return 'Ethernet';
      case ConnectivityResult.none:
        return 'אין חיבור';
      default:
        return 'לא ידוע';
    }
  }

  String _gpsText() {
    if (!_hasGpsPermission) return 'אין הרשאה';
    if (!_hasLocationService) return 'כבוי';
    return 'פעיל';
  }

  Color _gpsColor() {
    if (_hasGpsPermission && _hasLocationService) return Colors.green;
    return Colors.red;
  }

  String _permissionDisplayName(String key) {
    switch (key) {
      case 'location': return 'מיקום (GPS)';
      case 'locationAlways': return 'מיקום ברקע';
      case 'notification': return 'התראות';
      case 'microphone': return 'מיקרופון';
      case 'phone': return 'טלפון';
      default: return key;
    }
  }

  String _permissionStatusText(PermissionStatus status) {
    if (status.isGranted) return 'מאושר';
    if (status.isPermanentlyDenied) return 'נחסם — יש לאשר בהגדרות';
    if (status.isDenied) return 'לא אושר';
    if (status.isRestricted) return 'מוגבל';
    return 'לא ידוע';
  }

  Permission _permissionFromKey(String key) {
    switch (key) {
      case 'location': return Permission.location;
      case 'locationAlways': return Permission.locationAlways;
      case 'notification': return Permission.notification;
      case 'microphone': return Permission.microphone;
      case 'phone': return Permission.phone;
      default: return Permission.location;
    }
  }

  Future<void> _requestPermission(String key) async {
    final permission = _permissionFromKey(key);
    final result = await permission.request();
    if (mounted) {
      setState(() => _permissions[key] = result);
      if (!result.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('ההרשאה לא אושרה — ניתן לאשר בהגדרות המכשיר'),
            action: SnackBarAction(label: 'הגדרות', onPressed: openAppSettings),
          ),
        );
      }
    }
    // רענן גם GPS אם זו הרשאת מיקום
    if (key == 'location' || key == 'locationAlways') {
      _hasGpsPermission = await _gpsService.checkPermissions();
      _hasLocationService = await _gpsService.isGpsAvailable();
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final route = widget.navigation.routes[widget.currentUser.uid];
    final routeApproved = route?.isApproved ?? false;

    final pttEnabled = widget.navigation.communicationSettings.walkieTalkieEnabled;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'בדיקת מערכות',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.navigation.name,
                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                ),
                const SizedBox(height: 24),

                // סוללה
                _checkCard(
                  icon: _batteryLevel < 0
                      ? Icons.battery_unknown
                      : _batteryLevel < 20
                          ? Icons.battery_alert
                          : Icons.battery_std,
                  title: 'סוללה',
                  value: _isCheckingBattery ? 'בודק...' : _batteryText(),
                  color: _isCheckingBattery ? Colors.grey : _batteryColor(),
                ),

                // GPS
                _checkCard(
                  icon: (_hasGpsPermission && _hasLocationService) ? Icons.gps_fixed : Icons.gps_off,
                  title: 'GPS',
                  value: _isCheckingGps ? 'בודק...' : _gpsText(),
                  color: _isCheckingGps ? Colors.grey : _gpsColor(),
                ),

                // קישוריות
                _checkCard(
                  icon: Icons.signal_cellular_alt,
                  title: 'קישוריות',
                  value: _isCheckingConnectivity
                      ? 'בודק...'
                      : _connectivityLabel(_connectivity),
                  color: _isCheckingConnectivity
                      ? Colors.grey
                      : _connectivityColor(_connectivity),
                ),

                // אישור ציר
                _checkCard(
                  icon: routeApproved ? Icons.check_circle : Icons.cancel,
                  title: 'אישור ציר',
                  value: routeApproved ? 'אושר' : 'לא אושר',
                  color: routeApproved ? Colors.green : Colors.red,
                ),

                const SizedBox(height: 16),

                // הרשאות מכשיר
                _buildPermissionsSection(),

                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _isCheckingBattery = true;
                        _isCheckingConnectivity = true;
                        _isCheckingGps = true;
                        _isCheckingPermissions = true;
                      });
                      _runChecks();
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('בדיקה מחדש'),
                  ),
                ),
              ],
            ),
          ),
        ),
        // ווקי טוקי
        if (pttEnabled) ...[
          Builder(builder: (context) {
            _voiceService ??= VoiceService();
            return VoiceMessagesPanel(
              navigationId: widget.navigation.id,
              currentUser: widget.currentUser,
              voiceService: _voiceService!,
              isCommander: false,
              enabled: true,
            );
          }),
        ],
      ],
    );
  }

  Widget _buildPermissionsSection() {
    if (_isCheckingPermissions) {
      return const Card(
        margin: EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_permissions.isEmpty) return const SizedBox.shrink();

    final allGranted = _permissions.values.every((s) => s.isGranted);

    return Card(
      color: allGranted ? Colors.green[50] : Colors.orange[50],
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  allGranted ? Icons.verified_user : Icons.security,
                  color: allGranted ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 8),
                Text(
                  'הרשאות מכשיר',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: allGranted ? Colors.green[800] : Colors.orange[800],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ..._permissions.entries.map((entry) {
              final isGranted = entry.value.isGranted;
              final isPermanentlyDenied = entry.value.isPermanentlyDenied;
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  isGranted ? Icons.check_circle : Icons.cancel,
                  color: isGranted ? Colors.green : Colors.red,
                  size: 22,
                ),
                title: Text(_permissionDisplayName(entry.key)),
                subtitle: Text(
                  _permissionStatusText(entry.value),
                  style: TextStyle(
                    fontSize: 12,
                    color: isGranted ? Colors.green[700] : Colors.red[700],
                  ),
                ),
                trailing: isGranted
                    ? null
                    : isPermanentlyDenied
                        ? TextButton(
                            onPressed: openAppSettings,
                            child: const Text('הגדרות'),
                          )
                        : TextButton(
                            onPressed: () => _requestPermission(entry.key),
                            child: const Text('אשר'),
                          ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _checkCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon, color: color, size: 32),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
