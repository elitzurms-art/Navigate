import 'package:flutter/material.dart';
import '../../../domain/entities/navigation.dart' as domain;
import '../../../domain/entities/navigation_settings.dart';
import '../../../domain/entities/checkpoint.dart';
import '../../../data/repositories/nav_layer_repository.dart';
import '../../../data/repositories/navigation_repository.dart';
import '../../../data/repositories/navigation_tree_repository.dart';
import '../../../data/repositories/checkpoint_repository.dart';
import '../../../domain/entities/navigation_tree.dart';
import '../../../services/routes_distribution_service.dart';
import '../../../services/navigation_layer_copy_service.dart';
import 'routes_verification_screen.dart';

/// שלב 2 - הגדרות חלוקה אוטומטית
class RoutesAutomaticSetupScreen extends StatefulWidget {
  final domain.Navigation navigation;

  const RoutesAutomaticSetupScreen({super.key, required this.navigation});

  @override
  State<RoutesAutomaticSetupScreen> createState() => _RoutesAutomaticSetupScreenState();
}

class _RoutesAutomaticSetupScreenState extends State<RoutesAutomaticSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final NavLayerRepository _navLayerRepo = NavLayerRepository();
  final NavigationRepository _navRepo = NavigationRepository();
  final NavigationTreeRepository _treeRepo = NavigationTreeRepository();
  final CheckpointRepository _checkpointRepo = CheckpointRepository();
  final NavigationLayerCopyService _layerCopyService = NavigationLayerCopyService();
  final RoutesDistributionService _distributionService = RoutesDistributionService();

  List<Checkpoint> _checkpoints = [];
  NavigationTree? _tree;
  bool _isLoading = false;

  // הגדרות
  String _navigationType = 'regular';
  String _executionOrder = 'sequential';
  double _minRouteLength = 5.0;
  double _maxRouteLength = 15.0;
  int _checkpointsPerNavigator = 5;
  String? _startPointId;
  String? _endPointId;

  // נקודות ביניים
  bool _waypointsEnabled = false;
  List<WaypointCheckpoint> _waypoints = [];

  @override
  void initState() {
    super.initState();
    _loadData();
    _initializeFromNavigation();
  }

  void _initializeFromNavigation() {
    setState(() {
      _navigationType = widget.navigation.navigationType ?? 'regular';
      _executionOrder = widget.navigation.executionOrder ?? 'sequential';
      if (widget.navigation.routeLengthKm != null) {
        _minRouteLength = widget.navigation.routeLengthKm!.min;
        _maxRouteLength = widget.navigation.routeLengthKm!.max;
      }
      _checkpointsPerNavigator = widget.navigation.checkpointsPerNavigator ?? 5;
      _startPointId = widget.navigation.startPoint;
      _endPointId = widget.navigation.endPoint;

      // נקודות ביניים
      _waypointsEnabled = widget.navigation.waypointSettings.enabled;
      _waypoints = List.from(widget.navigation.waypointSettings.waypoints);
    });
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // טעינת נקודות ציון מהשכבות הניווטיות (כבר מסוננות לפי גבול גזרה)
      var navCheckpoints = await _navLayerRepo.getCheckpointsByNavigation(
        widget.navigation.id,
      );

      // אם אין נקודות ניווטיות — ננסה להעתיק שכבות מהשטח
      if (navCheckpoints.isEmpty) {
        print('DEBUG: No nav checkpoints found, attempting to copy layers from area');
        await _layerCopyService.copyLayersForNavigation(
          navigationId: widget.navigation.id,
          boundaryId: widget.navigation.boundaryLayerId ?? '',
          areaId: widget.navigation.areaId,
          createdBy: '',
        );
        // ניסיון חוזר לטעינה
        navCheckpoints = await _navLayerRepo.getCheckpointsByNavigation(
          widget.navigation.id,
        );
      }

      // אם עדיין אין — טעינה ישירה מנקודות השטח
      List<Checkpoint> checkpoints;
      if (navCheckpoints.isEmpty) {
        print('DEBUG: Still no nav checkpoints, loading area checkpoints directly');
        checkpoints = await _checkpointRepo.getByArea(widget.navigation.areaId);
        print('DEBUG: Loaded ${checkpoints.length} area checkpoints as fallback');
      } else {
        // המרה ל-Checkpoint עם sourceId כ-ID (תאימות לאחור)
        checkpoints = navCheckpoints.map((nc) => Checkpoint(
          id: nc.sourceId,
          areaId: nc.areaId,
          name: nc.name,
          description: nc.description,
          type: nc.type,
          color: nc.color,
          coordinates: nc.coordinates,
          sequenceNumber: nc.sequenceNumber,
          labels: nc.labels,
          createdBy: nc.createdBy,
          createdAt: nc.createdAt,
        )).toList();
      }

      // טעינת עץ מבנה
      final tree = await _treeRepo.getById(widget.navigation.treeId);

      setState(() {
        _checkpoints = checkpoints;
        _tree = tree;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה בטעינת נתונים: $e')),
        );
      }
    }
  }

  Future<void> _distribute() async {
    if (!_formKey.currentState!.validate()) return;
    if (_tree == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('לא נטען עץ מבנה')),
      );
      return;
    }

    // וידוא נקודות התחלה וסיום
    if (_navigationType == 'star') {
      if (_startPointId == null || _endPointId == null || _startPointId != _endPointId) {
        final result = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('ניווט כוכב'),
            content: const Text(
              'בניווט כוכב, נקודת ההתחלה והסיום צריכות להיות זהות.\n'
              'האם לקבוע את נקודת ההתחלה גם כנקודת סיום?'
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('ביטול'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('אישור'),
              ),
            ],
          ),
        );

        if (result != true) return;
        setState(() => _endPointId = _startPointId);
      }
    }

    setState(() => _isLoading = true);

    try {
      // חלוקה אוטומטית (הנקודות כבר מסוננות לפי גבול גזרה)
      final routes = await _distributionService.distributeAutomatically(
        navigation: widget.navigation,
        tree: _tree!,
        checkpoints: _checkpoints,
        boundary: null,
        startPointId: _startPointId,
        endPointId: _endPointId,
        executionOrder: _executionOrder,
        checkpointsPerNavigator: _checkpointsPerNavigator,
        minRouteLength: _minRouteLength,
        maxRouteLength: _maxRouteLength,
      );

      // עדכון ניווט עם הצירים החדשים
      final updatedNavigation = widget.navigation.copyWith(
        routes: routes,
        routesStage: 'verification',
        routesDistributed: true,
        navigationType: _navigationType,
        executionOrder: _executionOrder,
        routeLengthKm: domain.RouteLengthRange(
          min: _minRouteLength,
          max: _maxRouteLength,
        ),
        checkpointsPerNavigator: _checkpointsPerNavigator,
        startPoint: _startPointId,
        endPoint: _endPointId,
        waypointSettings: WaypointSettings(
          enabled: _waypointsEnabled,
          waypoints: _waypoints,
        ),
        updatedAt: DateTime.now(),
      );

      await _navRepo.update(updatedNavigation);

      if (mounted) {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => RoutesVerificationScreen(navigation: updatedNavigation),
          ),
        );
        if (result == true && mounted) {
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה בחלוקה: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('חלוקה אוטומטית'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'הגדרות חלוקה',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // סוג ניווט
                    _buildNavigationTypeSection(),
                    const SizedBox(height: 16),

                    // אופן ביצוע
                    _buildExecutionOrderSection(),
                    const SizedBox(height: 16),

                    // טווח אורך ציר
                    _buildRouteLengthSection(),
                    const SizedBox(height: 16),

                    // כמות נקודות למנווט
                    _buildCheckpointsPerNavigatorSection(),
                    const SizedBox(height: 16),

                    // נקודות התחלה וסיום
                    _buildStartEndPointsSection(),
                    const SizedBox(height: 16),

                    // נקודות ביניים
                    _buildWaypointsSection(),
                    const SizedBox(height: 24),

                    // אשכולות/ביצים (בפיתוח)
                    if (_navigationType == 'clusters' || _navigationType == 'eggs')
                      _buildClustersSection(),

                    const SizedBox(height: 32),

                    // כפתור חלוקה
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _distribute,
                        icon: const Icon(Icons.auto_awesome),
                        label: const Text('חלק אוטומטית'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildNavigationTypeSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'סוג ניווט',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _navigationType,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'בחר סוג',
              ),
              items: const [
                DropdownMenuItem(value: 'regular', child: Text('רגיל')),
                DropdownMenuItem(value: 'star', child: Text('כוכב')),
                DropdownMenuItem(value: 'reverse', child: Text('הפוך')),
                DropdownMenuItem(value: 'parachute', child: Text('צנחנים')),
                DropdownMenuItem(value: 'clusters', child: Text('אשכולות')),
                DropdownMenuItem(value: 'developing', child: Text('מפתח')),
              ],
              onChanged: (value) {
                setState(() => _navigationType = value!);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExecutionOrderSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'אופן ביצוע',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            RadioListTile<String>(
              title: const Text('לפי סדר הנקודות'),
              subtitle: const Text('המנווט חייב לעבור בנקודות לפי הסדר'),
              value: 'sequential',
              groupValue: _executionOrder,
              onChanged: (value) {
                setState(() => _executionOrder = value!);
              },
            ),
            RadioListTile<String>(
              title: const Text('לפי בחירת המנווט'),
              subtitle: const Text('המנווט יכול לבחור את סדר הנקודות'),
              value: 'navigator_choice',
              groupValue: _executionOrder,
              onChanged: (value) {
                setState(() => _executionOrder = value!);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRouteLengthSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'טווח אורך ציר (ק"מ)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: _minRouteLength.toString(),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'מינימום',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) return 'שדה חובה';
                      final num = double.tryParse(value);
                      if (num == null || num <= 0) return 'מספר חיובי';
                      return null;
                    },
                    onChanged: (value) {
                      _minRouteLength = double.tryParse(value) ?? _minRouteLength;
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    initialValue: _maxRouteLength.toString(),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'מקסימום',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) return 'שדה חובה';
                      final num = double.tryParse(value);
                      if (num == null || num <= 0) return 'מספר חיובי';
                      if (num < _minRouteLength) return 'גדול ממינימום';
                      return null;
                    },
                    onChanged: (value) {
                      _maxRouteLength = double.tryParse(value) ?? _maxRouteLength;
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckpointsPerNavigatorSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'כמות נקודות ציון למנווט',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: _checkpointsPerNavigator.toString(),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'מספר נקודות (1-10)',
                helperText: 'כל מנווט יקבל אותו מספר נקודות',
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value == null || value.isEmpty) return 'שדה חובה';
                final num = int.tryParse(value);
                if (num == null || num < 1 || num > 10) return 'בין 1 ל-10';
                return null;
              },
              onChanged: (value) {
                _checkpointsPerNavigator = int.tryParse(value) ?? _checkpointsPerNavigator;
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStartEndPointsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'נקודות התחלה וסיום',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: 'נקודות משותפות לכל המנווטים',
                  child: Icon(Icons.info_outline, size: 18, color: Colors.grey[600]),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // נקודת התחלה
            DropdownButtonFormField<String>(
              value: _startPointId,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'נקודת התחלה (משותפת)',
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('בחר נקודה')),
                ..._checkpoints.map((cp) => DropdownMenuItem(
                  value: cp.id,
                  child: Text('${cp.name} (${cp.sequenceNumber})'),
                )),
              ],
              onChanged: (value) {
                setState(() => _startPointId = value);
              },
            ),
            const SizedBox(height: 12),

            // נקודת סיום
            DropdownButtonFormField<String>(
              value: _endPointId,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'נקודת סיום (משותפת)',
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('בחר נקודה')),
                ..._checkpoints.map((cp) => DropdownMenuItem(
                  value: cp.id,
                  child: Text('${cp.name} (${cp.sequenceNumber})'),
                )),
              ],
              onChanged: (value) {
                setState(() => _endPointId = value);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWaypointsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'נקודות ביניים (נ.צ. משותפות)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Switch(
                  value: _waypointsEnabled,
                  onChanged: (value) {
                    setState(() => _waypointsEnabled = value);
                  },
                ),
              ],
            ),
            if (_waypointsEnabled) ...[
              const SizedBox(height: 8),
              Text(
                'נקודות ציון שכל המנווטים יעברו בהן',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 16),

              // רשימת נקודות ביניים
              ..._waypoints.asMap().entries.map((entry) {
                final index = entry.key;
                final waypoint = entry.value;
                return _buildWaypointCard(index, waypoint);
              }),

              const SizedBox(height: 12),

              // כפתור הוספת נקודת ביניים
              OutlinedButton.icon(
                onPressed: _addWaypoint,
                icon: const Icon(Icons.add),
                label: const Text('הוסף נקודת ביניים'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.blue,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildWaypointCard(int index, WaypointCheckpoint waypoint) {
    // מציאת נקודת הציון
    final checkpoint = _checkpoints.firstWhere(
      (cp) => cp.id == waypoint.checkpointId,
      orElse: () => _checkpoints.first,
    );

    return Card(
      color: Colors.blue[50],
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'נקודת ביניים ${index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete, size: 20),
                  onPressed: () => _removeWaypoint(index),
                  color: Colors.red,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // בחירת נקודת ציון
            DropdownButtonFormField<String>(
              value: waypoint.checkpointId,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'בחר נקודת ציון',
                filled: true,
                fillColor: Colors.white,
              ),
              items: _checkpoints.map((cp) => DropdownMenuItem(
                value: cp.id,
                child: Text('${cp.name} (${cp.sequenceNumber})'),
              )).toList(),
              onChanged: (value) {
                if (value != null) {
                  _updateWaypointCheckpoint(index, value);
                }
              },
            ),
            const SizedBox(height: 12),

            // סוג מיקום לבניית צירים
            DropdownButtonFormField<String>(
              value: waypoint.placementType,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'הגדרות לבניית צירים',
                filled: true,
                fillColor: Colors.white,
              ),
              items: const [
                DropdownMenuItem(
                  value: 'distance',
                  child: Text('לפי מרחק'),
                ),
                DropdownMenuItem(
                  value: 'between_checkpoints',
                  child: Text('בין נקודות ספציפיות'),
                ),
              ],
              onChanged: (value) => _updateWaypointPlacementType(index, value!),
            ),
            const SizedBox(height: 12),

            // שדות לפי סוג
            if (waypoint.placementType == 'distance')
              TextFormField(
                initialValue: waypoint.afterDistanceKm?.toString() ?? '5.0',
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'לעבור בה אחרי',
                  suffixText: 'ק"מ',
                  filled: true,
                  fillColor: Colors.white,
                ),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  final km = double.tryParse(value);
                  if (km != null) {
                    _updateWaypointDistance(index, km);
                  }
                },
              )
            else if (waypoint.placementType == 'between_checkpoints')
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: waypoint.afterCheckpointIndex != null
                          ? (waypoint.afterCheckpointIndex! + 1).toString()
                          : '',
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'אחרי נ.צ. מס׳',
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (value) {
                        final num = int.tryParse(value);
                        if (num != null && num > 0) {
                          _updateWaypointAfter(index, num - 1);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      initialValue: waypoint.beforeCheckpointIndex != null
                          ? (waypoint.beforeCheckpointIndex! + 1).toString()
                          : '',
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'לפני נ.צ. מס׳',
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (value) {
                        final num = int.tryParse(value);
                        if (num != null && num > 0) {
                          _updateWaypointBefore(index, num - 1);
                        }
                      },
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  void _addWaypoint() {
    if (_checkpoints.isEmpty) return;
    setState(() {
      _waypoints.add(WaypointCheckpoint(
        checkpointId: _checkpoints.first.id,
        placementType: 'distance',
        afterDistanceKm: 5.0,
      ));
    });
  }

  void _removeWaypoint(int index) {
    setState(() {
      _waypoints.removeAt(index);
    });
  }

  void _updateWaypointCheckpoint(int index, String checkpointId) {
    setState(() {
      final current = _waypoints[index];
      _waypoints[index] = current.copyWith(checkpointId: checkpointId);
    });
  }

  void _updateWaypointPlacementType(int index, String type) {
    setState(() {
      final current = _waypoints[index];
      _waypoints[index] = WaypointCheckpoint(
        checkpointId: current.checkpointId,
        placementType: type,
        afterDistanceKm: type == 'distance' ? (current.afterDistanceKm ?? 5.0) : null,
        afterCheckpointIndex: type == 'between_checkpoints' ? (current.afterCheckpointIndex ?? 0) : null,
        beforeCheckpointIndex: type == 'between_checkpoints' ? (current.beforeCheckpointIndex ?? 1) : null,
      );
    });
  }

  void _updateWaypointDistance(int index, double km) {
    setState(() {
      final current = _waypoints[index];
      _waypoints[index] = current.copyWith(afterDistanceKm: km);
    });
  }

  void _updateWaypointAfter(int index, int afterIndex) {
    setState(() {
      final current = _waypoints[index];
      _waypoints[index] = current.copyWith(afterCheckpointIndex: afterIndex);
    });
  }

  void _updateWaypointBefore(int index, int beforeIndex) {
    setState(() {
      final current = _waypoints[index];
      _waypoints[index] = current.copyWith(beforeCheckpointIndex: beforeIndex);
    });
  }

  Widget _buildClustersSection() {
    return Card(
      color: Colors.amber[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(Icons.construction, size: 48, color: Colors.amber[700]),
            const SizedBox(height: 8),
            const Text(
              'אשכולות / ביצים',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'תכונה בפיתוח',
              style: TextStyle(color: Colors.amber[700]),
            ),
          ],
        ),
      ),
    );
  }
}
