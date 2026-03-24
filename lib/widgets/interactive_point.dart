import 'package:flutter/material.dart';
import '../models/book_page.dart';

class InteractivePoint extends StatefulWidget {
  final InteractiveHotspot hotspot;
  final Size parentSize;
  final VoidCallback onTap;

  const InteractivePoint({
    super.key,
    required this.hotspot,
    required this.parentSize,
    required this.onTap,
  });

  @override
  State<InteractivePoint> createState() => _InteractivePointState();
}

class _InteractivePointState extends State<InteractivePoint>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  late AnimationController _sparkleController;
  late Animation<double> _sparkleOpacity;
  late Animation<double> _sparkleScale;

  @override
  void initState() {
    super.initState();
    // Scale + opacity pulse to draw kids' attention
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _scaleAnimation = Tween<double>(begin: 0.75, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _opacityAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Sparkle overlay shown on tap
    _sparkleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _sparkleOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _sparkleController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
      ),
    );
    _sparkleScale = Tween<double>(begin: 0.5, end: 1.8).animate(
      CurvedAnimation(parent: _sparkleController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _sparkleController.dispose();
    super.dispose();
  }

  void _handleTap() {
    _sparkleController.forward(from: 0).then((_) {
      _sparkleController.reverse();
    });
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final hs = widget.hotspot;
    final left = hs.x * widget.parentSize.width;
    final top = hs.y * widget.parentSize.height;
    final width = hs.width * widget.parentSize.width;
    final height = hs.height * widget.parentSize.height;

    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: GestureDetector(
        onTap: _handleTap,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Invisible tap area
            Container(color: Colors.transparent),
            // Pulsing ring (outer glow)
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, _) => Opacity(
                opacity: _opacityAnimation.value * 0.4,
                child: Transform.scale(
                  scale: _scaleAnimation.value * 1.5,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.25),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
            // Pulsing dot (inner)
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, _) => Opacity(
                opacity: _opacityAnimation.value,
                child: Transform.scale(
                  scale: _scaleAnimation.value,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFAA00).withOpacity(0.85),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white,
                        width: 2.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.orange.withOpacity(0.6),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.touch_app,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
            // Sparkle overlay
            AnimatedBuilder(
              animation: _sparkleController,
              builder: (context, _) => Opacity(
                opacity: _sparkleOpacity.value,
                child: Transform.scale(
                  scale: _sparkleScale.value,
                  child: const Text('✨', style: TextStyle(fontSize: 28)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
