import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home/home_screen.dart';
import 'training/training_navigations_screen.dart';
import 'training/learning_navigations_screen.dart';

/// מסך בחירת מצב ראשי לאפליקציה
class MainModeSelectionScreen extends StatelessWidget {
  const MainModeSelectionScreen({super.key});

  Future<void> _selectMode(BuildContext context, String mode) async {
    Widget targetScreen;
    String modeName = '';

    switch (mode) {
      case 'preparation':
        modeName = 'הכנות ולמידה';
        targetScreen = const HomeScreen();
        break;
      case 'training':
        modeName = 'אימון';
        targetScreen = const TrainingNavigationsScreen();
        break;
      case 'learning':
        modeName = 'למידה ותחקור';
        targetScreen = const LearningNavigationsScreen();
        break;
      default:
        targetScreen = const HomeScreen();
    }

    // שמירת מצב אפליקציה
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_mode', mode);

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => targetScreen),
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('נכנסת למצב: $modeName'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('בחר מצב עבודה'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).primaryColor.withOpacity(0.1),
              Colors.white,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // לוגו או כותרת
                  Icon(
                    Icons.navigation,
                    size: 80,
                    color: Theme.of(context).primaryColor,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'מערכת ניווט',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).primaryColor,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'בחר מצב עבודה',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.grey[600],
                        ),
                  ),
                  const SizedBox(height: 48),

                  // 1. הכנות ולמידה
                  _buildModeCard(
                    context,
                    mode: 'preparation',
                    title: 'הכנות ולמידה',
                    description: 'יצירת ניווטים, חלוקת צירים,\nהפעלת מצב למידה למנווטים',
                    icon: Icons.map,
                    color: const Color(0xFF2196F3), // כחול
                    gradient: [const Color(0xFF2196F3), const Color(0xFF1976D2)],
                    onTap: () => _selectMode(context, 'preparation'),
                  ),

                  const SizedBox(height: 20),

                  // 2. אימון
                  _buildModeCard(
                    context,
                    mode: 'training',
                    title: 'אימון',
                    description: 'אימוני מנווטים, תרגולים\nובדיקות כשירות',
                    icon: Icons.fitness_center,
                    color: const Color(0xFFFF9800), // כתום
                    gradient: [const Color(0xFFFF9800), const Color(0xFFF57C00)],
                    onTap: () => _selectMode(context, 'training'),
                  ),

                  const SizedBox(height: 20),

                  // 3. למידה ותחקור
                  _buildModeCard(
                    context,
                    mode: 'learning',
                    title: 'למידה ותחקור',
                    description: 'צפייה בניווטים קודמים,\nניתוח נתונים ולמידה',
                    icon: Icons.school,
                    color: const Color(0xFF4CAF50), // ירוק
                    gradient: [const Color(0xFF4CAF50), const Color(0xFF388E3C)],
                    onTap: () => _selectMode(context, 'learning'),
                  ),

                  const SizedBox(height: 32),

                  // כפתור יציאה
                  TextButton.icon(
                    onPressed: () {
                      // TODO: התנתקות
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.logout),
                    label: const Text('התנתק'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModeCard(
    BuildContext context, {
    required String mode,
    required String title,
    required String description,
    required IconData icon,
    required Color color,
    required List<Color> gradient,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                gradient[0].withOpacity(0.9),
                gradient[1],
              ],
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, size: 48, color: Colors.white),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withOpacity(0.9),
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.white,
                  size: 28,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
