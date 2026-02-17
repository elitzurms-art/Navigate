import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'map_with_selector.dart';
import 'map_controls.dart';

/// מסך מפה במסך מלא — תצוגת שכבות מהמסך המקורי עם כלי מדידה
class FullscreenMapScreen extends StatefulWidget {
  final String title;
  final List<Widget> layers;
  final List<MapLayerConfig> layerConfigs;
  final List<Widget> Function(Map<String, bool> visibility, Map<String, double> opacity)? layerBuilder;
  final LatLng initialCenter;
  final double initialZoom;
  final CameraFit? initialCameraFit;

  const FullscreenMapScreen({
    super.key,
    required this.title,
    this.layers = const [],
    this.layerConfigs = const [],
    this.layerBuilder,
    required this.initialCenter,
    this.initialZoom = 14.0,
    this.initialCameraFit,
  });

  @override
  State<FullscreenMapScreen> createState() => _FullscreenMapScreenState();
}

class _FullscreenMapScreenState extends State<FullscreenMapScreen> {
  final MapController _mapController = MapController();
  bool _measureMode = false;
  final List<LatLng> _measurePoints = [];
  final Map<String, bool> _visibility = {};
  final Map<String, double> _opacity = {};

  @override
  void initState() {
    super.initState();
    for (final config in widget.layerConfigs) {
      _visibility[config.id] = config.visible;
      if (config.opacity != null) {
        _opacity[config.id] = config.opacity!;
      }
    }
  }

  List<MapLayerConfig> _buildInternalConfigs() {
    return widget.layerConfigs.map((c) => MapLayerConfig(
      id: c.id,
      label: c.label,
      color: c.color,
      visible: _visibility[c.id] ?? c.visible,
      opacity: c.opacity != null ? (_opacity[c.id] ?? c.opacity!) : null,
      onVisibilityChanged: (v) => setState(() => _visibility[c.id] = v),
      onOpacityChanged: c.opacity != null
          ? (v) => setState(() => _opacity[c.id] = v)
          : null,
    )).toList();
  }

  @override
  Widget build(BuildContext context) {
    final effectiveLayers = widget.layerBuilder != null
        ? widget.layerBuilder!(_visibility, _opacity)
        : widget.layers;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          MapWithTypeSelector(
            mapController: _mapController,
            showTypeSelector: false,
            options: MapOptions(
              initialCenter: widget.initialCenter,
              initialZoom: widget.initialZoom,
              initialCameraFit: widget.initialCameraFit,
              onTap: (tapPosition, point) {
                if (_measureMode) {
                  setState(() => _measurePoints.add(point));
                }
              },
            ),
            layers: [
              ...effectiveLayers,
              ...MapControls.buildMeasureLayers(_measurePoints),
            ],
          ),
          MapControls(
            mapController: _mapController,
            layers: _buildInternalConfigs(),
            measureMode: _measureMode,
            onMeasureModeChanged: (v) => setState(() {
              _measureMode = v;
              if (!v) _measurePoints.clear();
            }),
            measurePoints: _measurePoints,
            onMeasureClear: () => setState(() => _measurePoints.clear()),
            onMeasureUndo: () => setState(() {
              if (_measurePoints.isNotEmpty) _measurePoints.removeLast();
            }),
          ),
        ],
      ),
    );
  }
}
