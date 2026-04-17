import 'dart:async';
import 'dart:js_interop';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import '../services/lesson_service.dart';

@JS('fetch')
external JSPromise<JSAny> _rawFetch(JSString url);

/// Prefetch audio files in the background so the Service Worker caches them.
/// On web, triggers fetch() requests that the SW intercepts and caches.
/// On mobile, this is a no-op (assets are bundled).
class AudioPreloader {
  static bool _preloadingStory = false;
  static bool _preloadingPhonics = false;

  /// Preload audio for today's story (call from home screen).
  static Future<void> preloadStoryAudio() async {
    if (!kIsWeb || _preloadingStory) return;
    _preloadingStory = true;
    try {
      final service = LessonService();
      final lessonId = await service.restoreCurrentLessonId();
      final lesson = await service.loadLesson(lessonId);
      final urls = <String>[];
      for (final page in lesson.pages) {
        if (page.audioCN != null) urls.add('assets/assets/audio/${page.audioCN}.mp3');
        if (page.audioEN != null) urls.add('assets/assets/audio/${page.audioEN}.mp3');
      }
      await _prefetchUrls(urls, 'Story');
    } catch (e) {
      debugPrint('[Preloader] story error: $e');
    }
  }

  /// Preload audio for phonics (call from quiz screen).
  static Future<void> preloadPhonicsAudio() async {
    if (!kIsWeb || _preloadingPhonics) return;
    _preloadingPhonics = true;
    try {
      final service = LessonService();
      final lessonId = await service.restoreCurrentLessonId();
      final lesson = await service.loadLesson(lessonId);
      final urls = <String>[];
      for (final pw in lesson.phonicsWords) {
        urls.add('assets/assets/audio/phonics_sounds/word_${pw.word}.mp3');
        for (final p in pw.phonemes) {
          urls.add('assets/assets/audio/phonics_sounds/$p.mp3');
        }
      }
      // Feedback audio
      for (final f in ['you_got_it', 'one_more_time', 'amazing', 'bingo']) {
        urls.add('assets/assets/audio/phonemes/$f.mp3');
      }
      await _prefetchUrls(urls, 'Phonics');
    } catch (e) {
      debugPrint('[Preloader] phonics error: $e');
    }
  }

  static Future<void> _prefetchUrls(List<String> urls, String label) async {
    if (urls.isEmpty) return;
    debugPrint('[Preloader] $label: prefetching ${urls.length} files');
    for (int i = 0; i < urls.length; i += 3) {
      final batch = urls.skip(i).take(3);
      await Future.wait(
        batch.map((url) => _fetchOne(url)),
        eagerError: false,
      );
    }
    debugPrint('[Preloader] $label: done');
  }

  static Future<void> _fetchOne(String url) async {
    try {
      _rawFetch(url.toJS).toDart.timeout(
        const Duration(seconds: 10),
        onTimeout: () => null as dynamic,
      );
    } catch (_) {}
  }
}
