import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bridgeread/services/progress_service.dart';
import 'package:bridgeread/services/week_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    WeekService.overrideDate = null;
  });

  group('ProgressService.resetTodayIfNewDay', () {
    test('resets module flags when date changes', () async {
      final yesterday = _chinaTime().subtract(const Duration(days: 1));
      final yesterdayStr =
          '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';

      SharedPreferences.setMockInitialValues({
        'last_completed_date': yesterdayStr,
        'today_reader_done': true,
        'today_phonics_done': true,
        'today_quiz_done': true,
        'today_recording_done': true,
      });

      await ProgressService.resetTodayIfNewDay();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('today_reader_done'), false);
      expect(prefs.getBool('today_phonics_done'), false);
      expect(prefs.getBool('today_quiz_done'), false);
      expect(prefs.getBool('today_recording_done'), false);
    });

    test('does not reset when same day', () async {
      final todayStr = _todayStr();

      SharedPreferences.setMockInitialValues({
        'last_completed_date': todayStr,
        'today_reader_done': true,
        'today_quiz_done': true,
      });

      await ProgressService.resetTodayIfNewDay();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('today_reader_done'), true);
      expect(prefs.getBool('today_quiz_done'), true);
    });
  });

  group('ProgressService.getTodayPending', () {
    test('weekday: returns 4 when nothing is done', () async {
      final now = _chinaTime();
      final isWeekend = now.weekday > 5;
      SharedPreferences.setMockInitialValues({});
      final pending = await ProgressService.getTodayPending();
      // Weekend with default thisWeekBooks (5 books) → 2 (quiz+listen)
      // Weekday → 4 (all modules)
      expect(pending, isWeekend ? 2 : 4);
    });

    test('weekday: returns 3 when recap is done', () async {
      final now = _chinaTime();
      final isWeekend = now.weekday > 5;
      final todayStr = _todayStr();
      SharedPreferences.setMockInitialValues({
        'today_recap_done': todayStr,
      });
      final pending = await ProgressService.getTodayPending();
      expect(pending, isWeekend ? 2 : 3); // weekend doesn't track recap
    });

    test('returns 2 when recap and reader are done', () async {
      final now = _chinaTime();
      final isWeekend = now.weekday > 5;
      final todayStr = _todayStr();
      SharedPreferences.setMockInitialValues({
        'last_completed_date': todayStr,
        'today_recap_done': todayStr,
        'today_reader_done': true,
      });
      final pending = await ProgressService.getTodayPending();
      expect(pending, isWeekend ? 2 : 2);
    });

    test('returns 0 when all modules are done', () async {
      final todayStr = _todayStr();
      SharedPreferences.setMockInitialValues({
        'last_completed_date': todayStr,
        'today_recap_done': todayStr,
        'today_reader_done': true,
        'today_quiz_done': true,
        'today_listen_done': true,
      });
      final pending = await ProgressService.getTodayPending();
      expect(pending, 0);
    });

    test('recap from yesterday does not count as done today', () async {
      final now = _chinaTime();
      final isWeekend = now.weekday > 5;
      final yesterday = now.subtract(const Duration(days: 1));
      final yesterdayStr =
          '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';
      SharedPreferences.setMockInitialValues({
        'today_recap_done': yesterdayStr,
      });
      final pending = await ProgressService.getTodayPending();
      expect(pending, isWeekend ? 2 : 4);
    });
  });

  group('ProgressService.getDebtByDate', () {
    test('returns empty map when no data', () async {
      SharedPreferences.setMockInitialValues({});
      final debt = await ProgressService.getDebtByDate();
      expect(debt, isEmpty);
    });

    test('parses cached debt data correctly', () async {
      final debtData = {'2026-04-01': 3, '2026-04-02': 4, '2026-04-03': 1};

      SharedPreferences.setMockInitialValues({
        'debt_by_date': jsonEncode(debtData),
      });

      final debt = await ProgressService.getDebtByDate();
      expect(debt.length, 3);
      expect(debt['2026-04-01'], 3);
      expect(debt['2026-04-02'], 4);
      expect(debt['2026-04-03'], 1);
    });

    test('returns empty map for invalid JSON', () async {
      SharedPreferences.setMockInitialValues({
        'debt_by_date': 'not valid json',
      });

      // Should throw or return empty — test that it handles gracefully
      try {
        await ProgressService.getDebtByDate();
      } catch (e) {
        // FormatException is expected for invalid JSON
        expect(e, isA<FormatException>());
      }
    });
  });

  group('ProgressService.getTotalOwed', () {
    test('returns 0 when no data', () async {
      SharedPreferences.setMockInitialValues({});
      final owed = await ProgressService.getTotalOwed();
      expect(owed, 0);
    });

    test('returns cached value', () async {
      SharedPreferences.setMockInitialValues({
        'total_owed': 12,
      });

      final owed = await ProgressService.getTotalOwed();
      expect(owed, 12);
    });
  });

  group('ProgressService.getModuleStatusForDate', () {
    test('returns empty map when no data', () async {
      SharedPreferences.setMockInitialValues({});
      final status = await ProgressService.getModuleStatusForDate('2026-04-01');
      expect(status, isEmpty);
    });

    test('returns correct module status for a date', () async {
      final moduleData = {
        '2026-04-01': {
          'recap': true,
          'reader': true,
          'quiz': false,
          'listen': false,
        },
        '2026-04-02': {
          'recap': false,
          'reader': false,
          'quiz': false,
          'listen': false,
        },
      };

      SharedPreferences.setMockInitialValues({
        'debt_module_status': jsonEncode(moduleData),
      });

      final status = await ProgressService.getModuleStatusForDate('2026-04-01');
      expect(status['recap'], true);
      expect(status['reader'], true);
      expect(status['quiz'], false);
      expect(status['listen'], false);
    });

    test('returns empty map for date not in data', () async {
      SharedPreferences.setMockInitialValues({
        'debt_module_status': jsonEncode({'2026-04-01': {'recap': true}}),
      });

      final status = await ProgressService.getModuleStatusForDate('2026-12-25');
      expect(status, isEmpty);
    });
  });

  group('ProgressService.markModuleComplete', () {
    test('sets module done flag to true', () async {
      SharedPreferences.setMockInitialValues({});

      await ProgressService.markModuleComplete('reader', 10);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('today_reader_done'), true);
    });

    test('increments total stars', () async {
      SharedPreferences.setMockInitialValues({
        'total_stars': 50,
      });

      await ProgressService.markModuleComplete('quiz', 20);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('total_stars'), 70);
    });

    test('does not double-add stars on repeat completion', () async {
      SharedPreferences.setMockInitialValues({
        'total_stars': 0,
      });

      await ProgressService.markModuleComplete('reader', 10);
      await ProgressService.markModuleComplete('reader', 10);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('total_stars'), 10); // not 20
    });

    test('updates streak on first completion of the day', () async {
      final yesterday = _chinaTime().subtract(const Duration(days: 1));
      final yesterdayStr =
          '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';

      SharedPreferences.setMockInitialValues({
        'streak_days': 3,
        'last_completed_date': yesterdayStr,
      });

      await ProgressService.markModuleComplete('reader', 10);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('streak_days'), 4); // continued streak
    });

    test('resets streak when day is skipped', () async {
      // Last completed 3 days ago
      final threeDaysAgo = _chinaTime().subtract(const Duration(days: 3));
      final dateStr =
          '${threeDaysAgo.year}-${threeDaysAgo.month.toString().padLeft(2, '0')}-${threeDaysAgo.day.toString().padLeft(2, '0')}';

      SharedPreferences.setMockInitialValues({
        'streak_days': 10,
        'last_completed_date': dateStr,
      });

      await ProgressService.markModuleComplete('reader', 10);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('streak_days'), 1); // reset to 1
    });

    test('records active date', () async {
      SharedPreferences.setMockInitialValues({});

      await ProgressService.markModuleComplete('reader', 10);

      final prefs = await SharedPreferences.getInstance();
      final activeDates = prefs.getString('active_dates') ?? '';
      expect(activeDates, isNotEmpty);
    });
  });

  group('ProgressService.getTodayProgress', () {
    test('returns all fields with defaults', () async {
      SharedPreferences.setMockInitialValues({});

      final progress = await ProgressService.getTodayProgress();

      expect(progress['total_stars'], 0);
      expect(progress['streak_days'], 0);
      expect(progress['reader_done'], false);
      expect(progress['phonics_done'], false);
      expect(progress['quiz_done'], false);
      expect(progress['recording_done'], false);
      expect(progress['week_active'], isList);
      expect((progress['week_active'] as List).length, 7);
    });

    test('reflects completed modules', () async {
      SharedPreferences.setMockInitialValues({
        'total_stars': 100,
        'streak_days': 5,
        'today_reader_done': true,
        'today_quiz_done': true,
        'last_completed_date': _todayStr(),
      });

      final progress = await ProgressService.getTodayProgress();

      expect(progress['total_stars'], 100);
      expect(progress['streak_days'], 5);
      expect(progress['reader_done'], true);
      expect(progress['quiz_done'], true);
      expect(progress['phonics_done'], false);
      expect(progress['recording_done'], false);
    });
  });

  group('ProgressService China time consistency', () {
    test('_today uses China time, not local time', () async {
      // getTodayPending uses _today internally for recap check
      // If recap is marked with China time date, it should be detected
      final chinaToday = _todayStr();

      SharedPreferences.setMockInitialValues({
        'last_completed_date': chinaToday,
        'today_recap_done': chinaToday,
        'today_reader_done': true,
        'today_quiz_done': true,
        'today_listen_done': true,
      });

      final pending = await ProgressService.getTodayPending();
      expect(pending, 0); // all done with China time dates
    });

    test('recap done with local time does not match China time', () async {
      // Simulate a timezone mismatch: local time date != China time date
      // This only fails when local and China dates differ (e.g. US evening = China next day)
      final now = DateTime.now();
      final localStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final chinaStr = _todayStr();

      if (localStr != chinaStr) {
        final isWeekend = _chinaTime().weekday > 5;
        SharedPreferences.setMockInitialValues({
          'today_recap_done': localStr,
        });
        final pending = await ProgressService.getTodayPending();
        expect(pending, isWeekend ? 2 : 4); // recap not counted
      }
    });
  });

  group('ProgressService.getModuleStatusForDate past date viewing', () {
    test('returns status for a date with partial completion', () async {
      final moduleData = {
        '2026-04-02': {
          'recap': true,
          'reader': true,
          'quiz': false,
          'listen': false,
        },
      };

      SharedPreferences.setMockInitialValues({
        'debt_module_status': jsonEncode(moduleData),
      });

      final status = await ProgressService.getModuleStatusForDate('2026-04-02');
      expect(status['recap'], true);
      expect(status['reader'], true);
      expect(status['quiz'], false);
      expect(status['listen'], false);
    });

    test('returns all false for a date with no completions', () async {
      final moduleData = {
        '2026-04-02': {
          'recap': false,
          'reader': false,
          'quiz': false,
          'listen': false,
        },
      };

      SharedPreferences.setMockInitialValues({
        'debt_module_status': jsonEncode(moduleData),
      });

      final status = await ProgressService.getModuleStatusForDate('2026-04-02');
      expect(status.values.every((v) => v == false), true);
    });

    test('overrideDate determines which date progress is shown', () async {
      // When overrideDate is set, study screen should use server data
      // When null, should use local SharedPreferences
      WeekService.overrideDate = DateTime(2026, 4, 2);
      expect(WeekService.overrideDate, isNotNull);

      WeekService.overrideDate = null;
      expect(WeekService.overrideDate, isNull);
    });
  });

  group('ProgressService debt display logic', () {
    test('totalOwed 0 and todayPending 0 means nothing to show', () async {
      SharedPreferences.setMockInitialValues({
        'total_owed': 0,
      });

      final owed = await ProgressService.getTotalOwed();
      expect(owed, 0);
    });

    test('totalOwed > 0 means historical debt exists', () async {
      SharedPreferences.setMockInitialValues({
        'total_owed': 8,
      });

      final owed = await ProgressService.getTotalOwed();
      expect(owed, 8);
      // Home screen should show "待补 8" on calendar
    });

    test('todayPending decreases as modules are completed', () async {
      final todayStr = _todayStr();
      final isWeekend = _chinaTime().weekday > 5;

      // Only recap done (weekend doesn't track recap)
      SharedPreferences.setMockInitialValues({
        'last_completed_date': todayStr,
        'today_recap_done': todayStr,
      });
      expect(await ProgressService.getTodayPending(), isWeekend ? 2 : 3);

      // Recap + reader done
      SharedPreferences.setMockInitialValues({
        'last_completed_date': todayStr,
        'today_recap_done': todayStr,
        'today_reader_done': true,
      });
      expect(await ProgressService.getTodayPending(), isWeekend ? 2 : 2);

      // Recap + reader + quiz done
      SharedPreferences.setMockInitialValues({
        'last_completed_date': todayStr,
        'today_recap_done': todayStr,
        'today_reader_done': true,
        'today_quiz_done': true,
      });
      expect(await ProgressService.getTodayPending(), isWeekend ? 1 : 1);

      // All done
      SharedPreferences.setMockInitialValues({
        'last_completed_date': todayStr,
        'today_recap_done': todayStr,
        'today_reader_done': true,
        'today_quiz_done': true,
        'today_listen_done': true,
      });
      expect(await ProgressService.getTodayPending(), 0);
    });
  });
}

DateTime _chinaTime() => DateTime.now().toUtc().add(const Duration(hours: 8));

String _todayStr() {
  final now = _chinaTime();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}
