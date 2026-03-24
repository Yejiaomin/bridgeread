import 'dart:async';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/progress_service.dart';

// ---------------------------------------------------------------------------
// Data
// ---------------------------------------------------------------------------

const _kOrange = Color(0xFFFF8C42);

enum _RType { image, word }

class _Round {
  final String word;
  final _RType type;
  final String audio;
  const _Round(this.word, this.type, this.audio);
}

// All possible rounds — shuffled at game start
const _kAllRounds = [
  _Round('bed',   _RType.image, 'assets/audio/phonemes/word_bed.mp3'),
  _Round('bed',   _RType.word,  'assets/audio/phonemes/word_bed.mp3'),
  _Round('hug',   _RType.image, 'assets/audio/phonemes/word_hug.mp3'),
  _Round('hug',   _RType.word,  'assets/audio/phonemes/word_hug.mp3'),
  _Round('story', _RType.image, 'assets/audio/phonemes/word_story.mp3'),
  _Round('story', _RType.word,  'assets/audio/phonemes/word_story.mp3'),
];

const _kPositiveAudio = [
  'assets/audio/phonemes/bingo.mp3',
  'assets/audio/phonemes/great.mp3',
  'assets/audio/phonemes/nice.mp3',
  'assets/audio/phonemes/good_job.mp3',
  'assets/audio/phonemes/cool.mp3',
  'assets/audio/phonemes/excellent.mp3',
];

const _kEncouragementAudio = [
  'assets/audio/phonemes/oops.mp3',
  'assets/audio/phonemes/try_again.mp3',
  'assets/audio/phonemes/very_close.mp3',
  'assets/audio/phonemes/one_more_time.mp3',
];

const _kWordSet  = ['bed', 'hug', 'story', 'play', 'light'];
const _kEmoji    = ['🌟', '🐕'];

// Particle burst colors
const _kParticleColors = [
  Color(0xFFFBBF24),
  Color(0xFFF472B6),
  Color(0xFF34D399),
  Color(0xFF60A5FA),
  Color(0xFFFCA5A5),
];

// Per-bubble vibrant gradients (6 options, assigned by index % 6)
const _kBubbleGrads = [
  [Color(0xFFFF6B9D), Color(0xFFFF4757)],   // hot-pink → red
  [Color(0xFFFF9F43), Color(0xFFFF6B35)],   // orange → deep-orange
  [Color(0xFF26DE81), Color(0xFF20BF6B)],   // mint → green
  [Color(0xFFFFD93D), Color(0xFFFFA502)],   // yellow → amber
  [Color(0xFF54A0FF), Color(0xFF48DBFB)],   // blue → cyan
  [Color(0xFFC44EFF), Color(0xFF8854D0)],   // violet → purple
];

// Deep-space background gradient
const _kBgGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFF1a0033), Color(0xFF000d1a)],
);

// ---------------------------------------------------------------------------
// Bubble model
// ---------------------------------------------------------------------------

class _Bubble {
  final bool   isCorrect;
  final String? img;
  final String? emoji;
  final String? text;
  final double  size;          // diameter 100–140 px
  final double  bx, by;       // base position as fraction of area (0–1)
  final double  speed, px, py; // float animation params
  final int     colorIdx;      // index into _kBubbleGrads
  bool popped;

  _Bubble({
    required this.isCorrect,
    this.img, this.emoji, this.text,
    required this.size,
    required this.bx, required this.by,
    required this.speed, required this.px, required this.py,
    required this.colorIdx,
    this.popped = false,
  });

