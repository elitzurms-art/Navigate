import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/material.dart';
import '../core/utils/file_export_helper.dart';
import '../domain/entities/coordinate.dart';
import '../domain/entities/navigation.dart' as domain;
import '../domain/entities/nav_layer.dart';
import '../domain/entities/checkpoint_punch.dart';
import '../domain/entities/navigation_score.dart';
import '../data/repositories/nav_layer_repository.dart';
import '../data/repositories/navigation_track_repository.dart';
import '../data/repositories/checkpoint_punch_repository.dart';
import '../data/repositories/navigation_repository.dart';
import '../presentation/widgets/export_format_picker.dart';
import 'gps_tracking_service.dart';

/// פורמט ייצוא
enum ExportFormat { gpx, kml, geojson, csv }

/// נתוני ייצוא
class ExportData {
  final String navigationName;
  final String navigatorName;
  final List<TrackPoint> trackPoints;
  final List<NavCheckpoint> checkpoints;
  final List<CheckpointPunch> punches;
  final List<Coordinate>? plannedPath;
  final DateTime? startTime;
  final DateTime? endTime;

  const ExportData({
    required this.navigationName,
    required this.navigatorName,
    required this.trackPoints,
    required this.checkpoints,
    required this.punches,
    this.plannedPath,
    this.startTime,
    this.endTime,
  });
}

/// שירות ייצוא מסלולים — GPX, KML, GeoJSON, CSV
class RouteExportService {
  // ---------------------------------------------------------------------------
  // GPX
  // ---------------------------------------------------------------------------

  Future<String?> exportGPX({
    required String navigationName,
    required String navigatorName,
    required List<TrackPoint> trackPoints,
    required List<NavCheckpoint> checkpoints,
    required List<CheckpointPunch> punches,
    List<Coordinate>? plannedPath,
    DateTime? startTime,
    DateTime? endTime,
  }) async {
    final content = _buildGPX(
      navigationName: navigationName,
      navigatorName: navigatorName,
      trackPoints: trackPoints,
      checkpoints: checkpoints,
      punches: punches,
      plannedPath: plannedPath,
      startTime: startTime,
      endTime: endTime,
    );

    final fileName = _sanitizeFileName('${navigationName}_$navigatorName.gpx');
    return saveFileWithBytes(
      dialogTitle: 'ייצוא GPX',
      fileName: fileName,
      bytes: Uint8List.fromList(utf8.encode(content)),
      allowedExtensions: ['gpx'],
    );
  }

