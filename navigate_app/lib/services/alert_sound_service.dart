import 'package:audioplayers/audioplayers.dart';
import '../domain/entities/checkpoint_punch.dart';

/// שלושה צלילי התראה לפי קטגוריה — singleton service
class AlertSoundService {
  static final AlertSoundService _instance = AlertSoundService._();
  factory AlertSoundService() => _instance;
  AlertSoundService._();

  static final _audioContext = AudioContext(
    android: AudioContextAndroid(
      usageType: AndroidUsageType.alarm,
      contentType: AndroidContentType.sonification,
      audioFocus: AndroidAudioFocus.gainTransient,
    ),
    iOS: AudioContextIOS(
      category: AVAudioSessionCategory.playback,
      options: {AVAudioSessionOptions.duckOthers},
    ),
  );

  final Map<AlertSoundCategory, _CategorySound> _sounds = {
    AlertSoundCategory.monitoring: _CategorySound('sounds/alert_beep.wav'),
    AlertSoundCategory.request: _CategorySound('sounds/request_chime.wav'),
    AlertSoundCategory.emergency: _CategorySound('sounds/emergency_siren.wav'),
  };

  /// השמע צליל עבור סוג התראה בעוצמה נתונה
  Future<void> playAlert(AlertType type, double volume) async {
    await _sounds[type.soundCategory]!.play(volume);
  }

  /// השמע צליל עבור רשימת התראות — עוצמה מקסימלית לכל קטגוריה
  Future<void> playAlerts(List<MapEntry<AlertType, double>> alertsWithVolumes) async {
    final maxPerCategory = <AlertSoundCategory, double>{};
    for (final entry in alertsWithVolumes) {
      final cat = entry.key.soundCategory;
      final vol = entry.value;
      if (vol > (maxPerCategory[cat] ?? 0)) maxPerCategory[cat] = vol;
    }
    for (final entry in maxPerCategory.entries) {
      await _sounds[entry.key]!.play(entry.value);
    }
  }

  void dispose() {
    for (final sound in _sounds.values) {
      sound.dispose();
    }
  }
}

/// צליל בודד עם AudioPlayer משותף ומנגנון cooldown
class _CategorySound {
  final String filePath;
  late final AudioPlayer _player;
  DateTime? _lastPlayed;

  _CategorySound(this.filePath) {
    _player = AudioPlayer()..setAudioContext(AlertSoundService._audioContext);
  }

  Future<void> play(double volume) async {
    if (volume <= 0) return;
    final now = DateTime.now();
    if (_lastPlayed != null && now.difference(_lastPlayed!) < const Duration(seconds: 2)) return;
    _lastPlayed = now;
    await _player.setVolume(volume);
    await _player.stop();
    await _player.play(AssetSource(filePath));
  }

  void dispose() {
    _player.dispose();
  }
}
