import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../domain/entities/area.dart' as domain;
import '../../../data/repositories/area_repository.dart';
import '../../../services/auth_service.dart';
import '../../widgets/map_with_selector.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
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
      body: Column(
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
            child: MapWithTypeSelector(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: const LatLng(32.0853, 34.7818),
                initialZoom: 13.0,
                onTap: _isDrawing ? (tapPosition, point) {
                  setState(() {
                    _boundaryPoints.add(point);
                  });
                } : null,
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
              ],
            ),
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
