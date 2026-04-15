import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../utils/cdn_asset.dart';
import '../utils/responsive_utils.dart';

const _kCardBack = 'assets/pet/cards/card.webp';

const _kCards = [
  'assets/pet/cards/bicycle_card.webp',
  'assets/pet/cards/egg_card.webp',
  'assets/pet/cards/finished_card.webp',
  'assets/pet/cards/handstand_card.webp',
  'assets/pet/cards/hatching_card.webp',
  'assets/pet/cards/keepworking_card.webp',
  'assets/pet/cards/lying_down_card.webp',
  'assets/pet/cards/lying_face_down_card.webp',
  'assets/pet/cards/single_leg_card.webp',
  'assets/pet/cards/sleepy_card.webp',
  'assets/pet/cards/study_card.webp',
  'assets/pet/cards/wearing_hat_card.webp',
];

enum _Phase { idle, spinning, flipping, center, countdown }

class CardGachaScreen extends StatefulWidget {
  const CardGachaScreen({super.key});
  @override
  State<CardGachaScreen> createState() => _CardGachaScreenState();
}

class _CardGachaScreenState extends State<CardGachaScreen>
    with TickerProviderStateMixin {
  final _rng = Random();

  _Phase _phase        = _Phase.idle;
  int    _highlighted  = 0;   // ring position during spin
  int    _selectedSlot = 0;   // winning slot
  String _revealedImg  = '';

  Timer? _spinTimer;
  Timer? _countdownTimer;
  int    _countdown = 5;

  // Grid metrics (set by LayoutBuilder)
  double _cardW = 100, _cardH = 60;

  // 3-D flip: 0 → π
  late final AnimationController _flipCtrl;
  late final Animation<double>   _flipAnim;

  // Scale up to center: 0 → 1
  late final AnimationController _scaleCtrl;
  late final Animation<double>   _scaleAnim;

  // Twinkling stars
  late final AnimationController _starCtrl;

  @override
  void initState() {
    super.initState();

    _flipCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 650));
    _flipAnim = Tween<double>(begin: 0, end: pi)
        .animate(CurvedAnimation(parent: _flipCtrl, curve: Curves.easeInOut));

    _scaleCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _scaleAnim = CurvedAnimation(parent: _scaleCtrl, curve: Curves.easeInOutCubic);

    _starCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 3))..repeat();
  }

  @override
  void dispose() {
    _spinTimer?.cancel();
    _countdownTimer?.cancel();
    _flipCtrl.dispose();
    _scaleCtrl.dispose();
    _starCtrl.dispose();
    super.dispose();
  }

  // ── Gacha flow ───────────────────────────────────────────────────────────────

  void _startGacha() {
    if (_phase != _Phase.idle) return;
    setState(() { _phase = _Phase.spinning; _highlighted = 0; });

    int intervalMs = 120;
    int elapsed    = 0;
    const totalMs     = 2000;
    const slowStartMs = 1440;

    void tick() {
      if (!mounted) return;
      setState(() => _highlighted = (_highlighted + 1) % 12);
      elapsed += intervalMs;

      if (elapsed >= totalMs) {
        _revealCard();
        return;
      }
      if (elapsed > slowStartMs) {
        final t = (elapsed - slowStartMs) / (totalMs - slowStartMs);
        intervalMs = (120 + t * 230).toInt();
      }
      _spinTimer = Timer(Duration(milliseconds: intervalMs), tick);
    }

    _spinTimer = Timer(Duration(milliseconds: intervalMs), tick);
  }

  Future<void> _revealCard() async {
    _selectedSlot = _rng.nextInt(12);
    _revealedImg  = _kCards[_rng.nextInt(_kCards.length)];

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('today_eggy', _revealedImg);
    ApiService().updateStudyRoom({'todayEggy': _revealedImg});

    if (!mounted) return;

    // 1. Flip the selected card in-place
    setState(() => _phase = _Phase.flipping);
    await _flipCtrl.forward();
    if (!mounted) return;

    // 2. Wait 1 second so player can see the revealed card
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;

    // 3. Fly to center (scale up overlay)
    setState(() => _phase = _Phase.center);
    await _scaleCtrl.forward();
    if (!mounted) return;

    // 3. Start 5-second countdown
    setState(() { _phase = _Phase.countdown; _countdown = 5; });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _countdown--);
      if (_countdown <= 0) {
        t.cancel();
        Navigator.pushReplacementNamed(context, '/listen');
      }
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A1A),
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildStars(),
          SafeArea(child: _buildMain()),
          if (_phase == _Phase.center || _phase == _Phase.countdown)
            _buildCenterOverlay(),
        ],
      ),
    );
  }

  Widget _buildMain() {
    return Column(
      children: [
        // Title
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(
            '✨  Gacha Time!  ✨',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: Colors.amber.shade300,
              letterSpacing: 2,
              shadows: [Shadow(color: Colors.amber.withValues(alpha: 0.6), blurRadius: 12)],
            ),
          ),
        ),

        // Grid + START overlay
        Expanded(
          child: LayoutBuilder(builder: (_, box) {
            _cardW = (box.maxWidth  - 32 - 3 * 8) / 4;
            _cardH = (box.maxHeight - 2  * 8)     / 3;
            return Stack(
              alignment: Alignment.center,
              children: [
                // Card grid
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: _cardW / _cardH,
                    ),
                    itemCount: 12,
                    itemBuilder: (_, i) => _buildCard(i),
                  ),
                ),

                // Glowing orb running across cards during spin
                if (_phase == _Phase.spinning)
                  _buildGlowOrb(box),

                // Circular START button — centered over grid
                if (_phase == _Phase.idle)
                  GestureDetector(
                    onTap: _startGacha,
                    child: Container(
                      width: R.s(220),
                      height: R.s(220),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.amber.withValues(alpha: 0.18),
                        border: Border.all(
                          color: Colors.amber.withValues(alpha: 0.55),
                          width: 2.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.amber.withValues(alpha: 0.35),
                            blurRadius: 40,
                            spreadRadius: 10,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('🎰', style: TextStyle(fontSize: R.s(52))),
                          const SizedBox(height: 6),
                          Text(
                            'START',
                            style: TextStyle(
                              fontSize: R.s(26),
                              fontWeight: FontWeight.w900,
                              color: Colors.amber.shade200,
                              letterSpacing: 3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          }),
        ),
      ],
    );
  }

  // ── Individual card ───────────────────────────────────────────────────────────

  Widget _buildCard(int i) {
    final isFlipping = (_phase == _Phase.flipping || _phase == _Phase.center ||
                        _phase == _Phase.countdown) && i == _selectedSlot;
    final isGone     = (_phase == _Phase.center || _phase == _Phase.countdown)
                       && i == _selectedSlot;
    final isLoser    = _phase == _Phase.flipping && i != _selectedSlot;

    if (isGone) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: _img(_kCardBack),
      );
    }

    if (isFlipping) {
      return Transform.scale(
        scale: 0.8,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.amber.withValues(alpha: 0.95),
                blurRadius: 22,
                spreadRadius: 6,
              ),
            ],
          ),
          child: AnimatedBuilder(
            animation: _flipAnim,
            builder: (_, __) {
              final angle     = _flipAnim.value;
              final showFront = angle > pi / 2;
              return ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.001)
                    ..rotateY(showFront ? angle - pi : angle),
                  child: _img(showFront ? _revealedImg : _kCardBack),
                ),
              );
            },
          ),
        ),
      );
    }

    final base = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: _img(_kCardBack),
    );

    return isLoser ? Opacity(opacity: 0.4, child: base) : base;
  }

  // ── Center overlay (fly + countdown) ─────────────────────────────────────────

  Widget _buildCenterOverlay() {
    return LayoutBuilder(builder: (context, constraints) {
      // 1.5× bigger: was 0.55/0.75
      final targetW = constraints.maxWidth  * 0.78 * 1.5;
      final targetH = constraints.maxHeight * 0.90 * 1.5;
      return AnimatedBuilder(
        animation: _scaleAnim,
        builder: (_, __) {
          final t = _scaleAnim.value;
          return Container(
            color: Colors.black.withValues(alpha: t * 0.70),
            child: Center(
              child: Transform.scale(
                scale: 0.30 + t * 0.70,
                child: SizedBox(
                  width:  targetW,
                  height: targetH,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Eggy card
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: _img(_revealedImg),
                    ),
                    // Countdown on belly (only in countdown phase)
                    if (_phase == _Phase.countdown)
                      Positioned(
                        bottom: targetH * 0.12,
                        left: 0, right: 0,
                        child: Text(
                          '$_countdown',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: R.s(64),
                            fontWeight: FontWeight.w900,
                            color: Colors.white.withValues(alpha: 0.70),
                            shadows: [
                              Shadow(
                                color: Colors.black.withValues(alpha: 0.35),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
        },
      );
    });
  }

  // ── Glowing orb ──────────────────────────────────────────────────────────────

  Widget _buildGlowOrb(BoxConstraints box) {
    final col = _highlighted % 4;
    final row = _highlighted ~/ 4;
    // Card center relative to grid area (16px horizontal padding, 8px spacing)
    final cx = 16 + col * (_cardW + 8) + _cardW / 2;
    final cy = row * (_cardH + 8) + _cardH / 2;
    final r  = _cardH * 0.15; // orb radius ~15% of card height
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 90),
      curve: Curves.easeOut,
      left: cx - r,
      top:  cy - r,
      child: IgnorePointer(
        child: Container(
          width:  r * 2,
          height: r * 2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.amber.withValues(alpha: 0.55),
            boxShadow: [
              BoxShadow(
                color: Colors.amber.withValues(alpha: 0.9),
                blurRadius: r * 1.2,
                spreadRadius: r * 0.1,
              ),
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.6),
                blurRadius: r * 0.4,
                spreadRadius: 0,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

  Widget _img(String path) => cdnImage(path,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            Container(color: const Color(0xFF1A1A3A)),
      );

  Widget _buildStars() {
    return AnimatedBuilder(
      animation: _starCtrl,
      builder: (_, __) => CustomPaint(
        painter: _StarPainter(_starCtrl.value),
      ),
    );
  }
}

// ── Star background ────────────────────────────────────────────────────────────

class _StarPainter extends CustomPainter {
  final double t;
  static final _rng   = Random(42);
  static final _stars = List.generate(60, (_) => [
    _rng.nextDouble(), _rng.nextDouble(),
    _rng.nextDouble(), 0.8 + _rng.nextDouble() * 2.5,
  ]);
  _StarPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint();
    for (final s in _stars) {
      final opacity = (sin((t + s[2]) * 2 * pi) * 0.5 + 0.5).clamp(0.1, 1.0);
      p.color = Colors.white.withValues(alpha: opacity * 0.8);
      canvas.drawCircle(Offset(s[0] * size.width, s[1] * size.height), s[3], p);
    }
  }

  @override
  bool shouldRepaint(_StarPainter old) => old.t != t;
}
