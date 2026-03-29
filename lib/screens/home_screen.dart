import 'dart:math' show pi, cos, sin, min;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/test_data.dart';
import '../main.dart' show routeObserver;

// ─────────────────────────────────────────────────────────────────────────────
// HomeScreen — background image + transparent tap zones
// ─────────────────────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin, RouteAware {
  final _player = AudioPlayer();
  int _streakDays  = 0;
  int _totalStars  = 0;

  // Study room unlock state — true only when all 4 daily modules done
  bool _studyRoomUnlocked = false;

  // Glow animation for the books zone
  late final AnimationController _glowCtrl;
  late final Animation<double>   _glowAnim;

  // Press-down scale animation for the books zone
  late final AnimationController _pressCtrl;
  late final Animation<double>   _pressAnim;

  // Pulsing glow for the Eggy/study-room unlock zone
  late final AnimationController _eggyGlowCtrl;
  late final Animation<double>   _eggyGlowAnim;

  @override
  void initState() {
    super.initState();
    _glowCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 450));
    _glowAnim = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _glowCtrl, curve: Curves.easeOut));

    _pressCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 150));
    _pressAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.95), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 0.95, end: 1.0), weight: 1),
    ]).animate(_pressCtrl);

    // Eggy unlock orbit — linear repeat for smooth star rotation
    _eggyGlowCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 3000));
    _eggyGlowAnim = Tween<double>(begin: 0.0, end: 1.0)
        .animate(_eggyGlowCtrl); // linear, no curve

    _loadStats();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  // Reload whenever any child route is popped back to home
  @override
  void didPopNext() => _loadStats();

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _player.dispose();
    _glowCtrl.dispose();
    _pressCtrl.dispose();
    _eggyGlowCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStats() async {
    final prefs = await SharedPreferences.getInstance();
    // Seed demo data on first run (streak_days == 0 means fresh install)
    if ((prefs.getInt('streak_days') ?? 0) == 0) {
      await seedTestData();
    }

    // Same condition as study_screen end background: today_listen_done == true
    final allDone = prefs.getBool('today_listen_done') ?? false;

    if (mounted) {
      setState(() {
        _streakDays         = prefs.getInt('streak_days') ?? 0;
        _totalStars         = prefs.getInt('total_stars') ?? 0;
        _studyRoomUnlocked  = allDone;
      });
      // Start or stop the pulse based on unlock state
      if (allDone) {
        _eggyGlowCtrl.repeat();
      } else {
        _eggyGlowCtrl.stop();
        _eggyGlowCtrl.value = 0;
      }
    }
  }

  Future<void> _onBooksTap(BuildContext ctx) async {
    _pressCtrl.forward(from: 0);
    _glowCtrl.forward(from: 0).then((_) => _glowCtrl.reverse());
    _player.play(AssetSource('audio/sfx/book-open.wav'));
    await Future.delayed(const Duration(milliseconds: 180));
    if (mounted) Navigator.pushNamed(ctx, '/study').then((_) => _loadStats());
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
              // ── Background ────────────────────────────────────────────
              Image.asset('assets/home/home_bg.png',
                  fit: BoxFit.cover, width: w, height: h),

              // ── BOOKS tap zone ────────────────────────────────────────
              // x=0.415, y=0.313, w=0.421, h=0.655
              Positioned(
                left:   w * 0.415,
                top:    h * 0.313,
                child: _TapZone(
                  width:    w * 0.421,
                  height:   h * 0.655,
                  glowAnim: _glowAnim,
                  pressAnim: _pressAnim,
                  onTap: () => _onBooksTap(ctx),
                ),
              ),

              // ── CALENDAR tap zone ─────────────────────────────────────
              // x=0.787, y=0.040, w=0.197, h=0.309
              Positioned(
                left:  w * 0.787,
                top:   h * 0.040,
                child: _TapZone(
                  width:  w * 0.197,
                  height: h * 0.309,
                  onTap: () => Navigator.pushNamed(ctx, '/calendar'),
                ),
              ),

              // ── EGGY unlock zone ──────────────────────────────────────
              // Invisible until all 4 daily modules are done.
              // Coordinates from highlight: x=0.087, y=0.710, w=0.144, h=0.215
              if (_studyRoomUnlocked)
                Positioned(
                  left:   w * 0.087,
                  top:    h * 0.710,
                  width:  w * 0.144,
                  height: h * 0.215,
                  child: GestureDetector(
                    onTap: () => Navigator.pushNamed(ctx, '/studyroom')
                        .then((_) => _loadStats()),
                    child: AnimatedBuilder(
                      animation: _eggyGlowAnim,
                      builder: (_, __) => CustomPaint(
                        painter: _EggyOrbitPainter(_eggyGlowAnim.value),
                      ),
                    ),
                  ),
                ),

              // ── DEV shortcuts ─────────────────────────────────────────
              Positioned(
                right: 16,
                bottom: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _DevBtn(label: '🛠 书房', onTap: () async {
                      final prefs = await SharedPreferences.getInstance();
                      final current = prefs.getInt('total_stars') ?? 0;
                      await prefs.setInt('total_stars', current + 100);
                      if (!mounted) return;
                      Navigator.pushNamed(ctx, '/studyroom').then((_) => _loadStats());
                    }),
                    const SizedBox(height: 6),
                    _DevBtn(label: '🔤 拼读', onTap: () =>
                        Navigator.pushNamed(ctx, '/phonics').then((_) => _loadStats())),
                    const SizedBox(height: 6),
                    _DevBtn(label: '🎙 录音', onTap: () =>
                        Navigator.pushNamed(ctx, '/recording').then((_) => _loadStats())),
                    const SizedBox(height: 6),
                    _DevBtn(label: '🧩 消消乐', onTap: () =>
                        Navigator.pushNamed(ctx, '/quiz').then((_) => _loadStats())),
                    const SizedBox(height: 6),
                    _DevBtn(label: '🎧 听力', onTap: () =>
                        Navigator.pushNamed(ctx, '/listen').then((_) => _loadStats())),
                    const SizedBox(height: 6),
                    _DevBtn(label: '📖 讲解', onTap: () =>
                        Navigator.pushNamed(ctx, '/reader').then((_) => _loadStats())),
                  ],
                ),
              ),

              // ── Streak badge (top-left) ───────────────────────────────
              Positioned(
                left: 16,
                top:  MediaQuery.of(ctx).padding.top + 12,
                child: GestureDetector(
                  onTap: () => Navigator.pushNamed(ctx, '/calendar'),
                  child: _StreakBadge(days: _streakDays),
                ),
              ),



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
// Dev shortcut button
// ─────────────────────────────────────────────────────────────────────────────

