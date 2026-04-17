import 'dart:async';
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../utils/safe_audio_player.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../services/progress_service.dart';
import '../services/lesson_service.dart';
import '../models/lesson.dart';
import 'eggy_celebration_screen.dart';
import '../utils/cdn_asset.dart';
import '../utils/responsive_utils.dart';

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

// Vowel set for coloring
const _kVowels = {'a', 'e', 'i', 'o', 'u'};

/// Build _WordData list from lesson's PhonicsWords
/// All phoneme audio now comes from phonics_sounds/ (user-clipped from video)
List<_WordData> _buildWordsFromLesson(List<PhonicsWord> phonicsWords) {
  return phonicsWords.map((pw) {
    final letters = <_LetterInfo>[];
    for (int i = 0; i < pw.phonemes.length; i++) {
      final p = pw.phonemes[i];
      final isVowel = _kVowels.contains(p);
      final audioPath = 'assets/audio/phonics_sounds/$p.mp3';
      letters.add(_LetterInfo(p, isVowel ? _kYellow : _kOrange, audioPath));
    }
    return _WordData(
      word: pw.word,
      bookImage: pw.imageAsset,
      wordAudioPath: 'assets/audio/phonics_sounds/word_${pw.word}.mp3',
      letters: letters,
    );
  }).toList();
}

// Default fallback words
final List<_WordData> _kDefaultWords = [
  _WordData(
    word: 'bed',
    bookImage: 'assets/books/01Biscuit/spread_02.webp',
    wordAudioPath: 'assets/audio/phonics_sounds/word_bed.mp3',
    letters: const [
      _LetterInfo('b', _kOrange, 'assets/audio/phonics_sounds/b.mp3'),
      _LetterInfo('e', _kYellow, 'assets/audio/phonics_sounds/e.mp3'),
      _LetterInfo('d', _kOrange, 'assets/audio/phonics_sounds/d.mp3'),
    ],
  ),
  _WordData(
    word: 'hug',
    bookImage: 'assets/books/01Biscuit/spread_06.webp',
    wordAudioPath: 'assets/audio/phonics_sounds/word_hug.mp3',
    letters: const [
      _LetterInfo('h', _kOrange, 'assets/audio/phonics_sounds/h.mp3'),
      _LetterInfo('u', _kYellow, 'assets/audio/phonics_sounds/u.mp3'),
      _LetterInfo('g', _kOrange, 'assets/audio/phonics_sounds/g.mp3'),
    ],
  ),
];

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

enum _Step      { intro, tiles, echo, drag }
enum _EchoPhase { idle, recording, scored }

class PhonicsScreen extends StatefulWidget {
  final bool weekendMode;
  const PhonicsScreen({super.key, this.weekendMode = false});

  @override
  State<PhonicsScreen> createState() => _PhonicsScreenState();
}

