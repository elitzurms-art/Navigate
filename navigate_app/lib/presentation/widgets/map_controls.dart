import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/map_config.dart';
import '../../core/utils/geometry_utils.dart';
import '../../domain/entities/coordinate.dart';

/// הגדרת שכבה בודדת עבור פאנל השכבות
class MapLayerConfig {
  final String id;
  final String label;
  final Color color;
  final bool visible;
  final double? opacity;
  final ValueChanged<bool> onVisibilityChanged;
  final ValueChanged<double>? onOpacityChanged;

  const MapLayerConfig({
    required this.id,
    required this.label,
    required this.color,
    required this.visible,
    this.opacity,
    required this.onVisibilityChanged,
    this.onOpacityChanged,
  });
}

/// בקרי מפה משותפים — סוג מפה, מדידה, שכבות, חץ צפון
class MapControls extends StatefulWidget {
  final MapController mapController;
  final List<MapLayerConfig> layers;
  final bool measureMode;
  final ValueChanged<bool> onMeasureModeChanged;
  final List<LatLng> measurePoints;
  final VoidCallback? onMeasureClear;
  final VoidCallback? onMeasureUndo;

  const MapControls({
    required this.mapController,
    required this.onMeasureModeChanged,
    super.key,
    this.layers = const [],
    this.measureMode = false,
    this.measurePoints = const [],
    this.onMeasureClear,
    this.onMeasureUndo,
  });

  @override
  State<MapControls> createState() => _MapControlsState();

