import 'package:flutter/material.dart';
import '../../core/map_config.dart';

/// כפתור בחירת סוג מפה (OSM / טופוגרפית / לוויין)
class MapTypeSelector extends StatelessWidget {
  const MapTypeSelector({super.key});

  static const _icons = {
    MapType.standard: Icons.map_outlined,
    MapType.topographic: Icons.terrain,
    MapType.satellite: Icons.satellite_alt,
  };

  @override
  Widget build(BuildContext context) {
    final config = MapConfig();

    return ValueListenableBuilder<MapType>(
      valueListenable: config.typeNotifier,
      builder: (context, currentType, _) {
        return Material(
          color: Colors.white,
          elevation: 2,
          borderRadius: BorderRadius.circular(8),
          child: PopupMenuButton<MapType>(
            icon: Icon(_icons[currentType], color: Colors.grey[700]),
            tooltip: 'סוג מפה',
            onSelected: (type) => config.setType(type),
            itemBuilder: (_) => MapType.values.map((type) {
              final selected = type == currentType;
              return PopupMenuItem<MapType>(
                value: type,
                child: Row(
                  children: [
                    Icon(
                      _icons[type],
                      color: selected ? Theme.of(context).primaryColor : Colors.grey[600],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        config.label(type),
                        style: TextStyle(
                          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                          color: selected ? Theme.of(context).primaryColor : null,
                        ),
                      ),
                    ),
                    if (selected)
                      Icon(Icons.check, color: Theme.of(context).primaryColor, size: 20),
                  ],
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}
