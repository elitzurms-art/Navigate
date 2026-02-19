import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../domain/entities/unit.dart';
import '../../../domain/entities/navigation_tree.dart';
import '../../../domain/entities/user.dart' as domain;
import '../../../data/repositories/user_repository.dart';
import '../../../data/repositories/unit_repository.dart';
import '../../../data/sync/sync_manager.dart';
import 'create_unit_screen.dart';

/// מסך חברי יחידה — הצגת משתמשים מאושרים + ממתינים + שינוי תפקידים
/// כולל יחידות משנה עם נעילה/אקורדיון
class UnitMembersScreen extends StatefulWidget {
  final Unit unit;

  const UnitMembersScreen({super.key, required this.unit});

  @override
  State<UnitMembersScreen> createState() => _UnitMembersScreenState();
}

class _UnitMembersScreenState extends State<UnitMembersScreen> {
  final UserRepository _userRepository = UserRepository();
  final UnitRepository _unitRepository = UnitRepository();

  // נתונים לפי יחידה (ID → רשימה)
  final Map<String, List<domain.User>> _membersByUnit = {};
  final Map<String, List<domain.User>> _pendingByUnit = {};
  final Map<String, bool> _noCommandersByUnit = {};

  // יחידות משנה ישירות
  List<Unit> _childUnits = [];

  // מצב UI — סקציות פתוחות/נעולות
  final Set<String> _expandedUnits = {};
  final Set<String> _lockedUnits = {};

  // toggle "מפקד" למשתמשים ממתינים
  final Map<String, bool> _commanderToggle = {};

  bool _isLoading = true;
  StreamSubscription<String>? _syncSubscription;

  static const _roleOrder = {
    'admin': 0,
    'developer': 1,
    'unit_admin': 2,
    'commander': 3,
    'navigator': 4,
  };

  @override
  void initState() {
    super.initState();
    _expandedUnits.add(widget.unit.id); // היחידה הראשית פתוחה כברירת מחדל
    _loadAllData();
    _syncSubscription = SyncManager().onDataChanged.listen((collection) {
      if (collection == AppConstants.usersCollection && mounted) {
        _loadAllData();
      }
    });
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // טעינת נתונים
  // ---------------------------------------------------------------------------

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    try {
      // נתוני היחידה הראשית
      await _loadUnitData(widget.unit.id);

      // יחידות משנה ישירות
      final allUnits = await _unitRepository.getAll();
      _childUnits = allUnits
          .where((u) => u.parentUnitId == widget.unit.id)
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));

