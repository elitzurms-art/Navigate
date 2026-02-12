import 'package:flutter/material.dart';
import '../../../domain/entities/area.dart';
import '../../../data/repositories/checkpoint_repository.dart';
import '../../../data/repositories/safety_point_repository.dart';
import '../../../data/repositories/boundary_repository.dart';
import '../../../data/repositories/cluster_repository.dart';
import '../layers/checkpoints_list_screen.dart';
import '../layers/safety_points_list_screen.dart';
import '../layers/boundaries_list_screen.dart';
import '../layers/clusters_list_screen.dart';
import '../layers/map_with_layers_screen.dart';

/// מסך פרטי אזור - מציג את כל השכבות של אזור ספציפי
class AreaDetailsScreen extends StatefulWidget {
  final Area area;

  const AreaDetailsScreen({super.key, required this.area});

  @override
  State<AreaDetailsScreen> createState() => _AreaDetailsScreenState();
}

class _AreaDetailsScreenState extends State<AreaDetailsScreen> with WidgetsBindingObserver {
  final CheckpointRepository _checkpointRepo = CheckpointRepository();
  final SafetyPointRepository _safetyPointRepo = SafetyPointRepository();
  final BoundaryRepository _boundaryRepo = BoundaryRepository();
  final ClusterRepository _clusterRepo = ClusterRepository();

  int _checkpointsCount = 0;
  int _safetyPointsCount = 0;
  int _boundariesCount = 0;
  int _clustersCount = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadCounts();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadCounts();
    }
  }

  Future<void> _loadCounts() async {
    setState(() => _isLoading = true);
    try {
      final checkpoints = await _checkpointRepo.getByArea(widget.area.id);
      final safetyPoints = await _safetyPointRepo.getByArea(widget.area.id);
      final boundaries = await _boundaryRepo.getByArea(widget.area.id);
      final clusters = await _clusterRepo.getByArea(widget.area.id);

      setState(() {
        _checkpointsCount = checkpoints.length;
        _safetyPointsCount = safetyPoints.length;
        _boundariesCount = boundaries.length;
        _clustersCount = clusters.length;
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
        title: Text('אזור ${widget.area.name}'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadCounts,
            tooltip: 'רענן',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // מידע על האזור
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.map,
                              size: 32,
                              color: Theme.of(context).primaryColor,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.area.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  if (widget.area.description.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      widget.area.description,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(color: Colors.grey[600]),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // כותרת שכבות
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Text(
                    'שכבות האזור',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[700],
                        ),
                  ),
                ),

                const SizedBox(height: 8),

                // נקודות ציון
                _buildLayerCard(
                  context: context,
                  title: 'נ"ז - נקודות ציון',
                  subtitle: '$_checkpointsCount נקודות',
                  icon: Icons.place,
                  color: Colors.blue,
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            CheckpointsListScreen(area: widget.area),
                      ),
                    );
                    _loadCounts();
                  },
                ),

                const SizedBox(height: 12),

                // נקודות תורפה בטיחותיות
                _buildLayerCard(
                  context: context,
                  title: 'נת"ב - נקודות תורפה בטיחותיות',
                  subtitle: '$_safetyPointsCount נקודות',
                  icon: Icons.warning,
                  color: Colors.red,
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            SafetyPointsListScreen(area: widget.area),
                      ),
                    );
                    _loadCounts();
                  },
                ),

                const SizedBox(height: 12),

                // גבול גזרה
                _buildLayerCard(
                  context: context,
                  title: 'ג"ג - גבול גזרה',
                  subtitle: '$_boundariesCount פוליגונים',
                  icon: Icons.border_all,
                  color: Colors.black,
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            BoundariesListScreen(area: widget.area),
                      ),
                    );
                    _loadCounts();
                  },
                ),

                const SizedBox(height: 12),

                // ביצי אזור
                _buildLayerCard(
                  context: context,
                  title: 'ב"א - ביצי אזור',
                  subtitle: '$_clustersCount פוליגונים',
                  icon: Icons.grid_on,
                  color: Colors.green,
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            ClustersListScreen(area: widget.area),
                      ),
                    );
                    _loadCounts();
                  },
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => MapWithLayersScreen(area: widget.area),
            ),
          );
        },
        icon: const Icon(Icons.map),
        label: const Text('מפה משולבת'),
        backgroundColor: Theme.of(context).primaryColor,
      ),
    );
  }

  Widget _buildLayerCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 32),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey[600],
                          ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 20,
                color: Colors.grey[400],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