  String _buildGPX({
    required String navigationName,
    required String navigatorName,
    required List<TrackPoint> trackPoints,
    required List<NavCheckpoint> checkpoints,
    required List<CheckpointPunch> punches,
    List<Coordinate>? plannedPath,
    DateTime? startTime,
    DateTime? endTime,
  }) {
    final buf = StringBuffer();
    buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buf.writeln('<gpx version="1.1" creator="Navigate App"');
    buf.writeln('     xmlns="http://www.topografix.com/GPX/1/1">');

    // Metadata
    buf.writeln('  <metadata>');
    buf.writeln('    <name>${_xmlEscape('$navigationName - $navigatorName')}</name>');
    final metaTime = startTime ??
        (trackPoints.isNotEmpty
            ? trackPoints.first.timestamp
            : DateTime.now());
    buf.writeln('    <time>${metaTime.toUtc().toIso8601String()}</time>');
    buf.writeln('  </metadata>');

    // Planned route track
    if (plannedPath != null && plannedPath.isNotEmpty) {
      buf.writeln('  <trk>');
      buf.writeln('    <name>מסלול מתוכנן</name>');
      buf.writeln('    <type>planned</type>');
      buf.writeln('    <trkseg>');
      for (final coord in plannedPath) {
        buf.writeln(
            '      <trkpt lat="${coord.lat}" lon="${coord.lng}">');
        buf.writeln('      </trkpt>');
      }
      buf.writeln('    </trkseg>');
      buf.writeln('  </trk>');
    }

    // Actual GPS track
    if (trackPoints.isNotEmpty) {
      buf.writeln('  <trk>');
      buf.writeln('    <name>מסלול בפועל</name>');
      buf.writeln('    <type>actual</type>');
      buf.writeln('    <trkseg>');
      for (final pt in trackPoints) {
        buf.writeln(
            '      <trkpt lat="${pt.coordinate.lat}" lon="${pt.coordinate.lng}">');
        if (pt.altitude != null) {
          buf.writeln('        <ele>${pt.altitude}</ele>');
        }
        buf.writeln(
            '        <time>${pt.timestamp.toUtc().toIso8601String()}</time>');
        buf.writeln('        <extensions>');
        buf.writeln('          <accuracy>${pt.accuracy}</accuracy>');
        if (pt.speed != null) {
          buf.writeln('          <speed>${pt.speed}</speed>');
        }
        if (pt.heading != null) {
          buf.writeln('          <heading>${pt.heading}</heading>');
        }
        buf.writeln(
            '          <source>${_xmlEscape(pt.positionSource)}</source>');
        buf.writeln('        </extensions>');
        buf.writeln('      </trkpt>');
      }
      buf.writeln('    </trkseg>');
      buf.writeln('  </trk>');
    }

    // Checkpoints as waypoints
    for (final cp in checkpoints) {
      final coord = cp.coordinates;
      if (coord == null) continue;
      final label = cp.labels.isNotEmpty ? cp.labels.first : '';
      final displayName =
          label.isNotEmpty ? '$label - ${cp.name}' : cp.name;
      buf.writeln(
          '  <wpt lat="${coord.lat}" lon="${coord.lng}">');
      buf.writeln('    <name>${_xmlEscape(displayName)}</name>');
      buf.writeln('    <type>${_xmlEscape(cp.type)}</type>');
      buf.writeln('  </wpt>');
    }

    // Punches as waypoints
    for (final punch in punches) {
      final cp = _findCheckpoint(checkpoints, punch.checkpointId);
      final cpName = cp != null ? cp.name : punch.checkpointId;
      buf.writeln(
          '  <wpt lat="${punch.punchLocation.lat}" lon="${punch.punchLocation.lng}">');
      buf.writeln(
          '    <name>${_xmlEscape('דקירה - $cpName')}</name>');
      buf.writeln('    <type>punch</type>');
      buf.writeln(
          '    <time>${punch.punchTime.toUtc().toIso8601String()}</time>');
      buf.writeln('  </wpt>');
    }

    buf.writeln('</gpx>');
    return buf.toString();
  }

  // ---------------------------------------------------------------------------
  // KML
  // ---------------------------------------------------------------------------

  Future<String?> exportKML({
    required String navigationName,
    required String navigatorName,
    required List<TrackPoint> trackPoints,
    required List<NavCheckpoint> checkpoints,
    required List<CheckpointPunch> punches,
    List<Coordinate>? plannedPath,
    DateTime? startTime,
    DateTime? endTime,
  }) async {
    final content = _buildKML(
      navigationName: navigationName,
      navigatorName: navigatorName,
      trackPoints: trackPoints,
      checkpoints: checkpoints,
      punches: punches,
      plannedPath: plannedPath,
      startTime: startTime,
      endTime: endTime,
    );

    final fileName = _sanitizeFileName('${navigationName}_$navigatorName.kml');
    return saveFileWithBytes(
      dialogTitle: 'ייצוא KML',
      fileName: fileName,
      bytes: Uint8List.fromList(utf8.encode(content)),
      allowedExtensions: ['kml'],
    );
  }

