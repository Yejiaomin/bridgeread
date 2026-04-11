import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import '../services/progress_service.dart';
import '../utils/cdn_asset.dart';
import '../utils/responsive_utils.dart';

// ── Praise options ────────────────────────────────────────────────────────────

const _kPraiseOptions = [
  ('Brilliant!',   'audio/phonemes/brilliant.mp3'),
  ('Stunning!',    'audio/phonemes/stunning.mp3'),
  ('Perfect!',     'audio/phonemes/perfect.mp3'),
  ('Awesome!',     'audio/phonemes/awesome.mp3'),
  ('Phenomenal!',  'audio/phonemes/phenomenal.mp3'),
  ('Incredible!',  'audio/phonemes/incredible.mp3'),
  ('Masterpiece!', 'audio/phonemes/masterpiece.mp3'),
  ('Exceptional!', 'audio/phonemes/exceptional.mp3'),
  ('Amazing!',     'audio/phonemes/amazing.mp3'),
  ('Excellent!',   'audio/phonemes/excellent.mp3'),
];
const _kStarCount = 9;

const _kBgGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFF1a0033), Color(0xFF000d1a)],
);

// ── Screen ────────────────────────────────────────────────────────────────────

/// Full-screen Eggy celebration with flying stars.
///
/// Parameters:
///   [nextRoute]    — named route pushed (via pushReplacementNamed) when Next is tapped.
///   [nextLabel]    — text on the Next button.
///   [moduleKey]    — key passed to ProgressService.markModuleComplete.
///   [modulePoints] — points passed to ProgressService.markModuleComplete.
class EggyCelebrationScreen extends StatefulWidget {
  final String nextRoute;
  final String nextLabel;
  final String moduleKey;
  final int    modulePoints;
  final String? customTitle;
  final VoidCallback? onComplete;

  const EggyCelebrationScreen({
    super.key,
    required this.nextRoute,
    required this.nextLabel,
    required this.moduleKey,
    required this.modulePoints,
    this.customTitle,
    this.onComplete,
  });

  @override
  State<EggyCelebrationScreen> createState() => _EggyCelebrationScreenState();
}

