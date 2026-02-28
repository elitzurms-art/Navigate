import 'dart:async';

import 'package:flutter/material.dart';
import '../../data/repositories/voice_message_repository.dart';
import '../../domain/entities/user.dart';
import '../../domain/entities/voice_message.dart';
import '../../services/voice_service.dart';
import 'push_to_talk_button.dart';
import 'voice_message_bubble.dart';

/// מידע על מנווט (לבחירת יעד)
class NavigatorInfo {
  final String id;
  final String name;

  const NavigatorInfo({required this.id, required this.name});
}

/// פאנל הודעות קוליות — כולל רשימת הודעות + כפתור PTT
class VoiceMessagesPanel extends StatefulWidget {
  final String navigationId;
  final User currentUser;
  final VoiceService voiceService;
  final bool isCommander;
  final bool enabled;
  final List<NavigatorInfo>? navigators;

  const VoiceMessagesPanel({
    super.key,
    required this.navigationId,
    required this.currentUser,
    required this.voiceService,
    this.isCommander = false,
    this.enabled = true,
    this.navigators,
  });

  @override
  State<VoiceMessagesPanel> createState() => _VoiceMessagesPanelState();
}

class _VoiceMessagesPanelState extends State<VoiceMessagesPanel> {
  final VoiceMessageRepository _repo = VoiceMessageRepository();
  bool _isExpanded = false;
  String? _selectedTargetId;
  String? _selectedTargetName;
  final Set<String> _seenMessageIds = {};
  bool _initialLoadDone = false;
  String? _replyToId;
  String? _replyToName;

  StreamSubscription<List<VoiceMessage>>? _messagesSub;
  List<VoiceMessage> _messages = [];
  int _readUpToCount = 0;

  int get _unreadCount => (_messages.length - _readUpToCount).clamp(0, 999);

  @override
  void initState() {
    super.initState();
    _messagesSub = _repo
        .watchMessages(widget.navigationId,
            currentUserId: widget.currentUser.uid)
        .listen(_onMessagesUpdate);
  }

  @override
  void dispose() {
    _messagesSub?.cancel();
    super.dispose();
  }

  void _onMessagesUpdate(List<VoiceMessage> messages) {
    if (!mounted) return;

    if (messages.isNotEmpty) {
      if (!_initialLoadDone) {
        // טעינה ראשונה — סימון כ"נראו" בלי השמעה
        _seenMessageIds.addAll(messages.map((m) => m.id));
        _readUpToCount = messages.length;
        _initialLoadDone = true;
        // אם ההודעה האחרונה הייתה פרטית אליי — להיכנס מיד למצב מענה פרטי
        if (!widget.isCommander) {
          final privateToMe = messages.where((m) =>
              m.targetId == widget.currentUser.uid &&
              m.senderId != widget.currentUser.uid);
          if (privateToMe.isNotEmpty) {
            _replyToId = privateToMe.first.senderId;
            _replyToName = privateToMe.first.senderName;
          }
        }
      } else {
        // הודעות חדשות מאחרים — הכנסה לתור (מהישנה לחדשה)
        for (final msg in messages.reversed) {
          if (!_seenMessageIds.contains(msg.id) &&
              msg.senderId != widget.currentUser.uid) {
            widget.voiceService.enqueueMessage(msg.audioUrl, msg.id);
            // הודעה פרטית חדשה אליי — עדכון יעד המענה
            if (!widget.isCommander &&
                msg.targetId == widget.currentUser.uid) {
              _replyToId = msg.senderId;
              _replyToName = msg.senderName;
            }
          }
          _seenMessageIds.add(msg.id);
        }
      }
    }

    setState(() => _messages = messages);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header — לחיצה לפתיחה/סגירה
          GestureDetector(
            onTap: () => setState(() {
              _isExpanded = !_isExpanded;
              if (_isExpanded) {
                _readUpToCount = _messages.length;
              }
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    Icons.headset_mic,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'ווקי טוקי',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  if (_unreadCount > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$_unreadCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  Icon(
                    _isExpanded
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_up,
                    color: Colors.grey,
                  ),
                ],
              ),
            ),
          ),

          // תוכן מורחב
          if (_isExpanded) ...[
            const Divider(height: 1),

            // בורר יעד (מפקד בלבד)
            if (widget.isCommander &&
                widget.navigators != null &&
                widget.navigators!.isNotEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: DropdownButtonFormField<String?>(
                  value: _selectedTargetId,
                  decoration: const InputDecoration(
                    labelText: 'שלח ל',
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('כולם'),
                    ),
                    ...widget.navigators!.map((nav) =>
                        DropdownMenuItem<String?>(
                          value: nav.id,
                          child: Text(nav.name),
                        )),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedTargetId = value;
                      _selectedTargetName = value != null
                          ? widget.navigators!
                              .firstWhere((n) => n.id == value)
                              .name
                          : null;
                    });
                  },
                ),
              ),

            // רשימת הודעות
            SizedBox(
              height: 250,
              child: _messages.isEmpty
                  ? Center(
                      child: Text(
                        'אין הודעות עדיין',
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    )
                  : ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final msg = _messages[index];
                        return VoiceMessageBubble(
                          message: msg,
                          isMine: msg.senderId == widget.currentUser.uid,
                          voiceService: widget.voiceService,
                        );
                      },
                    ),
            ),

            const Divider(height: 1),
          ],

          // chip מענה פרטי (מנווט בלבד — כשהמפקד שלח הודעה פרטית)
          if (!widget.isCommander && _replyToId != null)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.reply, size: 14, color: Colors.orange[700]),
                    const SizedBox(width: 6),
                    Text(
                      'מענה פרטי ← $_replyToName',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange[700],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => setState(() {
                        _replyToId = null;
                        _replyToName = null;
                      }),
                      child: Icon(Icons.close,
                          size: 14, color: Colors.orange[700]),
                    ),
                  ],
                ),
              ),
            ),

          // כפתור PTT — תמיד מוצג
          PushToTalkButton(
            enabled: widget.enabled,
            voiceService: widget.voiceService,
            onRecordingComplete: (filePath, duration) async {
              final effectiveTargetId =
                  widget.isCommander ? _selectedTargetId : _replyToId;
              final effectiveTargetName =
                  widget.isCommander ? _selectedTargetName : _replyToName;
              try {
                await _repo.sendMessage(
                  navigationId: widget.navigationId,
                  filePath: filePath,
                  duration: duration,
                  senderId: widget.currentUser.uid,
                  senderName: widget.currentUser.fullName,
                  targetId: effectiveTargetId,
                  targetName: effectiveTargetName,
                );
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('שגיאה בשליחת הודעה: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            onRecordingCanceled: () {},
          ),
        ],
      ),
    );
  }
}
