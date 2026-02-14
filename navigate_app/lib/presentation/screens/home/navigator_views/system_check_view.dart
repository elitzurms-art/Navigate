import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../../domain/entities/navigation.dart' as domain;
import '../../../../domain/entities/user.dart';
import '../../../../services/gps_service.dart';

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

  int _batteryLevel = -1; // -1 = לא זמין
  bool _isCheckingBattery = true;
  ConnectivityResult? _connectivity;
  bool _isCheckingConnectivity = true;

  bool _hasGpsPermission = false;
  bool _hasLocationService = false;
  bool _isCheckingGps = true;

  Map<String, PermissionStatus> _permissions = {};
  bool _isCheckingPermissions = true;

  @override
  void initState() {
    super.initState();
    _runChecks();
  }

  @override
  void dispose() {
    _gpsService.dispose();
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

    return SingleChildScrollView(
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
