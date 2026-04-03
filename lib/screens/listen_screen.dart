import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/progress_service.dart';
import '../services/lesson_service.dart';

// ── Playlist ──────────────────────────────────────────────────────────────────

class _Track {
  final String label, path;
  const _Track(this.label, this.path);
}

// Default fallback
const _kDefaultTracks = [
  _Track('Biscuit - Original Narration', 'audio/biscuit_original.mp3'),
];

// ── Screen ────────────────────────────────────────────────────────────────────

class ListenScreen extends StatefulWidget {
  const ListenScreen({super.key});
  @override
  State<ListenScreen> createState() => _ListenScreenState();
}

class _ListenScreenState extends State<ListenScreen>
    with TickerProviderStateMixin {
  final _player = AudioPlayer();

  // Playlist
  List<_Track> _tracks = _kDefaultTracks;

  // Audio state
  bool _playing = false;
  int  _trackIdx = 0;

  final List<StreamSubscription> _subs = [];

  // Listening time counter (seconds today)
  int _listenSeconds = 0;
  Timer? _petTimer;

  // Eggy display (matches study room)
  int _eggyMonth = 1;
  String? _equippedAccessory;

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

    _subs.addAll([
      _player.onPlayerComplete.listen((_) => _nextTrack()),
      _player.onPositionChanged.listen((p) {
        if (mounted) setState(() => _position = p);
      }),
      _player.onDurationChanged.listen((d) {
        if (mounted) setState(() => _duration = d);
      }),
    ]);

    _loadListenTime();
    _loadEggy();
    _startTimers();

    // Wait for data to load before starting playback
    _loadListenData().then((_) {
      if (mounted) _playTrack(0);
    });
  }

  // Ordered list of all lessons for building listen playlists
  static const _kLessonOrder = [
    ('biscuit_book1_day1',          'Biscuit',                    'audio/biscuit_original.mp3'),
    ('biscuit_baby_book2_day1',     'Biscuit and the Baby',       'audio/biscuit_baby_original.mp3'),
    ('biscuit_library_book3_day1',  'Biscuit Loves the Library',  'books/03Biscuit_Loves_the_Library/audio.mp3'),
  ];

  Future<void> _loadListenData() async {
    final service = LessonService();
    final lessonId = await service.restoreCurrentLessonId();
    final lesson = await service.loadLesson(lessonId);

    if (lesson.originalAudio.isEmpty) return;

    // Find current day index (0-based) in the lesson order
    int dayIndex = _kLessonOrder.indexWhere((e) => e.$1 == lessonId);
    if (dayIndex < 0) dayIndex = 0;

    final todayTitle = lesson.bookTitle;
    final todayAudio = lesson.originalAudio;

    final playlist = <_Track>[];

    if (dayIndex == 0) {
      // Day 1: today × 2
      playlist.add(_Track('$todayTitle (1/2)', todayAudio));
      playlist.add(_Track('$todayTitle (2/2)', todayAudio));
    } else {
      // Day 2+: today × 1, then previous day, then today again
      final prevTitle = _kLessonOrder[dayIndex - 1].$2;
      final prevAudio = _kLessonOrder[dayIndex - 1].$3;

      playlist.add(_Track('$todayTitle - 新故事', todayAudio));
      playlist.add(_Track('$prevTitle - 复习', prevAudio));
      playlist.add(_Track('$todayTitle - 巩固', todayAudio));
    }

    if (mounted) {
      setState(() => _tracks = playlist);
    }
  }

  @override
  void dispose() {
    for (final s in _subs) s.cancel();
    _player.dispose();
    for (final c in _waveCtrl) c.dispose();
    _petTimer?.cancel();
    super.dispose();
  }

  // ── Listening time ───────────────────────────────────────────────────────────

  Future<void> _loadEggy() async {
    final prefs = await SharedPreferences.getInstance();
    // Eggy month: same calculation as study room
    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (!prefs.containsKey('app_start_date')) {
      await prefs.setString('app_start_date', today);
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
    await prefs.setString('listen_date', _dateStr(DateTime.now()));
    await prefs.setInt('listen_seconds', _listenSeconds);
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
    setState(() => _trackIdx = i);
    await _player.stop();
    await _player.play(AssetSource(_tracks[i].path));
    _setPlaying(true);
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
      await _player.pause();
      _setPlaying(false);
    } else {
      await _player.resume();
      _setPlaying(true);
    }
  }

  void _nextTrack() {
    if (_trackIdx + 1 >= _tracks.length) {
      // All tracks finished — mark listen done and go home
      _onListenComplete();
    } else {
      _playTrack(_trackIdx + 1);
    }
  }

  Future<void> _onListenComplete() async {
    await _player.stop();
    _setPlaying(false);
    await _saveListenTime();
    await ProgressService.markModuleComplete('listen', 10);
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
    }
  }

  void _prevTrack() =>
      _playTrack((_trackIdx - 1 + _tracks.length) % _tracks.length);

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Dark starry background ──────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF0D1B2A), Color(0xFF1B2A4A)],
              ),
            ),
          ),
          Positioned.fill(
            child: Stack(
                alignment: Alignment.center,
                children: [
                  Image.asset(
                    'assets/pet/cards/bicycle.webp',
                    fit: BoxFit.contain,
                    width: double.infinity,
                    height: double.infinity,
                    errorBuilder: (_, __, ___) => Image.asset(
                      'assets/pet/costumes/base/egg_month$_eggyMonth.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                  if (_equippedAccessory != null)
                    Image.asset(
                      'assets/pet/costumes/accessories/$_equippedAccessory.png',
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      errorBuilder: (_, __, ___) => const SizedBox(),
                    ),
                ],
            ),
          ),
          // ── Dark overlay ─────────────────────────────────────────────────────
          Container(color: Colors.black.withValues(alpha: 0.55)),

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
    final m = (_listenSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_listenSeconds % 60).toString().padLeft(2, '0');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded,
                color: Colors.white70, size: 22),
            onPressed: () {
              _saveListenTime();
              _player.stop();
              Navigator.pop(context);
            },
          ),
          const Expanded(
            child: Text('磨耳朵  👂',
              textAlign: TextAlign.center,
              style: TextStyle(
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
          // Done button — shows Eggy celebration
          GestureDetector(
            onTap: () async {
              await _saveListenTime();
              _player.stop();
              await ProgressService.markModuleComplete('listen', 10);
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
              activeTrackColor: const Color(0xFFFF8C42),
              inactiveTrackColor: Colors.white.withValues(alpha: 0.2),
              thumbColor: Colors.white,
              overlayColor: Colors.white.withValues(alpha: 0.15),
            ),
            child: Slider(
              value: progress,
              onChanged: (v) {
                if (_duration.inMilliseconds > 0) {
                  _player.seek(Duration(
                      milliseconds: (v * _duration.inMilliseconds).toInt()));
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
            width: 80,
            height: 80,
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
              size: 46,
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


