import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../domain/entities/area.dart';
import '../../../domain/entities/checkpoint.dart';
import '../../../domain/entities/coordinate.dart';
import '../../../data/repositories/checkpoint_repository.dart';
import '../../widgets/map_with_selector.dart';

/// מסך עריכת נקודת ציון
class EditCheckpointScreen extends StatefulWidget {
  final Area area;
  final Checkpoint checkpoint;

  const EditCheckpointScreen({
    super.key,
    required this.area,
    required this.checkpoint,
  });

  @override
  State<EditCheckpointScreen> createState() => _EditCheckpointScreenState();
}

class _EditCheckpointScreenState extends State<EditCheckpointScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _sequenceController = TextEditingController();
  final _latController = TextEditingController();
  final _lngController = TextEditingController();
  final _utmController = TextEditingController();
  final _labelController = TextEditingController();

  late String _selectedType;
  late String _selectedColor;
  late LatLng _selectedLocation;
  late List<String> _labels;
  final MapController _mapController = MapController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // טעינת נתוני הנקודה הקיימת
    _nameController.text = widget.checkpoint.name;
    _descriptionController.text = widget.checkpoint.description;
    _sequenceController.text = widget.checkpoint.sequenceNumber.toString();
    _latController.text = widget.checkpoint.coordinates.lat.toStringAsFixed(6);
    _lngController.text = widget.checkpoint.coordinates.lng.toStringAsFixed(6);
    _utmController.text = widget.checkpoint.coordinates.utm;

    _selectedType = widget.checkpoint.type;
    _selectedColor = widget.checkpoint.color;
    _selectedLocation = LatLng(
      widget.checkpoint.coordinates.lat,
      widget.checkpoint.coordinates.lng,
    );
    _labels = List<String>.from(widget.checkpoint.labels);

    // הזזת המפה למיקום הנקודה
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mapController.move(_selectedLocation, 14);
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _sequenceController.dispose();
    _latController.dispose();
    _lngController.dispose();
    _utmController.dispose();
    _labelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('עריכת ${widget.checkpoint.name}'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
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
              icon: const Icon(Icons.save),
              onPressed: _updateCheckpoint,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // שם הנקודה
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'שם הנקודה',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.label),
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
              maxLines: 2,
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
                  return 'יש להזין מספר תקין';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // סוג הנקודה
            DropdownButtonFormField<String>(
              value: _selectedType,
              decoration: const InputDecoration(
                labelText: 'סוג הנקודה',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.category),
              ),
              items: const [
                DropdownMenuItem(value: 'checkpoint', child: Text('נקודת ציון')),
                DropdownMenuItem(value: 'mandatory_passage', child: Text('נקודת מעבר חובה')),
                DropdownMenuItem(value: 'start', child: Text('נקודת התחלה')),
                DropdownMenuItem(value: 'end', child: Text('נקודת סיום')),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedType = value!;
                });
              },
            ),
            const SizedBox(height: 16),

            // צבע הנקודה
            DropdownButtonFormField<String>(
              value: _selectedColor,
              decoration: const InputDecoration(
                labelText: 'צבע',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.palette),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'blue',
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.blue,
                        radius: 10,
                      ),
                      SizedBox(width: 8),
                      Text('כחול'),
                    ],
                  ),
                ),
                DropdownMenuItem(
                  value: 'green',
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.green,
                        radius: 10,
                      ),
                      SizedBox(width: 8),
                      Text('ירוק'),
                    ],
                  ),
                ),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedColor = value!;
                });
              },
            ),
            const SizedBox(height: 24),

            // תוויות/תאי שטח
            Text(
              'תוויות ותאי שטח',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _labelController,
                    decoration: const InputDecoration(
                      labelText: 'הוסף תווית',
                      border: OutlineInputBorder(),
                      hintText: 'לדוגמה: תא-1, מגזר-A',
                    ),
                    onSubmitted: (_) => _addLabel(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _addLabel,
                  icon: const Icon(Icons.add),
                  label: const Text('הוסף'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_labels.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _labels.map((label) {
                  return Chip(
                    label: Text(label),
                    deleteIcon: const Icon(Icons.close, size: 18),
                    onDeleted: () {
                      setState(() {
                        _labels.remove(label);
                      });
                    },
                  );
                }).toList(),
              ),
            const SizedBox(height: 24),

            // כותרת קואורדינטות
            Text(
              'קואורדינטות',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),

            // מפה לבחירת מיקום
            Container(
              height: 300,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: MapWithTypeSelector(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _selectedLocation,
                    initialZoom: 14,
                    onTap: (tapPosition, point) {
                      setState(() {
                        _selectedLocation = point;
                        _latController.text = point.latitude.toStringAsFixed(6);
                        _lngController.text = point.longitude.toStringAsFixed(6);
                      });
                    },
                  ),
                  layers: [
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _selectedLocation,
                          width: 40,
                          height: 40,
                          child: Icon(
                            Icons.place,
                            color: _selectedColor == 'blue' ? Colors.blue : Colors.green,
                            size: 40,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'לחץ על המפה לשינוי המיקום',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),

            // קואורדינטות ידניות
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _latController,
                    decoration: const InputDecoration(
                      labelText: 'קו רוחב (Lat)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (value) {
                      final lat = double.tryParse(value);
                      final lng = double.tryParse(_lngController.text);
                      if (lat != null && lng != null) {
                        setState(() {
                          _selectedLocation = LatLng(lat, lng);
                          _mapController.move(_selectedLocation, 14);
                        });
                      }
                    },
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'נדרש';
                      }
                      if (double.tryParse(value) == null) {
                        return 'מספר לא תקין';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _lngController,
                    decoration: const InputDecoration(
                      labelText: 'קו אורך (Lng)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (value) {
                      final lat = double.tryParse(_latController.text);
                      final lng = double.tryParse(value);
                      if (lat != null && lng != null) {
                        setState(() {
                          _selectedLocation = LatLng(lat, lng);
                          _mapController.move(_selectedLocation, 14);
                        });
                      }
                    },
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'נדרש';
                      }
                      if (double.tryParse(value) == null) {
                        return 'מספר לא תקין';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // UTM (אופציונלי)
            TextFormField(
              controller: _utmController,
              decoration: const InputDecoration(
                labelText: 'UTM (אופציונלי)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.grid_on),
                hintText: 'לדוגמה: 36R 123456 7654321',
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _addLabel() {
    if (_labelController.text.isNotEmpty) {
      setState(() {
        _labels.add(_labelController.text);
        _labelController.clear();
      });
    }
  }

  Future<void> _updateCheckpoint() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSaving = true);

    try {
      final updatedCheckpoint = widget.checkpoint.copyWith(
        name: _nameController.text,
        description: _descriptionController.text,
        type: _selectedType,
        color: _selectedColor,
        sequenceNumber: int.parse(_sequenceController.text),
        coordinates: Coordinate(
          lat: _selectedLocation.latitude,
          lng: _selectedLocation.longitude,
          utm: _utmController.text.isEmpty ? '' : _utmController.text,
        ),
        labels: _labels,
      );

      final repository = CheckpointRepository();
      await repository.update(updatedCheckpoint);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('נקודת ציון עודכנה בהצלחה'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בעדכון: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }
}
