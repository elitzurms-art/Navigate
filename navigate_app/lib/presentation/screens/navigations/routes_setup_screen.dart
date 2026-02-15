import 'package:flutter/material.dart';
import '../../../domain/entities/navigation.dart' as domain;
import 'routes_manual_upload_screen.dart';
import 'routes_automatic_setup_screen.dart';
import 'routes_manual_app_screen.dart';

/// שלב 2 - בחירת שיטת יצירת צירים
class RoutesSetupScreen extends StatelessWidget {
  final domain.Navigation navigation;

  const RoutesSetupScreen({super.key, required this.navigation});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('יצירת טבלת צירים'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // כותרת
            Text(
              'בחר שיטת יצירת צירים',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'ניווט: ${navigation.name}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),

            // אופציה 1 - טעינה ידנית מקובץ Excel
            _buildOptionCard(
              context,
              title: 'טעינה ידנית מקובץ Excel',
              description: 'טען קובץ Excel עם חלוקת נקודות מוכנה.\n'
                  'המערכת תוודא שכל המנווטים והנקודות תקינים.',
              icon: Icons.upload_file,
              color: Colors.blue,
              onTap: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => RoutesManualUploadScreen(navigation: navigation),
                  ),
                );
                if (result == true && context.mounted) {
                  Navigator.pop(context, true);
                }
              },
            ),

            const SizedBox(height: 16),

            // אופציה 2 - חלוקה אוטומטית
            _buildOptionCard(
              context,
              title: 'חלוקה אוטומטית',
              description: 'המערכת תחלק את הנקודות באופן אוטומטי\n'
                  'לפי ההגדרות והקריטריונים שתבחר.',
              icon: Icons.auto_fix_high,
              color: Colors.green,
              onTap: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => RoutesAutomaticSetupScreen(navigation: navigation),
                  ),
                );
                if (result == true && context.mounted) {
                  Navigator.pop(context, true);
                }
              },
            ),

            const SizedBox(height: 16),

            // אופציה 3 - חלוקה ידנית באפליקציה
            _buildOptionCard(
              context,
              title: 'חלוקה ידנית באפליקציה',
              description: 'בחר ידנית נקודות ציון לכל מנווט,\n'
                  'סדר את הסדר וצפה בתצוגה מקדימה על מפה.',
              icon: Icons.touch_app,
              color: Colors.orange,
              onTap: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => RoutesManualAppScreen(navigation: navigation),
                  ),
                );
                if (result == true && context.mounted) {
                  Navigator.pop(context, true);
                }
              },
            ),

            const SizedBox(height: 16),

            // הסבר על השלבים הבאים
            Card(
              color: Colors.grey[100],
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.grey[700]),
                        const SizedBox(width: 8),
                        Text(
                          'השלבים הבאים:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildStepRow('1', 'יצירת/טעינת טבלת צירים', isActive: true),
                    _buildStepRow('2', 'וידוא צירים'),
                    _buildStepRow('3', 'שינויים (אופציונלי)'),
                    _buildStepRow('4', 'סיום הכנות ושמירה'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionCard(
    BuildContext context, {
    required String title,
    required String description,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withOpacity(0.3), width: 2),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 40, color: color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
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
              Icon(Icons.arrow_forward_ios, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepRow(String number, String text, {bool isActive = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: isActive ? Colors.blue : Colors.grey[300],
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: TextStyle(
                  color: isActive ? Colors.white : Colors.grey[600],
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              color: isActive ? Colors.black87 : Colors.grey[600],
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
