import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../../core/map_config.dart';
import 'map_type_selector.dart';

/// עוטף FlutterMap עם TileLayer אוטומטי וכפתור בחירת סוג מפה
class MapWithTypeSelector extends StatelessWidget {
  final MapOptions options;
  final List<Widget> layers;
  final MapController? mapController;
  final bool showTypeSelector;

  const MapWithTypeSelector({
    required this.options,
    super.key,
    this.layers = const [],
    this.mapController,
    this.showTypeSelector = true,
  });

  @override
  Widget build(BuildContext context) {
    final config = MapConfig();

    return Stack(
      children: [
        ValueListenableBuilder<MapType>(
          valueListenable: config.typeNotifier,
          builder: (context, mapType, _) {
            return FlutterMap(
              mapController: mapController,
              options: options,
              children: [
                TileLayer(
                  urlTemplate: config.urlTemplate(mapType),
                  maxZoom: config.maxZoom(mapType),
                  userAgentPackageName: MapConfig.userAgentPackageName,
                ),
                ...layers,
              ],
            );
          },
        ),
        if (showTypeSelector)
          const Positioned(
            top: 8,
            right: 8,
            child: MapTypeSelector(),
          ),
      ],
    );
  }
}
