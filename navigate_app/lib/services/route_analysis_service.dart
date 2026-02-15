import 'dart:math';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../domain/entities/navigation.dart';
import '../domain/entities/nav_layer.dart';
import '../domain/entities/checkpoint_punch.dart';
import '../domain/entities/coordinate.dart';
import '../core/utils/geometry_utils.dart';
import 'gps_tracking_service.dart';

// ============================================================
// Data classes
// ============================================================

/// קטע סטייה מהציר המתוכנן
class DeviationSegment {
  final int startIndex;
  final int endIndex;
  final double maxDeviation;
  final double avgDeviation;
  final LatLng worstPoint;
  final Duration duration;

  const DeviationSegment({
    required this.startIndex,
    required this.endIndex,
    required this.maxDeviation,
    required this.avgDeviation,
    required this.worstPoint,
    required this.duration,
  });
}

/// תוצאת ניתוח דקירת נ"צ
class CheckpointTimingResult {
  final String checkpointId;
  final String checkpointName;
  final String label;
  final DateTime? expectedTime;
  final DateTime? actualTime;
  final Duration? timeDifference;
  final double? distanceFromPrevious;
  final double? punchDistance;
  final bool wasPunched;
  final PunchStatus? punchStatus;

  const CheckpointTimingResult({
    required this.checkpointId,
    required this.checkpointName,
    required this.label,
    this.expectedTime,
    this.actualTime,
    this.timeDifference,
    this.distanceFromPrevious,
    this.punchDistance,
    required this.wasPunched,
    this.punchStatus,
  });
}

/// סטטיסטיקות מסלול כוללות
class RouteStatistics {
  final double plannedDistanceKm;
  final double actualDistanceKm;
  final double distanceDifferenceKm;
  final double distanceDifferencePercent;
  final Duration totalDuration;
  final double avgSpeedKmh;
  final double maxSpeedKmh;
  final double minSpeedKmh;
  final int totalCheckpoints;
  final int checkpointsPunched;
  final int checkpointsApproved;
  final int checkpointsRejected;
  final int checkpointsMissed;
  final double avgPunchDistance;
  final int deviationCount;
  final double maxDeviation;
  final double totalDeviationDistance;
  final Duration totalDeviationTime;
  final List<SpeedSegment> speedProfile;

  const RouteStatistics({
    required this.plannedDistanceKm,
    required this.actualDistanceKm,
    required this.distanceDifferenceKm,
    required this.distanceDifferencePercent,
    required this.totalDuration,
    required this.avgSpeedKmh,
    required this.maxSpeedKmh,
    required this.minSpeedKmh,
    required this.totalCheckpoints,
    required this.checkpointsPunched,
    required this.checkpointsApproved,
    required this.checkpointsRejected,
    required this.checkpointsMissed,
    required this.avgPunchDistance,
    required this.deviationCount,
    required this.maxDeviation,
    required this.totalDeviationDistance,
    required this.totalDeviationTime,
    required this.speedProfile,
  });
}

/// קטע מהירות (לתרשים)
class SpeedSegment {
  final DateTime timestamp;
  final double speedKmh;
  final LatLng position;
  final double distanceFromStartKm;

  const SpeedSegment({
    required this.timestamp,
    required this.speedKmh,
    required this.position,
    required this.distanceFromStartKm,
  });
}

/// תוצאת השוואת מנווטים
class NavigatorComparison {
  final String navigatorId;
  final String navigatorName;
  final RouteStatistics statistics;
  final List<CheckpointTimingResult> checkpointTimings;
  final List<DeviationSegment> deviations;
  final double overallScore;

  const NavigatorComparison({
    required this.navigatorId,
    required this.navigatorName,
    required this.statistics,
    required this.checkpointTimings,
    required this.deviations,
    required this.overallScore,
  });
}

/// נתוני מנווט לצורך השוואה
class NavigatorComparisonInput {
  final String navigatorId;
  final String navigatorName;
  final List<TrackPoint> trackPoints;
  final List<NavCheckpoint> checkpoints;
  final List<CheckpointPunch> punches;

  const NavigatorComparisonInput({
    required this.navigatorId,
    required this.navigatorName,
    required this.trackPoints,
    required this.checkpoints,
    required this.punches,
  });
}

