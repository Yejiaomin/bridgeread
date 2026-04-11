import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'week_service.dart' show activeDate, chinaTime;

class ProgressService {
  static const _kTotalStars    = 'total_stars';
  static const _kStreakDays    = 'streak_days';
  static const _kLastDate      = 'last_completed_date';
  static const _kReaderDone    = 'today_reader_done';
  static const _kPhonicsDone   = 'today_phonics_done';
  static const _kQuizDone      = 'today_quiz_done';
  static const _kRecordingDone = 'today_recording_done';
  static const _kActiveDates   = 'active_dates'; // comma-separated YYYY-MM-DD
  static const _kTotalOwed     = 'total_owed';
  static const _kDebtByDate    = 'debt_by_date'; // JSON map: {"2026-04-01": 3, ...}

  static String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static DateTime _chinaTime() => chinaTime();
  static String get _today => _dateStr(_chinaTime());

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

  /// Set the study date when entering from calendar. Call this before starting modules.
  static Future<void> setStudyDate(DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('_current_study_date', _dateStr(date));
  }

  /// Get the current study date (set by calendar or defaults to today).
  static Future<String> _getStudyDate() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('_current_study_date') ?? _today;
  }

  /// Public version for study_screen recap.
  static Future<String> getStudyDateStr() => _getStudyDate();

  /// Mark a module complete and award stars. module = 'reader'|'phonics'|'quiz'|'recording'.
  static Future<void> markModuleComplete(String module, int stars) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'today_${module}_done';
    final wasAlreadyDone = prefs.getBool(key) ?? false;
    await prefs.setBool(key, true);

    // Use saved study date (persisted, survives page transitions)
    final syncDate = await _getStudyDate();

    // Save to debt_module_status for the active date (calendar-selected or today)
    final dateKey = syncDate;
    final raw = prefs.getString('debt_module_status');
    final all = raw != null ? Map<String, dynamic>.from(jsonDecode(raw)) : <String, dynamic>{};
    final dayData = all[dateKey] != null
        ? Map<String, dynamic>.from(all[dateKey] as Map)
        : <String, dynamic>{};
    dayData[module] = true;
    all[dateKey] = dayData;
    await prefs.setString('debt_module_status', jsonEncode(all));

    if (!wasAlreadyDone) {
      final current = prefs.getInt(_kTotalStars) ?? 0;
      await prefs.setInt(_kTotalStars, current + stars);
    }

    // Record this date as active (any module completion = active day)
    final activeDates = (prefs.getString(_kActiveDates) ?? '')
        .split(',')
        .where((s) => s.isNotEmpty)
        .toList();
    if (!activeDates.contains(dateKey)) {
      activeDates.add(dateKey);
      if (activeDates.length > 30) activeDates.removeAt(0);
      await prefs.setString(_kActiveDates, activeDates.join(','));
    }

    // Update streak on first module completion of the day
    final lastDate = prefs.getString(_kLastDate) ?? '';
    if (lastDate != dateKey) {
      final yesterday = _dateStr(
          _chinaTime().subtract(const Duration(days: 1)));
      final currentStreak = prefs.getInt(_kStreakDays) ?? 0;
      final newStreak = lastDate == yesterday ? currentStreak + 1 : 1;
      await prefs.setInt(_kStreakDays, newStreak);
      await prefs.setString(_kLastDate, dateKey);
    }
  }

  /// Returns today's progress map. Resets module flags if it's a new day.
  static Future<Map<String, dynamic>> getTodayProgress() async {
    await resetTodayIfNewDay();
    final prefs = await SharedPreferences.getInstance();

    // Build Mon–Sun active flags for the current calendar week
    final now = _chinaTime();
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

  /// Fetch debt data — no-op in local mode, uses cached SharedPreferences data.
  static Future<void> syncDebtFromServer() async {
    // No backend available; local data in SharedPreferences is the source of truth.
  }

  /// Get total owed count (cached).
  static Future<int> getTotalOwed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kTotalOwed) ?? 0;
  }

  /// Get debt map by date (cached): {"2026-04-01": 3, ...}
  static Future<Map<String, int>> getDebtByDate() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kDebtByDate);
    if (raw == null) return {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map((k, v) => MapEntry(k, v as int));
  }

  /// Get module status for a specific date: {reader: true, phonics: false, ...}
  static Future<Map<String, bool>> getModuleStatusForDate(String date) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('debt_module_status');
    if (raw == null) return {};
    final all = jsonDecode(raw) as Map<String, dynamic>;
    final dayData = all[date] as Map<String, dynamic>?;
    if (dayData == null) return {};
    return dayData.map((k, v) => MapEntry(k, v as bool));
  }

  /// Get today's pending module count (modules not yet done today).
  /// The 4 tracked modules are: recap, reader, quiz, listen.
  static Future<int> getTodayPending() async {
    await resetTodayIfNewDay();
    final prefs = await SharedPreferences.getInstance();
    final now = _chinaTime();
    final todayStr = _today;

    if (now.weekday == 6 || now.weekday == 7) {
      // Weekend: 2 modules (game + listen)
      int pending = 0;
      if (!(prefs.getBool(_kQuizDone) ?? false)) pending++;
      if (!(prefs.getBool('today_listen_done') ?? false)) pending++;
      return pending;
    }

    // Weekday: 4 modules (recap, reader, quiz, listen)
    int pending = 0;
    if (prefs.getString('today_recap_done') != todayStr) pending++;
    if (!(prefs.getBool(_kReaderDone) ?? false)) pending++;
    if (!(prefs.getBool(_kQuizDone) ?? false)) pending++;
    if (!(prefs.getBool('today_listen_done') ?? false)) pending++;
    return pending;
  }
}
