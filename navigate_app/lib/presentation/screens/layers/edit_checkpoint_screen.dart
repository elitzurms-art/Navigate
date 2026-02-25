import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../domain/entities/area.dart';
import '../../../domain/entities/checkpoint.dart';
import '../../../domain/entities/coordinate.dart';
import '../../../data/repositories/checkpoint_repository.dart';
import '../../../core/utils/utm_converter.dart';
import '../../widgets/map_with_selector.dart';
import '../../widgets/map_controls.dart';

/// מסך עריכת נקודת ציון
class EditCheckpointScreen extends StatefulWidget {
  final Area area;
  final Checkpoint checkpoint;
  final List<Checkpoint>? existingCheckpoints;

  const EditCheckpointScreen({
    super.key,
    required this.area,
    required this.checkpoint,
    this.existingCheckpoints,
  });

  @override
  State<EditCheckpointScreen> createState() => _EditCheckpointScreenState();
}

class _EditCheckpointScreenState extends State<EditCheckpointScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _sequenceController = TextEditingController();
  final _eastingController = TextEditingController();
  final _northingController = TextEditingController();
  final CheckpointRepository _repository = CheckpointRepository();

  late String _selectedType;
  late LatLng _selectedLocation;
  List<Checkpoint> _existingCheckpoints = [];
  final MapController _mapController = MapController();
  bool _isSaving = false;
  bool _measureMode = false;
  final List<LatLng> _measurePoints = [];

  // Auto-save
  Timer? _debounceTimer;
  bool _saved = false;

  Color get _typeColor => Checkpoint.flutterColorForType(_selectedType);

  @override
  void initState() {
    super.initState();
    // טעינת נתוני הנקודה הקיימת
    _descriptionController.text = widget.checkpoint.description;
    _sequenceController.text = widget.checkpoint.sequenceNumber.toString();
    _selectedType = widget.checkpoint.type;
    _selectedLocation = LatLng(
      widget.checkpoint.coordinates?.lat ?? 32.0853,
      widget.checkpoint.coordinates?.lng ?? 34.7818,
    );

    // טעינת שדות UTM מהנקודה הקיימת
    final existingUtm = widget.checkpoint.coordinates?.utm ?? '';
    if (existingUtm.length == 12) {
      _eastingController.text = existingUtm.substring(0, 6);
      _northingController.text = existingUtm.substring(6, 12);
    } else if (widget.checkpoint.coordinates != null) {
      // המרה מ-LatLng ל-UTM
      _updateUtmFromLocation(_selectedLocation);
    }

    _existingCheckpoints = widget.existingCheckpoints ?? [];
    if (_existingCheckpoints.isEmpty) {
      _loadExistingCheckpoints();
    }

    // הזזת המפה למיקום הנקודה
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mapController.move(_selectedLocation, 14);
    });
  }

  Future<void> _loadExistingCheckpoints() async {
    try {
      final checkpoints = await _repository.getByArea(widget.area.id);
      setState(() {
        _existingCheckpoints = checkpoints;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _descriptionController.dispose();
    _sequenceController.dispose();
    _eastingController.dispose();
    _northingController.dispose();
    super.dispose();
  }

  void _scheduleAutoSave() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), _autoSave);
  }

  void _saveImmediately() {
    _debounceTimer?.cancel();
    _autoSave();
  }

  Future<void> _autoSave() async {
    if (!mounted || _isSaving) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final utmString = _eastingController.text + _northingController.text;
      final autoColor = Checkpoint.colorForType(_selectedType);

      final updatedCheckpoint = widget.checkpoint.copyWith(
        name: '',
        description: _descriptionController.text,
        type: _selectedType,
        color: autoColor,
        sequenceNumber: int.parse(_sequenceController.text),
        coordinates: Coordinate(
          lat: _selectedLocation.latitude,
          lng: _selectedLocation.longitude,
          utm: utmString,
        ),
        labels: const [],
      );

      await _repository.update(updatedCheckpoint);

      if (mounted) {
        setState(() {
          _saved = true;
          _isSaving = false;
        });
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('הנקודה נשמרה'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 1),
          ),
        );
        // הסתרת אינדיקטור אחרי 2 שניות
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _saved = false);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בשמירה: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _updateLocationFromUtm() {
    final easting = _eastingController.text;
    final northing = _northingController.text;
    if (easting.length == 6 && northing.length == 6 &&
        int.tryParse(easting) != null && int.tryParse(northing) != null) {
      try {
        final utmString = easting + northing;
        final latLng = UtmConverter.utmToLatLng(utmString);
        setState(() {
          _selectedLocation = latLng;
          _mapController.move(latLng, 14);
        });
        _scheduleAutoSave();
      } catch (_) {}
    }
  }

  void _updateUtmFromLocation(LatLng point) {
    try {
      final utmString = UtmConverter.latLngToUtm(point);
      if (utmString.length == 12) {
        _eastingController.text = utmString.substring(0, 6);
        _northingController.text = utmString.substring(6, 12);
      }
    } catch (_) {}
  }

  Future<void> _openGoogleMaps() async {
    final url = Uri.parse(
      'https://www.google.com/maps?q=${_selectedLocation.latitude},${_selectedLocation.longitude}',
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  String _getTypeText(String type) {
    switch (type) {
      case 'checkpoint':
        return 'נ"צ';
      case 'mandatory_passage':
        return 'מעבר חובה';
      case 'start':
        return 'התחלה';
      case 'end':
        return 'סיום';
      default:
        return type;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('עריכת ${_getTypeText(widget.checkpoint.type)} #${widget.checkpoint.sequenceNumber}'),
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
          else if (_saved)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: Icon(Icons.check, color: Colors.white),
              ),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // תיאור
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'תיאור',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.description),
              ),
              maxLines: 2,
              onChanged: (_) => _scheduleAutoSave(),
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
              onChanged: (_) => _scheduleAutoSave(),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'נא להזין מספר';
                }
                final num = int.tryParse(value);
                if (num == null) {
                  return 'יש להזין מספר תקין';
                }
                // בדיקת ייחודיות (לא כולל הנקודה הנוכחית)
                final duplicate = _existingCheckpoints.any(
                  (cp) => cp.sequenceNumber == num && cp.id != widget.checkpoint.id,
                );
                if (duplicate) {
                  return 'מספר סידורי $num כבר קיים באזור זה';
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
                _saveImmediately();
              },
            ),
            const SizedBox(height: 8),
            // תצוגת צבע אוטומטי
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: _typeColor,
                  radius: 10,
                ),
                const SizedBox(width: 8),
                Text(
                  'צבע: ${_getColorName(Checkpoint.colorForType(_selectedType))}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

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
                            _updateUtmFromLocation(point);
                          });
                          _scheduleAutoSave();
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
                                color: _typeColor,
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
              'לחץ על המפה לשינוי המיקום',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),

            // שדות UTM
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _eastingController,
                    decoration: const InputDecoration(
                      labelText: 'מזרחה (Easting)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.grid_on),
                    ),
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    onChanged: (_) => _updateLocationFromUtm(),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'נדרש';
                      }
                      if (value.length != 6 || int.tryParse(value) == null) {
                        return '6 ספרות';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _northingController,
                    decoration: const InputDecoration(
                      labelText: 'צפונה (Northing)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.grid_on),
                    ),
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    onChanged: (_) => _updateLocationFromUtm(),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'נדרש';
                      }
                      if (value.length != 6 || int.tryParse(value) == null) {
                        return '6 ספרות';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // קישור לגוגל מפות
            InkWell(
              onTap: _openGoogleMaps,
              child: Row(
                children: [
                  Icon(Icons.map, color: Colors.blue[700], size: 18),
                  const SizedBox(width: 4),
                  Text(
                    'פתח בגוגל מפות',
                    style: TextStyle(
                      color: Colors.blue[700],
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getColorName(String colorString) {
    switch (colorString) {
      case 'blue':
        return 'כחול';
      case 'green':
        return 'ירוק';
      case 'red':
        return 'אדום';
      case 'yellow':
        return 'צהוב';
      default:
        return colorString;
    }
  }
}
