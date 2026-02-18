import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/voice_service.dart';

/// כפתור Push-To-Talk — לחיצה ארוכה להקלטה, החלקה לביטול
class PushToTalkButton extends StatefulWidget {
  final bool enabled;
  final VoiceService voiceService;
  final void Function(String filePath, double duration)? onRecordingComplete;
  final VoidCallback? onRecordingCanceled;

  const PushToTalkButton({
    super.key,
    required this.enabled,
    required this.voiceService,
    this.onRecordingComplete,
    this.onRecordingCanceled,
  });

  @override
  State<PushToTalkButton> createState() => _PushToTalkButtonState();
}

enum _PttState { idle, recording, canceling }

class _PushToTalkButtonState extends State<PushToTalkButton>
    with SingleTickerProviderStateMixin {
  _PttState _state = _PttState.idle;
  double _dragOffset = 0;
  StreamSubscription<int>? _durationSub;
  int _seconds = 0;
  late AnimationController _pulseController;

  static const double _cancelThreshold = 100;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
  }

  @override
  void dispose() {
    _durationSub?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _onLongPressStart(LongPressStartDetails details) async {
    if (!widget.enabled) return;

    final hasPermission =
        await widget.voiceService.requestMicrophonePermission();
    if (!hasPermission) return;

    await widget.voiceService.startRecording();
    _durationSub = widget.voiceService.recordingDuration.listen((s) {
      if (mounted) setState(() => _seconds = s);
    });

    if (mounted) {
      setState(() {
        _state = _PttState.recording;
        _dragOffset = 0;
      });
      _pulseController.repeat(reverse: true);
    }
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    if (_state == _PttState.idle) return;

    // RTL: החלקה ימינה (חיובית) לביטול
    final dx = details.offsetFromOrigin.dx;
    setState(() {
      _dragOffset = dx;
      _state = dx > _cancelThreshold ? _PttState.canceling : _PttState.recording;
    });
  }

  void _onLongPressEnd(LongPressEndDetails details) async {
    _durationSub?.cancel();
    _pulseController.stop();

    if (_state == _PttState.canceling) {
      await widget.voiceService.cancelRecording();
      widget.onRecordingCanceled?.call();
    } else if (_state == _PttState.recording) {
      final result = await widget.voiceService.stopRecording();
      if (result != null) {
        widget.onRecordingComplete?.call(result.path, result.duration);
      }
    }

    if (mounted) {
      setState(() {
        _state = _PttState.idle;
        _seconds = 0;
        _dragOffset = 0;
      });
    }
  }

  String _formatDuration(int seconds) {
    final remaining = 30 - seconds;
    return '0:${remaining.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCanceling = _state == _PttState.canceling;
    final isRecording = _state == _PttState.recording;
    final isActive = isRecording || isCanceling;

    return GestureDetector(
      onLongPressStart: _onLongPressStart,
      onLongPressMoveUpdate: _onLongPressMoveUpdate,
      onLongPressEnd: _onLongPressEnd,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // הודעת ביטול
            if (isActive)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  isCanceling ? 'שחרר לביטול' : '<< החלק לביטול',
                  style: TextStyle(
                    color: isCanceling ? Colors.red : Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
              ),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // טיימר
                if (isActive)
                  Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Text(
                      _formatDuration(_seconds),
                      style: TextStyle(
                        color: isCanceling ? Colors.red : theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),

                // כפתור מיקרופון
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    final scale = isActive
                        ? 1.0 + (_pulseController.value * 0.15)
                        : 1.0;
                    return Transform.scale(
                      scale: scale,
                      child: child,
                    );
                  },
                  child: Container(
                    width: isActive ? 64 : 48,
                    height: isActive ? 64 : 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: !widget.enabled
                          ? Colors.grey[300]
                          : isCanceling
                              ? Colors.red
                              : isRecording
                                  ? Colors.red[700]
                                  : theme.colorScheme.primary,
                      boxShadow: isActive
                          ? [
                              BoxShadow(
                                color: (isCanceling ? Colors.red : Colors.red[700]!)
                                    .withValues(alpha: 0.4),
                                blurRadius: 12,
                                spreadRadius: 2,
                              )
                            ]
                          : null,
                    ),
                    child: Icon(
                      isCanceling ? Icons.close : Icons.mic,
                      color: Colors.white,
                      size: isActive ? 32 : 24,
                    ),
                  ),
                ),

                // גלי סאונד
                if (isRecording && !isCanceling)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Row(
                      children: List.generate(4, (i) {
                        return AnimatedBuilder(
                          animation: _pulseController,
                          builder: (context, _) {
                            final height = 8.0 +
                                (_pulseController.value * (8.0 + i * 4));
                            return Container(
                              width: 3,
                              height: height,
                              margin: const EdgeInsets.symmetric(horizontal: 1),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            );
                          },
                        );
                      }),
                    ),
                  ),
              ],
            ),

            // טקסט עזרה
            if (!isActive)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  widget.enabled ? 'לחיצה ארוכה לדיבור' : 'ווקי טוקי מושבת',
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 11,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