class _DevBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _DevBtn({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white30, width: 1),
        ),
        child: Text(
          label,
          style: const TextStyle(
              color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CalendarScreen — streak calendar placeholder
// ─────────────────────────────────────────────────────────────────────────────

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  int  _streakDays = 0;
  List<bool> _weekActive = List.filled(7, false);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final activeDates = (prefs.getString('active_dates') ?? '')
        .split(',')
        .where((s) => s.isNotEmpty)
        .toSet();
    final now      = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    String dateStr(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final week = List.generate(
        7, (i) => activeDates.contains(dateStr(weekStart.add(Duration(days: i)))));
    if (mounted) {
      setState(() {
        _streakDays = prefs.getInt('streak_days') ?? 0;
        _weekActive = week;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const labels  = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const orange  = Color(0xFFFF8C42);
    final todayIdx = DateTime.now().weekday - 1;

    return Scaffold(
      backgroundColor: const Color(0xFFFFF4E6),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: orange),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('学习日历',
            style: TextStyle(
                color: orange,
                fontWeight: FontWeight.w900,
                fontSize: 20)),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Streak card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFFFFB347), Color(0xFFFF7043)]),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                      color: const Color(0xFFFF7043).withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 6))
                ],
              ),
              child: Column(
                children: [
                  const Text('🔥', style: TextStyle(fontSize: 48)),
                  const SizedBox(height: 8),
                  Text('$_streakDays 天连续学习！',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900)),
                ],
              ),
            ),
            const SizedBox(height: 32),
            // Week row
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('本周打卡',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFE65100))),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(7, (i) {
                final isToday = i == todayIdx;
                final active  = _weekActive[i];
                return Column(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: active
                            ? orange
                            : isToday
                                ? const Color(0xFFFFE0B2)
                                : Colors.grey.shade200,
                        border: isToday && !active
                            ? Border.all(color: orange, width: 2.5)
                            : null,
                        boxShadow: active
                            ? [BoxShadow(
                                color: orange.withValues(alpha: 0.40),
                                blurRadius: 8,
                                offset: const Offset(0, 3))]
                            : null,
                      ),
                      child: active
                          ? const Icon(Icons.check_rounded,
                              color: Colors.white, size: 22)
                          : isToday
                              ? Center(
                                  child: Container(
                                    width: 10, height: 10,
                                    decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: orange),
                                  ))
                              : null,
                    ),
                    const SizedBox(height: 6),
                    Text(labels[i],
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: isToday
                                ? FontWeight.w900
                                : FontWeight.w500,
                            color: isToday
                                ? orange
                                : Colors.grey.shade500)),
                  ],
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Transparent tap zone. Must be placed inside a Positioned in a Stack.
/// Handles glow + press-down scale animations internally.
class _TapZone extends StatelessWidget {
  final double width, height;
  final VoidCallback onTap;
  final Animation<double>? glowAnim;
  final Animation<double>? pressAnim;

