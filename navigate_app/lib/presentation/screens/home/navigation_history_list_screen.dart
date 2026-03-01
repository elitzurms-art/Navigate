import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../domain/entities/navigation.dart' as domain;
import '../../../domain/entities/navigation_score.dart';
import '../../../domain/entities/user.dart';
import '../../../data/repositories/navigation_repository.dart';
import '../../../data/repositories/area_repository.dart';
import 'navigation_history_review_screen.dart';

/// מסך היסטוריית ניווטים — רשימת ניווטים שהסתיימו
class NavigationHistoryListScreen extends StatefulWidget {
  final User currentUser;

  const NavigationHistoryListScreen({
    super.key,
    required this.currentUser,
  });

  @override
  State<NavigationHistoryListScreen> createState() =>
      _NavigationHistoryListScreenState();
}

class _NavigationHistoryListScreenState
    extends State<NavigationHistoryListScreen> {
  final NavigationRepository _navRepo = NavigationRepository();
  final AreaRepository _areaRepo = AreaRepository();

  bool _loading = true;
  List<domain.Navigation> _navigations = [];
  final Map<String, String> _areaNames = {};
  final Map<String, NavigationScore?> _scores = {};

  @override
  void initState() {
    super.initState();
    _loadNavigations();
  }

  Future<void> _loadNavigations() async {
    try {
      final all = await _navRepo.getAllIncludingDeleted();
      final uid = widget.currentUser.uid;

      // סינון: רק approval/review + המנווט משתתף
      final filtered = all.where((nav) {
        if (nav.status != 'approval' && nav.status != 'review') return false;
        if (nav.routes.containsKey(uid)) return true;
        if (nav.selectedParticipantIds.contains(uid)) return true;
        return false;
      }).toList();

      // מיון לפי updatedAt יורד
      filtered.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      if (!mounted) return;
      setState(() {
        _navigations = filtered;
        _loading = false;
      });

      // טעינת שמות שטחות ב-batch
      final areaIds = filtered.map((n) => n.areaId).toSet();
      for (final areaId in areaIds) {
        if (areaId.isEmpty) continue;
        final area = await _areaRepo.getById(areaId);
        if (area != null && mounted) {
          setState(() => _areaNames[areaId] = area.name);
        }
      }

      // טעינת ציונים async מ-Firestore
      for (final nav in filtered) {
        _loadScoreForNavigation(nav);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadScoreForNavigation(domain.Navigation nav) async {
    try {
      final scores = await _navRepo.fetchScoresFromFirestore(nav.id);
      final myScores = scores
          .where((s) => s['navigatorId'] == widget.currentUser.uid)
          .toList();
      if (myScores.isNotEmpty && mounted) {
        setState(() {
          _scores[nav.id] = NavigationScore.fromMap(myScores.first);
        });
      }
    } catch (_) {
      // ציון לא זמין — לא חוסם את התצוגה
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'review':
        return 'תחקור';
      case 'approval':
        return 'ממתין לאישור';
      default:
        return status;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'review':
        return Colors.blue;
      case 'approval':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('היסטוריית ניווטים'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _navigations.isEmpty
              ? _buildEmptyState()
              : _buildList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'אין היסטוריית ניווטים',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'ניווטים שהושלמו יופיעו כאן',
            style: TextStyle(color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _navigations.length,
      itemBuilder: (context, index) {
        final nav = _navigations[index];
        return _buildNavigationCard(nav);
      },
    );
  }

  Widget _buildNavigationCard(domain.Navigation nav) {
    final dateStr = DateFormat('dd/MM/yyyy').format(nav.updatedAt);
    final areaName = _areaNames[nav.areaId];
    final score = _scores[nav.id];

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(
          nav.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.calendar_today, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(dateStr, style: TextStyle(color: Colors.grey[600])),
                if (areaName != null) ...[
                  const SizedBox(width: 12),
                  Icon(Icons.terrain, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      areaName,
                      style: TextStyle(color: Colors.grey[600]),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Chip(
                  label: Text(
                    _statusLabel(nav.status),
                    style: const TextStyle(fontSize: 12, color: Colors.white),
                  ),
                  backgroundColor: _statusColor(nav.status),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                if (score != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: _getScoreColor(score.totalScore),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${score.totalScore}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_left),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => NavigationHistoryReviewScreen(
                navigation: nav,
                currentUser: widget.currentUser,
                score: score,
              ),
            ),
          );
        },
      ),
    );
  }

  Color _getScoreColor(int score) {
    if (score >= 80) return Colors.green;
    if (score >= 60) return Colors.orange;
    return Colors.red;
  }
}
