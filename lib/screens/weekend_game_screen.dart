import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/lesson_service.dart';
import 'quiz_screen.dart';
import 'phonics_screen.dart';
import 'recording_screen.dart';
import 'eggy_celebration_screen.dart';

/// Weekend Review Game Screen
/// Chains through multiple days of quiz → phonics → recording.
///
/// Reviews only the lessons actually studied this week.
/// Full week (Mon start): Sat = first 3, Sun = last 2
/// Partial week examples:
///   Tue start (4 days): Sat = first 2, Sun = last 2
///   Wed start (3 days): Sat = first 1, Sun = last 2
///   Thu start (2 days): Sat & Sun = all 2
///   Fri start (1 day):  Sat & Sun = all 1

DateTime _chinaTime() => DateTime.now().toUtc().add(const Duration(hours: 8));

class WeekendGameScreen extends StatefulWidget {
  const WeekendGameScreen({super.key});
  @override
  State<WeekendGameScreen> createState() => _WeekendGameScreenState();
}

class _WeekendGameScreenState extends State<WeekendGameScreen> {
  static const _weekLessons = [
    'biscuit_book1_day1',
    'biscuit_baby_book2_day1',
    'biscuit_library_book3_day1',
    'friend_book04_day1',
    'trick_book05_day1',
  ];

  List<String> _reviewLessons = [];
  int _phase = 0; // 0=quiz, 1=phonics, 2=recording
  int _dayIdx = 0; // which day within current phase
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _loadReviewLessons();
  }

  Future<void> _loadReviewLessons() async {
    final prefs = await SharedPreferences.getInstance();
    final startStr = prefs.getString('book_start_date');
    final now = _chinaTime();
    final isSaturday = now.weekday == 6;

    // This week's Monday
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final mondayDate = DateTime(monday.year, monday.month, monday.day);

    // How many weekdays were studied this week?
    int studyDays = 5; // default full week
    if (startStr != null) {
      final parts = startStr.split('-');
      final start = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
      if (start.isAfter(mondayDate)) {
        // Partial first week: count weekdays from start to Friday
        studyDays = (5 - start.weekday + 1).clamp(1, 5);
      }
    }

    // Get only the lessons that were studied this week
    final studied = _weekLessons.sublist(0, studyDays);

    // Split for Saturday / Sunday
    if (studyDays <= 2) {
      // 1-2 days: both Sat and Sun review everything
      _reviewLessons = studied;
    } else {
      // 3+ days: Sat = first (n-2), Sun = last 2
      _reviewLessons = isSaturday
          ? studied.sublist(0, studyDays - 2)
          : studied.sublist(studyDays - 2);
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
    if (_phase >= 3) {
      // All 3 phases done → go home
      if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/home', (r) => false);
      return;
    }

    if (_dayIdx >= _reviewLessons.length) {
      // Current phase done → show celebration, then move to next phase
      await _showCelebration();
      _phase++;
      _dayIdx = 0;
      if (mounted) _runCurrentStep();
      return;
    }

    // Set lesson for current day
    await LessonService().setCurrentLesson(_reviewLessons[_dayIdx]);
    if (!mounted) return;

    // Navigate to the right screen (weekendMode=true → no internal celebration)
    Widget screen;
    switch (_phase) {
      case 0:
        screen = const QuizScreen(weekendMode: true);
        break;
      case 1:
        screen = const PhonicsScreen(weekendMode: true);
        break;
      case 2:
        screen = const RecordingScreen(weekendMode: true);
        break;
      default:
        return;
    }

    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    if (!mounted) return;

    // Move to next day
    _dayIdx++;
    _runCurrentStep();
  }

  Future<void> _showCelebration() async {
    final labels = ['消消乐全部完成！', '自然拼读全部完成！', '录音全部完成！'];
    final nextLabels = ['开始自然拼读', '开始录音', '开始听力'];

    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EggyCelebrationScreen(
          nextRoute: '', // won't be used — we pop manually
          nextLabel: _phase < 2 ? nextLabels[_phase] : '完成！',
          moduleKey: ['quiz', 'phonics', 'recording'][_phase],
          modulePoints: 15,
          customTitle: labels[_phase],
          onComplete: () => Navigator.pop(context),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final phaseNames = ['消消乐', '自然拼读', '录音'];
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F0),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Weekend Review',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFFFF8C42))),
            const SizedBox(height: 16),
            if (_phase < 3) Text(
              '${phaseNames[_phase]} (${_dayIdx + 1}/${_reviewLessons.length})',
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
