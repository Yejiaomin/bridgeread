import 'dart:async';
import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show DefaultAssetBundle;
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/progress_service.dart';
import '../services/api_service.dart';
import '../services/lesson_service.dart';
import '../services/week_service.dart';
import '../utils/cdn_asset.dart';
import '../utils/media_session.dart';
import '../utils/responsive_utils.dart';
import '../utils/web_audio_player.dart';

// ── Playlist ──────────────────────────────────────────────────────────────────

class _Track {
  final String label, path;
  final bool showBook;
  final String? lessonId;
  final String? coverImage; // cover image for intro page
  const _Track(this.label, this.path, {this.showBook = false, this.lessonId, this.coverImage});
}

class _PageTiming {
  final String imageAsset;
  final int startMs;
  const _PageTiming(this.imageAsset, this.startMs);
}

// Default fallback
const _kDefaultTracks = [
  _Track('Biscuit - Original Narration', 'audio/biscuit_original.mp3'),
];

// ── Screen ────────────────────────────────────────────────────────────────────

class ListenScreen extends StatefulWidget {
  final bool bedtimeMode;
  const ListenScreen({super.key, this.bedtimeMode = false});
  @override
  State<ListenScreen> createState() => _ListenScreenState();
}

class _ListenScreenState extends State<ListenScreen>
    with TickerProviderStateMixin {
  // Web: persistent HTML5 Audio for iOS autoplay compat
  // Mobile: standard audioplayers
  final WebAudioPlayer? _webPlayer = kIsWeb ? WebAudioPlayer() : null;
  final AudioPlayer? _nativePlayer = kIsWeb ? null : AudioPlayer();
  final WebSfxPlayer? _webSfx = kIsWeb ? WebSfxPlayer() : null;
  final AudioPlayer? _nativeSfx = kIsWeb ? null : AudioPlayer();

  static const _eggyImages = [
    'assets/pet/cards/1egg.webp',
    'assets/pet/cards/2hatching.webp',
    'assets/pet/cards/4Handstand.webp',
    'assets/pet/cards/5Lying face down.webp',
    'assets/pet/cards/6Lying down.webp',
    'assets/pet/cards/7Single-leg stance.webp',
    'assets/pet/cards/8study.webp',
    'assets/pet/cards/9wearing hat.webp',
    'assets/pet/cards/10bicycle.webp',
  ];

  // Playlist
  List<_Track> _tracks = _kDefaultTracks;

  // Audio state
  bool _playing = false;
  int  _trackIdx = 0;

  final List<StreamSubscription> _subs = [];

  // Listening time counter (seconds today)
  int _listenSeconds = 0;
  Timer? _petTimer;

  // Bedtime mode: auto-close after 20 minutes
  Timer? _bedtimeTimer;
  int _bedtimeRemaining = 20 * 60; // seconds

  // Eggy display (matches study room)
  int _eggyMonth = 1;
  String? _equippedAccessory;
  bool _showEggyBg = true; // toggle: true = eggy background (default), false = book pages

  // Book page display — timings per lesson
  final Map<String, List<_PageTiming>> _allPageTimings = {};
  List<_PageTiming> _pageTimings = [];
  int _currentPageIdx = 0;

  // Progress
  Duration _position = Duration.zero;
  Duration _duration  = Duration.zero;

  // Waveform: 5 bars with different speeds
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
        Tween<double>(begin: 6, end: 48).animate(
            CurvedAnimation(parent: c, curve: Curves.easeInOut))).toList();

    if (_webPlayer != null) {
      _subs.addAll([
        _webPlayer!.onComplete.listen((_) => _nextTrack()),
        _webPlayer!.onPositionChanged.listen((p) {
          if (mounted) {
            setState(() {
              _position = p;
              // Also update duration from JS (no separate onDurationChanged on web)
              final durMs = _webPlayer!.durationMs;
              if (durMs > 0) _duration = Duration(milliseconds: durMs);
            });
            _updatePageForPosition(p);
          }
        }),
      ]);
    } else {
      _subs.addAll([
        _nativePlayer!.onPlayerComplete.handleError((_) {}).listen((_) => _nextTrack()),
        _nativePlayer!.onPositionChanged.handleError((_) {}).listen((p) {
          if (mounted) {
            setState(() => _position = p);
            _updatePageForPosition(p);
          }
        }),
        _nativePlayer!.onDurationChanged.handleError((_) {}).listen((d) {
          if (mounted) setState(() => _duration = d);
        }),
      ]);
    }

    _loadPrefs();
    _loadListenTime();
    _loadEggy();
    _startTimers();

    // Keep screen on during listening
    WakelockPlus.enable();

    // Bedtime mode: start 20-minute countdown
    if (widget.bedtimeMode) {
      _bedtimeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _bedtimeRemaining--);
        if (_bedtimeRemaining <= 0) {
          _bedtimeTimer?.cancel();
          if (_webPlayer != null) { _webPlayer!.stop(); } else { _nativePlayer?.stop(); }
          WakelockPlus.disable();
          // Exit app or go back to home
          if (mounted) {
            Navigator.of(context).popUntil((route) => route.isFirst);
          }
        }
      });
    }

    // Wait for data to load before starting playback
    _loadListenData().then((_) {
      if (mounted) _playTrack(0);
    });
  }

  Future<void> _loadListenData() async {
    final service = LessonService();
    final lessonId = await service.restoreCurrentLessonId();
    final lesson = await service.loadLesson(lessonId);

    if (lesson.originalAudio.isEmpty) return;

    final playlist = <_Track>[];

    // Helper to get cover image from lesson JSON
    Future<String?> getCover(String lid) async {
      try {
        final js = await DefaultAssetBundle.of(context).loadString('assets/lessons/$lid.json');
        final map = json.decode(js) as Map<String, dynamic>;
        final pages = map['pages'] as List;
        if (pages.isNotEmpty) return pages[0]['imageAsset'] as String?;
      } catch (_) {}
      return null;
    }

    final now = activeDate();
    final isWeekend = now.weekday == 6 || now.weekday == 7;

    if (isWeekend) {
      // Weekend: play all books studied this week in order, loop
      final weekBooks = await WeekService.thisWeekBooks();
      if (weekBooks.isNotEmpty) {
        for (int i = 0; i < weekBooks.length; i++) {
          final book = weekBooks[i];
          final cover = await getCover(book.lessonId);
          playlist.add(_Track('${book.title} (${i + 1}/${weekBooks.length})',
              book.originalAudio, showBook: true, lessonId: book.lessonId, coverImage: cover));
        }
      } else {
        // Fallback: play current lesson (testing or no scheduled books)
        final todayCover = await getCover(lessonId);
        playlist.add(_Track(lesson.bookTitle, lesson.originalAudio,
            showBook: true, lessonId: lessonId, coverImage: todayCover));
      }
    } else {
      // Weekday: today → yesterday → today, then loop
      final todayTitle = lesson.bookTitle;
      final todayAudio = lesson.originalAudio;
      final todayCover = await getCover(lessonId);

      // Find previous book in global order
      final allIdx = kAllBooks.indexWhere((b) => b.lessonId == lessonId);

      if (allIdx <= 0) {
        // First book ever: play twice then loop
        playlist.add(_Track('$todayTitle (1/2)', todayAudio, showBook: true, lessonId: lessonId, coverImage: todayCover));
        playlist.add(_Track('$todayTitle (2/2)', todayAudio, showBook: true, lessonId: lessonId, coverImage: todayCover));
      } else {
        final prev = kAllBooks[allIdx - 1];
        final prevCover = await getCover(prev.lessonId);

        playlist.add(_Track(todayTitle, todayAudio, showBook: true, lessonId: lessonId, coverImage: todayCover));
        playlist.add(_Track('${prev.title} - 复习', prev.originalAudio, showBook: true, lessonId: prev.lessonId, coverImage: prevCover));
        playlist.add(_Track('$todayTitle - 巩固', todayAudio, showBook: true, lessonId: lessonId, coverImage: todayCover));
      }
    }

    // Load page timings for all needed lessons
    final lessonIds = playlist.map((t) => t.lessonId).where((id) => id != null).toSet();
    for (final lid in lessonIds) {
      if (_allPageTimings.containsKey(lid)) continue;
      try {
        final jsonString = await DefaultAssetBundle.of(context)
            .loadString('assets/lessons/$lid.json');
        final jsonMap = json.decode(jsonString) as Map<String, dynamic>;
        final timings = <_PageTiming>[];
        for (final p in jsonMap['pages'] as List) {
          final ms = p['pageStartMs'] as int?;
          if (ms != null) {
            timings.add(_PageTiming(p['imageAsset'] as String, ms));
          }
        }
        _allPageTimings[lid!] = timings;
      } catch (_) {}
    }

    // Weekday 3-track playlist: loop from track 1 (skip initial "today")
    // Weekend / 2-track / 1-track: loop from start
    _loopStart = (!isWeekend && playlist.length == 3) ? 1 : 0;

    if (mounted) {
      setState(() {
        _tracks = playlist;
        _bookTitle = lesson.bookTitle;
        // Set initial page timings for first track
        final firstLessonId = playlist.isNotEmpty ? playlist[0].lessonId : null;
        _pageTimings = firstLessonId != null ? (_allPageTimings[firstLessonId] ?? []) : [];
      });
    }
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    clearMediaSession();
    for (final s in _subs) s.cancel();
    _webPlayer?.dispose();
    _nativePlayer?.dispose();
    _nativeSfx?.dispose();
    for (final c in _waveCtrl) c.dispose();
    _petTimer?.cancel();
    _bedtimeTimer?.cancel();
    super.dispose();
  }

  // ── Listening time ───────────────────────────────────────────────────────────

  Future<void> _loadEggy() async {
    final prefs = await SharedPreferences.getInstance();
    // Eggy month: same calculation as study room
    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (!prefs.containsKey('app_start_date')) {
      await prefs.setString('app_start_date', today);
      ApiService().setupProgress(appStartDate: today);
    }
    final startStr  = prefs.getString('app_start_date') ?? today;
    final startDate = DateTime.tryParse(startStr) ?? DateTime.now();
    final eggyMonth = (DateTime.now().difference(startDate).inDays ~/ 30) % 6 + 1;
    final accessory = prefs.getString('equipped_accessory');
    if (mounted) {
      setState(() {
        _eggyMonth = eggyMonth;
        _equippedAccessory = accessory;
      });
    }
  }

  Future<void> _loadListenTime() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _dateStr(DateTime.now());
    if ((prefs.getString('listen_date') ?? '') == today) {
      if (mounted) setState(() => _listenSeconds = prefs.getInt('listen_seconds') ?? 0);
    }
  }

  Future<void> _saveListenTime() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _dateStr(DateTime.now());
    await prefs.setString('listen_date', today);
    await prefs.setInt('listen_seconds', _listenSeconds);
    // Sync to server (fire-and-forget)
    ApiService().syncProgress(
      date: today,
      module: 'listen',
      done: _allTracksCompleted,
      stars: 0,
      listenSeconds: _listenSeconds,
    );
  }

  String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

  // ── Pet + timer ──────────────────────────────────────────────────────────────

  void _startTimers() {
    _petTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_playing) _listenSeconds++;
      if (_listenSeconds % 10 == 0 && _playing) _saveListenTime();
      setState(() {}); // refresh timer display
    });
  }

  // ── Playback ─────────────────────────────────────────────────────────────────

  Future<void> _playTrack(int idx) async {
    final i = idx % _tracks.length;
    final track = _tracks[i];
    // Switch page timings for this track's lesson
    final timings = track.lessonId != null ? (_allPageTimings[track.lessonId] ?? []) : <_PageTiming>[];
    setState(() {
      _trackIdx = i;
      _pageTimings = timings;
      _currentPageIdx = 0;
    });
    // Play page-flip sound when switching between different books
    if (idx > 0) {
      try {
        if (_webSfx != null) {
          _webSfx!.play('audio/sfx/book-open.wav');
        } else {
          await _nativeSfx!.play(cdnAudioSource('audio/sfx/book-open.wav'));
        }
        await Future.delayed(const Duration(milliseconds: 600));
      } catch (_) {}
    }

    if (_webPlayer != null) {
      // Strip 'audio/' prefix not needed — track.path already has it
      _webPlayer!.play(track.path);
    } else {
      await _nativePlayer!.play(cdnAudioSource(track.path));
    }
    _setPlaying(true);

    // Media Session API: enable lock screen controls & background audio
    setMediaSession(
      title: '${track.label} - ${track.lessonId ?? ""}',
      onPlay: () => _togglePlay(),
      onPause: () => _togglePlay(),
      onNextTrack: () => _nextTrack(),
      onPreviousTrack: () {
        if (mounted) _playTrack((_trackIdx - 1 + _tracks.length) % _tracks.length);
      },
    );
  }

  void _setPlaying(bool v) {
    setState(() => _playing = v);
    if (v) {
      for (final c in _waveCtrl) c.repeat(reverse: true);
    } else {
      for (final c in _waveCtrl) { c.stop(); c.value = 0; }
    }
  }

  Future<void> _togglePlay() async {
    if (_playing) {
      _webPlayer?.pause();
      await _nativePlayer?.pause();
      _setPlaying(false);
    } else {
      _webPlayer?.resume();
      await _nativePlayer?.resume();
      _setPlaying(true);
    }
  }

  bool _allTracksCompleted = false;
  int _loopStart = 0; // where to loop back to after completion

  void _nextTrack() {
    if (_trackIdx + 1 >= _tracks.length) {
      // All tracks played once — mark done, show completion, start loop
      if (!_allTracksCompleted) {
        _allTracksCompleted = true;
        ProgressService.markModuleComplete('listen', 20);
        _saveListenTime();
      }
      setState(() {});
      // Loop: weekday = skip first track (yesterday+today only), weekend = all
      _playTrack(_loopStart);
    } else {
      _playTrack(_trackIdx + 1);
    }
  }

  List<Widget> _buildBookListColumns() {
    final total = _getAvailableBookCount();
    final hasRight = total > 10;
    final leftCount = hasRight ? 10 : total;
    final rightCount = hasRight ? total - 10 : 0;

    Widget buildColumn(int startIdx, int count, {bool isLeft = true}) {
      return Positioned(
        left: isLeft ? R.s(8) : null,
        right: isLeft ? null : R.s(8),
        top: R.s(40),
        bottom: R.s(40),
        width: R.s(160),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isLeft)
              Text('📚 选择听力', style: TextStyle(
                fontSize: R.s(13), fontWeight: FontWeight.w800,
                color: const Color(0xFFFF8C42))),
            if (isLeft) SizedBox(height: R.s(6)),
            Expanded(
              child: ListView.builder(
                itemCount: count,
                itemBuilder: (_, i) {
                  final idx = startIdx + i;
                  if (idx >= kAllBooks.length) return const SizedBox();
                  final book = kAllBooks[idx];
                  final isPlaying = _tracks.isNotEmpty &&
                      _trackIdx < _tracks.length &&
                      _tracks[_trackIdx].lessonId == book.lessonId;
                  return GestureDetector(
                    onTap: () => _playBookFromList(book),
                    child: Container(
                      margin: EdgeInsets.only(bottom: R.s(4)),
                      padding: EdgeInsets.symmetric(
                        horizontal: R.s(8), vertical: R.s(6)),
                      decoration: BoxDecoration(
                        color: isPlaying
                            ? const Color(0xFFFF8C42).withValues(alpha: 0.2)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(R.s(8)),
                      ),
                      child: Row(
                        children: [
                          Text('${idx + 1}', style: TextStyle(
                            fontSize: R.s(11), fontWeight: FontWeight.w800,
                            color: const Color(0xFFFF8C42))),
                          SizedBox(width: R.s(6)),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(book.title, style: TextStyle(
                                  fontSize: R.s(12), fontWeight: FontWeight.w700,
                                  color: isPlaying ? const Color(0xFFFF8C42) : const Color(0xFF333333)),
                                  overflow: TextOverflow.ellipsis),
                                Text(book.titleCN, style: TextStyle(
                                  fontSize: R.s(11), fontWeight: FontWeight.w500,
                                  color: isPlaying ? const Color(0xFFFF8C42) : Colors.grey)),
                              ],
                            ),
                          ),
                          if (isPlaying)
                            Icon(Icons.volume_up_rounded,
                              size: R.s(14), color: const Color(0xFFFF8C42)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );
    }

    final columns = <Widget>[buildColumn(0, leftCount, isLeft: true)];
    if (hasRight) {
      columns.add(buildColumn(10, rightCount, isLeft: false));
    }
    return columns;
  }

  int _getAvailableBookCount() {
    // Books from day 1 to active date (today or calendar-selected date)
    final startStr = _prefs?.getString('book_start_date');
    if (startStr == null) return 1;
    final startDate = WeekService.parseDate(startStr);
    if (startDate == null) return 1;
    final current = activeDate();
    // Count weekdays from start to current date
    int count = 0;
    var d = startDate;
    while (!d.isAfter(current) && count < kAllBooks.length) {
      if (d.weekday >= 1 && d.weekday <= 5) count++;
      d = d.add(const Duration(days: 1));
    }
    return count.clamp(1, kAllBooks.length);
  }

  SharedPreferences? _prefs;

  Future<void> _loadPrefs() async {
    _prefs = await SharedPreferences.getInstance();
  }

  void _playBookFromList(BookInfo book) async {
    // Switch to this book's audio
    setState(() {
      _allTracksCompleted = false;
      _tracks = [_Track(book.title, book.originalAudio,
          showBook: true, lessonId: book.lessonId)];
      _trackIdx = 0;
    });
    // Load page timings
    if (!_allPageTimings.containsKey(book.lessonId)) {
      try {
        final jsonString = await DefaultAssetBundle.of(context)
            .loadString('assets/lessons/${book.lessonId}.json');
        final jsonMap = json.decode(jsonString) as Map<String, dynamic>;
        final timings = <_PageTiming>[];
        for (final p in jsonMap['pages'] as List) {
          final ms = p['pageStartMs'] as int?;
          if (ms != null) timings.add(_PageTiming(p['imageAsset'] as String, ms));
        }
        _allPageTimings[book.lessonId] = timings;
      } catch (_) {}
    }
    _pageTimings = _allPageTimings[book.lessonId] ?? [];
    _playTrack(0);
  }

  Future<void> _onListenComplete() async {
    if (_webPlayer != null) { _webPlayer!.stop(); } else { await _nativePlayer?.stop(); }
    _setPlaying(false);
    await _saveListenTime();
    if (!_allTracksCompleted) {
      await ProgressService.markModuleComplete('listen', 20);
    }
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/ranking', (route) => false);
    }
  }

  void _prevTrack() =>
      _playTrack((_trackIdx - 1 + _tracks.length) % _tracks.length);

  // ── Page tracking ────────────────────────────────────────────────────────────

  void _updatePageForPosition(Duration pos) {
    if (_tracks.isEmpty || !_tracks[_trackIdx].showBook || _pageTimings.isEmpty) return;
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

  bool get _isBookMode =>
      _tracks.isNotEmpty && _trackIdx < _tracks.length && _tracks[_trackIdx].showBook && _pageTimings.isNotEmpty;

  // Book title for cover display
  String _bookTitle = 'Biscuit';

  Widget _buildListenCover() {
    // Use the current track's cover image
    final track = _tracks.isNotEmpty && _trackIdx < _tracks.length ? _tracks[_trackIdx] : null;
    final coverImage = track?.coverImage ?? 'assets/books/01Biscuit/cover.webp';
    final title = track?.label.split(' - ').first.split(' (').first ?? _bookTitle;

    return Row(
      children: [
        // ── Left: book cover ──────────────────────────────────────────
        Expanded(
          child: ColoredBox(
            color: const Color(0xFFFFF8F0),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: cdnImage(coverImage, fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const SizedBox()),
            ),
          ),
        ),
        // ── Right: warm gradient + Eggy + bubble ─────────────────────
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
                // Decorative circles
                Positioned(top: -30, right: -30,
                  child: Container(width: 120, height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.18)))),
                Positioned(bottom: 40, left: -20,
                  child: Container(width: 90, height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.13)))),

                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Speech bubble
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
                          'Almost there!\n马上就要通关啦~',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: R.s(24),
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFFF6B35),
                            height: 1.5,
                          ),
                        ),
                      ),
                      // Bubble tail
                      CustomPaint(
                        size: const Size(20, 10),
                        painter: _BubbleTailPainter(),
                      ),
                      const SizedBox(height: 4),

                      // Eggy
                      cdnImage(
                        'assets/pet/eggy_transparent_bg.webp',
                        width: R.s(300),
                        height: R.s(300),
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.pets, size: R.s(180), color: const Color(0xFFFFAD7A)),
                      ),
                      const SizedBox(height: 16),

                      // Book title
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: R.s(42),
                          fontWeight: FontWeight.w900,
                          color: Color(0xFFB84A00),
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        "Let's listen together!",
                        style: TextStyle(
                          fontSize: 20,
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

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Background: book pages or eggy (toggled by user) ─────────
          if (!_showEggyBg && _isBookMode && _currentPageIdx == 0 && _position.inMilliseconds < (_pageTimings.isNotEmpty ? _pageTimings[0].startMs : 0)) ...[
            // Cover intro: left = book cover, right = eggy + bubble
            Positioned.fill(
              child: _buildListenCover(),
            ),
          ] else if (!_showEggyBg && _isBookMode) ...[
            // Book mode: show current page spread
            Positioned.fill(
              child: Container(
                color: const Color(0xFFFFF8F0),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  child: cdnImage(
                    _pageTimings[_currentPageIdx].imageAsset,
                    key: ValueKey(_currentPageIdx),
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                  ),
                ),
              ),
            ),
          ] else ...[
            // Eggy mode: warm gradient + cycling eggy images
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFFFE8D6), Color(0xFFFFCBA4), Color(0xFFFFAD7A)],
                ),
              ),
            ),
            Positioned.fill(
              child: Stack(
                  alignment: Alignment.center,
                  children: [
                    cdnImage(_eggyImages[_trackIdx % _eggyImages.length],
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      errorBuilder: (_, __, ___) => cdnImage('assets/pet/eggy_transparent_bg.webp',
                        fit: BoxFit.contain),
                    ),
                  ],
              ),
            ),
            Container(color: Colors.black.withValues(alpha: 0.55)),
          ],

          // ── "All done" overlay ──────────────────────────────────────────────
          if (_allTracksCompleted) ...[
            // Center: return button (semi-transparent)
            Positioned.fill(
              child: GestureDetector(
                onTap: _onListenComplete,
                child: Container(
                  color: Colors.black.withValues(alpha: 0.05),
                  child: Center(
                    child: Container(
                      width: R.s(260),
                      height: R.s(260),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFFFF5EB).withValues(alpha: 0.6),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFF8C42).withValues(alpha: 0.15),
                            blurRadius: 30, spreadRadius: 3,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('全部完成啦！',
                            style: TextStyle(color: Color(0xFFFF8C42), fontSize: 18, fontWeight: FontWeight.w900)),
                          cdnImage('assets/pet/eggy_transparent_bg.webp',
                            width: R.s(140), height: R.s(140), fit: BoxFit.contain),
                          const Text('点击返回',
                            style: TextStyle(color: Color(0xFFFFAA66), fontSize: 13, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Book list columns (left, or left+right if >10) — hide on mobile
            if (!R.isMobile) ..._buildBookListColumns(),
          ],

          // ── Top bar + waveform + controls ────────────────────────────────────
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(context),
                const Expanded(child: SizedBox()),
                _buildWaveform(),
                const SizedBox(height: 8),
                _buildProgressBar(),
                const SizedBox(height: 8),
                _buildControls(),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final displaySeconds = widget.bedtimeMode ? _bedtimeRemaining : _listenSeconds;
    final m = (displaySeconds ~/ 60).toString().padLeft(2, '0');
    final s = (displaySeconds % 60).toString().padLeft(2, '0');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded,
                color: Colors.white70, size: 22),
            onPressed: () {
              _saveListenTime();
              if (_webPlayer != null) { _webPlayer!.stop(); } else { _nativePlayer?.stop(); }
              if (Navigator.canPop(context)) {
                Navigator.pop(context);
              } else {
                Navigator.pushReplacementNamed(context, '/study');
              }
            },
          ),
          Expanded(
            child: Text(widget.bedtimeMode ? '🌙 睡前陪伴' : '磨耳朵  👂',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800)),
          ),
          // Today's listening time
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.headphones_rounded,
                  color: Colors.white70, size: 16),
              const SizedBox(width: 6),
              Text('$m:$s',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
            ]),
          ),
          const SizedBox(width: 8),
          // Toggle: book pages vs eggy background
          GestureDetector(
            onTap: () => setState(() => _showEggyBg = !_showEggyBg),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _showEggyBg ? '📖' : '🥚',
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Done button — shows Eggy celebration
          GestureDetector(
            onTap: () async {
              await _saveListenTime();
              if (_webPlayer != null) { _webPlayer!.stop(); } else { _nativePlayer?.stop(); }
              await ProgressService.markModuleComplete('listen', 20);
              if (mounted) {
                Navigator.pushNamedAndRemoveUntil(
                    context, '/home', (route) => false);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFF8C42),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                '完成',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Widget _buildProgressBar() {
    final progress = _duration.inMilliseconds > 0
        ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: const Color(0x59FF8C42),
              inactiveTrackColor: const Color(0x1AFF8C42),
              thumbColor: const Color(0x66FF8C42),
              overlayColor: const Color(0x1AFF8C42),
            ),
            child: Slider(
              value: progress,
              onChanged: (v) {
                if (_duration.inMilliseconds > 0) {
                  final pos = Duration(milliseconds: (v * _duration.inMilliseconds).toInt());
                  if (_webPlayer != null) {
                    _webPlayer!.seek(pos);
                  } else {
                    _nativePlayer!.seek(pos);
                  }
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
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
                Text(_fmt(_duration),
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          iconSize: 44,
          icon: const Icon(Icons.skip_previous_rounded, color: Colors.white70),
          onPressed: _prevTrack,
        ),
        const SizedBox(width: 12),
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
                    offset: const Offset(0, 6))
              ],
            ),
            child: Icon(
              _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: const Color(0xFF0D1B2A),
              size: R.s(46),
            ),
          ),
        ),
        const SizedBox(width: 12),
        IconButton(
          iconSize: 44,
          icon: const Icon(Icons.skip_next_rounded, color: Colors.white70),
          onPressed: _nextTrack,
        ),
      ],
    );
  }

  Widget _buildWaveform() {
    return SizedBox(
      height: 60,
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


