import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Zone data
// ─────────────────────────────────────────────────────────────────────────────

class _Zone {
  final double x, y, w, h;
  final String route, doneKey, sfx;
  const _Zone(this.x, this.y, this.w, this.h, this.route, this.doneKey, this.sfx);
}

// Set to true to show colored debug boxes for all tap zones
const _kDebugZones = false;

const _kZoneColors = [
  Colors.red,
  Colors.blue,
  Colors.green,
  Color(0xFFCC0000), // show - recording
  Colors.purple,     // listen - 磨耳朵
];

// 5 books: read / game / phonics / show（开口录音）/ listen（磨耳朵）
const _kZones = [
  _Zone(0.167, 0.444, 0.140, 0.247, '/reader',    'reader_done',    'audio/sfx/book-open.wav'),
  _Zone(0.356, 0.427, 0.141, 0.216, '/quiz',       'quiz_done',      'audio/sfx/pop-click.wav'),
  _Zone(0.551, 0.482, 0.133, 0.267, '/phonics',    'phonics_done',   'audio/sfx/magic-sparkle.wav'),
  _Zone(0.722, 0.534, 0.129, 0.224, '/recording',  'recording_done', 'audio/sfx/cartoon-whistle.wav'),
  _Zone(0.862, 0.492, 0.133, 0.250, '/listen',    'reader_done',    'audio/sfx/book-open.wav'),
];

// ─────────────────────────────────────────────────────────────────────────────
// StudyScreen
// ─────────────────────────────────────────────────────────────────────────────

class StudyScreen extends StatefulWidget {
  const StudyScreen({super.key});
  @override
  State<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends State<StudyScreen>
    with TickerProviderStateMixin {
  final _player = AudioPlayer();
  // Glow animations (420ms)
  late final List<AnimationController> _ctrls;
  late final List<Animation<double>>   _anims;
  // Press-down animations (150ms) — 1.0 → 0.95 → 1.0
  late final List<AnimationController> _pressCtrls;
  late final List<Animation<double>>   _pressAnims;

  @override
  void initState() {
    super.initState();
    _ctrls = List.generate(
      _kZones.length,
      (_) => AnimationController(
          vsync: this, duration: const Duration(milliseconds: 420)),
    );
    _anims = _ctrls
        .map((c) => Tween<double>(begin: 0, end: 1).animate(
            CurvedAnimation(parent: c, curve: Curves.easeOut)))
        .toList();

    _pressCtrls = List.generate(
      _kZones.length,
      (_) => AnimationController(
          vsync: this, duration: const Duration(milliseconds: 150)),
    );
    _pressAnims = _pressCtrls.map((c) =>
      TweenSequence<double>([
        TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.95), weight: 1),
        TweenSequenceItem(tween: Tween(begin: 0.95, end: 1.0), weight: 1),
      ]).animate(c),
    ).toList();
  }

  @override
  void dispose() {
    _player.dispose();
    for (final c in _ctrls) c.dispose();
    for (final c in _pressCtrls) c.dispose();
    super.dispose();
  }

  Future<void> _onZoneTap(int i) async {
    // Press-down then release
    _pressCtrls[i].forward(from: 0);
    // Glow
    _ctrls[i].forward(from: 0).then((_) => _ctrls[i].reverse());
    // Per-zone sound
    _player.stop();
    _player.play(AssetSource(_kZones[i].sfx));
    // Short delay then navigate
    await Future.delayed(const Duration(milliseconds: 160));
    if (mounted) {
      Navigator.pushNamed(context, _kZones[i].route);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (ctx, box) {
          final w = box.maxWidth;
          final h = box.maxHeight;
          return Stack(
            children: [
              // ── Background ────────────────────────────────────────────
              Image.asset('assets/home/study_bg.png',
                  fit: BoxFit.cover, width: w, height: h),

              // ── Back button ───────────────────────────────────────────
              Positioned(
                left: 8,
                top:  MediaQuery.of(ctx).padding.top + 4,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_rounded,
                      color: Colors.white, size: 26),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),

              // ── Tap zones ─────────────────────────────────────────────
              ...List.generate(_kZones.length, (i) {
                final z = _kZones[i];
                return Positioned(
                  left:   z.x * w,
                  top:    z.y * h,
                  width:  z.w * w,
                  height: z.h * h,
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_anims[i], _pressAnims[i]]),
                    builder: (_, __) {
                      final v = _anims[i].value;
                      final scale = _pressAnims[i].value * (1.0 + v * 0.07);
                      return Transform.scale(
                        scale: scale,
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: () => _onZoneTap(i),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              // Debug: show colored box; set _kDebugZones=false when coords are correct
                              color: _kDebugZones
                                  ? _kZoneColors[i].withValues(alpha: 0.35)
                                  : Colors.white.withValues(alpha: v * 0.22),
                              border: _kDebugZones
                                  ? Border.all(color: _kZoneColors[i], width: 2)
                                  : null,
                              boxShadow: !_kDebugZones && v > 0.02
                                  ? [
                                      BoxShadow(
                                        color: Colors.yellowAccent
                                            .withValues(alpha: v * 0.65),
                                        blurRadius: 28 * v,
                                        spreadRadius: 6 * v,
                                      )
                                    ]
                                  : null,
                            ),
                            child: _kDebugZones
                                ? Center(
                                    child: Text(
                                      ['READ', 'GAME', 'PHONICS', 'SHOW', 'LISTEN'][i],
                                      style: TextStyle(
                                        color: _kZoneColors[i],
                                        fontWeight: FontWeight.w900,
                                        fontSize: 12,
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                        ),
                      );
                    },
                  ),
                );
              }),

            ],
          );
        },
      ),
    );
  }

}
