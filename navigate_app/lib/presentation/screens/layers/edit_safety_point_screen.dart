import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../domain/entities/area.dart';
import '../../../domain/entities/safety_point.dart';
import '../../../domain/entities/coordinate.dart';
import '../../../data/repositories/safety_point_repository.dart';
import '../../widgets/map_with_selector.dart';
import '../../widgets/map_controls.dart';

/// מסך עריכת נקודת בטיחות
class EditSafetyPointScreen extends StatefulWidget {
  final Area area;
  final SafetyPoint point;

  const EditSafetyPointScreen({
    super.key,
    required this.area,
    required this.point,
  });

  @override
  State<EditSafetyPointScreen> createState() => _EditSafetyPointScreenState();
}

class _EditSafetyPointScreenState extends State<EditSafetyPointScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _sequenceController;
  final MapController _mapController = MapController();
  final SafetyPointRepository _repository = SafetyPointRepository();

  late String _selectedSeverity;
  late LatLng _selectedLocation;
  bool _isLoading = false;
  bool _measureMode = false;
  final List<LatLng> _measurePoints = [];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.point.name);
    _descriptionController = TextEditingController(text: widget.point.description);
    _sequenceController = TextEditingController(text: widget.point.sequenceNumber.toString());
    _selectedSeverity = widget.point.severity;
    // תמיכה רק בנקודות (לא בפוליגונים)
    if (widget.point.type == 'point' && widget.point.coordinates != null) {
      _selectedLocation = LatLng(
        widget.point.coordinates!.lat,
        widget.point.coordinates!.lng,
      );
    }

    // התמקד במיקום הנוכחי
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mapController.move(_selectedLocation, 14);
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _sequenceController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final updatedPoint = widget.point.copyWith(
        name: _nameController.text,
        description: _descriptionController.text,
        coordinates: widget.point.type == 'point'
            ? Coordinate(
                lat: _selectedLocation.latitude,
                lng: _selectedLocation.longitude,
                utm: widget.point.coordinates?.utm ?? '',
              )
            : null,
        sequenceNumber: int.parse(_sequenceController.text),
        severity: _selectedSeverity,
        updatedAt: DateTime.now(),
      );

      await _repository.update(updatedPoint);

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('נת"ב עודכן בהצלחה')),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה: $e')),
        );
      }
    }
  }

  Color _getSeverityColor(String severity) {
    switch (severity) {
      case 'low':
        return Colors.orange;
      case 'medium':
        return Colors.red;
      case 'high':
        return Colors.red.shade700;
      case 'critical':
        return Colors.red.shade900;
      default:
        return Colors.red;
    }
  }

  String _getSeverityLabel(String severity) {
    switch (severity) {
      case 'low':
        return 'נמוכה';
      case 'medium':
        return 'בינונית';
      case 'high':
        return 'גבוהה';
      case 'critical':
        return 'קריטית';
      default:
        return 'בינונית';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('עריכת נת"ב - ${widget.area.name}'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _save,
              tooltip: 'שמור',
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // שם
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'שם נקודת הבטיחות',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.warning),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'נא להזין שם';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // תיאור
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'תיאור',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.description),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),

            // מספר סידורי
            TextFormField(
              controller: _sequenceController,
              decoration: const InputDecoration(
                labelText: 'מספר סידורי',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.numbers),
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'נא להזין מספר';
                }
                if (int.tryParse(value) == null) {
                  return 'נא להזין מספר תקין';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // רמת חומרה
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'רמת חומרה',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: ['low', 'medium', 'high', 'critical'].map((severity) {
                        return ChoiceChip(
                          label: Text(_getSeverityLabel(severity)),
                          selected: _selectedSeverity == severity,
                          onSelected: (selected) {
                            if (selected) {
                              setState(() => _selectedSeverity = severity);
                            }
                          },
                          selectedColor: _getSeverityColor(severity).withOpacity(0.3),
                          labelStyle: TextStyle(
                            color: _selectedSeverity == severity
                                ? _getSeverityColor(severity)
                                : null,
                            fontWeight: _selectedSeverity == severity
                                ? FontWeight.bold
                                : null,
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // מפה
            const Text(
              'מיקום על המפה',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'לחץ על המפה לשינוי מיקום',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 300,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  children: [
                    MapWithTypeSelector(
                      showTypeSelector: false,
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _selectedLocation,
                        initialZoom: 14,
                        onTap: (tapPosition, point) {
                          if (_measureMode) {
                            setState(() => _measurePoints.add(point));
                            return;
                          }
                          setState(() {
                            _selectedLocation = point;
                          });
                        },
                      ),
                      layers: [
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: _selectedLocation,
                              width: 50,
                              height: 50,
                              child: Icon(
                                Icons.warning,
                                color: _getSeverityColor(_selectedSeverity),
                                size: 40,
                              ),
                            ),
                          ],
                        ),
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
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'קואורדינטות: ${_selectedLocation.latitude.toStringAsFixed(6)}, ${_selectedLocation.longitude.toStringAsFixed(6)}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
