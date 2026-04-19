import 'dart:async';
import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show DefaultAssetBundle;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/progress_service.dart';
import '../services/api_service.dart';
import '../services/lesson_service.dart';
import '../services/week_service.dart';
import '../main.dart' show routeObserver;
import '../utils/cdn_asset.dart';
import '../utils/responsive_utils.dart';
import '../utils/audio_preloader.dart';
import '../services/analytics_service.dart';
import '../services/telemetry.dart';

class _RecapPage {
  final String imageAsset;
  final int startMs;
  const _RecapPage(this.imageAsset, this.startMs);
}

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

// Weekday: 4 zones: recap / story / game / listen
const _kZones = [
  _Zone(0.152, 0.420, 0.152, 0.217, '',        'audio/sfx/book-open.wav'),      // RECAP
  _Zone(0.355, 0.416, 0.144, 0.203, '/reader', 'audio/sfx/book-open.wav'),      // STORY
  _Zone(0.567, 0.421, 0.119, 0.247, '/quiz',   'audio/sfx/pop-click.wav'),      // GAME
  _Zone(0.781, 0.421, 0.136, 0.270, '/listen', 'audio/sfx/magic-sparkle.wav'),  // LISTEN
];

// Weekend: 2 zones: game / listen (positions adjusted for weekend_bg.webp)
const _kWeekendZones = [
  _Zone(0.398, 0.367, 0.155, 0.267, '/weekend-game', 'audio/sfx/pop-click.wav'),    // GAME
  _Zone(0.746, 0.432, 0.179, 0.291, '/listen',       'audio/sfx/magic-sparkle.wav'), // LISTEN
];

const _kWeekendZoneColors = [Colors.green, Colors.purple];
const _kWeekendZoneLabels = ['GAME', 'LISTEN'];

/// Check if active date is weekend
bool _isWeekend() {
  final day = activeDate().weekday;
  return day == 6 || day == 7;
}

