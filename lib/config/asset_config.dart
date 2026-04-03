/// Central configuration for asset loading.
/// On web, large assets (books, audio, images) are loaded from CDN via HTTP.
/// On mobile, assets are bundled locally.
library;

import 'package:flutter/foundation.dart' show kIsWeb;

class AssetConfig {
  AssetConfig._();

  /// Base URL for CDN assets. On web, points to the same origin.
  /// On mobile, this is unused (assets are bundled).
  static const String cdnBase = kIsWeb ? '' : '';

  /// Get the full URL for a CDN asset (web) or the asset path (mobile).
  /// [assetPath] should start with 'assets/' e.g. 'assets/books/01Biscuit/cover.webp'
  static String imageUrl(String assetPath) {
    if (kIsWeb) return '/$assetPath';
    return assetPath;
  }

  /// Get the audio path for web (UrlSource) or mobile (AssetSource).
  /// [audioPath] should NOT start with 'assets/', e.g. 'audio/biscuit_p1_cn.mp3'
  static String audioUrl(String audioPath) {
    if (kIsWeb) return '/assets/$audioPath';
    return audioPath;
  }
}
