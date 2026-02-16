import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'map_with_selector.dart';
import 'map_controls.dart';

/// מסך מפה במסך מלא — תצוגת שכבות מהמסך המקורי עם כלי מדידה
class FullscreenMapScreen extends StatefulWidget {
  final String title;
  final List<Widget> layers;
  final LatLng initialCenter;
  final double initialZoom;
  final CameraFit? initialCameraFit;

  const FullscreenMapScreen({
    super.key,
    required this.title,
    required this.layers,
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

  @override
  Widget build(BuildContext context) {
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
              ...widget.layers,
              ...MapControls.buildMeasureLayers(_measurePoints),
            ],
          ),
          MapControls(
            mapController: _mapController,
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
