import 'dart:async';
import 'package:flutter/material.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/repositories/unit_repository.dart';
import '../../../domain/entities/unit.dart';
import '../../../domain/entities/user.dart';
import '../../../services/auth_service.dart';
import '../../../services/session_service.dart';

/// מסך אישור מנווטים — מפקד מאשר/דוחה בקשות הצטרפות ליחידה
class PendingApprovalsScreen extends StatefulWidget {
  const PendingApprovalsScreen({super.key});

  @override
  State<PendingApprovalsScreen> createState() => _PendingApprovalsScreenState();
}

class _PendingApprovalsScreenState extends State<PendingApprovalsScreen> {
  final UserRepository _userRepo = UserRepository();
  final UnitRepository _unitRepo = UnitRepository();
  final SessionService _sessionService = SessionService();
  final AuthService _authService = AuthService();

  List<User> _pendingUsers = [];
  bool _isLoading = true;
  String? _errorMessage;
  bool _isDeveloper = false;
  bool _canAssignRoles = false; // רק developer/unit_admin יכולים לקבוע תפקידים
  String? _commanderUnitId;
  StreamSubscription<List<User>>? _pendingUsersListener;

  // מעקב אחרי toggle "מפקד" לכל משתמש
  final Map<String, bool> _commanderToggle = {};

  // שמות יחידות לתצוגה (למפתח שרואה משתמשים ממספר יחידות)
  final Map<String, String> _unitNames = {};

  // יחידות ללא מפקדים מאושרים — אישור ראשון = unit_admin
  final Set<String> _unitsWithoutCommanders = {};

  // יחידות ללא חברים מאושרים כלל — חובה מנהל יחידה
  final Set<String> _unitsWithNoMembers = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _pendingUsersListener?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final user = await _authService.getCurrentUser();
      _isDeveloper = user?.role == 'developer';
      _canAssignRoles = user?.role == 'developer' || user?.role == 'unit_admin';

      final session = await _sessionService.getSavedSession();
      _commanderUnitId = session?.unitId;

