import 'dart:async';
import 'dart:js' as js;
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import '../services/progress_service.dart';
import '../services/lesson_service.dart';
import '../models/lesson.dart';
import 'eggy_celebration_screen.dart';
import '../utils/cdn_asset.dart';
import '../utils/responsive_utils.dart';

const _kOrange = Color(0xFFFF8C42);

// Per-sentence state: hear → record → done
enum _SentencePhase { hear, record, done }

class RecordingScreen extends StatefulWidget {
  final bool weekendMode;
  const RecordingScreen({super.key, this.weekendMode = false});
  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen>
    with TickerProviderStateMixin {

  final AudioPlayer  _player   = AudioPlayer();
  final AudioRecorder _recorder = AudioRecorder();

  RecordingPage? _recPage;
  int _currentIdx = 0;
  _SentencePhase _phase = _SentencePhase.hear;
  bool _isPlaying = false;
  bool _isRecording = false;
  bool _isPlayingBack = false;
  final Map<int, String?> _recordings = {};
  final Map<int, int> _scores = {}; // 0-100 score per sentence
  DateTime? _recordStart;
  Duration? _refDuration; // reference audio duration
  double _avgEnergy = 0; // average waveform energy during recording
  int _energySamples = 0;
  int _silentFrames = 0; // frames with very low energy

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;
  late final AnimationController _waveCtrl;
  final List<double> _barHeights = List.generate(20, (_) => 0.15);
  final Random _rng = Random();

  // Real mic volume from record package
  double _realVolume = 0; // 0.0 ~ 1.0
  Timer? _ampTimer;
  bool _scoring = false; // true while waiting for Whisper score
  bool _whisperReady = false;

  RecordingSentence? get _current =>
      _recPage != null && _currentIdx < _recPage!.sentences.length
          ? _recPage!.sentences[_currentIdx] : null;

  bool get _isLastSentence =>
      _recPage != null && _currentIdx >= _recPage!.sentences.length - 1;

  @override
  void initState() {
    super.initState();
    _loadData();
    // Pre-load Whisper model in background + check status
    if (kIsWeb) {
      try { js.context.callMethod('preloadWhisper', []); } catch (_) {}
      Timer.periodic(const Duration(seconds: 2), (t) {
        if (!mounted) { t.cancel(); return; }
        try {
          final ready = js.context.callMethod('isWhisperReady', []) as bool;
          if (ready && !_whisperReady) setState(() => _whisperReady = true);
          if (ready) t.cancel();
        } catch (_) {}
      });
    }
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.93, end: 1.07)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _waveCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 80))
      ..addListener(() {
        if (!mounted) return;
        setState(() {
          for (int i = 0; i < _barHeights.length; i++) {
            // Use real volume + small random variation for visual
            final target = _realVolume * 0.85 + _rng.nextDouble() * 0.15;
            _barHeights[i] = _barHeights[i] * 0.4 + target.clamp(0.05, 1.0) * 0.6;
          }
          // Track energy for scoring
          if (_isRecording) {
            _avgEnergy = (_avgEnergy * _energySamples + _realVolume) / (_energySamples + 1);
            _energySamples++;
            if (_realVolume < 0.05) _silentFrames++;
          }
        });
      });
    _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _isPlaying = false;
        _isPlayingBack = false;
        // After hearing, capture ref duration and show record button
        if (_phase == _SentencePhase.hear) {
          if (_playStart != null) {
            _refDuration = DateTime.now().difference(_playStart!);
          }
          _phase = _SentencePhase.record;
        }
      });
    });
  }

  @override
  void dispose() {
    _stopAmpPolling();
    _pulseCtrl.dispose();
    _waveCtrl.dispose();
    _player.dispose();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final service = LessonService();
    final lessonId = await service.restoreCurrentLessonId();
    final lesson = await service.loadLesson(lessonId);
    if (mounted && lesson.recordingPage != null) {
      setState(() => _recPage = lesson.recordingPage);
    }
  }

  DateTime? _playStart;

  void _playSentence() async {
    if (_current == null) return;
    _playStart = DateTime.now();
    setState(() => _isPlaying = true);
    await _player.play(cdnAudioSource(_current!.audio));
  }

  bool _ampWorking = false;

  void _startAmpPolling() {
    _ampWorking = false;
    _ampTimer = Timer.periodic(const Duration(milliseconds: 100), (_) async {
      if (!_isRecording) return;
      try {
        final amp = await _recorder.getAmplitude();
        final db = amp.current;
        // Check if amplitude API actually works (not -infinity or -160)
        if (db > -160 && db.isFinite) {
          _ampWorking = true;
          _realVolume = ((db + 50) / 50).clamp(0.0, 1.0);
        }
      } catch (_) {}
    });
  }

  void _stopAmpPolling() {
    _ampTimer?.cancel();
    _ampTimer = null;
    _realVolume = 0;
  }

  Future<void> _startRecording() async {
    try {
      if (!await _recorder.hasPermission()) return;
      String recPath = '';
      if (!kIsWeb) {
        final dir = await getApplicationDocumentsDirectory();
        recPath = '${dir.path}/rec_${_currentIdx}_${DateTime.now().millisecondsSinceEpoch}.m4a';
      }
      await _recorder.start(
        RecordConfig(
          encoder: kIsWeb ? AudioEncoder.wav : AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 16000,
        ),
        path: recPath,
      );
      _waveCtrl.repeat();
      _startAmpPolling();
      _recordStart = DateTime.now();
      _avgEnergy = 0;
      _energySamples = 0;
      _silentFrames = 0;
      setState(() => _isRecording = true);
    } catch (_) {}
  }

  Future<void> _stopRecording() async {
    _waveCtrl.stop();
    _stopAmpPolling();
    final recDuration = _recordStart != null
        ? DateTime.now().difference(_recordStart!)
        : Duration.zero;
    final result = await _recorder.stop();

    setState(() {
      _isRecording = false;
      _recordings[_currentIdx] = result;
      _phase = _SentencePhase.done;
      _scoring = true;
    });
    for (int i = 0; i < _barHeights.length; i++) _barHeights[i] = 0.15;

    // Try Whisper AI scoring, fall back to local
    final score = await _getScore(result, recDuration);
    if (mounted) setState(() {
      _scores[_currentIdx] = score;
      _scoring = false;
    });
  }

  Future<int> _getScore(String? audioUrl, Duration recDuration) async {
    // Try Whisper (browser-based AI)
    if (kIsWeb && audioUrl != null && _current != null) {
      try {
        // Wait up to 30s for Whisper to load if it's still loading
        final isLoading = js.context.callMethod('isWhisperLoading', []) as bool;
        if (isLoading) {
          for (int i = 0; i < 150; i++) { // 150 * 200ms = 30s
            await Future.delayed(const Duration(milliseconds: 200));
            if (js.context.callMethod('isWhisperReady', []) as bool) break;
          }
        }

        // Call transcribeAndScore (returns a Promise)
        final resultJs = js.context.callMethod(
          'transcribeAndScore',
          [audioUrl, _current!.text],
        );
        final result = await _awaitJsPromise(resultJs);
        final score = (result['score'] as num?)?.toInt() ?? -1;
        if (score >= 0) return score;
      } catch (e) {
        print('[Whisper] Error: $e');
      }
    }
    // Fallback: local duration-based scoring
    return _calculateScore(recDuration);
  }

  Future<void> _awaitJsPromise2(dynamic jsPromise) async {
    final completer = Completer<void>();
    final promise = jsPromise as js.JsObject;
    promise.callMethod('then', [
      js.allowInterop((_) => completer.complete()),
    ]);
    promise.callMethod('catch', [
      js.allowInterop((_) => completer.complete()),
    ]);
    return completer.future;
  }

  Future<Map<String, dynamic>> _awaitJsPromise(dynamic jsPromise) async {
    final completer = Completer<Map<String, dynamic>>();
    final promise = jsPromise as js.JsObject;
    promise.callMethod('then', [
      js.allowInterop((result) {
        final map = <String, dynamic>{};
        final jsObj = result as js.JsObject;
        map['text'] = jsObj['text'];
        map['score'] = jsObj['score'];
        completer.complete(map);
      }),
    ]);
    promise.callMethod('catch', [
      js.allowInterop((error) {
        completer.complete({'text': '', 'score': -1});
      }),
    ]);
    return completer.future;
  }

  int _calculateScore(Duration recDuration) {
    // If amplitude API works, use real volume scoring
    if (_ampWorking) {
      // 1. Duration score (40 points)
      double durationScore = 40;
      if (_refDuration != null && _refDuration!.inMilliseconds > 0) {
        final ratio = recDuration.inMilliseconds / _refDuration!.inMilliseconds;
        if (ratio < 0.3) { durationScore = 5; }
        else if (ratio < 0.7) { durationScore = 15 + (ratio - 0.3) / 0.4 * 25; }
        else if (ratio <= 1.5) { durationScore = 40; }
        else if (ratio <= 2.5) { durationScore = 40 - (ratio - 1.5) / 1.0 * 20; }
        else { durationScore = 10; }
      }

      // 2. Energy score (30 points)
      double energyScore;
      if (_avgEnergy < 0.02) { energyScore = 0; }
      else if (_avgEnergy < 0.05) { energyScore = 10; }
      else if (_avgEnergy < 0.15) { energyScore = 25; }
      else { energyScore = 30; }

      // 3. Consistency score (30 points)
      double consistencyScore = 30;
      if (_energySamples > 0) {
        final silentRatio = _silentFrames / _energySamples;
        if (silentRatio > 0.8) { consistencyScore = 0; }
        else if (silentRatio > 0.6) { consistencyScore = 10; }
        else if (silentRatio > 0.3) { consistencyScore = 20; }
      }

      return (durationScore + energyScore + consistencyScore).round().clamp(0, 100);
    }

    // Fallback: amplitude API not available, score based on duration only
    final recMs = recDuration.inMilliseconds;
    if (_refDuration != null && _refDuration!.inMilliseconds > 0) {
      final refMs = _refDuration!.inMilliseconds;
      final ratio = recMs / refMs;
      // Good range: 0.7x ~ 1.8x → 70-95 points
      if (ratio < 0.2) return 15;
      if (ratio < 0.5) return 40 + ((ratio - 0.2) / 0.3 * 30).round();
      if (ratio <= 1.8) return 70 + ((1.0 - (ratio - 1.0).abs()) * 25).round().clamp(0, 25);
      if (ratio <= 3.0) return 50;
      return 20;
    }
    // No reference: just check they recorded something reasonable
    if (recMs < 500) return 10;
    if (recMs < 1500) return 50;
    if (recMs < 5000) return 75;
    return 60;
  }

  void _playBack() async {
    final path = _recordings[_currentIdx];
    if (path == null) return;
    setState(() => _isPlayingBack = true);
    await _player.play(kIsWeb ? UrlSource(path) : DeviceFileSource(path));
  }

  void _reRecord() => setState(() => _phase = _SentencePhase.record);

  void _next() {
    if (_isLastSentence) {
      _onComplete();
    } else {
      setState(() {
        _currentIdx++;
        _phase = _SentencePhase.hear;
      });
    }
  }

  Future<void> _onComplete() async {
    await ProgressService.markModuleComplete('recording', 10);
    if (!mounted) return;
    if (widget.weekendMode) {
      Navigator.pop(context);
    } else {
      Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (_) => EggyCelebrationScreen(
          nextRoute: '/listen', nextLabel: '开始听力 🎧',
          moduleKey: 'recording', modulePoints: 10,
        ),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_recPage == null || _current == null) {
      return const Scaffold(
        backgroundColor: Color(0xFFFFF8F0),
        body: Center(child: CircularProgressIndicator(color: _kOrange)),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F0),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Full-screen spread ──
          cdnImage(_recPage!.imageAsset, fit: BoxFit.contain),


          // ── Top bar ──
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_rounded, color: _kOrange),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Expanded(child: Text('Say it out loud!',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _kOrange, fontSize: 18, fontWeight: FontWeight.w800))),
                    // Progress: 1/3 etc
                    Container(
                      margin: const EdgeInsets.only(right: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: _kOrange, borderRadius: BorderRadius.circular(14)),
                      child: Text('${_currentIdx + 1}/${_recPage!.sentences.length}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Whisper status ──
          if (kIsWeb)
            Positioned(
              top: 0, right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8, top: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _whisperReady ? Colors.green.shade50 : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _whisperReady ? Icons.check_circle : Icons.downloading,
                          size: 14,
                          color: _whisperReady ? Colors.green : Colors.orange,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _whisperReady ? 'AI Ready' : 'AI Loading...',
                          style: TextStyle(
                            fontSize: 11,
                            color: _whisperReady ? Colors.green : Colors.orange,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // ── Scoring indicator ──
          if (_scoring)
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8)],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: _kOrange)),
                    const SizedBox(width: 10),
                    Text('Scoring...', style: TextStyle(
                      color: _kOrange, fontWeight: FontWeight.w700, fontSize: 14)),
                  ],
                ),
              ),
            ),

          // ── Center controls ──
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Current sentence text — pulses during playback
                  ScaleTransition(
                    scale: _isPlaying ? _pulseAnim : const AlwaysStoppedAnimation(1.0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      decoration: BoxDecoration(
                        color: _kOrange.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _kOrange.withValues(alpha: 0.4)),
                        boxShadow: [BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 8,
                        )],
                      ),
                      child: Text(
                        _current!.text,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: R.s(28), fontWeight: FontWeight.w900,
                          color: const Color(0xFF333333), height: 1.3,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Waveform
                  if (_isRecording)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: SizedBox(
                        height: 36,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: _barHeights.map((h) => Container(
                            width: 3.5, height: 36 * h,
                            margin: const EdgeInsets.symmetric(horizontal: 1.5),
                            decoration: BoxDecoration(
                              color: _kOrange.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          )).toList(),
                        ),
                      ),
                    ),

                  // ── Hear phase ──
                  if (_phase == _SentencePhase.hear) ...[
                    ScaleTransition(
                      scale: _pulseAnim,
                      child: GestureDetector(
                        onTap: _isPlaying ? null : _playSentence,
                        child: Container(
                          width: R.s(150), height: R.s(150),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.9),
                            border: Border.all(color: _kOrange, width: 2),
                            boxShadow: [BoxShadow(
                              color: _kOrange.withValues(alpha: 0.2),
                              blurRadius: 20, spreadRadius: 4,
                            )],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(_isPlaying ? Icons.hearing : Icons.play_circle_fill,
                                  size: R.s(56), color: _kOrange),
                              const SizedBox(height: 10),
                              Text(_isPlaying ? 'Listening...' : 'Hear it first',
                                  style: TextStyle(fontSize: R.s(22), fontWeight: FontWeight.w800, color: _kOrange)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],

                  // ── Record phase (only after hearing) ──
                  if (_phase == _SentencePhase.record) ...[
                    // Hear again (only when NOT recording)
                    if (!_isRecording) ...[
                      ElevatedButton.icon(
                        onPressed: () {
                          setState(() => _phase = _SentencePhase.hear);
                          _playSentence();
                        },
                        icon: const Icon(Icons.replay, size: 22),
                        label: const Text('Hear again',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: _kOrange,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                          side: const BorderSide(color: _kOrange),
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],
                    // Record button
                    GestureDetector(
                      onTap: _isRecording ? _stopRecording : _startRecording,
                      child: Container(
                        width: R.s(88), height: R.s(88),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isRecording ? Colors.red : _kOrange,
                          boxShadow: [BoxShadow(
                            color: (_isRecording ? Colors.red : _kOrange).withValues(alpha: 0.3),
                            blurRadius: 16, spreadRadius: 4,
                          )],
                        ),
                        child: Icon(_isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                            color: Colors.white, size: R.s(42)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(_isRecording ? 'Tap to stop' : 'Tap to record',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 16)),
                  ],

                  // ── Done phase ──
                  if (_phase == _SentencePhase.done) ...[
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        _pillButton(
                          icon: _isPlayingBack ? Icons.pause : Icons.play_arrow,
                          label: 'Play back',
                          onTap: _isPlayingBack ? null : _playBack,
                          color: Colors.grey.shade100,
                          textColor: Colors.grey.shade700,
                        ),
                        if (!_scoring && _scores.containsKey(_currentIdx))
                          Positioned(
                            right: -10,
                            top: -10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: (_scores[_currentIdx] ?? 0) >= 75
                                    ? const Color(0xFFFF8C42)
                                    : (_scores[_currentIdx] ?? 0) >= 50
                                        ? Colors.amber
                                        : Colors.redAccent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${_scores[_currentIdx] ?? 0}',
                                style: TextStyle(
                                  fontSize: R.s(14),
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _pillButton(
                      icon: Icons.mic,
                      label: 'Re-record',
                      onTap: _reRecord,
                      color: Colors.grey.shade100,
                      textColor: Colors.grey.shade700,
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: _next,
                      child: Container(
                        width: R.s(220),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        decoration: BoxDecoration(
                          color: _kOrange,
                          borderRadius: BorderRadius.circular(28),
                        ),
                        child: Center(
                          child: Text(
                            _isLastSentence ? 'Done' : 'Next →',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }


  Widget _pillButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    required Color color,
    required Color textColor,
    bool border = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: R.s(220),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(28),
          border: border ? Border.all(color: _kOrange, width: 1.5) : null,
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 22, color: textColor),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: textColor)),
        ]),
      ),
    );
  }
}
