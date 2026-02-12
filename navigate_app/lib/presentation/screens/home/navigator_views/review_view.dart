import 'package:flutter/material.dart';
import '../../../../domain/entities/navigation.dart' as domain;
import '../../../../domain/entities/user.dart';

/// תצוגת תחקיר למנווט — מפה + ציונים
class ReviewView extends StatelessWidget {
  final domain.Navigation navigation;
  final User currentUser;

  const ReviewView({
    super.key,
    required this.navigation,
    required this.currentUser,
  });

  @override
  Widget build(BuildContext context) {
    final route = navigation.routes[currentUser.uid];
    final showScores = navigation.reviewSettings.showScoresAfterApproval;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'תחקיר ניווט',
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
          const SizedBox(height: 16),

          // מקרא
          Row(
            children: [
              _legendItem(Colors.blue, 'מסלול מתוכנן'),
              const SizedBox(width: 24),
              _legendItem(Colors.green, 'מסלול בפועל'),
            ],
          ),
          const SizedBox(height: 16),

          // ייצוא GPX
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
          const SizedBox(height: 24),

          // ציונים
          if (showScores) ...[
            Text(
              'ציונים',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            _buildScoreCard(context, route),
          ] else
            Card(
              color: Colors.grey[100],
              child: const ListTile(
                leading: Icon(Icons.visibility_off),
                title: Text('ציונים אינם מוצגים'),
                subtitle: Text('המפקד בחר שלא להציג ציונים בתחקיר'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildScoreCard(BuildContext context, domain.AssignedRoute? route) {
    // TODO: fetch real scores from NavigationRepository.fetchScoresFromFirestore
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.score, color: Colors.amber),
                const SizedBox(width: 8),
                Text(
                  'ציון סופי: --',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (route != null) ...[
              Text('נקודות בציר: ${route.checkpointIds.length}'),
              Text('אורך ציר: ${route.routeLengthKm.toStringAsFixed(2)} ק"מ'),
            ],
            const SizedBox(height: 8),
            Text(
              'ציונים מפורטים — בפיתוח',
              style: TextStyle(color: Colors.grey[500]),
            ),
          ],
        ),
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
}
