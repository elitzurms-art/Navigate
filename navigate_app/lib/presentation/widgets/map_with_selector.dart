import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../../core/map_config.dart';
import '../../services/tile_cache_service.dart';
import 'map_type_selector.dart';

/// עוטף FlutterMap עם TileLayer אוטומטי וכפתור בחירת סוג מפה
class MapWithTypeSelector extends StatefulWidget {
  final MapOptions options;
  final List<Widget> layers;
  final MapController? mapController;
  final bool showTypeSelector;

  /// סוג מפה התחלתי — אם מסופק, יחליף את הגדרת MapConfig הגלובלית בבנייה הראשונה
  final MapType? initialMapType;

  const MapWithTypeSelector({
    required this.options,
    super.key,
    this.layers = const [],
    this.mapController,
    this.showTypeSelector = true,
    this.initialMapType,
  });

  @override
  State<MapWithTypeSelector> createState() => _MapWithTypeSelectorState();
}

class _MapWithTypeSelectorState extends State<MapWithTypeSelector> {
  bool _didApplyInitialMapType = false;

  @override
  void initState() {
    super.initState();
    // החלפת סוג מפה גלובלי אם סופק initialMapType
    if (widget.initialMapType != null && !_didApplyInitialMapType) {
      _didApplyInitialMapType = true;
      MapConfig().setType(widget.initialMapType!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = MapConfig();

    return Stack(
      children: [
        ValueListenableBuilder<MapType>(
          valueListenable: config.typeNotifier,
          builder: (context, mapType, _) {
            return FlutterMap(
              mapController: widget.mapController,
              options: widget.options,
              children: [
                TileLayer(
                  urlTemplate: config.urlTemplate(mapType),
                  maxZoom: config.maxZoom(mapType),
                  userAgentPackageName: MapConfig.userAgentPackageName,
                  tileProvider: TileCacheService().getTileProvider(),
                ),
                ...widget.layers,
              ],
            );
          },
        ),
        if (widget.showTypeSelector)
          const Positioned(
            top: 8,
            right: 8,
            child: MapTypeSelector(),
          ),
      ],
    );
  }
}
