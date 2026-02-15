import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../domain/entities/navigation.dart' as domain;
import '../../../../domain/entities/checkpoint_punch.dart';
import '../../../../domain/entities/coordinate.dart';
import '../../../../domain/entities/user.dart';
import '../../../../domain/entities/navigator_personal_status.dart';
import '../../../../data/repositories/navigation_track_repository.dart';
import '../../../../data/repositories/checkpoint_punch_repository.dart';
import '../../../../data/repositories/navigator_alert_repository.dart';
import '../../../../data/datasources/local/app_database.dart' hide User;
import '../../../../core/constants/app_constants.dart';
import '../../../../services/gps_service.dart';
import '../../../../services/gps_tracking_service.dart';
import '../../../../services/health_check_service.dart';
import '../../../../services/security_manager.dart';
import '../../../../services/alert_monitoring_service.dart';

/// תצוגת ניווט פעיל למנווט — 3 מצבים: ממתין / פעיל / סיים
class ActiveView extends StatefulWidget {
  final domain.Navigation navigation;
  final User currentUser;
  final ValueChanged<domain.Navigation> onNavigationUpdated;

  const ActiveView({
    super.key,
    required this.navigation,
    required this.currentUser,
    required this.onNavigationUpdated,
  });

  @override
  State<ActiveView> createState() => _ActiveViewState();
}

class _ActiveViewState extends State<ActiveView> {
  final SecurityManager _securityManager = SecurityManager();
  final GpsService _gpsService = GpsService();
  final NavigatorAlertRepository _alertRepo = NavigatorAlertRepository();
  final NavigationTrackRepository _trackRepo = NavigationTrackRepository();
  final CheckpointPunchRepository _punchRepo = CheckpointPunchRepository();

  NavigatorPersonalStatus _personalStatus = NavigatorPersonalStatus.waiting;
  NavigationTrack? _track;
  bool _isLoading = true;

  int _punchCount = 0;
  bool _securityActive = false;

  // GPS tracking
  final GPSTrackingService _gpsTracker = GPSTrackingService();
  Timer? _trackSaveTimer;
  int _trackPointCount = 0;

  // GPS source tracking
  PositionSource _gpsSource = PositionSource.none;
  Timer? _gpsCheckTimer;

  // Health check
  HealthCheckService? _healthCheckService;

  // Alert monitoring
  AlertMonitoringService? _alertMonitoringService;

  // טיימר זמן שחלף
  Timer? _elapsedTimer;
  Duration _elapsed = Duration.zero;
  DateTime? _startTime;

  domain.Navigation get _nav => widget.navigation;
  domain.AssignedRoute? get _route => _nav.routes[widget.currentUser.uid];

  @override
  void initState() {
    super.initState();
    _loadTrackState();
  }

  @override
  void dispose() {
    _stopSecurity();
    _gpsCheckTimer?.cancel();
    _elapsedTimer?.cancel();
    _trackSaveTimer?.cancel();
    _healthCheckService?.dispose();
    _alertMonitoringService?.dispose();
    _gpsTracker.stopTracking();
    _gpsService.dispose();
    super.dispose();
  }

  // ===========================================================================
  // State loading
  // ===========================================================================

