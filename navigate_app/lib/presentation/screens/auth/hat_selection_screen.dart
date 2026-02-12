import 'package:flutter/material.dart';
import '../../../domain/entities/hat_type.dart';
import '../../../services/session_service.dart';
import '../home/home_screen.dart';
import '../home/navigator_home_screen.dart';

/// מסך בחירת יחידה + כובע
class HatSelectionScreen extends StatefulWidget {
  final List<UnitHats> unitHats;
  final bool isSwitch;

  const HatSelectionScreen({
    super.key,
    required this.unitHats,
    this.isSwitch = false,
  });

  @override
  State<HatSelectionScreen> createState() => _HatSelectionScreenState();
}

class _HatSelectionScreenState extends State<HatSelectionScreen> {
  final SessionService _sessionService = SessionService();
  UnitHats? _selectedUnit;

  @override
  void initState() {
    super.initState();
    // אם יש רק יחידה אחת — דילוג אוטומטי
    if (widget.unitHats.length == 1) {
      _selectedUnit = widget.unitHats.first;
      // אם יש רק כובע אחד — בחירה אוטומטית
      if (_selectedUnit!.hats.length == 1) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _selectHat(_selectedUnit!.hats.first);
        });
      }
    }
  }

  Future<void> _selectHat(HatInfo hat) async {
    await _sessionService.saveSession(hat);
    if (!mounted) return;

    if (hat.type == HatType.navigator) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const NavigatorHomeScreen()),
        (route) => false,
      );
    } else {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const HomeScreen()),
        (route) => false,
      );
    }
  }

  void _selectUnit(UnitHats unit) {
    setState(() {
      _selectedUnit = unit;
    });
    // אם יש רק כובע אחד — בחירה אוטומטית
    if (unit.hats.length == 1) {
      _selectHat(unit.hats.first);
    }
  }

  void _backToUnits() {
    setState(() {
      _selectedUnit = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('כניסה בתור'),
          backgroundColor: Theme.of(context).primaryColor,
          foregroundColor: Colors.white,
          leading: _selectedUnit != null && widget.unitHats.length > 1
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _backToUnits,
                )
              : widget.isSwitch
                  ? IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        Navigator.of(context).pushReplacementNamed('/home');
                      },
                    )
                  : null,
        ),
        body: _selectedUnit == null
            ? _buildUnitSelection()
            : _buildHatSelection(_selectedUnit!),
      ),
    );
  }

  /// שלב ראשון — בחירת יחידה
  Widget _buildUnitSelection() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: widget.unitHats.length,
      itemBuilder: (context, index) {
        final unit = widget.unitHats[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _selectUnit(unit),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Theme.of(context).primaryColor.withOpacity(0.15),
                    child: Icon(
                      Icons.military_tech,
                      color: Theme.of(context).primaryColor,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          unit.unitName.isNotEmpty ? unit.unitName : 'יחידה',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${unit.hats.length} תפקידים',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.arrow_forward_ios, color: Colors.grey[400], size: 20),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// שלב שני — בחירת כובע
  Widget _buildHatSelection(UnitHats unit) {
    return Column(
      children: [
        // כותרת יחידה
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: Theme.of(context).primaryColor.withOpacity(0.08),
          child: Row(
            children: [
              Icon(Icons.military_tech, color: Theme.of(context).primaryColor),
              const SizedBox(width: 8),
              Text(
                unit.unitName.isNotEmpty ? unit.unitName : 'יחידה',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).primaryColor,
                ),
              ),
            ],
          ),
        ),
        // רשימת כובעים
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: unit.hats.length,
            itemBuilder: (context, index) {
              final hat = unit.hats[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _selectHat(hat),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: _getHatColor(hat.type).withOpacity(0.15),
                          child: Icon(
                            _getHatIcon(hat.type),
                            color: _getHatColor(hat.type),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                hat.typeName,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                hat.unitName,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[600],
                                ),
                              ),
                              if (hat.subFrameworkName != null)
                                Text(
                                  hat.subFrameworkName!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[500],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _getHatColor(hat.type).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            hat.treeName,
                            style: TextStyle(
                              fontSize: 11,
                              color: _getHatColor(hat.type),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Color _getHatColor(HatType type) {
    switch (type) {
      case HatType.admin:
        return Colors.teal;
      case HatType.commander:
        return Colors.blue;
      case HatType.navigator:
        return Colors.green;
      case HatType.management:
        return Colors.purple;
      case HatType.observer:
        return Colors.orange;
    }
  }

  IconData _getHatIcon(HatType type) {
    switch (type) {
      case HatType.admin:
        return Icons.admin_panel_settings;
      case HatType.commander:
        return Icons.military_tech;
      case HatType.navigator:
        return Icons.navigation;
      case HatType.management:
        return Icons.business;
      case HatType.observer:
        return Icons.visibility;
    }
  }
}
