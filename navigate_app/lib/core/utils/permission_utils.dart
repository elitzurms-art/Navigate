import 'package:flutter/material.dart';
import 'package:navigate_app/domain/entities/user.dart';

class PermissionUtils {
  static bool checkManagement(BuildContext context, User? user) {
    if (user?.isManagement ?? false) return true;
    _showSnackbar(context);
    return false;
  }

  static bool checkManagementFlag(BuildContext context, bool isManagement) {
    if (isManagement) return true;
    _showSnackbar(context);
    return false;
  }

  static void _showSnackbar(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('אין לך הרשאה לבצע פעולה זו\nרק מנהל יחידה יכול לבצע אותה'),
        backgroundColor: Colors.orange,
      ),
    );
  }
}
