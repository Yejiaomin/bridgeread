import 'package:flutter/material.dart';

class HighlightOverlay extends StatefulWidget {
  final List<String> keywords;
  final List<String> keywordsCN;
  final String? activeKeyword;
  final void Function(String keyword) onKeywordTap;

  const HighlightOverlay({
    super.key,
    required this.keywords,
    this.keywordsCN = const [],
    required this.activeKeyword,
    required this.onKeywordTap,
  });

  @override
  State<HighlightOverlay> createState() => _HighlightOverlayState();
}

class _HighlightOverlayState extends State<HighlightOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _borderWidth;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _borderWidth = Tween<double>(begin: 1.5, end: 3.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      color: Colors.black.withOpacity(0.15),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(widget.keywords.length, (i) {
          final kw = widget.keywords[i];
          final cn = i < widget.keywordsCN.length ? widget.keywordsCN[i] : '';
          final isActive = kw == widget.activeKeyword;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: GestureDetector(
              onTap: () => widget.onKeywordTap(kw),
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (context, _) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Keyword chip
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: isActive
                              ? const Color(0xFFFFD93D)
                              : const Color(0xFFFFF176),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isActive
                                ? const Color(0xFFE65100)
                                : const Color(0xFFFF8C42),
                            width: isActive ? _borderWidth.value : 2.0,
                          ),
                          boxShadow: isActive
                              ? [
                                  BoxShadow(
                                    color: Colors.orange.withOpacity(0.4),
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                  )
                                ]
                              : [],
                        ),
                        child: Text(
                          kw,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isActive
                                ? const Color(0xFFBF360C)
                                : const Color(0xFF5D4037),
                          ),
                        ),
                      ),
                      // Chinese meaning below chip
                      if (cn.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            cn,
                            style: TextStyle(
                              fontSize: 12,
                              color: isActive
                                  ? const Color(0xFFE65100)
                                  : Colors.white.withOpacity(0.9),
                              fontWeight: FontWeight.w600,
                              shadows: const [
                                Shadow(
                                  color: Colors.black54,
                                  blurRadius: 4,
                                  offset: Offset(0, 1),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          );
        }),
      ),
    );
  }
}
