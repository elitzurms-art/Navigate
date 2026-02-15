import 'package:flutter/material.dart';
import '../../services/route_analysis_service.dart';
import '../../services/scoring_service.dart';

/// ווידג'ט השוואת מנווטים — כרטיסי השוואה מדורגים
class NavigatorComparisonWidget extends StatelessWidget {
  final List<NavigatorComparison> comparisons;
  final Map<String, Color> navigatorColors;

  const NavigatorComparisonWidget({
    super.key,
    required this.comparisons,
    this.navigatorColors = const {},
  });

  @override
  Widget build(BuildContext context) {
    if (comparisons.isEmpty) {
      return const Center(
        child: Text('אין נתונים להשוואה', style: TextStyle(color: Colors.grey)),
      );
    }

    // מיון לפי ציון (גבוה לנמוך)
    final sorted = List.of(comparisons)
      ..sort((a, b) => b.overallScore.compareTo(a.overallScore));

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: sorted.length,
      itemBuilder: (context, index) {
        final comp = sorted[index];
        final color = navigatorColors[comp.navigatorId] ?? Colors.blue;
        return _buildComparisonCard(context, comp, color, index + 1);
      },
    );
  }

  Widget _buildComparisonCard(
      BuildContext context, NavigatorComparison comp, Color color, int rank) {
    final scoreColor = ScoringService.getScoreColor(comp.overallScore.round());
    final stats = comp.statistics;

    // חישוב ציוני משנה מנתונים
    final checkpointPct = stats.totalCheckpoints > 0
        ? (stats.checkpointsPunched / stats.totalCheckpoints) * 100
        : 0.0;
    final deviationPct = stats.deviationCount == 0
        ? 100.0
        : (100.0 - (stats.maxDeviation / 10).clamp(0.0, 100.0));
    final avgDeviationM = stats.deviationCount > 0
        ? stats.totalDeviationDistance / stats.deviationCount
        : 0.0;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // כותרת
            Row(
              children: [
                // דירוג
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: rank <= 3 ? Colors.amber : Colors.grey[300],
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '$rank',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: rank <= 3 ? Colors.white : Colors.grey[600],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // צבע מנווט + שם
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    comp.navigatorName.isNotEmpty
                        ? comp.navigatorName
                        : comp.navigatorId.length > 4
                            ? '...${comp.navigatorId.substring(comp.navigatorId.length - 4)}'
                            : comp.navigatorId,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),

                // ציון כולל
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: scoreColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: scoreColor, width: 1.5),
                  ),
                  child: Text(
                    '${comp.overallScore.round()}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: scoreColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // סרגלי מדדים
            _buildMetricBar('נ.צ. שנדקרו',
                checkpointPct, Colors.green),
            const SizedBox(height: 6),
            _buildMetricBar('דיוק מסלול',
                deviationPct, Colors.blue),

            // פרטי מרחק
            const SizedBox(height: 8),
            Row(
              children: [
                _metricChip(
                  'מרחק',
                  '${stats.actualDistanceKm.toStringAsFixed(1)} ק"מ',
                  Icons.route,
                ),
                const SizedBox(width: 12),
                _metricChip(
                  'מהירות ממוצעת',
                  '${stats.avgSpeedKmh.toStringAsFixed(1)} קמ"ש',
                  Icons.speed,
                ),
                const SizedBox(width: 12),
                _metricChip(
                  'סטייה ממוצעת',
                  '${avgDeviationM.toStringAsFixed(0)} מ\'',
                  Icons.trending_up,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricBar(String label, double value, Color color) {
    final pct = value.clamp(0, 100);
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(label, style: const TextStyle(fontSize: 11)),
        ),
        Expanded(
          child: Stack(
            children: [
              Container(
                height: 8,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              FractionallySizedBox(
                widthFactor: pct / 100,
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 30,
          child: Text('${pct.round()}',
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.bold, color: color),
              textAlign: TextAlign.end),
        ),
      ],
    );
  }

  Widget _metricChip(String label, String value, IconData icon) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey[500]),
          const SizedBox(height: 2),
          Text(value,
              style:
                  const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          Text(label,
              style: TextStyle(fontSize: 9, color: Colors.grey[500])),
        ],
      ),
    );
  }
}
