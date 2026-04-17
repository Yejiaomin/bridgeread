import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'web_audio_player.dart';
import 'cdn_asset.dart';

/// Cross-platform audio player that uses the persistent HTML5 Audio element
/// on web (for iOS Safari autoplay compat) and audioplayers on mobile.
class SafeAudioPlayer {
  final WebAudioPlayer? _web = kIsWeb ? WebAudioPlayer() : null;
  final AudioPlayer? _native = kIsWeb ? null : AudioPlayer();

  /// Play from a full asset path like 'assets/audio/phonemes/bingo.mp3'
  Future<void> playAssetPath(String assetPath) async {
    final path = assetPath.startsWith('assets/')
        ? assetPath.substring(7)
        : assetPath;
    if (_web != null) {
      _web!.play(path);
    } else {
      await _native!.play(cdnAudioFromAssetPath(assetPath));
    }
  }

  /// Play from an audio-relative path like 'audio/pop.wav'
  Future<void> playAudio(String audioPath) async {
    if (_web != null) {
      _web!.play(audioPath);
    } else {
      await _native!.play(cdnAudioSource(audioPath));
    }
  }

  /// Play from a Source (for compatibility with existing code)
  Future<void> playSource(Source source) async {
    if (_web != null && source is AssetSource) {
      // AssetSource stores path relative to assets/ folder
      _web!.play(source.path);
    } else if (_native != null) {
      await _native!.play(source);
    }
  }

  Future<void> pause() async {
    _web?.pause();
    try { await _native?.pause(); } catch (_) {}
  }

  Future<void> resume() async {
    _web?.resume();
    try { await _native?.resume(); } catch (_) {}
  }

  Future<void> stop() async {
    _web?.stop();
    try { await _native?.stop(); } catch (_) {}
  }

  Stream<void> get onPlayerComplete {
    if (_web != null) return _web!.onComplete;
    return _native!.onPlayerComplete;
  }

  Stream<Duration> get onPositionChanged {
    if (_web != null) return _web!.onPositionChanged;
    return _native!.onPositionChanged;
  }

  void dispose() {
    _web?.dispose();
    _native?.dispose();
  }
}
