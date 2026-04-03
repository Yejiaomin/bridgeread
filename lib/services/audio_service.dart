import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class AudioService {
  static final AudioService _instance = AudioService._internal();
  factory AudioService() => _instance;
  AudioService._internal();

  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  bool _cancelled = false;

  bool get isPlaying => _isPlaying;

  /// Stream of playback position updates for the current track.
  Stream<Duration> get onPositionChanged => _player.onPositionChanged;

  /// Loads an audio source.
  Source _source(String name) {
    return AssetSource('audio/$name.mp3');
  }

  /// Play a single asset by name — resolves to assets/audio/{name}.mp3.
  Future<void> playAsset(String name) async {
    _cancelled = false;
    _isPlaying = true;
    await _player.play(_source(name));
    await _waitForTrackEnd();
    _isPlaying = false;
  }

  /// Play CN audio then EN audio in sequence.
  /// [onENStart] is called just before the EN track begins.
  /// [onComplete] is called when both tracks finish naturally.
  Future<void> playSequence(
    String cn,
    String en, {
    VoidCallback? onENStart,
    VoidCallback? onComplete,
  }) async {
    _cancelled = false;
    _isPlaying = true;

    // Play CN track
    await _player.play(_source(cn));
    await _waitForTrackEnd();

    if (_cancelled) {
      _isPlaying = false;
      return;
    }

    // 0.5s gap between CN and EN
    await Future.delayed(const Duration(milliseconds: 500));
    if (_cancelled) {
      _isPlaying = false;
      return;
    }

    // CN finished — notify caller
    onENStart?.call();

    // Play EN track
    await _player.play(_source(en));
    await _waitForTrackEnd();

    _isPlaying = false;
    if (!_cancelled) onComplete?.call();
  }

  /// Pause playback without cancelling the sequence.
  Future<void> pause() async {
    try { await _player.pause(); } catch (_) {}
  }

  /// Resume a paused playback.
  Future<void> resume() async {
    try { await _player.resume(); } catch (_) {}
  }

  /// Stop all audio and cancel any running sequence.
  Future<void> stop() async {
    _cancelled = true;
    _isPlaying = false;
    try {
      await _player.stop();
    } catch (_) {}
  }

  void dispose() {
    _player.dispose();
  }

  Future<void> _waitForTrackEnd() async {
    final completer = Completer<void>();
    late StreamSubscription<PlayerState> sub;
    sub = _player.onPlayerStateChanged.listen((state) {
      if ((state == PlayerState.completed || state == PlayerState.stopped) &&
          !completer.isCompleted) {
        completer.complete();
        sub.cancel();
      }
    });
    await completer.future;
  }
}
