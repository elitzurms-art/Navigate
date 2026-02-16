import 'package:flutter/material.dart';
import '../../../domain/entities/area.dart';
import '../../../data/repositories/area_repository.dart';
import 'checkpoints_list_screen.dart';
import 'safety_points_list_screen.dart';
import 'boundaries_list_screen.dart';
import 'clusters_list_screen.dart';
import 'map_with_layers_screen.dart';

/// מסך שכבות
class LayersScreen extends StatefulWidget {
  const LayersScreen({super.key});

  @override
  State<LayersScreen> createState() => _LayersScreenState();
}

class _LayersScreenState extends State<LayersScreen> {
  final AreaRepository _areaRepository = AreaRepository();
  Area? _selectedArea;
  List<Area> _areas = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAreas();
  }

  Future<void> _loadAreas() async {
    setState(() => _isLoading = true);
    try {
      final areas = await _areaRepository.getAll();
      setState(() {
        _areas = areas;
        if (areas.isNotEmpty && _selectedArea == null) {
          _selectedArea = areas.first;
        }
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('שכבות'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          if (_selectedArea != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: DropdownButton<Area>(
                value: _selectedArea,
                dropdownColor: Theme.of(context).primaryColor,
                style: const TextStyle(color: Colors.white),
                underline: Container(),
                icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                items: _areas.map((area) {
                  return DropdownMenuItem<Area>(
                    value: area,
                    child: Text(
                      area.name,
                      style: const TextStyle(color: Colors.white),
                    ),
                  );
                }).toList(),
                onChanged: (area) {
                  setState(() {
                    _selectedArea = area;
                  });
                },
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _areas.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.map, size: 100, color: Colors.grey[300]),
                      const SizedBox(height: 20),
                      Text(
                        'אין אזורים',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'צור אזור כדי להוסיף שכבות',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: Colors.grey[500]),
                      ),
                    ],
                  ),
                )
              : ListView(
                  children: [
                    _buildLayerCategory(
                      context,
                      layerType: 'nz',
                      title: 'נ"צ - נקודות ציון',
                      description: 'נקודות כחולות וירוקות',
                      icon: Icons.place,
                      color: Colors.blue,
                    ),
                    _buildLayerCategory(
                      context,
                      layerType: 'nb',
                      title: 'נת"ב - נקודות תורפה בטיחותיות',
                      description: 'נקודות אדומות',
                      icon: Icons.warning,
                      color: Colors.red,
                    ),
                    _buildLayerCategory(
                      context,
                      layerType: 'gg',
                      title: 'ג"ג - גבול גזרה',
                      description: 'פוליגון שחור',
                      icon: Icons.border_all,
                      color: Colors.black,
                    ),
                    _buildLayerCategory(
                      context,
                      layerType: 'ba',
                      title: 'ב"א - ביצי איזור',
                      description: 'פוליגון ירוק',
                      icon: Icons.grid_on,
                      color: Colors.green,
                    ),
                  ],
                ),
      floatingActionButton: _selectedArea != null
          ? FloatingActionButton.extended(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => MapWithLayersScreen(area: _selectedArea!),
                  ),
                );
              },
              icon: const Icon(Icons.map),
              label: const Text('מפה משולבת'),
              backgroundColor: Theme.of(context).primaryColor,
            )
          : null,
    );
  }

  Widget _buildLayerCategory(
    BuildContext context, {
    required String layerType,
    required String title,
    required String description,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.2),
          child: Icon(icon, color: color),
        ),
        title: Text(title),
        subtitle: Text(description),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () {
          if (_selectedArea != null) {
            switch (layerType) {
              case 'nz':
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        CheckpointsListScreen(area: _selectedArea!),
                  ),
                );
                break;
              case 'nb':
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        SafetyPointsListScreen(area: _selectedArea!),
                  ),
                );
                break;
              case 'gg':
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        BoundariesListScreen(area: _selectedArea!),
                  ),
                );
                break;
              case 'ba':
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        ClustersListScreen(area: _selectedArea!),
                  ),
                );
                break;
            }
          }
        },
      ),
    );
  }
}

