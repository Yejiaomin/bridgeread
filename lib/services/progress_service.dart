import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'week_service.dart' show activeDate;

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

  static DateTime _chinaTime() => DateTime.now().toUtc().add(const Duration(hours: 8));
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

  /// Mark a module complete and award stars. module = 'reader'|'phonics'|'quiz'|'recording'.
  static Future<void> markModuleComplete(String module, int stars) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'today_${module}_done';
    final wasAlreadyDone = prefs.getBool(key) ?? false;
    await prefs.setBool(key, true);

    // Use activeDate (may be a past date when doing debt makeup)
    final syncDate = _dateStr(activeDate());

    if (!wasAlreadyDone) {
      final current = prefs.getInt(_kTotalStars) ?? 0;
      await prefs.setInt(_kTotalStars, current + stars);

      // Sync to server (fire-and-forget, offline-safe)
      ApiService().syncProgress(
        date: syncDate,
        module: module,
        done: true,
        stars: stars,
      ).then((result) {
        print('[SYNC] $module ($syncDate): $result');
      });
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
          _chinaTime().subtract(const Duration(days: 1)));
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

  /// Fetch debt data from server and cache locally.
  static Future<void> syncDebtFromServer() async {
    final result = await ApiService().getProgress();
    if (result == null) return;
    final prefs = await SharedPreferences.getInstance();

    final totalOwed = result['totalOwed'] ?? 0;
    final todayOwed = result['todayOwed'] ?? 0;
    final streak = result['streak'] ?? 0;
    await prefs.setInt(_kTotalOwed, totalOwed);
    await prefs.setInt('today_owed', todayOwed);
    await prefs.setInt(_kStreakDays, streak);

    // debtByDate: [{date: "2026-04-01", debt: 3}, ...]
    final debtList = result['debtByDate'] as List? ?? [];
    final debtMap = <String, int>{};
    for (final item in debtList) {
      debtMap[item['date'] as String] = item['debt'] as int;
    }
    await prefs.setString(_kDebtByDate, jsonEncode(debtMap));

    // Also cache per-date module status from progress array
    final progress = result['progress'] as List? ?? [];
    final moduleStatus = <String, Map<String, bool>>{}; // date -> {module: done}
    for (final p in progress) {
      final date = p['date'] as String;
      final module = p['module'] as String;
      final done = p['done'] == 1;
      moduleStatus.putIfAbsent(date, () => {});
      moduleStatus[date]![module] = done;
    }
    await prefs.setString('debt_module_status', jsonEncode(moduleStatus));
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
    final todayStr = _today;
    int pending = 0;
    // recap is stored as a date string, not bool
    if (prefs.getString('today_recap_done') != todayStr) pending++;
    if (!(prefs.getBool(_kReaderDone) ?? false)) pending++;
    if (!(prefs.getBool(_kQuizDone) ?? false)) pending++;
    if (!(prefs.getBool('today_listen_done') ?? false)) pending++;
    return pending;
  }
}
