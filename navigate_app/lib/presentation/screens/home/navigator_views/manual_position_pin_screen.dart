import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../widgets/map_with_selector.dart';

/// מסך דקירת מיקום ידנית — מפה במסך מלא לבחירת מיקום
class ManualPositionPinScreen extends StatefulWidget {
  const ManualPositionPinScreen({super.key});

  @override
  State<ManualPositionPinScreen> createState() => _ManualPositionPinScreenState();
}

class _ManualPositionPinScreenState extends State<ManualPositionPinScreen> {
  final MapController _mapController = MapController();
  LatLng? _pinnedLocation;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('דקירת מיקום עצמי'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          MapWithTypeSelector(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(31.5, 34.8),
              initialZoom: 10,
              onTap: (tapPosition, point) {
                setState(() => _pinnedLocation = point);
              },
            ),
            layers: [
              if (_pinnedLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _pinnedLocation!,
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.push_pin,
                        color: Colors.deepPurple,
                        size: 36,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          // הוראה למנווט
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
              ),
              child: const Text(
                'סמן את המיקום שלך במפה',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          // כפתור אישור
          if (_pinnedLocation != null)
            Positioned(
              bottom: 32,
              left: 32,
              right: 32,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pop(context, _pinnedLocation),
                icon: const Icon(Icons.check),
                label: const Text('אישור מיקום', style: TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