  String _buildKML({
    required String navigationName,
    required String navigatorName,
    required List<TrackPoint> trackPoints,
    required List<NavCheckpoint> checkpoints,
    required List<CheckpointPunch> punches,
    List<Coordinate>? plannedPath,
    DateTime? startTime,
    DateTime? endTime,
  }) {
    final buf = StringBuffer();
    buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buf.writeln('<kml xmlns="http://www.opengis.net/kml/2.2">');
    buf.writeln('  <Document>');
    buf.writeln(
        '    <name>${_xmlEscape('$navigationName - $navigatorName')}</name>');

    // Styles — KML uses AABBGGRR colour format
    buf.writeln('    <Style id="planned">');
    buf.writeln(
        '      <LineStyle><color>ff3636f4</color><width>4</width></LineStyle>');
    buf.writeln('    </Style>');
    buf.writeln('    <Style id="actual">');
    buf.writeln(
        '      <LineStyle><color>fff39621</color><width>3</width></LineStyle>');
    buf.writeln('    </Style>');
    buf.writeln('    <Style id="start">');
    buf.writeln(
        '      <IconStyle><color>ff50af4c</color></IconStyle>');
    buf.writeln('    </Style>');
    buf.writeln('    <Style id="end">');
    buf.writeln(
        '      <IconStyle><color>ff3636f4</color></IconStyle>');
    buf.writeln('    </Style>');
    buf.writeln('    <Style id="checkpoint">');
    buf.writeln(
        '      <IconStyle><color>ff07c1ff</color></IconStyle>');
    buf.writeln('    </Style>');
    buf.writeln('    <Style id="mandatory_passage">');
    buf.writeln(
        '      <IconStyle><color>ff0098ff</color></IconStyle>');
    buf.writeln('    </Style>');
    buf.writeln('    <Style id="punch">');
    buf.writeln(
        '      <IconStyle><color>ff00ff80</color></IconStyle>');
    buf.writeln('    </Style>');

    // Planned route
    if (plannedPath != null && plannedPath.isNotEmpty) {
      buf.writeln('    <Placemark>');
      buf.writeln('      <name>מסלול מתוכנן</name>');
      buf.writeln('      <styleUrl>#planned</styleUrl>');
      buf.writeln('      <LineString>');
      buf.writeln('        <coordinates>');
      final coords =
          plannedPath.map((c) => '${c.lng},${c.lat},0').join(' ');
      buf.writeln('          $coords');
      buf.writeln('        </coordinates>');
      buf.writeln('      </LineString>');
      buf.writeln('    </Placemark>');
    }

    // Actual route
    if (trackPoints.isNotEmpty) {
      buf.writeln('    <Placemark>');
      buf.writeln('      <name>מסלול בפועל</name>');
      buf.writeln('      <styleUrl>#actual</styleUrl>');
      buf.writeln('      <LineString>');
      buf.writeln('        <coordinates>');
      final coords = trackPoints.map((pt) {
        final alt = pt.altitude ?? 0;
        return '${pt.coordinate.lng},${pt.coordinate.lat},$alt';
      }).join(' ');
      buf.writeln('          $coords');
      buf.writeln('        </coordinates>');
      buf.writeln('      </LineString>');
      buf.writeln('    </Placemark>');
    }

    // Checkpoint placemarks
    for (final cp in checkpoints) {
      final coord = cp.coordinates;
      if (coord == null) continue;
      final label = cp.labels.isNotEmpty ? cp.labels.first : '';
      final displayName =
          label.isNotEmpty ? '$label - ${cp.name}' : cp.name;
      final styleId = _kmlStyleForType(cp.type);
      buf.writeln('    <Placemark>');
      buf.writeln(
          '      <name>${_xmlEscape(displayName)}</name>');
      buf.writeln('      <styleUrl>#$styleId</styleUrl>');
      buf.writeln(
          '      <Point><coordinates>${coord.lng},${coord.lat},0</coordinates></Point>');
      buf.writeln('    </Placemark>');
    }

    // Punch placemarks
    for (final punch in punches) {
      final cp = _findCheckpoint(checkpoints, punch.checkpointId);
      final cpName = cp != null ? cp.name : punch.checkpointId;
      buf.writeln('    <Placemark>');
      buf.writeln(
          '      <name>${_xmlEscape('דקירה - $cpName')}</name>');
      buf.writeln('      <styleUrl>#punch</styleUrl>');
      buf.writeln(
          '      <Point><coordinates>${punch.punchLocation.lng},${punch.punchLocation.lat},0</coordinates></Point>');
      buf.writeln('    </Placemark>');
    }

    buf.writeln('  </Document>');
    buf.writeln('</kml>');
    return buf.toString();
  }

  String _kmlStyleForType(String type) {
    switch (type) {
      case 'start':
        return 'start';
      case 'end':
        return 'end';
      case 'mandatory_passage':
        return 'mandatory_passage';
      default:
        return 'checkpoint';
    }
  }

