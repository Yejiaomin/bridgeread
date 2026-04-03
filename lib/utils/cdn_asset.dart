/// Helpers for loading assets.
///
/// On web: Flutter's AssetSource/Image.asset internally request `/assets/...`
/// via HTTP. In production, nginx serves these from the CDN assets directory.
/// No special UrlSource/Image.network needed — just keep files on the server.
///
/// On mobile: Assets are bundled as usual.
library;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

/// Load an image. Uses Image.asset which works on both web and mobile.
/// On web, Flutter requests `/assets/{assetPath}` via HTTP — nginx serves it.
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

/// Get an audio [Source].
/// [audioPath] does NOT start with 'assets/', e.g. 'audio/biscuit_p1_cn.mp3'
Source cdnAudioSource(String audioPath) {
  return AssetSource(audioPath);
}

/// Shorthand: get audio source from a full asset path (starts with 'assets/').
/// Strips the 'assets/' prefix automatically.
Source cdnAudioFromAssetPath(String assetPath) {
  final path = assetPath.startsWith('assets/')
      ? assetPath.substring(7) // strip 'assets/'
      : assetPath;
  return AssetSource(path);
}
