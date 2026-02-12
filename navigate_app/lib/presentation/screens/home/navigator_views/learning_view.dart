import 'dart:io';
import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:path_provider/path_provider.dart';
import '../../../../domain/entities/navigation.dart' as domain;
import '../../../../domain/entities/checkpoint.dart';
import '../../../../domain/entities/user.dart';
import '../../../../data/repositories/checkpoint_repository.dart';
import '../../../../data/repositories/navigation_repository.dart';
import '../../../widgets/map_with_selector.dart';
import 'route_editor_screen.dart';

/// תצוגת למידה למנווט — לשוניות דינמיות לפי LearningSettings
class LearningView extends StatefulWidget {
  final domain.Navigation navigation;
  final User currentUser;
  final ValueChanged<domain.Navigation> onNavigationUpdated;

  const LearningView({
    super.key,
    required this.navigation,
    required this.currentUser,
    required this.onNavigationUpdated,
  });

  @override
  State<LearningView> createState() => _LearningViewState();
}

class _LearningViewState extends State<LearningView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late List<_LearningTab> _tabs;
  final CheckpointRepository _checkpointRepo = CheckpointRepository();
  final NavigationRepository _navigationRepo = NavigationRepository();

  /// ניווט נוכחי — mutable, מתעדכן אחרי כל שמירה
  late domain.Navigation _currentNavigation;

  /// נקודות ציון טעונות לפי sequence — לשימוש במפה
  List<Checkpoint> _routeCheckpoints = [];
  bool _checkpointsLoaded = false;

  @override
  void initState() {
    super.initState();
    _currentNavigation = widget.navigation;
    _buildTabs();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _loadCheckpoints();
  }

  @override
  void didUpdateWidget(LearningView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _currentNavigation = widget.navigation;
    if (oldWidget.navigation.id != widget.navigation.id) {
      _buildTabs();
      _tabController.dispose();
      _tabController = TabController(length: _tabs.length, vsync: this);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _buildTabs() {
    final settings = widget.navigation.learningSettings;
    _tabs = [];

    if (settings.showNavigationDetails) {
      _tabs.add(_LearningTab(
        label: 'פרטי ניווט',
        icon: Icons.info_outline,
        builder: _buildDetailsTab,
      ));
    }

    if (settings.showRoutes) {
      _tabs.add(_LearningTab(
        label: 'הציר שלי',
        icon: Icons.route,
        builder: _buildRouteTab,
      ));
    }

    if (settings.allowRouteEditing) {
      _tabs.add(_LearningTab(
        label: 'עריכה ואישור',
        icon: Icons.edit,
        builder: _buildEditTab,
      ));
    }

    if (settings.allowRouteNarration) {
      _tabs.add(_LearningTab(
        label: 'סיפור דרך',
        icon: Icons.record_voice_over,
        builder: _buildNarrationTab,
      ));
    }

    // אם אין לשוניות בכלל, הוסף placeholder
    if (_tabs.isEmpty) {
      _tabs.add(_LearningTab(
        label: 'למידה',
        icon: Icons.school,
        builder: _buildEmptyTab,
      ));
    }
  }

  /// טעינת נקודות ציון של הציר לפי סדר ה-sequence
  Future<void> _loadCheckpoints() async {
    final route = widget.navigation.routes[widget.currentUser.uid];
    if (route == null || route.checkpointIds.isEmpty) {
      if (mounted) setState(() => _checkpointsLoaded = true);
      return;
    }

    try {
      final loaded = <Checkpoint>[];
      for (final cpId in route.sequence) {
        final cp = await _checkpointRepo.getById(cpId);
        if (cp != null) loaded.add(cp);
      }
      if (mounted) {
        setState(() {
          _routeCheckpoints = loaded;
          _checkpointsLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _checkpointsLoaded = true);
    }
  }

  // ===========================================================================
  // Tab builders
  // ===========================================================================

  Widget _buildDetailsTab() {
    final nav = widget.navigation;
    final route = nav.routes[widget.currentUser.uid];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _infoCard('שם ניווט', nav.name),
          _infoCard('שטח', nav.areaId),
          if (nav.boundaryLayerId != null)
            _infoCard('גבול גזרה', nav.boundaryLayerId!),
          if (nav.routeLengthKm != null)
            _infoCard(
              'מרחק ניווט',
              '${nav.routeLengthKm!.min.toStringAsFixed(1)} - ${nav.routeLengthKm!.max.toStringAsFixed(1)} ק"מ',
            ),
          if (route != null) ...[
            const SizedBox(height: 16),
            Text(
              'הציר שלי',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            _infoCard('מספר נקודות', '${route.checkpointIds.length}'),
            _infoCard('אורך ציר', '${route.routeLengthKm.toStringAsFixed(2)} ק"מ'),
            _infoCard('סטטוס', route.status),
          ],
        ],
      ),
    );
  }

  Widget _buildRouteTab() {
    final route = widget.navigation.routes[widget.currentUser.uid];

    if (route == null) {
      return const Center(child: Text('לא הוקצה ציר'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // מפת ציר
          _buildRouteMap(),
          const SizedBox(height: 16),
          Text(
            'נקודות הציר',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: route.sequence.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.blue,
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  title: Text(route.sequence[index]),
                  trailing: Icon(
                    index == 0
                        ? Icons.play_arrow
                        : index == route.sequence.length - 1
                            ? Icons.flag
                            : Icons.circle,
                    size: 16,
                    color: Colors.blue,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          _infoCard('אורך ציר', '${route.routeLengthKm.toStringAsFixed(2)} ק"מ'),
        ],
      ),
    );
  }

  /// בניית מפה עם נקודות ציון ו-polyline
  Widget _buildRouteMap() {
    if (!_checkpointsLoaded) {
      return const SizedBox(
        height: 250,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_routeCheckpoints.isEmpty) {
      return SizedBox(
        height: 250,
        child: Card(
          color: Colors.grey[100],
          child: const Center(child: Text('אין נתוני מיקום לנקודות')),
        ),
      );
    }

    final points = _routeCheckpoints
        .map((cp) => cp.coordinates.toLatLng())
        .toList();

    // חישוב bounds למיקוד המפה
    final bounds = LatLngBounds.fromPoints(points);

    final markers = <Marker>[];
    for (var i = 0; i < _routeCheckpoints.length; i++) {
      final cp = _routeCheckpoints[i];
      final isFirst = i == 0;
      final isLast = i == _routeCheckpoints.length - 1;

      markers.add(Marker(
        point: cp.coordinates.toLatLng(),
        width: 32,
        height: 32,
        child: Tooltip(
          message: cp.name,
          child: Container(
            decoration: BoxDecoration(
              color: isFirst
                  ? Colors.green
                  : isLast
                      ? Colors.red
                      : Colors.blue,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: Center(
              child: Text(
                '${i + 1}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ));
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 250,
        child: MapWithTypeSelector(
          options: MapOptions(
            initialCenter: bounds.center,
            initialZoom: 14.0,
            initialCameraFit: points.length > 1
                ? CameraFit.bounds(
                    bounds: bounds,
                    padding: const EdgeInsets.all(40),
                  )
                : null,
          ),
          layers: [
            if (points.length > 1)
              PolylineLayer(polylines: [
                Polyline(
                  points: points,
                  color: Colors.blue,
                  strokeWidth: 3.0,
                ),
              ]),
            MarkerLayer(markers: markers),
          ],
        ),
      ),
    );
  }

  void _openRouteEditor() {
    final route = _currentNavigation.routes[widget.currentUser.uid];
    if (route == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RouteEditorScreen(
          navigation: _currentNavigation,
          navigatorUid: widget.currentUser.uid,
          checkpoints: _routeCheckpoints,
          onNavigationUpdated: (updatedNav) {
            setState(() => _currentNavigation = updatedNav);
            widget.onNavigationUpdated(updatedNav);
          },
        ),
      ),
    );
  }

  Future<void> _approveRoute() async {
    final route = _currentNavigation.routes[widget.currentUser.uid];
    if (route == null) return;

    final updatedRoute = route.copyWith(isApproved: true);
    final updatedRoutes = Map<String, domain.AssignedRoute>.from(
      _currentNavigation.routes,
    );
    updatedRoutes[widget.currentUser.uid] = updatedRoute;

    final updatedNav = _currentNavigation.copyWith(
      routes: updatedRoutes,
      updatedAt: DateTime.now(),
    );

    try {
      await _navigationRepo.update(updatedNav);
      setState(() => _currentNavigation = updatedNav);
      widget.onNavigationUpdated(updatedNav);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('הציר אושר בהצלחה')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה באישור: $e')),
        );
      }
    }
  }

  Widget _buildEditTab() {
    final route = _currentNavigation.routes[widget.currentUser.uid];

    if (route == null) {
      return const Center(child: Text('לא הוקצה ציר'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // סטטוס אישור
          if (route.isApproved)
            Card(
              color: Colors.green[50],
              child: const ListTile(
                leading: Icon(Icons.check_circle, color: Colors.green),
                title: Text('הציר אושר'),
                subtitle: Text('שינויים נוספים ידרשו אישור מחדש'),
              ),
            )
          else
            Card(
              color: Colors.orange[50],
              child: const ListTile(
                leading: Icon(Icons.warning, color: Colors.orange),
                title: Text('הציר טרם אושר'),
                subtitle: Text('סקור את הציר ואשר לפני בדיקת מערכות'),
              ),
            ),
          const SizedBox(height: 16),

          // כפתור עריכת ציר על המפה
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _checkpointsLoaded ? _openRouteEditor : null,
              icon: const Icon(Icons.map),
              label: Text(
                route.plannedPath.isEmpty
                    ? 'ערוך ציר על המפה'
                    : 'ערוך ציר על המפה (${route.plannedPath.length} נקודות)',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // רשימת נקודות ציון
          Text(
            'סדר נקודות',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: route.sequence.length,
              itemBuilder: (context, index) {
                return ListTile(
                  leading: CircleAvatar(
                    radius: 14,
                    child: Text('${index + 1}', style: const TextStyle(fontSize: 12)),
                  ),
                  title: Text(route.sequence[index]),
                );
              },
            ),
          ),
          const SizedBox(height: 16),

          // כפתור אישור ציר
          if (!route.isApproved)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _approveRoute,
                icon: const Icon(Icons.check),
                label: const Text('אשר ציר'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _exportNarrationCsv() async {
    final route = _currentNavigation.routes[widget.currentUser.uid];
    if (route == null) return;

    final rows = <List<String>>[
      ['#', 'נקודה', 'פעולה', 'הערות'],
    ];

    for (var i = 0; i < route.sequence.length; i++) {
      final cpName = route.sequence[i];
      final isFirst = i == 0;
      final isLast = i == route.sequence.length - 1;
      final action = isFirst
          ? 'התחלה'
          : isLast
              ? 'סיום'
              : 'מעבר';
      rows.add(['${i + 1}', cpName, action, '']);
    }

    final csvData = const ListToCsvConverter().convert(rows);

    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(
        '${dir.path}/narration_${_currentNavigation.id}_${widget.currentUser.uid}.csv',
      );
      await file.writeAsString('\uFEFF$csvData'); // BOM for Hebrew in Excel

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('הקובץ נשמר: ${file.path}'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה בייצוא: $e')),
        );
      }
    }
  }

  Widget _buildNarrationTab() {
    final route = _currentNavigation.routes[widget.currentUser.uid];

    if (route == null) {
      return const Center(child: Text('לא הוקצה ציר'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // כותרת
          Row(
            children: [
              const Icon(Icons.record_voice_over, color: Colors.deepPurple),
              const SizedBox(width: 8),
              Text(
                'סיפור דרך — כרונולוגיה',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'סדר הנקודות לאורך הציר — רשום הערות לכל תחנה',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          const SizedBox(height: 16),

          // טבלת כרונולוגיה
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                // כותרת טבלה
                Container(
                  color: Colors.deepPurple[50],
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: const Row(
                    children: [
                      SizedBox(width: 32, child: Text('#', style: TextStyle(fontWeight: FontWeight.bold))),
                      Expanded(flex: 3, child: Text('נקודה', style: TextStyle(fontWeight: FontWeight.bold))),
                      Expanded(flex: 2, child: Text('פעולה', style: TextStyle(fontWeight: FontWeight.bold))),
                    ],
                  ),
                ),
                // שורות
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: route.sequence.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final cpName = route.sequence[index];
                    final isFirst = index == 0;
                    final isLast = index == route.sequence.length - 1;

                    final actionLabel = isFirst
                        ? 'התחלה'
                        : isLast
                            ? 'סיום'
                            : 'מעבר';
                    final actionColor = isFirst
                        ? Colors.green
                        : isLast
                            ? Colors.red
                            : Colors.blue;
                    final actionIcon = isFirst
                        ? Icons.play_arrow
                        : isLast
                            ? Icons.flag
                            : Icons.arrow_forward;

                    // חיפוש ה-checkpoint הטעון כדי להציג קואורדינטות
                    final loadedCp = _routeCheckpoints.length > index
                        ? _routeCheckpoints[index]
                        : null;

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 32,
                            child: CircleAvatar(
                              radius: 12,
                              backgroundColor: actionColor,
                              child: Text(
                                '${index + 1}',
                                style: const TextStyle(color: Colors.white, fontSize: 11),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(cpName, style: const TextStyle(fontWeight: FontWeight.w500)),
                                if (loadedCp != null)
                                  Text(
                                    '${loadedCp.coordinates.lat.toStringAsFixed(5)}, ${loadedCp.coordinates.lng.toStringAsFixed(5)}',
                                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                                  ),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Row(
                              children: [
                                Icon(actionIcon, size: 16, color: actionColor),
                                const SizedBox(width: 4),
                                Text(
                                  actionLabel,
                                  style: TextStyle(color: actionColor, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // סיכום
          _infoCard('סה"כ נקודות', '${route.sequence.length}'),
          _infoCard('אורך ציר', '${route.routeLengthKm.toStringAsFixed(2)} ק"מ'),

          const SizedBox(height: 16),

          // כפתור ייצוא CSV
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _exportNarrationCsv,
              icon: const Icon(Icons.download),
              label: const Text('ייצוא לקובץ CSV'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.deepPurple,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.school, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'שלב הלמידה פעיל',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'המפקד לא הפעיל הגדרות למידה נוספות',
            style: TextStyle(fontSize: 16, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // Helpers
  // ===========================================================================

  Widget _infoCard(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  // ===========================================================================
  // Build
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tabController,
          isScrollable: _tabs.length > 3,
          tabs: _tabs.map((t) => Tab(text: t.label, icon: Icon(t.icon))).toList(),
          labelColor: Theme.of(context).primaryColor,
          unselectedLabelColor: Colors.grey,
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: _tabs.map((t) => t.builder()).toList(),
          ),
        ),
      ],
    );
  }
}

class _LearningTab {
  final String label;
  final IconData icon;
  final Widget Function() builder;

  _LearningTab({
    required this.label,
    required this.icon,
    required this.builder,
  });
}
