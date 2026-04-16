import 'dart:js_interop';

@JS('navigator.mediaSession')
external JSObject? get _mediaSession;

@JS('MediaMetadata')
@staticInterop
class _MediaMetadata {
  external factory _MediaMetadata(JSObject init);
}

/// Set up Media Session API for background audio on iOS Safari.
void setMediaSession({
  required String title,
  String artist = 'BridgeRead',
  void Function()? onPlay,
  void Function()? onPause,
  void Function()? onNextTrack,
  void Function()? onPreviousTrack,
}) {
  try {
    final session = _mediaSession;
    if (session == null) return;

    // Set metadata
    final init = <String, dynamic>{
      'title': title,
      'artist': artist,
    }.jsify() as JSObject;
    final metadata = _MediaMetadata(init);
    (session as dynamic).metadata = metadata;

    // Set action handlers
    if (onPlay != null) {
      _setAction(session, 'play', onPlay);
    }
    if (onPause != null) {
      _setAction(session, 'pause', onPause);
    }
    if (onNextTrack != null) {
      _setAction(session, 'nexttrack', onNextTrack);
    }
    if (onPreviousTrack != null) {
      _setAction(session, 'previoustrack', onPreviousTrack);
    }
  } catch (_) {}
}

/// Clear media session.
void clearMediaSession() {
  try {
    final session = _mediaSession;
    if (session == null) return;
    (session as dynamic).metadata = null;
  } catch (_) {}
}

@JS('navigator.mediaSession.setActionHandler')
external void _jsSetActionHandler(JSString action, JSFunction? handler);

void _setAction(JSObject session, String action, void Function() callback) {
  try {
    _jsSetActionHandler(action.toJS, (() { callback(); }).toJS);
  } catch (_) {}
}
