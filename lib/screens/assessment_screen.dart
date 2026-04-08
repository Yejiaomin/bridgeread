import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../utils/cdn_asset.dart';

const _kOrange = Color(0xFFFF8C42);
const _kCream = Color(0xFFFFF8F0);

class AssessmentScreen extends StatefulWidget {
  const AssessmentScreen({super.key});
  @override
  State<AssessmentScreen> createState() => _AssessmentScreenState();
}

class _AssessmentScreenState extends State<AssessmentScreen> {
  final AudioPlayer _player = AudioPlayer();
  int _step = 0;
  int _selected = -1;
  bool _isPlaying = false;
  int _score = 0; // accumulate correct answers
  int _selectedLevel = -1;

  // ── Test data ─────────────────────────────────────────────────────────────
  // ── A Level (Biscuit — beginner) ──
  static const _levelA = [
    _TestStep(
      type: 'listen', level: 'A',
      instruction: '听一听，这句话是什么意思？',
      audio: 'audio/biscuit_rec_left.mp3',
      options: ['小饼干该睡觉啦', '小饼干想吃东西', '小饼干在玩球'],
      correctIndex: 0,
    ),
    _TestStep(
      type: 'word', level: 'A',
      instruction: '这个单词是什么意思？',
      displayWord: 'dog',
      options: ['猫', '狗', '鸟'],
      correctIndex: 1,
    ),
    _TestStep(
      type: 'listen', level: 'A',
      instruction: '再听一句，这句话是什么意思？',
      audio: 'audio/farm_rec_left.mp3',
      options: ['我们也可以喂小猪', '小猪在睡觉', '我们去看小鸟'],
      correctIndex: 0,
    ),
  ];

  // ── B Level (Pete the Cat — intermediate) ──
  static const _levelB = [
    _TestStep(
      type: 'listen', level: 'B',
      instruction: '听听这句话，Pete the Cat 在做什么？',
      audio: 'audio/assessment_b1.mp3',
      options: ['Pete 穿着新白鞋走在街上', 'Pete 在家里睡觉', 'Pete 在吃东西'],
      correctIndex: 0,
    ),
    _TestStep(
      type: 'word', level: 'B',
      instruction: '这个单词是什么意思？',
      displayWord: 'street',
      options: ['街道', '学校', '公园'],
      correctIndex: 0,
    ),
    _TestStep(
      type: 'listen', level: 'B',
      instruction: 'Pete 哭了吗？',
      audio: 'audio/assessment_b2.mp3',
      options: ['没有，他继续走继续唱歌', '他大哭了一场', '他回家了'],
      correctIndex: 0,
    ),
  ];

  List<_TestStep> _steps = [];

  void _buildSteps() {
    // Start with A level
    _steps = List.of(_levelA);
  }

  int _aCorrect = 0;
  int _bCorrect = 0;
  bool _bAdded = false;

  _TestStep get _current => _step < _steps.length ? _steps[_step] : _steps.last;
  bool get _isTestDone => _step >= _steps.length;

  void _playAudio() async {
    if (_current.audio == null) return;
    setState(() => _isPlaying = true);
    await _player.play(cdnAudioSource(_current.audio!));
    _player.onPlayerComplete.first.then((_) {
      if (mounted) setState(() => _isPlaying = false);
    });
  }

  void _selectOption(int index) {
    if (_selected >= 0) return;
    setState(() => _selected = index);
    final correct = index == _current.correctIndex;
    if (correct) {
      _score++;
      if (_current.level == 'A') _aCorrect++;
      if (_current.level == 'B') _bCorrect++;
    }

    // After finishing A level, if mostly correct → add B level questions
    if (_step == _levelA.length - 1 && !_bAdded && _aCorrect >= 2) {
      _steps.addAll(_levelB);
      _bAdded = true;
    }

    Future.delayed(const Duration(milliseconds: 1000), () {
      if (!mounted) return;
      setState(() {
        _step++;
        _selected = -1;
      });
      if (!_isTestDone && _steps[_step].type == 'listen') {
        Future.delayed(const Duration(milliseconds: 500), _playAudio);
      }
    });
  }

