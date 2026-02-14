import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../../domain/entities/navigation.dart' as domain;
import '../../../domain/entities/checkpoint.dart';
import '../../../domain/entities/checkpoint_punch.dart';
import '../../../domain/entities/coordinate.dart';
import '../../../services/gps_tracking_service.dart';
import '../../../services/security_manager.dart';
import 'package:uuid/uuid.dart';

/// מסך ניהול ניווט פעיל (למנווט)
class ActiveNavigationScreen extends StatefulWidget {
  final domain.Navigation navigation;
  final String navigatorId;
  final List<Checkpoint> assignedCheckpoints;

  const ActiveNavigationScreen({
    super.key,
    required this.navigation,
    required this.navigatorId,
    required this.assignedCheckpoints,
  });

  @override
  State<ActiveNavigationScreen> createState() => _ActiveNavigationScreenState();
}

class _ActiveNavigationScreenState extends State<ActiveNavigationScreen> {
  final GPSTrackingService _gpsService = GPSTrackingService();
  final SecurityManager _securityManager = SecurityManager();
  final Uuid _uuid = const Uuid();

  bool _isNavigationActive = false;
  Position? _currentPosition;
  List<CheckpointPunch> _punches = [];
  double _totalDistance = 0;

  @override
  void dispose() {
    if (_isNavigationActive) {
      _stopNavigation();
    }
    super.dispose();
  }

