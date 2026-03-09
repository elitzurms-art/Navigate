import 'package:flutter/material.dart';
import '../../../services/device_security_service.dart';

/// מסך הנחיות להפעלת Guided Access (iOS)
/// מחזיר `true` ב-pop כאשר המשתמש אישר (GA מזוהה או אישור עצמי)
class GuidedAccessInstructionsScreen extends StatefulWidget {
  const GuidedAccessInstructionsScreen({super.key});

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
      // Guided Access מופעל — pop with true
      if (mounted) {
        Navigator.pop(context, true);
      }
    } else {
      // לא מזוהה — שאל את המשתמש לאישור עצמי
      if (mounted) {
        final selfConfirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.help_outline, color: Colors.orange),
                SizedBox(width: 8),
                Flexible(child: Text('Guided Access הופעל?')),
              ],
            ),
            content: const Text(
              'המערכת לא הצליחה לזהות ש-Guided Access מופעל.\n\n'
              'האם הפעלת Guided Access?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('לא'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('כן, הפעלתי'),
              ),
            ],
          ),
        );
        if (selfConfirmed == true && mounted) {
          Navigator.pop(context, true);
        }
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
            // הודעת הרתעה
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.red[50],
                border: Border.all(color: Colors.red.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.visibility, color: Colors.red[700], size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'יציאה מהאפליקציה במהלך ניווט תירשם במערכת',
                      style: TextStyle(
                        color: Colors.red[800],
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

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
              title: 'לחץ 3 פעמים על כפתור הצד',
              description: 'יפתח תפריט Guided Access',
            ),

            _buildStep(
              number: '2',
              title: 'בחר Guided Access',
              description: 'אם לא מופיע — הפעל בהגדרות: Settings → Accessibility → Guided Access',
            ),

            _buildStep(
              number: '3',
              title: 'לחץ Start',
              description: 'Guided Access יופעל והאפליקציה תינעל',
            ),

            _buildStep(
              number: '4',
              title: 'חזור לאפליקציה ולחץ "אישור"',
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