// ============================================================
// Service
// ============================================================

/// שירות ניתוח מסלולים — סטיות, תזמוני נ"צ וסטטיסטיקות
class RouteAnalysisService {
  // ----------------------------------------------------------
  // Deviation analysis
  // ----------------------------------------------------------

  List<DeviationSegment> analyzeDeviations({
    required List<LatLng> plannedRoute,
    required List<TrackPoint> actualTrack,
    double thresholdMeters = 100.0,
  }) {
    if (plannedRoute.length < 2 || actualTrack.isEmpty) return [];

    final segments = <DeviationSegment>[];

    int? deviationStart;
    double maxDev = 0;
    double sumDev = 0;
    int devCount = 0;
    LatLng? worstPt;

    for (int i = 0; i < actualTrack.length; i++) {
      final point = LatLng(
        actualTrack[i].coordinate.lat,
        actualTrack[i].coordinate.lng,
      );
      final dist = _distanceToPolyline(point, plannedRoute);

      if (dist > thresholdMeters) {
        if (deviationStart == null) {
          deviationStart = i;
          maxDev = dist;
          sumDev = dist;
          devCount = 1;
          worstPt = point;
        } else {
          sumDev += dist;
          devCount++;
          if (dist > maxDev) {
            maxDev = dist;
            worstPt = point;
          }
        }
      } else {
        if (deviationStart != null) {
          segments.add(_buildDeviationSegment(
            startIndex: deviationStart,
            endIndex: i - 1,
            maxDeviation: maxDev,
            sumDeviation: sumDev,
            devCount: devCount,
            worstPoint: worstPt!,
            trackPoints: actualTrack,
          ));
          deviationStart = null;
          maxDev = 0;
          sumDev = 0;
          devCount = 0;
          worstPt = null;
        }
      }
    }

    if (deviationStart != null) {
      segments.add(_buildDeviationSegment(
        startIndex: deviationStart,
        endIndex: actualTrack.length - 1,
        maxDeviation: maxDev,
        sumDeviation: sumDev,
        devCount: devCount,
        worstPoint: worstPt!,
        trackPoints: actualTrack,
      ));
    }

    return segments;
  }

  DeviationSegment _buildDeviationSegment({
    required int startIndex,
    required int endIndex,
    required double maxDeviation,
    required double sumDeviation,
    required int devCount,
    required LatLng worstPoint,
    required List<TrackPoint> trackPoints,
  }) {
    final duration = trackPoints[endIndex].timestamp
        .difference(trackPoints[startIndex].timestamp);

    return DeviationSegment(
      startIndex: startIndex,
      endIndex: endIndex,
      maxDeviation: maxDeviation,
      avgDeviation: devCount > 0 ? sumDeviation / devCount : 0,
      worstPoint: worstPoint,
      duration: duration.isNegative ? Duration.zero : duration,
    );
  }

  // ----------------------------------------------------------
  // Checkpoint timing analysis
  // ----------------------------------------------------------

  List<CheckpointTimingResult> analyzeCheckpointTiming({
    required List<NavCheckpoint> checkpoints,
    required List<CheckpointPunch> punches,
    required List<TrackPoint> trackPoints,
    required AssignedRoute route,
  }) {
    if (checkpoints.isEmpty) return [];

    final orderedCheckpoints = _orderCheckpoints(checkpoints, route);
    final avgSpeedKmh = _averageSpeedFromTrack(trackPoints);
    final DateTime? startTime = _resolveStartTime(trackPoints, punches);

    final results = <CheckpointTimingResult>[];
    double cumulativeDistanceKm = 0;

    for (int idx = 0; idx < orderedCheckpoints.length; idx++) {
      final cp = orderedCheckpoints[idx];
      final label = _buildLabel(idx + 1, cp.type, orderedCheckpoints.length);

      double? segmentDistKm;
      if (idx > 0) {
        final prevCp = orderedCheckpoints[idx - 1];
        segmentDistKm = _checkpointDistanceKm(prevCp, cp);
        if (segmentDistKm != null) {
          cumulativeDistanceKm += segmentDistKm;
        }
      }

      DateTime? expectedTime;
      if (startTime != null && avgSpeedKmh > 0 && cumulativeDistanceKm > 0) {
        final hoursNeeded = cumulativeDistanceKm / avgSpeedKmh;
        final secondsNeeded = (hoursNeeded * 3600).round();
        expectedTime = startTime.add(Duration(seconds: secondsNeeded));
      }

      final punch = _findBestPunch(cp.id, punches);

      final actualTime = punch?.punchTime;
      Duration? timeDiff;
      if (expectedTime != null && actualTime != null) {
        timeDiff = actualTime.difference(expectedTime);
      }

      results.add(CheckpointTimingResult(
        checkpointId: cp.id,
        checkpointName: cp.name,
        label: label,
        expectedTime: expectedTime,
        actualTime: actualTime,
        timeDifference: timeDiff,
        distanceFromPrevious: segmentDistKm,
        punchDistance: punch?.distanceFromCheckpoint,
        wasPunched: punch != null && !punch.isDeleted,
        punchStatus: punch?.status,
      ));
    }

    return results;
  }

