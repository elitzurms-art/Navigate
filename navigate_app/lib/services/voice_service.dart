import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// שירות הקלטה והשמעה קולית (PTT)
class VoiceService {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  bool _isRecording = false;
  String? _currentRecordingPath;
  DateTime? _recordingStartTime;

  String? _currentPlayingMessageId;
  final List<({String audioUrl, String messageId})> _playbackQueue = [];

  Timer? _durationTimer;
  Timer? _maxDurationTimer;

  final StreamController<int> _recordingDurationController =
      StreamController<int>.broadcast();
  final StreamController<Duration> _playbackPositionController =
      StreamController<Duration>.broadcast();

  /// האם מתבצעת הקלטה כרגע
  bool get isRecording => _isRecording;

  /// מזהה ההודעה המושמעת כרגע (null אם אין)
  String? get currentPlayingMessageId => _currentPlayingMessageId;

  /// stream של משך ההקלטה בשניות
  Stream<int> get recordingDuration => _recordingDurationController.stream;

  /// stream של מיקום ההשמעה
  Stream<Duration> get playbackPosition => _playbackPositionController.stream;

  VoiceService() {
    _player.onPositionChanged.listen((position) {
      _playbackPositionController.add(position);
    });

    _player.onPlayerComplete.listen((_) {
      _currentPlayingMessageId = null;
      _playNextInQueue();
    });
  }

  /// בקשת הרשאת מיקרופון
  Future<bool> requestMicrophonePermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  /// התחלת הקלטה
  Future<void> startRecording() async {
    if (_isRecording) return;

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      final granted = await requestMicrophonePermission();
      if (!granted) return;
    }

    final dir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    _currentRecordingPath = '${dir.path}/voice_$timestamp.m4a';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      ),
      path: _currentRecordingPath!,
    );

    _isRecording = true;
    _recordingStartTime = DateTime.now();

    // טיימר עדכון משך הקלטה
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_recordingStartTime != null) {
        final elapsed =
            DateTime.now().difference(_recordingStartTime!).inSeconds;
        _recordingDurationController.add(elapsed);
      }
    });

    // עצירה אוטומטית אחרי 30 שניות
    _maxDurationTimer = Timer(const Duration(seconds: 30), () {
      if (_isRecording) {
        stopRecording();
      }
    });
  }

  /// עצירת הקלטה — מחזיר נתיב ומשך
  Future<({String path, double duration})?> stopRecording() async {
    if (!_isRecording) return null;

    _durationTimer?.cancel();
    _maxDurationTimer?.cancel();

    final path = await _recorder.stop();
    _isRecording = false;

    if (path == null || _recordingStartTime == null) return null;

    final duration =
        DateTime.now().difference(_recordingStartTime!).inMilliseconds / 1000.0;
    _recordingStartTime = null;

    // ודא שהקובץ קיים ולא ריק
    final file = File(path);
    if (!await file.exists() || await file.length() == 0) return null;

    return (path: path, duration: duration);
  }

  /// ביטול הקלטה — עצירה + מחיקת הקובץ
  Future<void> cancelRecording() async {
    if (!_isRecording) return;

    _durationTimer?.cancel();
    _maxDurationTimer?.cancel();

    await _recorder.stop();
    _isRecording = false;
    _recordingStartTime = null;

    // מחיקת קובץ ההקלטה
    if (_currentRecordingPath != null) {
      try {
        await File(_currentRecordingPath!).delete();
      } catch (_) {}
      _currentRecordingPath = null;
    }
  }

  /// השמעה פנימית (ללא ניקוי תור)
  Future<void> _playImmediate(String audioUrl, String messageId) async {
    if (_currentPlayingMessageId != null) {
      await _player.stop();
    }
    _currentPlayingMessageId = messageId;
    await _player.play(UrlSource(audioUrl));
  }

  /// השמעת הודעה (ידנית — מנקה תור)
  Future<void> playMessage(String audioUrl, String messageId) async {
    _playbackQueue.clear();
    await _playImmediate(audioUrl, messageId);
  }

  /// הוספת הודעה לתור השמעה (auto-play)
  void enqueueMessage(String audioUrl, String messageId) {
    if (_isRecording) return;

    if (_currentPlayingMessageId == null) {
      _playImmediate(audioUrl, messageId);
    } else {
      _playbackQueue.add((audioUrl: audioUrl, messageId: messageId));
    }
  }

  /// השמעת ההודעה הבאה בתור
  void _playNextInQueue() {
    if (_playbackQueue.isNotEmpty) {
      final next = _playbackQueue.removeAt(0);
      _playImmediate(next.audioUrl, next.messageId);
    }
  }

  /// השהיית השמעה
  Future<void> pauseMessage() async {
    _playbackQueue.clear();
    await _player.pause();
    _currentPlayingMessageId = null;
  }

  /// עצירת השמעה
  Future<void> stopPlayback() async {
    _playbackQueue.clear();
    await _player.stop();
    _currentPlayingMessageId = null;
  }

  /// שחרור משאבים
  void dispose() {
    _durationTimer?.cancel();
    _maxDurationTimer?.cancel();
    _recorder.dispose();
    _player.dispose();
    _recordingDurationController.close();
    _playbackPositionController.close();
  }
}