  Future<void> _loadTrackState() async {
    try {
      final track = await _trackRepo.getByNavigatorAndNavigation(
        widget.currentUser.uid,
        _nav.id,
      );

      final punches = await _punchRepo.getByNavigator(widget.currentUser.uid);
      final navPunches = punches.where((p) => p.navigationId == _nav.id).toList();

      NavigatorPersonalStatus status;
      NavigationTrack? effectiveTrack = track;
      if (track == null) {
        status = NavigatorPersonalStatus.waiting;
      } else {
        status = NavigatorPersonalStatus.deriveFromTrack(
          hasTrack: true,
          isActive: track.isActive,
          endedAt: track.endedAt,
        );
      }

      // Safety net: אם הניווט פעיל/ממתין אבל ה-track המקומי מראה "סיים" —
      // זהו track ישן מהפעלה קודמת. מוחקים ומאפסים.
      final navStatus = _nav.status;
      if (status == NavigatorPersonalStatus.finished &&
          (navStatus == 'active' || navStatus == 'waiting')) {
        if (effectiveTrack != null) {
          await _trackRepo.deleteByNavigation(_nav.id);
          effectiveTrack = null;
        }
        status = NavigatorPersonalStatus.waiting;
      }

      if (mounted) {
        setState(() {
          _track = effectiveTrack;
          _personalStatus = status;
          _punchCount = navPunches.length;
          _isLoading = false;
        });

        // אם המנווט כבר פעיל (חזר למסך) — להמשיך טיימר + שירותים
        if (status == NavigatorPersonalStatus.active && track != null) {
          _startTime = track.startedAt;
          _elapsed = DateTime.now().difference(track.startedAt);
          _startElapsedTimer();
          _startSecurity();
          _startGpsTracking();
          _startGpsSourceCheck();
          _startHealthCheck();
          _startAlertMonitoring();
        }

        // אם סיים — לחשב זמן כולל
        if (status == NavigatorPersonalStatus.finished && track != null) {
          _startTime = track.startedAt;
          _elapsed = (track.endedAt ?? DateTime.now()).difference(track.startedAt);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ===========================================================================
  // Timer
  // ===========================================================================

  void _startElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_startTime != null && mounted) {
        setState(() {
          _elapsed = DateTime.now().difference(_startTime!);
        });
      }
    });
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  // ===========================================================================
  // Security
  // ===========================================================================

  Future<void> _startSecurity() async {
    if (_securityActive) return;

    final success = await _securityManager.startNavigationSecurity(
      navigationId: _nav.id,
      navigatorId: widget.currentUser.uid,
      settings: _nav.securitySettings,
    );

    if (mounted) {
      setState(() => _securityActive = success);
    }

    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('לא ניתן להפעיל נעילת אבטחה'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _stopSecurity() async {
    if (!_securityActive) return;
    await _securityManager.stopNavigationSecurity(normalEnd: true);
    _securityActive = false;
  }

  // ===========================================================================
  // GPS Source Check
  // ===========================================================================

  void _startGpsSourceCheck() {
    _checkGpsSource();
    _gpsCheckTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _checkGpsSource();
    });
  }

  Future<void> _checkGpsSource() async {
    await _gpsService.getCurrentPosition(highAccuracy: false);
    if (mounted) {
      setState(() {
        _gpsSource = _gpsService.lastPositionSource;
      });
    }
  }

  // ===========================================================================
  // GPS Tracking — שמירה תקופתית ל-DB + סנכרון
  // ===========================================================================

  Future<void> _startGpsTracking() async {
    final interval = _nav.gpsUpdateIntervalSeconds;
    final started = await _gpsTracker.startTracking(intervalSeconds: interval);
    if (!started) {
      print('DEBUG ActiveView: GPS tracking failed to start');
      return;
    }

    // שמירה תקופתית ל-Drift כל interval שניות (או מינימום 30)
    final saveInterval = interval < 30 ? interval : 30;
    _trackSaveTimer = Timer.periodic(
      Duration(seconds: saveInterval),
      (_) => _saveTrackPoints(),
    );
  }

  Future<void> _saveTrackPoints() async {
    if (_track == null) return;

    final points = _gpsTracker.trackPoints;
    if (points.isEmpty) return;

    try {
      await _trackRepo.updateTrackPoints(_track!.id, points);

      // סנכרון ל-Firestore
      final updatedTrack = await _trackRepo.getById(_track!.id);
      await _trackRepo.syncTrackToFirestore(updatedTrack);

      if (mounted) {
        setState(() => _trackPointCount = points.length);
      }

      // בדיקת עצירה מרחוק (כל ~30 שניות)
      await _checkRemoteStop();
    } catch (e) {
      print('DEBUG ActiveView: track save error: $e');
    }
  }

  Future<void> _stopGpsTracking() async {
    _trackSaveTimer?.cancel();
    _trackSaveTimer = null;

    // שמירה סופית לפני עצירה
    await _saveTrackPoints();

    await _gpsTracker.stopTracking();
  }

  // ===========================================================================
  // Remote Stop — זיהוי עצירה מרחוק ע"י מפקד
  // ===========================================================================

  Future<void> _checkRemoteStop() async {
    if (_track == null || _personalStatus != NavigatorPersonalStatus.active) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection(AppConstants.navigationTracksCollection)
          .doc(_track!.id)
          .get();

      if (!doc.exists) return;

      final data = doc.data();
      if (data == null) return;

      final isActive = data['isActive'] as bool? ?? true;
      if (!isActive) {
        // המפקד עצר את הניווט מרחוק
        await _performRemoteStop();
      }
    } catch (e) {
      print('DEBUG ActiveView: remote stop check error: $e');
    }
  }