/// Async check: true weekend only if NOT the registration day.
/// Registration day is always treated as weekday (4 tasks).
Future<bool> _isReviewWeekend() async {
  final day = activeDate().weekday;
  if (day != 6 && day != 7) return false;
  // Registration day = weekday mode
  final prefs = await SharedPreferences.getInstance();
  final startStr = prefs.getString('book_start_date');
  if (startStr == null) return false;
  final startDate = WeekService.parseDate(startStr);
  if (startDate == null) return false;
  final now = activeDate();
  final today = DateTime(now.year, now.month, now.day);
  final start = DateTime(startDate.year, startDate.month, startDate.day);
  if (today == start) return false; // registration day = weekday
  return true; // normal weekend
}

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

  // Weekend mode — resolved async in initState
  bool _weekend = _isWeekend(); // initial guess, refined by _resolveWeekend()
  bool _resolved = false;

  List<_Zone> get _zones => _weekend ? _kWeekendZones : _kZones;

  // Progress state
  int _completedCount = 0; // 0-4
  // Module done flags for badge display: [recap, reader, quiz, listen]
  // Only reader(1) and quiz(2) are tracked in daily_progress for debt
  List<bool> _zoneDone = [false, false, false, false];

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
    AnalyticsService.logEvent('book_start');
    Telemetry.log('study_enter', {
      'weekend_initial': _weekend,
      'override_date': WeekService.overrideDate?.toIso8601String(),
    });
    _resolveWeekend();
    // Always create 4 controllers (max zones); use first N based on mode
    const zoneCount = 4;
    _ctrls = List.generate(
      zoneCount,
      (_) => AnimationController(
          vsync: this, duration: const Duration(milliseconds: 420)),
    );
    _anims = _ctrls
        .map((c) => Tween<double>(begin: 0, end: 1).animate(
            CurvedAnimation(parent: c, curve: Curves.easeOut)))
        .toList();

    _pressCtrls = List.generate(
      zoneCount,
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

  /// Resolve weekend mode:
  /// - Weekend + no books this week (new user) → weekday mode
  /// - Weekday + all books completed → review mode (last 5 books)
  /// - Otherwise → normal
  Future<void> _resolveWeekend() async {
    bool shouldBeWeekend = _weekend;

    try {
      if (_weekend) {
        final weekBooks = await WeekService.thisWeekBooks();
        if (weekBooks.isEmpty) shouldBeWeekend = false;
      } else {
        final allDone = await WeekService.allBooksCompleted();
        final todayIdx = await WeekService.todayBookIndex();
        if (allDone && todayIdx == null) shouldBeWeekend = true;
      }
    } catch (e, st) {
      Telemetry.log('study_resolve_weekend_error', {'error': e.toString(), 'stack': st.toString().split('\n').take(3).join(' | ')});
      rethrow;
    }

    // Always mark resolved (even if mode didn't flip) so build() stops showing
    // the loading state and renders the correct zones in one go — no flicker.
    if (mounted) {
      setState(() {
        _weekend = shouldBeWeekend;
        _resolved = true;
      });
    }
    Telemetry.log('study_weekend_resolved', {'weekend': _weekend});
    _loadProgress();
  }

  Future<void> _loadProgress() async {
    final active = activeDate();
    final now = chinaTime();
    final todayDate = DateTime(now.year, now.month, now.day);
    final activeDay = DateTime(active.year, active.month, active.day);
    final isViewingToday = WeekService.overrideDate == null || activeDay == todayDate;

    bool recapDone, readerDone, quizDone, listenDone;

    if (isViewingToday) {
      // Today: read from local SharedPreferences
      await ProgressService.resetTodayIfNewDay();
      final prefs = await SharedPreferences.getInstance();
      final now = chinaTime();
      final todayStr = '${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}';
      recapDone = prefs.getString('today_recap_done') == todayStr;
      readerDone = prefs.getBool('today_reader_done') == true;
      quizDone = prefs.getBool('today_quiz_done') == true;
      listenDone = prefs.getBool('today_listen_done') == true;
    } else {
      // Past date (from calendar): read from server-cached module status
      final dateStr = '${active.year}-${active.month.toString().padLeft(2,'0')}-${active.day.toString().padLeft(2,'0')}';
      final status = await ProgressService.getModuleStatusForDate(dateStr);
      recapDone = status['recap'] ?? false;
      readerDone = status['reader'] ?? false;
      quizDone = status['quiz'] ?? false;
      listenDone = status['listen'] ?? false;
    }

    // Count completed modules (for zone-enable logic)
    int count = 0;
    if (recapDone) count++;
    if (readerDone) count++;
    if (quizDone) count++;
    if (listenDone) count++;

    if (mounted) setState(() {
      _completedCount = count;
      _listenDone = listenDone;
      _zoneDone = _weekend
          ? [quizDone, listenDone]  // weekend: game, listen
          : [recapDone, readerDone, quizDone, listenDone];
    });
  }

  bool _listenDone = false;

  String get _bgImage {
    if (_weekend) return 'assets/home/weekend_bg.webp';
    if (_completedCount == 4) return 'assets/home/study_bg_end.webp';
    if (!_zoneDone[0]) return 'assets/home/study_bg_start.webp'; // recap not done
    return 'assets/home/study_bg_mid.webp';
  }

  // Zone 0 (RECAP) is always active; zones 1-3 unlock after RECAP is done
  // Weekend: all zones always active
  bool _zoneEnabled(int i) {
    if (_weekend) return true;
    if (i == 0) return true;
    return _zoneDone[0]; // RECAP done → all others unlocked
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
    if (!_zoneEnabled(i)) return;

    // Analytics: track zone start
    final labels = _weekend ? _kWeekendZoneLabels : _kZoneLabels;
    if (i < labels.length) {
      AnalyticsService.logEvent('${labels[i].toLowerCase()}_start');
    }

    // Press-down animation
    if (i < _pressCtrls.length) _pressCtrls[i].forward(from: 0);
    if (i < _ctrls.length) _ctrls[i].forward(from: 0).then((_) => _ctrls[i].reverse());
    // Per-zone SFX
    if (i < _zones.length) {
      try { _player.stop(); } catch (_) {}
      try { _player.play(cdnAudioSource(_zones[i].sfx)); } catch (_) {}
    }

    await Future.delayed(const Duration(milliseconds: 160));
    if (!mounted) return;

    if (!_weekend && i == 0) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const RecapScreen()),
      );
    } else {
      Navigator.pushNamed(context, _zones[i].route);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Wait until weekend mode is resolved before rendering — avoids the
    // weekend → weekday flicker (and the brief blank during AnimatedSwitcher
    // bg crossfade) for new users on Saturday/Sunday.
    if (!_resolved) {
      return const Scaffold(
        backgroundColor: Color(0xFFFFF4E6),
        body: Center(child: CircularProgressIndicator(color: Color(0xFFFF8C42))),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFFFFF4E6),
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
                    child: cdnImage(_bgImage,
                      key: ValueKey(_bgImage),
                      fit: BoxFit.cover,
                      width: w,
                      height: h,
                      errorBuilder: (_, err, __) {
                        Telemetry.log('study_bg_load_error', {
                          'image': _bgImage,
                          'error': err.toString(),
                        });
                        return Container(
                          color: const Color(0xFFFFF4E6),
                          alignment: Alignment.center,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.broken_image_outlined,
                                  size: 48, color: Color(0xFFFF8C42)),
                              const SizedBox(height: 12),
                              const Text('背景图加载失败',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFFE65100))),
                              const SizedBox(height: 4),
                              const Text('请检查网络或刷新页面',
                                  style: TextStyle(fontSize: 13, color: Colors.black54)),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: () {
                                  imageCache.evict(AssetImage(_bgImage));
                                  setState(() {});
                                },
                                child: const Text('重试'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),

                  // ── Back button ───────────────────────────────────────
                  Positioned(
                    left: 8,
                    top: MediaQuery.of(ctx).padding.top + 4,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.25),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back_ios_rounded,
                            color: Colors.white, size: 22),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ),
                  ),

                  // ── Tap zones ─────────────────────────────────────────
                  ...List.generate(_zones.length, (i) {
                    final z = _zones[i];
                    // Show "1" badge on all incomplete zones (weekday and weekend)
                    final showBadge = i < _zoneDone.length && !_zoneDone[i];
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
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Container(
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
                                  // Red debt badge
                                  if (showBadge)
                                    Positioned(
                                      right: R.s(i == 2 ? -22 : 2),
                                      top: R.s(-4),
                                      child: Container(
                                        height: R.s(22),
                                        width: R.s(32),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFF6B35),
                                          borderRadius: BorderRadius.circular(R.s(11)),
                                          boxShadow: const [
                                            BoxShadow(
                                              color: Color(0x66FF6B35),
                                              blurRadius: 6,
                                              offset: Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: Center(
                                          child: Text('1',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: R.s(13),
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
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

  // Book page display for recap
  List<_RecapPage> _pageTimings = [];
  int _currentPageIdx = 0;
  String _coverImage = '';
  String _recapTitle = '';

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
      _player.onPositionChanged.handleError((_) {}).listen((p) {
        if (mounted) {
          setState(() => _position = p);
          _updatePageForPosition(p);
        }
      }),
      _player.onDurationChanged.handleError((_) {}).listen((d) {
        if (mounted) setState(() => _duration = d);
      }),
      _player.onPlayerComplete.listen((_) async {
        _setPlaying(false);
        await _markRecapDone();
        if (mounted) Navigator.pushReplacementNamed(context, '/reader');
      }),
    ]);

    WidgetsBinding.instance.addPostFrameCallback((_) => _play());
    // Preload all task audio while user listens to recap
    AudioPreloader.preloadAllAudio();
  }

  void _updatePageForPosition(Duration pos) {
    if (_pageTimings.isEmpty) return;
    final ms = pos.inMilliseconds;
    int pageIdx = 0;
    for (int i = _pageTimings.length - 1; i >= 0; i--) {
      if (ms >= _pageTimings[i].startMs) {
        pageIdx = i;
        break;
      }
    }
    if (pageIdx != _currentPageIdx) {
      setState(() => _currentPageIdx = pageIdx);
    }
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
    final d = await ProgressService.getStudyDateStr();
    await prefs.setString('today_recap_done', d);
    AnalyticsService.logEvent('recap_done');

    // Save to debt_module_status for calendar history
    final raw = prefs.getString('debt_module_status');
    final all = raw != null ? Map<String, dynamic>.from(jsonDecode(raw)) : <String, dynamic>{};
    final dayData = all[d] != null ? Map<String, dynamic>.from(all[d] as Map) : <String, dynamic>{};
    dayData['recap'] = true;
    all[d] = dayData;
    await prefs.setString('debt_module_status', jsonEncode(all));

    // Sync to server
    final lessonId = prefs.getString('current_lesson_id');
    ApiService().syncProgress(
      date: d,
      module: 'recap',
      done: true,
      stars: 10,
      lessonId: lessonId,
    );
  }

  // Get previous book from global order (no hardcoded map needed)
  static (String, String) _prevBook(String lessonId) {
    final idx = kAllBooks.indexWhere((b) => b.lessonId == lessonId);
    if (idx <= 0) {
      // First book: recap itself
      final first = kAllBooks[0];
      return (first.lessonId, first.originalAudio);
    }
    final prev = kAllBooks[idx - 1];
    return (prev.lessonId, prev.originalAudio);
  }

  Future<void> _play() async {
    final service = LessonService();
    final lessonId = await service.restoreCurrentLessonId();

    final prev = _prevBook(lessonId);
    final prevLessonId = prev.$1;
    final audioPath = prev.$2;

    // Load previous book's page timings for book display
    try {
      final jsonString = await DefaultAssetBundle.of(context)
          .loadString('assets/lessons/$prevLessonId.json');
      final jsonMap = json.decode(jsonString) as Map<String, dynamic>;
      final timings = <_RecapPage>[];
      for (final p in jsonMap['pages'] as List) {
        final ms = p['pageStartMs'] as int?;
        if (ms != null) {
          timings.add(_RecapPage(p['imageAsset'] as String, ms));
        }
      }
      // Get cover image (first page) and book title
      final pages = jsonMap['pages'] as List;
      final cover = pages.isNotEmpty ? (pages[0]['imageAsset'] as String? ?? '') : '';
      final bookTitle = jsonMap['bookTitle'] as String? ?? '';

      if (mounted && timings.isNotEmpty) {
        setState(() {
          _pageTimings = timings;
          _coverImage = cover;
          _recapTitle = bookTitle;
        });
      }
    } catch (_) {}

    await _player.play(cdnAudioSource(audioPath));
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

  Widget _buildRecapCover() {
    return Row(
      children: [
        Expanded(
          child: ColoredBox(
            color: const Color(0xFFFFF8F0),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: cdnImage(_coverImage, fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const SizedBox()),
            ),
          ),
        ),
        Expanded(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFFE8D6), Color(0xFFFFCBA4), Color(0xFFFFAD7A)],
              ),
            ),
            child: Stack(
              children: [
                Positioned(top: -30, right: -30,
                  child: Container(width: 120, height: 120,
                    decoration: BoxDecoration(shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.18)))),
                Positioned(bottom: 40, left: -20,
                  child: Container(width: 90, height: 90,
                    decoration: BoxDecoration(shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.13)))),
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [BoxShadow(
                            color: const Color(0xFFFF8C42).withValues(alpha: 0.25),
                            blurRadius: 12, offset: const Offset(0, 4))],
                        ),
                        child: Text('还记得这个故事吗？\n让我们再听一遍~',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: R.s(24), fontWeight: FontWeight.w800,
                            color: const Color(0xFFFF6B35), height: 1.5)),
                      ),
                      const CustomPaint(size: Size(20, 10), painter: _RecapBubbleTailPainter()),
                      const SizedBox(height: 4),
                      cdnImage('assets/pet/eggy_transparent_bg.webp',
                        width: R.s(300), height: R.s(300), fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Icon(Icons.pets, size: R.s(180), color: const Color(0xFFFFAD7A))),
                      const SizedBox(height: 16),
                      Text(_recapTitle,
                        style: TextStyle(fontSize: R.s(42), fontWeight: FontWeight.w900,
                          color: const Color(0xFFB84A00), letterSpacing: 1.5)),
                      const SizedBox(height: 4),
                      const Text("Let's listen again!",
                        style: TextStyle(fontSize: 20, color: Color(0xFFCC6622), fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
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
          // ── Background: cover intro, book pages, or sleepy eggy ──────
          if (_pageTimings.isNotEmpty && _currentPageIdx == 0 && _position.inMilliseconds < _pageTimings[0].startMs && _coverImage.isNotEmpty) ...[
            // Cover intro: left = book cover, right = eggy
            Positioned.fill(child: _buildRecapCover()),
          ] else if (_pageTimings.isNotEmpty) ...[
            Positioned.fill(
              child: Container(
                color: const Color(0xFFFFF8F0),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  child: cdnImage(
                    _pageTimings[_currentPageIdx].imageAsset,
                    key: ValueKey(_currentPageIdx),
                    fit: BoxFit.contain,
                    width: double.infinity,
                    height: double.infinity,
                  ),
                ),
              ),
            ),
          ] else ...[
            cdnImage('assets/pet/cards/spleepy.webp',
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, __, ___) =>
                  Container(color: const Color(0xFF1A2A4A)),
            ),
            Container(color: Colors.black.withValues(alpha: 0.52)),
          ],

          // ── Content ──────────────────────────────────────────────────────
          SafeArea(
            child: Column(
              children: [
                // Top bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.25),
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.arrow_back_ios_rounded,
                              color: Colors.white, size: 20),
                          onPressed: () {
                            _player.stop();
                            Navigator.pop(context);
                          },
                        ),
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
                    width: R.s(80),
                    height: R.s(80),
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
                      size: R.s(46),
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
                          activeTrackColor: const Color(0x59FF8C42),
                          inactiveTrackColor: const Color(0x1AFF8C42),
                          thumbColor: const Color(0x66FF8C42),
                          overlayColor: const Color(0x1AFF8C42),
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

class _RecapBubbleTailPainter extends CustomPainter {
  const _RecapBubbleTailPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, paint);
  }
  @override
  bool shouldRepaint(_RecapBubbleTailPainter _) => false;
}
