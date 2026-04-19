import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import 'week_service.dart' show activeDate, chinaTime, WeekService;
import 'analytics_service.dart';
import 'api_service.dart';

class ProgressService {
  static const _kTotalStars    = 'total_stars';
  static const _kStreakDays    = 'streak_days';
  static const _kLastDate      = 'last_completed_date';
  static const _kActiveDates   = 'active_dates'; // comma-separated YYYY-MM-DD
  static const _kTotalOwed     = 'total_owed';
  static const _kDebtByDate    = 'debt_by_date'; // JSON map: {"2026-04-01": 3, ...}
  static const _kModuleStatus  = 'debt_module_status'; // single source of truth
  // Server-mirrored module completion. Schema:
  //   { "<YYYY-MM-DD>": { "<module>": true, ... }, ... }
  // Replaces all the per-module today_X_done bool flags — those were a
  // parallel local truth that drifted out of sync (logout/login wiped flags
  // but server was correct, etc).

  static final _api = ApiService();

  static String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static DateTime _chinaTime() => chinaTime();
  static String get _today => _dateStr(_chinaTime());

  /// Fetch progress from server and update local cache.
  /// Call on app start / login.
  static Future<void> syncFromServer() async {
    final data = await _api.getProgress();
    if (data == null || data['success'] != true) return;

    final prefs = await SharedPreferences.getInstance();
    final user = data['user'] as Map<String, dynamic>?;
    if (user != null) {
      await prefs.setInt(_kTotalStars, user['total_stars'] ?? 0);
      if (user['book_start_date'] != null) {
        await prefs.setString('book_start_date', user['book_start_date']);
      }
      if (user['start_series_index'] != null) {
        await prefs.setInt('start_series_index', user['start_series_index']);
      }
      // Restore listen time from server
      if (user['listen_date'] != null) {
        await prefs.setString('listen_date', user['listen_date']);
        await prefs.setInt('listen_seconds', user['listen_seconds'] ?? 0);
      }
      // Restore app_start_date from server
      if (user['app_start_date'] != null) {
        await prefs.setString('app_start_date', user['app_start_date']);
      }
    }

    // Update streak from server
    if (data['streak'] != null) {
      await prefs.setInt(_kStreakDays, data['streak']);
    }

    // Update debt data from server
    if (data['totalOwed'] != null) {
      await prefs.setInt(_kTotalOwed, data['totalOwed']);
    }
    if (data['debtByDate'] != null) {
      final debtMap = <String, int>{};
      for (final item in data['debtByDate'] as List) {
        debtMap[item['date']] = item['debt'];
      }
      await prefs.setString(_kDebtByDate, jsonEncode(debtMap));
    }

    // Update module status from server progress — debt_module_status is the
    // single source of truth for "what's done on what date". No separate flags.
    final progress = data['progress'] as List?;
    if (progress != null) {
      final moduleStatus = <String, dynamic>{};
      final activeDates = <String>{};
      String? latestDoneDate;

      for (final p in progress) {
        final date = p['date'] as String;
        final module = p['module'] as String;
        final done = p['done'] == 1;

        moduleStatus[date] ??= <String, dynamic>{};
        (moduleStatus[date] as Map<String, dynamic>)[module] = done;

        if (done) {
          activeDates.add(date);
          if (latestDoneDate == null || date.compareTo(latestDoneDate) > 0) {
            latestDoneDate = date;
          }
        }
      }

      if (latestDoneDate != null) {
        await prefs.setString(_kLastDate, latestDoneDate);
      }

      await prefs.setString(_kModuleStatus, jsonEncode(moduleStatus));
      final datesList = activeDates.toList()..sort();
      if (datesList.length > 30) datesList.removeRange(0, datesList.length - 30);
      await prefs.setString(_kActiveDates, datesList.join(','));
    }

    debugPrint('[Progress] synced from server');
  }

  /// Whether [module] is marked done for today in the local mirror of server
  /// state. Reads from debt_module_status, which is keyed by date — naturally
  /// rolls over at midnight without needing an explicit reset.
  static Future<bool> isDoneToday(String module) async {
    final status = await getModuleStatusForDate(_today);
    return status[module] == true;
  }

  /// Today's done state for all 6 modules.
  static Future<Map<String, bool>> todayDoneFlags() async {
    final status = await getModuleStatusForDate(_today);
    return {
      for (final m in ['recap', 'reader', 'quiz', 'listen', 'phonics', 'recording'])
        m: status[m] == true,
    };
  }

  /// Set the study date when entering from calendar.
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