      _startPendingUsersListener();
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// התחלת האזנה למשתמשים ממתינים דרך UserRepository
  void _startPendingUsersListener() async {
    _pendingUsersListener?.cancel();

    try {
      List<String> unitIds;
      if (!_isDeveloper && _commanderUnitId != null) {
        final descendantIds = await _unitRepo.getDescendantIds(_commanderUnitId!);
        if (!mounted) return;
        unitIds = [_commanderUnitId!, ...descendantIds];
      } else {
        // developer — רשימה ריקה = כל המשתמשים הממתינים
        unitIds = [];
      }

      _pendingUsersListener = _userRepo.watchPendingUsers(unitIds).listen(
        (users) async {
          if (!mounted) return;
          await _loadUnitMetadata(users);
          if (mounted) {
            setState(() {
              _pendingUsers = users;
              _isLoading = false;
              _errorMessage = null;
            });
          }
        },
        onError: (error) {
          print('DEBUG PendingApprovals: watchPendingUsers error: $error');
          if (mounted) {
            setState(() {
              _isLoading = false;
              _errorMessage = 'שגיאה בטעינת בקשות: $error';
            });
          }
        },
      );
    } catch (e) {
      print('DEBUG PendingApprovals: listener setup failed: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'שגיאה בהגדרת האזנה: $e';
        });
      }
    }
  }

  /// רענון ידני — שאילתה חד-פעמית דרך UserRepository
  Future<void> _refreshFromFirestore() async {
    try {
      List<User> users;
      if (!_isDeveloper && _commanderUnitId != null) {
        final descendantIds = await _unitRepo.getDescendantIds(_commanderUnitId!);
        final unitIds = [_commanderUnitId!, ...descendantIds];
        users = await _userRepo.getPendingApprovalUsers(unitIds);
      } else {
        users = await _userRepo.getAllPendingApprovalUsers();
      }

      await _loadUnitMetadata(users);
      if (mounted) {
        setState(() {
          _pendingUsers = users;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// טעינת metadata ליחידות (שמות, מפקדים, חברים) — במקביל per-unit
  Future<void> _loadUnitMetadata(List<User> users) async {
    _unitsWithoutCommanders.clear();
    _unitsWithNoMembers.clear();

    // איסוף יחידות ייחודיות
    final uniqueUnitIds = <String>{};
    for (final user in users) {
      final uid = user.unitId;
      if (uid != null && uid.isNotEmpty) {
        uniqueUnitIds.add(uid);
      }
    }

    // שאילתות במקביל לכל יחידה
    await Future.wait(uniqueUnitIds.map((unitId) async {
      final results = await Future.wait([
        _unitRepo.getById(unitId),
        _unitRepo.hasApprovedCommandersInHierarchy(unitId),
        _userRepo.getApprovedUsersForUnit(unitId),
      ]);

      final unit = results[0] as Unit?;
      final hasCommanders = results[1] as bool;
      final members = results[2] as List;

      _unitNames[unitId] = unit?.name ?? unitId;
      if (!hasCommanders) _unitsWithoutCommanders.add(unitId);
      if (members.isEmpty) _unitsWithNoMembers.add(unitId);
    }));
  }

  Future<void> _approveUser(User user) async {
    String? role;
    final hasNoMembers = user.unitId != null &&
        _unitsWithNoMembers.contains(user.unitId);

    if (hasNoMembers) {
      // אין חברים מאושרים ביחידה — חובה מנהל יחידה
      role = 'unit_admin';
    } else if (_canAssignRoles) {
      final isCommander = _commanderToggle[user.uid] ?? false;
      final noCommandersInUnit = user.unitId != null &&
          _unitsWithoutCommanders.contains(user.unitId);
      role = isCommander
          ? (noCommandersInUnit ? 'unit_admin' : 'commander')
          : null;

      // אם ליחידה אין מפקדים מאושרים בהיררכיה — אישור ראשון = unit_admin
      if (!isCommander && noCommandersInUnit) {
        role = 'unit_admin';
      }
    }

    await _userRepo.approveUser(user.uid, role: role);
    _commanderToggle.remove(user.uid);
    await _refreshFromFirestore();
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

  Future<void> _rejectUser(User user) async {
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

    await _userRepo.rejectUser(user.uid);
    _commanderToggle.remove(user.uid);
    await _refreshFromFirestore();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('הבקשה של ${user.fullName} נדחתה'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('אישור מנווטים'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refreshFromFirestore,
              child: Column(
                children: [
                  if (_errorMessage != null)
                    MaterialBanner(
                      content: Text(
                        _errorMessage!,
                        style: const TextStyle(fontSize: 13),
                      ),
                      leading: const Icon(Icons.error_outline, color: Colors.red),
                      backgroundColor: Colors.red.shade50,
                      actions: [
                        TextButton(
                          onPressed: () {
                            setState(() => _errorMessage = null);
                            _startPendingUsersListener();
                          },
                          child: const Text('נסה שוב'),
                        ),
                      ],
                    ),
                  Expanded(
                    child: _pendingUsers.isEmpty
                        ? ListView(
                            children: const [
                              SizedBox(height: 80),
                              Center(
                                child: Column(
                                  children: [
                                    Icon(Icons.check_circle_outline,
                                        size: 64, color: Colors.green),
                                    SizedBox(height: 16),
                                    Text(
                                      'אין בקשות ממתינות',
                                      style: TextStyle(
                                        fontSize: 18,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: _pendingUsers.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              return _buildUserCard(_pendingUsers[index]);
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildUserCard(User user) {
    final isCommanderToggle = _commanderToggle[user.uid] ?? false;
    final unitName = _unitNames[user.unitId ?? ''];
    final noCommandersInUnit = user.unitId != null &&
        _unitsWithoutCommanders.contains(user.unitId);
    final hasNoMembers = user.unitId != null &&
        _unitsWithNoMembers.contains(user.unitId);
    // אם ליחידה אין חברים או אין מפקדים, ה-toggle הופך ל-"מנהל יחידה"
    final toggleLabel = (hasNoMembers || noCommandersInUnit)
        ? 'מנהל יחידה'
        : 'מפקד';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const CircleAvatar(
                    radius: 20,
                    child: Icon(Icons.person),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.fullName.isNotEmpty
                              ? user.fullName
                              : 'ללא שם',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'מ.א: ${user.uid}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                        if (user.phoneNumber.isNotEmpty)
                          Text(
                            user.phoneNumber,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                        if (unitName != null)
                          Text(
                            'יחידה: $unitName',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.indigo[400],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // הערה + toggle — רק למי שיכול לקבוע תפקידים (developer/unit_admin)
              if (_canAssignRoles) ...[
                if (hasNoMembers)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      'ליחידה אין חברים — חובה לאשר כמנהל יחידה',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.orange[700],
                        fontWeight: FontWeight.bold,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  )
                else if (noCommandersInUnit && !isCommanderToggle)
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
                      value: hasNoMembers ? true : isCommanderToggle,
                      onChanged: hasNoMembers
                          ? null
                          : (val) {
                              setState(() {
                                _commanderToggle[user.uid] = val;
                              });
                            },
                    ),
                    Text(
                      toggleLabel,
                      style: TextStyle(
                        color: (hasNoMembers || isCommanderToggle)
                            ? Colors.blue
                            : Colors.grey,
                        fontWeight: (hasNoMembers || isCommanderToggle)
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    const Spacer(),
                    OutlinedButton.icon(
                      onPressed: () => _rejectUser(user),
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('דחייה'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: () => _approveUser(user),
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('אישור'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green,
                      ),
                    ),
                  ],
                ),
              ],
              // מפקד רגיל — רק כפתורי אישור/דחייה, בלי toggle
              if (!_canAssignRoles)
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _rejectUser(user),
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('דחייה'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: () => _approveUser(user),
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('אישור'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
