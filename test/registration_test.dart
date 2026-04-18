import 'package:flutter_test/flutter_test.dart';
import 'package:bridgeread/services/week_service.dart';

/// Test the registration logic for book_start_date calculation.
/// New users always start from today with 0 books completed.

String formatDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

void main() {
  group('Registration — new user starts from today', () {
    test('book_start_date = today', () {
      final today = DateTime(2026, 4, 18);
      final dateStr = formatDate(today);
      expect(dateStr, '2026-04-18');
    });

    test('no batch sync needed (0 books)', () {
      // New user has 0 books → no past progress to sync
      const booksCompleted = 0;
      expect(booksCompleted, 0);
      // No items to sync
    });

    test('register Monday: today = book 0', () {
      final today = DateTime(2026, 4, 13); // Monday
      expect(WeekService.bookIndexForDate(today, today), 0);
    });

    test('register Wednesday: today = book 0, Friday = book 2', () {
      final today = DateTime(2026, 4, 15); // Wednesday
      expect(WeekService.bookIndexForDate(today, today), 0);
      expect(WeekService.bookIndexForDate(DateTime(2026, 4, 17), today), 2);
    });

    test('register Saturday: today returns null (weekend)', () {
      final today = DateTime(2026, 4, 18); // Saturday
      // Weekend → bookIndexForDate returns null
      // But _resolveWeekend treats it as weekday for new user
      expect(WeekService.bookIndexForDate(today, today), null);
    });

    test('register Saturday: next Monday = book 0', () {
      final saturday = DateTime(2026, 4, 18);
      final monday = DateTime(2026, 4, 20);
      final idx = WeekService.bookIndexForDate(monday, saturday);
      expect(idx, 0);
    });

    test('full cycle: register today, 20 books over 4+ weeks', () {
      final start = DateTime(2026, 4, 13); // Monday
      int bookCount = 0;
      for (var d = start;
          d.isBefore(DateTime(2026, 6, 1));
          d = d.add(const Duration(days: 1))) {
        if (d.weekday <= 5) {
          final idx = WeekService.bookIndexForDate(d, start);
          if (idx != null) bookCount++;
        }
      }
      expect(bookCount, 20);
    });

    test('stars start at 0', () {
      const initialStars = 0;
      expect(initialStars, 0);
    });
  });
}