  // ----------------------------------------------------------
  // Route statistics
  // ----------------------------------------------------------

  RouteStatistics calculateStatistics({
    required List<TrackPoint> trackPoints,
    required List<NavCheckpoint> checkpoints,
    required List<CheckpointPunch> punches,
    required AssignedRoute route,
    List<LatLng>? plannedRoute,
  }) {
    final plannedDistKm = route.routeLengthKm;
    final actualDistKm = _calculateTotalDistanceKm(trackPoints);
    final diffKm = actualDistKm - plannedDistKm;
    final diffPct = plannedDistKm > 0 ? (diffKm / plannedDistKm) * 100 : 0.0;

    final totalDuration = trackPoints.length >= 2
        ? trackPoints.last.timestamp.difference(trackPoints.first.timestamp)
        : Duration.zero;

    final speedProfile = calculateSpeedProfile(trackPoints: trackPoints);
    final speeds = speedProfile.map((s) => s.speedKmh).where((s) => s > 0).toList();
    final avgSpeed = speeds.isNotEmpty
        ? speeds.reduce((a, b) => a + b) / speeds.length
        : 0.0;
    final maxSpeed = speeds.isNotEmpty
        ? speeds.reduce((a, b) => a > b ? a : b)
        : 0.0;
    final minSpeed = speeds.isNotEmpty
        ? speeds.reduce((a, b) => a < b ? a : b)
        : 0.0;

    final routeCheckpointIds = route.checkpointIds.toSet();
    final relevantCheckpoints = checkpoints
        .where((cp) =>
            routeCheckpointIds.contains(cp.id) ||
            routeCheckpointIds.contains(cp.sourceId))
        .toList();

    final totalCp = relevantCheckpoints.length;

    final punchedIds = <String>{};
    final approvedIds = <String>{};
    final rejectedIds = <String>{};
    double punchDistSum = 0;
    int punchDistCount = 0;

    for (final p in punches) {
      if (p.isDeleted) continue;
      punchedIds.add(p.checkpointId);
      if (p.isApproved) approvedIds.add(p.checkpointId);
      if (p.isRejected) rejectedIds.add(p.checkpointId);
      if (p.distanceFromCheckpoint != null) {
        punchDistSum += p.distanceFromCheckpoint!;
        punchDistCount++;
      }
    }

    final cpPunched = punchedIds.length;
    final cpApproved = approvedIds.length;
    final cpRejected = rejectedIds.length;
    final cpMissed = totalCp - cpPunched;
    final avgPunchDist = punchDistCount > 0 ? punchDistSum / punchDistCount : 0.0;

    List<DeviationSegment> deviations = [];
    if (plannedRoute != null && plannedRoute.length >= 2) {
      deviations = analyzeDeviations(
        plannedRoute: plannedRoute,
        actualTrack: trackPoints,
      );
    }

    final devCount = deviations.length;
    final maxDev = deviations.isNotEmpty
        ? deviations.map((d) => d.maxDeviation).reduce((a, b) => a > b ? a : b)
        : 0.0;

    double totalDevDistKm = 0;
    Duration totalDevTime = Duration.zero;
    for (final seg in deviations) {
      totalDevDistKm += _segmentDistanceKm(trackPoints, seg.startIndex, seg.endIndex);
      totalDevTime += seg.duration;
    }

    return RouteStatistics(
      plannedDistanceKm: plannedDistKm,
      actualDistanceKm: actualDistKm,
      distanceDifferenceKm: diffKm,
      distanceDifferencePercent: diffPct,
      totalDuration: totalDuration.isNegative ? Duration.zero : totalDuration,
      avgSpeedKmh: avgSpeed,
      maxSpeedKmh: maxSpeed,
      minSpeedKmh: minSpeed,
      totalCheckpoints: totalCp,
      checkpointsPunched: cpPunched,
      checkpointsApproved: cpApproved,
      checkpointsRejected: cpRejected,
      checkpointsMissed: cpMissed < 0 ? 0 : cpMissed,
      avgPunchDistance: avgPunchDist,
      deviationCount: devCount,
      maxDeviation: maxDev,
      totalDeviationDistance: totalDevDistKm,
      totalDeviationTime: totalDevTime,
      speedProfile: speedProfile,
    );
  }

