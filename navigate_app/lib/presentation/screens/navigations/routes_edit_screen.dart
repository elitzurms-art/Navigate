import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../domain/entities/navigation.dart' as domain;
import '../../../domain/entities/checkpoint.dart';
import '../../../domain/entities/coordinate.dart';
import '../../../domain/entities/user.dart';
import '../../../data/repositories/nav_layer_repository.dart';
import '../../../data/repositories/navigation_repository.dart';
import '../../../data/repositories/checkpoint_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../services/navigation_layer_copy_service.dart';
import '../../../core/utils/geometry_utils.dart';
import '../../widgets/map_with_selector.dart';
import '../../widgets/fullscreen_map_screen.dart';
import '../../widgets/map_controls.dart';
import '../../../core/map_config.dart';

/// שלב 4 - עריכת צירים (UI משודרג עם מפה, drag & drop, bottom sheet)
class RoutesEditScreen extends StatefulWidget {
  final domain.Navigation navigation;

  const RoutesEditScreen({super.key, required this.navigation});

  @override
  State<RoutesEditScreen> createState() => _RoutesEditScreenState();
}

class _RoutesEditScreenState extends State<RoutesEditScreen> {
  final NavLayerRepository _navLayerRepo = NavLayerRepository();
  final NavigationRepository _navRepo = NavigationRepository();
  final CheckpointRepository _checkpointRepo = CheckpointRepository();
  final NavigationLayerCopyService _layerCopyService = NavigationLayerCopyService();
  final UserRepository _userRepo = UserRepository();
  final MapController _mapController = MapController();

  // Data
  List<Checkpoint> _checkpoints = [];
  List<String> _navigatorIds = [];
  Map<String, User> _usersCache = {};

  // Shared points (read-only in this screen)
  String? _startPointId;
  String? _endPointId;
  List<String> _intermediatePointIds = [];

  // Per-navigator assignments: uid → [checkpointIds in order]
  Map<String, List<String>> _navigatorCheckpoints = {};

  // UI state
  String? _expandedNavigatorId;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // טעינת נקודות ציון
      var navCheckpoints = await _navLayerRepo.getCheckpointsByNavigation(
        widget.navigation.id,
      );

      if (navCheckpoints.isEmpty) {
        await _layerCopyService.copyLayersForNavigation(
          navigationId: widget.navigation.id,
          boundaryId: widget.navigation.boundaryLayerId ?? '',
          areaId: widget.navigation.areaId,
          createdBy: '',
        );
        navCheckpoints = await _navLayerRepo.getCheckpointsByNavigation(
          widget.navigation.id,
        );
      }