  /// Pixel offset from base at time t ∈ [0, 1) (looping).
  Offset drift(double t) {
    final a = t * 2 * pi;
    return Offset(
      sin(a * speed + px) * 28,
      cos(a * speed * 0.7 + py) * 22,
    );
  }
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> with TickerProviderStateMixin {
  final _rng    = Random();
  final _player = AudioPlayer();

  late final List<_Round> _rounds; // shuffled at init

  int  _round         = 0;
  int  _score         = 0;
  bool _scoreLoaded   = false;
  bool _done          = false;
  bool _locked   = false; // block taps during animations
  bool _firstTry = true;

  String _randomPositive()     => _kPositiveAudio[_rng.nextInt(_kPositiveAudio.length)];
  String _randomEncouragement()=> _kEncouragementAudio[_rng.nextInt(_kEncouragementAudio.length)];

  List<_Bubble> _bubbles = [];
  int? _popIdx; // index of bubble being popped
  int? _wobIdx; // index of bubble wobbling

  // Background star field (150 stars, generated once)
  late final List<_StarData> _stars;

  final _popPlayer = AudioPlayer(); // dedicated player for pop SFX

  late final AnimationController _floatCtrl;
  late final AnimationController _popCtrl;
  late final AnimationController _wobCtrl;
  late final AnimationController _celebCtrl;

  late final Animation<double> _popAnim;
  late final Animation<double> _wobAnim;
  late final Animation<double> _celebAnim;

  Timer? _timer;

  @override
  void initState() {
    super.initState();

    _floatCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 7))
      ..repeat();

