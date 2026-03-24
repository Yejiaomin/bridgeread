import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/test_data.dart';

// ─────────────────────────────────────────────────────────────────────────────
// HomeScreen — background image + transparent tap zones
// ─────────────────────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin {
  final _player = AudioPlayer();
  int _streakDays  = 0;
  int _totalStars  = 0;

  // Glow animation for the books zone
  late final AnimationController _glowCtrl;
  late final Animation<double>   _glowAnim;

  // Press-down scale animation for the books zone
  late final AnimationController _pressCtrl;
  late final Animation<double>   _pressAnim;

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

    _loadStats();
  }

  @override
  void dispose() {
    _player.dispose();
    _glowCtrl.dispose();
    _pressCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStats() async {
    final prefs = await SharedPreferences.getInstance();
    // Seed demo data on first run (streak_days == 0 means fresh install)
    if ((prefs.getInt('streak_days') ?? 0) == 0) {
      await seedTestData();
    }
    if (mounted) {
      setState(() {
        _streakDays = prefs.getInt('streak_days') ?? 0;
        _totalStars = prefs.getInt('total_stars') ?? 0;
      });
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
          return Stack(
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

              // ── Overlay: streak (top-left) ────────────────────────────
              Positioned(
                left: 16,
                top:  MediaQuery.of(ctx).padding.top + 12,
                child: _StatBadge(
                  emoji: '🔥',
                  value: '$_streakDays天',
                  bg:   const Color(0xFFFF6B35),
                  textColor: Colors.white,
                ),
              ),



            ],
          );
        },
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

class _StatBadge extends StatelessWidget {
  final String emoji, value;
  final Color bg, textColor;
  const _StatBadge({
    required this.emoji,
    required this.value,
    required this.bg,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 8,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 5),
          Text(value,
              style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 15)),
        ],
      ),
    );
  }
}