  /// Mark a module complete and award stars.
  static Future<void> markModuleComplete(String module, int stars) async {
    final prefs = await SharedPreferences.getInstance();
    final syncDate = await _getStudyDate();
    final dateKey = syncDate;

    // Read current debt_module_status — that's the truth, not a parallel flag
    final raw = prefs.getString(_kModuleStatus);
    final all = raw != null ? Map<String, dynamic>.from(jsonDecode(raw)) : <String, dynamic>{};
    final dayData = all[dateKey] != null
        ? Map<String, dynamic>.from(all[dateKey] as Map)
        : <String, dynamic>{};
    final wasAlreadyDone = dayData[module] == true;
    dayData[module] = true;
    all[dateKey] = dayData;
    await prefs.setString(_kModuleStatus, jsonEncode(all));

    // Analytics
    if (!wasAlreadyDone) {
      const moduleToEvent = {
        'reader': 'story_done',
        'quiz': 'game_done',
        'listen': 'listen_done',
        'recording': 'recording_done',
      };
      final event = moduleToEvent[module] ?? '${module}_done';
      AnalyticsService.logEvent(event);
    }

    if (!wasAlreadyDone) {
      final current = prefs.getInt(_kTotalStars) ?? 0;
      await prefs.setInt(_kTotalStars, current + stars);
    }

    // Record this date as active
    final activeDates = (prefs.getString(_kActiveDates) ?? '')
        .split(',')
        .where((s) => s.isNotEmpty)
        .toList();
    if (!activeDates.contains(dateKey)) {
      activeDates.add(dateKey);
      if (activeDates.length > 30) activeDates.removeAt(0);
      await prefs.setString(_kActiveDates, activeDates.join(','));
    }

    // Update streak
    final lastDate = prefs.getString(_kLastDate) ?? '';
    if (lastDate != dateKey) {
      final yesterday = _dateStr(
          _chinaTime().subtract(const Duration(days: 1)));
      final currentStreak = prefs.getInt(_kStreakDays) ?? 0;
      final newStreak = lastDate == yesterday ? currentStreak + 1 : 1;
      await prefs.setInt(_kStreakDays, newStreak);
      await prefs.setString(_kLastDate, dateKey);
    }

    // Sync to server (fire-and-forget, don't block UI)
    final lessonId = prefs.getString('current_lesson_id');
    _api.syncProgress(
      date: dateKey,
      module: module,
      done: true,
      stars: stars,
      lessonId: lessonId,
    ).then((res) {
      if (res != null) {
        debugPrint('[Progress] synced $module to server');
        // Update local cache with server totals (only if server is ahead)
        if (res['totalStars'] != null) {
          final serverStars = res['totalStars'] as int;
          final localStars = prefs.getInt(_kTotalStars) ?? 0;
          if (serverStars >= localStars) {
            prefs.setInt(_kTotalStars, serverStars);
          }
        }
      }
    });
  }

  /// Returns today's progress map.
  static Future<Map<String, dynamic>> getTodayProgress() async {
    final prefs = await SharedPreferences.getInstance();
    final flags = await todayDoneFlags();

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
      'reader_done':    flags['reader']!,
      'phonics_done':   flags['phonics']!,
      'quiz_done':      flags['quiz']!,
      'recording_done': flags['recording']!,
      'week_active':    weekActive,
    };
  }

  /// Fetch debt data from server.
  static Future<void> syncDebtFromServer() async {
    await syncFromServer();
  }

  /// Get total owed count (cached).
  static Future<int> getTotalOwed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kTotalOwed) ?? 0;
  }

  /// Get debt map by date (cached).
  static Future<Map<String, int>> getDebtByDate() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kDebtByDate);
    if (raw == null) return {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map((k, v) => MapEntry(k, v as int));
  }

  /// Get module status for a specific date.
  static Future<Map<String, bool>> getModuleStatusForDate(String date) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('debt_module_status');
    if (raw == null) return {};
    final all = jsonDecode(raw) as Map<String, dynamic>;
    final dayData = all[date] as Map<String, dynamic>?;
    if (dayData == null) return {};
    return dayData.map((k, v) => MapEntry(k, v as bool));
  }

  /// Get today's pending module count.
  static Future<int> getTodayPending() async {
    final prefs = await SharedPreferences.getInstance();
    final now = _chinaTime();
    final flags = await todayDoneFlags();

    if (now.weekday == 6 || now.weekday == 7) {
      final startStr = prefs.getString('book_start_date');
      final startDate = startStr != null ? WeekService.parseDate(startStr) : null;
      final isRegistrationDay = startDate != null &&
          startDate.year == now.year && startDate.month == now.month && startDate.day == now.day;
      if (!isRegistrationDay) {
        return (flags['quiz']! ? 0 : 1) + (flags['listen']! ? 0 : 1);
      }
      // Registration day on weekend: fall through to weekday logic (4 modules)
    }

    return (flags['recap']! ? 0 : 1) + (flags['reader']! ? 0 : 1) +
           (flags['quiz']! ? 0 : 1) + (flags['listen']! ? 0 : 1);
  }
}