class _PhonicsScreenState extends State<PhonicsScreen>
    with TickerProviderStateMixin {
  final SafeAudioPlayer _player = SafeAudioPlayer();
  final Random _rng = Random();

  // Intro step: word-speaker feedback
  static const _kPositive      = 'assets/audio/phonemes/you_got_it.mp3';
  static const _kEncouragement = 'assets/audio/phonemes/one_more_time.mp3';
  // Drag step: letter-placement feedback
  static const _kBingo = 'assets/audio/phonemes/bingo.mp3';
  static const _kOops  = 'assets/audio/phonemes/oops.mp3';

  List<_WordData> _words = _kDefaultWords;
  int _wordIndex = 0;
  int _revealId = 0; // incremented on each new word to cancel stale async reveals
  _Step _step = _Step.intro;
  bool _celebration = false;

  // Score
  int _score = 0;
  int _totalStars = 0;
  late final AnimationController _plusOneCtrl;

  // Step 2: staggered tile bounce-in
  late final List<AnimationController> _tileControllers;
  late final List<Animation<double>> _tileScaleAnims;
  int _tilesShown = 0; // how many tiles have started bounce-in
  int _tilesLit = 0;   // how many tiles have completed audio (are lit up)

  // Step 3: drag state
  List<int> _shuffledOrder = [0, 1, 2]; // will be resized in _enterDrag
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
  bool _echoPlayingBack  = false;
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
    _loadPhonicsData();
    ProgressService.getTodayProgress().then((p) {
      if (mounted) setState(() => _totalStars = (p['total_stars'] as int?) ?? 0);
    });

    // Create enough controllers for up to 5 phonemes (use first N as needed)
    _tileControllers = List.generate(
      5,
      (_) => AnimationController(
          vsync: this, duration: const Duration(milliseconds: 650)),
    );
    _tileScaleAnims = _tileControllers
        .map((c) => Tween<double>(begin: 0.0, end: 1.0).animate(
              CurvedAnimation(parent: c, curve: Curves.elasticOut),
            ))
        .toList();

    _slotControllers = List.generate(
      5,
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

    _enterTiles();
  }

  Future<void> _loadPhonicsData() async {
    final service = LessonService();
    final lessonId = await service.restoreCurrentLessonId();
    final lesson = await service.loadLesson(lessonId);
    if (lesson.phonicsWords.isNotEmpty && mounted) {
      setState(() {
        _words = _buildWordsFromLesson(lesson.phonicsWords);
      });
    }
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
    await _player.playAssetPath(assetPath);
  }

  /// Play audio and wait for it to finish before returning.
  Future<void> _playAndWait(String assetPath) async {
    if (!mounted) return;
    final completer = Completer<void>();
    late StreamSubscription<void> sub;
    sub = _player.onPlayerComplete.listen((_) {
      if (!completer.isCompleted) completer.complete();
      sub.cancel();
    });
    try {
      await _player.playAssetPath(assetPath);
      await completer.future.timeout(const Duration(seconds: 15), onTimeout: () {});
    } catch (_) {
      if (!completer.isCompleted) completer.complete();
    }
    sub.cancel();
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
      final _count = _words[_wordIndex].letters.length;
      _slots = List.filled(_count, null);
      _slotSad = List.filled(_count, false);
      _shuffledOrder = List.generate(_count, (i) => i);
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
      await _playAndWait(_words[_wordIndex].wordAudioPath);
      if (mounted && !_wordSpeakerDone) {
        _speakerShakeCtrl.repeat(reverse: true);
      }
    });
  }

  void _enterTiles() {
    for (final c in _tileControllers) c.reset();
    for (final c in _slotControllers) c.reset();
    _starController.reset();
    _tileShakeCtrl.stop();
    _tileShakeCtrl.reset();
    _soundItOutBounceCtrl.stop();
    _soundItOutBounceCtrl.reset();
    _wordMsgController.reset();
    _wordBubbleScale.reset();
    _echoPulseCtrl.stop();
    _echoPulseCtrl.reset();
    _waveCtrl.stop();
    for (final c in _echoStarCtrls) c.reset();
    setState(() {
      _step = _Step.tiles;
      _tilesShown = 0;
      _tilesLit = 0;
      _letterStarsTapped.clear();
      _tilesPlayable = false;
      _nextTileToTap = 0;
      _placedLetters.clear();
      final _count = _words[_wordIndex].letters.length;
      _slots = List.filled(_count, null);
      _slotSad = List.filled(_count, false);
      _shuffledOrder = List.generate(_count, (i) => i);
      _wordComplete = false;
      _showAmazing = false;
      _showNextBtn = false;
      _echoPhase = _EchoPhase.idle;
      _echoScorePoints = 0;
      _echoShowButtons = false;
      _echoPlayingBack = false;
      _echoRecordStart = null;
      _recordingPath = null;
    });
    _revealId++;
    _revealTilesSequentially(_revealId);
  }

  /// Reveals each tile one-by-one: bounce in → play audio → light up → next.
  Future<void> _revealTilesSequentially(int id) async {
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted || id != _revealId) return;
    final word = _words[_wordIndex];
    final letters = word.letters;

    // 1. Play full word first
    await _playAndWait(word.wordAudioPath);
    if (!mounted || id != _revealId) return;
    await Future.delayed(const Duration(milliseconds: 350));

    // 2. Reveal each letter tile with its phoneme audio (b → e → d)
    for (int i = 0; i < letters.length; i++) {
      if (!mounted || id != _revealId) return;
      _tileControllers[i].forward();
      setState(() => _tilesShown = i + 1);
      await _playAndWait(letters[i].audioPath);
      if (!mounted || id != _revealId) return;
      setState(() => _tilesLit = i + 1);
      if (i < letters.length - 1) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }

    // 3. Play full word again after all letters (pause to let last phoneme finish)
    if (!mounted) return;
    await Future.delayed(const Duration(milliseconds: 600));
    await _playAndWait(word.wordAudioPath);
    if (!mounted) return;

    // 4. Start interactive phase — shake first target tile
    setState(() => _tilesPlayable = true);
    _tileShakeCtrl.repeat(reverse: true);
  }

  void _enterEcho() {
    // Stay on tiles step — recording UI appears inline below the tiles
    setState(() {
      _echoPhase = _EchoPhase.idle;
      _echoScorePoints = 0;
      _echoShowButtons = false;
      _echoPlayingBack = false;
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

      // Auto-play the recording back, show buttons after playback finishes
      if (_recordingPath != null) {
        await Future.delayed(const Duration(milliseconds: 300));
        if (mounted) await _playEchoRecording();
      } else {
        if (mounted) setState(() => _echoShowButtons = true);
      }
    } else {
      // ── START ──
      try {
        if (!await _recorder.hasPermission()) return;
        final String path;
        if (kIsWeb) {
          path = 'phonics_echo.m4a';
        } else {
          final dir = await getTemporaryDirectory();
          path = '${dir.path}/phonics_echo.m4a';
        }
        await _recorder.start(
          RecordConfig(
            encoder: AudioEncoder.aacLc,
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

  StreamSubscription? _echoPlaybackSub;

  Future<void> _playEchoRecording() async {
    if (_recordingPath == null || _echoPlayingBack) return;
    setState(() => _echoPlayingBack = true);
    _echoPlaybackSub?.cancel();
    await _player.stop();
    final completer = Completer<void>();
    // Recording playback: use a separate native player (not asset-based)
    final echoPlayer = AudioPlayer();
    final source = kIsWeb
        ? UrlSource(_recordingPath!)
        : DeviceFileSource(_recordingPath!);
    _echoPlaybackSub = echoPlayer.onPlayerComplete.listen((_) {
      _echoPlaybackSub?.cancel();
      echoPlayer.dispose();
      if (!completer.isCompleted) completer.complete();
    });
    try {
      await echoPlayer.play(source);
    } catch (_) {
      echoPlayer.dispose();
      // Web may fail to play back recording
      if (!completer.isCompleted) completer.complete();
    }
    // Wait for playback to actually finish
    await completer.future.timeout(const Duration(seconds: 5), onTimeout: () {});
    // Keep ear icon visible briefly after sound ends
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) setState(() {
      _echoPlayingBack = false;
      _echoShowButtons = true;
    });
  }

  void _onEchoConfirmed() {
    _addPoint();
    _addPoint();
    _enterDrag();
  }

  void _enterDrag() {
    final count = _words[_wordIndex].letters.length;
    final shuffled = List.generate(count, (i) => i)..shuffle(_rng);
    setState(() {
      _shuffledOrder = shuffled;
      _slots = List.filled(count, null);
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

    _playAudio(_words[_wordIndex].letters[index].audioPath);
    _tileShakeCtrl.stop();
    _tileShakeCtrl.reset();

    final letters = _words[_wordIndex].letters;
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
      // All done — wait for last letter audio to finish, then play full word
      _tileShakeCtrl.stop();
      Future.delayed(const Duration(milliseconds: 1000), () async {
        if (!mounted) return;
        await _playAndWait(_words[_wordIndex].wordAudioPath);
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

    if (_placedLetters.length == _words[_wordIndex].letters.length) {
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

    final isLastWord = _wordIndex == _words.length - 1;

    if (isLastWord) {
      if (widget.weekendMode) {
        if (mounted) { if (Navigator.canPop(context)) { Navigator.pop(context); } else { Navigator.pushReplacementNamed(context, '/study'); } }
        return;
      }
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const EggyCelebrationScreen(
            nextRoute:    '/recording',
            nextLabel:    'Say it! 🎙️',
            moduleKey:    'phonics',
            modulePoints: 15,
          ),
        ),
      );
    } else {
      // Not the last word — go directly to next word
      _onNextPressed();
    }
  }

  void _onNextPressed() {
    if (_wordIndex < _words.length - 1) {
      setState(() {
        _wordIndex++;
        _celebration = false;
        // Reset arrays immediately to match new word length (prevents RangeError in build)
        final count = _words[_wordIndex].letters.length;
        _slots = List.filled(count, null);
        _slotSad = List.filled(count, false);
        _shuffledOrder = List.generate(count, (i) => i);
        _placedLetters.clear();
        _tilesShown = 0;
        _tilesLit = 0;
        _letterStarsTapped.clear();
        _nextTileToTap = 0;
        _wordComplete = false;
        _showAmazing = false;
        _showNextBtn = false;
      });
      _enterTiles();
    } else {
      // Navigate to Eggy celebration screen instead of showing inline widget
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const EggyCelebrationScreen(
            nextRoute:    '/recording',
            nextLabel:    'Say it! 🎙️',
            moduleKey:    'phonics',
            modulePoints: 15,
          ),
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final word = _words[_wordIndex];

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── BACKGROUND ─────────────────────────────────────────────────
          Container(color: Colors.white),

          // ── Back button ──────────────────────────────────────────────────
          Positioned(
            left: 8,
            top: MediaQuery.of(context).padding.top + 4,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.25),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.arrow_back_ios_rounded,
                    color: _kOrange, size: 22),
                onPressed: () { if (Navigator.canPop(context)) { Navigator.pop(context); } else { Navigator.pushReplacementNamed(context, '/study'); } },
              ),
            ),
          ),

          // ── CENTER: full-width game panel ───────────────────────────────
          Positioned.fill(
            child: _buildGameArea(word),
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
                    '$_totalStars',
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
    final allTapped = _letterStarsTapped.length == _words[_wordIndex].letters.length;
    final isRecording = _echoPhase == _EchoPhase.recording;
    final isScored    = _echoPhase == _EchoPhase.scored;
    final starCount   = _echoScorePoints == 10 ? 3 : _echoScorePoints == 5 ? 1 : 0;

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight - 40),
        child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.03),
          // Word display with speaker
          GestureDetector(
            onTap: () => _playAudio(word.wordAudioPath),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(word.word,
                    style: TextStyle(fontSize: R.s(52), fontWeight: FontWeight.bold,
                        color: const Color(0xFF333333), letterSpacing: 4)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Subtitle — always occupies space, text changes
          AnimatedOpacity(
            opacity: 1.0,
            duration: const Duration(milliseconds: 300),
            child: Text(
              allTapped ? 'Your turn! 🎤' : 'Tap each letter!',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                  color: Color(0xFF555555)),
            ),
          ),
          // Chinese hint — always occupies space, fades out when done
          AnimatedOpacity(
            opacity: allTapped ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 300),
            child: const Text('点击每个字母听发音',
                style: TextStyle(fontSize: 14, color: Color(0xFFAAAAAA))),
          ),
          const SizedBox(height: 16),

          // Letter tiles — always rendered with fixed size slots
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(word.letters.length, (i) {
              final letter = word.letters[i];
              final tapped = _letterStarsTapped.contains(i);
              final isCurrentTarget = _tilesPlayable && i == _nextTileToTap && !tapped;
              final shown = i < _tilesShown;

              double tileOpacity;
              if (!shown) {
                tileOpacity = 0.0;
              } else if (!_tilesPlayable) {
                tileOpacity = i < _tilesLit ? 1.0 : 0.55;
              } else if (tapped || allTapped) {
                tileOpacity = 1.0;
              } else if (i == _nextTileToTap) {
                tileOpacity = 1.0;
              } else {
                tileOpacity = 0.40;
              }

              Widget tileBtn = GestureDetector(
                onTap: (isCurrentTarget && shown) ? () => _onLetterTileTap(i) : null,
                child: Container(
                  width: R.s(96), height: R.s(96),
                  decoration: BoxDecoration(
                    color: letter.tileColor,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(
                      color: letter.tileColor.withValues(alpha: 0.45),
                      blurRadius: 14, offset: const Offset(0, 7),
                    )],
                  ),
                  alignment: Alignment.center,
                  child: Text(letter.char, style: TextStyle(
                      fontSize: R.s(56), fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              );

              if (isCurrentTarget && shown) {
                tileBtn = AnimatedBuilder(
                  animation: _tileShakeCtrl,
                  builder: (context, child) => Transform.translate(
                      offset: Offset(_tileShakeAnim.value * 5, 0), child: child),
                  child: tileBtn,
                );
              }

              return AnimatedOpacity(
                opacity: tileOpacity,
                duration: const Duration(milliseconds: 400),
                child: ScaleTransition(
                  scale: _tileScaleAnims[i],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      AnimatedOpacity(
                        opacity: tapped ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 350),
                        child: const Text('⭐', style: TextStyle(fontSize: 28)),
                      ),
                      const SizedBox(height: 9),
                      tileBtn,
                    ]),
                  ),
                ),
              );
            }),
          ),

          // ── Recording / scored section — shared space via Stack ────────────
          const SizedBox(height: 20),

          // Fixed-height area: mic/recording OR scored buttons share this space
          SizedBox(
            height: R.s(320),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // ── Recording state: REC dot + waveform + stop button ────
                AnimatedOpacity(
                  opacity: (allTapped && isRecording) ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: IgnorePointer(
                    ignoring: !isRecording,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedBuilder(
                          animation: _recDotCtrl,
                          builder: (_, __) => Opacity(
                            opacity: isRecording ? _recDotCtrl.value : 0.0,
                            child: const Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.circle, color: Colors.red, size: 16),
                              SizedBox(width: 8),
                              Text('REC', style: TextStyle(fontSize: 18,
                                  fontWeight: FontWeight.bold, color: Colors.red, letterSpacing: 3)),
                            ]),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 56,
                          child: AnimatedBuilder(
                            animation: _waveCtrl,
                            builder: (_, __) => Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: List.generate(_barHeights.length, (i) => Container(
                                width: 5,
                                height: _barHeights[i] * 52,
                                margin: const EdgeInsets.symmetric(horizontal: 2),
                                decoration: BoxDecoration(
                                  color: Colors.red.withValues(alpha: 0.5 + _barHeights[i] * 0.5),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              )),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        GestureDetector(
                          onTap: _toggleEchoRecording,
                          child: AnimatedBuilder(
                            animation: _echoPulseCtrl,
                            builder: (_, child) => Transform.scale(
                              scale: _echoPulseAnim.value,
                              child: child,
                            ),
                            child: Container(
                              width: R.s(120), height: R.s(120),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFFCC0000),
                                boxShadow: [BoxShadow(
                                  color: Colors.red.withValues(alpha: 0.55),
                                  blurRadius: 28, spreadRadius: 6,
                                )],
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.stop_rounded, color: Colors.white, size: R.s(50)),
                                  SizedBox(height: 4),
                                  Text('Stop', style: TextStyle(color: Colors.white,
                                      fontSize: 14, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Idle state: mic button ───────────────────────────────
                AnimatedOpacity(
                  opacity: (allTapped && !isScored && !isRecording) ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: IgnorePointer(
                    ignoring: !allTapped || isScored || isRecording,
                    child: GestureDetector(
                      onTap: _toggleEchoRecording,
                      child: Container(
                        width: R.s(120), height: R.s(120),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.red,
                          boxShadow: [BoxShadow(
                            color: Colors.red.withValues(alpha: 0.30),
                            blurRadius: 16, spreadRadius: 2,
                            offset: const Offset(0, 5),
                          )],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.mic_rounded, color: Colors.white, size: R.s(50)),
                            SizedBox(height: 4),
                            Text('Record', style: TextStyle(color: Colors.white,
                                fontSize: 14, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // ── Scored state: Re-record + Let's spell it ─
                AnimatedOpacity(
                  opacity: isScored ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: IgnorePointer(
                    ignoring: !isScored,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!_echoShowButtons)
                          Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.hearing, size: R.s(48), color: const Color(0xFFFF8C42)),
                                SizedBox(height: R.s(6)),
                                Text('Listening...', style: TextStyle(
                                  fontSize: R.s(16), fontWeight: FontWeight.w700,
                                  color: const Color(0xFFFF8C42))),
                              ],
                            ),
                        if (_echoShowButtons) ...[
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _echoPhase = _EchoPhase.idle;
                                _echoScorePoints = 0;
                                _echoShowButtons = false;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.mic, color: Color(0xFF666666), size: 22),
                                SizedBox(width: 8),
                                Text('Re-record', style: TextStyle(fontSize: 18,
                                    fontWeight: FontWeight.bold, color: Color(0xFF666666))),
                              ]),
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        AnimatedOpacity(
                          opacity: _echoShowButtons ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 300),
                          child: SizedBox(
                            height: R.s(56),
                            width: R.s(260),
                            child: ElevatedButton(
                              onPressed: _echoShowButtons ? _onEchoConfirmed : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _kOrange,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(32)),
                                textStyle: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              child: const Text("Let's spell it!"),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        ),
      ),
    ));
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
                      width: R.s(68), height: R.s(68),
                      margin: const EdgeInsets.symmetric(horizontal: 5),
                      decoration: BoxDecoration(color: l.tileColor,
                          borderRadius: BorderRadius.circular(14)),
                      alignment: Alignment.center,
                      child: Text(l.char, style: TextStyle(
                          fontSize: R.s(40), fontWeight: FontWeight.bold,
                          color: Colors.white)),
                    )),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Text('→', style: TextStyle(fontSize: 28,
                      color: Color(0xFFCCCCCC))),
                ),
                Text(word.word, style: TextStyle(fontSize: R.s(44),
                    fontWeight: FontWeight.bold, color: const Color(0xFF333333))),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // ── Scored: re-record + let's spell it ──────────────────────────
          if (isScored && _echoShowButtons) ...[
            // Re-record button
            GestureDetector(
              onTap: () {
                setState(() {
                  _echoPhase = _EchoPhase.idle;
                  _echoScorePoints = 0;
                  _recordingPath = null;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.mic, color: Color(0xFF666666), size: 22),
                  SizedBox(width: 8),
                  Text('Re-record', style: TextStyle(fontSize: 18,
                      fontWeight: FontWeight.bold, color: Color(0xFF666666))),
                ]),
              ),
            ),
            const SizedBox(height: 28),
          ] else if (isScored) ...[
            // While auto-playing back, show a small indicator
            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.hearing, size: R.s(48), color: const Color(0xFFFF8C42)),
                                SizedBox(height: R.s(6)),
                                Text('Listening...', style: TextStyle(
                                  fontSize: R.s(16), fontWeight: FontWeight.w700,
                                  color: const Color(0xFFFF8C42))),
                              ],
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
                  width: R.s(110), height: R.s(110),
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
                    color: Colors.white, size: R.s(54),
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
                  List.generate(word.letters.length, (i) => _buildDropSlot(word, i)),
            ),

            const SizedBox(height: 52),

            // Draggable letter cards (centered, shuffled)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: _shuffledOrder.map((letterIdx) {
                if (_placedLetters.contains(letterIdx)) {
                  return SizedBox(width: R.s(112), height: R.s(96));
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
      padding: const EdgeInsets.symmetric(horizontal: 12),
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
                  width: R.s(96),
                  height: R.s(96),
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
            width: R.s(96),
            height: R.s(96),
            margin: const EdgeInsets.symmetric(horizontal: 12),
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
                    Text(
                      'Amazing!',
                      style: TextStyle(
                        fontSize: R.s(52),
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
                            '$_totalStars  stars',
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
                  height: R.s(64),
                  width: R.s(280),
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
                      _wordIndex >= _words.length - 1
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

}
