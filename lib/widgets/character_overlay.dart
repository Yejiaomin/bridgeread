import 'package:flutter/material.dart';
import '../models/book_page.dart';

class CharacterOverlay extends StatelessWidget {
  final CharacterPosition position;
  final Size parentSize;
  final bool visible;

  const CharacterOverlay({
    super.key,
    required this.position,
    required this.parentSize,
    this.visible = true,
  });

  Color get _actionColor {
    switch (position.action) {
      case 'excited':
        return Colors.orange;
      case 'run':
        return Colors.green;
      case 'jump':
        return Colors.blue;
      case 'yawn':
        return Colors.purple;
      case 'sit':
        return Colors.teal;
      default:
        return Colors.orange;
    }
  }

  double get _actionSize {
    switch (position.action) {
      case 'excited':
        return 64;
      case 'run':
        return 56;
      case 'jump':
        return 60;
      default:
        return 52;
    }
  }

  @override
  Widget build(BuildContext context) {
    final left = position.x * parentSize.width - _actionSize / 2;
    final top = position.y * parentSize.height - _actionSize / 2;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      left: left,
      top: top,
      child: AnimatedOpacity(
        opacity: visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 500),
        child: Container(
          width: _actionSize,
          height: _actionSize,
          decoration: BoxDecoration(
            color: _actionColor.withValues(alpha: 0.85),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: _actionColor.withOpacity(0.4),
                blurRadius: 8,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Center(
            child: Text(
              '🐕',
              style: TextStyle(fontSize: _actionSize * 0.55),
            ),
          ),
        ),
      ),
    );
  }
}