  // ---------------------------------------------------------------------------
  // GeoJSON
  // ---------------------------------------------------------------------------

  Future<String?> exportGeoJSON({
    required String navigationName,
    required String navigatorName,
    required List<TrackPoint> trackPoints,
    required List<NavCheckpoint> checkpoints,
    required List<CheckpointPunch> punches,
    List<Coordinate>? plannedPath,
    DateTime? startTime,
    DateTime? endTime,
  }) async {
    final content = _buildGeoJSON(
      navigationName: navigationName,
      navigatorName: navigatorName,
      trackPoints: trackPoints,
      checkpoints: checkpoints,
      punches: punches,
      plannedPath: plannedPath,
      startTime: startTime,
      endTime: endTime,
    );

    final fileName =
        _sanitizeFileName('${navigationName}_$navigatorName.geojson');
    return saveFileWithBytes(
      dialogTitle: 'ייצוא GeoJSON',
      fileName: fileName,
      bytes: Uint8List.fromList(utf8.encode(content)),
      allowedExtensions: ['geojson', 'json'],
    );
  }

  String _buildGeoJSON({
    required String navigationName,
    required String navigatorName,
    required List<TrackPoint> trackPoints,
    required List<NavCheckpoint> checkpoints,
    required List<CheckpointPunch> punches,
    List<Coordinate>? plannedPath,
    DateTime? startTime,
    DateTime? endTime,
  }) {
    final features = <Map<String, dynamic>>[];

    // Planned route
    if (plannedPath != null && plannedPath.isNotEmpty) {
      features.add({
        'type': 'Feature',
        'properties': {
          'name': 'מסלול מתוכנן',
          'type': 'planned',
          'stroke': '#F44336',
          'stroke-width': 4,
          'navigationName': navigationName,
          'navigatorName': navigatorName,
        },
        'geometry': {
          'type': 'LineString',
          'coordinates':
              plannedPath.map((c) => [c.lng, c.lat]).toList(),
        },
      });
    }

    // Actual GPS track
    if (trackPoints.isNotEmpty) {
      features.add({
        'type': 'Feature',
        'properties': {
          'name': 'מסלול בפועל',
          'type': 'actual',
          'stroke': '#2196F3',
          'stroke-width': 3,
          'navigationName': navigationName,
          'navigatorName': navigatorName,
          if (startTime != null)
            'startTime': startTime.toUtc().toIso8601String(),
          if (endTime != null)
            'endTime': endTime.toUtc().toIso8601String(),
          'pointCount': trackPoints.length,
        },
        'geometry': {
          'type': 'LineString',
          'coordinates': trackPoints.map((pt) {
            final alt = pt.altitude ?? 0;
            return [pt.coordinate.lng, pt.coordinate.lat, alt];
          }).toList(),
        },
      });
    }

    // Checkpoints
    for (final cp in checkpoints) {
      final coord = cp.coordinates;
      if (coord == null) continue;
      final label = cp.labels.isNotEmpty ? cp.labels.first : '';
      final displayName =
          label.isNotEmpty ? '$label - ${cp.name}' : cp.name;
      features.add({
        'type': 'Feature',
        'properties': {
          'name': displayName,
          'type': cp.type,
          'marker-color': _geojsonColorForType(cp.type),
          'sequenceNumber': cp.sequenceNumber,
          if (cp.description.isNotEmpty) 'description': cp.description,
        },
        'geometry': {
          'type': 'Point',
          'coordinates': [coord.lng, coord.lat],
        },
      });
    }

    // Punches
    for (final punch in punches) {
      final cp = _findCheckpoint(checkpoints, punch.checkpointId);
      final cpName = cp != null ? cp.name : punch.checkpointId;
      features.add({
        'type': 'Feature',
        'properties': {
          'name': 'דקירה - $cpName',
          'type': 'punch',
          'marker-color': '#FF9800',
          'punchTime': punch.punchTime.toUtc().toIso8601String(),
          'status': punch.status.code,
          if (punch.distanceFromCheckpoint != null)
            'distanceFromCheckpoint': punch.distanceFromCheckpoint,
        },
        'geometry': {
          'type': 'Point',
          'coordinates': [
            punch.punchLocation.lng,
            punch.punchLocation.lat,
          ],
        },
      });
    }

    final featureCollection = {
      'type': 'FeatureCollection',
      'features': features,
    };

    return const JsonEncoder.withIndent('  ').convert(featureCollection);
  }

