import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'eggy_celebration_screen.dart';
import '../models/lesson.dart';
import '../models/book_page.dart';
import '../services/audio_service.dart';
import '../services/lesson_service.dart';
import '../services/progress_service.dart';
import '../services/api_service.dart';
import '../widgets/highlighter_overlay.dart';
import '../utils/cdn_asset.dart';
import '../utils/responsive_utils.dart';

class ReaderScreen extends StatefulWidget {
  final String? lessonId;
  const ReaderScreen({super.key, this.lessonId});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen>
    with TickerProviderStateMixin {
  final LessonService _lessonService = LessonService();
  final AudioService _audioService = AudioService();

  Lesson? _lesson;
  int _currentPage = 0;
  bool _loading = true;

  // Eggy avatar
  int _eggyMonth = 1;
  String? _equippedAccessory;
  bool _isAudioPlaying = false;
  bool _isPaused = false;
  bool _waitingToAdvance = false;
  bool _showSubtitles = false;
  bool _showCelebration = false;
  int _score = 0;
  int _totalStars = 0;
  final Set<int> _triggeredHighlights = {};
  StreamSubscription<Duration>? _positionSub;
  Timer? _autoAdvanceTimer;

  // Pulsing speaker animation
  late final AnimationController _speakerController;
  late final Animation<double> _speakerAnim;

  // Teacher breathing animation
  late final AnimationController _breathController;
  late final Animation<double> _breathAnim;

  // Cover page bubble bounce
  late final AnimationController _bubbleCtrl;
  late final Animation<double>   _bubbleAnim;

  // Score: +1 float animation
  late final AnimationController _plusOneCtrl;

  // Celebration star burst
  late final AnimationController _celebCtrl;
  late final Animation<double> _celebAnim;

  // Video player for animated teacher character
  VideoPlayerController? _videoController;

  @override
  void initState() {
    super.initState();
    ProgressService.getTodayProgress().then((p) {
      if (mounted) setState(() => _totalStars = (p['total_stars'] as int?) ?? 0);
    });
    _speakerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _speakerAnim = Tween<double>(begin: 0.65, end: 1.0).animate(
      CurvedAnimation(parent: _speakerController, curve: Curves.easeInOut),
    );
    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat(reverse: true);
    _breathAnim = Tween<double>(begin: 1.0, end: 1.02).animate(
      CurvedAnimation(parent: _breathController, curve: Curves.easeInOut),
    );
    _bubbleCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat(reverse: true);
    _bubbleAnim = Tween<double>(begin: 0.0, end: -8.0).animate(
        CurvedAnimation(parent: _bubbleCtrl, curve: Curves.easeInOut));

    _plusOneCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 750));
    _celebCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400));
    _celebAnim = CurvedAnimation(parent: _celebCtrl, curve: Curves.easeOut);
    _loadEggy();
    _loadLesson();
  }

  @override
  void dispose() {
    _speakerController.dispose();
    _breathController.dispose();
    _bubbleCtrl.dispose();
    _plusOneCtrl.dispose();
    _celebCtrl.dispose();
    _autoAdvanceTimer?.cancel();
    _positionSub?.cancel();
    _audioService.stop();
    _videoController?.dispose();
    super.dispose();
  }

  /// Initialize video but do NOT play yet — returns ready controller or null.
  Future<VideoPlayerController?> _prepareVideo(String assetPath) async {
    final controller = VideoPlayerController.asset(assetPath);
    await controller.initialize();
    controller.setLooping(true);
    controller.setVolume(0);
    return controller;
  }

  Future<void> _loadEggy() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (!prefs.containsKey('app_start_date')) {
      await prefs.setString('app_start_date', today);
      ApiService().setupProgress(appStartDate: today);
    }
    final startDate = DateTime.tryParse(prefs.getString('app_start_date') ?? today) ?? DateTime.now();
    final eggyMonth = (DateTime.now().difference(startDate).inDays ~/ 30) % 6 + 1;
    if (mounted) {
      setState(() {
        _eggyMonth = eggyMonth;
        _equippedAccessory = prefs.getString('equipped_accessory');
      });
    }
  }

  Future<void> _loadLesson() async {
    final lessonId = widget.lessonId ?? await _lessonService.restoreCurrentLessonId();
    final lesson = await _lessonService.loadLesson(lessonId);
    setState(() {
      _lesson = lesson;
      _loading = false;
    });
    await _startPageAudio();
  }

  Future<void> _startPageAudio() async {
    if (_lesson == null) return;
    _autoAdvanceTimer?.cancel();
    await _audioService.stop();

    // Capture and clear old controller before async work
    final oldCtrl = _videoController;
    _videoController = null;

    final page = _lesson!.pages[_currentPage];
    final hasCN = page.audioCN != null;
    final hasEN = page.audioEN != null;
    final hasAudio = hasCN;
    final videoAsset = page.videoAsset;

    _positionSub?.cancel();
    _positionSub = null;
    setState(() {
      _isAudioPlaying = hasAudio;
      _isPaused = false;
      _waitingToAdvance = false;
      _triggeredHighlights.clear();
    });

    if (!hasAudio) {
      setState(() => _isAudioPlaying = false);
      await oldCtrl?.dispose();
      // No audio — auto-advance after a short pause
      setState(() => _waitingToAdvance = true);
      _scheduleAdvance();
      return;
    }

    // Run video preparation and 1s delay in parallel.
    final videoFuture = videoAsset != null
        ? _prepareVideo(videoAsset)
        : Future<VideoPlayerController?>.value(null);
    final delayFuture = Future<void>.delayed(const Duration(seconds: 1));

    final newCtrl = await videoFuture;
    await delayFuture;
    await oldCtrl?.dispose();

    if (!mounted) {
      newCtrl?.dispose();
      return;
    }

    // Start video and audio simultaneously
    if (newCtrl != null) {
      setState(() => _videoController = newCtrl);
      newCtrl.play();
    }

    void onDone() {
      if (!mounted) return;
      _positionSub?.cancel();
      _positionSub = null;
      setState(() {
        _isAudioPlaying = false;
        _waitingToAdvance = true;
      });
      if (!_isPaused) _scheduleAdvance();
    }

    if (hasEN) {
      // Full sequence: CN then EN
      final ok = await _audioService.playSequence(
        page.audioCN!,
        page.audioEN!,
        onENStart: () {
          if (!mounted) return;
          final highlights = _lesson!.pages[_currentPage].highlights;
          _positionSub?.cancel();
          _positionSub = _audioService.onPositionChanged.listen((pos) {
            final ms = pos.inMilliseconds;
            for (int i = 0; i < highlights.length; i++) {
              if (ms >= highlights[i].positionMs &&
                  !_triggeredHighlights.contains(i)) {
                if (mounted) setState(() => _triggeredHighlights.add(i));
              }
            }
          });
        },
        onComplete: onDone,
      );
      // If playback failed, stop and wait — don't auto-advance
      if (!ok && mounted) {
        setState(() {
          _isAudioPlaying = false;
          _waitingToAdvance = true;
        });
      }
    } else {
      // CN-only page (e.g. intro): play once and finish
      final ok = await _audioService.playAsset(page.audioCN!);
      if (ok) {
        onDone();
      } else if (mounted) {
        // Audio failed — stay on page, let user tap replay or next
        setState(() {
          _isAudioPlaying = false;
          _waitingToAdvance = true;
        });
      }
    }
  }

  /// Schedule auto-advance 1.5 s after audio finishes.
  void _scheduleAdvance() {
    _autoAdvanceTimer?.cancel();
    _autoAdvanceTimer = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted || _isPaused) return;
      // Award 1 point for completing this page
      setState(() {
        _score++;
        _waitingToAdvance = false;
      });
      _plusOneCtrl.forward(from: 0);
      if (_lesson != null && _currentPage < _lesson!.pages.length - 1) {
        Future.delayed(const Duration(milliseconds: 500), _nextPage);
      } else {
        // Last page — navigate to Eggy celebration screen
        Future.delayed(const Duration(milliseconds: 600), () {
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => const EggyCelebrationScreen(
                nextRoute:    '/quiz',
                nextLabel:    '开始闯关  🎯 →',
                moduleKey:    'reader',
                modulePoints: 20,
              ),
            ),
          );
        });
      }
    });
  }

  void _togglePause() {
    if (_isPaused) {
      // Resume
      setState(() => _isPaused = false);
      if (_waitingToAdvance) {
        _scheduleAdvance();
      } else {
        _audioService.resume();
        _videoController?.play();
      }
    } else {
      // Pause
      setState(() => _isPaused = true);
      _autoAdvanceTimer?.cancel();
      _audioService.pause();
      _videoController?.pause();
    }
  }

  void _prevPage() {
    if (_lesson == null || _currentPage == 0) return;
    setState(() => _currentPage--);
    _startPageAudio();
  }

  void _nextPage() {
    if (_lesson == null) return;
    if (_currentPage < _lesson!.pages.length - 1) {
      setState(() => _currentPage++);
      _startPageAudio();
    }
  }

  // ── Eggy avatar widget (base + accessory) ─────────────────────────────────
  Widget _buildEggyAvatar(double size) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          cdnImage('assets/pet/costumes/base/egg_month$_eggyMonth.png',
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const SizedBox(),
          ),
          if (_equippedAccessory != null)
            cdnImage('assets/pet/costumes/accessories/$_equippedAccessory.png',
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const SizedBox(),
            ),
        ],
      ),
    );
  }

  Widget _buildPageImage(String imageAsset, int pageIndex,
      {List<KeywordHighlight> highlights = const [],
       Set<int> triggeredIndices = const {}}) {
    // Cover page: book on left, Eggy + warm gradient on right
    if (pageIndex == 0) {
      return Row(
        children: [
          // ── Left: book cover ──────────────────────────────────────────────
          Expanded(
            child: ColoredBox(
              color: const Color(0xFFFFF8F0),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: cdnImage(imageAsset, fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const SizedBox()),
              ),
            ),
          ),

          // ── Right: warm gradient + Eggy + bubble ─────────────────────────
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
                  // Decorative circles background
                  Positioned(top: -30, right: -30,
                    child: Container(width: R.s(120), height: R.s(120),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.18)))),
                  Positioned(bottom: 40, left: -20,
                    child: Container(width: R.s(90), height: R.s(90),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.13)))),
                  Positioned(top: 60, left: 30,
                    child: Container(width: R.s(50), height: R.s(50),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.10)))),

                  // Main content: bubble + Eggy + title
                  Positioned.fill(
                   child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Speech bubble (bounces up/down)
                      AnimatedBuilder(
                        animation: _bubbleAnim,
                        builder: (_, child) => Transform.translate(
                          offset: Offset(0, _bubbleAnim.value),
                          child: child,
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFFF8C42).withValues(alpha: 0.25),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Text(
                            '谢谢你来看我，\n陪我一起听故事~',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: R.s(24),
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFFF6B35),
                              height: 1.5,
                            ),
                          ),
                        ),
                      ),
                      // Bubble tail
                      CustomPaint(
                        size: const Size(20, 10),
                        painter: _BubbleTailPainter(),
                      ),
                      const SizedBox(height: 4),

                      // Eggy with breathing
                      Flexible(
                        child: ScaleTransition(
                          scale: _breathAnim,
                          alignment: Alignment.center,
                          child: _buildEggyAvatar(R.s(280)),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Book title
                      Text(
                        'Biscuit',
                        style: TextStyle(
                          fontSize: R.s(36),
                          fontWeight: FontWeight.w900,
                          color: Color(0xFFB84A00),
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Let\'s read together! ✨',
                        style: TextStyle(
                          fontSize: 18,
                          color: Color(0xFFCC6622),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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

    const imgAR = 2480.0 / 1754.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final double imgW, imgH;
        if (constraints.maxWidth / constraints.maxHeight > imgAR) {
          imgH = constraints.maxHeight;
          imgW = imgH * imgAR;
        } else {
          imgW = constraints.maxWidth;
          imgH = imgW / imgAR;
        }
        final left = (constraints.maxWidth  - imgW) / 2;
        final top  = (constraints.maxHeight - imgH) / 2;

        return Stack(
          children: [
            Positioned.fill(
              child: const ColoredBox(color: Color(0xFFFFF8F0)),
            ),
            Positioned(
              left: left, top: top, width: imgW, height: imgH,
              child: cdnImage(imageAsset,
                fit: BoxFit.fill,
                errorBuilder: (_, __, ___) => Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.menu_book, size: 64, color: Color(0xFFFF8C42)),
                      const SizedBox(height: 16),
                      Text('Page ${pageIndex + 1}',
                          style: const TextStyle(fontSize: 28,
                              color: Color(0xFFFF8C42),
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ),
            if (highlights.isNotEmpty)
              Positioned(
                left: left, top: top, width: imgW, height: imgH,
                child: HighlighterOverlay(
                  highlights: highlights,
                  triggeredIndices: triggeredIndices,
                ),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFFFFF8F0),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final lesson = _lesson!;
    final page = lesson.pages[_currentPage];
    final totalPages = lesson.pages.length;

    return Scaffold(
      backgroundColor: Colors.black,
      // Pause / play FAB — bottom-left so it doesn't overlap the teacher
      floatingActionButton: FloatingActionButton(
        onPressed: _togglePause,
        backgroundColor:
            _isPaused ? const Color(0xFFFF8C42) : Colors.black54,
        elevation: 4,
        child: Icon(
          _isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
          color: Colors.white,
          size: 32,
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar: progress + CC + 🔁 replay
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Column(
                    children: [
                      // Stage dots
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(5, (i) {
                          final colors = [
                            Colors.red,
                            Colors.orange,
                            Colors.yellow,
                            Colors.green,
                            Colors.blue,
                          ];
                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: i <= _currentPage
                                  ? colors[i % colors.length]
                                  : colors[i % colors.length]
                                      .withValues(alpha: 0.3),
                              shape: BoxShape.circle,
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 4),
                      // Page counter
                      Text(
                        'Page ${_currentPage + 1} / $totalPages',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white54,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Progress bar — subtle transparent style
                      LinearProgressIndicator(
                        value: (_currentPage + 1) / totalPages,
                        backgroundColor: Colors.transparent,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                            Colors.transparent),
                        minHeight: 2,
                      ),
                    ],
                  ),
                  // Left-side: back button
                  Positioned(
                    left: 0,
                    top: 0,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back_ios_rounded,
                          color: Colors.white70, size: 22),
                      padding: EdgeInsets.zero,
                      onPressed: () { if (Navigator.canPop(context)) { Navigator.pop(context); } else { Navigator.pushReplacementNamed(context, '/study'); } },
                    ),
                  ),
                  // Right-side buttons: score + CC + 🔁
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Row(
                      children: [
                        // Score chip
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF8C42),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('⭐',
                                  style: TextStyle(fontSize: 13)),
                              const SizedBox(width: 4),
                              Text('$_totalStars',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  )),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // CC subtitle toggle
                        GestureDetector(
                          onTap: () =>
                              setState(() => _showSubtitles = !_showSubtitles),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(
                              color: _showSubtitles
                                  ? Colors.white.withValues(alpha: 0.85)
                                  : Colors.white.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'CC',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: _showSubtitles
                                    ? Colors.black87
                                    : Colors.white54,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // 🔁 Replay button — restarts current page
                        GestureDetector(
                          onTap: _isAudioPlaying && !_isPaused
                              ? null
                              : _startPageAudio,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: (_isAudioPlaying && !_isPaused)
                                  ? Colors.white12
                                  : const Color(0xFFFFD93D),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text('🔁',
                                style: TextStyle(fontSize: 18)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Main book image area with page turn animation
            Expanded(
              child: Stack(
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 500),
                    transitionBuilder: (child, animation) {
                      return FadeTransition(opacity: animation, child: child);
                    },
                    child: SizedBox.expand(
                      key: ValueKey<int>(_currentPage),
                      child: _buildPageImage(
                        page.imageAsset,
                        _currentPage,
                        highlights: page.highlights,
                        triggeredIndices: Set.unmodifiable(_triggeredHighlights),
                      ),
                    ),
                  ),
                  // Eggy avatar — bottom-right (hidden on cover page, shown there via split layout)
                  if (_currentPage != 0)
                    Positioned(
                      bottom: 8,
                      right: 12,
                      child: ScaleTransition(
                        scale: _breathAnim,
                        alignment: Alignment.bottomCenter,
                        child: _buildEggyAvatar(R.s(140)),
                      ),
                    ),
                  // 🔊 Pulsing speaker icon while audio plays
                  if (_isAudioPlaying && !_isPaused)
                    Positioned(
                      bottom: 16,
                      left: 72, // offset right of the FAB
                      child: ScaleTransition(
                        scale: _speakerAnim,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: const Text('🔊',
                              style: TextStyle(fontSize: 28)),
                        ),
                      ),
                    ),
                  // +1 float animation
                  AnimatedBuilder(
                    animation: _plusOneCtrl,
                    builder: (_, __) {
                      final p = _plusOneCtrl.value;
                      if (p == 0.0 || p == 1.0) return const SizedBox.shrink();
                      final opacity = sin(p * pi).clamp(0.0, 1.0);
                      return Positioned(
                        top: 60 - p * 50,
                        right: 16,
                        child: Opacity(
                          opacity: opacity,
                          child: const Text('+1',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFFF8C42),
                                shadows: [
                                  Shadow(
                                      color: Colors.black38,
                                      blurRadius: 4,
                                      offset: Offset(0, 2)),
                                ],
                              )),
                        ),
                      );
                    },
                  ),

                  // ← Previous page
                  if (_currentPage > 0)
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: GestureDetector(
                        onTap: _prevPage,
                        child: Container(
                          width: 48,
                          color: Colors.transparent,
                          alignment: Alignment.center,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black45,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: const Icon(Icons.chevron_left_rounded,
                                color: Colors.white, size: 28),
                          ),
                        ),
                      ),
                    ),

                  // → Next page
                  if (_lesson != null &&
                      _currentPage < _lesson!.pages.length - 1)
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      child: GestureDetector(
                        onTap: _nextPage,
                        child: Container(
                          width: 48,
                          color: Colors.transparent,
                          alignment: Alignment.center,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black45,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: const Icon(Icons.chevron_right_rounded,
                                color: Colors.white, size: 28),
                          ),
                        ),
                      ),
                    ),

                  // ⏸ Paused indicator
                  if (_isPaused)
                    Positioned(
                      bottom: 16,
                      left: 72,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: const Text(
                          '⏸ Paused',
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.white70,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Subtitle panel — toggled by CC button
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              child: _showSubtitles
                  ? Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.92),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 8,
                            offset: const Offset(0, -2),
                          ),
                        ],
                      ),
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            page.narrativeCN,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 16,
                              color: Color(0xFF333333),
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            page.narrativeEN,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFFFF8C42),
                              fontStyle: FontStyle.italic,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

}

// ── Bubble tail painter ──────────────────────────────────────────────────────
class _BubbleTailPainter extends CustomPainter {
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
  bool shouldRepaint(_BubbleTailPainter _) => false;
}

