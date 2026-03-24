import 'dart:async';
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../services/progress_service.dart';

// ---------------------------------------------------------------------------
// Constants & data
// ---------------------------------------------------------------------------

const _kOrange = Color(0xFFFF8C42);
const _kYellow = Color(0xFFFFD93D);
const _kCream = Color(0xFFFFF8F0);

class _LetterInfo {
  final String char;
  final Color tileColor;
  final String audioPath;
  const _LetterInfo(this.char, this.tileColor, this.audioPath);
}

class _WordData {
  final String word;
  final String bookImage;
  final String wordAudioPath;
  final List<_LetterInfo> letters;
  const _WordData({
    required this.word,
    required this.bookImage,
    required this.wordAudioPath,
    required this.letters,
  });
}

final List<_WordData> _kWords = [
  _WordData(
    word: 'bed',
    bookImage: 'assets/books/biscuit_spread_02.png',
    wordAudioPath: 'assets/audio/phonemes/word_bed.mp3',
    letters: const [
      _LetterInfo('b', _kOrange, 'assets/audio/phonemes/b.mp3'),
      _LetterInfo('e', _kYellow, 'assets/audio/phonemes/e_short.mp3'),
      _LetterInfo('d', _kOrange, 'assets/audio/phonemes/d.mp3'),
    ],
  ),
  _WordData(
    word: 'hug',
    bookImage: 'assets/books/biscuit_spread_06.png',
    wordAudioPath: 'assets/audio/phonemes/word_hug.mp3',
    letters: const [
      _LetterInfo('h', _kOrange, 'assets/audio/phonemes/h.mp3'),
      _LetterInfo('u', _kYellow, 'assets/audio/phonemes/u_short.mp3'),
      _LetterInfo('g', _kOrange, 'assets/audio/phonemes/g.mp3'),
    ],
  ),
];

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

enum _Step      { intro, tiles, echo, drag }
enum _EchoPhase { idle, recording, scored }

class PhonicsScreen extends StatefulWidget {
  const PhonicsScreen({super.key});

  @override
  State<PhonicsScreen> createState() => _PhonicsScreenState();
}

