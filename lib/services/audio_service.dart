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
  Stream<Duration> get onPositionChanged =>
      _player.onPositionChanged.handleError((_) {});

  Source _source(String name) {
    return AssetSource('audio/$name.mp3');
  }

  /// Play a single asset. Returns true if completed, false if failed/cancelled.
  Future<bool> playAsset(String name) async {
    _cancelled = false;
    _isPlaying = true;
    try {
      await _player.play(_source(name));
      if (_cancelled) { _isPlaying = false; return false; }
      await _waitForTrackEnd();
      _isPlaying = false;
      return !_cancelled;
    } catch (e) {
      debugPrint('[Audio] playAsset error: $e for $name');
      _isPlaying = false;
      return false;
    }
  }

  /// Play CN then EN in sequence. Returns true if at least one track played.
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
      if (!_cancelled) {
        cnOk = true;
        await _waitForTrackEnd();
      }
    } catch (e) {
      debugPrint('[Audio] CN error: $e for $cn');
    }

    if (_cancelled) { _isPlaying = false; return false; }

    // 0.5s gap between CN and EN
    await Future.delayed(const Duration(milliseconds: 500));
    if (_cancelled) { _isPlaying = false; return false; }

    onENStart?.call();

    // Play EN track
    bool enOk = false;
    try {
      await _player.play(_source(en));
      if (!_cancelled) {
        enOk = true;
        await _waitForTrackEnd();
      }
    } catch (e) {
      debugPrint('[Audio] EN error: $e for $en');
    }

    _isPlaying = false;
    final ok = cnOk || enOk;
    if (!_cancelled && ok) onComplete?.call();
    return ok;
  }

  Future<void> pause() async {
    try { await _player.pause(); } catch (_) {}
  }

  Future<void> resume() async {
    try { await _player.resume(); } catch (_) {}
  }

  Future<void> stop() async {
    _cancelled = true;
    _isPlaying = false;
    try { await _player.stop(); } catch (_) {}
  }

  void dispose() {
    _player.dispose();
  }

  Future<void> _waitForTrackEnd() async {
    final completer = Completer<void>();
    late StreamSubscription<PlayerState> sub;

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
      }
    });

    await completer.future;
    timer.cancel();
    sub.cancel();
  }
}
