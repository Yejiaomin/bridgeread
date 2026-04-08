import 'package:flutter_test/flutter_test.dart';
import 'package:bridgeread/services/week_service.dart';

void main() {
  group('WeekService.parseDate', () {
    test('parses valid date string', () {
      final d = WeekService.parseDate('2026-04-07');
      expect(d, isNotNull);
      expect(d!.year, 2026);
      expect(d.month, 4);
      expect(d.day, 7);
    });

    test('returns null for null input', () {
      expect(WeekService.parseDate(null), isNull);
    });
  });

  group('WeekService.bookIndexForDate', () {
    // Start date: Monday 2026-03-30
    final startMon = DateTime(2026, 3, 30);

    test('first weekday returns book index 0', () {
      final idx = WeekService.bookIndexForDate(DateTime(2026, 3, 30), startMon);
      expect(idx, 0);
    });

    test('second weekday returns book index 1', () {
      final idx = WeekService.bookIndexForDate(DateTime(2026, 3, 31), startMon);
      expect(idx, 1);
    });

    test('fifth weekday (Friday) returns book index 4', () {
      final idx = WeekService.bookIndexForDate(DateTime(2026, 4, 3), startMon);
      expect(idx, 4);
    });

    test('Saturday returns null (weekend)', () {
      final idx = WeekService.bookIndexForDate(DateTime(2026, 4, 4), startMon);
      expect(idx, isNull);
    });

    test('Sunday returns null (weekend)', () {
      final idx = WeekService.bookIndexForDate(DateTime(2026, 4, 5), startMon);
      expect(idx, isNull);
    });

    test('next Monday returns book index 5', () {
      final idx = WeekService.bookIndexForDate(DateTime(2026, 4, 6), startMon);
      expect(idx, 5);
    });

    test('date before start returns null', () {
      final idx = WeekService.bookIndexForDate(DateTime(2026, 3, 29), startMon);
      expect(idx, isNull);
    });

    // Start date: Wednesday 2026-04-01
    final startWed = DateTime(2026, 4, 1);

    test('start on Wednesday — first day is book 0', () {
      final idx = WeekService.bookIndexForDate(DateTime(2026, 4, 1), startWed);
      expect(idx, 0);
    });

    test('start on Wednesday — Friday is book 2', () {
      final idx = WeekService.bookIndexForDate(DateTime(2026, 4, 3), startWed);
      expect(idx, 2);
    });

    test('start on Wednesday — next Monday is book 3', () {
      final idx = WeekService.bookIndexForDate(DateTime(2026, 4, 6), startWed);
      expect(idx, 3);
    });

    test('consecutive weekdays get consecutive books', () {
      final indices = <int?>[];
      // Two weeks: Mon Mar 30 to Fri Apr 10
      for (var d = DateTime(2026, 3, 30);
          d.isBefore(DateTime(2026, 4, 11));
          d = d.add(const Duration(days: 1))) {
        if (d.weekday <= 5) {
          indices.add(WeekService.bookIndexForDate(d, startMon));
        }
      }
      // Should be 0,1,2,3,4,5,6,7,8,9
      expect(indices, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
    });
  });

  group('WeekService.bookForWeekdayCount', () {
    test('weekday count 1 returns book 0', () {
      expect(WeekService.bookForWeekdayCount(1, 1), 0);
    });

    test('weekday count 5 returns book 4', () {
      expect(WeekService.bookForWeekdayCount(5, 1), 4);
    });

    test('weekday count 6 returns book 5 (second week)', () {
      expect(WeekService.bookForWeekdayCount(6, 1), 5);
    });

    test('start on Wednesday (weekday 3): first week has 3 books', () {
      // Wed=1, Thu=2, Fri=3 → books 0,1,2
      expect(WeekService.bookForWeekdayCount(1, 3), 0);
      expect(WeekService.bookForWeekdayCount(2, 3), 1);
      expect(WeekService.bookForWeekdayCount(3, 3), 2);
      // Next week starts at book 3
      expect(WeekService.bookForWeekdayCount(4, 3), 3);
    });

    test('start on Friday (weekday 5): first week has 1 book', () {
      expect(WeekService.bookForWeekdayCount(1, 5), 0);
      // Next week starts at book 1
      expect(WeekService.bookForWeekdayCount(2, 5), 1);
    });
  });

  group('WeekService.overrideDate', () {
    tearDown(() {
      WeekService.overrideDate = null;
    });

    test('activeDate returns overrideDate when set', () {
      final override = DateTime(2026, 3, 30);
      WeekService.overrideDate = override;
      final active = activeDate();
      expect(active.year, 2026);
      expect(active.month, 3);
      expect(active.day, 30);
    });

    test('activeDate returns real time when overrideDate is null', () {
      WeekService.overrideDate = null;
      final active = activeDate();
      // Should be close to now (within a day, accounting for China time)
      final now = DateTime.now();
      expect(active.difference(now).inDays.abs(), lessThanOrEqualTo(1));
    });

    test('setting overrideDate to weekend affects weekend detection', () {
      // Saturday
      WeekService.overrideDate = DateTime(2026, 4, 4);
      expect(activeDate().weekday, 6);

      // Monday
      WeekService.overrideDate = DateTime(2026, 4, 6);
      expect(activeDate().weekday, 1);
    });
  });

  group('kAllBooks', () {
    test('has at least 20 books', () {
      expect(kAllBooks.length, greaterThanOrEqualTo(20));
    });

    test('all books have required fields', () {
      for (final book in kAllBooks) {
        expect(book.title, isNotEmpty);
        expect(book.titleCN, isNotEmpty);
        expect(book.lessonId, isNotEmpty);
        expect(book.coverAsset, isNotEmpty);
        expect(book.originalAudio, isNotEmpty);
      }
    });

    test('all lessonIds are unique', () {
      final ids = kAllBooks.map((b) => b.lessonId).toSet();
      expect(ids.length, kAllBooks.length);
    });
  });
}
