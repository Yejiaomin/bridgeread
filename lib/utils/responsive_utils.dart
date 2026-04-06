import 'package:flutter/widgets.dart';

/// Responsive scaling utility.
///
/// Reference design: 1024 × 768 (typical tablet landscape).
/// On tablets the scale factor ≈ 1.0; on phones ≈ 0.5–0.7.
///
/// Usage:
///   R.init(context);          // call once per screen build
///   Container(width: R.s(150)) // scales 150 px proportionally
class R {
  static double _scale = 1.0;

  /// Must be called inside a build method (needs MediaQuery).
  static void init(BuildContext context) {
    final size = MediaQuery.of(context).size;
    _scale = (size.width / 1024).clamp(0.4, 1.5);
  }

  /// Scale a pixel value for the current screen.
  static double s(double px) => px * _scale;

  /// Current scale factor (useful for conditional logic).
  static double get scale => _scale;
}
