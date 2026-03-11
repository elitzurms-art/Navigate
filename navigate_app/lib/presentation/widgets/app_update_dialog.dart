import 'package:flutter/material.dart';
import '../../services/app_update_service.dart';

/// דיאלוג עדכון אפליקציה — כפוי או מומלץ
class AppUpdateDialog {
  AppUpdateDialog._();

  /// הצגת דיאלוג עדכון
  static Future<void> show(
    BuildContext context, {
    required bool isForced,
    required String storeUrl,
    required String title,
    required String message,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: !isForced,
      builder: (ctx) => PopScope(
        canPop: !isForced,
        child: AlertDialog(
          icon: Icon(
            Icons.system_update,
            color: isForced ? Colors.red : Colors.blue,
            size: 48,
          ),
          title: Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isForced ? Colors.red : null,
            ),
          ),
          content: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            if (!isForced)
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  AppUpdateService().saveDismissedTimestamp();
                },
                child: const Text('לא עכשיו'),
              ),
            ElevatedButton.icon(
              icon: const Icon(Icons.download),
              label: Text(isForced ? 'עדכן עכשיו' : 'עדכן'),
              style: ElevatedButton.styleFrom(
                backgroundColor: isForced ? Colors.red : Colors.blue,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              onPressed: () {
                AppUpdateService().openStore(storeUrl);
              },
            ),
          ],
        ),
      ),
    );
  }
}
