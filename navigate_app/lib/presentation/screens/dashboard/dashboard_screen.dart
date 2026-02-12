import 'package:flutter/material.dart';

/// מסך לוח בקרה
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('לוח בקרה'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          children: [
            _buildDashboardCard(
              context,
              icon: Icons.navigation,
              title: 'ניווטים פעילים',
              count: '0',
              color: Colors.blue,
            ),
            _buildDashboardCard(
              context,
              icon: Icons.check_circle,
              title: 'ממתינים לאישור',
              count: '0',
              color: Colors.orange,
            ),
            _buildDashboardCard(
              context,
              icon: Icons.map,
              title: 'אזורים',
              count: '0',
              color: Colors.green,
            ),
            _buildDashboardCard(
              context,
              icon: Icons.people,
              title: 'משתמשים',
              count: '0',
              color: Colors.purple,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String count,
    required Color color,
  }) {
    return Card(
      elevation: 4,
      child: InkWell(
        onTap: () {},
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 48, color: color),
              const SizedBox(height: 12),
              Text(
                count,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