      List<Checkpoint> checkpoints;
      if (navCheckpoints.isEmpty) {
        checkpoints = await _checkpointRepo.getByArea(widget.navigation.areaId);
      } else {
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

      // אתחול מ-routes קיימים
      final routes = widget.navigation.routes;
      final navigatorIds = routes.keys.toList();

      // טעינת פרטי משתמשים
      final usersCache = <String, User>{};
      for (final uid in navigatorIds) {
        final user = await _userRepo.getUser(uid);
        if (user != null) {
          usersCache[uid] = user;
        }
      }

      // אתחול הקצאות מנווטים מ-routes קיימים
      final navigatorCheckpoints = <String, List<String>>{};
      String? startPointId;
      String? endPointId;
      List<String> intermediatePointIds = [];

      for (final entry in routes.entries) {
        navigatorCheckpoints[entry.key] = List.from(entry.value.checkpointIds);
        startPointId ??= entry.value.startPointId;
        endPointId ??= entry.value.endPointId;
        if (entry.value.waypointIds.isNotEmpty && intermediatePointIds.isEmpty) {
          intermediatePointIds = List.from(entry.value.waypointIds);
        }
      }

      // fallback מהגדרות ניווט
      startPointId ??= widget.navigation.startPoint;
      endPointId ??= widget.navigation.endPoint;
      if (intermediatePointIds.isEmpty && widget.navigation.waypointSettings.enabled) {
        intermediatePointIds = widget.navigation.waypointSettings.waypoints
            .map((w) => w.checkpointId)
            .toList();
      }

      setState(() {
        _checkpoints = checkpoints;
        _navigatorIds = navigatorIds;
        _usersCache = usersCache;
        _navigatorCheckpoints = navigatorCheckpoints;
        _startPointId = startPointId;
        _endPointId = endPointId;
        _intermediatePointIds = intermediatePointIds;
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

  // ===================== HELPERS =====================

  Checkpoint? _getCheckpoint(String id) {
    try {
      return _checkpoints.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  String _getNavigatorName(String uid) {
    final user = _usersCache[uid];
    if (user != null) return '${user.fullName} (${user.uid})';
    return uid;
  }

  /// בניית רצף סופי: התחלה → [רשימת המנווט] → סיום
  List<String> _buildFullSequence(List<String> navigatorCps) {
    if (navigatorCps.isEmpty) return [];
    final result = <String>[];
    if (_startPointId != null) result.add(_startPointId!);
    result.addAll(navigatorCps);
    if (_endPointId != null) result.add(_endPointId!);
    return result;
  }

  /// חישוב אורך ציר בק"מ
  double _calculateRouteLength(List<String> sequence) {
    final coords = <Coordinate>[];
    for (final cpId in sequence) {
      final cp = _getCheckpoint(cpId);
      if (cp?.coordinates != null) {
        coords.add(cp!.coordinates!);
      }
    }
    return GeometryUtils.calculatePathLengthKm(coords);
  }

  /// קביעת סטטוס ציר לפי טווח אורך
  String _getRouteStatus(double lengthKm) {
    final range = widget.navigation.routeLengthKm;
    if (range == null) return 'optimal';
    if (lengthKm < range.min) return 'too_short';
    if (lengthKm > range.max) return 'too_long';
    return 'optimal';
  }

  /// ספירת כמה מנווטים קיבלו נקודה מסוימת
  int _getCheckpointAssignmentCount(String checkpointId, {String? currentNavigatorId, Set<String>? currentSelected}) {
    int count = 0;
    for (final entry in _navigatorCheckpoints.entries) {
      if (entry.key == currentNavigatorId) continue;
      if (entry.value.contains(checkpointId)) count++;
    }
    if (currentSelected != null && currentSelected.contains(checkpointId)) count++;
    return count;
  }

  // ===================== BOTTOM SHEET — בחירת נקודות למנווט =====================

  void _showCheckpointSelector(String navigatorId) {
    final selected = Set<String>.from(_navigatorCheckpoints[navigatorId] ?? []);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            // סינון נקודות: לא כולל התחלה/סיום/ביניים
            final excludedIds = <String>{
              if (_startPointId != null) _startPointId!,
              if (_endPointId != null) _endPointId!,
              ..._intermediatePointIds,
            };
            final availableCheckpoints = _checkpoints
                .where((c) => !excludedIds.contains(c.id))
                .toList();

            return DraggableScrollableSheet(
              initialChildSize: 0.7,
              minChildSize: 0.4,
              maxChildSize: 0.9,
              expand: false,
              builder: (_, scrollController) {
                return Column(
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(16),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'בחירת נקודות — ${_getNavigatorName(navigatorId)}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Text(
                            '${selected.length} נבחרו',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _navigatorCheckpoints[navigatorId] =
                                    selected.toList();
                              });
                              Navigator.pop(ctx);
                            },
                            child: const Text('אישור'),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    // Checkpoint list
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: availableCheckpoints.length,
                        itemBuilder: (_, index) {
                          final cp = availableCheckpoints[index];
                          final isSelected = selected.contains(cp.id);
                          final assignCount = _getCheckpointAssignmentCount(
                            cp.id,
                            currentNavigatorId: navigatorId,
                            currentSelected: selected,
                          );

                          return CheckboxListTile(
                            value: isSelected,
                            onChanged: (val) {
                              setSheetState(() {
                                if (val == true) {
                                  selected.add(cp.id);
                                } else {
                                  selected.remove(cp.id);
                                }
                              });
                            },
                            title: Text(
                              '${cp.sequenceNumber}. ${cp.name}',
                              style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            subtitle: assignCount > 0
                                ? Text(
                                    '$assignCount מנווטים קיבלו',
                                    style: TextStyle(
                                      color: Colors.orange[700],
                                      fontSize: 12,
                                    ),
                                  )
                                : cp.description.isNotEmpty
                                    ? Text(
                                        cp.description,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      )
                                    : null,
                            secondary: assignCount > 0
                                ? CircleAvatar(
                                    radius: 14,
                                    backgroundColor: Colors.orange[100],
                                    child: Text(
                                      '$assignCount',
                                      style: TextStyle(
                                        color: Colors.orange[800],
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  )
                                : null,
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  // ===================== MAP =====================

  List<Marker> _buildMarkers({String? navigatorId}) {
    final markers = <Marker>[];
    final sequence = navigatorId != null
        ? _buildFullSequence(_navigatorCheckpoints[navigatorId] ?? [])
        : null;
    final sequenceSet = sequence?.toSet();

    for (final cp in _checkpoints) {
      if (cp.coordinates == null) continue;
      final isStart = cp.id == _startPointId;
      final isEnd = cp.id == _endPointId;
      final isIntermediate = _intermediatePointIds.contains(cp.id);
      final isInSequence = sequenceSet?.contains(cp.id) ?? false;

      Color bgColor;
      String letter;
      if (isStart) {
        bgColor = const Color(0xFF4CAF50);
        letter = 'H';
      } else if (isEnd) {
        bgColor = const Color(0xFFF44336);
        letter = 'S';
      } else if (isIntermediate) {
        bgColor = const Color(0xFFFFC107);
        letter = 'B';
      } else if (navigatorId == null || isInSequence) {
        bgColor = Colors.blue;
        letter = '';
      } else {
        bgColor = Colors.grey;
        letter = '';
      }
      final label = letter.isNotEmpty
          ? '${cp.sequenceNumber}$letter'
          : '${cp.sequenceNumber}';

      markers.add(Marker(
        point: cp.coordinates!.toLatLng(),
        width: 38,
        height: 38,
        child: Container(
          decoration: BoxDecoration(
            color: bgColor,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 4,
              ),
            ],
          ),
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ));
    }
    return markers;
  }

  static const _nonRedRouteColors = [
    Color(0xFF2196F3),
    Color(0xFF4CAF50),
    Color(0xFF9C27B0),
    Color(0xFFFF9800),
    Color(0xFF00BCD4),
    Color(0xFF795548),
    Color(0xFF3F51B5),
    Color(0xFF009688),
    Color(0xFF8BC34A),
    Color(0xFFE91E63),
  ];

  List<Polyline> _buildPolylines({String? selectedNavigatorId}) {
    final polylines = <Polyline>[];
    int colorIdx = 0;

    for (final uid in _navigatorIds) {
      final cps = _navigatorCheckpoints[uid] ?? [];
      if (cps.isEmpty) continue;
      final seq = _buildFullSequence(cps);
      final points = <LatLng>[];
      for (final cpId in seq) {
        final cp = _getCheckpoint(cpId);
        if (cp?.coordinates != null) {
          points.add(cp!.coordinates!.toLatLng());
        }
      }
      if (points.length < 2) continue;

      final isSelected = uid == selectedNavigatorId;
      polylines.add(Polyline(
        points: points,
        color: isSelected
            ? Colors.red
            : _nonRedRouteColors[colorIdx % _nonRedRouteColors.length].withValues(alpha: 0.6),
        strokeWidth: isSelected ? 4.0 : 2.5,
      ));
      if (!isSelected) colorIdx++;
    }
    return polylines;
  }

  LatLngBounds? _getMapBounds() {
    final allCoords = _checkpoints
        .where((c) => c.coordinates != null)
        .map((c) => c.coordinates!.toLatLng())
        .toList();
    if (allCoords.isEmpty) return null;
    return LatLngBounds.fromPoints(allCoords);
  }

  // ===================== SAVE =====================

  Future<void> _saveChanges() async {
    setState(() => _isSaving = true);

    try {
      final routes = <String, domain.AssignedRoute>{};
      final mandatorySet = _intermediatePointIds.toSet();

      for (final uid in _navigatorIds) {
        final cps = _navigatorCheckpoints[uid] ?? [];
        final manualCps = cps.where((c) => !mandatorySet.contains(c)).toList();

        final sequence = _buildFullSequence(cps);
        final lengthKm = _calculateRouteLength(sequence);
        final status = _getRouteStatus(lengthKm);

        // שמירת ה-route הקיים עם עדכון הנקודות
        final existingRoute = widget.navigation.routes[uid];
        routes[uid] = domain.AssignedRoute(
          checkpointIds: manualCps,
          routeLengthKm: lengthKm,
          sequence: sequence,
          startPointId: _startPointId,
          endPointId: _endPointId,
          waypointIds: _intermediatePointIds,
          status: status,
          isVerified: false,
          approvalStatus: existingRoute?.approvalStatus ?? 'not_submitted',
          plannedPath: existingRoute?.plannedPath ?? const [],
          narrationEntries: existingRoute?.narrationEntries ?? const [],
        );
      }

      final updatedNavigation = widget.navigation.copyWith(
        routes: routes,
        routesStage: 'verification',
        updatedAt: DateTime.now(),
      );

      await _navRepo.update(updatedNavigation);

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('שינויים נשמרו')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה בשמירה: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ===================== BUILD =====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('עריכת צירים'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _navigatorIds.isEmpty
              ? const Center(child: Text('אין צירים'))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildSharedPointsReadOnly(),
                      const SizedBox(height: 16),
                      _buildNavigatorsSection(),
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
      bottomNavigationBar: _isLoading
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _saveChanges,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: Text(_isSaving ? 'שומר...' : 'שמור שינויים'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  // ===================== SECTION 1: נקודות משותפות (קריאה בלבד) =====================

  Widget _buildSharedPointsReadOnly() {
    final hasSharedPoints = _startPointId != null ||
        _endPointId != null ||
        _intermediatePointIds.isNotEmpty;

    if (!hasSharedPoints) return const SizedBox.shrink();

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.route, color: Colors.orange[700]),
                const SizedBox(width: 8),
                const Text(
                  'נקודות מסלול משותפות',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // נקודת התחלה
            if (_startPointId != null)
              _buildReadOnlyPoint(
                icon: Icons.play_arrow,
                color: Colors.green,
                label: 'התחלה',
                checkpoint: _getCheckpoint(_startPointId!),
              ),

            // נקודת סיום
            if (_endPointId != null) ...[
              const SizedBox(height: 8),
              _buildReadOnlyPoint(
                icon: Icons.stop,
                color: Colors.red,
                label: 'סיום',
                checkpoint: _getCheckpoint(_endPointId!),
              ),
            ],

            // נקודות ביניים
            if (_intermediatePointIds.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.more_horiz, color: Colors.purple[400], size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'נקודות ביניים (${_intermediatePointIds.length})',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: _intermediatePointIds.map((cpId) {
                  final cp = _getCheckpoint(cpId);
                  return Chip(
                    label: Text(cp?.name ?? cpId),
                    backgroundColor: Colors.purple.shade50,
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildReadOnlyPoint({
    required IconData icon,
    required Color color,
    required String label,
    Checkpoint? checkpoint,
  }) {
    return Row(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        Expanded(
          child: Text(
            checkpoint != null
                ? '${checkpoint.sequenceNumber}. ${checkpoint.name}'
                : 'לא נמצא',
            style: TextStyle(color: Colors.grey[700]),
          ),
        ),
      ],
    );
  }

  // ===================== SECTION 2: רשימת מנווטים =====================

  Widget _buildNavigatorsSection() {
    if (_navigatorIds.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'לא נמצאו מנווטים',
            style: TextStyle(color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final mandatorySet = _intermediatePointIds.toSet();
    final assignedCount = _navigatorIds
        .where((uid) {
          final cps = _navigatorCheckpoints[uid] ?? [];
          return cps.any((c) => !mandatorySet.contains(c));
        })
        .length;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.people, color: Colors.orange[700]),
                const SizedBox(width: 8),
                Text(
                  'מנווטים ($assignedCount/${_navigatorIds.length} חולקו)',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final uid in _navigatorIds) ...[
              _buildNavigatorTile(uid),
              if (_expandedNavigatorId == uid)
                _buildInlineMap(uid),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNavigatorTile(String uid) {
    final cps = _navigatorCheckpoints[uid] ?? [];
    final isExpanded = _expandedNavigatorId == uid;
    final mandatorySet = _intermediatePointIds.toSet();
    final manualCount = cps.where((c) => !mandatorySet.contains(c)).length;
    final hasCheckpoints = manualCount > 0;
    final sequence = cps.isNotEmpty ? _buildFullSequence(cps) : <String>[];
    final lengthKm = cps.isNotEmpty ? _calculateRouteLength(sequence) : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(
          color: hasCheckpoints ? Colors.green.shade200 : Colors.grey.shade300,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          // Header
          InkWell(
            onTap: () {
              setState(() {
                _expandedNavigatorId = isExpanded ? null : uid;
              });
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    hasCheckpoints ? Icons.check_circle : Icons.circle_outlined,
                    color: hasCheckpoints ? Colors.green : Colors.grey,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _getNavigatorName(uid),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if (cps.isNotEmpty)
                          Text(
                            '$manualCount נקודות${_intermediatePointIds.isNotEmpty ? ' + ${_intermediatePointIds.length} חובה' : ''} · ${lengthKm.toStringAsFixed(1)} ק"מ',
                            style: TextStyle(
                              fontSize: 12,
                              color: hasCheckpoints ? Colors.grey[600] : Colors.orange[400],
                            ),
                          ),
                      ],
                    ),
                  ),
                  // כפתור בחירת נקודות
                  IconButton(
                    icon: const Icon(Icons.checklist, size: 20),
                    tooltip: 'בחר נקודות',
                    onPressed: () => _showCheckpointSelector(uid),
                  ),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.grey,
                  ),
                ],
              ),
            ),
          ),
          // Expanded content — ReorderableListView
          if (isExpanded && cps.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ReorderableListView.builder(
                shrinkWrap: true,
                buildDefaultDragHandles: false,
                itemCount: cps.length,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (newIndex > oldIndex) newIndex -= 1;
                    final item = cps.removeAt(oldIndex);
                    cps.insert(newIndex, item);
                  });
                },
                itemBuilder: (_, index) {
                  final cpId = cps[index];
                  final cp = _getCheckpoint(cpId);
                  final isMandatory = _intermediatePointIds.contains(cpId);
                  return ListTile(
                    key: ValueKey('$uid-$cpId'),
                    dense: true,
                    leading: ReorderableDragStartListener(
                      index: index,
                      child: const Icon(Icons.drag_handle, size: 20),
                    ),
                    title: Text(
                      '${index + 1}. ${cp?.name ?? cpId}',
                      style: TextStyle(
                        fontSize: 14,
                        color: isMandatory ? Colors.purple[700] : null,
                        fontWeight: isMandatory ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    subtitle: isMandatory
                        ? Text('נקודת ביניים (חובה)',
                            style: TextStyle(fontSize: 11, color: Colors.purple[400]))
                        : null,
                    trailing: isMandatory
                        ? Icon(Icons.lock, size: 14, color: Colors.purple[300])
                        : IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: () {
                              setState(() => cps.removeAt(index));
                            },
                          ),
                  );
                },
              ),
            ),
          if (isExpanded && cps.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'לא נבחרו נקודות — לחץ על הכפתור לבחירה',
                style: TextStyle(color: Colors.grey[500], fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }

  // ===================== INLINE MAP =====================

  Widget _buildInlineMap(String navigatorId) {
    final bounds = _getMapBounds();
    if (bounds == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'אין נקודות עם קואורדינטות',
          style: TextStyle(color: Colors.grey[500], fontSize: 13),
          textAlign: TextAlign.center,
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.orange.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          height: 300,
          child: Stack(
            children: [
              MapWithTypeSelector(
                mapController: _mapController,
                initialMapType: MapConfig.resolveMapType(widget.navigation.displaySettings.defaultMap),
                options: MapOptions(
                  initialCameraFit: CameraFit.bounds(
                    bounds: bounds,
                    padding: const EdgeInsets.all(40),
                  ),
                ),
                layers: [
                  PolylineLayer(polylines: _buildPolylines(selectedNavigatorId: navigatorId)),
                  MarkerLayer(markers: _buildMarkers(navigatorId: navigatorId)),
                ],
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Material(
                  color: Colors.white,
                  elevation: 2,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      final camera = _mapController.camera;
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => FullscreenMapScreen(
                          title: 'עריכת צירים',
                          initialCenter: camera.center,
                          initialZoom: camera.zoom,
                          layerConfigs: [
                            MapLayerConfig(id: 'routes', label: 'צירים', color: Colors.orange, visible: true, onVisibilityChanged: (_) {}),
                            MapLayerConfig(id: 'checkpoints', label: 'נקודות ציון', color: Colors.blue, visible: true, onVisibilityChanged: (_) {}),
                          ],
                          layerBuilder: (visibility, opacity) => [
                            if (visibility['routes'] == true)
                              PolylineLayer(polylines: _buildPolylines(selectedNavigatorId: navigatorId)),
                            if (visibility['checkpoints'] == true)
                              MarkerLayer(markers: _buildMarkers(navigatorId: navigatorId)),
                          ],
                        ),
                      ));
                    },
                    child: const SizedBox(
                      width: 40, height: 40,
                      child: Icon(Icons.fullscreen, size: 22),
                    ),
                  ),
                ),
              ),
              // מקרא צבעים
              Positioned(
                bottom: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 12, height: 3, color: Colors.red),
                      const SizedBox(width: 4),
                      Text(
                        _usersCache[navigatorId]?.fullName ?? navigatorId,
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