  Future<void> _startNavigation() async {
    // התחלת GPS tracking
    final gpsStarted = await _gpsService.startTracking(
      intervalSeconds: widget.navigation.gpsUpdateIntervalSeconds,
    );

    if (!gpsStarted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('שגיאה בהפעלת GPS'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // התחלת אבטחה (נעילה)
    await _securityManager.startNavigationSecurity(
      navigationId: widget.navigation.id,
      navigatorId: widget.navigatorId,
      settings: widget.navigation.securitySettings,
    );

    // האזנה למיקומים
    _gpsService.positionStream.listen((position) {
      if (mounted) {
        setState(() {
          _currentPosition = position;
          _totalDistance = _gpsService.getTotalDistance();
        });
      }
    });

    setState(() => _isNavigationActive = true);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('הניווט התחיל!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _stopNavigation() async {
    await _gpsService.stopTracking();
    await _securityManager.stopNavigationSecurity();
    setState(() => _isNavigationActive = false);
  }

  Future<void> _punchCheckpoint() async {
    if (_currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('אין מיקום GPS')),
      );
      return;
    }

    // בחירת נקודה לדקירה
    final checkpoint = await showDialog<Checkpoint>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('בחר נקודת ציון לדקירה'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: widget.assignedCheckpoints.map((cp) {
              final alreadyPunched = _punches.any(
                (p) => p.checkpointId == cp.id && !p.isDeleted,
              );
              return ListTile(
                leading: Icon(
                  Icons.place,
                  color: alreadyPunched ? Colors.green : Colors.grey,
                ),
                title: Text(cp.name),
                subtitle: Text('מספר: ${cp.sequenceNumber}'),
                trailing: alreadyPunched
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : null,
                onTap: () => Navigator.pop(context, cp),
              );
            }).toList(),
          ),
        ),
      ),
    );

    if (checkpoint == null) return;

    // אישור
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('דקירת נקודת ציון'),
        content: Text('האם אתה בטוח שברצונך לדקור:\n${checkpoint.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.green),
            child: const Text('דקור'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // יצירת דקירה
    final punch = CheckpointPunch(
      id: _uuid.v4(),
      navigationId: widget.navigation.id,
      navigatorId: widget.navigatorId,
      checkpointId: checkpoint.id,
      punchLocation: Coordinate(
        lat: _currentPosition!.latitude,
        lng: _currentPosition!.longitude,
        utm: '', // TODO: חישוב UTM
      ),
      punchTime: DateTime.now(),
      distanceFromCheckpoint: Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        checkpoint.coordinates!.lat,
        checkpoint.coordinates!.lng,
      ),
    );

    setState(() => _punches.add(punch));

    // TODO: שמירה ב-DB ושליחה לשרת

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('נקודה נדקרה: ${checkpoint.name}'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _deletePunch() async {
    // TODO: מחיקת דקירה
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('מחיקת דקירה - בפיתוח')),
    );
  }

  Future<void> _finishNavigation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('סיום ניווט'),
        content: const Text('האם אתה בטוח שברצונך לסיים את הניווט?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('סיים'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _stopNavigation();

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('הניווט הסתיים'),
          backgroundColor: Colors.blue,
        ),
      );
    }
  }

  Future<void> _sendEmergency() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red, size: 32),
            SizedBox(width: 12),
            Text('חירום'),
          ],
        ),
        content: const Text(
          'האם אתה בטוח שברצונך לדווח על מצוקה?\n\n'
          'התראה תישלח לכל המפקדים!',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.red,
            ),
            child: const Text('דווח חירום'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // TODO: שליחת התראת חירום

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('התראת חירום נשלחה!'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _sendBarbur() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info, color: Colors.orange, size: 32),
            SizedBox(width: 12),
            Text('ברבור'),
          ],
        ),
        content: const Text('האם אתה בטוח שברצונך לדווח על ברבור?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            child: const Text('דווח ברבור'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // TODO: שליחת התראת ברבור

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('התראת ברבור נשלחה'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.navigation.name),
            Text(
              _isNavigationActive ? 'ניווט פעיל' : 'ממתין להתחלה',
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
        backgroundColor: _isNavigationActive ? Colors.green : Colors.grey,
        foregroundColor: Colors.white,
      ),
      body: _isNavigationActive ? _buildActiveView() : _buildStartView(),
    );
  }

  Widget _buildStartView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.play_circle_outline,
              size: 120,
              color: Colors.green[700],
            ),
            const SizedBox(height: 32),
            const Text(
              'ניווט מוכן להתחלה',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(
              'לחץ על הכפתור להתחלת הניווט',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            const SizedBox(height: 48),
            SizedBox(
              width: double.infinity,
              height: 64,
              child: ElevatedButton.icon(
                onPressed: _startNavigation,
                icon: const Icon(Icons.play_arrow, size: 32),
                label: const Text(
                  'התחל ניווט',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveView() {
    return Column(
      children: [
        // סטטוס
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: Colors.green[50],
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatusItem(
                    icon: Icons.route,
                    label: 'מרחק',
                    value: '${_totalDistance.toStringAsFixed(2)} ק"מ',
                  ),
                  _buildStatusItem(
                    icon: Icons.check_circle,
                    label: 'נדקרו',
                    value: '${_punches.where((p) => !p.isDeleted).length}/${widget.assignedCheckpoints.length}',
                  ),
                  if (_currentPosition != null)
                    _buildStatusItem(
                      icon: Icons.gps_fixed,
                      label: 'GPS',
                      value: '${_currentPosition!.accuracy.toInt()}m',
                    ),
                ],
              ),
            ],
          ),
        ),

        // כפתורי פעולה
        Expanded(
          child: GridView.count(
            crossAxisCount: 2,
            padding: const EdgeInsets.all(16),
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            children: [
              _buildActionButton(
                icon: Icons.push_pin,
                label: 'דקירת נ.צ',
                color: Colors.blue,
                onTap: _punchCheckpoint,
              ),
              _buildActionButton(
                icon: Icons.delete,
                label: 'מחיקת דקירה',
                color: Colors.orange,
                onTap: _deletePunch,
              ),
              _buildActionButton(
                icon: Icons.stop_circle,
                label: 'סיום ניווט',
                color: Colors.red,
                onTap: _finishNavigation,
              ),
              _buildActionButton(
                icon: Icons.warning,
                label: 'חירום',
                color: Colors.red[900]!,
                onTap: _sendEmergency,
              ),
              _buildActionButton(
                icon: Icons.info,
                label: 'ברבור',
                color: Colors.amber,
                onTap: _sendBarbur,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      children: [
        Icon(icon, color: Colors.green[700]),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 4,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color.withOpacity(0.8), color],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 48, color: Colors.white),
              const SizedBox(height: 12),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
