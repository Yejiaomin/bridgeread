import 'package:flutter/material.dart';
import '../services/lesson_service.dart';
import '../services/week_service.dart';
import 'quiz_screen.dart';
import 'eggy_celebration_screen.dart';

/// Weekend Review Game Screen
/// Plays quiz (消消乐) for each reviewed lesson, then goes to listen.
///
/// Reviews only the lessons actually studied this week.
/// Full week (5 days): Sat = first 3, Sun = last 2
/// Partial week examples:
///   4 days: Sat = first 2, Sun = last 2
///   3 days: Sat = first 1, Sun = last 2
///   2 days: Sat & Sun = all 2
///   1 day:  Sat & Sun = all 1

// Uses activeDate() from week_service.dart

class WeekendGameScreen extends StatefulWidget {
  const WeekendGameScreen({super.key});
  @override
  State<WeekendGameScreen> createState() => _WeekendGameScreenState();
}

class _WeekendGameScreenState extends State<WeekendGameScreen> {
  List<String> _reviewLessons = [];
  int _phase = 0; // 0=quiz only
  int _dayIdx = 0; // which day within current phase
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _loadReviewLessons();
  }

  Future<void> _loadReviewLessons() async {
    final weekBooks = await WeekService.thisWeekBooks();
    if (weekBooks.isNotEmpty) {
      // Normal review: all books studied this week
      _reviewLessons = weekBooks.map((b) => b.lessonId).toList();
    } else {
      // All books completed, no new books this week → review last 5
      final last5 = WeekService.lastNBooks(5);
      _reviewLessons = last5.map((b) => b.lessonId).toList();
    }

    if (mounted) {
      setState(() {});
      if (!_started && _reviewLessons.isNotEmpty) {
        _started = true;
        Future.microtask(() => _runCurrentStep());
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // _started is triggered from _loadReviewLessons after async load
  }

  Future<void> _runCurrentStep() async {
    if (_dayIdx >= _reviewLessons.length) {
      // All quiz done → celebration → listen
      await _showCelebration();
      if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/listen', (r) => false);
      return;
    }

    await LessonService().setCurrentLesson(_reviewLessons[_dayIdx]);
    if (!mounted) return;

    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => const QuizScreen(weekendMode: true),
    ));
    if (!mounted) return;

    _dayIdx++;
    _runCurrentStep();
  }

  Future<void> _showCelebration() async {
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EggyCelebrationScreen(
          nextRoute: '',
          nextLabel: '开始听力 🎧',
          moduleKey: 'quiz',
          modulePoints: 15,
          customTitle: '消消乐全部完成！',
          onComplete: () => Navigator.pop(context),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const phaseNames = ['消消乐'];
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F0),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Weekend Review',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFFFF8C42))),
            const SizedBox(height: 16),
            if (_dayIdx < _reviewLessons.length) Text(
              '${phaseNames[0]} (${_dayIdx + 1}/${_reviewLessons.length})',
              style: const TextStyle(fontSize: 18, color: Color(0xFF666666)),
            ),
            const SizedBox(height: 24),
            const CircularProgressIndicator(color: Color(0xFFFF8C42)),
          ],
        ),
      ),
    );
  }
}
