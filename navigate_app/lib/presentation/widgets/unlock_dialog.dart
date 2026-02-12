import 'package:flutter/material.dart';
import '../../services/device_security_service.dart';

/// דיאלוג לביטול נעילה עם קוד
class UnlockDialog extends StatefulWidget {
  final String correctCode;
  final SecurityLevel securityLevel;

  const UnlockDialog({
    super.key,
    required this.correctCode,
    required this.securityLevel,
  });

  @override
  State<UnlockDialog> createState() => _UnlockDialogState();
}

class _UnlockDialogState extends State<UnlockDialog> {
  final TextEditingController _codeController = TextEditingController();
  final DeviceSecurityService _securityService = DeviceSecurityService();
  bool _isUnlocking = false;
  String? _errorMessage;

  Future<void> _attemptUnlock() async {
    final code = _codeController.text;

    if (code.isEmpty) {
      setState(() => _errorMessage = 'נא להזין קוד');
      return;
    }

    if (code != widget.correctCode) {
      setState(() => _errorMessage = 'קוד שגוי');
      return;
    }

    setState(() {
      _isUnlocking = true;
      _errorMessage = null;
    });

    bool success = false;

    try {
      switch (widget.securityLevel) {
        case SecurityLevel.lockTask:
          success = await _securityService.disableLockTask(code);
          break;
        case SecurityLevel.kioskMode:
          success = await _securityService.disableKioskMode(code);
          break;
        default:
          success = true; // iOS או Desktop
      }

      if (success && mounted) {
        Navigator.pop(context, true);
      } else {
        setState(() {
          _errorMessage = 'שגיאה בביטול נעילה';
          _isUnlocking = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'שגיאה: $e';
        _isUnlocking = false;
      });
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.lock_open, color: Colors.orange),
          SizedBox(width: 12),
          Text('ביטול נעילה'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'הזן קוד מדריך לביטול נעילת הניווט',
            style: TextStyle(color: Colors.grey[700]),
          ),
          const SizedBox(height: 20),

          // שדה קוד
          TextField(
            controller: _codeController,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: 'קוד ביטול',
              prefixIcon: const Icon(Icons.pin),
              errorText: _errorMessage,
              filled: true,
            ),
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            autofocus: true,
            enabled: !_isUnlocking,
            onSubmitted: (_) => _attemptUnlock(),
          ),

          const SizedBox(height: 16),

          // הערת אזהרה
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red[200]!),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.red[700], size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'ביטול נעילה יירשם כחריגת אבטחה',
                    style: TextStyle(fontSize: 12, color: Colors.red[900]),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isUnlocking ? null : () => Navigator.pop(context, false),
          child: const Text('ביטול'),
        ),
        ElevatedButton.icon(
          onPressed: _isUnlocking ? null : _attemptUnlock,
          icon: _isUnlocking
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.lock_open),
          label: Text(_isUnlocking ? 'מבטל נעילה...' : 'בטל נעילה'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}
