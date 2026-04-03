/// Helpers for loading assets from CDN (web) or local bundle (mobile).
library;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Load an image from CDN on web, or from bundled assets on mobile.
/// [assetPath] starts with 'assets/', e.g. 'assets/books/01Biscuit/cover.webp'
Widget cdnImage(
  String assetPath, {
  Key? key,
  BoxFit fit = BoxFit.contain,
  double? width,
  double? height,
  Alignment alignment = Alignment.center,
  Widget Function(BuildContext, Object, StackTrace?)? errorBuilder,
}) {
  if (kIsWeb) {
    return Image.network(
      '/$assetPath',
      key: key,
      fit: fit,
      width: width,
      height: height,
      alignment: alignment,
      errorBuilder: errorBuilder,
    );
  }
  return Image.asset(
    assetPath,
    key: key,
    fit: fit,
    width: width,
    height: height,
    alignment: alignment,
    errorBuilder: errorBuilder,
  );
}

/// Get an audio [Source] from CDN on web, or from bundled assets on mobile.
/// [audioPath] does NOT start with 'assets/', e.g. 'audio/biscuit_p1_cn.mp3'
Source cdnAudioSource(String audioPath) {
  if (kIsWeb) return UrlSource('/assets/$audioPath');
  return AssetSource(audioPath);
}

/// Shorthand: get audio source from a full asset path (starts with 'assets/').
/// Strips the 'assets/' prefix automatically.
Source cdnAudioFromAssetPath(String assetPath) {
  final path = assetPath.startsWith('assets/')
      ? assetPath.substring(7) // strip 'assets/'
      : assetPath;
  return cdnAudioSource(path);
}