  // ----------------------------------------------------------
  // Speed profile
  // ----------------------------------------------------------

  List<SpeedSegment> calculateSpeedProfile({
    required List<TrackPoint> trackPoints,
    int smoothingWindowSize = 3,
  }) {
    if (trackPoints.length < 2) return [];

    final rawSpeeds = <_RawSpeed>[];
    double cumulativeDist = 0;

    for (int i = 1; i < trackPoints.length; i++) {
      final prev = trackPoints[i - 1];
      final curr = trackPoints[i];

      final distMeters = _distanceBetween(
        LatLng(prev.coordinate.lat, prev.coordinate.lng),
        LatLng(curr.coordinate.lat, curr.coordinate.lng),
      );
      final dtSeconds =
          curr.timestamp.difference(prev.timestamp).inMilliseconds / 1000.0;

      double speedKmh = 0;
      if (dtSeconds > 0) {
        speedKmh = (distMeters / dtSeconds) * 3.6;
      }

      cumulativeDist += distMeters;

      rawSpeeds.add(_RawSpeed(
        timestamp: curr.timestamp,
        speedKmh: speedKmh,
        position: LatLng(curr.coordinate.lat, curr.coordinate.lng),
        cumulativeDistKm: cumulativeDist / 1000.0,
      ));
    }

    if (rawSpeeds.isEmpty) return [];

    final windowHalf = (smoothingWindowSize - 1) ~/ 2;
    final smoothed = <SpeedSegment>[];

    for (int i = 0; i < rawSpeeds.length; i++) {
      final lo = (i - windowHalf).clamp(0, rawSpeeds.length - 1);
      final hi = (i + windowHalf).clamp(0, rawSpeeds.length - 1);

      double sum = 0;
      int count = 0;
      for (int j = lo; j <= hi; j++) {
        sum += rawSpeeds[j].speedKmh;
        count++;
      }

      smoothed.add(SpeedSegment(
        timestamp: rawSpeeds[i].timestamp,
        speedKmh: count > 0 ? sum / count : 0,
        position: rawSpeeds[i].position,
        distanceFromStartKm: rawSpeeds[i].cumulativeDistKm,
      ));
    }

    return smoothed;
  }

  // ----------------------------------------------------------
  // Navigator comparison
  // ----------------------------------------------------------

  List<NavigatorComparison> compareNavigators({
    required Navigation navigation,
    required List<NavigatorComparisonInput> navigatorData,
  }) {
    if (navigatorData.isEmpty) return [];

    final comparisons = <NavigatorComparison>[];

    for (final data in navigatorData) {
      final route = navigation.routes[data.navigatorId];
      if (route == null) continue;

      final plannedRoute =
          route.plannedPath.map((c) => LatLng(c.lat, c.lng)).toList();

      final stats = calculateStatistics(
        trackPoints: data.trackPoints,
        checkpoints: data.checkpoints,
        punches: data.punches,
        route: route,
        plannedRoute: plannedRoute.length >= 2 ? plannedRoute : null,
      );

      final timings = analyzeCheckpointTiming(
        checkpoints: data.checkpoints,
        punches: data.punches,
        trackPoints: data.trackPoints,
        route: route,
      );

      final deviations = plannedRoute.length >= 2
          ? analyzeDeviations(
              plannedRoute: plannedRoute,
              actualTrack: data.trackPoints,
            )
          : <DeviationSegment>[];

      final score = _calculateOverallScore(stats, timings);

      comparisons.add(NavigatorComparison(
        navigatorId: data.navigatorId,
        navigatorName: data.navigatorName,
        statistics: stats,
        checkpointTimings: timings,
        deviations: deviations,
        overallScore: score,
      ));
    }

    comparisons.sort((a, b) => b.overallScore.compareTo(a.overallScore));

    return comparisons;
  }

