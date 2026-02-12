import 'package:flutter/material.dart';
import '../../../../domain/entities/navigation.dart' as domain;
import '../../../../domain/entities/user.dart';

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

  @override
  void initState() {
    super.initState();
    _buildTabs();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void didUpdateWidget(LearningView oldWidget) {
    super.didUpdateWidget(oldWidget);
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

  Widget _buildEditTab() {
    final route = widget.navigation.routes[widget.currentUser.uid];

    if (route == null) {
      return const Center(child: Text('לא הוקצה ציר'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          if (!route.isApproved)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  // TODO: אישור ציר — עדכון route.isApproved = true
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('אישור ציר — בפיתוח')),
                  );
                },
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

  Widget _buildNarrationTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.record_voice_over, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'סיפור דרך',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'בפיתוח',
            style: TextStyle(fontSize: 16, color: Colors.grey[500]),
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
