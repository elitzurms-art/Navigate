import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../data/repositories/unit_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/sync/sync_manager.dart';
import '../../../domain/entities/unit.dart';
import '../../../services/auth_service.dart';
import 'waiting_for_approval_screen.dart';

/// מסך בחירת יחידה — מנווט חדש בוחר יחידה להצטרף אליה
class ChooseUnitScreen extends StatefulWidget {
  const ChooseUnitScreen({super.key});

  @override
  State<ChooseUnitScreen> createState() => _ChooseUnitScreenState();
}

class _ChooseUnitScreenState extends State<ChooseUnitScreen> {
  final UnitRepository _unitRepo = UnitRepository();
  final UserRepository _userRepo = UserRepository();
  final AuthService _authService = AuthService();
  final SyncManager _syncManager = SyncManager();

  List<_UnitWithDepth> _hierarchicalUnits = [];
  bool _isLoading = true;
  String? _error;
  StreamSubscription<String>? _syncSubscription;

  @override
  void initState() {
    super.initState();
    // האזנה לשינויי סנכרון — אם יחידות מגיעות מאוחר, טעינה מחדש
    _syncSubscription = _syncManager.onDataChanged.listen((collection) {
      if (collection == 'units' && mounted) {
        _loadUnits();
      }
    });
    _loadUnits();
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadUnits() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      var allUnits = await _unitRepo.getAll();

      // אם DB מקומי ריק — ניסיון טעינה ישירה מ-Firestore
      if (allUnits.isEmpty) {
        allUnits = await _loadUnitsFromFirestore();
      }

      if (!mounted) return;
      setState(() {
        _hierarchicalUnits = _buildHierarchy(allUnits);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'שגיאה בטעינת יחידות';
        _isLoading = false;
      });
    }
  }

  /// טעינת יחידות ישירות מ-Firestore כ-fallback
  Future<List<Unit>> _loadUnitsFromFirestore() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('units')
          .get()
          .timeout(const Duration(seconds: 10));

      final units = <Unit>[];
      for (final doc in snapshot.docs) {
        try {
          final data = Map<String, dynamic>.from(doc.data());
          data['id'] = doc.id;
          // המרת Timestamp ל-ISO string
          data.forEach((key, value) {
            if (value is Timestamp) {
              data[key] = value.toDate().toIso8601String();
            }
          });
          units.add(Unit.fromMap(data));
        } catch (_) {}
      }
      return units;
    } catch (e) {
      return [];
    }
  }

  List<_UnitWithDepth> _buildHierarchy(List<Unit> allUnits) {
    final result = <_UnitWithDepth>[];
    final childrenMap = <String?, List<Unit>>{};

    for (final unit in allUnits) {
      childrenMap.putIfAbsent(unit.parentUnitId, () => []).add(unit);
    }

    for (final list in childrenMap.values) {
      list.sort((a, b) => a.name.compareTo(b.name));
    }

    void addRecursive(String? parentId, int depth) {
      final children = childrenMap[parentId];
      if (children == null) return;
      for (final unit in children) {
        result.add(_UnitWithDepth(unit, depth));
        addRecursive(unit.id, depth + 1);
      }
    }

    addRecursive(null, 0);
    return result;
  }

  Future<void> _selectUnit(Unit unit) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('הצטרפות ליחידה'),
        content: Text('האם להצטרף ליחידה "${unit.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ביטול'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('הצטרפות'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final user = await _authService.getCurrentUser();
    if (user == null) return;

    await _userRepo.setUserUnit(user.uid, unit.id);

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => WaitingForApprovalScreen(unitName: unit.name),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('בחירת יחידה'),
        centerTitle: true,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'התנתקות',
            onPressed: () async {
              await _authService.signOut();
              if (mounted) {
                Navigator.of(context).pushReplacementNamed('/');
              }
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadUnits,
                        child: const Text('נסה שוב'),
                      ),
                    ],
                  ),
                )
              : _hierarchicalUnits.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'לא נמצאו יחידות.\nפנה למנהל המערכת.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadUnits,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _hierarchicalUnits.length,
                        itemBuilder: (context, index) {
                          final item = _hierarchicalUnits[index];
                          return _buildUnitTile(item);
                        },
                      ),
                    ),
    );
  }

  Widget _buildUnitTile(_UnitWithDepth item) {
    final indent = item.depth * 24.0;
    return ListTile(
      contentPadding: EdgeInsetsDirectional.only(start: 16 + indent, end: 16),
      leading: Icon(
        item.depth == 0 ? Icons.military_tech : Icons.group,
        color: item.depth == 0 ? Colors.blue : Colors.grey[600],
      ),
      title: Text(
        item.unit.name,
        style: TextStyle(
          fontWeight: item.depth == 0 ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: item.unit.description.isNotEmpty
          ? Text(
              item.unit.description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            )
          : null,
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: () => _selectUnit(item.unit),
    );
  }
}

class _UnitWithDepth {
  final Unit unit;
  final int depth;
  _UnitWithDepth(this.unit, this.depth);
}
