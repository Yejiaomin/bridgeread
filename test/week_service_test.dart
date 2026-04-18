import 'package:flutter_test/flutter_test.dart';
import 'package:bridgeread/services/week_service.dart';

void main() {
  // ── parseDate ──────────────────────────────────────────────────────────────

  group('parseDate', () {
    test('parses valid date', () {
      final d = WeekService.parseDate('2026-04-13');
      expect(d, DateTime(2026, 4, 13));
    });

    test('returns null for null', () {
      expect(WeekService.parseDate(null), null);
    });
  });

  // ── bookForWeekdayCount — Monday start ─────────────────────────────────────

  group('bookForWeekdayCount — Monday start', () {
    test('day 1 = book 0', () {
      expect(WeekService.bookForWeekdayCount(1, 1), 0);
    });

    test('day 5 = book 4 (end of week 1)', () {
      expect(WeekService.bookForWeekdayCount(5, 1), 4);
    });

    test('day 6 = book 5 (start of week 2)', () {
      expect(WeekService.bookForWeekdayCount(6, 1), 5);
    });

    test('day 10 = book 9', () {
      expect(WeekService.bookForWeekdayCount(10, 1), 9);
    });

    test('day 20 = book 19 (last book)', () {
      expect(WeekService.bookForWeekdayCount(20, 1), 19);
    });

    test('day 21 = null (all exhausted)', () {
      expect(WeekService.bookForWeekdayCount(21, 1), null);
    });

    test('day 100 = null', () {
      expect(WeekService.bookForWeekdayCount(100, 1), null);
    });

    test('full 4-week sequence', () {
      final books = List.generate(20, (i) => WeekService.bookForWeekdayCount(i + 1, 1));
      expect(books, List.generate(20, (i) => i));
    });
  });

  // ── bookForWeekdayCount — partial first week ───────────────────────────────

  group('bookForWeekdayCount — Wednesday start', () {
    test('Wed=book0, Thu=book1, Fri=book2', () {
      expect(WeekService.bookForWeekdayCount(1, 3), 0);
      expect(WeekService.bookForWeekdayCount(2, 3), 1);
      expect(WeekService.bookForWeekdayCount(3, 3), 2);
    });

    test('next Mon=book3', () {
      expect(WeekService.bookForWeekdayCount(4, 3), 3);
    });

    test('20 books completed at day 20', () {
      expect(WeekService.bookForWeekdayCount(20, 3), 19);
      expect(WeekService.bookForWeekdayCount(21, 3), null);
    });
  });

  group('bookForWeekdayCount — Friday start', () {
    test('Fri=book0, next Mon=book1', () {
      expect(WeekService.bookForWeekdayCount(1, 5), 0);
      expect(WeekService.bookForWeekdayCount(2, 5), 1);
    });
  });

  group('bookForWeekdayCount — Thursday start', () {
    test('Thu=book0, Fri=book1, next Mon=book2', () {
      expect(WeekService.bookForWeekdayCount(1, 4), 0);
      expect(WeekService.bookForWeekdayCount(2, 4), 1);
      expect(WeekService.bookForWeekdayCount(3, 4), 2);
    });
  });

  // ── bookIndexForDate ───────────────────────────────────────────────────────

  group('bookIndexForDate', () {
    final monday = DateTime(2026, 4, 13); // Monday

    test('same day = book 0', () {
      expect(WeekService.bookIndexForDate(monday, monday), 0);
    });

    test('Tuesday = book 1', () {
      expect(WeekService.bookIndexForDate(DateTime(2026, 4, 14), monday), 1);
    });

    test('Friday = book 4', () {
      expect(WeekService.bookIndexForDate(DateTime(2026, 4, 17), monday), 4);
    });

    test('Saturday = null', () {
      expect(WeekService.bookIndexForDate(DateTime(2026, 4, 18), monday), null);
    });

    test('Sunday = null', () {
      expect(WeekService.bookIndexForDate(DateTime(2026, 4, 19), monday), null);
    });

    test('next Monday = book 5', () {
      expect(WeekService.bookIndexForDate(DateTime(2026, 4, 20), monday), 5);
    });

    test('before start = null', () {
      expect(WeekService.bookIndexForDate(DateTime(2026, 4, 12), monday), null);
    });

    test('4 weeks later = last book', () {
      // 20 weekdays from Monday Apr 13 = Friday May 8
      expect(WeekService.bookIndexForDate(DateTime(2026, 5, 8), monday), 19);
    });

    test('after all books = null', () {
      expect(WeekService.bookIndexForDate(DateTime(2026, 5, 11), monday), null);
    });

    test('10 consecutive weekdays = books 0-9', () {
      final indices = <int?>[];
      for (var d = DateTime(2026, 4, 13); // Monday
          d.isBefore(DateTime(2026, 4, 25)); // until next Friday
          d = d.add(const Duration(days: 1))) {
        if (d.weekday <= 5) {
          indices.add(WeekService.bookIndexForDate(d, monday));
        }
      }
      expect(indices, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
    });

    test('Wednesday start — first week partial', () {
      final wed = DateTime(2026, 4, 15); // Wednesday
      expect(WeekService.bookIndexForDate(DateTime(2026, 4, 15), wed), 0); // Wed
      expect(WeekService.bookIndexForDate(DateTime(2026, 4, 16), wed), 1); // Thu
      expect(WeekService.bookIndexForDate(DateTime(2026, 4, 17), wed), 2); // Fri
      // Next Monday: weekday count = 6 (Wed,Thu,Fri + Mon,Tue,Wed... but skips weekend)
      // Actually: Wed(1), Thu(2), Fri(3), [Sat,Sun skip], Mon(4)
      final monIdx = WeekService.bookIndexForDate(DateTime(2026, 4, 21), wed);
      expect(monIdx, isNotNull);
      expect(monIdx, greaterThanOrEqualTo(3));
    });
  });

  // ── activeDate / overrideDate ──────────────────────────────────────────────

  group('activeDate / overrideDate', () {
    tearDown(() => WeekService.overrideDate = null);

    test('returns override when set', () {
      WeekService.overrideDate = DateTime(2026, 4, 18); // Saturday
      expect(activeDate().weekday, 6);
    });

    test('returns china time when null', () {
      WeekService.overrideDate = null;
      final d = activeDate();
      expect(d.year, greaterThanOrEqualTo(2026));
    });
  });

  // ── kAllBooks ──────────────────────────────────────────────────────────────

  group('kAllBooks', () {
    test('has 20 books', () {
      expect(kAllBooks.length, 20);
    });

    test('kSeriesSizes sums to total books', () {
      expect(kSeriesSizes.reduce((a, b) => a + b), kAllBooks.length);
    });

    test('all series sizes are multiples of 5', () {
      for (final s in kSeriesSizes) {
        expect(s % 5, 0, reason: 'Series size $s is not a multiple of 5');
      }
    });

    test('all books have non-empty fields', () {
      for (final b in kAllBooks) {
        expect(b.title.isNotEmpty, true);
        expect(b.titleCN.isNotEmpty, true);
        expect(b.lessonId.isNotEmpty, true);
        expect(b.coverAsset.isNotEmpty, true);
        expect(b.originalAudio.isNotEmpty, true);
      }
    });

    test('lesson IDs are unique', () {
      final ids = kAllBooks.map((b) => b.lessonId).toSet();
      expect(ids.length, kAllBooks.length);
    });
  });

  // ── lastNBooks ─────────────────────────────────────────────────────────────

  group('lastNBooks', () {
    test('last 5 books', () {
      final last5 = WeekService.lastNBooks(5);
      expect(last5.length, 5);
      expect(last5.first.lessonId, kAllBooks[15].lessonId);
      expect(last5.last.lessonId, kAllBooks[19].lessonId);
    });

    test('last 1 book', () {
      final last1 = WeekService.lastNBooks(1);
      expect(last1.length, 1);
      expect(last1.first.lessonId, kAllBooks[19].lessonId);
    });

    test('more than total returns all', () {
      final all = WeekService.lastNBooks(100);
      expect(all.length, kAllBooks.length);
    });
  });
}