    _popCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _wobCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 280));
    _celebCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400));

    _popAnim = CurvedAnimation(parent: _popCtrl, curve: Curves.easeOut);
    _wobAnim = Tween<double>(begin: -1.0, end: 1.0)
        .animate(CurvedAnimation(parent: _wobCtrl, curve: Curves.easeInOut));
    _celebAnim = CurvedAnimation(parent: _celebCtrl, curve: Curves.easeOut);

    final radii = [0.6, 1.1, 1.8]; // 3 sizes
    _stars = List.generate(150, (i) {
      final twinkle = _rng.nextDouble() < 0.35; // ~35% twinkle
      return _StarData(
        x:            _rng.nextDouble(),
        y:            _rng.nextDouble(),
        radius:       radii[_rng.nextInt(3)],
        phase:        _rng.nextDouble() * 2 * pi,
        twinkleSpeed: 1.5 + _rng.nextDouble() * 3.0,
        twinkle:      twinkle,
      );
    });

    _rounds = List.of(_kAllRounds)..shuffle(_rng);
    _loadRound();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _player.dispose();
    _popPlayer.dispose();
    _floatCtrl.dispose();
    _popCtrl.dispose();
    _wobCtrl.dispose();
    _celebCtrl.dispose();
    super.dispose();
  }

  // ── Round loading ──────────────────────────────────────────────────────────

  void _loadRound() {
    final r   = _rounds[_round];
    final pos = _scatter(5);
    final bubbles = <_Bubble>[];

    // Shuffle color indices so each bubble gets a unique vibrant color
    final colorOrder = List.generate(6, (i) => i)..shuffle(_rng);

    if (r.type == _RType.image) {
      final others = ['bed', 'hug', 'story'].where((w) => w != r.word).toList();
      final opts = <(bool, String?, String?)>[
        (true,  'assets/quiz/${r.word}.png',    null),
        (false, 'assets/quiz/${others[0]}.png', null),
        (false, 'assets/quiz/${others[1]}.png', null),
        (false, null,                           _kEmoji[0]),
        (false, null,                           _kEmoji[1]),
      ]..shuffle(_rng);

      for (int i = 0; i < 5; i++) {
        final (correct, img, emoji) = opts[i];
        final p = pos[i];
        bubbles.add(_Bubble(
          isCorrect: correct,
          img: img, emoji: emoji,
          size: 100 + _rng.nextDouble() * 40,
          bx: p.dx, by: p.dy,
          speed: 0.5 + _rng.nextDouble(),
          px: _rng.nextDouble() * 2 * pi,
          py: _rng.nextDouble() * 2 * pi,
          colorIdx: colorOrder[i],
        ));
      }
    } else {
      var words = List.of(_kWordSet)..shuffle(_rng);
      if (!words.contains(r.word)) {
        words[0] = r.word;
        words.shuffle(_rng);
      }
      for (int i = 0; i < 5; i++) {
        final p = pos[i];
        bubbles.add(_Bubble(
          isCorrect: words[i] == r.word,
          text: words[i],
          size: 100 + _rng.nextDouble() * 40,
          bx: p.dx, by: p.dy,
          speed: 0.5 + _rng.nextDouble(),
          px: _rng.nextDouble() * 2 * pi,
          py: _rng.nextDouble() * 2 * pi,
          colorIdx: colorOrder[i],
        ));
      }
    }

    setState(() {
      _bubbles  = bubbles;
      _locked   = false;
      _firstTry = true;
      _popIdx   = null;
      _wobIdx   = null;
    });
    _popCtrl.reset();
    _wobCtrl.reset();
    _timer?.cancel();

    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) _play(r.audio);
    });
  }

  /// Generate n non-overlapping fractional positions across the play area.
  List<Offset> _scatter(int n) {
    // y is capped at 0.75 so bubbles don't overlap the bottom prompt bar
    final out  = <Offset>[];
    int   tries = 0;
    while (out.length < n && tries++ < 600) {
      final x = 0.12 + _rng.nextDouble() * 0.76;
      final y = 0.08 + _rng.nextDouble() * 0.67;
      if (out.every((p) =>
          (p.dx - x).abs() > 0.26 || (p.dy - y).abs() > 0.20)) {
        out.add(Offset(x, y));
      }
    }
    while (out.length < n) {
      out.add(Offset(
          0.12 + _rng.nextDouble() * 0.76, 0.10 + _rng.nextDouble() * 0.65));
    }
    return out;
  }

  // ── Interaction ────────────────────────────────────────────────────────────

  void _onTap(int i) {
    if (_locked || _bubbles[i].popped ||
        _popIdx != null || _wobIdx != null) return;
    _bubbles[i].isCorrect ? _correct(i) : _wrong(i);
  }

  void _correct(int i) {
    setState(() {
      _score += _firstTry ? 4 : 2;
      _popIdx = i;
      _locked = true;
    });
    // Play pop SFX simultaneously with the positive voice (fails silently if file missing)
    _popPlayer.stop().then((_) =>
        _popPlayer.play(AssetSource('audio/pop.wav'))
            .catchError((_) {}));
    _play(_randomPositive());
    _popCtrl.forward(from: 0).then((_) {
      if (!mounted) return;
      setState(() {
        _bubbles[i].popped = true;
        _popIdx            = null;
      });
      _timer = Timer(const Duration(milliseconds: 600), _advance);
    });
  }

  void _wrong(int i) {
    _firstTry = false;
    setState(() => _wobIdx = i);
    _play(_randomEncouragement());
    _wobCtrl.repeat(reverse: true);
    _timer = Timer(const Duration(milliseconds: 750), () {
      if (!mounted) return;
      _wobCtrl
        ..stop()
        ..reset();
      setState(() => _wobIdx = null);
    });
  }

  void _advance() {
    if (!mounted) return;
    if (_round < _rounds.length - 1) {
      setState(() => _round++);
      _loadRound();
    } else {
      setState(() => _done = true);
      _celebCtrl.forward(from: 0);
    }
  }

  Future<void> _play(String path) async {
    await _player.stop();
    await _player.play(AssetSource(path.replaceFirst('assets/', '')));
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scoreLoaded = true;
  }

  @override
  Widget build(BuildContext context) =>
      _done ? _buildCelebration() : _buildGame();

  Widget _buildGame() {
    final r = _rounds[_round];
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: _kBgGradient),
        child: AnimatedBuilder(
          animation: _floatCtrl,
          builder: (_, child) => CustomPaint(
            painter: _StarPainter(_stars, _floatCtrl.value),
            child: child,
          ),
          child: SafeArea(
            child: Stack(
              children: [
                Column(
                  children: [
                    _buildHeader(),
                    Expanded(
                      child: LayoutBuilder(builder: (ctx, box) {
                        return AnimatedBuilder(
                          animation: Listenable.merge(
                              [_floatCtrl, _popCtrl, _wobCtrl]),
                          builder: (_, __) => Stack(
                            children: [
                              for (int i = 0; i < _bubbles.length; i++)
                                if (!_bubbles[i].popped)
                                  _positionedBubble(
                                      i, box.maxWidth, box.maxHeight),
                              if (_popIdx != null)
                                _particleBurst(
                                    _popIdx!, box.maxWidth, box.maxHeight),
                            ],
                          ),
                        );
                      }),
                    ),
                  ],
                ),
                // Prompt bar pinned to bottom
                Positioned(
                  left: 0, right: 0, bottom: 0,
                  child: _buildPrompt(r),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _positionedBubble(int i, double w, double h) {
    final b  = _bubbles[i];
    final d  = b.drift(_floatCtrl.value);
    final cx = b.bx * w + d.dx;
    final cy = b.by * h + d.dy;

    double scale   = 1.0;
    double opacity = 1.0;
    double wobbleX = 0.0;

    if (_popIdx == i) {
      final p = _popAnim.value;
      scale   = 1.0 + p * 1.8;
      opacity = (1.0 - p * 1.6).clamp(0.0, 1.0);
    }
    if (_wobIdx == i) wobbleX = _wobAnim.value * 10;

    return Positioned(
      left:   cx - b.size / 2 + wobbleX,
      top:    cy - b.size / 2,
      width:  b.size,
      height: b.size,
      child: GestureDetector(
        onTap: () => _onTap(i),
        child: Transform.scale(
          scale: scale,
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: _bubbleWidget(b),
          ),
        ),
      ),
    );
  }

  Widget _bubbleWidget(_Bubble b) {
    final grads = _kBubbleGrads[b.colorIdx % _kBubbleGrads.length];
    final s = b.size;
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [grads[0], grads[1]],
        ),
        border: Border.all(
            color: Colors.white.withValues(alpha: 0.55), width: 2.5),
        boxShadow: [
          BoxShadow(
              color: grads[1].withValues(alpha: 0.55),
              blurRadius: 24,
              spreadRadius: 3),
        ],
      ),
      child: ClipOval(
        child: Stack(
          children: [
            // Main content
            Positioned.fill(child: _bubbleContent(b)),
            // Glass highlight — white oval at top-left
            Positioned(
              top:  s * 0.07,
              left: s * 0.13,
              child: Opacity(
                opacity: 0.40,
                child: Container(
                  width:  s * 0.38,
                  height: s * 0.20,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
              ),
            ),
            // Smaller second highlight dot
            Positioned(
              top:  s * 0.12,
              left: s * 0.17,
              child: Opacity(
                opacity: 0.25,
                child: Container(
                  width:  s * 0.14,
                  height: s * 0.09,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bubbleContent(_Bubble b) {
    if (b.img != null) {
      return Image.asset(b.img!, fit: BoxFit.cover);
    }
    if (b.emoji != null) {
      return Center(
          child: Text(b.emoji!, style: const TextStyle(fontSize: 52)));
    }
    // Dark shadow pass — renders behind the gradient text for readability
    final textStyle = GoogleFonts.nunito(
      fontSize: 24,
      fontWeight: FontWeight.w900,
      color: Colors.white,
    );
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Shadow layer
          Text(
            b.text!,
            textAlign: TextAlign.center,
            style: textStyle.copyWith(
              foreground: Paint()
                ..color = Colors.black.withValues(alpha: 0.45)
                ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
            ),
          ),
          // Gradient text layer
          ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) => const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFFFE066), // bright yellow
                Color(0xFFFF9F43), // orange
                Color(0xFFFF6B9D), // hot pink
                Color(0xFF66D4FF), // sky blue
              ],
            ).createShader(bounds),
            child: Text(
              b.text!,
              textAlign: TextAlign.center,
              style: textStyle,
            ),
          ),
        ],
      ),
    );
  }

  Widget _particleBurst(int i, double w, double h) {
    final b  = _bubbles[i];
    final d  = b.drift(_floatCtrl.value);
    final cx = b.bx * w + d.dx;
    final cy = b.by * h + d.dy;
    final p  = _popAnim.value;

    // ── Shockwave ring ────────────────────────────────────────────────────
    final ringSize    = b.size * (1.0 + p * 4.0);
    final ringOpacity = (0.9 - p * 1.8).clamp(0.0, 1.0);

    // ── 24 colored dot particles ──────────────────────────────────────────
    final dotParticles = List.generate(24, (j) {
      final angle      = (j / 24) * 2 * pi;
      final distScale  = 1.0 + (j % 4) * 0.28;  // staggered distances
      final size       = 8.0 + (j % 5) * 4.0;   // 8, 12, 16, 20, 8 …
      final dist       = p * 185 * distScale;
      final fadeOffset = 0.3 + (j % 3) * 0.15;  // staggered fade start
      final op = ((1.0 - (p - fadeOffset).clamp(0.0, 1.0) /
              (1.0 - fadeOffset).clamp(0.01, 1.0)))
          .clamp(0.0, 1.0);
      return Positioned(
        left: cx + cos(angle) * dist - size / 2,
        top:  cy + sin(angle) * dist - size / 2,
        child: Opacity(
          opacity: op,
          child: Container(
            width: size, height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _kParticleColors[j % _kParticleColors.length],
            ),
          ),
        ),
      );
    });

    // ── 6 emoji sparks ────────────────────────────────────────────────────
    const emojis = ['💥', '✨', '🌟', '⭐', '✨', '💫'];
    final emojiParticles = List.generate(6, (j) {
      final angle = (j / 6) * 2 * pi + pi / 12;
      final dist  = p * 145;
      return Positioned(
        left: cx + cos(angle) * dist - 18,
        top:  cy + sin(angle) * dist - 18,
        child: Opacity(
          opacity: (1.0 - p * 1.4).clamp(0.0, 1.0),
          child: Text(emojis[j], style: const TextStyle(fontSize: 32)),
        ),
      );
    });

    return IgnorePointer(
      child: Stack(
        children: [
          // Shockwave ring
          Positioned(
            left: cx - ringSize / 2,
            top:  cy - ringSize / 2,
            child: Opacity(
              opacity: ringOpacity,
              child: Container(
                width: ringSize, height: ringSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.85),
                    width: 3.5,
                  ),
                ),
              ),
            ),
          ),
          // Second inner ring (slightly delayed feel)
          Positioned(
            left: cx - ringSize * 0.6 / 2,
            top:  cy - ringSize * 0.6 / 2,
            child: Opacity(
              opacity: (ringOpacity * 0.6).clamp(0.0, 1.0),
              child: Container(
                width: ringSize * 0.6, height: ringSize * 0.6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.yellowAccent.withValues(alpha: 0.7),
                    width: 2.5,
                  ),
                ),
              ),
            ),
          ),
          ...dotParticles,
          ...emojiParticles,
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          // Back button
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded,
                color: Colors.white70, size: 22),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          // Progress dots
          Row(
            children: List.generate(6, (i) {
              final Color c;
              if (i < _round)       c = const Color(0xFF34D399);
              else if (i == _round) c = Colors.white;
              else                  c = Colors.white.withValues(alpha: 0.28);
              return Container(
                margin: const EdgeInsets.only(right: 7),
                width: 11, height: 11,
                decoration:
                    BoxDecoration(shape: BoxShape.circle, color: c),
              );
            }),
          ),
          const Spacer(),
          // Score chip
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                const Text('⭐', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 5),
                Text('$_score',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrompt(_Round r) {
    final text = r.type == _RType.image
        ? 'Find the  "${r.word}"'
        : 'Pop the bubble that says  "${r.word}"';
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.40),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Speaker button — tapping replays the audio
          GestureDetector(
            onTap: () => _play(r.audio),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.volume_up_rounded,
                  color: Colors.white, size: 28),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Celebration ────────────────────────────────────────────────────────────

  Widget _buildCelebration() {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: _kBgGradient),
        child: SafeArea(
          child: AnimatedBuilder(
            animation: _celebAnim,
            builder: (_, __) {
              final p = _celebAnim.value;
              return Stack(
                children: [
                  _starField(p),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Transform.scale(
                          scale: Curves.elasticOut
                              .transform(p.clamp(0.0, 1.0)),
                          child: const Text('🎉',
                              style: TextStyle(fontSize: 80)),
                        ),
                        const SizedBox(height: 16),
                        Opacity(
                          opacity: p.clamp(0.0, 1.0),
                          child: const Text('Amazing!',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 52,
                                  fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(height: 6),
                        Opacity(
                          opacity: p.clamp(0.0, 1.0),
                          child: const Text('太棒了！',
                              style: TextStyle(
                                  color: Colors.white60,
                                  fontSize: 22)),
                        ),
                        const SizedBox(height: 32),
                        Opacity(
                          opacity: p.clamp(0.0, 1.0),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 36, vertical: 18),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(32),
                              border: Border.all(
                                  color: Colors.white
                                      .withValues(alpha: 0.25)),
                            ),
                            child: Column(
                              children: [
                                const Text('⭐⭐⭐',
                                    style: TextStyle(fontSize: 40)),
                                const SizedBox(height: 10),
                                Text('$_score points!',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 32,
                                        fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 44),
                        Opacity(
                          opacity: p.clamp(0.0, 1.0),
                          child: ElevatedButton(
                            onPressed: () async {
                              await ProgressService.markModuleComplete('quiz', 20);
                              if (mounted) Navigator.pushReplacementNamed(context, '/phonics');
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _kOrange,
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
                            child: const Text('拼读练习  🔤 →'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  // _starField used only in celebration — background stars are _StarPainter
  Widget _starField(double p) {
    return IgnorePointer(
      child: LayoutBuilder(builder: (ctx, box) {
        final cx = box.maxWidth / 2;
        final cy = box.maxHeight / 2;
        return Stack(
          children: List.generate(14, (i) {
            final angle = (i / 14) * 2 * pi;
            final dist  = p * (box.maxWidth * 0.44);
            return Positioned(
              left: cx + cos(angle) * dist - 18,
              top:  cy + sin(angle) * dist - 18,
              child: Opacity(
                opacity: (1.0 - p * 0.65).clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: 0.3 + p * 0.7,
                  child:
                      const Text('⭐', style: TextStyle(fontSize: 34)),
                ),
              ),
            );
          }),
        );
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// Star data model
// ---------------------------------------------------------------------------

class _StarData {
  final double x, y, radius, phase, twinkleSpeed;
  final bool   twinkle;
  const _StarData({
    required this.x, required this.y, required this.radius,
    required this.phase, required this.twinkleSpeed, required this.twinkle,
  });
}

// ---------------------------------------------------------------------------
// Star-field background painter — 150 stars, ~35% twinkle
// ---------------------------------------------------------------------------

class _StarPainter extends CustomPainter {
  final List<_StarData> stars;
  final double animValue; // from _floatCtrl 0→1

  const _StarPainter(this.stars, this.animValue);

  @override
  void paint(Canvas canvas, Size size) {
    final t = animValue * 2 * pi;
    for (final s in stars) {
      final double opacity;
      if (s.twinkle) {
        // oscillate between 0.25 and 1.0
        opacity = 0.25 + 0.75 * ((sin(t * s.twinkleSpeed + s.phase) + 1) / 2);
      } else {
        opacity = 0.82;
      }
      final paint = Paint()
        ..color = Colors.white.withValues(alpha: opacity.clamp(0.0, 1.0));
      canvas.drawCircle(
        Offset(s.x * size.width, s.y * size.height),
        s.radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_StarPainter old) => old.animValue != animValue;
}
