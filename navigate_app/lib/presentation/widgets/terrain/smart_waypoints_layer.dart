import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../../services/terrain/terrain_models.dart';

/// שכבת נקודות ציון חכמות — סמנים צבעוניים עם tooltip על המפה.
/// כל סמן מציג את סוג נקודת הציון, הגובה והבולטות.
class SmartWaypointsLayer extends StatelessWidget {
  /// רשימת נקודות ציון חכמות להצגה
  final List<SmartWaypoint> waypoints;

  /// callback בלחיצה על נקודת ציון
  final ValueChanged<SmartWaypoint>? onWaypointTap;

  const SmartWaypointsLayer({
    super.key,
    required this.waypoints,
    this.onWaypointTap,
  });

  @override
  Widget build(BuildContext context) {
    if (waypoints.isEmpty) {
      return const SizedBox.shrink();
    }

    return MarkerLayer(
      markers: waypoints.map((waypoint) {
        return Marker(
          point: waypoint.position,
          width: 30,
          height: 30,
          child: Tooltip(
            // תיאור בעברית: סוג, גובה ובולטות
            message:
                '${waypoint.type.hebrewLabel}\n'
                'גובה: ${waypoint.elevation}מ\n'
                'בולטות: ${waypoint.prominence.toStringAsFixed(1)}מ',
            child: GestureDetector(
              onTap:
                  onWaypointTap != null
                      ? () => onWaypointTap!(waypoint)
                      : null,
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: waypoint.type.color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Icon(
                  waypoint.type.icon,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
