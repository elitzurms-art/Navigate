import 'package:flutter/material.dart';

void main() {
  runApp(const NavigateAppSimple());
}

class NavigateAppSimple extends StatelessWidget {
  const NavigateAppSimple({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Navigate App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.blue,
              Colors.blue.shade300,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo
                  const Icon(
                    Icons.navigation,
                    size: 100,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 24),

                  // Title
                  const Text(
                    'Navigate',
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'מערכת ניהול ניווטים ותחקור',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.white70,
                    ),
                    textDirection: TextDirection.rtl,
                  ),
                  const SizedBox(height: 60),

                  // Info Card
                  Card(
                    elevation: 8,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.check_circle,
                            size: 64,
                            color: Colors.green,
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            '🎉 האפליקציה עובדת!',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                            textDirection: TextDirection.rtl,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Flutter מותקן וקוד עובד בהצלחה',
                            textAlign: TextAlign.center,
                            textDirection: TextDirection.rtl,
                          ),
                          const SizedBox(height: 24),
                          const Divider(),
                          const SizedBox(height: 16),
                          InfoRow(icon: Icons.check, text: 'Flutter SDK: מותקן'),
                          InfoRow(icon: Icons.check, text: 'Dependencies: 162 packages'),
                          InfoRow(icon: Icons.check, text: 'קבצים: 28 נוצרו'),
                          InfoRow(icon: Icons.check, text: 'Build: הצליח'),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 40),

                  // Version
                  const Text(
                    'גרסה 1.0.0 - Demo',
                    style: TextStyle(
                      color: Colors.white70,
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
}

class InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const InfoRow({
    super.key,
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.green),
          const SizedBox(width: 12),
          Text(
            text,
            style: const TextStyle(fontSize: 14),
          ),
        ],
      ),
    );
  }
}
