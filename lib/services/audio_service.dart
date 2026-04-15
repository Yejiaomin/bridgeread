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
  /// Wrapped to suppress "Bad state: No element" errors from audioplayers
  /// when the player is stopped but the stream is still being listened to.
  Stream<Duration> get onPositionChanged =>
      _player.onPositionChanged.handleError((_) {});

  /// Loads an audio source.
  Source _source(String name) {
    return AssetSource('audio/$name.mp3');
  }

  /// Play a single asset by name — resolves to assets/audio/{name}.mp3.
  /// Returns true if playback completed, false if failed or cancelled.
  Future<bool> playAsset(String name) async {
    _cancelled = false;
    _isPlaying = true;
    try {
      await _player.play(_source(name));
      // Verify player actually started
      await Future.delayed(const Duration(milliseconds: 50));
      if (_cancelled) { _isPlaying = false; return false; }
      final state = _player.state;
      if (state != PlayerState.playing) {
        debugPrint('[Audio] playAsset failed: player state=$state for $name');
        _isPlaying = false;
        return false;
      }
      await _waitForTrackEnd();
      _isPlaying = false;
      return !_cancelled;
    } catch (e) {
      debugPrint('[Audio] playAsset error: $e for $name');
      _isPlaying = false;
      return false;
    }
  }

  /// Play CN audio then EN audio in sequence.
  /// [onENStart] is called just before the EN track begins.
  /// [onComplete] is called when both tracks finish naturally.
  /// Returns true if both played successfully.
  Future<bool> playSequence(
    String cn,
    String en, {
    VoidCallback? onENStart,
    VoidCallback? onComplete,
  }) async {
    _cancelled = false;
    _isPlaying = true;

    // Play CN track
    bool cnOk = false;
    try {
      await _player.play(_source(cn));
      await Future.delayed(const Duration(milliseconds: 50));
      if (!_cancelled && _player.state == PlayerState.playing) {
        cnOk = true;
        await _waitForTrackEnd();
      } else {
        debugPrint('[Audio] CN play failed: state=${_player.state} for $cn');
      }
    } catch (e) {
      debugPrint('[Audio] CN play error: $e for $cn');
    }

    if (_cancelled) {
      _isPlaying = false;
      return false;
    }

    // 0.5s gap between CN and EN
    await Future.delayed(const Duration(milliseconds: 500));
    if (_cancelled) {
      _isPlaying = false;
      return false;
    }

    // CN finished — notify caller
    onENStart?.call();

    // Play EN track
    bool enOk = false;
    try {
      await _player.play(_source(en));
      await Future.delayed(const Duration(milliseconds: 50));
      if (!_cancelled && _player.state == PlayerState.playing) {
        enOk = true;
        await _waitForTrackEnd();
      } else {
        debugPrint('[Audio] EN play failed: state=${_player.state} for $en');
      }
    } catch (e) {
      debugPrint('[Audio] EN play error: $e for $en');
    }

    _isPlaying = false;
    final ok = cnOk || enOk; // at least one track played
    if (!_cancelled && ok) onComplete?.call();
    return ok;
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

    // Timeout: if audio doesn't finish in 120s, something is wrong
    final timer = Timer(const Duration(seconds: 120), () {
      if (!completer.isCompleted) {
        debugPrint('[Audio] _waitForTrackEnd timed out');
        completer.complete();
      }
    });

    sub = _player.onPlayerStateChanged.listen((state) {
      if ((state == PlayerState.completed || state == PlayerState.stopped) &&
          !completer.isCompleted) {
        completer.complete();
        sub.cancel();
      }
    });

    await completer.future;
    timer.cancel();
    sub.cancel();
  }
}
