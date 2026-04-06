import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kOrange = Color(0xFFFF8C42);
const _kCream = Color(0xFFFFF8F0);

class AssessmentScreen extends StatefulWidget {
  const AssessmentScreen({super.key});
  @override
  State<AssessmentScreen> createState() => _AssessmentScreenState();
}

class _AssessmentScreenState extends State<AssessmentScreen> {
  int _step = 0; // 0=age, 1=experience, 2=words, 3=result, 4=agreement
  int _age = -1;
  int _experience = -1;
  int _wordsKnown = 0;

  // Questions
  static const _ageOptions = ['3-4 岁', '5-6 岁', '7-8 岁', '9 岁以上'];
  static const _expOptions = ['完全没学过', '学过一点点', '学了半年以上'];
  static const _testWords = ['dog', 'cat', 'apple', 'book', 'happy', 'school'];

  int get _recommendedLevel {
    // Simple scoring: age + experience + words known
    int score = 0;
    if (_age >= 2) score += 2; // 7+ years old
    if (_age >= 1) score += 1; // 5+ years old
    if (_experience >= 1) score += 2;
    if (_experience >= 2) score += 2;
    score += _wordsKnown;
    // score 0-2 = A (beginner), 3-5 = B, 6+ = C
    if (score <= 2) return 0; // Series A
    if (score <= 5) return 1; // Series B
    return 2; // Series C
  }

  String get _levelName {
    const names = ['A 级 · 零基础启蒙', 'B 级 · 有一点基础', 'C 级 · 进阶提升'];
    return names[_recommendedLevel.clamp(0, 2)];
  }

  int _selectedLevel = -1; // -1 = not chosen yet

  void _nextStep() {
    if (_step < 4) setState(() => _step++);
    if (_step == 3 && _selectedLevel == -1) _selectedLevel = _recommendedLevel;
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('start_series_index', _selectedLevel);
    await prefs.setBool('assessment_done', true);
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/home', (r) => false);
    }
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
                // Progress dots
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (i) => Container(
                    width: 10, height: 10,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i <= _step ? _kOrange : Colors.grey.shade300,
                    ),
                  )),
                ),
                const SizedBox(height: 32),

                if (_step == 0) _buildAge(),
                if (_step == 1) _buildExperience(),
                if (_step == 2) _buildWords(),
                if (_step == 3) _buildResult(),
                if (_step == 4) _buildAgreement(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Step 0: Age ──
  Widget _buildAge() {
    return _questionCard(
      '孩子几岁了？',
      _ageOptions,
      _age,
      (i) => setState(() => _age = i),
      canNext: _age >= 0,
    );
  }

  // ── Step 1: Experience ──
  Widget _buildExperience() {
    return _questionCard(
      '之前学过英语吗？',
      _expOptions,
      _experience,
      (i) => setState(() => _experience = i),
      canNext: _experience >= 0,
    );
  }

  // ── Step 2: Word recognition ──
  Widget _buildWords() {
    return Column(
      children: [
        const Text('认识这些单词吗？', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF333333))),
        const SizedBox(height: 8),
        const Text('点击认识的单词', style: TextStyle(fontSize: 14, color: Color(0xFF999999))),
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: List.generate(_testWords.length, (i) {
            final known = _wordsKnown > i; // simplified: first N are "known"
            return GestureDetector(
              onTap: () => setState(() => _wordsKnown = known ? i : i + 1),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                decoration: BoxDecoration(
                  color: known ? _kOrange : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: known ? _kOrange : Colors.grey.shade300),
                ),
                child: Text(_testWords[i], style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w700,
                  color: known ? Colors.white : const Color(0xFF333333),
                )),
              ),
            );
          }),
        ),
        const SizedBox(height: 32),
        _nextButton(true),
      ],
    );
  }

  // ── Step 3: Result ──
  Widget _buildResult() {
    return Column(
      children: [
        Image.asset('assets/pet/eggy_transparent_bg.webp', width: 120, height: 120),
        const SizedBox(height: 16),
        const Text('推荐学习级别', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF333333))),
        const SizedBox(height: 24),

        // Level options
        ...List.generate(3, (i) {
          final names = ['A 级 · 零基础启蒙', 'B 级 · 有一点基础', 'C 级 · 进阶提升'];
          final descs = ['从最简单的绘本开始', '跳过入门，从基础开始', '适合有一定基础的孩子'];
          final selected = _selectedLevel == i;
          final recommended = _recommendedLevel == i;
          return GestureDetector(
            onTap: () => setState(() => _selectedLevel = i),
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: selected ? _kOrange.withValues(alpha: 0.1) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected ? _kOrange : Colors.grey.shade300,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(selected ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: selected ? _kOrange : Colors.grey),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(names[i], style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                          color: selected ? _kOrange : const Color(0xFF333333))),
                        Text(descs[i], style: const TextStyle(fontSize: 13, color: Color(0xFF999999))),
                      ],
                    ),
                  ),
                  if (recommended)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: _kOrange, borderRadius: BorderRadius.circular(10)),
                      child: const Text('推荐', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 16),
        _nextButton(true),
      ],
    );
  }

  // ── Step 4: Agreement ──
  Widget _buildAgreement() {
    return Column(
      children: [
        Image.asset('assets/pet/eggy_transparent_bg.webp', width: 100, height: 100),
        const SizedBox(height: 16),
        const Text('使用须知', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF333333))),
        const SizedBox(height: 20),

        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('关于 BridgeRead', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _kOrange)),
              SizedBox(height: 8),
              Text('BridgeRead 是一款公益儿童英语启蒙应用，通过绘本阅读、自然拼读、听力训练等方式，帮助孩子轻松开始英语学习之旅。',
                style: TextStyle(fontSize: 14, color: Color(0xFF666666), height: 1.6)),
              SizedBox(height: 16),
              Text('请家长注意', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _kOrange)),
              SizedBox(height: 8),
              Text('• 不要强迫孩子开口说英语，让他们自然地接受\n'
                   '• 用好奇心引导孩子讨论故事内容\n'
                   '• 帮助孩子养成每天听故事的习惯\n'
                   '• 睡前听力是最好的磨耳朵时间\n'
                   '• 坚持比完美更重要',
                style: TextStyle(fontSize: 14, color: Color(0xFF666666), height: 1.8)),
            ],
          ),
        ),

        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: _finish,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kOrange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            ),
            child: const Text('我知道了，开始学习', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  // ── Shared widgets ──
  Widget _questionCard(String question, List<String> options, int selected, void Function(int) onSelect, {required bool canNext}) {
    return Column(
      children: [
        Text(question, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF333333))),
        const SizedBox(height: 24),
        ...List.generate(options.length, (i) {
          final active = selected == i;
          return GestureDetector(
            onTap: () => onSelect(i),
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              decoration: BoxDecoration(
                color: active ? _kOrange.withValues(alpha: 0.1) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: active ? _kOrange : Colors.grey.shade300, width: active ? 2 : 1),
              ),
              child: Text(options[i], style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
                color: active ? _kOrange : const Color(0xFF333333))),
            ),
          );
        }),
        const SizedBox(height: 16),
        _nextButton(canNext),
      ],
    );
  }

  Widget _nextButton(bool enabled) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: enabled ? _nextStep : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: _kOrange,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
        child: const Text('下一步', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      ),
    );
  }
}
