import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../domain/entities/user_role.dart';
import '../../../domain/entities/unit.dart' as domain;
import '../../../domain/entities/user.dart' as app_user;
import '../../../data/repositories/unit_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../services/auth_service.dart';

/// מסך בחירת מצב אורח (לבדיקות)
class GuestModeScreen extends StatelessWidget {
  const GuestModeScreen({super.key});

  Future<void> _selectGuestMode(BuildContext context, UserRole role) async {
    // שמירת התפקיד
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('guest_role', role.code);
    await prefs.setString('guest_name', role.displayName);

    if (context.mounted) {
      Navigator.of(context).pushReplacementNamed('/home');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('נכנסת כ${role.displayName}'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _selectUnitAdminMode(BuildContext context) async {
    // טעינת יחידות ומשתמשים קיימים
    final unitRepo = UnitRepository();
    final userRepo = UserRepository();
    final units = await unitRepo.getAll();
    final allUsers = await userRepo.getAll();

    if (!context.mounted) return;

    // בחירת משתמש קיים + בחירת יחידה
    app_user.User? selectedUser;
    domain.Unit? selectedUnit;
    List<domain.Unit> managedUnits = []; // יחידות שהמשתמש מנהל

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('מצב אורח - מנהל מערכת'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('בחר משתמש:'),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () async {
                      final picked = await showDialog<app_user.User>(
                        context: context,
                        builder: (ctx) => _GuestUserSelectionDialog(
                          users: allUsers,
                        ),
                      );
                      if (picked != null) {
                        setDialogState(() {
                          selectedUser = picked;
                          // סינון יחידות — רק יחידות שהמשתמש מנהל
                          managedUnits = units
                              .where((u) => u.managerIds.contains(picked.uid))
                              .toList();
                          // בחירה אוטומטית אם יש רק יחידה אחת
                          if (managedUnits.length == 1) {
                            selectedUnit = managedUnits.first;
                          } else {
                            selectedUnit = null;
                          }
                        });
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person),
                        suffixIcon: Icon(Icons.arrow_drop_down),
                      ),
                      child: Text(
                        selectedUser?.fullName ?? 'בחר משתמש',
                        style: TextStyle(
                          color: selectedUser != null ? null : Colors.grey[600],
                        ),
                      ),
                    ),
                  ),
                  if (selectedUser != null && managedUnits.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    DropdownButtonFormField<domain.Unit>(
                      value: selectedUnit,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'בחר יחידה',
                        prefixIcon: Icon(Icons.military_tech),
                      ),
                      items: managedUnits.map((unit) {
                        return DropdownMenuItem(
                          value: unit,
                          child: Text(unit.name),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setDialogState(() {
                          selectedUnit = value;
                        });
                      },
                    ),
                  ],
                  if (selectedUser != null && managedUnits.isEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, size: 16, color: Colors.orange[700]),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'למשתמש זה אין יחידות מנוהלות',
                              style: TextStyle(fontSize: 12, color: Colors.orange[900]),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('ביטול'),
              ),
              TextButton(
                onPressed: selectedUser != null
                    ? () => Navigator.pop(context, true)
                    : null,
                style: TextButton.styleFrom(foregroundColor: Colors.indigo),
                child: const Text('אישור'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed == true && selectedUser != null) {
      // שמירת תפקיד + UID האמיתי של המשתמש הנבחר
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('guest_role', UserRole.unitAdmin.code);
      await prefs.setString('guest_name', selectedUser!.fullName);
      await prefs.setString('guest_user_uid', selectedUser!.uid);

      // ניקוי guest_unit_id ישן תמיד
      await prefs.remove('guest_unit_id');

      // שיוך יחידה
      if (selectedUnit != null) {
        await prefs.setString('guest_unit_id', selectedUnit!.id);
      }

      if (context.mounted) {
        Navigator.of(context).pushReplacementNamed('/home');

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('נכנסת כמנהל מערכת: ${selectedUser!.fullName}'),
            backgroundColor: Colors.indigo,
          ),
        );
      }
    }
  }

  Future<void> _selectNavigatorMode(BuildContext context) async {
    // בקשת שם מנווט
    final TextEditingController nameController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('מצב אורח - מנווט'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('הכנס שם מנווט:'),
            const SizedBox(height: 16),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'שם המנווט',
                hintText: 'לדוגמה: מנווט 1',
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.green),
            child: const Text('אישור'),
          ),
        ],
      ),
    );

    if (confirmed == true && nameController.text.isNotEmpty) {
      final navigatorName = nameController.text;

      // שמירת תפקיד ושם
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('guest_role', UserRole.guestNavigator.code);
      await prefs.setString('guest_name', navigatorName);

      if (context.mounted) {
        Navigator.of(context).pushReplacementNamed('/home');

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('נכנסת כמנווט: $navigatorName'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('בחירת מצב אורח'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),
            Text(
              'בחר תפקיד לבדיקה',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'מצב אורח - לבדיקות בלבד',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),

            // מפתח
            _buildRoleCard(
              context,
              role: UserRole.guestDeveloper,
              icon: Icons.code,
              color: Colors.purple,
              description: 'גישה מלאה לכל המערכת\nיצירת יחידות, מסגרות והגדרות',
              onTap: () => _selectGuestMode(context, UserRole.guestDeveloper),
            ),

            const SizedBox(height: 16),

            // מנהל מערכת יחידתי
            _buildRoleCard(
              context,
              role: UserRole.unitAdmin,
              icon: Icons.admin_panel_settings,
              color: Colors.indigo,
              description: 'ניהול יחידה\nיצירת מסגרות ואישור הרשאות',
              onTap: () => _selectUnitAdminMode(context),
            ),

            const SizedBox(height: 16),

            // מפקד
            _buildRoleCard(
              context,
              role: UserRole.guestCommander,
              icon: Icons.shield,
              color: Colors.blue,
              description: 'יצירת וניהול ניווטים\nאישור צירים והפעלת למידה',
              onTap: () => _selectGuestMode(context, UserRole.guestCommander),
            ),

            const SizedBox(height: 16),

            // מנווט
            _buildRoleCard(
              context,
              role: UserRole.guestNavigator,
              icon: Icons.person,
              color: Colors.green,
              description: 'צפייה בנקודות הציון האישיות\nעריכת ציר והגשה לאישור',
              onTap: () => _selectNavigatorMode(context),
            ),

            const Spacer(),

            // הערה
            Card(
              color: Colors.orange[50],
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber, color: Colors.orange[700]),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'מצבי אורח מיועדים לבדיקות בלבד.\nבפרודקשן יהיה התחברות מלאה עם Firebase.',
                        style: TextStyle(fontSize: 12, color: Colors.orange[900]),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleCard(
    BuildContext context, {
    required UserRole role,
    required IconData icon,
    required Color color,
    required String description,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 4,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, size: 40, color: color),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      role.displayName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

/// דיאלוג בחירת משתמש קיים למצב אורח
class _GuestUserSelectionDialog extends StatefulWidget {
  final List<app_user.User> users;

  const _GuestUserSelectionDialog({required this.users});

  @override
  State<_GuestUserSelectionDialog> createState() =>
      _GuestUserSelectionDialogState();
}

class _GuestUserSelectionDialogState extends State<_GuestUserSelectionDialog> {
  final TextEditingController _searchController = TextEditingController();
  List<app_user.User> _filteredUsers = [];

  @override
  void initState() {
    super.initState();
    _filteredUsers = widget.users;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterUsers(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredUsers = widget.users;
      } else {
        _filteredUsers = widget.users
            .where((u) =>
                u.fullName.contains(query) ||
                u.personalNumber.contains(query) ||
                u.uid.contains(query))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SimpleDialog(
        title: const Text('בחר משתמש'),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'חיפוש לפי שם',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              autofocus: true,
              onChanged: _filterUsers,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.maxFinite,
            height: 300,
            child: _filteredUsers.isEmpty
                ? const Center(
                    child: Text(
                      'לא נמצאו משתמשים',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _filteredUsers.length,
                    itemBuilder: (context, index) {
                      final user = _filteredUsers[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.indigo[100],
                          child: Text(
                            user.fullName.isNotEmpty
                                ? user.fullName[0]
                                : '?',
                            style: TextStyle(color: Colors.indigo[700]),
                          ),
                        ),
                        title: Text(user.fullName),
                        subtitle: Text(
                          '${user.role} | ${user.uid}',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[600]),
                        ),
                        onTap: () => Navigator.pop(context, user),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