  // ----------------------------------------------------------
  // Deviation color
  // ----------------------------------------------------------

  Color getDeviationColor(double deviationMeters, {double threshold = 100.0}) {
    if (deviationMeters <= threshold * 0.5) {
      return const Color(0xFF4CAF50);
    } else if (deviationMeters <= threshold) {
      return const Color(0xFFFFC107);
    } else if (deviationMeters <= threshold * 2) {
      return const Color(0xFFFF9800);
    } else {
      return const Color(0xFFF44336);
    }
  }

  // ============================================================
  // Private helpers
  // ============================================================

  double _distanceBetween(LatLng a, LatLng b) {
    const earthRadius = 6371000.0;
    final dLat = _toRadians(b.latitude - a.latitude);
    final dLon = _toRadians(b.longitude - a.longitude);
    final a1 = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(a.latitude)) *
            cos(_toRadians(b.latitude)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a1), sqrt(1 - a1));
    return earthRadius * c;
  }

  static double _toRadians(double degrees) => degrees * pi / 180;

  double _distanceToPolyline(LatLng point, List<LatLng> polyline) {
    if (polyline.isEmpty) return double.infinity;
    if (polyline.length == 1) return _distanceBetween(point, polyline.first);

    double minDist = double.infinity;
    for (int i = 0; i < polyline.length - 1; i++) {
      final dist = _distanceToSegment(point, polyline[i], polyline[i + 1]);
      if (dist < minDist) minDist = dist;
    }
    return minDist;
  }

  double _distanceToSegment(LatLng point, LatLng segA, LatLng segB) {
    final coordP =
        Coordinate(lat: point.latitude, lng: point.longitude, utm: '');
    final coordA =
        Coordinate(lat: segA.latitude, lng: segA.longitude, utm: '');
    final coordB =
        Coordinate(lat: segB.latitude, lng: segB.longitude, utm: '');
    return GeometryUtils.distanceFromPointToSegmentMeters(coordP, coordA, coordB);
  }

  double _calculateTotalDistanceKm(List<TrackPoint> points) {
    if (points.length < 2) return 0;

    double totalMeters = 0;
    for (int i = 0; i < points.length - 1; i++) {
      totalMeters += _distanceBetween(
        LatLng(points[i].coordinate.lat, points[i].coordinate.lng),
        LatLng(points[i + 1].coordinate.lat, points[i + 1].coordinate.lng),
      );
    }
    return totalMeters / 1000.0;
  }

  double _segmentDistanceKm(
      List<TrackPoint> points, int startIndex, int endIndex) {
    if (startIndex >= endIndex ||
        startIndex < 0 ||
        endIndex >= points.length) {
      return 0;
    }
    double totalMeters = 0;
    for (int i = startIndex; i < endIndex; i++) {
      totalMeters += _distanceBetween(
        LatLng(points[i].coordinate.lat, points[i].coordinate.lng),
        LatLng(points[i + 1].coordinate.lat, points[i + 1].coordinate.lng),
      );
    }
    return totalMeters / 1000.0;
  }

  double _averageSpeedFromTrack(List<TrackPoint> points) {
    if (points.length < 2) return 4.0;

    final distKm = _calculateTotalDistanceKm(points);
    final durSeconds =
        points.last.timestamp.difference(points.first.timestamp).inSeconds;

    if (durSeconds <= 0) return 4.0;
    final speed = distKm / (durSeconds / 3600.0);
    return speed > 0 ? speed : 4.0;
  }

  List<NavCheckpoint> _orderCheckpoints(
    List<NavCheckpoint> checkpoints,
    AssignedRoute route,
  ) {
    if (route.sequence.isEmpty) {
      final sorted = List<NavCheckpoint>.from(checkpoints);
      sorted.sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));
      return sorted;
    }

    final byId = <String, NavCheckpoint>{};
    for (final cp in checkpoints) {
      byId[cp.id] = cp;
      byId[cp.sourceId] = cp;
    }

    final ordered = <NavCheckpoint>[];
    for (final seqId in route.sequence) {
      final cp = byId[seqId];
      if (cp != null && !ordered.contains(cp)) {
        ordered.add(cp);
      }
    }

    for (final cp in checkpoints) {
      if (!ordered.contains(cp)) {
        ordered.add(cp);
      }
    }

    return ordered;
  }

  String _buildLabel(int index, String type, int totalCount) {
    String letter;
    if (type == 'start') {
      letter = 'H';
    } else if (type == 'end') {
      letter = 'S';
    } else if (type == 'mandatory_passage') {
      letter = 'M';
    } else {
      letter = 'B';
    }
    return '$index$letter';
  }

  double? _checkpointDistanceKm(NavCheckpoint a, NavCheckpoint b) {
    final coordA = _checkpointCenter(a);
    final coordB = _checkpointCenter(b);
    if (coordA == null || coordB == null) return null;
    return GeometryUtils.distanceBetweenMeters(coordA, coordB) / 1000.0;
  }

  Coordinate? _checkpointCenter(NavCheckpoint cp) {
    if (cp.coordinates != null) return cp.coordinates;
    if (cp.isPolygon &&
        cp.polygonCoordinates != null &&
        cp.polygonCoordinates!.isNotEmpty) {
      return GeometryUtils.getPolygonCenter(cp.polygonCoordinates!);
    }
    return null;
  }

  DateTime? _resolveStartTime(
    List<TrackPoint> trackPoints,
    List<CheckpointPunch> punches,
  ) {
    DateTime? earliest;

    if (trackPoints.isNotEmpty) {
      earliest = trackPoints.first.timestamp;
    }

    for (final p in punches) {
      if (p.isDeleted) continue;
      if (earliest == null || p.punchTime.isBefore(earliest)) {
        earliest = p.punchTime;
      }
    }

    return earliest;
  }

  CheckpointPunch? _findBestPunch(
      String checkpointId, List<CheckpointPunch> punches) {
    final matching = punches
        .where((p) => p.checkpointId == checkpointId && !p.isDeleted)
        .toList();

    if (matching.isEmpty) return null;

    matching.sort((a, b) {
      final priorityA = _punchPriority(a.status);
      final priorityB = _punchPriority(b.status);
      if (priorityA != priorityB) return priorityA.compareTo(priorityB);
      return b.punchTime.compareTo(a.punchTime);
    });

    return matching.first;
  }

  int _punchPriority(PunchStatus status) {
    switch (status) {
      case PunchStatus.approved:
        return 0;
      case PunchStatus.active:
        return 1;
      case PunchStatus.rejected:
        return 2;
      case PunchStatus.deleted:
        return 3;
    }
  }

  double _calculateOverallScore(
    RouteStatistics stats,
    List<CheckpointTimingResult> timings,
  ) {
    double cpScore = 0;
    if (stats.totalCheckpoints > 0) {
      cpScore = (stats.checkpointsApproved / stats.totalCheckpoints) * 100;
    }

    double devScore = 100;
    if (stats.actualDistanceKm > 0) {
      final devRatio = stats.totalDeviationDistance / stats.actualDistanceKm;
      devScore = ((1 - devRatio) * 100).clamp(0, 100).toDouble();
    }

    double timeScore = 100;
    final punchedTimings =
        timings.where((t) => t.wasPunched && t.timeDifference != null).toList();
    if (punchedTimings.isNotEmpty) {
      final avgAbsDiff = punchedTimings
              .map((t) => t.timeDifference!.inSeconds.abs())
              .reduce((a, b) => a + b) /
          punchedTimings.length;
      timeScore = ((1 - avgAbsDiff / 1800) * 100).clamp(0, 100).toDouble();
    }

    return cpScore * 0.5 + devScore * 0.3 + timeScore * 0.2;
  }
}

class _RawSpeed {
  final DateTime timestamp;
  final double speedKmh;
  final LatLng position;
  final double cumulativeDistKm;

  const _RawSpeed({
    required this.timestamp,
    required this.speedKmh,
    required this.position,
    required this.cumulativeDistKm,
  });
}
