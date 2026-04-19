import 'dart:convert';
import 'dart:math' show pi, cos, sin, min;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart' show routeObserver;
import 'reader_screen.dart';
import '../services/lesson_service.dart';
import '../services/progress_service.dart';
import '../services/week_service.dart';
import '../utils/cdn_asset.dart';
import '../utils/responsive_utils.dart';
import '../utils/audio_preloader.dart';
import '../services/analytics_service.dart';
import '../services/telemetry.dart';

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
  int _totalOwed   = 0;   // total debt across all past days
  int _todayPending = 4;  // modules not yet done today

  // Study room unlock state — true only when all 4 daily modules done
  bool _studyRoomUnlocked = false;
  bool _studyRoomVisitedToday = false;

  // Glow animation for the books zone
  late final AnimationController _glowCtrl;
  late final Animation<double>   _glowAnim;

  // Press-down scale animation for the books zone
  late final AnimationController _pressCtrl;
  late final Animation<double>   _pressAnim;

  // Book sparkle animation (always on)
  late final AnimationController _bookSparkleCtrl;
  late final Animation<double>   _bookSparkleAnim;

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

    // Book sparkle — slow loop, always running
    _bookSparkleCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 4000));
    _bookSparkleAnim = Tween<double>(begin: 0.0, end: 1.0)
        .animate(_bookSparkleCtrl);
    _bookSparkleCtrl.repeat();

    // Eggy unlock orbit — linear repeat for smooth star rotation
    _eggyGlowCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 3000));
    _eggyGlowAnim = Tween<double>(begin: 0.0, end: 1.0)
        .animate(_eggyGlowCtrl); // linear, no curve

    _loadStats();
    // Preload today's story audio in background
    AudioPreloader.preloadStoryAudio();
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
    _bookSparkleCtrl.dispose();
    _eggyGlowCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStats() async {
    final prefs = await SharedPreferences.getInstance();
    // Studyroom unlocks once today's listen is done
    final allDone = await ProgressService.isDoneToday('listen');

    // Check if studyroom was visited today
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final visitedDate = prefs.getString('studyroom_visited_date') ?? '';
    final visitedToday = visitedDate == todayStr;

    // Calculate total owed from debt_module_status
    final owed = await _calcTotalOwed(prefs);
    final pending = await ProgressService.getTodayPending();

    if (mounted) {
      setState(() {
        _streakDays         = prefs.getInt('streak_days') ?? 0;
        _totalStars         = prefs.getInt('total_stars') ?? 0;
        _studyRoomUnlocked  = allDone;
        _studyRoomVisitedToday = visitedToday;
        _totalOwed          = owed;
        _todayPending       = pending;
      });
      // Start or stop the orbit — show only when unlocked AND not yet visited today
      if (allDone && !visitedToday) {
        _eggyGlowCtrl.repeat();
      } else {
        _eggyGlowCtrl.stop();
        _eggyGlowCtrl.value = 0;
      }
    }
  }

  Future<int> _calcTotalOwed(SharedPreferences prefs) async {
    final startStr = prefs.getString('book_start_date');
    if (startStr == null) return 0;
    final startDate = WeekService.parseDate(startStr);
    if (startDate == null) return 0;

    final rawStatus = prefs.getString('debt_module_status');
    final moduleStatus = rawStatus != null
        ? Map<String, dynamic>.from(jsonDecode(rawStatus))
        : <String, dynamic>{};

    final now = chinaTime();
    final today = DateTime(now.year, now.month, now.day);
    int total = 0;
    var d = startDate;

    while (d.isBefore(today)) {
      final dateKey = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final status = moduleStatus[dateKey] as Map<String, dynamic>? ?? {};
      final dDate = DateTime(d.year, d.month, d.day);
      final sDate = DateTime(startDate.year, startDate.month, startDate.day);
      final isRegistrationDay = dDate == sDate;

      if (d.weekday >= 1 && d.weekday <= 5 || isRegistrationDay) {
        // Weekday or registration day: 4 modules
        const modules = ['recap', 'reader', 'quiz', 'listen'];
        total += modules.where((m) => status[m] != true).length;
      } else {
        // Normal weekend: 2 modules
        const modules = ['quiz', 'listen'];
        total += modules.where((m) => status[m] != true).length;
      }
      d = d.add(const Duration(days: 1));
    }
    return total;
  }

  Future<void> _onBooksTap(BuildContext ctx) async {
    _pressCtrl.forward(from: 0);
    _glowCtrl.forward(from: 0).then((_) => _glowCtrl.reverse());
    try { _player.play(cdnAudioSource('audio/sfx/book-open.wav')); } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 180));
    // Reset overrideDate so study page shows today's content
    WeekService.overrideDate = null;
    await ProgressService.setStudyDate(chinaTime());
    // Set today's lesson based on book_start_date
    final prefs = await SharedPreferences.getInstance();
    final startStr = prefs.getString('book_start_date');
    if (startStr != null) {
      final startDate = WeekService.parseDate(startStr);
      if (startDate != null) {
        final today = chinaTime();
        final bookIdx = WeekService.bookIndexForDate(today, startDate);
        if (bookIdx != null && bookIdx < kAllBooks.length) {
          await LessonService().setCurrentLesson(kAllBooks[bookIdx].lessonId);
        }
      }
    }
    if (mounted) Navigator.pushNamed(ctx, '/study').then((_) => _loadStats());
  }

  @override
  Widget build(BuildContext context) {
    R.init(context);
    return Scaffold(
      body: LayoutBuilder(
        builder: (ctx, box) {
          final w = box.maxWidth;
          final h = box.maxHeight;
          final mobile = R.isMobile;
          return SizedBox(
            width: w,
            height: h,
            child: Stack(
            fit: StackFit.expand,
            children: [
              // ── Layer 1: Background (fill entire screen) ────────────
              Positioned.fill(
                child: cdnImage('assets/home/layers/bg.png',
                  fit: BoxFit.cover, width: w, height: h,
                  errorBuilder: (_, __, ___) => Container(color: const Color(0xFFFFF4E6))),
              ),


              // ── Layer 3: Girl + Book (combined) ──────────────────
              Positioned.fill(
                child: Stack(
                  children: [
                    // The combined image
                    Positioned.fill(
                      child: cdnImage('assets/home/layers/girl_book.png',
                        fit: BoxFit.cover, width: w, height: h,
                        errorBuilder: (_, __, ___) => const SizedBox()),
                    ),
                    // Sparkle effect (only when study not yet done)
                    if (!_studyRoomUnlocked)
                    Positioned(
                      left: w * 0.4,
                      bottom: 0,
                      width: w * 1.15,
                      height: h * 0.75,
                      child: IgnorePointer(
                        child: AnimatedBuilder(
                          animation: _bookSparkleAnim,
                          builder: (_, __) => CustomPaint(
                            painter: _BookSparklePainter(_bookSparkleAnim.value),
                          ),
                        ),
                      ),
                    ),
                    // Book tap zone (right half)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      width: w * 0.55,
                      height: h * 0.75,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: () => _onBooksTap(ctx),
                      ),
                    ),
                    // Girl tap zone (left side, only when study room unlocked)
                    Positioned(
                      left: w * 0.03,
                      bottom: 0,
                      width: w * 0.45,
                      height: h * 0.6,
                      child: Stack(
                        children: [
                          // Glow effect when unlocked and not yet visited today
                          if (_studyRoomUnlocked && !_studyRoomVisitedToday)
                            Positioned.fill(
                              child: AnimatedBuilder(
                                animation: _eggyGlowAnim,
                                builder: (_, __) => CustomPaint(
                                  painter: _EggyOrbitPainter(_eggyGlowAnim.value),
                                ),
                              ),
                            ),
                          // Tap area
                          Positioned.fill(
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onTap: _studyRoomUnlocked
                                  ? () => _enterStudyRoom(ctx)
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ── Layer 5: Calendar (top-right, tappable) ─────────────
              Positioned(
                right: w * 0.02,
                top: h * 0.02,
                child: GestureDetector(
                  onTap: () => Navigator.pushNamed(ctx, '/calendar'),
                  child: cdnImage('assets/home/layers/cal.png',
                    height: h * 0.25, fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const SizedBox()),
                ),
              ),

              // ── Shortcuts (only visible after today's study is complete) ──
              if (_studyRoomUnlocked)
                Positioned(
                  right: mobile ? 8 : 16,
                  bottom: mobile ? 8 : 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _DevBtn(label: '📖 讲解', onTap: () =>
                          Navigator.pushNamed(ctx, '/reader').then((_) => _loadStats())),
                      const SizedBox(height: 6),
                      _DevBtn(label: '🧩 消消乐', onTap: () =>
                          Navigator.pushNamed(ctx, '/quiz').then((_) => _loadStats())),
                      const SizedBox(height: 6),
                      _DevBtn(label: '🔤 拼读', onTap: () =>
                          Navigator.pushNamed(ctx, '/phonics').then((_) => _loadStats())),
                      const SizedBox(height: 6),
                      _DevBtn(label: '🎙 录音', onTap: () =>
                          Navigator.pushNamed(ctx, '/recording').then((_) => _loadStats())),
                      const SizedBox(height: 6),
                      _DevBtn(label: '🎧 听力', onTap: () =>
                          Navigator.pushNamed(ctx, '/listen').then((_) => _loadStats())),
                      const SizedBox(height: 6),
                      _DevBtn(label: '🏆 排行榜', onTap: () =>
                          Navigator.pushNamed(ctx, '/ranking').then((_) => _loadStats())),
                      const SizedBox(height: 6),
                      _DevBtn(label: '🛠 书房', onTap: () => _enterStudyRoom(ctx)),
                    ],
                  ),
                ),

              // ── "我的英语小家" tap zone (top-left, to profile) ────────
              Positioned(
                left: 0,
                top: 0,
                width: w * 0.3,
                height: h * 0.15,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () => Navigator.pushNamed(ctx, '/profile').then((_) => _loadStats()),
                ),
              ),

              // ── Today badge (book top-right corner) ────────────────
              if (_todayPending > 0)
                Positioned(
                  left: w * 0.84,
                  bottom: h * 0.55,
                  child: GestureDetector(
                    onTap: () => _onBooksTap(ctx),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: R.s(14), vertical: R.s(8)),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF8F00).withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFF8F00).withValues(alpha: 0.40),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('🎯', style: TextStyle(fontSize: R.s(16))),
                          SizedBox(width: R.s(5)),
                          Text('今日 $_todayPending',
                            style: TextStyle(
                              color: const Color(0xFF795548),
                              fontWeight: FontWeight.w900,
                              fontSize: R.s(15),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // ── Makeup debt badge (centered on calendar) ──────────────
              if (_totalOwed + _todayPending > 0)
                Positioned(
                  right: w * 0.05,
                  top:   h * 0.03,
                  height: h * 0.25,
                  child: GestureDetector(
                    onTap: () => Navigator.pushNamed(ctx, '/calendar'),
                    child: Center(
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFFFD54F), Color(0xFFFFB300)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFFFB300).withValues(alpha: 0.35),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Text('待打卡(${_totalOwed + _todayPending})',
                              style: TextStyle(
                                color: const Color(0xFF795548),
                                fontWeight: FontWeight.w900,
                                fontSize: R.s(16),
                              ),
                            ),
                          ),
                          // Bell icon — centered above, tilted 45°
                          Positioned(
                            left: -8,
                            right: 8,
                            top: -36,
                            child: Center(
                              child: Transform.rotate(
                                angle: -0.785, // -45 degrees
                                child: const Text('🔔', style: TextStyle(fontSize: 28)),
                              ),
                            ),
                          ),
                          // Red dot — top-right corner of pill
                          Positioned(
                            right: -2,
                            top: -2,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Color(0xFFE53935),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),



              // ── Night widget (only after 20:30 China time) ──────────
              if (_isBedtime())
                Positioned(
                  left: w * 0.12,
                  bottom: h * 0.52,
                  child: AnimatedBuilder(
                    animation: _bookSparkleAnim,
                    builder: (_, __) {
                      // Gentle float: 4px up and down
                      final float = sin(_bookSparkleAnim.value * 2 * pi) * 4;
                      return Transform.translate(
                        offset: Offset(0, float),
                        child: GestureDetector(
                          onTap: () => Navigator.pushNamed(ctx, '/night-candle'),
                          child: Image.asset(
                            'assets/home/layers/night.png',
                            height: h * 0.216,
                            fit: BoxFit.contain,
                          ),
                        ),
                      );
                    },
                  ),
                ),

            ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _enterStudyRoom(BuildContext ctx) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    await prefs.setString('studyroom_visited_date', todayStr);
    if (!mounted) return;
    await Navigator.pushNamed(ctx, '/studyroom');
    _loadStats();
  }

  /// Check if it's after 20:30 China time (UTC+8)
  bool _isBedtime() {
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    return (now.hour == 20 && now.minute >= 30) || now.hour >= 21;
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
        padding: EdgeInsets.symmetric(horizontal: R.s(12), vertical: R.s(6)),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white30, width: 1),
        ),
        child: Text(
          label,
          style: TextStyle(
              color: Colors.white, fontSize: R.s(13), fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CalendarScreen — book calendar (one book per day)
// ─────────────────────────────────────────────────────────────────────────────

// Book data is now in week_service.dart → kAllBooks

// Uses chinaTime() from week_service.dart (supports timeTravel debug)

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime? _startDate;
  late DateTime _viewMonth; // which month is displayed
  bool _testMode = true;
  Map<String, int> _debtByDate = {};
  Map<String, Map<String, dynamic>> _moduleStatus = {};

  @override
  void initState() {
    super.initState();
    AnalyticsService.logEvent('calendar_view');
    Telemetry.log('calendar_enter');
    final now = chinaTime();
    _viewMonth = DateTime(now.year, now.month);
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    var start = prefs.getString('book_start_date');
    if (start == null) {
      var now = chinaTime();
      // If first launch is on weekend, roll back to Monday
      while (now.weekday > 5) {
        now = now.subtract(const Duration(days: 1));
      }
      // Roll back to Monday of that week
      while (now.weekday > 1) {
        now = now.subtract(const Duration(days: 1));
      }
      start = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      await prefs.setString('book_start_date', start);
    }

    // Load module status for calendar display
    await ProgressService.syncDebtFromServer();
    final debt = await ProgressService.getDebtByDate();
    final prefs2 = await SharedPreferences.getInstance();
    final rawStatus = prefs2.getString('debt_module_status');
    Map<String, Map<String, dynamic>> moduleStatus = {};
    if (rawStatus != null) {
      final decoded = jsonDecode(rawStatus) as Map<String, dynamic>;
      moduleStatus = decoded.map((k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map)));
    }

    if (mounted) {
      setState(() {
        _startDate = WeekService.parseDate(start);
        _debtByDate = debt;
        _moduleStatus = moduleStatus;
      });
    }
  }

  void _prevMonth() {
    setState(() {
      _viewMonth = DateTime(_viewMonth.year, _viewMonth.month - 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _viewMonth = DateTime(_viewMonth.year, _viewMonth.month + 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFFF8C42);
    final now = chinaTime();
    final today = DateTime(now.year, now.month, now.day);

    // Month header text
    const monthNames = ['', '一月', '二月', '三月', '四月', '五月', '六月',
        '七月', '八月', '九月', '十月', '十一月', '十二月'];
    final monthLabel = '${_viewMonth.year}年 ${monthNames[_viewMonth.month]}';

    // Build calendar grid
    final firstOfMonth = DateTime(_viewMonth.year, _viewMonth.month, 1);
    final daysInMonth = DateTime(_viewMonth.year, _viewMonth.month + 1, 0).day;
    final startWeekday = firstOfMonth.weekday; // 1=Mon

    return Scaffold(
      backgroundColor: const Color(0xFFFFF4E6),
      appBar: AppBar(
        backgroundColor: Colors.transparent, elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: orange),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('学习日历',
            style: TextStyle(color: orange, fontWeight: FontWeight.w900, fontSize: 20)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(_testMode ? Icons.lock_open_rounded : Icons.lock_rounded, color: orange, size: 22),
            onPressed: () => setState(() => _testMode = !_testMode),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          children: [
            // Month navigation
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(icon: const Icon(Icons.chevron_left, color: orange), onPressed: _prevMonth),
                Text(monthLabel, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFFE65100))),
                IconButton(icon: const Icon(Icons.chevron_right, color: orange), onPressed: _nextMonth),
              ],
            ),
            const SizedBox(height: 8),
            // Weekday headers
            Row(
              children: ['一', '二', '三', '四', '五', '六', '日'].map((d) =>
                Expanded(child: Center(child: Text(d,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                    color: d == '六' || d == '日' ? Colors.grey : orange))))).toList(),
            ),
            const SizedBox(height: 6),
            // Calendar grid
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7, childAspectRatio: 0.65, crossAxisSpacing: 6, mainAxisSpacing: 6,
                ),
                padding: const EdgeInsets.all(2),
                itemCount: 42, // 6 weeks max
                itemBuilder: (context, idx) {
                  final dayNum = idx - (startWeekday - 1) + 1;
                  if (dayNum < 1 || dayNum > daysInMonth) {
                    return const SizedBox(); // empty cell
                  }
                  final date = DateTime(_viewMonth.year, _viewMonth.month, dayNum);
                  final isToday = date == today;
                  final isWeekend = date.weekday > 5;
                  final isPast = date.isBefore(today) || date == today;

                  // Get book for this date
                  int? bookIdx;
                  if (_startDate != null && !date.isBefore(_startDate!)) {
                    bookIdx = WeekService.bookIndexForDate(date, _startDate!);
                  }
                  // Only show book for today and past dates (not future)
                  final book = (bookIdx != null && bookIdx < kAllBooks.length && (isPast || isToday))
                      ? kAllBooks[bookIdx] : null;
                  final unlocked = _testMode || (isPast && book != null);
                  final isActiveWeekend = isWeekend && _startDate != null && !date.isBefore(_startDate!) && (isPast || isToday);

                  // Pending module count for this date
                  final dateKey = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
                  int debt = 0;
                  final isInRange = (isPast || isToday) && _startDate != null && !date.isBefore(_startDate!);
                  if (isInRange && !isWeekend && book != null) {
                    // Weekday with book: 4 tracked modules
                    final status = _moduleStatus[dateKey] ?? {};
                    const modules = ['recap', 'reader', 'quiz', 'listen'];
                    debt = modules.where((m) => status[m] != true).length;
                  } else if (isInRange && isWeekend) {
                    final status = _moduleStatus[dateKey] ?? {};
                    // Registration day on weekend = 4 modules
                    final isRegistrationDay = _startDate != null &&
                        date.year == _startDate!.year &&
                        date.month == _startDate!.month &&
                        date.day == _startDate!.day;
                    if (isRegistrationDay) {
                      const modules = ['recap', 'reader', 'quiz', 'listen'];
                      debt = modules.where((m) => status[m] != true).length;
                    } else {
                      // Normal weekend: 2 modules
                      const modules = ['quiz', 'listen'];
                      debt = modules.where((m) => status[m] != true).length;
                    }
                  }

                  return GestureDetector(
                    onTap: (unlocked && book != null) || isActiveWeekend || debt > 0 ? () async {
                      // Set this date as the active date for all screens
                      WeekService.overrideDate = date;
                      await ProgressService.setStudyDate(date);
                      if (book != null) {
                        await LessonService().setCurrentLesson(book.lessonId);
                      }
                      if (context.mounted) {
                        // Always go directly to study page
                        Navigator.pushNamed(context, '/study').then((_) => _load());
                      }
                    } : null,
                    child: Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: isWeekend ? const Color(0xFFF5EDE3)
                            : unlocked ? Colors.white
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: LayoutBuilder(
                          builder: (context, constraints) {
                            final cellW = constraints.maxWidth;
                            final imgW = cellW * 0.55;
                            final imgH = imgW * 1.4; // book cover aspect ratio
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // Date circle (no red for today or debt)
                                Container(
                                  width: 24, height: 24,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isToday ? orange : Colors.black.withValues(alpha: 0.3),
                                  ),
                                  child: Center(child: Text('$dayNum',
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.white))),
                                ),
                                const SizedBox(height: 3),
                                // Image with debt badge on top-right of book cover
                                if (book != null)
                                  Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      Container(
                                        width: imgW, height: imgH,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(6),
                                          boxShadow: isToday ? [
                                            BoxShadow(color: orange.withValues(alpha: 0.5), blurRadius: 10, spreadRadius: 2),
                                          ] : [
                                            BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 4, offset: const Offset(0, 2)),
                                          ],
                                        ),
                                        child: Stack(children: [
                                          Positioned.fill(child: ClipRRect(
                                            borderRadius: BorderRadius.circular(6),
                                            child: cdnImage(book.coverAsset, fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) => Container(color: Colors.grey.shade200)),
                                          )),
                                          if (!unlocked)
                                            Positioned.fill(child: Container(
                                              decoration: BoxDecoration(
                                                color: Colors.white.withValues(alpha: 0.6),
                                                borderRadius: BorderRadius.circular(6)),
                                              child: Center(child: Icon(Icons.lock_rounded, size: 16, color: Colors.grey.shade400)),
                                            )),
                                        ]),
                                      ),
                                      // Debt badge on book cover top-right
                                      if (debt > 0)
                                        Positioned(
                                          right: -10,
                                          top: -8,
                                          child: Container(
                                            height: 20,
                                            width: 30,
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFFF6B35),
                                              borderRadius: BorderRadius.circular(10),
                                              boxShadow: const [
                                                BoxShadow(color: Color(0x66FF6B35), blurRadius: 4, offset: Offset(0, 1)),
                                              ],
                                            ),
                                            child: Center(child: Text('$debt',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w900,
                                              ))),
                                          ),
                                        ),
                                    ],
                                  )
                                else if (isActiveWeekend)
                                  Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      SizedBox(
                                        height: imgH,
                                        child: cdnImage('assets/pet/eggy_transparent_bg.webp', fit: BoxFit.contain),
                                      ),
                                      if (debt > 0)
                                        Positioned(
                                          right: -10,
                                          top: -8,
                                          child: Container(
                                            height: 20,
                                            width: 30,
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFFF6B35),
                                              borderRadius: BorderRadius.circular(10),
                                              boxShadow: const [
                                                BoxShadow(color: Color(0x66FF6B35), blurRadius: 4, offset: Offset(0, 1)),
                                              ],
                                            ),
                                            child: Center(child: Text('$debt',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w900,
                                              ))),
                                          ),
                                        ),
                                    ],
                                  )
                                else
                                  SizedBox(height: imgH),
                                const SizedBox(height: 3),
                                // Label
                                Text(
                                  book != null ? book.titleCN : isActiveWeekend ? '游戏+放松' : '',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                                    color: book != null ? const Color(0xFF666666) : const Color(0xFFFFB74D)),
                                  maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                                ),
                              ],
                            );
                          },
                        ),
                    ),
                  );
                },
              ),
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
        color: const Color(0xFFFF8F00).withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF8F00).withValues(alpha: 0.40),
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
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Debt badge — shows today's pending + accumulated debt
// ─────────────────────────────────────────────────────────────────────────────

