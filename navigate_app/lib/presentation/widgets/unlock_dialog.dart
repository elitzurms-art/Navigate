import 'package:flutter/material.dart';
import '../../services/device_security_service.dart';

/// דיאלוג לביטול נעילה עם קוד — מזהיר שהניווט ייפסל
class UnlockDialog extends StatefulWidget {
  final String correctCode;
  final SecurityLevel securityLevel;
  final VoidCallback? onDisqualificationConfirmed;

  const UnlockDialog({
    super.key,
    required this.correctCode,
    required this.securityLevel,
    this.onDisqualificationConfirmed,
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

    // דיאלוג אישור כפול — אזהרה על פסילה
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.red[700]),
            const SizedBox(width: 12),
            const Text('אזהרה — פסילת ניווט'),
          ],
        ),
        content: const Text(
          'ביטול הנעילה יפסול את הניווט שלך.\n'
          'הציון שלך יהיה 0 והמפקד יקבל התראה.\n\n'
          'האם אתה בטוח?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('חזרה'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('אני מבין, בטל נעילה'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isUnlocking = true;
      _errorMessage = null;
    });

    // פסילה לפני ביטול נעילה
    widget.onDisqualificationConfirmed?.call();

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
      title: Row(
        children: [
          Icon(Icons.lock_open, color: Colors.red[700]),
          const SizedBox(width: 12),
          const Text('ביטול נעילה'),
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

          // הודעת אזהרה
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red[300]!),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.red[700], size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'ביטול נעילה יפסול את הניווט שלך — ציון 0',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.red[900],
                      fontWeight: FontWeight.bold,
                    ),
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
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}
