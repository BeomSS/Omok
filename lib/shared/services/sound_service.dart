import 'package:audioplayers/audioplayers.dart';

/// Contract for offline game sound effects.
abstract class SoundService {
  Future<void> playStonePlace();
  Future<void> playWin();
  Future<void> playLose();
  Future<void> playForbidden();
  void dispose();
}

/// Offline asset-backed sound service using `audioplayers`.
class AudioPlayerSoundService implements SoundService {
  AudioPlayerSoundService()
      : _stonePlayer = AudioPlayer()..setReleaseMode(ReleaseMode.stop),
        _effectPlayer = AudioPlayer()..setReleaseMode(ReleaseMode.stop);

  final AudioPlayer _stonePlayer;
  final AudioPlayer _effectPlayer;

  @override
  Future<void> playStonePlace() => _safePlay(
        _stonePlayer,
        'sounds/stone_place.wav',
        volume: 0.9,
      );

  @override
  Future<void> playWin() => _safePlay(
        _effectPlayer,
        'sounds/win_chime.wav',
        volume: 0.75,
      );

  @override
  Future<void> playLose() => _safePlay(
        _effectPlayer,
        'sounds/lose_tone.wav',
        volume: 0.7,
      );

  @override
  Future<void> playForbidden() => _safePlay(
        _effectPlayer,
        'sounds/forbidden_tap.wav',
        volume: 0.75,
      );

  Future<void> _safePlay(
    AudioPlayer player,
    String assetPath, {
    required double volume,
  }) async {
    try {
      await player.stop();
      await player.setVolume(volume);
      await player.play(AssetSource(assetPath));
    } catch (_) {
      // Never block gameplay if audio subsystem is unavailable.
    }
  }

  @override
  void dispose() {
    _stonePlayer.dispose();
    _effectPlayer.dispose();
  }
}

/// Silent no-op sound service for deterministic widget tests.
class SilentSoundService implements SoundService {
  const SilentSoundService();

  @override
  Future<void> playStonePlace() async {}

  @override
  Future<void> playWin() async {}

  @override
  Future<void> playLose() async {}

  @override
  Future<void> playForbidden() async {}

  @override
  void dispose() {}
}