  int get _recommendedLevel {
    if (_bAdded && _bCorrect >= 2) return 2; // C level
    if (_aCorrect >= 2) return 1; // B level
    return 0; // A level
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    final level = _selectedLevel >= 0 ? _selectedLevel : _recommendedLevel;
    await prefs.setInt('start_series_index', level);
    await prefs.setBool('assessment_done', true);

    // Set book_start_date to today if not set
    if (prefs.getString('book_start_date') == null) {
      final now = DateTime.now();
      final date = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      await prefs.setString('book_start_date', date);
      // Sync to server
      ApiService().setupProgress(bookStartDate: date, startSeriesIndex: level);
    } else {
      ApiService().setupProgress(startSeriesIndex: level);
    }

    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/ranking', (r) => false);
    }
  }

  @override
  void initState() {
    super.initState();
    _buildSteps();
    Future.delayed(const Duration(milliseconds: 800), () {
      if (_steps[0].type == 'listen') _playAudio();
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kCream,
      body: Center(
        child: SizedBox(
          width: MediaQuery.of(context).size.width / 3,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 40),
                // Progress
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_steps.length + 2, (i) => Container(
                    width: 10, height: 10,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i <= _step ? _kOrange : Colors.grey.shade300,
                    ),
                  )),
                ),
                const SizedBox(height: 32),

                if (!_isTestDone && _step < _steps.length)
                  _buildQuestion()
                else if (_step == _steps.length)
                  _buildResult()
                else
                  _buildAgreement(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Question ──────────────────────────────────────────────────────────────
  Widget _buildQuestion() {
    final q = _current;
    return Column(
      children: [
        Text('问题 ${_step + 1}/${_steps.length}',
          style: const TextStyle(fontSize: 14, color: Color(0xFF999999))),
        const SizedBox(height: 8),
        Text(q.instruction,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF333333)),
          textAlign: TextAlign.center),
        const SizedBox(height: 24),

        // Listen button or word display
        if (q.type == 'listen')
          GestureDetector(
            onTap: _isPlaying ? null : _playAudio,
            child: Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(color: _kOrange, width: 2),
              ),
              child: Icon(_isPlaying ? Icons.hearing : Icons.play_arrow,
                size: 36, color: _kOrange),
            ),
          )
        else if (q.displayWord != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _kOrange),
            ),
            child: Text(q.displayWord!,
              style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: Color(0xFF333333))),
          ),

        const SizedBox(height: 24),

        // Options
        ...List.generate(q.options.length, (i) {
          final isSelected = _selected == i;
          final isCorrect = i == q.correctIndex;
          Color bgColor = Colors.white;
          Color borderColor = Colors.grey.shade300;
          Color textColor = const Color(0xFF333333);

          if (_selected >= 0) {
            if (isCorrect) {
              bgColor = Colors.green.shade50;
              borderColor = Colors.green;
              textColor = Colors.green.shade800;
            } else if (isSelected && !isCorrect) {
              bgColor = Colors.red.shade50;
              borderColor = Colors.red;
              textColor = Colors.red.shade800;
            }
          }

          return GestureDetector(
            onTap: _selected >= 0 ? null : () => _selectOption(i),
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderColor, width: isSelected || (_selected >= 0 && isCorrect) ? 2 : 1),
              ),
              child: Row(
                children: [
                  Text(String.fromCharCode(65 + i), // A, B, C
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: textColor)),
                  const SizedBox(width: 12),
                  Text(q.options[i],
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textColor)),
                  const Spacer(),
                  if (_selected >= 0 && isCorrect)
                    const Icon(Icons.check_circle, color: Colors.green, size: 22),
                  if (_selected >= 0 && isSelected && !isCorrect)
                    const Icon(Icons.cancel, color: Colors.red, size: 22),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  // ── Result ────────────────────────────────────────────────────────────────
  Widget _buildResult() {
    if (_selectedLevel < 0) _selectedLevel = _recommendedLevel;
    return Column(
      children: [
        Image.asset('assets/pet/eggy_transparent_bg.webp', width: 120, height: 120),
        const SizedBox(height: 12),
        Text('答对 $_score/${_steps.length} 题',
          style: const TextStyle(fontSize: 18, color: Color(0xFF666666))),
        const SizedBox(height: 8),
        const Text('推荐学习级别', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF333333))),
        if (_bAdded && _bCorrect >= 2) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.shade300),
            ),
            child: const Row(
              children: [
                Text('⭐', style: TextStyle(fontSize: 20)),
                SizedBox(width: 8),
                Expanded(child: Text(
                  '孩子基础不错！想挑战更高难度，请私信 Amy 老师进行 1:1 面试定级',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF7B6B00)),
                )),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),

        ...List.generate(3, (i) {
          const names = ['A 级 · 零基础启蒙', 'B 级 · 有一点基础', 'C 级 · 进阶提升'];
          const descs = ['从最简单的绘本开始，适合完全没接触过英语的孩子', '跳过入门内容，从基础绘本开始', '适合已经有一定听说基础的孩子'];
          final selected = _selectedLevel == i;
          final recommended = _recommendedLevel == i;
          return GestureDetector(
            onTap: () => setState(() => _selectedLevel = i),
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: selected ? _kOrange.withValues(alpha: 0.1) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: selected ? _kOrange : Colors.grey.shade300, width: selected ? 2 : 1),
              ),
              child: Row(
                children: [
                  Icon(selected ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: selected ? _kOrange : Colors.grey, size: 22),
                  const SizedBox(width: 10),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(names[i], style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                        color: selected ? _kOrange : const Color(0xFF333333))),
                      Text(descs[i], style: const TextStyle(fontSize: 12, color: Color(0xFF999999))),
                    ],
                  )),
                  if (recommended)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: _kOrange, borderRadius: BorderRadius.circular(8)),
                      child: const Text('推荐', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
            ),
          );
        }),

        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity, height: 48,
          child: ElevatedButton(
            onPressed: () => setState(() => _step++),
            style: ElevatedButton.styleFrom(backgroundColor: _kOrange, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
            child: const Text('下一步', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  // ── Agreement ─────────────────────────────────────────────────────────────
  Widget _buildAgreement() {
    return Column(
      children: [
        Image.asset('assets/pet/eggy_transparent_bg.webp', width: 100, height: 100),
        const SizedBox(height: 12),
        const Text('使用须知', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF333333))),
        const SizedBox(height: 16),

        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('关于 BridgeRead', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _kOrange)),
              SizedBox(height: 6),
              Text('BridgeRead 是一款公益儿童英语启蒙应用，通过绘本阅读、自然拼读、听力训练等方式，帮助孩子轻松开始英语学习之旅。',
                style: TextStyle(fontSize: 14, color: Color(0xFF666666), height: 1.6)),
              SizedBox(height: 14),
              Text('请家长注意', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _kOrange)),
              SizedBox(height: 6),
              Text('• 不要强迫孩子开口说英语\n'
                   '• 用好奇心引导孩子讨论故事\n'
                   '• 帮助孩子养成每天听故事的习惯\n'
                   '• 睡前听力是最好的磨耳朵时间\n'
                   '• 坚持比完美更重要',
                style: TextStyle(fontSize: 14, color: Color(0xFF666666), height: 1.8)),
            ],
          ),
        ),

        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity, height: 48,
          child: ElevatedButton(
            onPressed: _finish,
            style: ElevatedButton.styleFrom(backgroundColor: _kOrange, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
            child: const Text('我知道了，开始学习', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}

class _TestStep {
  final String type; // 'listen' or 'word'
  final String level; // 'A', 'B', 'C'
  final String instruction;
  final String? audio;
  final String? displayWord;
  final List<String> options;
  final int correctIndex;

  const _TestStep({
    required this.type,
    required this.level,
    required this.instruction,
    this.audio,
    this.displayWord,
    required this.options,
    required this.correctIndex,
  });
}