      // נתוני כל יחידת משנה
      for (final child in _childUnits) {
        await _loadUnitData(child.id);
      }

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה בטעינה: $e')),
        );
      }
    }
  }

  Future<void> _loadUnitData(String unitId) async {
    final members = await _userRepository.getApprovedUsersForUnit(unitId);
    members.sort((a, b) {
      final orderA = _roleOrder[a.role] ?? 5;
      final orderB = _roleOrder[b.role] ?? 5;
      if (orderA != orderB) return orderA.compareTo(orderB);
      return a.fullName.compareTo(b.fullName);
    });

    final pending = await _userRepository.getPendingApprovalUsers([unitId]);
    final hasCommanders =
        await _unitRepository.hasApprovedCommandersInHierarchy(unitId);

    _membersByUnit[unitId] = members;
    _pendingByUnit[unitId] = pending;
    _noCommandersByUnit[unitId] = !hasCommanders;
  }

  // ---------------------------------------------------------------------------
  // אקורדיון + נעילה
  // ---------------------------------------------------------------------------

  void _toggleExpand(String unitId) {
    setState(() {
      if (_expandedUnits.contains(unitId)) {
        _expandedUnits.remove(unitId);
      } else {
        // סגירת כל הסקציות שאינן נעולות
        _expandedUnits.removeWhere((id) => !_lockedUnits.contains(id));
        _expandedUnits.add(unitId);
      }
    });
  }

  void _toggleLock(String unitId) {
    setState(() {
      if (_lockedUnits.contains(unitId)) {
        _lockedUnits.remove(unitId);
      } else {
        _lockedUnits.add(unitId);
      }
    });
  }

  // ---------------------------------------------------------------------------
  // פעולות על משתמשים
  // ---------------------------------------------------------------------------

  Future<void> _approveUser(domain.User user, String unitId) async {
    final isCommander = _commanderToggle[user.uid] ?? false;
    final noCommanders = _noCommandersByUnit[unitId] ?? false;
    String? role = isCommander
        ? (noCommanders ? 'unit_admin' : 'commander')
        : null;

    if (!isCommander && noCommanders) {
      role = 'unit_admin';
    }

    await _userRepository.approveUser(user.uid, role: role);
    _commanderToggle.remove(user.uid);
    await _loadAllData();
    if (mounted) {
      String roleLabel = '';
      if (role == 'unit_admin') {
        roleLabel = ' כמנהל יחידה';
      } else if (role == 'commander') {
        roleLabel = ' כמפקד';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${user.fullName} אושר$roleLabel'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _rejectUser(domain.User user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('דחיית בקשה'),
        content: Text('האם לדחות את הבקשה של ${user.fullName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ביטול'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('דחייה'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _userRepository.rejectUser(user.uid);
    _commanderToggle.remove(user.uid);
    await _loadAllData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('הבקשה של ${user.fullName} נדחתה'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _changeRole(domain.User user) async {
    if (!_canChangeRole(user)) return;

    final newRole = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('שינוי תפקיד — ${user.fullName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: _assignableRoles.map((role) {
            final isCurrentRole = role == user.role;
            return RadioListTile<String>(
              title: Text(_getRoleDisplayName(role)),
              value: role,
              groupValue: user.role,
              onChanged: isCurrentRole
                  ? null
                  : (value) => Navigator.pop(context, value),
              secondary: Icon(
                _getRoleIcon(role),
                color: _getRoleColor(role),
              ),
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ביטול'),
          ),
        ],
      ),
    );

    if (newRole == null || newRole == user.role) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('אישור שינוי תפקיד'),
        content: Text(
          'לשנות את ${user.fullName} '
          'מ-${_getRoleDisplayName(user.role)} '
          'ל-${_getRoleDisplayName(newRole)}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.blue),
            child: const Text('אישור'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _userRepository.updateUserRole(user.uid, newRole);
    await _loadAllData();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${user.fullName} — ${_getRoleDisplayName(newRole)}'),
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // עזרים — תפקידים
  // ---------------------------------------------------------------------------

  String _getRoleDisplayName(String role) {
    switch (role) {
      case 'navigator':
        return 'מנווט';
      case 'commander':
        return 'מפקד';
      case 'unit_admin':
        return 'מנהל יחידה';
      case 'developer':
        return 'מפתח';
      case 'admin':
        return 'מנהל מערכת';
      default:
        return role;
    }
  }

  Color _getRoleColor(String role) {
    switch (role) {
      case 'admin':
        return Colors.red;
      case 'developer':
        return Colors.purple;
      case 'unit_admin':
        return Colors.orange;
      case 'commander':
        return Colors.blue;
      case 'navigator':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  IconData _getRoleIcon(String role) {
    switch (role) {
      case 'admin':
        return Icons.admin_panel_settings;
      case 'developer':
        return Icons.code;
      case 'unit_admin':
        return Icons.manage_accounts;
      case 'commander':
        return Icons.military_tech;
      case 'navigator':
        return Icons.explore;
      default:
        return Icons.person;
    }
  }

  List<String> get _assignableRoles => ['navigator', 'commander', 'unit_admin'];

  /// מחיקת יחידת משנה — כולל cascade: משתמשים, עצים, ניווטים
  Future<void> _deleteChildUnit(Unit unit) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('מחיקת יחידת משנה'),
        content: Text(
          'האם למחוק את "${unit.name}"?\n\n'
          'כל המשתמשים ביחידה יוסרו ויחזרו לסטטוס לא מאושר.\n'
          'מפקדים ומנהלים יועברו לתפקיד מנווט.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('מחיקה'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _unitRepository.deleteWithCascade(unit.id);
      await _loadAllData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"${unit.name}" נמחקה'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה במחיקה: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// האם ניתן ליצור יחידת משנה — רק אם יש רמה מתחת להורה
  bool _canCreateChildUnit() {
    final parentLevel = widget.unit.level ??
        FrameworkLevel.fromUnitType(widget.unit.type);
    if (parentLevel == null) return true; // fallback — מאפשר
    return FrameworkLevel.getNextLevelBelow(parentLevel) != null;
  }

  bool _canChangeRole(domain.User user) {
    return user.role != 'admin' && user.role != 'developer';
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final totalMembers =
        _membersByUnit.values.fold<int>(0, (sum, list) => sum + list.length);
    final totalPending =
        _pendingByUnit.values.fold<int>(0, (sum, list) => sum + list.length);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.unit.name),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'עריכת יחידה',
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CreateUnitScreen(unit: widget.unit),
                ),
              );
              if (result == true && mounted) {
                Navigator.pop(context, true);
              }
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildUnitHeader(totalMembers, totalPending),
                const Divider(height: 1),
                Expanded(
                  child: totalMembers == 0 &&
                          totalPending == 0 &&
                          _childUnits.isEmpty
                      ? _buildEmptyState()
                      : ListView(
                          children: [
                            // סקציית היחידה הראשית
                            _buildUnitSection(widget.unit, isMainUnit: true),
                            // יחידות משנה — מוצג תמיד (גם אם ריק)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                              child: Row(
                                children: [
                                  Icon(Icons.account_tree,
                                      size: 18, color: Colors.grey[600]),
                                  const SizedBox(width: 8),
                                  Text(
                                    'יחידות משנה',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  const Spacer(),
                                  // כפתור + רק אם יש רמה מתחת (מחלקה = הכי נמוכה)
                                  if (_canCreateChildUnit())
                                    IconButton(
                                      icon: const Icon(Icons.add, size: 20),
                                      tooltip: 'יצירת יחידת משנה',
                                      onPressed: () async {
                                        final result = await Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => CreateUnitScreen(
                                              parentUnitId: widget.unit.id,
                                            ),
                                          ),
                                        );
                                        if (result == true && mounted) {
                                          _loadAllData();
                                        }
                                      },
                                      visualDensity: VisualDensity.compact,
                                    ),
                                ],
                              ),
                            ),
                            if (_childUnits.isNotEmpty)
                              ..._childUnits.map(
                                (child) => _buildUnitSection(child,
                                    isMainUnit: false),
                              ),
                            if (_childUnits.isEmpty)
                              Padding(
                                padding: const EdgeInsets.all(20),
                                child: Center(
                                  child: Text(
                                    'אין יחידות משנה',
                                    style: TextStyle(
                                        color: Colors.grey[500], fontSize: 13),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 24),
                          ],
                        ),
                ),
              ],
            ),
    );
  }

  // ---------------------------------------------------------------------------
  // Widgets
  // ---------------------------------------------------------------------------

  Widget _buildUnitHeader(int totalMembers, int totalPending) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: Theme.of(context).primaryColor.withOpacity(0.05),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: Colors.purple.withOpacity(0.2),
            child: Icon(
              widget.unit.getIcon(),
              color: Colors.purple,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.unit.name,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  '${widget.unit.getTypeName()} • $totalMembers חברים'
                  '${totalPending > 0 ? ' • $totalPending ממתינים' : ''}'
                  '${_childUnits.isNotEmpty ? ' • ${_childUnits.length} יחידות משנה' : ''}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'אין חברים ביחידה',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            'חברים חדשים יופיעו כאן לאחר אישור',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  /// סקציה מתקפלת ליחידה (ראשית או משנה)
  Widget _buildUnitSection(Unit unit, {required bool isMainUnit}) {
    final unitId = unit.id;
    final isExpanded = _expandedUnits.contains(unitId);
    final isLocked = _lockedUnits.contains(unitId);
    final members = _membersByUnit[unitId] ?? [];
    final pending = _pendingByUnit[unitId] ?? [];
    final noCommanders = _noCommandersByUnit[unitId] ?? false;

    return Column(
      children: [
        // כותרת סקציה — לחיצה לפתיחה/סגירה
        InkWell(
          onTap: () => _toggleExpand(unitId),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            color: isExpanded
                ? Theme.of(context).primaryColor.withOpacity(0.04)
                : null,
            child: Row(
              children: [
                Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_left,
                  color: Colors.grey[600],
                  size: 22,
                ),
                const SizedBox(width: 4),
                if (!isMainUnit) ...[
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: Colors.purple.withOpacity(0.1),
                    child:
                        Icon(unit.getIcon(), size: 16, color: Colors.purple),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isMainUnit ? 'חברי ${unit.name}' : unit.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        '${members.length} חברים'
                        '${pending.isNotEmpty ? ' • ${pending.length} ממתינים' : ''}',
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                // badge ממתינים
                if (pending.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    margin: const EdgeInsets.only(left: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${pending.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                // מנעול
                IconButton(
                  icon: Icon(
                    isLocked ? Icons.lock : Icons.lock_open,
                    size: 20,
                    color: isLocked ? Colors.blue : Colors.grey[400],
                  ),
                  onPressed: () => _toggleLock(unitId),
                  tooltip:
                      isLocked ? 'ביטול נעילה' : 'נעילה — הרשימה תישאר פתוחה',
                  visualDensity: VisualDensity.compact,
                ),
                // מחיקת יחידת משנה
                if (!isMainUnit)
                  IconButton(
                    icon: Icon(Icons.delete_outline,
                        size: 20, color: Colors.red[300]),
                    onPressed: () => _deleteChildUnit(unit),
                    tooltip: 'מחיקת יחידה',
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
        ),
        // תוכן (אם פתוח)
        if (isExpanded) ...[
          // ממתינים לאישור
          if (pending.isNotEmpty) ...[
            _buildSubSectionLabel(
                'ממתינים לאישור', Icons.hourglass_top, Colors.orange, pending.length),
            ...pending.map((u) => _buildPendingUserTile(u, unitId, noCommanders)),
          ],
          // חברים מאושרים
          if (members.isNotEmpty) ...[
            _buildSubSectionLabel(
                'חברים מאושרים', Icons.people, Colors.green, members.length),
            ...members.map(_buildMemberTile),
          ],
          // ריק
          if (pending.isEmpty && members.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: Text(
                  'אין חברים ביחידה זו',
                  style: TextStyle(color: Colors.grey[500], fontSize: 13),
                ),
              ),
            ),
        ],
        const Divider(height: 1),
      ],
    );
  }

  Widget _buildSubSectionLabel(
      String title, IconData icon, Color color, int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                  fontSize: 11, color: color, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingUserTile(
      domain.User user, String unitId, bool noCommanders) {
    final isCommanderToggle = _commanderToggle[user.uid] ?? false;
    final toggleLabel = noCommanders ? 'מנהל יחידה' : 'מפקד';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: Colors.orange.withOpacity(0.04),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.orange.withOpacity(0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.orange.withOpacity(0.15),
                  child: const Icon(Icons.person_add,
                      color: Colors.orange, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.fullName.isNotEmpty ? user.fullName : 'ללא שם',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        'מ.א: ${user.uid}',
                        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                      ),
                      if (user.phoneNumber.isNotEmpty)
                        Text(
                          user.phoneNumber,
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[500]),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (noCommanders && !isCommanderToggle)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'ליחידה אין מפקדים — יאושר כמנהל יחידה',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.orange[700],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            Row(
              children: [
                Switch(
                  value: isCommanderToggle,
                  onChanged: (val) {
                    setState(() => _commanderToggle[user.uid] = val);
                  },
                ),
                Text(
                  toggleLabel,
                  style: TextStyle(
                    color: isCommanderToggle ? Colors.blue : Colors.grey,
                    fontWeight: isCommanderToggle
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: () => _rejectUser(user),
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('דחייה'),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => _approveUser(user, unitId),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('אישור'),
                  style: FilledButton.styleFrom(backgroundColor: Colors.green),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _removeFromUnit(domain.User user) async {
    final roleNote = (user.role == 'commander' || user.role == 'unit_admin')
        ? '\nתפקידו ישתנה למנווט.'
        : '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('הסרה מהיחידה'),
        content: Text(
          'להסיר את ${user.fullName} מהיחידה?$roleNote',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('הסרה'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _userRepository.removeUserFromUnit(user.uid);
    await _loadAllData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${user.fullName} הוסר מהיחידה'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Widget _buildMemberTile(domain.User user) {
    final canChange = _canChangeRole(user);
    final roleColor = _getRoleColor(user.role);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: roleColor.withOpacity(0.15),
          child: Icon(
            _getRoleIcon(user.role),
            color: roleColor,
            size: 22,
          ),
        ),
        title: Text(
          user.fullName.isNotEmpty ? user.fullName : user.uid,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          '${user.uid} • ${user.phoneNumber}',
          style: TextStyle(color: Colors.grey[600], fontSize: 13),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canChange)
              ActionChip(
                label: Text(
                  _getRoleDisplayName(user.role),
                  style: TextStyle(color: roleColor, fontSize: 12),
                ),
                avatar: Icon(Icons.swap_horiz, size: 16, color: roleColor),
                backgroundColor: roleColor.withOpacity(0.1),
                side: BorderSide(color: roleColor.withOpacity(0.3)),
                onPressed: () => _changeRole(user),
              )
            else
              Chip(
                label: Text(
                  _getRoleDisplayName(user.role),
                  style: TextStyle(color: roleColor, fontSize: 12),
                ),
                backgroundColor: roleColor.withOpacity(0.1),
                side: BorderSide(color: roleColor.withOpacity(0.3)),
              ),
            if (canChange) ...[
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(Icons.person_remove,
                    size: 20, color: Colors.red[300]),
                tooltip: 'הסרה מהיחידה',
                onPressed: () => _removeFromUnit(user),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
