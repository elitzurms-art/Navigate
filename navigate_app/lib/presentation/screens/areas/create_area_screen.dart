import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../domain/entities/area.dart' as domain;
import '../../../data/repositories/area_repository.dart';
import '../../../services/auth_service.dart';
import '../../widgets/map_with_selector.dart';
import '../../widgets/map_controls.dart';

/// מסך יצירת אזור חדש
class CreateAreaScreen extends StatefulWidget {
  final domain.Area? area; // לעריכה

  const CreateAreaScreen({super.key, this.area});

  @override
  State<CreateAreaScreen> createState() => _CreateAreaScreenState();
}

class _CreateAreaScreenState extends State<CreateAreaScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final MapController _mapController = MapController();

  List<LatLng> _boundaryPoints = [];
  bool _isDrawing = false;
  bool _isSaving = false;
  bool _measureMode = false;
  bool _isFullscreen = false;
  final List<LatLng> _measurePoints = [];

  @override
  void initState() {
    super.initState();
    if (widget.area != null) {
      _nameController.text = widget.area!.name;
      _descriptionController.text = widget.area!.description;
      // TODO: טעינת נקודות גבול מהאזור
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Widget _buildMapWidget() {
    return Stack(
      children: [
        MapWithTypeSelector(
          showTypeSelector: false,
          mapController: _mapController,
          options: MapOptions(
            initialCenter: const LatLng(32.0853, 34.7818),
            initialZoom: 13.0,
            onTap: (tapPosition, point) {
              if (_measureMode) {
                setState(() => _measurePoints.add(point));
                return;
              }
              if (_isDrawing) {
                setState(() {
                  _boundaryPoints.add(point);
                });
              }
            },
          ),
          layers: [
            if (_boundaryPoints.isNotEmpty)
              PolygonLayer(
                polygons: [
                  Polygon(
                    points: _boundaryPoints,
                    color: Colors.blue.withOpacity(0.3),
                    borderColor: Colors.blue,
                    borderStrokeWidth: 3,
                    isFilled: true,
                  ),
                ],
              ),
            if (_boundaryPoints.isNotEmpty)
              MarkerLayer(
                markers: _boundaryPoints.asMap().entries.map((entry) {
                  return Marker(
                    point: entry.value,
                    width: 30,
                    height: 30,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Center(
                        child: Text(
                          '${entry.key + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
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
          onFullscreen: () => setState(() => _isFullscreen = !_isFullscreen),
        ),
        // פקדי ציור במסך מלא
        if (_isFullscreen)
          Positioned(
            bottom: 16,
            right: 16,
            left: 16,
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _isDrawing = !_isDrawing;
                      });
                    },
                    icon: Icon(_isDrawing ? Icons.stop : Icons.edit_location),
                    label: Text(_isDrawing ? 'סיים ציור' : 'צייר גבול'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isDrawing ? Colors.orange : Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _boundaryPoints.isEmpty ? null : () {
                    setState(() {
                      _boundaryPoints.clear();
                    });
                  },
                  icon: const Icon(Icons.clear),
                  label: const Text('נקה'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        if (_isFullscreen && _isDrawing)
          Positioned(
            top: 8,
            left: 60,
            right: 60,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'לחץ על המפה להוספת נקודות גבול (${_boundaryPoints.length} נקודות)',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.orange),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _isFullscreen ? null : AppBar(
        title: Text(widget.area == null ? 'אזור חדש' : 'עריכת אזור'),
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
              onPressed: _saveArea,
            ),
        ],
      ),
      body: _isFullscreen
          ? _buildMapWidget()
          : Column(
              children: [
                // טופס פרטי אזור
                Expanded(
                  flex: 2,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextFormField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                              labelText: 'שם האזור',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.map),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'נא להזין שם אזור';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
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
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    setState(() {
                                      _isDrawing = !_isDrawing;
                                    });
                                  },
                                  icon: Icon(_isDrawing ? Icons.stop : Icons.edit_location),
                                  label: Text(_isDrawing ? 'סיים ציור' : 'צייר גבול'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _isDrawing ? Colors.orange : Colors.blue,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                onPressed: _boundaryPoints.isEmpty ? null : () {
                                  setState(() {
                                    _boundaryPoints.clear();
                                  });
                                },
                                icon: const Icon(Icons.clear),
                                label: const Text('נקה'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'נקודות: ${_boundaryPoints.length}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if (_isDrawing)
                            Container(
                              padding: const EdgeInsets.all(8),
                              color: Colors.orange.shade50,
                              child: const Text(
                                'לחץ על המפה להוספת נקודות גבול',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.orange),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),

                // מפה
                Expanded(
                  flex: 3,
                  child: _buildMapWidget(),
                ),
              ],
            ),
    );
  }

  Future<void> _saveArea() async {
    print('DEBUG: _saveArea called');

    if (!_formKey.currentState!.validate()) {
      print('DEBUG: Form validation failed');
      return;
    }

    if (_boundaryPoints.length < 3 && widget.area == null) {
      print('DEBUG: Not enough boundary points');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('יש להגדיר לפחות 3 נקודות גבול'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      print('DEBUG: Starting save process');
      final authService = AuthService();
      print('DEBUG: Getting current user');
      final currentUser = await authService.getCurrentUser();
      print('DEBUG: Current user: ${currentUser?.uid}');

      if (currentUser == null) {
        throw Exception('משתמש לא מחובר');
      }

      print('DEBUG: Creating area repository');
      final areaRepository = AreaRepository();

      if (widget.area == null) {
        // יצירת אזור חדש
        print('DEBUG: Creating new area');
        final newArea = domain.Area(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: _nameController.text,
          description: _descriptionController.text,
          createdBy: currentUser.uid,
          createdAt: DateTime.now(),
        );

        print('DEBUG: Calling repository.create');
        await areaRepository.create(newArea);
        print('DEBUG: Area created successfully');

        // TODO: שמירת נקודות הגבול בשכבת gg
        // לעשות זאת כשנבנה את מערכת השכבות

      } else {
        // עדכון אזור קיים
        print('DEBUG: Updating existing area');
        final updatedArea = widget.area!.copyWith(
          name: _nameController.text,
          description: _descriptionController.text,
        );

        await areaRepository.update(updatedArea);
        print('DEBUG: Area updated successfully');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.area == null
                  ? 'האזור נשמר בהצלחה'
                  : 'האזור עודכן בהצלחה',
            ),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e, stackTrace) {
      print('DEBUG: Error occurred: $e');
      print('DEBUG: Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בשמירה: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }
}
