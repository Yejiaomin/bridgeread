import 'dart:math' show sin, pi;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

/// Candle-blowing transition before bedtime listening.
///
/// Flow:
///   1. Fade in night_candle_in (Eggy winking at lit candle)
///   2. Speech bubble: "帮我吹灭蜡烛睡觉吧~"
///   3. Tap → blow SFX + crossfade to night_candle_out (Eggy blowing)
///   4. Hold 3s, darken, then navigate to /bedtime
class NightCandleScreen extends StatefulWidget {
  const NightCandleScreen({super.key});
  @override
  State<NightCandleScreen> createState() => _NightCandleScreenState();
}

class _NightCandleScreenState extends State<NightCandleScreen>
    with TickerProviderStateMixin {
  // Phase: 0 = fading in, 1 = showing candle_in + bubble, 2 = blowing, 3 = darkening
  int _phase = 0;

  late final AnimationController _fadeInCtrl;
  late final AnimationController _bubbleCtrl;
  late final AnimationController _swayCtrl;
  late final AnimationController _crossfadeCtrl;
  late final AnimationController _darkenCtrl;

  final _player = AudioPlayer();

  @override
  void initState() {
    super.initState();

    // Phase 0 → 1: fade in the first image
    _fadeInCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    // Bubble bounce-in (same timing as fade in)
    _bubbleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    // Gentle sway loop
    _swayCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    // Phase 1 → 2: crossfade between two images
    _crossfadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    // Phase 2 → 3: darken and exit
    _darkenCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    );

    // Start the sequence — bubble fades in together with the image
    _fadeInCtrl.forward();
    _bubbleCtrl.forward().then((_) {
      if (!mounted) return;
      setState(() => _phase = 1);
    });
  }

  @override
  void dispose() {
    _fadeInCtrl.dispose();
    _bubbleCtrl.dispose();
    _swayCtrl.dispose();
    _crossfadeCtrl.dispose();
    _darkenCtrl.dispose();
    _player.dispose();
    super.dispose();
  }

  void _onTapBlow() {
    if (_phase != 1) return;
    setState(() => _phase = 2);

    // Play blow sound
    _player.play(AssetSource('audio/sfx/blow.wav'));

    // Crossfade to candle_out
    _crossfadeCtrl.forward().then((_) {
      if (!mounted) return;
      // Hold 1.5s then start darkening
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (!mounted) return;
        setState(() => _phase = 3);
        _darkenCtrl.forward().then((_) {
          if (!mounted) return;
          Navigator.pushReplacementNamed(context, '/bedtime');
        });
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _onTapBlow,
        child: AnimatedBuilder(
          animation: Listenable.merge([
            _fadeInCtrl, _bubbleCtrl, _swayCtrl, _crossfadeCtrl, _darkenCtrl,
          ]),
          builder: (context, _) {
            final fadeIn = _fadeInCtrl.value;
            final crossfade = _crossfadeCtrl.value;
            final darken = _darkenCtrl.value;
            final bubbleScale = _bubbleCtrl.value;

            return Stack(
              fit: StackFit.expand,
              children: [
                // Image 1: candle lit (always behind)
                Opacity(
                  opacity: fadeIn * (1.0 - crossfade),
                  child: Image.asset(
                    'assets/home/layers/night_candle_in_sm.jpg',
                    fit: BoxFit.cover,
                  ),
                ),

                // Image 2: candle blown (fades in on top)
                if (_phase >= 2)
                  Opacity(
                    opacity: crossfade,
                    child: Image.asset(
                      'assets/home/layers/night_candle_out_sm.jpg',
                      fit: BoxFit.cover,
                    ),
                  ),

                // Speech bubble (phase 0 & 1, fades in with image, sways)
                if (_phase <= 1 && bubbleScale > 0)
                  Positioned(
                    left: MediaQuery.of(context).size.width * 0.61,
                    top: MediaQuery.of(context).size.height * 0.28,
                    child: Opacity(
                      opacity: bubbleScale.clamp(0.0, 1.0),
                      child: Transform.translate(
                        offset: Offset(
                          sin(_swayCtrl.value * 2 * pi) * 6, // horizontal sway
                          sin(_swayCtrl.value * 2 * pi + 1) * 3, // vertical sway
                        ),
                        child: const Text(
                          '帮我吹灭蜡烛\n睡觉吧~',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFFFFE082),
                            shadows: [
                              Shadow(color: Color(0xAA000000), blurRadius: 8),
                              Shadow(color: Color(0x66000000), blurRadius: 16),
                            ],
                            decoration: TextDecoration.none,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),

                // Darken overlay
                if (_phase == 3)
                  Opacity(
                    opacity: darken,
                    child: Container(color: Colors.black),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
