import 'package:flutter/material.dart';
import '../../../../domain/entities/navigation.dart' as domain;
import '../../../../domain/entities/user.dart';

/// תצוגת אישרור למנווט — מפה עם מסלולים מתוכננים ובפועל
class ApprovalView extends StatelessWidget {
  final domain.Navigation navigation;
  final User currentUser;

  const ApprovalView({
    super.key,
    required this.navigation,
    required this.currentUser,
  });

  @override
  Widget build(BuildContext context) {
    final route = navigation.routes[currentUser.uid];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'אישרור ניווט',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            navigation.name,
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),

          // Placeholder למפה
          Container(
            height: 250,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.map, size: 48, color: Colors.grey[400]),
                  const SizedBox(height: 8),
                  Text(
                    'מפת מסלול — בפיתוח',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // מקרא
          Row(
            children: [
              _legendItem(Colors.blue, 'מסלול מתוכנן'),
              const SizedBox(width: 24),
              _legendItem(Colors.green, 'מסלול בפועל'),
            ],
          ),
          const SizedBox(height: 24),

          // סטטיסטיקות
          if (route != null) ...[
            _statCard(context, 'נקודות בציר', '${route.checkpointIds.length}'),
            _statCard(context, 'אורך מתוכנן', '${route.routeLengthKm.toStringAsFixed(2)} ק"מ'),
            _statCard(context, 'סטטוס ציר', route.status),
          ],

          const SizedBox(height: 24),

          // GPX export
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('ייצוא GPX — בפיתוח')),
                );
              },
              icon: const Icon(Icons.download),
              label: const Text('ייצוא GPX'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 4,
          color: color,
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 13)),
      ],
    );
  }

  Widget _statCard(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
