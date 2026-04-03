import 'dart:async';
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import '../services/progress_service.dart';
import '../services/lesson_service.dart';
import 'eggy_celebration_screen.dart';
import '../utils/cdn_asset.dart';

const _kOrange = Color(0xFFFF8C42);
const _kYellow = Color(0xFFFFD93D);
const _kCream  = Color(0xFFFFF8F0);

class RecordingScreen extends StatefulWidget {
  const RecordingScreen({super.key});

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen>
    with TickerProviderStateMixin {

  final AudioPlayer  _player   = AudioPlayer();
  final AudioRecorder _recorder = AudioRecorder();

  // ── lesson data ────────────────────────────────────────────────────────────
  String _featuredSentence = '"Time for bed, Biscuit!"';
  String _featuredSentenceCN = '小饼干，该睡觉啦！';
  String _demoAudioPath = 'audio/featured_time_for_bed.mp3';

  // ── state ──────────────────────────────────────────────────────────────────
  _Phase    _phase          = _Phase.demo;
  bool      _demoPlaying    = false;
  String?   _recordingPath;
  bool      _hasRecording   = false;
  bool      _isPlayingBack  = false;

  // ── scoring ────────────────────────────────────────────────────────────────
  // 0 = no attempt, 5 = too short, 10 = full score
  int       _scorePoints     = 0;
  int       _totalStars      = 0;
  DateTime? _recordStart;
  bool      _showScoreButtons = false;

  // stars to show: 10pts→3, 5pts→1, 0pts→0
  int get _starCount => _scorePoints == 10 ? 3 : _scorePoints == 5 ? 1 : 0;

  // ── demo pulse ─────────────────────────────────────────────────────────────
  late final AnimationController _pulseCtrl;
  late final Animation<double>   _pulseAnim;

  // ── record button pulse while recording ────────────────────────────────────
  late final AnimationController _recPulseCtrl;
  late final Animation<double>   _recPulseAnim;

  // ── REC dot blink ──────────────────────────────────────────────────────────
  late final AnimationController _recDotCtrl;

  // ── waveform bars ──────────────────────────────────────────────────────────
  late final AnimationController _waveCtrl;
  final List<double> _barHeights = List.generate(22, (_) => 0.15);

  // ── star pop-in animations (3 stars, staggered) ────────────────────────────
  late final List<AnimationController> _starCtrls;
  late final List<Animation<double>>   _starAnims;

  // ── confetti ───────────────────────────────────────────────────────────────
  late final AnimationController _confettiCtrl;
  late final Animation<double>   _confettiAnim;
  final Random _rng = Random();
  late final List<_Particle> _particles;

  @override
  void initState() {
    super.initState();
    _loadLessonData();
    ProgressService.getTodayProgress().then((p) {
      if (mounted) setState(() => _totalStars = (p['total_stars'] as int?) ?? 0);
    });

    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.93, end: 1.07)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _recPulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _recPulseAnim = Tween<double>(begin: 1.0, end: 1.12).animate(
        CurvedAnimation(parent: _recPulseCtrl, curve: Curves.easeInOut));

    _recDotCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600))
      ..repeat(reverse: true);

    _waveCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 80))
      ..addListener(_updateWave);

    _starCtrls = List.generate(3, (_) => AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500)));
    _starAnims = _starCtrls.map((c) =>
        Tween<double>(begin: 0.0, end: 1.0).animate(
            CurvedAnimation(parent: c, curve: Curves.elasticOut))).toList();

    _confettiCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800));
    _confettiAnim =
        CurvedAnimation(parent: _confettiCtrl, curve: Curves.easeOut);
    _particles = List.generate(40, (_) => _Particle(_rng));

    _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      if (_phase == _Phase.demo) {
        setState(() { _demoPlaying = false; _phase = _Phase.idle; });
      } else if (_phase == _Phase.playback) {
        setState(() { _isPlayingBack = false; });
      }
    });

    Future.delayed(const Duration(milliseconds: 600), _playDemo);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _recPulseCtrl.dispose();
    _recDotCtrl.dispose();
    _waveCtrl.dispose();
    for (final c in _starCtrls) { c.dispose(); }
    _confettiCtrl.dispose();
    _player.dispose();
    _recorder.dispose();
    super.dispose();
  }

  // ── lesson data ─────────────────────────────────────────────────────────────

  // Map lessonId to featured audio file
  static const _featuredAudioMap = {
    'biscuit_book1_day1': 'audio/featured_time_for_bed.mp3',
    'biscuit_baby_book2_day1': 'audio/biscuit_baby_featured.mp3',
    'biscuit_library_book3_day1': 'audio/library_featured.mp3',
  };

  Future<void> _loadLessonData() async {
    final service = LessonService();
    final lessonId = await service.restoreCurrentLessonId();
    final lesson = await service.loadLesson(lessonId);
    if (mounted) {
      setState(() {
        _featuredSentence = '"${lesson.featuredSentence}"';
        _demoAudioPath = _featuredAudioMap[lessonId] ?? 'audio/featured_time_for_bed.mp3';
      });
    }
  }

  // ── demo ───────────────────────────────────────────────────────────────────

  void _playDemo() async {
    if (!mounted) return;
    setState(() => _demoPlaying = true);
    await _player.play(cdnAudioSource(_demoAudioPath));
  }

  void _replayDemo() {
    if (_demoPlaying) return;
    setState(() => _phase = _Phase.demo);
    _playDemo();
  }

  // ── waveform ───────────────────────────────────────────────────────────────

  void _updateWave() {
    if (!mounted) return;
    setState(() {
      for (int i = 0; i < _barHeights.length; i++) {
        final t = 0.15 + _rng.nextDouble() * 0.85;
        _barHeights[i] = _barHeights[i] * 0.55 + t * 0.45;
      }
    });
  }

  // ── recording ──────────────────────────────────────────────────────────────

  Future<void> _toggleRecording() async {
    if (_phase == _Phase.recording) {
      // stop — on web, stop() returns a blob URL; on mobile it returns the file path
      _recPulseCtrl.stop();
      _recPulseCtrl.reset();
      _waveCtrl.stop();

      final durationMs = _recordStart == null ? 0
          : DateTime.now().difference(_recordStart!).inMilliseconds;
      final result = await _recorder.stop();
      _recordingPath = result;

      // 0 = no attempt (<300ms), 5 = too short (300-999ms), 10 = full (>=1000ms)
      final int newPoints = durationMs >= 1000 ? 10
                          : durationMs >= 300  ? 5
                          : 0;
      setState(() {
        _hasRecording     = true;
        _scorePoints      = newPoints;
        _showScoreButtons = false;
        _phase            = _Phase.scored;
      });
      for (int i = 0; i < _barHeights.length; i++) { _barHeights[i] = 0.15; }

      // animate stars in staggered (starCount derived from points)
      final int stars = newPoints == 10 ? 3 : newPoints == 5 ? 1 : 0;
      for (int i = 0; i < 3; i++) {
        _starCtrls[i].reset();
        if (i < stars) {
          final delay = Duration(milliseconds: i * 220);
          Future.delayed(delay, () { if (mounted) _starCtrls[i].forward(); });
        }
      }

      // Show buttons after short delay for all scores
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) setState(() => _showScoreButtons = true);
      });
    } else if (_phase == _Phase.idle ||
               _phase == _Phase.playback ||
               _phase == _Phase.scored) {
      // start
      try {
        final hasPermission = await _recorder.hasPermission();
        if (!hasPermission) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Microphone permission denied')),
            );
          }
          return;
        }

        // path_provider is not available on web — use a dummy path (ignored by record on web)
        final String recordPath;
        if (kIsWeb) {
          recordPath = 'bridgeread_recording.m4a';
        } else {
          final dir = await getTemporaryDirectory();
          recordPath = '${dir.path}/bridgeread_recording.m4a';
        }

        await _recorder.start(
          RecordConfig(
            encoder: AudioEncoder.aacLc,
            bitRate: 128000,
          ),
          path: recordPath,
        );
        _recordStart = DateTime.now();
        _waveCtrl.repeat();
        _recPulseCtrl.repeat(reverse: true);
        setState(() => _phase = _Phase.recording);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not start recording: $e')),
          );
        }
      }
    }
  }

  // ── playback ───────────────────────────────────────────────────────────────

  Future<void> _playRecording() async {
    if (_recordingPath == null) return;
    setState(() => _isPlayingBack = true);
    // On web, stop() returns a blob URL — use UrlSource.
    // On mobile, use DeviceFileSource with the file path.
    final source = kIsWeb
        ? UrlSource(_recordingPath!)
        : DeviceFileSource(_recordingPath!);
    await _player.play(source);
    if (!_confettiCtrl.isCompleted && !_confettiCtrl.isAnimating) {
      _confettiCtrl.forward(from: 0);
    }
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kCream,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Column(
              children: [
                _buildTopBar(),
                Expanded(child: _buildTwoPanel()),
              ],
            ),
            if (_hasRecording)
              IgnorePointer(child: _buildConfetti()),
          ],
        ),
      ),
    );
  }

  // ── top bar ────────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          // Back button
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(Icons.arrow_back_ios_rounded,
                  color: _kOrange, size: 22),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => Navigator.pushReplacementNamed(context, '/home'),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(Icons.home_rounded, color: _kOrange, size: 24),
            ),
          ),
          const SizedBox(width: 14),
          const Text(
            'Say it out loud! 🎙️',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF444444),
            ),
          ),
          const Spacer(),
          // ── score chip ──────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: _scorePoints == 10
                  ? _kOrange
                  : _scorePoints == 5
                      ? _kYellow
                      : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _scorePoints > 0 ? Colors.transparent : Colors.grey.shade300,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('⭐', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 4),
                Text(
                  '$_totalStars',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── two-panel layout ───────────────────────────────────────────────────────

  Widget _buildTwoPanel() {
    return LayoutBuilder(builder: (context, constraints) {
      final panelW = constraints.maxWidth * 0.50;
      return Stack(
        fit: StackFit.expand,
        children: [
          // ── book spread: same as reader — contain on cream background ────
          Positioned.fill(
            child: ColoredBox(
              color: const Color(0xFFFFF8F0),
              child: cdnImage('assets/books/01Biscuit/biscuit_spread_02.webp',
                fit: BoxFit.contain,
              ),
            ),
          ),

          // ── white panel covers the right half ───────────────────────────
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: panelW,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(28),
                  bottomLeft: Radius.circular(28),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.14),
                    blurRadius: 24,
                    offset: const Offset(-6, 0),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 1. Sentence
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _featuredSentence,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          fontStyle: FontStyle.italic,
                          color: Color(0xFF222222),
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                  // 2. Demo button
                  _buildDemoButton(),
                  // 3. Middle slot: mic/waveform OR play back + re-record
                  if (_phase == _Phase.scored)
                    _buildScoreSection()
                  else ...[
                    _buildWaveformOrStatus(),
                    _buildRecordButton(),
                  ],
                  // 4. Bottom: Next button (always occupies space)
                  _buildBottomControls(),
                ],
              ),
            ),
          ),
        ],
      );
    });
  }

  // ── demo button ────────────────────────────────────────────────────────────

  Widget _buildDemoButton() {
    return GestureDetector(
      onTap: _replayDemo,
      child: AnimatedBuilder(
        animation: _pulseCtrl,
        builder: (context, child) => Transform.scale(
          scale: _demoPlaying ? _pulseAnim.value : 1.0,
          child: child,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
          decoration: BoxDecoration(
            color: _demoPlaying ? _kOrange : _kOrange.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _demoPlaying
                    ? Icons.volume_up_rounded
                    : Icons.play_circle_filled_rounded,
                color: _demoPlaying ? Colors.white : _kOrange,
                size: 38,
              ),
              const SizedBox(width: 12),
              Text(
                _demoPlaying ? 'Playing...' : 'Hear it first',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: _demoPlaying ? Colors.white : _kOrange,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── score section ──────────────────────────────────────────────────────────

  Widget _buildScoreSection() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_recordingPath != null)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Play back button
              GestureDetector(
                onTap: _isPlayingBack ? null : _playRecording,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: _isPlayingBack
                        ? _kYellow
                        : _kYellow.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _kYellow, width: 2),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isPlayingBack
                            ? Icons.volume_up_rounded
                            : Icons.replay_rounded,
                        color: const Color(0xFF555500),
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isPlayingBack ? 'Playing...' : 'Play back',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF555500),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Re-record button
              GestureDetector(
                onTap: () {
                  setState(() {
                    _phase = _Phase.idle;
                    _scorePoints = 0;
                    _showScoreButtons = false;
                    _hasRecording = false;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.3), width: 2),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.mic_rounded, color: Colors.red, size: 22),
                      SizedBox(width: 8),
                      Text('Re-record',
                        style: TextStyle(fontSize: 16,
                            fontWeight: FontWeight.bold, color: Colors.red),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  // ── waveform / status ──────────────────────────────────────────────────────

  Widget _buildWaveformOrStatus() {
    if (_phase == _Phase.recording) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // flashing ● REC
          AnimatedBuilder(
            animation: _recDotCtrl,
            builder: (context, child) => Opacity(
              opacity: _recDotCtrl.value,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, color: Colors.red, size: 16),
                  SizedBox(width: 8),
                  Text('REC',
                      style: TextStyle(
                        color: Colors.red,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 3,
                      )),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          // waveform bars
          SizedBox(
            height: 64,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: List.generate(_barHeights.length, (i) {
                return Container(
                  width: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  height: _barHeights[i] * 60,
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.5 + _barHeights[i] * 0.5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
          ),
        ],
      );
    }

    if (_phase == _Phase.playback || _phase == _Phase.scored) {
      return GestureDetector(
        onTap: _isPlayingBack ? null : _playRecording,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: _isPlayingBack ? _kYellow : _kYellow.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _kYellow, width: 2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _isPlayingBack ? Icons.volume_up_rounded : Icons.replay_rounded,
                color: const Color(0xFF555500),
                size: 20,
              ),
              const SizedBox(width: 6),
              Text(
                _isPlayingBack ? 'Playing...' : 'Play back',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF555500),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  // ── record button ──────────────────────────────────────────────────────────

  Widget _buildRecordButton() {
    final isRecording = _phase == _Phase.recording;
    final canRecord   = _phase == _Phase.idle ||
                        _phase == _Phase.playback ||
                        _phase == _Phase.scored;

    return GestureDetector(
      onTap: (isRecording || canRecord) ? _toggleRecording : null,
      child: AnimatedBuilder(
        animation: _recPulseAnim,
        builder: (_, child) => Transform.scale(
          scale: isRecording ? _recPulseAnim.value : 1.0,
          child: child,
        ),
        child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 130,
        height: 130,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isRecording
              ? const Color(0xFFCC0000)
              : canRecord
                  ? Colors.red
                  : Colors.grey.shade300,
          boxShadow: isRecording
              ? [
                  BoxShadow(
                    color: Colors.red.withValues(alpha: 0.55),
                    blurRadius: 28,
                    spreadRadius: 6,
                  ),
                ]
              : canRecord
                  ? [
                      BoxShadow(
                        color: Colors.red.withValues(alpha: 0.30),
                        blurRadius: 16,
                        spreadRadius: 2,
                        offset: const Offset(0, 5),
                      ),
                    ]
                  : [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isRecording ? Icons.stop_rounded : Icons.mic_rounded,
              color: Colors.white,
              size: 54,
            ),
            const SizedBox(height: 6),
            Text(
              isRecording ? 'Stop' : canRecord ? 'Record' : '',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  // ── bottom controls ────────────────────────────────────────────────────────

  Widget _buildBottomControls() {
    if (_phase == _Phase.scored && _showScoreButtons) {
      return SizedBox(
        height: 64,
        width: 280,
        child: ElevatedButton(
          onPressed: () {
            if (!mounted) return;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => EggyCelebrationScreen(
                  nextRoute:    '/listen',
                  nextLabel:    'Final Step! 🎧',
                  moduleKey:    'listen',
                  modulePoints: _scorePoints > 0 ? _scorePoints : 10,
                ),
              ),
            );
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: _kOrange,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(32)),
            textStyle: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold),
          ),
          child: const Text('Next! →'),
        ),
      );
    }
    return const SizedBox(height: 8);
  }

  // ── confetti ───────────────────────────────────────────────────────────────

  Widget _buildConfetti() {
    return AnimatedBuilder(
      animation: _confettiAnim,
      builder: (context, _) {
        final p = _confettiAnim.value;
        return LayoutBuilder(builder: (ctx, box) {
          return Stack(
            children: _particles.map((pt) {
              final x = pt.x * box.maxWidth;
              final y = pt.startY * box.maxHeight + p * pt.speed * box.maxHeight;
              final opacity = (1.0 - p * 1.2).clamp(0.0, 1.0);
              return Positioned(
                left: x,
                top: y,
                child: Opacity(
                  opacity: opacity,
                  child: Transform.rotate(
                    angle: p * pt.spin,
                    child: Text(pt.emoji,
                        style: TextStyle(fontSize: pt.size)),
                  ),
                ),
              );
            }).toList(),
          );
        });
      },
    );
  }
}

// ── phase ──────────────────────────────────────────────────────────────────────

enum _Phase { demo, idle, recording, playback, scored }

// ── confetti particle ──────────────────────────────────────────────────────────

class _Particle {
  final double x, startY, speed, spin, size;
  final String emoji;
  static const _emojis = ['⭐', '🌟', '✨', '🎉', '🎊', '💫'];
  _Particle(Random rng)
      : x      = rng.nextDouble(),
        startY = -0.1 - rng.nextDouble() * 0.3,
        speed  = 0.6 + rng.nextDouble() * 0.8,
        spin   = (rng.nextDouble() - 0.5) * 8,
        size   = 18 + rng.nextDouble() * 20,
        emoji  = _emojis[rng.nextInt(_emojis.length)];
}
