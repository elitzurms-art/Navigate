import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../domain/entities/area.dart';
import '../../../domain/entities/safety_point.dart';
import '../../../domain/entities/coordinate.dart';
import '../../../data/repositories/safety_point_repository.dart';
import '../../widgets/map_with_selector.dart';

/// מסך עריכת נקודת בטיחות — נקודה או פוליגון
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
  late String _type; // 'point' or 'polygon'
  LatLng? _selectedLocation; // לנקודה
  List<LatLng> _polygonPoints = []; // לפוליגון
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.point.name);
    _descriptionController = TextEditingController(text: widget.point.description);
    _sequenceController = TextEditingController(text: widget.point.sequenceNumber.toString());
    _selectedSeverity = widget.point.severity;
    _type = widget.point.type;

    if (_type == 'point' && widget.point.coordinates != null) {
      _selectedLocation = LatLng(
        widget.point.coordinates!.lat,
        widget.point.coordinates!.lng,
      );
    } else if (_type == 'polygon' && widget.point.polygonCoordinates != null) {
      _polygonPoints = widget.point.polygonCoordinates!
          .map((c) => LatLng(c.lat, c.lng))
          .toList();
    }

    // התמקד במיקום הנוכחי
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_type == 'point' && _selectedLocation != null) {
        _mapController.move(_selectedLocation!, 14);
      } else if (_type == 'polygon' && _polygonPoints.isNotEmpty) {
        final bounds = LatLngBounds.fromPoints(_polygonPoints);
        _mapController.fitCamera(CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(50),
        ));
      }
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

    if (_type == 'point' && _selectedLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('נא לבחור מיקום על המפה')),
      );
      return;
    }

    if (_type == 'polygon' && _polygonPoints.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('נא לסמן לפחות 3 נקודות לפוליגון')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final SafetyPoint updatedPoint;

      if (_type == 'point') {
        updatedPoint = widget.point.copyWith(
          name: _nameController.text,
          description: _descriptionController.text,
          coordinates: Coordinate(
            lat: _selectedLocation!.latitude,
            lng: _selectedLocation!.longitude,
            utm: widget.point.coordinates?.utm ?? '',
          ),
          sequenceNumber: int.parse(_sequenceController.text),
          severity: _selectedSeverity,
          updatedAt: DateTime.now(),
        );
      } else {
        updatedPoint = widget.point.copyWith(
          name: _nameController.text,
          description: _descriptionController.text,
          polygonCoordinates: _polygonPoints
              .map((ll) => Coordinate(lat: ll.latitude, lng: ll.longitude, utm: ''))
              .toList(),
          sequenceNumber: int.parse(_sequenceController.text),
          severity: _selectedSeverity,
          updatedAt: DateTime.now(),
        );
      }

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

  LatLng get _mapCenter {
    if (_type == 'point' && _selectedLocation != null) {
      return _selectedLocation!;
    }
    if (_type == 'polygon' && _polygonPoints.isNotEmpty) {
      final bounds = LatLngBounds.fromPoints(_polygonPoints);
      return bounds.center;
    }
    return const LatLng(31.5, 34.75);
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
            // סוג (לקריאה בלבד)
            Card(
              color: Colors.grey[100],
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(
                      _type == 'point' ? Icons.location_on : Icons.pentagon_outlined,
                      color: Colors.grey[700],
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'סוג: ${_type == 'point' ? 'נקודה' : 'פוליגון'}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

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
            Text(
              _type == 'point' ? 'מיקום על המפה' : 'עריכת פוליגון',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _type == 'point'
                  ? 'לחץ על המפה לשינוי מיקום'
                  : 'לחץ על המפה להוספת/שינוי קודקודים',
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 8),

            // toolbar לפוליגון
            if (_type == 'polygon' && _polygonPoints.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(Icons.pentagon_outlined, size: 18, color: Colors.grey[700]),
                    const SizedBox(width: 8),
                    Text(
                      '${_polygonPoints.length} קודקודים',
                      style: TextStyle(color: Colors.grey[700]),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () {
                        setState(() => _polygonPoints.removeLast());
                      },
                      icon: const Icon(Icons.undo, size: 18),
                      label: const Text('בטל אחרון'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.orange,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                    const SizedBox(width: 4),
                    TextButton.icon(
                      onPressed: () {
                        setState(() => _polygonPoints.clear());
                      },
                      icon: const Icon(Icons.clear, size: 18),
                      label: const Text('נקה'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                  ],
                ),
              ),

            SizedBox(
              height: 300,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: MapWithTypeSelector(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _mapCenter,
                    initialZoom: 14,
                    onTap: (tapPosition, point) {
                      setState(() {
                        if (_type == 'point') {
                          _selectedLocation = point;
                        } else {
                          _polygonPoints.add(point);
                        }
                      });
                    },
                  ),
                  layers: [
                    // נקודה — marker
                    if (_type == 'point' && _selectedLocation != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _selectedLocation!,
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
                    // פוליגון — צורה מלאה
                    if (_type == 'polygon' && _polygonPoints.length >= 3)
                      PolygonLayer(
                        polygons: [
                          Polygon(
                            points: _polygonPoints,
                            color: _getSeverityColor(_selectedSeverity).withOpacity(0.2),
                            borderColor: _getSeverityColor(_selectedSeverity),
                            borderStrokeWidth: 3,
                            isFilled: true,
                          ),
                        ],
                      ),
                    // קו בין נקודות (כשפחות מ-3)
                    if (_type == 'polygon' && _polygonPoints.length >= 2 && _polygonPoints.length < 3)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: _polygonPoints,
                            color: _getSeverityColor(_selectedSeverity),
                            strokeWidth: 2,
                          ),
                        ],
                      ),
                    // markers לקודקודים
                    if (_type == 'polygon' && _polygonPoints.isNotEmpty)
                      MarkerLayer(
                        markers: _polygonPoints.asMap().entries.map((entry) {
                          return Marker(
                            point: entry.value,
                            width: 24,
                            height: 24,
                            child: Container(
                              decoration: BoxDecoration(
                                color: _getSeverityColor(_selectedSeverity),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: Center(
                                child: Text(
                                  '${entry.key + 1}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),
            ),
            if (_type == 'point' && _selectedLocation != null) ...[
              const SizedBox(height: 8),
              Text(
                'קואורדינטות: ${_selectedLocation!.latitude.toStringAsFixed(6)}, ${_selectedLocation!.longitude.toStringAsFixed(6)}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
            if (_type == 'polygon' && _polygonPoints.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${_polygonPoints.length} קודקודים${_polygonPoints.length < 3 ? ' (נדרשים לפחות 3)' : ''}',
                style: TextStyle(
                  fontSize: 12,
                  color: _polygonPoints.length < 3 ? Colors.red : Colors.grey,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