  Future<void> _performRemoteStop() async {
    // עצירת GPS tracking
    _trackSaveTimer?.cancel();
    _trackSaveTimer = null;
    await _gpsTracker.stopTracking();

    // עצירת שירותים
    _alertMonitoringService?.stop();
    _healthCheckService?.dispose();
    _gpsCheckTimer?.cancel();
    _elapsedTimer?.cancel();
    await _stopSecurity();

    // עדכון DB מקומי
    if (_track != null) {
      try {
        await _trackRepo.endNavigation(_track!.id);
      } catch (_) {}
    }

    final endTime = DateTime.now();
    _elapsed = endTime.difference(_startTime ?? endTime);

    if (mounted) {
      setState(() {
        _personalStatus = NavigatorPersonalStatus.finished;
        _isLoading = false;
      });

      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('הניווט הופסק על ידי המפקד'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 5),
        ),
      );
    }
  }

  // ===========================================================================
  // Health Check
  // ===========================================================================

  void _startHealthCheck() {
    final alerts = _nav.alerts;
    if (alerts.healthCheckEnabled) {
      _healthCheckService = HealthCheckService(
        intervalMinutes: alerts.healthCheckIntervalMinutes,
        navigatorId: widget.currentUser.uid,
        navigationId: _nav.id,
        navigatorName: widget.currentUser.fullName,
        alertRepository: _alertRepo,
        onAlarmStateChanged: (isAlarming, message) {
          if (mounted) setState(() {});
        },
      );
      _healthCheckService!.start();
    }
  }

  // ===========================================================================
  // Alert Monitoring
  // ===========================================================================

  void _startAlertMonitoring() {
    final route = _route;
    _alertMonitoringService = AlertMonitoringService(
      navigationId: _nav.id,
      navigatorId: widget.currentUser.uid,
      navigatorName: widget.currentUser.fullName,
      alertsConfig: _nav.alerts,
      gpsTracker: _gpsTracker,
      alertRepository: _alertRepo,
      areaId: _nav.areaId,
      boundaryLayerId: _nav.boundaryLayerId,
      plannedPath: route?.plannedPath ?? const [],
    );
    _alertMonitoringService!.start();
  }

  // ===========================================================================
  // Actions — start / end navigation
  // ===========================================================================

  Future<void> _startNavigation() async {
    setState(() => _isLoading = true);
    try {
      final track = await _trackRepo.startNavigation(
        navigatorUserId: widget.currentUser.uid,
        navigationId: _nav.id,
      );

      _startTime = track.startedAt;

      // הפעלת שירותים
      await _startSecurity();
      await _startGpsTracking();
      _startGpsSourceCheck();
      _startHealthCheck();
      _startAlertMonitoring();

      setState(() {
        _track = track;
        _personalStatus = NavigatorPersonalStatus.active;
        _elapsed = Duration.zero;
        _isLoading = false;
      });

      _startElapsedTimer();
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בהתחלת ניווט: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _endNavigation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('סיום ניווט'),
        content: const Text('האם לסיים את הניווט? לא ניתן לחזור אחורה.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ביטול'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('סיום ניווט', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true || _track == null) return;

    setState(() => _isLoading = true);
    try {
      // עצירת GPS tracking + שמירה סופית
      await _stopGpsTracking();

      await _trackRepo.endNavigation(_track!.id);

      // סנכרון סופי אחרי סיום
      final finalTrack = await _trackRepo.getById(_track!.id);
      await _trackRepo.syncTrackToFirestore(finalTrack);

      // עצירת שירותים
      _alertMonitoringService?.stop();
      _gpsCheckTimer?.cancel();
      _elapsedTimer?.cancel();
      _healthCheckService?.dispose();
      await _stopSecurity();

      final endTime = DateTime.now();
      _elapsed = endTime.difference(_startTime ?? endTime);

      setState(() {
        _personalStatus = NavigatorPersonalStatus.finished;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בסיום ניווט: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ===========================================================================
  // Actions — punch, report, emergency, barbur
  // ===========================================================================

  Future<void> _punchCheckpoint() async {
    // TODO: implement real punch logic with GPS + verification
    setState(() => _punchCount++);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('דקירה #$_punchCount נרשמה'),
        backgroundColor: Colors.blue,
      ),
    );
  }

  Future<void> _reportStatus() async {
    _healthCheckService?.reportHealthy();

    try {
      final position = await _gpsService.getCurrentPosition();
      final alert = NavigatorAlert(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        navigationId: _nav.id,
        navigatorId: widget.currentUser.uid,
        type: AlertType.healthReport,
        location: Coordinate(
          lat: position?.latitude ?? 0,
          lng: position?.longitude ?? 0,
          utm: '',
        ),
        timestamp: DateTime.now(),
      );
      await _alertRepo.create(alert);
    } catch (e) {
      print('DEBUG ActiveView: health report failed: $e');
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('דיווח תקינות נשלח'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _emergencyAlert() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('מצב חירום'),
        content: const Text('האם לשלוח התראת חירום למפקד?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ביטול'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _sendEmergencyAlert();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('שלח', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _sendEmergencyAlert() async {
    try {
      final position = await _gpsService.getCurrentPosition();
      final alert = NavigatorAlert(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        navigationId: _nav.id,
        navigatorId: widget.currentUser.uid,
        type: AlertType.emergency,
        location: Coordinate(
          lat: position?.latitude ?? 0,
          lng: position?.longitude ?? 0,
          utm: '',
        ),
        timestamp: DateTime.now(),
        navigatorName: widget.currentUser.fullName,
      );
      await _alertRepo.create(alert);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('התראת חירום נשלחה'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בשליחת התראה: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _barburReport() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('דיווח ברבור'),
        content: const Text('פיצ\'ר בפיתוח — דיווח ברבור'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('סגור'),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // Build
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    switch (_personalStatus) {
      case NavigatorPersonalStatus.waiting:
        return _buildWaitingView();
      case NavigatorPersonalStatus.active:
      case NavigatorPersonalStatus.noReception:
        return _buildActiveView();
      case NavigatorPersonalStatus.finished:
        return _buildFinishedView();
    }
  }

  // ---------------------------------------------------------------------------
  // מצב "ממתין" — כפתור התחלת ניווט
  // ---------------------------------------------------------------------------

  Widget _buildWaitingView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.navigation,
              size: 80,
              color: Colors.green[300],
            ),
            const SizedBox(height: 24),
            Text(
              'ניווט ${_nav.name}',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'לחץ על הכפתור כדי להתחיל',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: 220,
              height: 60,
              child: ElevatedButton.icon(
                onPressed: _startNavigation,
                icon: const Icon(Icons.play_arrow, size: 32),
                label: const Text(
                  'התחלת ניווט',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // מצב "פעיל" — סטטוס + גריד + כפתור סיום
  // ---------------------------------------------------------------------------

  Widget _buildActiveView() {
    return Column(
      children: [
        // Health check alarm banner
        if (_healthCheckService != null && _healthCheckService!.isAlarming)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.red,
            child: Row(
              children: [
                const Icon(Icons.warning, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _healthCheckService!.alarmMessage,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        // Status bar with elapsed timer
        _buildActiveStatusBar(),
        // Security indicator
        if (_securityActive)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: Colors.green.withOpacity(0.15),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock, size: 14, color: Colors.green[700]),
                const SizedBox(width: 6),
                Text(
                  'אבטחה פעילה',
                  style: TextStyle(fontSize: 12, color: Colors.green[700], fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        // 2×2 grid
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: GridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              children: [
                _buildActionCard(
                  title: 'דקירת נ.צ',
                  icon: Icons.location_on,
                  color: Colors.blue,
                  onTap: _punchCheckpoint,
                ),
                _buildActionCard(
                  title: 'דיווח תקינות',
                  icon: Icons.check_circle_outline,
                  color: Colors.green,
                  onTap: _reportStatus,
                ),
                _buildActionCard(
                  title: 'מצב חירום',
                  icon: Icons.warning_amber,
                  color: Colors.red,
                  onTap: _emergencyAlert,
                ),
                _buildActionCard(
                  title: 'ברבור',
                  icon: Icons.report_problem,
                  color: Colors.orange,
                  onTap: _barburReport,
                ),
              ],
            ),
          ),
        ),
        // כפתור סיום ניווט
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _endNavigation,
              icon: const Icon(Icons.stop),
              label: const Text(
                'סיום ניווט',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActiveStatusBar() {
    final route = _route;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Theme.of(context).primaryColor.withOpacity(0.1),
      child: Row(
        children: [
          // שעון זמן שחלף
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.timer, size: 18, color: Colors.green[700]),
                const SizedBox(width: 4),
                Text(
                  _formatDuration(_elapsed),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.green[700],
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _statusChip(
            icon: Icons.route,
            label: route != null
                ? '${route.routeLengthKm.toStringAsFixed(1)} ק"מ'
                : '-',
          ),
          const SizedBox(width: 12),
          _statusChip(
            icon: Icons.location_on,
            label: '$_punchCount דקירות',
          ),
          if (_trackPointCount > 0) ...[
            const SizedBox(width: 12),
            _statusChip(
              icon: Icons.timeline,
              label: '$_trackPointCount נק׳',
            ),
          ],
          const SizedBox(width: 12),
          _buildGpsChip(),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // מצב "סיים" — תצוגת סיכום
  // ---------------------------------------------------------------------------

  Widget _buildFinishedView() {
    final route = _route;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle,
              size: 80,
              color: Colors.green[400],
            ),
            const SizedBox(height: 24),
            const Text(
              'הניווט הסתיים',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 32),
            _summaryRow(
              icon: Icons.timer,
              label: 'זמן כולל',
              value: _formatDuration(_elapsed),
            ),
            const Divider(),
            _summaryRow(
              icon: Icons.location_on,
              label: 'דקירות',
              value: '$_punchCount',
            ),
            if (route != null) ...[
              const Divider(),
              _summaryRow(
                icon: Icons.route,
                label: 'אורך מסלול',
                value: '${route.routeLengthKm.toStringAsFixed(1)} ק"מ',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _summaryRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 28, color: Colors.grey[600]),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // Shared widgets
  // ===========================================================================

  Widget _buildGpsChip() {
    IconData icon;
    String label;
    Color color;
    switch (_gpsSource) {
      case PositionSource.gps:
        icon = Icons.gps_fixed;
        label = 'GPS';
        color = Colors.green;
      case PositionSource.cellTower:
        icon = Icons.cell_tower;
        label = 'אנטנות';
        color = Colors.orange;
      case PositionSource.none:
        icon = Icons.gps_off;
        label = 'אין מיקום';
        color = Colors.red;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _statusChip({required IconData icon, required String label}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.grey[700]),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
      ],
    );
  }

  Widget _buildActionCard({
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.3), width: 2),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 48, color: color),
              const SizedBox(height: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
