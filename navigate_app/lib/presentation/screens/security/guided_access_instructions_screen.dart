import 'package:flutter/material.dart';
import '../../../services/device_security_service.dart';

/// מסך הנחיות להפעלת Guided Access (iOS)
class GuidedAccessInstructionsScreen extends StatefulWidget {
  final VoidCallback onConfirmed;

  const GuidedAccessInstructionsScreen({
    super.key,
    required this.onConfirmed,
  });

  @override
  State<GuidedAccessInstructionsScreen> createState() =>
      _GuidedAccessInstructionsScreenState();
}

class _GuidedAccessInstructionsScreenState
    extends State<GuidedAccessInstructionsScreen> {
  final DeviceSecurityService _securityService = DeviceSecurityService();
  bool _isChecking = false;

  Future<void> _checkAndProceed() async {
    setState(() => _isChecking = true);

    final isEnabled = await _securityService.isGuidedAccessEnabled();

    setState(() => _isChecking = false);

    if (isEnabled) {
      // Guided Access מופעל - אפשר להמשיך
      if (mounted) {
        Navigator.pop(context);
        widget.onConfirmed();
      }
    } else {
      // לא מופעל - הצגת אזהרה
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.warning, color: Colors.red),
                SizedBox(width: 8),
                Text('Guided Access לא מופעל'),
              ],
            ),
            content: const Text(
              'על מנת להתחיל ניווט, חובה להפעיל Guided Access.\n\n'
              'אנא עקוב אחרי ההוראות והפעל את Guided Access לפני המשך.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('הבנתי'),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('הנחיות אבטחה - iOS'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // אייקון אזהרה
            Center(
              child: Icon(
                Icons.security,
                size: 80,
                color: Colors.orange[700],
              ),
            ),
            const SizedBox(height: 24),

            // כותרת
            const Text(
              'הפעלת Guided Access נדרשת',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),

            const Text(
              'לפני התחלת הניווט, חובה להפעיל Guided Access כדי למנוע יציאה מהאפליקציה.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 32),

            // הוראות
            const Text(
              'הוראות הפעלה:',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            _buildStep(
              number: '1',
              title: 'פתח הגדרות iOS',
              description: 'Settings → Accessibility → Guided Access',
            ),

            _buildStep(
              number: '2',
              title: 'הפעל Guided Access',
              description: 'הפעל את המתג העליון',
            ),

            _buildStep(
              number: '3',
              title: 'הגדר קוד',
              description: 'קבע קוד PIN לביטול (זכור אותו!)',
            ),

            _buildStep(
              number: '4',
              title: 'חזור לאפליקציה',
              description: 'לחץ 3 פעמים על כפתור הבית (או צד) להפעלה',
            ),

            _buildStep(
              number: '5',
              title: 'לחץ "אישור"',
              description: 'המערכת תבדוק שהכל מופעל',
            ),

            const SizedBox(height: 32),

            // הערה חשובה
            Card(
              color: Colors.red[50],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber, color: Colors.red[700]),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'חשוב: לא תוכל לצאת מהאפליקציה במהלך הניווט!\n'
                        'לביטול Guided Access: לחץ 3 פעמים על כפתור הצד והכנס את הקוד.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 32),

            // כפתור אישור
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _isChecking ? null : _checkAndProceed,
                icon: _isChecking
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_circle),
                label: Text(_isChecking ? 'בודק...' : 'אישור - הפעלתי Guided Access'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  textStyle: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep({
    required String number,
    required String title,
    required String description,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.orange,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
