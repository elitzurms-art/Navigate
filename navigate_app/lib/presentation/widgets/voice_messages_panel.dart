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
  int _unreadCount = 0;
  int _lastSeenCount = 0;
  final Set<String> _seenMessageIds = {};
  bool _initialLoadDone = false;

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
            onTap: () => setState(() => _isExpanded = !_isExpanded),
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
              child: StreamBuilder<List<VoiceMessage>>(
                stream: _repo.watchMessages(
                  widget.navigationId,
                  currentUserId: widget.currentUser.uid,
                ),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'שגיאה בטעינת הודעות: ${snapshot.error}',
                          style: TextStyle(color: Colors.red[400], fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }

                  final messages = snapshot.data ?? [];

                  // השמעה אוטומטית של הודעות חדשות נכנסות
                  if (messages.isNotEmpty) {
                    if (!_initialLoadDone) {
                      // טעינה ראשונה — סימון כ"נראו" בלי השמעה
                      _seenMessageIds.addAll(messages.map((m) => m.id));
                      _initialLoadDone = true;
                    } else {
                      // הודעות חדשות מאחרים — הכנסה לתור (מהישנה לחדשה)
                      for (final msg in messages.reversed) {
                        if (!_seenMessageIds.contains(msg.id) &&
                            msg.senderId != widget.currentUser.uid) {
                          widget.voiceService
                              .enqueueMessage(msg.audioUrl, msg.id);
                        }
                        _seenMessageIds.add(msg.id);
                      }
                    }
                  }

                  // חישוב הודעות שלא נקראו
                  if (messages.length > _lastSeenCount) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        setState(() {
                          _unreadCount =
                              messages.length - _lastSeenCount;
                        });
                      }
                    });
                  }
                  _lastSeenCount = messages.length;
                  _unreadCount = 0;

                  if (messages.isEmpty) {
                    return Center(
                      child: Text(
                        'אין הודעות עדיין',
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    );
                  }

                  return ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      return VoiceMessageBubble(
                        message: msg,
                        isMine:
                            msg.senderId == widget.currentUser.uid,
                        voiceService: widget.voiceService,
                      );
                    },
                  );
                },
              ),
            ),

            const Divider(height: 1),
          ],

          // כפתור PTT — תמיד מוצג
          PushToTalkButton(
            enabled: widget.enabled,
            voiceService: widget.voiceService,
            onRecordingComplete: (filePath, duration) async {
              try {
                await _repo.sendMessage(
                  navigationId: widget.navigationId,
                  filePath: filePath,
                  duration: duration,
                  senderId: widget.currentUser.uid,
                  senderName: widget.currentUser.fullName,
                  targetId: _selectedTargetId,
                  targetName: _selectedTargetName,
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
