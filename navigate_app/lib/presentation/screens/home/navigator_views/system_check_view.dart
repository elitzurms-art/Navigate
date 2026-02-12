import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../../../domain/entities/navigation.dart' as domain;
import '../../../../domain/entities/user.dart';

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
  double? _batteryLevel;
  bool _isCheckingBattery = true;
  ConnectivityResult? _connectivity;
  bool _isCheckingConnectivity = true;

  @override
  void initState() {
    super.initState();
    _runChecks();
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
      if (mounted) {
        setState(() => _isCheckingConnectivity = false);
      }
    }

    // סוללה — placeholder (אין package מובנה)
    if (mounted) {
      setState(() {
        _batteryLevel = null; // TODO: integrate battery_plus
        _isCheckingBattery = false;
      });
    }
  }

  Color _batteryColor(double? level) {
    if (level == null) return Colors.grey;
    if (level < 0.2) return Colors.red;
    if (level < 0.5) return Colors.orange;
    return Colors.green;
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
            icon: Icons.battery_std,
            title: 'סוללה',
            value: _isCheckingBattery
                ? 'בודק...'
                : _batteryLevel != null
                    ? '${(_batteryLevel! * 100).toInt()}%'
                    : 'לא זמין',
            color: _isCheckingBattery ? Colors.grey : _batteryColor(_batteryLevel),
          ),

          // GPS
          _checkCard(
            icon: Icons.gps_fixed,
            title: 'GPS',
            value: 'פעיל', // TODO: integrate GpsService
            color: Colors.green,
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

          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _isCheckingBattery = true;
                  _isCheckingConnectivity = true;
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
