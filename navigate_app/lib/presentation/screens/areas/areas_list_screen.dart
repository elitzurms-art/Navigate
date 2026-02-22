import 'dart:async';
import 'package:flutter/material.dart';
import '../../../domain/entities/area.dart';
import '../../../data/repositories/area_repository.dart';
import '../../../data/sync/sync_manager.dart';
import '../../../core/constants/app_constants.dart';
import '../../../services/auth_service.dart';
import 'create_area_screen.dart';
import 'area_details_screen.dart';

/// מסך רשימת אזורים
class AreasListScreen extends StatefulWidget {
  const AreasListScreen({super.key});

  @override
  State<AreasListScreen> createState() => _AreasListScreenState();
}

class _AreasListScreenState extends State<AreasListScreen> with WidgetsBindingObserver {
  final AreaRepository _areaRepository = AreaRepository();
  final AuthService _authService = AuthService();
  List<Area> _areas = [];
  bool _isLoading = true;
  StreamSubscription<String>? _syncSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAreas();
    _syncSubscription = SyncManager().onDataChanged.listen((collection) {
      if (collection == AppConstants.areasCollection && mounted) {
        _loadAreas();
      }
    });
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadAreas();
    }
  }

  Future<void> _loadAreas() async {
    setState(() => _isLoading = true);
    try {
      final areas = await _areaRepository.getAll();
      setState(() {
        _areas = areas;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בטעינת אזורים: $e'),
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
        title: const Text('אזורים'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAreas,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _areas.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.map,
                        size: 100,
                        color: Colors.grey[300],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'אין אזורים עדיין',
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  color: Colors.grey[600],
                                ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'לחץ על + להוספת אזור חדש',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.grey[500],
                            ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _areas.length,
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 80),
                  itemBuilder: (context, index) {
                    final area = _areas[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              Theme.of(context).primaryColor.withOpacity(0.2),
                          child: Icon(
                            Icons.map,
                            color: Theme.of(context).primaryColor,
                          ),
                        ),
                        title: Text(area.name),
                        subtitle: Text(area.description),
                        trailing: PopupMenuButton(
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'edit',
                              child: Row(
                                children: [
                                  Icon(Icons.edit),
                                  SizedBox(width: 8),
                                  Text('ערוך'),
                                ],
                              ),
                            ),
                          ],
                          onSelected: (value) async {
                            if (value == 'edit') {
                              final result = await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      CreateAreaScreen(area: area),
                                ),
                              );
                              if (result == true) {
                                _loadAreas();
                              }
                            }
                          },
                        ),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  AreaDetailsScreen(area: area),
                            ),
                          );
                          _loadAreas();
                        },
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const CreateAreaScreen(),
            ),
          );
          if (result == true) {
            _loadAreas();
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }

}

