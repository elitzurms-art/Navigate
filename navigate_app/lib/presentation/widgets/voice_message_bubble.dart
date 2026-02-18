import 'package:flutter/material.dart';
import '../../domain/entities/voice_message.dart';
import '../../services/voice_service.dart';

/// בועת הודעה קולית בסגנון WhatsApp
class VoiceMessageBubble extends StatefulWidget {
  final VoiceMessage message;
  final bool isMine;
  final VoiceService voiceService;

  const VoiceMessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.voiceService,
  });

  @override
  State<VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<VoiceMessageBubble> {
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    widget.voiceService.playbackPosition.listen((pos) {
      if (mounted &&
          widget.voiceService.currentPlayingMessageId == widget.message.id) {
        setState(() => _position = pos);
      }
    });
  }

  bool get _isPlaying =>
      widget.voiceService.currentPlayingMessageId == widget.message.id;

  String _formatDuration(double seconds) {
    final mins = seconds ~/ 60;
    final secs = (seconds % 60).toInt();
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final msg = widget.message;
    final totalDuration = Duration(milliseconds: (msg.duration * 1000).toInt());
    final progress = totalDuration.inMilliseconds > 0
        ? (_position.inMilliseconds / totalDuration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    // RTL: הודעות שלי מימין (רקע כחול), אחרים משמאל (רקע אפור)
    final bgColor = widget.isMine
        ? theme.colorScheme.primary.withValues(alpha: 0.15)
        : Colors.grey[200]!;

    final alignment =
        widget.isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Column(
        crossAxisAlignment: alignment,
        children: [
          Container(
            constraints: const BoxConstraints(maxWidth: 280),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // שם שולח + יעד
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // אות ראשונה כ-avatar
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: widget.isMine
                          ? theme.colorScheme.primary
                          : Colors.grey[400],
                      child: Text(
                        msg.senderName.isNotEmpty
                            ? msg.senderName[0]
                            : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        msg.senderName,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: theme.colorScheme.primary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (msg.targetId != null) ...[
                      const SizedBox(width: 4),
                      Text(
                        '← ${msg.targetName ?? ""}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                        ),
                      ),
                    ] else ...[
                      const SizedBox(width: 4),
                      Text(
                        'כולם',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ],
                ),

                const SizedBox(height: 6),

                // פלייר
                Row(
                  children: [
                    // כפתור play/pause
                    GestureDetector(
                      onTap: () {
                        if (_isPlaying) {
                          widget.voiceService.pauseMessage();
                        } else {
                          widget.voiceService
                              .playMessage(msg.audioUrl, msg.id);
                        }
                        setState(() {});
                      },
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.colorScheme.primary,
                        ),
                        child: Icon(
                          _isPlaying ? Icons.pause : Icons.play_arrow,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),

                    const SizedBox(width: 8),

                    // Progress bar + waveform
                    Expanded(
                      child: Column(
                        children: [
                          // Waveform simulation
                          SizedBox(
                            height: 24,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: List.generate(20, (i) {
                                final barProgress = i / 20;
                                final isPlayed = barProgress <= progress;
                                // Simulated waveform heights
                                final heights = [
                                  0.4, 0.7, 0.5, 0.9, 0.6, 0.8, 0.3, 0.7,
                                  0.5, 0.9, 0.4, 0.6, 0.8, 0.5, 0.7, 0.3,
                                  0.6, 0.9, 0.5, 0.4,
                                ];
                                return Expanded(
                                  child: Container(
                                    margin:
                                        const EdgeInsets.symmetric(horizontal: 0.5),
                                    height: 24 * heights[i],
                                    decoration: BoxDecoration(
                                      color: isPlayed
                                          ? theme.colorScheme.primary
                                          : Colors.grey[400],
                                      borderRadius: BorderRadius.circular(1),
                                    ),
                                  ),
                                );
                              }),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 8),

                    // משך
                    Text(
                      _isPlaying
                          ? _formatDuration(
                              (totalDuration - _position).inSeconds.toDouble())
                          : _formatDuration(msg.duration),
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // שעה
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 4, left: 4),
            child: Text(
              '${msg.createdAt.hour.toString().padLeft(2, '0')}:${msg.createdAt.minute.toString().padLeft(2, '0')}',
              style: TextStyle(fontSize: 10, color: Colors.grey[500]),
            ),
          ),
        ],
      ),
    );
  }
}