  String _geojsonColorForType(String type) {
    switch (type) {
      case 'start':
        return '#4CAF50';
      case 'end':
        return '#2196F3';
      case 'mandatory_passage':
        return '#FF9800';
      default:
        return '#FFEB3B';
    }
  }

  // ---------------------------------------------------------------------------
  // CSV
  // ---------------------------------------------------------------------------

  Future<String?> exportCSV({
    required String navigationName,
    required String navigatorName,
    required List<TrackPoint> trackPoints,
    required List<NavCheckpoint> checkpoints,
    required List<CheckpointPunch> punches,
    List<Coordinate>? plannedPath,
    DateTime? startTime,
    DateTime? endTime,
  }) async {
    // Track points CSV
    final trackCsv = _buildTrackPointsCsv(trackPoints);
    final trackFileName =
        _sanitizeFileName('${navigationName}_${navigatorName}_track.csv');
    final trackPath = await saveFileWithBytes(
      dialogTitle: 'ייצוא נקודות מסלול (CSV)',
      fileName: trackFileName,
      bytes: Uint8List.fromList(utf8.encode(trackCsv)),
      allowedExtensions: ['csv'],
    );

    if (trackPath == null) return null;

    // Checkpoints CSV
    final cpCsv = _buildCheckpointsCsv(checkpoints, punches);
    final cpFileName = _sanitizeFileName(
        '${navigationName}_${navigatorName}_checkpoints.csv');
    await saveFileWithBytes(
      dialogTitle: 'ייצוא נקודות ציון (CSV)',
      fileName: cpFileName,
      bytes: Uint8List.fromList(utf8.encode(cpCsv)),
      allowedExtensions: ['csv'],
    );

    return trackPath;
  }

  String _buildTrackPointsCsv(List<TrackPoint> trackPoints) {
    final buf = StringBuffer();
    // BOM for Excel Hebrew support
    buf.write('\uFEFF');
    buf.writeln(
        'timestamp,lat,lng,utm,altitude,speed,heading,accuracy,source');

    for (final pt in trackPoints) {
      buf.writeln(
        '${pt.timestamp.toUtc().toIso8601String()},'
        '${pt.coordinate.lat},'
        '${pt.coordinate.lng},'
        '${_csvEscape(pt.coordinate.utm)},'
        '${pt.altitude ?? ''},'
        '${pt.speed ?? ''},'
        '${pt.heading ?? ''},'
        '${pt.accuracy},'
        '${_csvEscape(pt.positionSource)}',
      );
    }

    return buf.toString();
  }

  String _buildCheckpointsCsv(
    List<NavCheckpoint> checkpoints,
    List<CheckpointPunch> punches,
  ) {
    final buf = StringBuffer();
    buf.write('\uFEFF');
    buf.writeln(
        'number,label,name,type,lat,lng,utm,punch_time,punch_distance_m,punch_status');

    for (final cp in checkpoints) {
      final coord = cp.coordinates;
      final label = cp.labels.isNotEmpty ? cp.labels.first : '';

      final punch = punches.cast<CheckpointPunch?>().firstWhere(
            (p) => p!.checkpointId == cp.id,
            orElse: () => null,
          );

      buf.writeln(
        '${cp.sequenceNumber},'
        '${_csvEscape(label)},'
        '${_csvEscape(cp.name)},'
        '${_csvEscape(cp.type)},'
        '${coord?.lat ?? ''},'
        '${coord?.lng ?? ''},'
        '${_csvEscape(coord?.utm ?? '')},'
        '${punch != null ? punch.punchTime.toUtc().toIso8601String() : ''},'
        '${punch?.distanceFromCheckpoint ?? ''},'
        '${punch != null ? punch.status.code : ''}',
      );
    }

    return buf.toString();
  }

  // ---------------------------------------------------------------------------
  // Export dialog
  // ---------------------------------------------------------------------------

  Future<void> showExportDialog(
    BuildContext context, {
    required ExportData data,
  }) async {
    final format = await showModalBottomSheet<ExportFormat>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const ExportFormatPicker(),
    );

