import 'package:flutter/material.dart';
import '../models/book_page.dart';

class HighlighterOverlay extends StatefulWidget {
  final List<KeywordHighlight> highlights;
  final Set<int> triggeredIndices;
  final double imageAspectRatio;

  const HighlighterOverlay({
    super.key,
    required this.highlights,
    required this.triggeredIndices,
    required this.imageAspectRatio,
  });

  @override
  State<HighlighterOverlay> createState() => _HighlighterOverlayState();
}

class _HighlighterOverlayState extends State<HighlighterOverlay>
    with TickerProviderStateMixin {
  // Each highlight has two controllers: sweep (width) and fade (opacity)
  final List<AnimationController> _sweepControllers = [];
  final List<AnimationController> _fadeControllers = [];
  final List<Animation<double>> _sweepAnims = [];
  final List<Animation<double>> _fadeAnims = [];

  @override
  void initState() {
    super.initState();
    _buildAnimations();
    for (final i in widget.triggeredIndices) {
      if (i < _sweepControllers.length) _triggerAt(i);
    }
  }

  @override
  void didUpdateWidget(HighlighterOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.highlights != oldWidget.highlights) {
      _disposeControllers();
      _buildAnimations();
    }

    for (final i in widget.triggeredIndices) {
      if (!oldWidget.triggeredIndices.contains(i) &&
          i < _sweepControllers.length) {
        _triggerAt(i);
      }
    }

    for (final i in oldWidget.triggeredIndices) {
      if (!widget.triggeredIndices.contains(i) &&
          i < _sweepControllers.length) {
        _sweepControllers[i].reset();
        _fadeControllers[i].reset();
      }
    }
  }

  void _buildAnimations() {
    for (int i = 0; i < widget.highlights.length; i++) {
      final sweep = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 600),
      );
      final fade = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 300),
      );
      _sweepControllers.add(sweep);
      _fadeControllers.add(fade);
      _sweepAnims.add(
        CurvedAnimation(parent: sweep, curve: Curves.easeOut),
      );
      _fadeAnims.add(
        Tween<double>(begin: 1.0, end: 0.0).animate(
          CurvedAnimation(parent: fade, curve: Curves.easeIn),
        ),
      );
    }
  }

  Future<void> _triggerAt(int i) async {
    if (!mounted) return;
    _sweepControllers[i].reset();
    _fadeControllers[i].reset();
    // Sweep in
    await _sweepControllers[i].forward();
    // Stay visible for 1.5 seconds
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    // Fade out
    await _fadeControllers[i].forward();
  }

  void _disposeControllers() {
    for (final c in _sweepControllers) c.dispose();
    for (final c in _fadeControllers) c.dispose();
    _sweepControllers.clear();
    _fadeControllers.clear();
    _sweepAnims.clear();
    _fadeAnims.clear();
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  Color _parseColor(String hex) {
    final cleaned = hex.replaceFirst('#', '');
    final value = int.tryParse('FF$cleaned', radix: 16) ?? 0xFFFFD93D;
    return Color(value);
  }

  Rect _containRect(double widgetW, double widgetH, double imageAspectRatio) {
    final widgetAspect = widgetW / widgetH;
    double imgW, imgH;
    if (imageAspectRatio > widgetAspect) {
      imgW = widgetW;
      imgH = widgetW / imageAspectRatio;
    } else {
      imgH = widgetH;
      imgW = widgetH * imageAspectRatio;
    }
    return Rect.fromLTWH(
      (widgetW - imgW) / 2,
      (widgetH - imgH) / 2,
      imgW,
      imgH,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.highlights.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final imgRect =
            _containRect(constraints.maxWidth, constraints.maxHeight,
                widget.imageAspectRatio);

        return Stack(
          children: [
            for (int i = 0; i < widget.highlights.length; i++)
              AnimatedBuilder(
                animation: Listenable.merge(
                    [_sweepControllers[i], _fadeControllers[i]]),
                builder: (context, _) {
                  final hl = widget.highlights[i];
                  final left = imgRect.left + hl.x * imgRect.width;
                  final top = imgRect.top + hl.y * imgRect.height;
                  final fullWidth = hl.width * imgRect.width;
                  final height = hl.height * imgRect.height;

                  return Positioned(
                    left: left,
                    top: top,
                    child: Opacity(
                      opacity: _fadeAnims[i].value,
                      child: ClipRect(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          widthFactor: _sweepAnims[i].value,
                          child: Container(
                            width: fullWidth,
                            height: height,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFD93D).withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }
}