class _PhonicsScreenState extends State<PhonicsScreen>
    with TickerProviderStateMixin {
  final AudioPlayer _player = AudioPlayer();
  final Random _rng = Random();

  // Intro step: word-speaker feedback
  static const _kPositive      = 'assets/audio/phonemes/you_got_it.mp3';
  static const _kEncouragement = 'assets/audio/phonemes/one_more_time.mp3';
  // Drag step: letter-placement feedback
  static const _kBingo = 'assets/audio/phonemes/bingo.mp3';
  static const _kOops  = 'assets/audio/phonemes/oops.mp3';

  int _wordIndex = 0;
  _Step _step = _Step.intro;
  bool _celebration = false;

  // Score
  int _score = 0;
  late final AnimationController _plusOneCtrl;

  // Step 2: staggered tile bounce-in
  late final List<AnimationController> _tileControllers;
  late final List<Animation<double>> _tileScaleAnims;
  int _tilesShown = 0; // how many tiles have started bounce-in
  int _tilesLit = 0;   // how many tiles have completed audio (are lit up)

  // Step 3: drag state
  List<int> _shuffledOrder = [0, 1, 2];
  List<int?> _slots = [null, null, null];
  final Set<int> _placedLetters = {};

  // Step 3: slot pop animation on correct placement
  late final List<AnimationController> _slotControllers;
  late final List<Animation<double>> _slotScaleAnims;

  // Step 3: sad-face feedback on wrong drop
  List<bool> _slotSad = [false, false, false];
  Timer? _sadFaceTimer;

  // Completion
  bool _wordComplete = false;
  bool _showAmazing = false;
  bool _showNextBtn = false;
  late final AnimationController _starController;
  late final Animation<double> _starAnim;

  // Intro step: word speaker gate + shake
  bool _wordSpeakerDone = false;
  late final AnimationController _speakerShakeCtrl;
  late final Animation<double> _speakerShakeAnim;

  // Intro step: falling stars (you got it)
  late final AnimationController _fallingStarsCtrl;
  late final Animation<double> _fallingStarsAnim;

  // Tiles step: per-letter star tracking + playable gate + sequential shake
  final Set<int> _letterStarsTapped = {};
  bool _tilesPlayable = false;
  int _nextTileToTap = 0;
  late final AnimationController _tileShakeCtrl;
  late final Animation<double> _tileShakeAnim;

  // Word-tap feedback (intro step)
  int _wordTapCount = 0;
  int _tapStars = 0; // persists across taps: 0→1→2→3
  bool _isYouGotIt = false;
  Timer? _wordMsgTimer;
  late final AnimationController _wordMsgController;
  late final AnimationController _wordBubbleScale;
  late final Animation<double> _wordBubbleScaleAnim;
  late final AnimationController _wordStarController;
  late final Animation<double> _wordStarAnim;

  // Intro step: Sound it out button bounce to guide child after "You got it!"
  late final AnimationController _soundItOutBounceCtrl;
  late final Animation<double> _soundItOutBounceAnim;

  // Echo step (record & repeat)
  final AudioRecorder _recorder = AudioRecorder();
  String? _recordingPath;
  _EchoPhase _echoPhase = _EchoPhase.idle;
  int  _echoScorePoints  = 0;
  bool _echoShowButtons  = false;
  DateTime? _echoRecordStart;

  late final AnimationController _echoPulseCtrl; // idle mic pulse
  late final Animation<double>   _echoPulseAnim;
  late final AnimationController _recDotCtrl;    // REC dot blink
  late final AnimationController _waveCtrl;      // waveform update
  final List<double> _barHeights = List.generate(18, (_) => 0.15);
  late final List<AnimationController> _echoStarCtrls;
  late final List<Animation<double>>   _echoStarAnims;

  @override
  void initState() {
    super.initState();

    _tileControllers = List.generate(
      3,
      (_) => AnimationController(
          vsync: this, duration: const Duration(milliseconds: 650)),
    );
    _tileScaleAnims = _tileControllers
        .map((c) => Tween<double>(begin: 0.0, end: 1.0).animate(
              CurvedAnimation(parent: c, curve: Curves.elasticOut),
            ))
        .toList();

    _slotControllers = List.generate(
      3,
      (_) => AnimationController(
          vsync: this, duration: const Duration(milliseconds: 450)),
    );
    _slotScaleAnims = _slotControllers
        .map((c) => TweenSequence<double>([
              TweenSequenceItem(
                  tween: Tween<double>(begin: 1.0, end: 1.35), weight: 40),
              TweenSequenceItem(
                  tween: Tween<double>(begin: 1.35, end: 1.0), weight: 60),
            ]).animate(CurvedAnimation(parent: c, curve: Curves.easeInOut)))
        .toList();

    _starController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400));
    _starAnim =
        CurvedAnimation(parent: _starController, curve: Curves.easeOut);

    _speakerShakeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 380));
    _speakerShakeAnim = Tween<double>(begin: -1.0, end: 1.0)
        .animate(CurvedAnimation(parent: _speakerShakeCtrl, curve: Curves.easeInOut));

    _fallingStarsCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _fallingStarsAnim =
        CurvedAnimation(parent: _fallingStarsCtrl, curve: Curves.easeIn);

    _tileShakeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 360));
    _tileShakeAnim = Tween<double>(begin: -1.0, end: 1.0)
        .animate(CurvedAnimation(parent: _tileShakeCtrl, curve: Curves.easeInOut));

    _plusOneCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 750));

    _wordMsgController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 250));
    _wordBubbleScale = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _wordBubbleScaleAnim = CurvedAnimation(
        parent: _wordBubbleScale, curve: Curves.easeOutBack);
    _wordStarController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));
    _wordStarAnim =
        CurvedAnimation(parent: _wordStarController, curve: Curves.easeOut);

    _soundItOutBounceCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _soundItOutBounceAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 1.08), weight: 50),
      TweenSequenceItem(tween: Tween<double>(begin: 1.08, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(parent: _soundItOutBounceCtrl, curve: Curves.easeInOut));

    _echoPulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _echoPulseAnim = Tween<double>(begin: 0.93, end: 1.07)
        .animate(CurvedAnimation(parent: _echoPulseCtrl, curve: Curves.easeInOut));

    _recDotCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600))
      ..repeat(reverse: true);

    _waveCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 80))
      ..addListener(_updateWave);

    _echoStarCtrls = List.generate(3, (_) => AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500)));
    _echoStarAnims = _echoStarCtrls.map((c) =>
        Tween<double>(begin: 0.0, end: 1.0).animate(
            CurvedAnimation(parent: c, curve: Curves.elasticOut))).toList();

    _enterIntro();
  }

  @override
  void dispose() {
    _player.dispose();
    for (final c in _tileControllers) {
      c.dispose();
    }
    for (final c in _slotControllers) {
      c.dispose();
    }
    _starController.dispose();
    _speakerShakeCtrl.dispose();
    _fallingStarsCtrl.dispose();
    _tileShakeCtrl.dispose();
    _plusOneCtrl.dispose();
    _wordMsgTimer?.cancel();
    _sadFaceTimer?.cancel();
    _wordMsgController.dispose();
    _wordBubbleScale.dispose();
    _wordStarController.dispose();
    _soundItOutBounceCtrl.dispose();
    _echoPulseCtrl.dispose();
    _recDotCtrl.dispose();
    _waveCtrl.dispose();
    for (final c in _echoStarCtrls) c.dispose();
    _recorder.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Audio helpers
  // ---------------------------------------------------------------------------

  Future<void> _playAudio(String assetPath) async {
    await _player.stop();
    await _player.play(AssetSource(assetPath.replaceFirst('assets/', '')));
  }

  /// Play audio and wait for it to finish before returning.
  Future<void> _playAndWait(String assetPath) async {
    await _player.stop();
    final completer = Completer<void>();
    late StreamSubscription<void> sub;
    sub = _player.onPlayerComplete.listen((_) {
      if (!completer.isCompleted) completer.complete();
      sub.cancel();
    });
    await _player.play(AssetSource(assetPath.replaceFirst('assets/', '')));
    await completer.future;
  }


  // ---------------------------------------------------------------------------
  // Step transitions
  // ---------------------------------------------------------------------------

  void _enterIntro() {
    for (final c in _tileControllers) {
      c.reset();
    }
    for (final c in _slotControllers) {
      c.reset();
    }
    _starController.reset();
    _wordMsgTimer?.cancel();
    _wordMsgController.reset();
    _wordBubbleScale.reset();
    _wordStarController.reset();
    _speakerShakeCtrl.stop();
    _speakerShakeCtrl.reset();
    _fallingStarsCtrl.reset();
    _tileShakeCtrl.stop();
    _tileShakeCtrl.reset();
    _soundItOutBounceCtrl.stop();
    _soundItOutBounceCtrl.reset();
    setState(() {
      _step = _Step.intro;
      _tilesShown = 0;
      _placedLetters.clear();
      _slots = [null, null, null];
      _slotSad = [false, false, false];
      _shuffledOrder = [0, 1, 2];
      _wordComplete = false;
      _showAmazing = false;
      _showNextBtn = false;
      _wordTapCount = 0;
      _tapStars = 0;
      _isYouGotIt = false;
      _wordSpeakerDone = false;
      _letterStarsTapped.clear();
      _nextTileToTap = 0;
      _tilesPlayable = false;
      _tilesLit = 0;
      _echoPhase = _EchoPhase.idle;
      _echoScorePoints = 0;
      _echoShowButtons = false;
      _echoRecordStart = null;
      _recordingPath = null;
    });
    _echoPulseCtrl.stop();
    _echoPulseCtrl.reset();
    _waveCtrl.stop();
    for (final c in _echoStarCtrls) c.reset();
    // Play word, then start speaker shake to invite the child to tap
    Future.delayed(const Duration(milliseconds: 500), () async {
      if (!mounted) return;
      await _playAndWait(_kWords[_wordIndex].wordAudioPath);
      if (mounted && !_wordSpeakerDone) {
        _speakerShakeCtrl.repeat(reverse: true);
      }
    });
  }

  void _enterTiles() {
    _soundItOutBounceCtrl.stop();
    _soundItOutBounceCtrl.reset();
    _wordMsgController.reset();
    _wordBubbleScale.reset();
    _tileShakeCtrl.stop();
    _tileShakeCtrl.reset();
    setState(() {
      _step = _Step.tiles;
      _tilesShown = 0;
      _tilesLit = 0;
      _letterStarsTapped.clear();
      _tilesPlayable = false;
      _nextTileToTap = 0;
    });
    _revealTilesSequentially();
  }

  /// Reveals each tile one-by-one: bounce in → play audio → light up → next.
  Future<void> _revealTilesSequentially() async {
    await Future.delayed(const Duration(milliseconds: 350));
    final letters = _kWords[_wordIndex].letters;
    for (int i = 0; i < letters.length; i++) {
      if (!mounted) return;
      // Bounce tile in AND start audio simultaneously
      _tileControllers[i].forward();
      setState(() => _tilesShown = i + 1);
      await _playAndWait(letters[i].audioPath);
      if (!mounted) return;
      // Light up this tile after its audio finishes
      setState(() => _tilesLit = i + 1);
      if (i < letters.length - 1) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }
    // All letters revealed — start interactive phase, shake first target
    if (!mounted) return;
    setState(() => _tilesPlayable = true);
    _tileShakeCtrl.repeat(reverse: true);
  }

  void _enterEcho() {
    setState(() {
      _step = _Step.echo;
      _echoPhase = _EchoPhase.idle;
      _echoScorePoints = 0;
      _echoShowButtons = false;
      _echoRecordStart = null;
      _recordingPath = null;
    });
    _echoPulseCtrl.stop();
    _echoPulseCtrl.reset();
    _echoPulseCtrl.repeat(reverse: true);
  }

  void _updateWave() {
    if (!mounted) return;
    setState(() {
      for (int i = 0; i < _barHeights.length; i++) {
        _barHeights[i] = _barHeights[i] * 0.55 + (_rng.nextDouble() * 0.85 + 0.15) * 0.45;
      }
    });
  }

  Future<void> _toggleEchoRecording() async {
    if (_echoPhase == _EchoPhase.recording) {
      // ── STOP ──
      _echoPulseCtrl.stop();
      _waveCtrl.stop();
      final durationMs = _echoRecordStart == null ? 0
          : DateTime.now().difference(_echoRecordStart!).inMilliseconds;
      final result = await _recorder.stop();
      _recordingPath = result ?? _recordingPath;
      for (int i = 0; i < _barHeights.length; i++) _barHeights[i] = 0.15;

      final int pts = durationMs >= 1000 ? 10 : durationMs >= 300 ? 5 : 0;
      setState(() {
        _echoPhase = _EchoPhase.scored;
        _echoScorePoints = pts;
        _echoShowButtons = false;
      });

      // Staggered stars
      final stars = pts == 10 ? 3 : pts == 5 ? 1 : 0;
      for (int i = 0; i < 3; i++) {
        _echoStarCtrls[i].reset();
        if (i < stars) {
          Future.delayed(Duration(milliseconds: 200 + i * 220), () {
            if (mounted) _echoStarCtrls[i].forward();
          });
        }
      }
      // Reward sound
      final audio = pts == 10 ? 'audio/phonemes/amazing.mp3' : 'audio/phonemes/one_more_time.mp3';
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _player.play(AssetSource(audio));
      });
      // Show buttons after 2 s
      Future.delayed(const Duration(milliseconds: 2000), () {
        if (mounted) setState(() => _echoShowButtons = true);
      });
    } else {
      // ── START ──
      try {
        if (!await _recorder.hasPermission()) return;
        final String path;
        if (kIsWeb) {
          path = 'phonics_echo.webm';
        } else {
          final dir = await getTemporaryDirectory();
          path = '${dir.path}/phonics_echo.m4a';
        }
        await _recorder.start(
          RecordConfig(
            encoder: kIsWeb ? AudioEncoder.opus : AudioEncoder.aacLc,
            bitRate: 128000,
          ),
          path: path,
        );
        _echoRecordStart = DateTime.now();
        _recordingPath = path;
        _echoPulseCtrl.repeat(reverse: true);
        _waveCtrl.repeat();
        setState(() => _echoPhase = _EchoPhase.recording);
        // Auto-stop after 6 s
        Future.delayed(const Duration(seconds: 6), () {
          if (mounted && _echoPhase == _EchoPhase.recording) _toggleEchoRecording();
        });
      } catch (_) {}
    }
  }

  Future<void> _playEchoRecording() async {
    if (_recordingPath == null) return;
    await _player.stop();
    final source = kIsWeb
        ? UrlSource(_recordingPath!)
        : DeviceFileSource(_recordingPath!);
    await _player.play(source);
  }

  void _onEchoConfirmed() {
    _addPoint();
    _addPoint();
    _enterDrag();
  }

  void _enterDrag() {
    final shuffled = [0, 1, 2]..shuffle(_rng);
    setState(() {
      _shuffledOrder = shuffled;
      _slots = [null, null, null];
      _placedLetters.clear();
      _step = _Step.drag;
    });
  }

  // ---------------------------------------------------------------------------
  // Word-tap feedback
  // ---------------------------------------------------------------------------

  void _onWordTap() {
    if (_wordSpeakerDone) return; // disabled after "You got it!"
    _speakerShakeCtrl.stop();
    _speakerShakeCtrl.reset();

    _wordMsgTimer?.cancel();
    final nextCount = _wordTapCount + 1;
    final youGotIt = nextCount >= 3;
    setState(() {
      _wordTapCount = nextCount;
      _tapStars = nextCount.clamp(0, 3);
      _isYouGotIt = youGotIt;
    });

    _playAudio(youGotIt ? 'assets/audio/phonemes/you_got_it.mp3' : _kEncouragement);
    _wordBubbleScale.forward(from: 0);
    _wordMsgController.forward(from: 0);

    if (youGotIt) {
      // "You got it!" bubble stays visible; show Sound it out after short delay
      _wordMsgTimer = Timer(const Duration(milliseconds: 700), () {
        if (!mounted) return;
        setState(() => _wordSpeakerDone = true);
        _soundItOutBounceCtrl.repeat();
      });
    } else {
      // "One more time!" fades after 1500 ms, then resume shake
      _wordMsgTimer = Timer(const Duration(milliseconds: 1500), () {
        if (!mounted) return;
        _wordMsgController.reverse().then((_) {
          if (!mounted) return;
          _wordBubbleScale.reset();
          _speakerShakeCtrl.repeat(reverse: true);
        });
      });
    }
  }

  Widget _buildFallingStars() => const SizedBox.shrink();

  Widget _buildWordStars() {
    return AnimatedBuilder(
      animation: _wordStarAnim,
      builder: (context, _) {
        final p = _wordStarAnim.value;
        return SizedBox(
          height: 56,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(3, (i) {
              final delay = i * 0.15;
              final t = ((p - delay) / (1.0 - delay)).clamp(0.0, 1.0);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Transform.translate(
                  offset: Offset(0, -24 * t),
                  child: Opacity(
                    opacity: t * (1.0 - p * 0.6).clamp(0.0, 1.0),
                    child: Transform.scale(
                      scale: 0.2 + t * 0.8,
                      child:
                          const Text('⭐', style: TextStyle(fontSize: 34)),
                    ),
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Scoring
  // ---------------------------------------------------------------------------

  void _addPoint() {
    setState(() => _score++);
    _plusOneCtrl.forward(from: 0);
  }

  // ---------------------------------------------------------------------------
  // Tiles step — letter tap with star reward
  // ---------------------------------------------------------------------------

  void _onLetterTileTap(int index) {
    if (!_tilesPlayable) return;
    if (index != _nextTileToTap) return; // enforce sequential order
    if (_letterStarsTapped.contains(index)) return;

    _playAudio(_kWords[_wordIndex].letters[index].audioPath);
    _tileShakeCtrl.stop();
    _tileShakeCtrl.reset();

    final letters = _kWords[_wordIndex].letters;
    setState(() {
      _letterStarsTapped.add(index);
      _nextTileToTap = index + 1;
    });
    _addPoint();

    if (index < letters.length - 1) {
      // Shake the next tile after a short delay
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) _tileShakeCtrl.repeat(reverse: true);
      });
    } else {
      // All done — play full word audio then auto-enter echo
      _tileShakeCtrl.stop();
      Future.delayed(const Duration(milliseconds: 400), () async {
        if (!mounted) return;
        await _playAndWait(_kWords[_wordIndex].wordAudioPath);
        if (mounted) _enterEcho();
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Drag logic
  // ---------------------------------------------------------------------------

  void _onLetterDropped(int slotIndex, int letterIndex) {
    if (_slots[slotIndex] != null) return;

    if (letterIndex != slotIndex) {
      // Wrong slot — show sad face briefly and play oops
      _playAudio(_kOops);
      _sadFaceTimer?.cancel();
      setState(() => _slotSad[slotIndex] = true);
      _sadFaceTimer = Timer(const Duration(milliseconds: 900), () {
        if (mounted) setState(() => _slotSad[slotIndex] = false);
      });
      return;
    }

    // Correct placement — pop animation + bingo
    setState(() {
      _slots[slotIndex] = letterIndex;
      _placedLetters.add(letterIndex);
    });
    _slotControllers[slotIndex].forward(from: 0);
    _addPoint();

    if (_placedLetters.length == 3) {
      _playAndWait(_kBingo).then((_) {
        if (mounted) _onAllCorrect();
      });
    } else {
      _playAudio(_kBingo);
    }
  }

  Future<void> _onAllCorrect() async {
    setState(() => _wordComplete = true);
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    _playAudio('assets/audio/phonemes/amazing.mp3');
    _starController.forward(from: 0);
    setState(() => _showAmazing = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _showNextBtn = true);
  }

  void _onNextPressed() {
    if (_wordIndex < _kWords.length - 1) {
      setState(() {
        _wordIndex++;
        _celebration = false;
      });
      _enterIntro();
    } else {
      setState(() => _celebration = true);
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_celebration) return _buildCelebration();

    final word = _kWords[_wordIndex];

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── BACKGROUND: white base + full-screen book image ─────────────
          Container(color: Colors.white),
          Image.asset(
            word.bookImage,
            fit: BoxFit.cover,
            alignment: Alignment.centerLeft,
          ),

          // ── Back button ──────────────────────────────────────────────────
          Positioned(
            left: 8,
            top: MediaQuery.of(context).padding.top + 4,
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios_rounded,
                  color: _kOrange, size: 26),
              onPressed: () => Navigator.pop(context),
            ),
          ),

          // ── RIGHT HALF: semi-transparent game panel ──────────────────────
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            width: MediaQuery.of(context).size.width / 2,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.92),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(32),
                  bottomLeft: Radius.circular(32),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 24,
                    offset: const Offset(-4, 0),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(32),
                  bottomLeft: Radius.circular(32),
                ),
                child: _buildGameArea(word),
              ),
            ),
          ),

          // ── SCORE CHIP — on top of the right panel ───────────────────────
          Positioned(
            top: 12,
            right: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _kOrange,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                      color: _kOrange.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 3)),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('⭐', style: TextStyle(fontSize: 14)),
                  const SizedBox(width: 4),
                  Text(
                    '$_score',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── +1 FLOAT ANIMATION ───────────────────────────────────────────
          AnimatedBuilder(
            animation: _plusOneCtrl,
            builder: (_, __) {
              final p = _plusOneCtrl.value;
              if (p == 0.0 || p == 1.0) return const SizedBox.shrink();
              final opacity = sin(p * pi).clamp(0.0, 1.0);
              return Positioned(
                top: 52 - p * 38,
                right: 22,
                child: Opacity(
                  opacity: opacity,
                  child: const Text(
                    '+1',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _kOrange,
                      shadows: [
                        Shadow(
                            color: Colors.black26,
                            blurRadius: 4,
                            offset: Offset(0, 2)),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildGameArea(_WordData word) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (!_wordComplete) ...[
          if (_step == _Step.intro) _buildIntroStep(word),
          if (_step == _Step.tiles) _buildTilesStep(word),
          if (_step == _Step.echo) _buildEchoStep(word),
          if (_step == _Step.drag) _buildDragStep(word),
        ],
        if (_wordComplete) _buildCompletionOverlay(),
        // Falling stars — shown on "You got it!" in intro step
        _buildFallingStars(),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Step 1 — Intro
  // ---------------------------------------------------------------------------

  Widget _buildIntroStep(_WordData word) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              "Today's word",
              style: TextStyle(fontSize: 18, color: Color(0xFF999999)),
            ),
            const Text(
              '今天的单词',
              style: TextStyle(fontSize: 16, color: Color(0xFFBBBBBB)),
            ),
            const SizedBox(height: 36),

            // Word card — bubble overlaid at top-right of speaker icon
            GestureDetector(
              onTap: _onWordTap,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 32, vertical: 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: _kOrange.withValues(alpha: 0.25),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      word.word,
                      style: const TextStyle(
                        fontSize: 72,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF333333),
                        letterSpacing: 6,
                      ),
                    ),
                    const SizedBox(width: 14),
                    // Speaker icon with shake animation + bubble overlay
                    AnimatedBuilder(
                      animation: _speakerShakeCtrl,
                      builder: (context, child) => Transform.translate(
                        offset: Offset(_speakerShakeAnim.value * 6, 0),
                        child: child,
                      ),
                      child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        const Icon(Icons.volume_up_rounded,
                            size: 38, color: _kOrange),
                        Positioned(
                          left: 0,
                          bottom: 44,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              ScaleTransition(
                                scale: _wordBubbleScaleAnim,
                                alignment: Alignment.bottomLeft,
                                child: FadeTransition(
                                  opacity: _wordMsgController,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFD93D),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      _isYouGotIt
                                          ? 'You got it!'
                                          : 'One more time!',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    ), // AnimatedBuilder
                    const SizedBox(width: 10),
                    // Stars to the right of the speaker, one per tap
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(3, (i) => AnimatedScale(
                        scale: i < _tapStars ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.elasticOut,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 3),
                          child: Text('⭐', style: TextStyle(fontSize: 28)),
                        ),
                      )),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 48),

            AnimatedBuilder(
              animation: _soundItOutBounceCtrl,
              builder: (context, child) => Transform.scale(
                scale: _soundItOutBounceAnim.value,
                child: child,
              ),
              child: AnimatedOpacity(
                opacity: _wordSpeakerDone ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 500),
                child: SizedBox(
                  height: 64,
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _wordSpeakerDone ? _enterTiles : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kOrange,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(32)),
                      textStyle: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    child: const Text('Sound it out! →'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Step 2 — Letter tiles
  // ---------------------------------------------------------------------------

  Widget _buildTilesStep(_WordData word) {
    final allTapped = _letterStarsTapped.length == 3;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Tap each letter!',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF555555)),
            ),
            const Text(
              '点击每个字母听发音',
              style: TextStyle(fontSize: 15, color: Color(0xFFAAAAAA)),
            ),
            const SizedBox(height: 44),

            // Letter tiles with star above each tapped tile
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(3, (i) {
                if (i >= _tilesShown) {
                  return const SizedBox(width: 112, height: 130);
                }
                final letter = word.letters[i];
                final tapped = _letterStarsTapped.contains(i);
                final isCurrentTarget =
                    _tilesPlayable && i == _nextTileToTap && !tapped;

                // Opacity logic:
                // During reveal: lit tiles bright, unrevealed dim
                // During interactive phase: tapped/target bright, future dim
                double opacity;
                if (!_tilesPlayable) {
                  opacity = i < _tilesLit ? 1.0 : 0.55;
                } else if (tapped) {
                  opacity = 1.0;
                } else if (i == _nextTileToTap) {
                  opacity = 1.0;
                } else {
                  opacity = 0.40;
                }

                Widget tileBtn = GestureDetector(
                  onTap: isCurrentTarget ? () => _onLetterTileTap(i) : null,
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: letter.tileColor,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: letter.tileColor.withValues(alpha: 0.45),
                          blurRadius: 14,
                          offset: const Offset(0, 7),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      letter.char,
                      style: const TextStyle(
                        fontSize: 56,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                );

                // Shake only the current target tile
                if (isCurrentTarget) {
                  tileBtn = AnimatedBuilder(
                    animation: _tileShakeCtrl,
                    builder: (context, child) => Transform.translate(
                      offset: Offset(_tileShakeAnim.value * 5, 0),
                      child: child,
                    ),
                    child: tileBtn,
                  );
                }

                return AnimatedOpacity(
                  opacity: opacity,
                  duration: const Duration(milliseconds: 400),
                  child: ScaleTransition(
                    scale: _tileScaleAnims[i],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Star reward — visible once tapped
                          AnimatedOpacity(
                            opacity: tapped ? 1.0 : 0.0,
                            duration: const Duration(milliseconds: 350),
                            child: const Text('⭐',
                                style: TextStyle(fontSize: 28)),
                          ),
                          const SizedBox(height: 6),
                          tileBtn,
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),

          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Step 3 — Echo (record & repeat)
  // ---------------------------------------------------------------------------

  Widget _buildEchoStep(_WordData word) {
    final isRecording = _echoPhase == _EchoPhase.recording;
    final isScored    = _echoPhase == _EchoPhase.scored;
    final starCount   = _echoScorePoints == 10 ? 3 : _echoScorePoints == 5 ? 1 : 0;

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
          // ── Title ────────────────────────────────────────────────────────
          const Text('Your turn! 🎤',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800,
                  color: Color(0xFF444444))),
          const SizedBox(height: 6),
          const Text('跟着读：b · e · d · bed',
              style: TextStyle(fontSize: 16, color: Color(0xFFAAAAAA))),
          const SizedBox(height: 28),

          // ── Word tiles card ───────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [BoxShadow(color: _kOrange.withValues(alpha: 0.18),
                  blurRadius: 18, offset: const Offset(0, 6))],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ...word.letters.map((l) => Container(
                      width: 68, height: 68,
                      margin: const EdgeInsets.symmetric(horizontal: 5),
                      decoration: BoxDecoration(color: l.tileColor,
                          borderRadius: BorderRadius.circular(14)),
                      alignment: Alignment.center,
                      child: Text(l.char, style: const TextStyle(
                          fontSize: 40, fontWeight: FontWeight.bold,
                          color: Colors.white)),
                    )),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Text('→', style: TextStyle(fontSize: 28,
                      color: Color(0xFFCCCCCC))),
                ),
                Text(word.word, style: const TextStyle(fontSize: 44,
                    fontWeight: FontWeight.bold, color: Color(0xFF333333))),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // ── Scored: stars + message + play back ──────────────────────────
          if (isScored) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(3, (i) {
                final lit = i < starCount;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: ScaleTransition(
                    scale: _echoStarAnims[i],
                    child: Text(lit ? '⭐' : '☆',
                        style: TextStyle(fontSize: 62,
                            color: lit ? null : Colors.grey.shade300)),
                  ),
                );
              }),
            ),
            const SizedBox(height: 16),
            Text(
              _echoScorePoints == 10 ? 'Amazing! 🎉'
                  : _echoScorePoints == 5 ? 'Good try! Keep going!'
                  : 'Try speaking! 💪',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold,
                  color: _echoScorePoints == 10 ? _kOrange : Colors.blueGrey),
            ),
            const SizedBox(height: 24),
            if (_recordingPath != null)
              GestureDetector(
                onTap: _playEchoRecording,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 28, vertical: 16),
                  decoration: BoxDecoration(
                    color: _kYellow.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: _kYellow, width: 2.5),
                  ),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.replay_rounded,
                        color: Color(0xFF664400), size: 24),
                    SizedBox(width: 10),
                    Text('Play back', style: TextStyle(fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF664400))),
                  ]),
                ),
              ),
            const SizedBox(height: 28),
          ] else ...[
            // ── Waveform while recording ───────────────────────────────────
            SizedBox(
              height: 60,
              child: isRecording
                  ? AnimatedBuilder(
                      animation: _waveCtrl,
                      builder: (_, __) => Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: List.generate(_barHeights.length, (i) =>
                          Container(
                            width: 5,
                            height: 60 * _barHeights[i].clamp(0.1, 1.0),
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          )),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            // ── REC dot ───────────────────────────────────────────────────
            SizedBox(
              height: 24,
              child: isRecording
                  ? AnimatedBuilder(
                      animation: _recDotCtrl,
                      builder: (_, __) => Opacity(
                        opacity: _recDotCtrl.value,
                        child: const Row(mainAxisSize: MainAxisSize.min,
                            children: [
                          Icon(Icons.circle, color: Colors.red, size: 14),
                          SizedBox(width: 6),
                          Text('REC', style: TextStyle(fontSize: 14,
                              fontWeight: FontWeight.bold, color: Colors.red,
                              letterSpacing: 2)),
                        ]),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(height: 20),
            // ── Mic button ─────────────────────────────────────────────────
            AnimatedBuilder(
              animation: _echoPulseCtrl,
              builder: (_, child) => Transform.scale(
                scale: isRecording ? 1.0 : _echoPulseAnim.value,
                child: child,
              ),
              child: GestureDetector(
                onTap: _toggleEchoRecording,
                child: Container(
                  width: 110, height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isRecording ? Colors.red : _kOrange,
                    boxShadow: [BoxShadow(
                      color: (isRecording ? Colors.red : _kOrange)
                          .withValues(alpha: 0.45),
                      blurRadius: 24, offset: const Offset(0, 8),
                    )],
                  ),
                  child: Icon(
                    isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                    color: Colors.white, size: 54,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              isRecording ? 'Tap to stop' : 'Tap to record',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 28),
          ],

          // ── Continue button ───────────────────────────────────────────────
          AnimatedOpacity(
            opacity: _echoShowButtons ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 400),
            child: SizedBox(
              height: 64, width: double.infinity,
              child: ElevatedButton(
                onPressed: _echoShowButtons ? _onEchoConfirmed : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kOrange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(32)),
                  textStyle: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold),
                ),
                child: const Text("Let's spell it! →"),
              ),
            ),
          ),
        ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Step 4 — Drag to spell
  // ---------------------------------------------------------------------------

  Widget _buildDragStep(_WordData word) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Drag to spell the word!',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF555555)),
            ),
            const Text(
              '拖动字母拼出单词',
              style: TextStyle(fontSize: 15, color: Color(0xFFAAAAAA)),
            ),
            const SizedBox(height: 40),

            // Drop slots (centered)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children:
                  List.generate(3, (i) => _buildDropSlot(word, i)),
            ),

            const SizedBox(height: 52),

            // Draggable letter cards (centered, shuffled)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: _shuffledOrder.map((letterIdx) {
                if (_placedLetters.contains(letterIdx)) {
                  return const SizedBox(width: 112, height: 96);
                }
                return _buildDraggableLetter(word, letterIdx);
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropSlot(_WordData word, int slotIndex) {
    final placedIdx = _slots[slotIndex];
    final isFilled = placedIdx != null;
    final isSad = _slotSad[slotIndex];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: DragTarget<int>(
        onWillAcceptWithDetails: (details) => !isFilled,
        onAcceptWithDetails: (details) =>
            _onLetterDropped(slotIndex, details.data),
        builder: (context, candidateData, _) {
          final isHovering = candidateData.isNotEmpty;
          return ScaleTransition(
            scale: _slotScaleAnims[slotIndex],
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: isFilled
                        ? word.letters[placedIdx].tileColor
                        : isSad
                            ? Colors.red.withValues(alpha: 0.12)
                            : isHovering
                                ? _kYellow.withValues(alpha: 0.35)
                                : Colors.white.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(20),
                    border: isFilled
                        ? null
                        : Border.all(
                            color: isSad
                                ? Colors.red.withValues(alpha: 0.5)
                                : isHovering
                                    ? _kOrange
                                    : const Color(0xFFDDDDDD),
                            width: 2.5,
                          ),
                    boxShadow: isFilled
                        ? [
                            BoxShadow(
                              color: word.letters[placedIdx].tileColor
                                  .withValues(alpha: 0.4),
                              blurRadius: 14,
                              offset: const Offset(0, 6),
                            ),
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: isFilled
                      ? Text(
                          word.letters[placedIdx].char,
                          style: const TextStyle(
                            fontSize: 56,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        )
                      : isSad
                          ? const Text('😢',
                              style: TextStyle(fontSize: 36))
                          : Icon(
                              Icons.add_rounded,
                              size: 34,
                              color: isHovering
                                  ? _kOrange
                                  : const Color(0xFFCCCCCC),
                            ),
                ),
                // Gold star badge on correct placement
                if (isFilled)
                  Positioned(
                    top: -14,
                    right: -14,
                    child: AnimatedOpacity(
                      opacity: 1.0,
                      duration: const Duration(milliseconds: 300),
                      child: const Text('⭐',
                          style: TextStyle(fontSize: 26)),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDraggableLetter(_WordData word, int letterIndex) {
    final letter = word.letters[letterIndex];

    Widget tile({double opacity = 1.0}) => Opacity(
          opacity: opacity,
          child: Container(
            width: 96,
            height: 96,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: letter.tileColor,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: letter.tileColor.withValues(alpha: 0.45),
                  blurRadius: 14,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              letter.char,
              style: const TextStyle(
                fontSize: 56,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        );

    return Draggable<int>(
      data: letterIndex,
      feedback: Material(
        color: Colors.transparent,
        child: Transform.scale(scale: 1.12, child: tile()),
      ),
      childWhenDragging: tile(opacity: 0.28),
      child: tile(),
    );
  }

  // ---------------------------------------------------------------------------
  // Completion overlay
  // ---------------------------------------------------------------------------

  Widget _buildCompletionOverlay() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: Colors.white.withValues(alpha: 0.88)),
        _buildStarBurst(),
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedOpacity(
                opacity: _showAmazing ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 450),
                child: Column(
                  children: [
                    const Text(
                      'Amazing!',
                      style: TextStyle(
                        fontSize: 52,
                        fontWeight: FontWeight.bold,
                        color: _kOrange,
                        shadows: [
                          Shadow(
                              color: Colors.black12,
                              blurRadius: 12,
                              offset: Offset(0, 4)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '太棒了！',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF777777),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 28, vertical: 14),
                      decoration: BoxDecoration(
                        color: _kOrange.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                            color: _kOrange.withValues(alpha: 0.28),
                            width: 1.5),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('⭐',
                              style: TextStyle(fontSize: 26)),
                          const SizedBox(width: 10),
                          Text(
                            '$_score  stars',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: _kOrange,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              AnimatedOpacity(
                opacity: _showNextBtn ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 400),
                child: SizedBox(
                  height: 64,
                  width: 280,
                  child: ElevatedButton(
                    onPressed: _showNextBtn ? _onNextPressed : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kOrange,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(32)),
                      textStyle: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    child: Text(
                      _wordIndex >= _kWords.length - 1
                          ? 'Finish! 🎉'
                          : 'Next word! →',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStarBurst() {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _starAnim,
        builder: (context, _) {
          final p = _starAnim.value;
          return Stack(
            fit: StackFit.expand,
            children: List.generate(14, (i) {
              final angle = (i / 14) * 2 * pi;
              final opacity = (1.0 - p * 0.85).clamp(0.0, 1.0);
              return Align(
                alignment: Alignment(
                  cos(angle) * p * 1.15,
                  sin(angle) * p * 1.15,
                ),
                child: Opacity(
                  opacity: opacity,
                  child: Transform.scale(
                    scale: 0.2 + p * 0.9,
                    child:
                        const Text('⭐', style: TextStyle(fontSize: 38)),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Celebration screen (both words done)
  // ---------------------------------------------------------------------------

  Widget _buildCelebration() {
    return Scaffold(
      backgroundColor: _kCream,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('🎊', style: TextStyle(fontSize: 90)),
              const SizedBox(height: 28),
              const Text(
                'You did it!',
                style: TextStyle(
                    fontSize: 52,
                    fontWeight: FontWeight.bold,
                    color: _kOrange),
              ),
              const SizedBox(height: 10),
              const Text(
                '你学会了两个新单词！',
                style: TextStyle(fontSize: 22, color: Color(0xFF777777)),
              ),
              const SizedBox(height: 28),
              const Text(
                'bed  •  hug',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF333333),
                  letterSpacing: 8,
                ),
              ),
              const SizedBox(height: 28),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 36, vertical: 20),
                decoration: BoxDecoration(
                  color: _kOrange.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                      color: _kOrange.withValues(alpha: 0.28), width: 1.5),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('⭐⭐⭐',
                        style: TextStyle(fontSize: 36)),
                    const SizedBox(height: 8),
                    Text(
                      '$_score  stars!',
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        color: _kOrange,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'out of ${_kWords.length * 6} total',
                      style: const TextStyle(
                        fontSize: 15,
                        color: Color(0xFFAAAAAA),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                height: 64,
                width: 280,
                child: ElevatedButton(
                  onPressed: () async {
                    await ProgressService.markModuleComplete('phonics', 15);
                    if (mounted) Navigator.pushReplacementNamed(context, '/recording');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kOrange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(32)),
                    textStyle: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  child: const Text('回到首页  🏠'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