    if (format == null) return;

    String? result;
    switch (format) {
      case ExportFormat.gpx:
        result = await exportGPX(
          navigationName: data.navigationName,
          navigatorName: data.navigatorName,
          trackPoints: data.trackPoints,
          checkpoints: data.checkpoints,
          punches: data.punches,
          plannedPath: data.plannedPath,
          startTime: data.startTime,
          endTime: data.endTime,
        );
        break;
      case ExportFormat.kml:
        result = await exportKML(
          navigationName: data.navigationName,
          navigatorName: data.navigatorName,
          trackPoints: data.trackPoints,
          checkpoints: data.checkpoints,
          punches: data.punches,
          plannedPath: data.plannedPath,
          startTime: data.startTime,
          endTime: data.endTime,
        );
        break;
      case ExportFormat.geojson:
        result = await exportGeoJSON(
          navigationName: data.navigationName,
          navigatorName: data.navigatorName,
          trackPoints: data.trackPoints,
          checkpoints: data.checkpoints,
          punches: data.punches,
          plannedPath: data.plannedPath,
          startTime: data.startTime,
          endTime: data.endTime,
        );
        break;
      case ExportFormat.csv:
        result = await exportCSV(
          navigationName: data.navigationName,
          navigatorName: data.navigatorName,
          trackPoints: data.trackPoints,
          checkpoints: data.checkpoints,
          punches: data.punches,
          plannedPath: data.plannedPath,
          startTime: data.startTime,
          endTime: data.endTime,
        );
        break;
    }

    if (!context.mounted) return;

