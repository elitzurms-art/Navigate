import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../../domain/entities/navigation.dart' as domain;
import '../../../../services/gps_service.dart';
import '../../../widgets/map_with_selector.dart';
import '../../../widgets/map_controls.dart';

/// מסך מפה מלא — נפתח מ-drawer בזמן ניווט פעיל
class NavigatorMapScreen extends StatefulWidget {
  final domain.Navigation navigation;
  final bool showSelfLocation;
  final bool showRoute;

  const NavigatorMapScreen({
    super.key,
    required this.navigation,
    this.showSelfLocation = false,
    this.showRoute = false,
  });

  @override
  State<NavigatorMapScreen> createState() => _NavigatorMapScreenState();
}

class _NavigatorMapScreenState extends State<NavigatorMapScreen> {
  final MapController _mapController = MapController();
  final GpsService _gpsService = GpsService();

  LatLng? _currentPosition;
  StreamSubscription? _positionSubscription;

  bool _measureMode = false;
  final List<LatLng> _measurePoints = [];

  // ברירת מחדל — מרכז ישראל
  static const _defaultCenter = LatLng(31.5, 34.8);
  static const _defaultZoom = 13.0;

  @override
  void initState() {
    super.initState();
    if (widget.showSelfLocation) {
      _startLocationTracking();
    }
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  void _startLocationTracking() {
    // TODO: use GpsService stream for live position updates
    // For now, get single position
    _gpsService.getCurrentPosition().then((latLng) {
      if (mounted && latLng != null) {
        setState(() {
          _currentPosition = latLng;
        });
        _mapController.move(_currentPosition!, _defaultZoom);
      }
    }).catchError((_) {});
  }

  LatLng _initialCenter() {
    final ds = widget.navigation.displaySettings;
    if (ds.openingLat != null && ds.openingLng != null) {
      return LatLng(ds.openingLat!, ds.openingLng!);
    }
    return _currentPosition ?? _defaultCenter;
  }

  // ===========================================================================
  // Map layers
  // ===========================================================================

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];

    // מיקום עצמי
    if (widget.showSelfLocation && _currentPosition != null) {
      markers.add(Marker(
        point: _currentPosition!,
        width: 30,
        height: 30,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.blue,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.withOpacity(0.3),
                blurRadius: 8,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Icon(Icons.my_location, size: 16, color: Colors.white),
        ),
      ));
    }

    return markers;
  }

  List<Polyline> _buildPolylines() {
    final polylines = <Polyline>[];

    // TODO: build route polyline from assigned route checkpoints when showRoute is true
    // This requires loading checkpoint coordinates from NavCheckpoints table

    return polylines;
  }

  // ===========================================================================
  // Build
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.navigation.name),
        centerTitle: true,
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          if (widget.showSelfLocation)
            IconButton(
              icon: const Icon(Icons.my_location),
              onPressed: () {
                if (_currentPosition != null) {
                  _mapController.move(_currentPosition!, _defaultZoom);
                }
              },
            ),
        ],
      ),
      body: Stack(
        children: [
          MapWithTypeSelector(
            mapController: _mapController,
            showTypeSelector: false,
            options: MapOptions(
              initialCenter: _initialCenter(),
              initialZoom: _defaultZoom,
              onTap: (tapPosition, point) {
                if (_measureMode) {
                  setState(() => _measurePoints.add(point));
                  return;
                }
              },
            ),
            layers: [
              PolylineLayer(polylines: _buildPolylines()),
              MarkerLayer(markers: _buildMarkers()),
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
