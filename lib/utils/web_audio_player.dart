import 'dart:async';
import 'dart:js_interop';

/// Dart wrapper for the persistent HTML5 Audio element (web/audio-player.js).
/// Uses a single <audio> element that survives across track changes,
/// so iOS Safari doesn't block play() from timer callbacks.
class WebAudioPlayer {
  StreamController<void>? _onCompleteCtrl;
  StreamController<Duration>? _onPositionCtrl;
  bool _callbacksRegistered = false;

  Stream<void> get onComplete {
    _onCompleteCtrl ??= StreamController<void>.broadcast();
    _ensureCallbacks();
    return _onCompleteCtrl!.stream;
  }

  Stream<Duration> get onPositionChanged {
    _onPositionCtrl ??= StreamController<Duration>.broadcast();
    _ensureCallbacks();
    return _onPositionCtrl!.stream;
  }

  void _ensureCallbacks() {
    if (_callbacksRegistered) return;
    _callbacksRegistered = true;

    _jsOnEnd((() {
      _onCompleteCtrl?.add(null);
    }).toJS);

    _jsOnPosition(((JSNumber ms) {
      _onPositionCtrl?.add(Duration(milliseconds: ms.toDartInt));
    }).toJS);
  }

  /// Play audio from an asset path (relative to /assets/).
  /// On web, Flutter assets are served at /assets/assets/...
  void play(String assetPath) {
    // Flutter web serves assets at: /assets/{assetPath}
    // AssetSource('audio/file.mp3') → URL: /assets/assets/audio/file.mp3
    final url = 'assets/assets/$assetPath';
    _jsPlay(url.toJS);
  }

  void pause() => _jsPause();
  void resume() => _jsResume();
  void stop() => _jsStop();

  bool get isPlaying => _jsIsPlaying().toDart;

  void dispose() {
    _jsStop();
    _onCompleteCtrl?.close();
    _onPositionCtrl?.close();
  }
}

@JS('window._brAudio.play')
external void _jsPlay(JSString url);

@JS('window._brAudio.pause')
external void _jsPause();

@JS('window._brAudio.resume')
external void _jsResume();

@JS('window._brAudio.stop')
external void _jsStop();

@JS('window._brAudio.onEnd')
external void _jsOnEnd(JSFunction callback);

@JS('window._brAudio.onPosition')
external void _jsOnPosition(JSFunction callback);

@JS('window._brAudio.isPlaying')
external JSBoolean _jsIsPlaying();