  const _TapZone({
    required this.width,
    required this.height,
    required this.onTap,
    this.glowAnim,
    this.pressAnim,
  });

  @override
  Widget build(BuildContext context) {
    final anims = <Listenable>[
      if (glowAnim  != null) glowAnim!,
      if (pressAnim != null) pressAnim!,
    ];

    return AnimatedBuilder(
      animation: anims.isEmpty
          ? const AlwaysStoppedAnimation(0)
          : Listenable.merge(anims),
      builder: (_, __) {
        final glow  = glowAnim?.value  ?? 0.0;
        final press = pressAnim?.value ?? 1.0;
        return Transform.scale(
          scale: press * (1.0 + glow * 0.05),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onTap,
            child: Container(
              width:  width,
              height: height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Colors.white.withValues(alpha: glow * 0.18),
                boxShadow: glow > 0.01
                    ? [
                        BoxShadow(
                          color: Colors.orangeAccent
                              .withValues(alpha: glow * 0.55),
                          blurRadius: 24 * glow,
                          spreadRadius: 6 * glow,
                        )
                      ]
                    : null,
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Streak badge — shows flame + day count + Eggy's emotional message
// ─────────────────────────────────────────────────────────────────────────────

class _StreakBadge extends StatelessWidget {
  final int days;
  const _StreakBadge({required this.days});

  String get _message {
    if (days == 0) return 'Eggy 在等你 💛';
    if (days == 1) return 'Eggy：欢迎回来！';
    if (days < 4)  return 'Eggy：你记得我～';
    if (days < 7)  return 'Eggy：谢谢你每天来！';
    if (days < 14) return 'Eggy：已经一周啦 🎉';
    if (days < 30) return 'Eggy：你是我好朋友！';
    return 'Eggy：整整一个月！💛';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFF6B35),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF6B35).withValues(alpha: 0.40),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🔥', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 5),
              Text(
                days == 0 ? '快来打卡' : '$days 天连续',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            _message,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Orbiting colorful stars around the Eggy unlock zone
// ─────────────────────────────────────────────────────────────────────────────

class _EggyOrbitPainter extends CustomPainter {
  final double t; // 0.0 → 1.0, repeating
  _EggyOrbitPainter(this.t);

  static const _starColors = [
    Color(0xFFFF4E8C), // pink
    Color(0xFFFF9900), // orange
    Color(0xFFFFE600), // yellow
    Color(0xFF44FF88), // green
    Color(0xFF44CCFF), // cyan
    Color(0xFFCC44FF), // violet
    Color(0xFFFF6644), // red-orange
    Color(0xFFFFFFFF), // white
    Color(0xFF00FFD4), // teal
    Color(0xFFFF44CC), // magenta
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width  / 2;
    final cy = size.height / 2;
    final rx = size.width  * 0.52; // horizontal orbit radius
    final ry = size.height * 0.52; // vertical orbit radius

    for (int i = 0; i < 10; i++) {
      final phase  = (i / 10.0);           // evenly spaced
      final speed  = 0.7 + (i % 3) * 0.2; // slight speed variation
      final angle  = (t * speed + phase) * 2 * pi;
      final px     = cx + cos(angle) * rx;
      final py     = cy + sin(angle) * ry;
      final color  = _starColors[i];
      final radius = 4.0 + (i % 3) * 1.5; // 4–7 px

      // Glow
      final glowPaint = Paint()
        ..color  = color.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawCircle(Offset(px, py), radius * 2.2, glowPaint);

      // 4-point star
      _drawStar(canvas, Offset(px, py), radius, color);
    }
  }

  void _drawStar(Canvas canvas, Offset center, double r, Color color) {
    final path = Path();
    const points = 4;
    final inner  = r * 0.42;
    for (int i = 0; i < points * 2; i++) {
      final a   = (i * pi / points) - pi / 2;
      final rad = (i.isEven) ? r : inner;
      final x   = center.dx + cos(a) * rad;
      final y   = center.dy + sin(a) * rad;
      if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_EggyOrbitPainter old) => old.t != t;
}