class _EggyCelebrationScreenState extends State<EggyCelebrationScreen>
    with TickerProviderStateMixin {
  final _rng    = Random();
  final _player = AudioPlayer();

  late final AnimationController _eggyBounceCtrl;
  late final AnimationController _starFlyCtrl;
  late final AnimationController _eggyJiggleCtrl;
  late final AnimationController _praisePopCtrl;

  String         _praiseWord      = '';
  bool           _showNextBtn     = false;
  bool           _navigating      = false;
  List<Offset>   _starStartFracs  = [];

  @override
  void initState() {
    super.initState();

    _eggyBounceCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);

    _starFlyCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2000));

    _eggyJiggleCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));

    _praisePopCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));

    _startCelebration();
  }

  void _startCelebration() {
    // Pick random praise
    final idx = _rng.nextInt(_kPraiseOptions.length);
    final (word, audio) = _kPraiseOptions[idx];

    // Generate star edge-start positions as fractions
    final fracs = List.generate(_kStarCount, (i) {
      final side = _rng.nextInt(4);
      return switch (side) {
        0 => Offset(0.1 + _rng.nextDouble() * 0.8, -0.06),  // top
        1 => Offset(0.1 + _rng.nextDouble() * 0.8,  1.06),  // bottom
        2 => Offset(-0.06, 0.1 + _rng.nextDouble() * 0.8),  // left
        _ => Offset( 1.06, 0.1 + _rng.nextDouble() * 0.8),  // right
      };
    });

    setState(() {
      _praiseWord     = word;
      _starStartFracs = fracs;
    });

    _starFlyCtrl.forward(from: 0);
    _praisePopCtrl.forward(from: 0);

    // Play praise audio after a short pause
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _player.play(cdnAudioSource(audio));
    });

    // Eggy jiggles when each star lands
    for (int i = 0; i < _kStarCount; i++) {
      final landMs = ((i * 0.09 + 0.55) * 2000).round();
      Future.delayed(Duration(milliseconds: landMs), () {
        if (mounted) _eggyJiggleCtrl.forward(from: 0);
      });
    }

    // Show Next button after 2.5 s
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _showNextBtn = true);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    _eggyBounceCtrl.dispose();
    _starFlyCtrl.dispose();
    _eggyJiggleCtrl.dispose();
    _praisePopCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: _kBgGradient),
        child: SafeArea(
          child: LayoutBuilder(builder: (ctx, box) {
            final sw = box.maxWidth;
            final sh = box.maxHeight;
            final eggyTargetX = sw / 2;
            final eggyTargetY = sh * 0.52;

            return AnimatedBuilder(
              animation: Listenable.merge([
                _starFlyCtrl,
                _eggyBounceCtrl,
                _eggyJiggleCtrl,
                _praisePopCtrl,
              ]),
              builder: (_, __) {
                final flyP    = _starFlyCtrl.value;
                final bounceP = _eggyBounceCtrl.value;
                final jiggleP = _eggyJiggleCtrl.value;
                final popP    = _praisePopCtrl.value;

                final eggyScale = (1.0 + bounceP * 0.08) *
                    (1.0 + sin(jiggleP * pi) * 0.06);

                return Stack(
                  children: [
                    // ── Flying stars ──────────────────────────────────────
                    IgnorePointer(
                      child: Stack(
                        children: List.generate(_kStarCount, (i) {
                          final iStart = i * 0.09;
                          const iLen   = 0.55;
                          final raw = ((flyP - iStart) / iLen).clamp(0.0, 1.0);
                          final t   = Curves.easeInCubic.transform(raw);

                          if (raw <= 0.0) return const SizedBox.shrink();

                          final frac = _starStartFracs[i];
                          final sx   = frac.dx * sw;
                          final sy   = frac.dy * sh;
                          final cx   = sx + (eggyTargetX - sx) * t;
                          final cy   = sy + (eggyTargetY - sy) * t;

                          final landed  = raw >= 1.0;
                          final starOp  = landed ? 0.0 : (1.0 - raw * 0.4).clamp(0.0, 1.0);
                          final flashOp = landed
                              ? 0.0
                              : (t > 0.88
                                  ? ((t - 0.88) / 0.12).clamp(0.0, 1.0)
                                  : 0.0);

                          return Stack(
                            children: [
                              Positioned(
                                left: cx - 14,
                                top:  cy - 14,
                                child: Opacity(
                                  opacity: starOp,
                                  child: Transform.scale(
                                    scale: 0.5 + t * 0.8,
                                    child: const Text('⭐',
                                        style: TextStyle(fontSize: 28)),
                                  ),
                                ),
                              ),
                              if (flashOp > 0)
                                Positioned(
                                  left: eggyTargetX - 30,
                                  top:  eggyTargetY - 30,
                                  child: Opacity(
                                    opacity: flashOp * 0.75,
                                    child: Container(
                                      width: 60, height: 60,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: const Color(0xFFFBBF24)
                                            .withValues(alpha: 0.6),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        }),
                      ),
                    ),

                    // ── Central column ────────────────────────────────────
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Praise text — pop-in
                          Transform.scale(
                            scale: Curves.elasticOut
                                .transform(popP.clamp(0.0, 1.0)),
                            child: ShaderMask(
                              blendMode: BlendMode.srcIn,
                              shaderCallback: (bounds) =>
                                  const LinearGradient(
                                colors: [
                                  Color(0xFFFFE066),
                                  Color(0xFFFF9F43),
                                  Color(0xFFFF6B9D),
                                  Color(0xFF66D4FF),
                                ],
                              ).createShader(bounds),
                              child: Text(
                                _praiseWord,
                                style: TextStyle(
                                  fontSize: R.s(52),
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  shadows: const [
                                    Shadow(
                                        color: Colors.black54,
                                        blurRadius: 8,
                                        offset: Offset(2, 2)),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 24),

                          // Eggy — scaled for screen size
                          Transform.scale(
                            scale: eggyScale,
                            child: cdnImage('assets/pet/eggy_transparent_bg.webp',
                              height: R.s(400),
                              fit: BoxFit.contain,
                            ),
                          ),

                          const SizedBox(height: 32),

                          // Next button — appears after 2.5 s
                          AnimatedOpacity(
                            opacity: _showNextBtn ? 1.0 : 0.0,
                            duration: const Duration(milliseconds: 400),
                            child: AnimatedScale(
                              scale: _showNextBtn ? 1.0 : 0.5,
                              duration: const Duration(milliseconds: 400),
                              curve: Curves.elasticOut,
                              child: ElevatedButton(
                                onPressed: _showNextBtn
                                    ? () async {
                                        if (_navigating) return;
                                        _navigating = true;
                                        await ProgressService
                                            .markModuleComplete(
                                                widget.moduleKey,
                                                widget.modulePoints);
                                        if (widget.onComplete != null) {
                                          widget.onComplete!();
                                        } else if (mounted) {
                                          Navigator.pushReplacementNamed(
                                              context, widget.nextRoute);
                                        }
                                      }
                                    : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFF8C42),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 40, vertical: 16),
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(32)),
                                  textStyle: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold),
                                ),
                                child: Text(widget.nextLabel),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          }),
        ),
      ),
    );
  }
}