class _DebtBadge extends StatelessWidget {
  final int totalOwed;
  final int todayPending;
  const _DebtBadge({required this.totalOwed, required this.todayPending});

  @override
  Widget build(BuildContext context) {
    final total = totalOwed + todayPending;
    if (total == 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF4CAF50),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF4CAF50).withValues(alpha: 0.40),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('✅', style: TextStyle(fontSize: 16)),
            SizedBox(width: 5),
            Text('全部完成！', style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: totalOwed > 0 ? const Color(0xFFFF6B35) : const Color(0xFFFF8F00),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: (totalOwed > 0 ? const Color(0xFFFF6B35) : const Color(0xFFFF8F00))
                .withValues(alpha: 0.40),
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
              Text(totalOwed > 0 ? '📋' : '📚', style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 5),
              Text(
                '待打卡 $total',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          if (totalOwed > 0) ...[
            const SizedBox(height: 2),
            Text(
              '今日 $todayPending + 欠卡 $totalOwed',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Orbiting colorful stars around the Eggy unlock zone
// ─────────────────────────────────────────────────────────────────────────────

class _TriangleBadgePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFFFF8F00);
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height * 0.7)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(0, size.height * 0.7)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

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
    final rx = size.width  * 0.35; // horizontal orbit radius (2/3 of 0.52)
    final ry = size.height * 0.35; // vertical orbit radius (2/3 of 0.52)

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

/// Colorful twinkling sparkles around the book to attract kids
class _BookSparklePainter extends CustomPainter {
  final double t;
  _BookSparklePainter(this.t);

  static const _colors = [
    Color(0xFFFFE600), // yellow
    Color(0xFFFF9900), // orange
    Color(0xFFFF4E8C), // pink
    Color(0xFF44CCFF), // cyan
    Color(0xFF44FF88), // green
    Color(0xFFCC44FF), // violet
    Color(0xFFFFFFFF), // white
    Color(0xFFFF6644), // red-orange
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < 35; i++) {
      // Spread stars densely around the book area
      final px = size.width  * (0.05 + (((i * 73 + 42) % 100) / 100.0) * 0.9);
      final baseY = size.height * (0.05 + (((i * 131 + 42) % 100) / 100.0) * 0.85);

      // Each star fades in/out at different phase + slight float up/down
      final phase = (t + i / 35.0) % 1.0;
      final alpha = (sin(phase * 2 * pi) * 0.4 + 0.6); // 0.2 ~ 1.0
      final floatY = sin(phase * 2 * pi) * 5; // float +/- 5px
      final py = baseY + floatY;

      final color = _colors[i % _colors.length].withValues(alpha: alpha);
      final radius = 6.0 + (i % 3) * 2.5; // 6–11 px

      // Glow
      final glowPaint = Paint()
        ..color = _colors[i % _colors.length].withValues(alpha: alpha * 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawCircle(Offset(px, py), radius * 2.0, glowPaint);

      // 4-point star
      final path = Path();
      final inner = radius * 0.4;
      for (int j = 0; j < 8; j++) {
        final a = (j * pi / 4) - pi / 2;
        final r = (j.isEven) ? radius : inner;
        final x = px + cos(a) * r;
        final y = py + sin(a) * r;
        if (j == 0) path.moveTo(x, y); else path.lineTo(x, y);
      }
      path.close();
      canvas.drawPath(path, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_BookSparklePainter old) => old.t != t;
}
