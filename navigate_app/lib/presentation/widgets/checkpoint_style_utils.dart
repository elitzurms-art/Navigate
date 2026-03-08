import 'package:flutter/material.dart';
import '../../domain/entities/navigation.dart';

/// סגנון תצוגת נקודת ציון (צבע, אות, גבול)
class CheckpointStyle {
  final Color color;
  final String letter;
  final Color borderColor;
  final Color textColor;

  const CheckpointStyle(this.color, this.letter,
      {this.borderColor = Colors.white, this.textColor = Colors.white});
}

/// מחזיר סגנון נקודת ציון לפי תפקידה (התחלה/סיום/ביניים/החלפה/רגילה)
CheckpointStyle getCheckpointStyle({
  required String checkpointId,
  String? sourceId,
  required Set<String> swapIds,
  required Set<String> startIds,
  required Set<String> endIds,
  required Set<String> waypointIds,
}) {
  final isSwap = swapIds.contains(checkpointId) ||
      (sourceId != null && swapIds.contains(sourceId));
  final isStart = startIds.contains(checkpointId) ||
      (sourceId != null && startIds.contains(sourceId));
  final isEnd = endIds.contains(checkpointId) ||
      (sourceId != null && endIds.contains(sourceId));
  final isWaypoint = waypointIds.contains(checkpointId) ||
      (sourceId != null && waypointIds.contains(sourceId));

  if (isSwap) {
    return CheckpointStyle(Colors.white, 'S',
        borderColor: Colors.grey[700]!, textColor: Colors.grey[800]!);
  } else if (isStart) {
    return const CheckpointStyle(Color(0xFF4CAF50), 'H');
  } else if (isEnd) {
    return const CheckpointStyle(Color(0xFFF44336), 'F');
  } else if (isWaypoint) {
    return const CheckpointStyle(Color(0xFFFFC107), 'B');
  } else {
    return const CheckpointStyle(Colors.blue, '');
  }
}

/// איסוף מזהי נקודות לכל התפקידים מצירי הניווט + הגדרות ניווט
({Set<String> startIds, Set<String> endIds, Set<String> swapIds, Set<String> waypointIds})
collectCheckpointRoleIds(Navigation navigation) {
  final startIds = <String>{};
  final endIds = <String>{};
  final swapIds = <String>{};
  final waypointIds = <String>{};

  for (final route in navigation.routes.values) {
    if (route.startPointId != null) startIds.add(route.startPointId!);
    if (route.endPointId != null) endIds.add(route.endPointId!);
    if (route.swapPointId != null) swapIds.add(route.swapPointId!);
    waypointIds.addAll(route.waypointIds);
  }
  endIds.removeAll(swapIds);

  // fallback — הגדרות ניווט (לפני חלוקת צירים / אשכולות)
  if (navigation.startPoint != null) startIds.add(navigation.startPoint!);
  if (navigation.endPoint != null) endIds.add(navigation.endPoint!);
  if (navigation.waypointSettings.enabled) {
    for (final wp in navigation.waypointSettings.waypoints) {
      waypointIds.add(wp.checkpointId);
    }
  }

  return (startIds: startIds, endIds: endIds, swapIds: swapIds, waypointIds: waypointIds);
}

/// וריאנט לציר בודד (תצוגת מנווט) — ציר + fallback מהגדרות ניווט
({String? startId, String? endId, String? swapId, Set<String> waypointIds})
collectSingleRouteRoleIds(Navigation navigation, AssignedRoute? route) {
  final startId = route?.startPointId ?? navigation.startPoint;
  final endId = route?.endPointId ?? navigation.endPoint;
  final swapId = route?.swapPointId;
  final waypointIds = <String>{};
  if (route != null) waypointIds.addAll(route.waypointIds);
  if (navigation.waypointSettings.enabled) {
    for (final wp in navigation.waypointSettings.waypoints) {
      waypointIds.add(wp.checkpointId);
    }
  }
  return (startId: startId, endId: endId, swapId: swapId, waypointIds: waypointIds);
}
