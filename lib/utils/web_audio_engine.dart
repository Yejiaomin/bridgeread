import 'dart:async';
import 'dart:js_interop';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'cdn_asset.dart';

// ── JS interop ──────────────────────────────────────────────────────────────

@JS('window._brWebAudio.play')
external void _jsPlay(JSString url);
@JS('window._brWebAudio.pause')
external void _jsPause();
@JS('window._brWebAudio.resume')
external void _jsResume();
@JS('window._brWebAudio.stop')
external void _jsStop();
@JS('window._brWebAudio.seek')
external void _jsSeek(JSNumber ms);
@JS('window._brWebAudio.isPlaying')
external JSBoolean _jsIsPlaying();
@JS('window._brWebAudio.getDuration')
external JSNumber _jsGetDuration();
@JS('window._brWebAudio.getPosition')
external JSNumber _jsGetPosition();
@JS('window._brWebAudio.onEnd')
external void _jsOnEnd(JSFunction cb);
@JS('window._brWebAudio.onPosition')
external void _jsOnPosition(JSFunction cb);
@JS('window._brWebAudio.playSfx')
external void _jsPlaySfx(JSString url);
@JS('window._brWebAudio.preload')
external JSPromise<JSAny?> _jsPreload(JSString url);

// ── GameAudioPlayer (main audio — narration, words, phonemes) ───────────────

/// Unified audio player using Web Audio API on web, audioplayers on mobile.
///
/// Web Audio API advantage: AudioContext only needs ONE user gesture to unlock.
/// After that, ALL plays via createBufferSource().start() work from any context
/// (timers, callbacks, async). This is guaranteed by the Web Audio spec.
class GameAudioPlayer {
  AudioPlayer? _native;
  StreamController<void>? _onCompleteCtrl;
  StreamController<Duration>? _onPositionCtrl;
  bool _webCallbacksSet = false;

  GameAudioPlayer() {
    if (!kIsWeb) _native = AudioPlayer();
  }

  /// Play from audio-relative path, e.g. 'audio/biscuit_p1_cn.mp3'
  Future<void> playAudio(String audioPath) async {
    if (kIsWeb) {
      _ensureWebCallbacks();
      _jsPlay('assets/assets/$audioPath'.toJS);
    } else {
      await _native!.play(cdnAudioSource(audioPath));
    }
  }

  /// Play from full asset path, e.g. 'assets/audio/phonemes/bingo.mp3'
  Future<void> playAssetPath(String assetPath) async {
    final path = assetPath.startsWith('assets/') ? assetPath.substring(7) : assetPath;
    await playAudio(path);
  }

  void pause() {
    if (kIsWeb) _jsPause(); else _native?.pause();
  }

  void resume() {
    if (kIsWeb) _jsResume(); else _native?.resume();
  }

  void stop() {
    if (kIsWeb) _jsStop(); else _native?.stop();
  }

  void seek(Duration position) {
    if (kIsWeb) _jsSeek(position.inMilliseconds.toJS); else _native?.seek(position);
  }

  bool get isPlaying {
    if (kIsWeb) return _jsIsPlaying().toDart;
    return _native?.state == PlayerState.playing;
  }

  int get durationMs {
    if (kIsWeb) return _jsGetDuration().toDartInt;
    return 0;
  }

  Stream<void> get onPlayerComplete {
    if (kIsWeb) { _ensureWebCallbacks(); return _onCompleteCtrl!.stream; }
    return _native!.onPlayerComplete;
  }

  Stream<Duration> get onPositionChanged {
    if (kIsWeb) { _ensureWebCallbacks(); return _onPositionCtrl!.stream; }
    return _native!.onPositionChanged;
  }

  Stream<Duration> get onDurationChanged {
    if (kIsWeb) return const Stream.empty();
    return _native!.onDurationChanged;
  }

  void dispose() {
    if (kIsWeb) { _jsStop(); _onCompleteCtrl?.close(); _onPositionCtrl?.close(); }
    else { _native?.dispose(); }
  }

  void _ensureWebCallbacks() {
    if (_webCallbacksSet) return;
    _webCallbacksSet = true;
    _onCompleteCtrl = StreamController<void>.broadcast();
    _onPositionCtrl = StreamController<Duration>.broadcast();
    _jsOnEnd((() { _onCompleteCtrl?.add(null); }).toJS);
    _jsOnPosition(((JSNumber ms) {
      _onPositionCtrl?.add(Duration(milliseconds: ms.toDartInt));
    }).toJS);
  }
}

// ── GameSfxPlayer (fire-and-forget, overlaps with main) ─────────────────────

class GameSfxPlayer {
  AudioPlayer? _native;
  GameSfxPlayer() { if (!kIsWeb) _native = AudioPlayer(); }

  void playAudio(String audioPath) {
    if (kIsWeb) {
      _jsPlaySfx('assets/assets/$audioPath'.toJS);
    } else {
      try { _native?.play(cdnAudioSource(audioPath)); } catch (_) {}
    }
  }

  void playAssetPath(String assetPath) {
    final path = assetPath.startsWith('assets/') ? assetPath.substring(7) : assetPath;
    playAudio(path);
  }

  void dispose() { _native?.dispose(); }
}
