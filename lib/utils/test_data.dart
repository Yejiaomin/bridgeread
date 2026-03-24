import 'package:shared_preferences/shared_preferences.dart';

/// Pre-fills SharedPreferences with demo data so the UI has something to show
/// on first run. Only called when streak_days == 0 (fresh install).
Future<void> seedTestData() async {
  final prefs = await SharedPreferences.getInstance();

  // Basic stats
  await prefs.setInt('streak_days', 5);
  await prefs.setInt('total_stars', 35);

  // Today's modules: reader + phonics done, quiz + recording not
  final today = _dateStr(DateTime.now());
  await prefs.setBool('today_reader_done',    true);
  await prefs.setBool('today_phonics_done',   true);
  await prefs.setBool('today_quiz_done',      false);
  await prefs.setBool('today_recording_done', false);
  await prefs.setString('last_completed_date', today);

  // Mark Mon–Fri of the current week as active
  final now       = DateTime.now();
  final weekStart = now.subtract(Duration(days: now.weekday - 1)); // Monday
  final activeDates = List.generate(5, (i) =>            // Mon=0 … Fri=4
      _dateStr(weekStart.add(Duration(days: i))));
  await prefs.setString('active_dates', activeDates.join(','));
}

String _dateStr(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