    if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('הקובץ יוצא בהצלחה')),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Full Navigation Export (.nav.json)
  // ---------------------------------------------------------------------------

  /// ייצוא ניווט מלא לקובץ JSON — כולל כל הנתונים
  Future<String?> exportFullNavigation({
    required domain.Navigation navigation,
    Map<String, String>? navigatorNames,
  }) async {
    final navLayerRepo = NavLayerRepository();
    final trackRepo = NavigationTrackRepository();
    final punchRepo = CheckpointPunchRepository();
    final navRepo = NavigationRepository();

    // טעינת שכבות
    final checkpoints = await navLayerRepo.getCheckpointsByNavigation(navigation.id);
    final safetyPoints = await navLayerRepo.getSafetyPointsByNavigation(navigation.id);
    final boundaries = await navLayerRepo.getBoundariesByNavigation(navigation.id);

    // טעינת tracks לכל מנווט
    final tracks = <String, dynamic>{};
    for (final navId in navigation.routes.keys) {
      final track = await trackRepo.getByNavigatorAndNavigation(navId, navigation.id);
      if (track != null && track.trackPointsJson.isNotEmpty) {
        try {
          tracks[navId] = jsonDecode(track.trackPointsJson);
        } catch (_) {}
      }
    }

    // טעינת דקירות
    List<CheckpointPunch> punches = [];
    try {
      punches = await punchRepo.getByNavigationFromFirestore(navigation.id);
    } catch (_) {
      for (final navId in navigation.routes.keys) {
        final navPunches = await punchRepo.getByNavigator(navId);
        punches.addAll(
          navPunches.where((p) => p.navigationId == navigation.id),
        );
      }
    }

    // טעינת ציונים
    final scores = <String, dynamic>{};
    try {
      final scoresList = await navRepo.fetchScoresFromFirestore(navigation.id);
      for (final s in scoresList) {
        final navigatorId = s['navigatorId'] as String?;
        if (navigatorId != null) {
          scores[navigatorId] = s;
        }
      }
    } catch (_) {}

    // בניית JSON
    final exportData = {
      'version': 2,
      'exportedAt': DateTime.now().toIso8601String(),
      'navigation': navigation.toMap(),
      if (navigatorNames != null && navigatorNames.isNotEmpty)
        'navigatorNames': navigatorNames,
      'routes': navigation.routes.map((k, v) => MapEntry(k, v.toMap())),
      'tracks': tracks,
      'punches': punches.map((p) => p.toMap()).toList(),
      'scores': scores,
      'checkpoints': checkpoints.map((c) => {
        'id': c.id,
        'sourceId': c.sourceId,
        'name': c.name,
        'type': c.type,
        'sequenceNumber': c.sequenceNumber,
        'labels': c.labels,
        if (c.coordinates != null) 'coordinates': c.coordinates!.toMap(),
        if (c.description.isNotEmpty) 'description': c.description,
        'geometryType': c.geometryType,
        if (c.polygonCoordinates != null && c.polygonCoordinates!.isNotEmpty)
          'polygonCoordinates': c.polygonCoordinates!.map((co) => co.toMap()).toList(),
      }).toList(),
      'boundaries': boundaries.map((b) => {
        'id': b.id,
        'sourceId': b.sourceId,
        'name': b.name,
        'coordinates': b.coordinates.map((c) => c.toMap()).toList(),
      }).toList(),
      'safetyPoints': safetyPoints.map((s) => {
        'id': s.id,
        'sourceId': s.sourceId,
        'name': s.name,
        if (s.coordinates != null) 'coordinates': s.coordinates!.toMap(),
        if (s.polygonCoordinates != null && s.polygonCoordinates!.isNotEmpty)
          'polygonCoordinates': s.polygonCoordinates!.map((co) => co.toMap()).toList(),
      }).toList(),
    };

    final sanitized = _sanitizeForJson(exportData);
    final content = const JsonEncoder.withIndent('  ').convert(sanitized);
    final fileName = _sanitizeFileName('${navigation.name}.nav.json');

    return saveFileWithBytes(
      dialogTitle: 'שמירת ניווט',
      fileName: fileName,
      bytes: Uint8List.fromList(utf8.encode(content)),
      allowedExtensions: ['json'],
    );
  }

  // ---------------------------------------------------------------------------
  // Full Navigation Import (.nav.json)
  // ---------------------------------------------------------------------------

  /// ייבוא ניווט מלא מקובץ JSON
  Future<domain.Navigation?> importFullNavigation() async {
    final content = await pickAndReadFile(
      dialogTitle: 'ייבוא ניווט',
      allowedExtensions: ['json'],
    );

    if (content == null) return null;

    final Map<String, dynamic> data;
    try {
      data = jsonDecode(content) as Map<String, dynamic>;
    } catch (e) {
      throw Exception('הקובץ אינו JSON תקין');
    }

    // Validate version
    final version = data['version'] as int? ?? 0;
    if (version < 1 || version > 2) {
      throw Exception('גרסת קובץ לא נתמכת: $version');
    }

    // Validate required fields
    if (data['navigation'] == null) {
      throw Exception('הקובץ חסר נתוני ניווט');
    }

    // Reconstruct Navigation
    final navMap = data['navigation'] as Map<String, dynamic>;
    final navigation = domain.Navigation.fromMap(navMap);

    final navRepo = NavigationRepository();
    final navLayerRepo = NavLayerRepository();
    final trackRepo = NavigationTrackRepository();
    final punchRepo = CheckpointPunchRepository();

    // Check if navigation already exists — update or create
    final existing = await navRepo.getById(navigation.id);
    if (existing != null) {
      await navRepo.updateLocalFromFirestore(navigation);
    } else {
      try {
        await navRepo.create(navigation);
      } catch (_) {
        // If create fails (e.g. unique constraint), try update
        await navRepo.updateLocalFromFirestore(navigation);
      }
    }

    // Import checkpoints
    if (data['checkpoints'] != null) {
      final checkpointsList = (data['checkpoints'] as List)
          .map((m) {
            final cpMap = Map<String, dynamic>.from(m as Map);
            cpMap['navigationId'] = navigation.id;
            return cpMap;
          })
          .toList();

      // Delete existing layers first, then re-add
      try {
        await navLayerRepo.deleteAllLayersForNavigation(navigation.id);
      } catch (_) {}

      final checkpoints = <NavCheckpoint>[];
      for (final cpMap in checkpointsList) {
        try {
          checkpoints.add(NavCheckpoint.fromMap(cpMap));
        } catch (e) {
          print('DEBUG import: Skipping checkpoint: $e');
        }
      }
      if (checkpoints.isNotEmpty) {
        await navLayerRepo.addCheckpointsBatch(checkpoints);
      }
    }

    // Import safety points
    if (data['safetyPoints'] != null) {
      final spList = (data['safetyPoints'] as List)
          .map((m) {
            final spMap = Map<String, dynamic>.from(m as Map);
            spMap['navigationId'] = navigation.id;
            return spMap;
          })
          .toList();
      final safetyPoints = <NavSafetyPoint>[];
      for (final spMap in spList) {
        try {
          safetyPoints.add(NavSafetyPoint.fromMap(spMap));
        } catch (e) {
          print('DEBUG import: Skipping safety point: $e');
        }
      }
      if (safetyPoints.isNotEmpty) {
        await navLayerRepo.addSafetyPointsBatch(safetyPoints);
      }
    }

    // Import boundaries
    if (data['boundaries'] != null) {
      final bList = (data['boundaries'] as List)
          .map((m) {
            final bMap = Map<String, dynamic>.from(m as Map);
            bMap['navigationId'] = navigation.id;
            return bMap;
          })
          .toList();
      for (final bMap in bList) {
        try {
          await navLayerRepo.addBoundary(NavBoundary.fromMap(bMap));
        } catch (e) {
          print('DEBUG import: Skipping boundary: $e');
        }
      }
    }

    // Import tracks
    if (data['tracks'] != null) {
      final tracksMap = data['tracks'] as Map<String, dynamic>;
      for (final entry in tracksMap.entries) {
        final navigatorId = entry.key;
        try {
          // Check if track exists
          final existingTrack = await trackRepo.getByNavigatorAndNavigation(
              navigatorId, navigation.id);
          if (existingTrack != null) {
            final trackPoints = (entry.value as List)
                .map((m) => TrackPoint.fromMap(m as Map<String, dynamic>))
                .toList();
            await trackRepo.updateTrackPoints(existingTrack.id, trackPoints);
          } else {
            // Create new track
            final track = await trackRepo.startNavigation(
              navigatorUserId: navigatorId,
              navigationId: navigation.id,
            );
            final trackPoints = (entry.value as List)
                .map((m) => TrackPoint.fromMap(m as Map<String, dynamic>))
                .toList();
            await trackRepo.updateTrackPoints(track.id, trackPoints);
            await trackRepo.endNavigation(track.id);
          }
        } catch (e) {
          print('DEBUG import: Error importing track for $navigatorId: $e');
        }
      }
    }

    // Import punches
    if (data['punches'] != null) {
      final punchesList = data['punches'] as List;
      for (final pMap in punchesList) {
        try {
          final punch = CheckpointPunch.fromMap(
              Map<String, dynamic>.from(pMap as Map));
          await punchRepo.create(punch);
        } catch (e) {
          print('DEBUG import: Skipping punch: $e');
        }
      }
    }

    // Import scores
    if (data['scores'] != null) {
      final scoresMap = data['scores'] as Map<String, dynamic>;
      for (final entry in scoresMap.entries) {
        try {
          await navRepo.pushScore(
            navigationId: navigation.id,
            navigatorId: entry.key,
            scoreData: Map<String, dynamic>.from(entry.value as Map),
          );
        } catch (e) {
          print('DEBUG import: Error importing score for ${entry.key}: $e');
        }
      }
    }

    return navigation;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  NavCheckpoint? _findCheckpoint(
      List<NavCheckpoint> checkpoints, String id) {
    try {
      return checkpoints.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  String _xmlEscape(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  String _csvEscape(String input) {
    if (input.contains(',') ||
        input.contains('\n') ||
        input.contains('"')) {
      return '"${input.replaceAll('"', '""')}"';
    }
    return input;
  }

  String _sanitizeFileName(String name) {
    return name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  /// המרת Timestamp/DateTime ל-ISO string רקורסיבית — מניעת שגיאת jsonEncode
  dynamic _sanitizeForJson(dynamic value) {
    if (value is Timestamp) {
      return value.toDate().toIso8601String();
    } else if (value is DateTime) {
      return value.toIso8601String();
    } else if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), _sanitizeForJson(v)));
    } else if (value is List) {
      return value.map((item) => _sanitizeForJson(item)).toList();
    }
    return value;
  }
}
