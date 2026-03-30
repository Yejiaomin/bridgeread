import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/progress_service.dart';
import '../services/lesson_service.dart';
import '../main.dart' show routeObserver;

// ─────────────────────────────────────────────────────────────────────────────
// Zone data
// ─────────────────────────────────────────────────────────────────────────────

class _Zone {
  final double x, y, w, h;
  final String route, sfx;
  const _Zone(this.x, this.y, this.w, this.h, this.route, this.sfx);
}

// Set to true to show colored debug boxes for all tap zones
const _kDebugZones = false;

const _kZoneColors = [
  Colors.orange,  // RECAP
  Colors.blue,    // STORY
  Colors.green,   // GAME
  Colors.purple,  // LISTEN
];

const _kZoneLabels = ['RECAP', 'STORY', 'GAME', 'LISTEN'];

// 4 zones: recap / story / game / listen
// RECAP (i=0) has special navigation — handled in _onZoneTap
const _kZones = [
  _Zone(0.152, 0.420, 0.152, 0.217, '',        'audio/sfx/book-open.wav'),      // RECAP
  _Zone(0.355, 0.416, 0.144, 0.203, '/reader', 'audio/sfx/book-open.wav'),      // STORY
  _Zone(0.567, 0.421, 0.119, 0.247, '/quiz',   'audio/sfx/pop-click.wav'),      // GAME
  _Zone(0.781, 0.421, 0.136, 0.270, '/listen', 'audio/sfx/magic-sparkle.wav'),  // LISTEN
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
    with TickerProviderStateMixin, RouteAware {
  final _player = AudioPlayer();

  // Progress state
  int _completedCount = 0; // 0-4

  // Glow animations (420 ms)
  late final List<AnimationController> _ctrls;
  late final List<Animation<double>>   _anims;

  // Press-down animations (150 ms) — 1.0 → 0.95 → 1.0
  late final List<AnimationController> _pressCtrls;
  late final List<Animation<double>>   _pressAnims;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  // Called when the route above this one is popped — user is back on this screen
  @override
  void didPopNext() => _loadProgress();

  @override
  void initState() {
    super.initState();
    _loadProgress();
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
    _pressAnims = _pressCtrls
        .map((c) => TweenSequence<double>([
              TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.95), weight: 1),
              TweenSequenceItem(tween: Tween(begin: 0.95, end: 1.0), weight: 1),
            ]).animate(c))
        .toList();
  }

  Future<void> _loadProgress() async {
    await ProgressService.resetTodayIfNewDay();
    final prefs = await SharedPreferences.getInstance();

    // Check recap (stored as date string)
    final today = DateTime.now();
    final todayStr = '${today.year}-${today.month.toString().padLeft(2,'0')}-${today.day.toString().padLeft(2,'0')}';
    final recapDone = prefs.getString('today_recap_done') == todayStr;

    // Check listen (the final module — stored as bool by ProgressService)
    final listenDone = prefs.getBool('today_listen_done') == true;

    // Count completed modules (for zone-enable logic)
    int count = recapDone ? 1 : 0;
    for (final key in ['today_reader_done', 'today_phonics_done', 'today_quiz_done', 'today_recording_done']) {
      if (prefs.getBool(key) == true) count++;
    }

    if (mounted) setState(() {
      _completedCount = count;
      _listenDone = listenDone;
    });
  }

  bool _listenDone = false;

  String get _bgImage {
    if (_listenDone) return 'assets/home/study_bg_end.png';
    if (_completedCount == 0) return 'assets/home/study_bg_start.png';
    return 'assets/home/study_bg_mid.png';
  }

  // Zone i is active only when completedCount > 0, except RECAP (i==0) which is always active
  bool _zoneEnabled(int i) {
    if (i == 0) return true;
    return _completedCount > 0;
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _player.dispose();
    for (final c in _ctrls) c.dispose();
    for (final c in _pressCtrls) c.dispose();
    super.dispose();
  }

  Future<void> _onZoneTap(int i) async {
    if (!_zoneEnabled(i)) return; // disabled zone — ignore tap

    // Press-down animation
    _pressCtrls[i].forward(from: 0);
    // Glow flash
    _ctrls[i].forward(from: 0).then((_) => _ctrls[i].reverse());
    // Per-zone SFX
    _player.stop();
    _player.play(AssetSource(_kZones[i].sfx));

    await Future.delayed(const Duration(milliseconds: 160));
    if (!mounted) return;

    if (i == 0) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const RecapScreen()),
      );
    } else {
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
          return InteractiveViewer(
            minScale: 0.5,
            maxScale: 2.0,
            child: SizedBox(
              width: w,
              height: h,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // ── Background ────────────────────────────────────────
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 600),
                    child: Image.asset(
                      _bgImage,
                      key: ValueKey(_bgImage),
                      fit: BoxFit.cover,
                      width: w,
                      height: h,
                    ),
                  ),

                  // ── Back button ───────────────────────────────────────
                  Positioned(
                    left: 8,
                    top: MediaQuery.of(ctx).padding.top + 4,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back_ios_rounded,
                          color: Colors.white, size: 26),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ),

                  // ── Tap zones ─────────────────────────────────────────
                  ...List.generate(_kZones.length, (i) {
                    final z = _kZones[i];
                    return Positioned(
                      left:   z.x * w,
                      top:    z.y * h,
                      width:  z.w * w,
                      height: z.h * h,
                      child: AnimatedBuilder(
                        animation:
                            Listenable.merge([_anims[i], _pressAnims[i]]),
                        builder: (_, __) {
                          final v     = _anims[i].value;
                          final scale = _pressAnims[i].value * (1.0 + v * 0.07);
                          return Transform.scale(
                            scale: scale,
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onTap: () => _onZoneTap(i),
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  color: _kDebugZones
                                      ? _kZoneColors[i].withValues(alpha: 0.35)
                                      : Colors.white.withValues(alpha: v * 0.22),
                                  border: _kDebugZones
                                      ? Border.all(
                                          color: _kZoneColors[i], width: 2)
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
                                          _kZoneLabels[i],
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
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RecapScreen — plays biscuit01_original.mp3 with progress bar, then /reader
// ─────────────────────────────────────────────────────────────────────────────

class RecapScreen extends StatefulWidget {
  const RecapScreen({super.key});
  @override
  State<RecapScreen> createState() => _RecapScreenState();
}

class _RecapScreenState extends State<RecapScreen>
    with TickerProviderStateMixin {
  final _player = AudioPlayer();
  final List<StreamSubscription> _subs = [];

  bool     _playing  = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  // Waveform: 5 bars (same style as ListenScreen)
  late final List<AnimationController> _waveCtrl;
  late final List<Animation<double>>   _waveAnim;

  @override
  void initState() {
    super.initState();

    _waveCtrl = List.generate(5, (i) => AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 280 + i * 90),
    ));
    _waveAnim = _waveCtrl.map((c) =>
        Tween<double>(begin: 6, end: 40).animate(
            CurvedAnimation(parent: c, curve: Curves.easeInOut))).toList();

    _subs.addAll([
      _player.onPositionChanged.listen((p) {
        if (mounted) setState(() => _position = p);
      }),
      _player.onDurationChanged.listen((d) {
        if (mounted) setState(() => _duration = d);
      }),
      _player.onPlayerComplete.listen((_) async {
        _setPlaying(false);
        await _markRecapDone();
        if (mounted) Navigator.pushReplacementNamed(context, '/reader');
      }),
    ]);

    WidgetsBinding.instance.addPostFrameCallback((_) => _play());
  }

  @override
  void dispose() {
    for (final s in _subs) s.cancel();
    _player.dispose();
    for (final c in _waveCtrl) c.dispose();
    super.dispose();
  }

  Future<void> _markRecapDone() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now();
    final d = '${today.year}-${today.month.toString().padLeft(2,'0')}-${today.day.toString().padLeft(2,'0')}';
    await prefs.setString('today_recap_done', d);
  }

  Future<void> _play() async {
    // Play previous day's original audio for recap
    final service = LessonService();
    final lessonId = await service.restoreCurrentLessonId();

    // Map of lessonId -> previous book's original audio
    const prevAudioMap = {
      'biscuit_book1_day1': 'audio/biscuit_original.mp3', // Day 1 has no previous, play own
      'biscuit_baby_book2_day1': 'audio/biscuit_original.mp3', // Day 2 recaps Day 1
    };

    final audioPath = prevAudioMap[lessonId] ?? 'audio/biscuit_original.mp3';
    await _player.play(AssetSource(audioPath));
    _setPlaying(true);
  }

  Future<void> _togglePlay() async {
    if (_playing) {
      await _player.pause();
      _setPlaying(false);
    } else {
      await _player.resume();
      _setPlaying(true);
    }
  }

  void _setPlaying(bool v) {
    if (!mounted) return;
    setState(() => _playing = v);
    if (v) {
      for (final c in _waveCtrl) c.repeat(reverse: true);
    } else {
      for (final c in _waveCtrl) { c.stop(); c.value = 0; }
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final progress = _duration.inMilliseconds > 0
        ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Sleepy eggy background ───────────────────────────────────────
          Image.asset(
            'assets/pet/cards/spleepy.png',
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (_, __, ___) =>
                Container(color: const Color(0xFF1A2A4A)),
          ),
          // ── Dark overlay ─────────────────────────────────────────────────
          Container(color: Colors.black.withValues(alpha: 0.52)),

          // ── Content ──────────────────────────────────────────────────────
          SafeArea(
            child: Column(
              children: [
                // Top bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_rounded,
                            color: Colors.white70, size: 22),
                        onPressed: () {
                          _player.stop();
                          Navigator.pop(context);
                        },
                      ),
                      const Expanded(
                        child: Text(
                          'Story Recap  👂',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      // Skip → go straight to reader
                      GestureDetector(
                        onTap: () async {
                          _player.stop();
                          await _markRecapDone();
                          if (mounted) Navigator.pushReplacementNamed(context, '/reader');
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF8C42),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text('跳过',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              )),
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // Waveform
                _buildWaveform(),
                const SizedBox(height: 20),

                // Play / Pause button
                GestureDetector(
                  onTap: _togglePlay,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.25),
                          blurRadius: 24,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Icon(
                      _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: const Color(0xFF0D1B2A),
                      size: 46,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Progress slider + timestamps
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    children: [
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 6,
                          thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 8),
                          overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 16),
                          activeTrackColor: const Color(0xFFFF8C42),
                          inactiveTrackColor:
                              Colors.white.withValues(alpha: 0.2),
                          thumbColor: Colors.white,
                          overlayColor:
                              Colors.white.withValues(alpha: 0.15),
                        ),
                        child: Slider(
                          value: progress,
                          onChanged: (v) {
                            if (_duration.inMilliseconds > 0) {
                              final target = Duration(
                                  milliseconds:
                                      (v * _duration.inMilliseconds).toInt());
                              _player.seek(target);
                            }
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_fmt(_position),
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12)),
                            Text(_fmt(_duration),
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWaveform() {
    return SizedBox(
      height: 56,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(5, (i) => AnimatedBuilder(
          animation: _waveAnim[i],
          builder: (_, __) {
            final h = _playing ? _waveAnim[i].value : 6.0;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 80),
              width: 7,
              height: h,
              margin: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: _playing ? 0.75 : 0.25),
                borderRadius: BorderRadius.circular(4),
              ),
            );
          },
        )),
      ),
    );
  }
}
