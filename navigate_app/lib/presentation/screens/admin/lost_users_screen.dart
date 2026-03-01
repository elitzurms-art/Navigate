import 'package:flutter/material.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/repositories/unit_repository.dart';
import '../../../domain/entities/user.dart';
import '../../../domain/entities/unit.dart' as domain;

/// מסך משתמשים אבודים — כלי תחזוקה למפתחים
/// מציג משתמשים שנפלו מזרם ה-onboarding (לא מאושרים, לא ממתינים, לא admin/developer)
class LostUsersScreen extends StatefulWidget {
  const LostUsersScreen({super.key});

  @override
  State<LostUsersScreen> createState() => _LostUsersScreenState();
}

class _LostUsersScreenState extends State<LostUsersScreen> {
  final UserRepository _userRepo = UserRepository();
  final UnitRepository _unitRepo = UnitRepository();

  List<User> _lostUsers = [];
  List<domain.Unit> _allUnits = [];
  Map<String, String> _unitNamesCache = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _userRepo.getLostUsers(),
        _unitRepo.getAll(),
      ]);
      final lost = results[0] as List<User>;
      final units = results[1] as List<domain.Unit>;

      final unitNames = <String, String>{};
      for (final u in units) {
        unitNames[u.id] = u.name;
      }

      if (mounted) {
        setState(() {
          _lostUsers = lost;
          _allUnits = units;
          _unitNamesCache = unitNames;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// סיווג הסיבה למה המשתמש "אבוד"
  String _diagnoseLostReason(User user) {
    if (user.unitId == null || user.unitId!.isEmpty) {
      return 'ללא יחידה';
    }
    if (!_unitNamesCache.containsKey(user.unitId)) {
      return 'יחידה לא קיימת';
    }
    if (user.isRejected) {
      return 'נדחה';
    }
    return 'ללא סטטוס';
  }

  Color _diagnosisColor(String reason) {
    switch (reason) {
      case 'ללא יחידה':
        return Colors.grey;
      case 'יחידה לא קיימת':
        return Colors.purple;
      case 'נדחה':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  Future<void> _deleteUser(User user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('מחיקת משתמש'),
        content: Text(
          'האם למחוק לצמיתות את ${user.fullName.isNotEmpty ? user.fullName : user.uid}?\n\n'
          'פעולה זו בלתי הפיכה.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ביטול'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('מחיקה'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _userRepo.deleteUserPermanently(user.uid);
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${user.fullName.isNotEmpty ? user.fullName : user.uid} נמחק'),
            backgroundColor: Colors.red,
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

  Future<void> _assignToUnit(User user) async {
    String? selectedUnitId;
    String selectedRole = 'navigator';

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              top: 16,
              left: 16,
              right: 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'שיוך ${user.fullName.isNotEmpty ? user.fullName : user.uid} ליחידה',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'יחידה',
                    border: OutlineInputBorder(),
                  ),
                  value: selectedUnitId,
                  items: _allUnits
                      .map((u) => DropdownMenuItem(
                            value: u.id,
                            child: Text(u.name),
                          ))
                      .toList(),
                  onChanged: (val) {
                    setSheetState(() => selectedUnitId = val);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'תפקיד',
                    border: OutlineInputBorder(),
                  ),
                  value: selectedRole,
                  items: const [
                    DropdownMenuItem(value: 'navigator', child: Text('מנווט')),
                    DropdownMenuItem(value: 'commander', child: Text('מפקד')),
                    DropdownMenuItem(value: 'unit_admin', child: Text('מנהל יחידה')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setSheetState(() => selectedRole = val);
                    }
                  },
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: selectedUnitId == null
                      ? null
                      : () => Navigator.pop(ctx, true),
                  child: const Text('שיוך'),
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );

    if (result != true || selectedUnitId == null) return;

    try {
      await _userRepo.addUserToUnit(user.uid, selectedUnitId!);
      if (selectedRole != 'navigator') {
        await _userRepo.updateUserRole(user.uid, selectedRole);
      }
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${user.fullName.isNotEmpty ? user.fullName : user.uid} שויך ליחידה'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בשיוך: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('משתמשים אבודים'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: _lostUsers.isEmpty
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
                                'אין משתמשים אבודים',
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
                      itemCount: _lostUsers.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        return _buildUserCard(_lostUsers[index]);
                      },
                    ),
            ),
    );
  }

  Widget _buildUserCard(User user) {
    final reason = _diagnoseLostReason(user);
    final chipColor = _diagnosisColor(reason);

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
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.red.shade50,
                    child: const Icon(Icons.person_off, color: Colors.red),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.fullName.isNotEmpty ? user.fullName : 'ללא שם',
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
                      ],
                    ),
                  ),
                  Chip(
                    label: Text(
                      reason,
                      style: const TextStyle(fontSize: 11, color: Colors.white),
                    ),
                    backgroundColor: chipColor,
                    padding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _deleteUser(user),
                    icon: const Icon(Icons.delete_forever, size: 18),
                    label: const Text('מחיקה'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => _assignToUnit(user),
                    icon: const Icon(Icons.group_add, size: 18),
                    label: const Text('שיוך ליחידה'),
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
