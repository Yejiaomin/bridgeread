import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class ProgressService {
  static const _kTotalStars    = 'total_stars';
  static const _kStreakDays    = 'streak_days';
  static const _kLastDate      = 'last_completed_date';
  static const _kReaderDone    = 'today_reader_done';
  static const _kPhonicsDone   = 'today_phonics_done';
  static const _kQuizDone      = 'today_quiz_done';
  static const _kRecordingDone = 'today_recording_done';
  static const _kActiveDates   = 'active_dates'; // comma-separated YYYY-MM-DD

  static String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String get _today => _dateStr(DateTime.now());

  /// Resets today's module flags if it's a new day.
  static Future<void> resetTodayIfNewDay() async {
    final prefs = await SharedPreferences.getInstance();
    final lastDate = prefs.getString(_kLastDate) ?? '';
    if (lastDate != _today) {
      await prefs.setBool(_kReaderDone, false);
      await prefs.setBool(_kPhonicsDone, false);
      await prefs.setBool(_kQuizDone, false);
      await prefs.setBool(_kRecordingDone, false);
    }
  }

  /// Mark a module complete and award stars. module = 'reader'|'phonics'|'quiz'|'recording'.
  static Future<void> markModuleComplete(String module, int stars) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'today_${module}_done';
    final wasAlreadyDone = prefs.getBool(key) ?? false;
    await prefs.setBool(key, true);

    if (!wasAlreadyDone) {
      final current = prefs.getInt(_kTotalStars) ?? 0;
      await prefs.setInt(_kTotalStars, current + stars);

      // Sync to server (fire-and-forget, offline-safe)
      ApiService().syncProgress(
        date: _today,
        module: module,
        done: true,
        stars: stars,
      );
    }

    // Record this date as active (any module completion = active day)
    final today = _today;
    final activeDates = (prefs.getString(_kActiveDates) ?? '')
        .split(',')
        .where((s) => s.isNotEmpty)
        .toList();
    if (!activeDates.contains(today)) {
      activeDates.add(today);
      if (activeDates.length > 30) activeDates.removeAt(0);
      await prefs.setString(_kActiveDates, activeDates.join(','));
    }

    // Update streak on first module completion of the day
    final lastDate = prefs.getString(_kLastDate) ?? '';
    if (lastDate != today) {
      final yesterday = _dateStr(
          DateTime.now().subtract(const Duration(days: 1)));
      final currentStreak = prefs.getInt(_kStreakDays) ?? 0;
      final newStreak = lastDate == yesterday ? currentStreak + 1 : 1;
      await prefs.setInt(_kStreakDays, newStreak);
      await prefs.setString(_kLastDate, today);
    }
  }

  /// Returns today's progress map. Resets module flags if it's a new day.
  static Future<Map<String, dynamic>> getTodayProgress() async {
    await resetTodayIfNewDay();
    final prefs = await SharedPreferences.getInstance();

    // Build Mon–Sun active flags for the current calendar week
    final now = DateTime.now();
    final activeDates = (prefs.getString(_kActiveDates) ?? '')
        .split(',')
        .where((s) => s.isNotEmpty)
        .toSet();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekActive = List.generate(
        7, (i) => activeDates.contains(
            _dateStr(weekStart.add(Duration(days: i)))));

    return {
      'total_stars':    prefs.getInt(_kTotalStars) ?? 0,
      'streak_days':    prefs.getInt(_kStreakDays) ?? 0,
      'reader_done':    prefs.getBool(_kReaderDone) ?? false,
      'phonics_done':   prefs.getBool(_kPhonicsDone) ?? false,
      'quiz_done':      prefs.getBool(_kQuizDone) ?? false,
      'recording_done': prefs.getBool(_kRecordingDone) ?? false,
      'week_active':    weekActive, // List<bool> Mon–Sun
    };
  }
}
