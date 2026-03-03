import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// שירות הקלטה והשמעה קולית (PTT)
class VoiceService {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  final AudioPlayer _beepPlayer = AudioPlayer();
  String? _beepFilePath;

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
    final audioContext = AudioContext(
      android: AudioContextAndroid(
        usageType: AndroidUsageType.alarm,
        contentType: AndroidContentType.speech,
        audioFocus: AndroidAudioFocus.gain,
      ),
    );

    // הגדרת audio context עם USAGE_ALARM כדי לעקוף DND
    _player.setAudioContext(audioContext);
    _beepPlayer.setAudioContext(audioContext);

    // עוצמה מקסימלית
    _player.setVolume(1.0);
    _beepPlayer.setVolume(1.0);

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

  /// יצירת קובץ WAV עם צליל roger beep (1000Hz+1400Hz, 200ms)
  Future<String> _ensureBeepFile() async {
    if (_beepFilePath != null) return _beepFilePath!;

    const sampleRate = 22050;
    const bitsPerSample = 16;
    const numChannels = 1;
    const tone1Freq = 1000.0;
    const tone2Freq = 1400.0;
    const toneDurationMs = 100;
    const samplesPerTone = sampleRate * toneDurationMs ~/ 1000; // 2205
    const totalSamples = samplesPerTone * 2;
    const dataSize = totalSamples * (bitsPerSample ~/ 8);
    const amplitude = 28000; // ~85% of max 32767

    final bytes = ByteData(44 + dataSize);

    // WAV header
    // "RIFF"
    bytes.setUint8(0, 0x52);
    bytes.setUint8(1, 0x49);
    bytes.setUint8(2, 0x46);
    bytes.setUint8(3, 0x46);
    bytes.setUint32(4, 36 + dataSize, Endian.little); // file size - 8
    // "WAVE"
    bytes.setUint8(8, 0x57);
    bytes.setUint8(9, 0x41);
    bytes.setUint8(10, 0x56);
    bytes.setUint8(11, 0x45);
    // "fmt "
    bytes.setUint8(12, 0x66);
    bytes.setUint8(13, 0x6D);
    bytes.setUint8(14, 0x74);
    bytes.setUint8(15, 0x20);
    bytes.setUint32(16, 16, Endian.little); // chunk size
    bytes.setUint16(20, 1, Endian.little); // PCM
    bytes.setUint16(22, numChannels, Endian.little);
    bytes.setUint32(24, sampleRate, Endian.little);
    bytes.setUint32(
        28, sampleRate * numChannels * (bitsPerSample ~/ 8), Endian.little);
    bytes.setUint16(32, numChannels * (bitsPerSample ~/ 8), Endian.little);
    bytes.setUint16(34, bitsPerSample, Endian.little);
    // "data"
    bytes.setUint8(36, 0x64);
    bytes.setUint8(37, 0x61);
    bytes.setUint8(38, 0x74);
    bytes.setUint8(39, 0x61);
    bytes.setUint32(40, dataSize, Endian.little);

    // טון 1: 1000Hz
    for (var i = 0; i < samplesPerTone; i++) {
      final sample =
          (amplitude * sin(2 * pi * tone1Freq * i / sampleRate)).toInt();
      bytes.setInt16(44 + i * 2, sample, Endian.little);
    }

    // טון 2: 1400Hz
    for (var i = 0; i < samplesPerTone; i++) {
      final sample =
          (amplitude * sin(2 * pi * tone2Freq * i / sampleRate)).toInt();
      bytes.setInt16(44 + (samplesPerTone + i) * 2, sample, Endian.little);
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/roger_beep.wav');
    await file.writeAsBytes(bytes.buffer.asUint8List());
    _beepFilePath = file.path;
    return _beepFilePath!;
  }

  /// השמעת ביפ מכשיר קשר
  Future<void> _playBeep() async {
    try {
      final path = await _ensureBeepFile();
      final completer = Completer<void>();
      late StreamSubscription sub;
      sub = _beepPlayer.onPlayerComplete.listen((_) {
        sub.cancel();
        completer.complete();
      });
      await _beepPlayer.play(DeviceFileSource(path));
      await completer.future;
    } catch (_) {
      // אם הביפ נכשל — ממשיך להשמעת ההודעה
    }
  }

  /// השמעה פנימית (ללא ניקוי תור)
  Future<void> _playImmediate(String audioUrl, String messageId,
      {bool playBeep = true}) async {
    if (_currentPlayingMessageId != null) {
      await _player.stop();
    }
    _currentPlayingMessageId = messageId;
    if (playBeep) {
      await _playBeep();
    }
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
    _beepPlayer.dispose();
    _recordingDurationController.close();
    _playbackPositionController.close();
  }
}
