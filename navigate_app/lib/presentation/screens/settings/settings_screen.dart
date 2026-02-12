import 'package:flutter/material.dart';
import 'offline_maps_screen.dart';

/// מסך הגדרות
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('הגדרות'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        children: [
          const SizedBox(height: 10),
          _buildSettingsSection(
            context,
            title: 'כללי',
            items: [
              _buildSettingsItem(
                context,
                icon: Icons.language,
                title: 'שפה',
                subtitle: 'עברית',
              ),
              _buildSettingsItem(
                context,
                icon: Icons.palette,
                title: 'ערכת נושא',
                subtitle: 'בהיר',
              ),
            ],
          ),
          _buildSettingsSection(
            context,
            title: 'מפה',
            items: [
              _buildSettingsItem(
                context,
                icon: Icons.map,
                title: 'שירות מפות',
                subtitle: 'OpenStreetMap',
              ),
              _buildSettingsItem(
                context,
                icon: Icons.offline_bolt,
                title: 'מפות אופליין',
                subtitle: 'ניהול מפות שמורות',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const OfflineMapsScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
          _buildSettingsSection(
            context,
            title: 'אודות',
            items: [
              _buildSettingsItem(
                context,
                icon: Icons.info,
                title: 'גרסה',
                subtitle: '1.0.0',
              ),
              _buildSettingsItem(
                context,
                icon: Icons.description,
                title: 'תנאי שימוש',
                subtitle: '',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsSection(
    BuildContext context, {
    required String title,
    required List<Widget> items,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).primaryColor,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
        ...items,
        const Divider(),
      ],
    );
  }

  Widget _buildSettingsItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle.isNotEmpty ? Text(subtitle) : null,
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: onTap,
    );
  }
}
