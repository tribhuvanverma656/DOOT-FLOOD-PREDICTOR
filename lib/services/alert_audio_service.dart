import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class AlertAudioService {
  static final AudioPlayer _audioPlayer = AudioPlayer();
  static bool _isPlaying = false;
  static final ValueNotifier<bool> isPlayingNotifier = ValueNotifier<bool>(false);

  static bool get isPlaying => _isPlaying;

  static Future<void> playSiren() async {
    if (_isPlaying) return;
    _isPlaying = true;
    isPlayingNotifier.value = true;
    try {
      await _audioPlayer.stop();
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      await _audioPlayer.setVolume(1.0);
      try {
        await _audioPlayer.play(AssetSource('audio/flash_flood.mp3'));
      } catch (_) {
        try {
          await _audioPlayer.play(AssetSource('flash_flood.mp3'));
        } catch (_) {
          await _audioPlayer.play(AssetSource('audio/siren.mp3'));
        }
      }
    } catch (e) {
      debugPrint("Audio Playback Error: $e");
    }
  }

  static Future<void> stopSiren() async {
    _isPlaying = false;
    isPlayingNotifier.value = false;
    try {
      await _audioPlayer.stop();
    } catch (e) {
      debugPrint("Audio Stop Error: $e");
    }
  }
}
