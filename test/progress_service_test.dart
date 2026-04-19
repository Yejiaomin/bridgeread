import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bridgeread/services/progress_service.dart';
import 'package:bridgeread/services/week_service.dart';

/// Helper: build a debt_module_status JSON for [date] with the given done flags.
String _statusFor(String date, Map<String, bool> done) =>
    jsonEncode({date: done});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    WeekService.overrideDate = null;
  });

  group('ProgressService.isDoneToday', () {
    test('false when no data', () async {
      expect(await ProgressService.isDoneToday('listen'), false);
    });

    test('true when today is marked done in debt_module_status', () async {
      SharedPreferences.setMockInitialValues({
        'debt_module_status': _statusFor(_todayStr(), {'listen': true}),
      });
      expect(await ProgressService.isDoneToday('listen'), true);
    });

    test('false when only yesterday is done', () async {
      final y = _chinaTime().subtract(const Duration(days: 1));
      final yStr = '${y.year}-${y.month.toString().padLeft(2, '0')}-${y.day.toString().padLeft(2, '0')}';
      SharedPreferences.setMockInitialValues({
        'debt_module_status': _statusFor(yStr, {'listen': true}),
      });
      expect(await ProgressService.isDoneToday('listen'), false);
    });

    test('different modules tracked independently', () async {
      SharedPreferences.setMockInitialValues({
        'debt_module_status': _statusFor(_todayStr(), {'reader': true, 'quiz': false}),
      });
      expect(await ProgressService.isDoneToday('reader'), true);
      expect(await ProgressService.isDoneToday('quiz'), false);
      expect(await ProgressService.isDoneToday('listen'), false);
    });
  });

  group('ProgressService.getTodayPending', () {
    test('weekday: 4 when nothing is done', () async {
      final isWeekend = _chinaTime().weekday > 5;
      final pending = await ProgressService.getTodayPending();
      expect(pending, isWeekend ? 2 : 4);
    });

    test('weekday: 3 when recap is done', () async {
      final isWeekend = _chinaTime().weekday > 5;
      SharedPreferences.setMockInitialValues({
        'debt_module_status': _statusFor(_todayStr(), {'recap': true}),
      });
      expect(await ProgressService.getTodayPending(), isWeekend ? 2 : 3);
    });

    test('returns 0 when all required modules are done', () async {
      SharedPreferences.setMockInitialValues({
        'debt_module_status': _statusFor(_todayStr(), {
          'recap': true, 'reader': true, 'quiz': true, 'listen': true,
        }),
      });
      expect(await ProgressService.getTodayPending(), 0);
    });

    test('yesterday completion does not count as today', () async {
      final y = _chinaTime().subtract(const Duration(days: 1));
      final yStr = '${y.year}-${y.month.toString().padLeft(2, '0')}-${y.day.toString().padLeft(2, '0')}';
      final isWeekend = _chinaTime().weekday > 5;
      SharedPreferences.setMockInitialValues({
        'debt_module_status': _statusFor(yStr, {
          'recap': true, 'reader': true, 'quiz': true, 'listen': true,
        }),
      });
      expect(await ProgressService.getTodayPending(), isWeekend ? 2 : 4);
    });
  });

  group('ProgressService.getDebtByDate', () {
    test('returns empty map when no data', () async {
      expect(await ProgressService.getDebtByDate(), isEmpty);
    });

    test('parses cached debt data correctly', () async {
      final debtData = {'2026-04-01': 3, '2026-04-02': 4, '2026-04-03': 1};
      SharedPreferences.setMockInitialValues({
        'debt_by_date': jsonEncode(debtData),
      });
      final debt = await ProgressService.getDebtByDate();
      expect(debt['2026-04-01'], 3);
      expect(debt['2026-04-02'], 4);
      expect(debt['2026-04-03'], 1);
    });
  });

  group('ProgressService.getTotalOwed', () {
    test('returns 0 when no data', () async {
      expect(await ProgressService.getTotalOwed(), 0);
    });

    test('returns cached value', () async {
      SharedPreferences.setMockInitialValues({'total_owed': 12});
      expect(await ProgressService.getTotalOwed(), 12);
    });
  });

  group('ProgressService.getModuleStatusForDate', () {
    test('returns empty map for missing date', () async {
      expect(await ProgressService.getModuleStatusForDate('2026-04-01'), isEmpty);
    });

    test('returns correct module status for a date', () async {
      SharedPreferences.setMockInitialValues({
        'debt_module_status': jsonEncode({
          '2026-04-01': {'recap': true, 'reader': true, 'quiz': false, 'listen': false},
        }),
      });
      final status = await ProgressService.getModuleStatusForDate('2026-04-01');
      expect(status['recap'], true);
      expect(status['quiz'], false);
    });
  });

  group('ProgressService.markModuleComplete', () {
    test('marks module done in debt_module_status (single source of truth)', () async {
      await ProgressService.markModuleComplete('reader', 10);
      expect(await ProgressService.isDoneToday('reader'), true);
    });

    test('increments total stars', () async {
      SharedPreferences.setMockInitialValues({'total_stars': 50});
      await ProgressService.markModuleComplete('quiz', 20);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('total_stars'), 70);
    });

    test('does not double-add stars on repeat completion', () async {
      SharedPreferences.setMockInitialValues({'total_stars': 0});
      await ProgressService.markModuleComplete('reader', 10);
      await ProgressService.markModuleComplete('reader', 10);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('total_stars'), 10);
    });

    test('updates streak on first completion of the day', () async {
      final y = _chinaTime().subtract(const Duration(days: 1));
      final yStr = '${y.year}-${y.month.toString().padLeft(2, '0')}-${y.day.toString().padLeft(2, '0')}';
      SharedPreferences.setMockInitialValues({
        'streak_days': 3,
        'last_completed_date': yStr,
      });
      await ProgressService.markModuleComplete('reader', 10);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('streak_days'), 4);
    });

    test('resets streak when day is skipped', () async {
      final t = _chinaTime().subtract(const Duration(days: 3));
      final tStr = '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
      SharedPreferences.setMockInitialValues({
        'streak_days': 10,
        'last_completed_date': tStr,
      });
      await ProgressService.markModuleComplete('reader', 10);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('streak_days'), 1);
    });

    test('records active date', () async {
      await ProgressService.markModuleComplete('reader', 10);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('active_dates') ?? '', isNotEmpty);
    });
  });

  group('ProgressService.getTodayProgress', () {
    test('returns all fields with defaults', () async {
      final progress = await ProgressService.getTodayProgress();
      expect(progress['total_stars'], 0);
      expect(progress['streak_days'], 0);
      expect(progress['reader_done'], false);
      expect(progress['phonics_done'], false);
      expect(progress['quiz_done'], false);
      expect(progress['recording_done'], false);
      expect((progress['week_active'] as List).length, 7);
    });

    test('reflects completed modules from debt_module_status', () async {
      SharedPreferences.setMockInitialValues({
        'total_stars': 100,
        'streak_days': 5,
        'debt_module_status': _statusFor(_todayStr(), {'reader': true, 'quiz': true}),
      });
      final progress = await ProgressService.getTodayProgress();
      expect(progress['total_stars'], 100);
      expect(progress['streak_days'], 5);
      expect(progress['reader_done'], true);
      expect(progress['quiz_done'], true);
      expect(progress['phonics_done'], false);
    });
  });
}

DateTime _chinaTime() => DateTime.now().toUtc().add(const Duration(hours: 8));

String _todayStr() {
  final now = _chinaTime();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}
