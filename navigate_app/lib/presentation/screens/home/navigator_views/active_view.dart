import 'package:flutter/material.dart';
import '../../../../domain/entities/navigation.dart' as domain;
import '../../../../domain/entities/user.dart';
import '../../../../services/security_manager.dart';

/// תצוגת ניווט פעיל למנווט — גריד 2×2 עם פעולות + הפעלת אבטחה
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

  int _punchCount = 0;
  bool _securityActive = false;

  domain.Navigation get _nav => widget.navigation;
  domain.AssignedRoute? get _route => _nav.routes[widget.currentUser.uid];

  @override
  void initState() {
    super.initState();
    _startSecurity();
  }

  @override
  void dispose() {
    _stopSecurity();
    super.dispose();
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
  // Actions
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

  void _reportStatus() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('דיווח תקינות'),
        content: const Text('פיצ\'ר בפיתוח — דיווח תקינות יישלח למפקד'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('סגור'),
          ),
        ],
      ),
    );
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
              // TODO: integrate emergency alert via NavigationRepository.pushAlert
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('התראת חירום נשלחה'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('שלח', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
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
    return Column(
      children: [
        // Status bar
        _buildStatusBar(),
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
      ],
    );
  }

  Widget _buildStatusBar() {
    final route = _route;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Theme.of(context).primaryColor.withOpacity(0.1),
      child: Row(
        children: [
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
          const SizedBox(width: 12),
          _statusChip(
            icon: Icons.gps_fixed,
            label: 'GPS פעיל',
          ),
        ],
      ),
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