  /// שכבות מדידה — קו צהוב + נקודות — לשימוש ע"י המסך המכיל
  /// מחזיר רשימת widgets שיש להכניס כ-layers ב-FlutterMap
  static List<Widget> buildMeasureLayers(List<LatLng> points) {
    if (points.isEmpty) return [];

    final widgets = <Widget>[];

    // קו מדידה צהוב
    if (points.length >= 2) {
      widgets.add(
        PolylineLayer(
          polylines: [
            Polyline(
              points: points,
              color: Colors.amber,
              strokeWidth: 3.0,
            ),
          ],
        ),
      );
    }

    // נקודות מדידה צהובות
    widgets.add(
      MarkerLayer(
        markers: points
            .map(
              (p) => Marker(
                point: p,
                width: 14,
                height: 14,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.amber,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.amber[800]!, width: 1.5),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );

    return widgets;
  }
}

class _MapControlsState extends State<MapControls> {
  bool _showLayersPanel = false;
  double _currentRotation = 0.0;
  StreamSubscription? _mapEventSubscription;

  @override
  void initState() {
    super.initState();
    // האזנה לאירועי מפה לעדכון סיבוב חץ הצפון
    _mapEventSubscription = widget.mapController.mapEventStream.listen((event) {
      final rotation = widget.mapController.camera.rotation;
      if (rotation != _currentRotation) {
        setState(() {
          _currentRotation = rotation;
        });
      }
    });
  }

  @override
  void dispose() {
    _mapEventSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // עמודה ימנית עליונה — סוג מפה, מדידה, שכבות
        Positioned(
          top: 8,
          right: 8,
          child: _buildRightColumn(),
        ),

        // חץ צפון — שמאלית עליונה
        Positioned(
          top: 8,
          left: 8,
          child: _buildNorthArrow(),
        ),

        // פאנל שכבות (מוצג מתחת לכפתורים)
        if (_showLayersPanel)
          Positioned(
            top: 8 + 44.0 * 3 + 12, // מתחת ל-3 כפתורים + רווח
            right: 8,
            child: _buildLayersPanel(),
          ),

        // סרגל מדידה תחתון
        if (widget.measureMode && widget.measurePoints.isNotEmpty)
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: _buildMeasurementBar(),
          ),
      ],
    );
  }

  /// עמודה ימנית — 3 כפתורים אנכיים
  Widget _buildRightColumn() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildMapTypeButton(),
        const SizedBox(height: 4),
        _buildMeasureButton(),
        if (widget.layers.isNotEmpty) ...[
          const SizedBox(height: 4),
          _buildLayersButton(),
        ],
      ],
    );
  }

  /// כפתור בחירת סוג מפה — popup menu
  Widget _buildMapTypeButton() {
    final config = MapConfig();

    const icons = {
      MapType.standard: Icons.map_outlined,
      MapType.topographic: Icons.terrain,
      MapType.satellite: Icons.satellite_alt,
    };

    return ValueListenableBuilder<MapType>(
      valueListenable: config.typeNotifier,
      builder: (context, currentType, _) {
        return Material(
          color: Colors.white,
          elevation: 2,
          borderRadius: BorderRadius.circular(8),
          child: PopupMenuButton<MapType>(
            icon: Icon(icons[currentType], color: Colors.grey[700], size: 22),
            tooltip: 'סוג מפה',
            onSelected: (type) => config.setType(type),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            itemBuilder: (_) => MapType.values.map((type) {
              final selected = type == currentType;
              return PopupMenuItem<MapType>(
                value: type,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icons[type],
                      color: selected
                          ? Theme.of(context).primaryColor
                          : Colors.grey[600],
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        config.label(type),
                        style: TextStyle(
                          fontWeight:
                              selected ? FontWeight.bold : FontWeight.normal,
                          color:
                              selected ? Theme.of(context).primaryColor : null,
                        ),
                      ),
                    ),
                    if (selected)
                      Icon(Icons.check,
                          color: Theme.of(context).primaryColor, size: 18),
                  ],
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  /// כפתור מדידה — toggle
  Widget _buildMeasureButton() {
    final isActive = widget.measureMode;
    return Material(
      color: isActive ? Colors.amber[100] : Colors.white,
      elevation: 2,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          widget.onMeasureModeChanged(!isActive);
        },
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(
            Icons.straighten,
            color: isActive ? Colors.amber[800] : Colors.grey[700],
            size: 22,
          ),
        ),
      ),
    );
  }

  /// כפתור שכבות — toggle פאנל
  Widget _buildLayersButton() {
    return Material(
      color: _showLayersPanel ? Colors.blue[50] : Colors.white,
      elevation: 2,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          setState(() {
            _showLayersPanel = !_showLayersPanel;
          });
        },
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(
            Icons.layers,
            color: _showLayersPanel ? Colors.blue[700] : Colors.grey[700],
            size: 22,
          ),
        ),
      ),
    );
  }

  /// חץ צפון — מסתובב עם המפה, לחיצה מאפסת סיבוב
  Widget _buildNorthArrow() {
    // הסיבוב בדיוק הפוך — כשמפה מסובבת 30 מעלות, החץ מסתובב -30
    final rotationRadians = -_currentRotation * pi / 180;

    return Material(
      color: Colors.white,
      elevation: 2,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          widget.mapController.rotate(0);
        },
        child: SizedBox(
          width: 40,
          height: 40,
          child: Transform.rotate(
            angle: rotationRadians,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'N',
                  style: TextStyle(
                    color: Colors.red[700],
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    height: 1.0,
                  ),
                ),
                Icon(
                  Icons.navigation,
                  color: Colors.red[700],
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// פאנל שכבות — toggles + opacity sliders
  Widget _buildLayersPanel() {
    if (widget.layers.isEmpty) {
      return const SizedBox.shrink();
    }

    return Material(
      color: Colors.white,
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 220,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.layers, color: Colors.grey[700], size: 18),
                const SizedBox(width: 6),
                const Text(
                  'שכבות',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const Spacer(),
                InkWell(
                  onTap: () {
                    setState(() {
                      _showLayersPanel = false;
                    });
                  },
                  child:
                      Icon(Icons.close, size: 18, color: Colors.grey[500]),
                ),
              ],
            ),
            const Divider(height: 12),
            ...widget.layers.map(_buildLayerRow),
          ],
        ),
      ),
    );
  }

  /// שורת שכבה בודדת — toggle + slider + נקודת צבע
  Widget _buildLayerRow(MapLayerConfig layer) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // נקודת צבע
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: layer.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              // תווית
              Expanded(
                child: Text(
                  layer.label,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              // toggle
              SizedBox(
                height: 28,
                child: Switch(
                  value: layer.visible,
                  onChanged: layer.onVisibilityChanged,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          // opacity slider — רק כשהשכבה מופעלת ויש תמיכה בשקיפות
          if (layer.visible && layer.opacity != null && layer.onOpacityChanged != null)
            SizedBox(
              height: 28,
              child: Row(
                children: [
                  const SizedBox(width: 18),
                  Icon(Icons.opacity, size: 14, color: Colors.grey[500]),
                  Expanded(
                    child: SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 2,
                        thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6),
                        overlayShape:
                            const RoundSliderOverlayShape(overlayRadius: 12),
                        activeTrackColor: layer.color.withValues(alpha: 0.7),
                        thumbColor: layer.color,
                      ),
                      child: Slider(
                        value: layer.opacity!,
                        min: 0.1,
                        max: 1.0,
                        onChanged: layer.onOpacityChanged,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 32,
                    child: Text(
                      '${(layer.opacity! * 100).round()}%',
                      style:
                          TextStyle(fontSize: 10, color: Colors.grey[600]),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// סרגל מדידה תחתון — מקטע אחרון + כולל
  Widget _buildMeasurementBar() {
    final points = widget.measurePoints;
    if (points.isEmpty) return const SizedBox.shrink();

    // חישוב מקטע אחרון
    String lastSegmentText = '';
    if (points.length >= 2) {
      final from = Coordinate(
        lat: points[points.length - 2].latitude,
        lng: points[points.length - 2].longitude,
        utm: '',
      );
      final to = Coordinate(
        lat: points.last.latitude,
        lng: points.last.longitude,
        utm: '',
      );
      final distance = GeometryUtils.distanceBetweenMeters(from, to);
      final bearing = GeometryUtils.bearingBetween(from, to);
      lastSegmentText =
          'מקטע אחרון: ${bearing.round()}° / ${distance.round()}מ\'';
    } else {
      lastSegmentText = 'נקודה ראשונה סומנה';
    }

    // חישוב אורך כולל
    String totalText = '';
    if (points.length >= 2) {
      final coords = points
          .map((p) => Coordinate(lat: p.latitude, lng: p.longitude, utm: ''))
          .toList();
      final totalKm = GeometryUtils.calculatePathLengthKm(coords);
      final totalMeters = (totalKm * 1000).round();
      totalText = ' | כולל: ${totalMeters}מ\'';
    }

    return Material(
      color: Colors.amber[50],
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.straighten, color: Colors.amber[800], size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$lastSegmentText$totalText',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[800],
                  fontWeight: FontWeight.w500,
                ),
                textDirection: TextDirection.rtl,
              ),
            ),
            if (widget.onMeasureUndo != null && points.length >= 2)
              InkWell(
                onTap: widget.onMeasureUndo,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.undo, size: 18, color: Colors.grey[700]),
                ),
              ),
            if (widget.onMeasureClear != null && points.isNotEmpty) ...[
              const SizedBox(width: 4),
              InkWell(
                onTap: widget.onMeasureClear,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child:
                      Icon(Icons.delete_outline, size: 18, color: Colors.red[400]),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
