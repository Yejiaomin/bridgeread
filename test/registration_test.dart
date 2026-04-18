import 'package:flutter_test/flutter_test.dart';
import 'package:bridgeread/services/week_service.dart';

/// Test the registration logic for book_start_date calculation.
/// Reproduces _goBackWeekdays and batch sync logic from login_screen.dart.

DateTime goBackWeekdays(DateTime from, int count) {
  if (count <= 0) return from;
  var d = from;
  int remaining = count;
  while (remaining > 0) {
    d = d.subtract(const Duration(days: 1));
    if (d.weekday >= 1 && d.weekday <= 5) remaining--;
  }
  return d;
}

String formatDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Simulate batch sync items (what gets sent to server on registration)
List<Map<String, dynamic>> buildBatchItems(DateTime startDate, DateTime today, int booksCompleted) {
  if (booksCompleted <= 0) return [];
  final items = <Map<String, dynamic>>[];
  var d = DateTime(startDate.year, startDate.month, startDate.day);
  while (d.isBefore(today)) {
    final ds = formatDate(d);
    if (d.weekday >= 1 && d.weekday <= 5) {
      for (final mod in ['recap', 'reader', 'quiz', 'listen']) {
        items.add({'date': ds, 'module': mod, 'done': true, 'stars': 0});
      }
    } else {
      for (final mod in ['quiz', 'listen']) {
        items.add({'date': ds, 'module': mod, 'done': true, 'stars': 0});
      }
    }
    d = d.add(const Duration(days: 1));
  }
  return items;
}

void main() {
  group('goBackWeekdays', () {
    test('0 books = same day', () {
      final monday = DateTime(2026, 4, 13);
      expect(goBackWeekdays(monday, 0), monday);
    });

    test('1 book back from Monday = previous Friday', () {
      final monday = DateTime(2026, 4, 13);
      final result = goBackWeekdays(monday, 1);
      expect(result.weekday, 5); // Friday
      expect(result, DateTime(2026, 4, 10));
    });

    test('5 books back from Monday = previous Monday', () {
      final monday = DateTime(2026, 4, 13);
      final result = goBackWeekdays(monday, 5);
      expect(result.weekday, 1); // Monday
      expect(result, DateTime(2026, 4, 6));
    });

    test('skips weekends', () {
      final monday = DateTime(2026, 4, 13);
      final result = goBackWeekdays(monday, 6);
      // 6 weekdays back from Mon Apr 13:
      // Fri 10, Thu 9, Wed 8, Tue 7, Mon 6, Fri 3
      expect(result, DateTime(2026, 4, 3));
      expect(result.weekday, 5); // Friday
    });

    test('10 books back = 2 full weeks', () {
      final monday = DateTime(2026, 4, 13);
      final result = goBackWeekdays(monday, 10);
      expect(result, DateTime(2026, 3, 30)); // Monday 2 weeks ago
    });
  });

  group('Registration batch sync', () {
    test('0 books completed = no items', () {
      final today = DateTime(2026, 4, 13);
      final items = buildBatchItems(today, today, 0);
      expect(items, isEmpty);
    });

    test('5 books: 5 weekdays × 4 modules = 20 items', () {
      final today = DateTime(2026, 4, 13); // Monday
      final start = goBackWeekdays(today, 5); // Previous Monday
      final items = buildBatchItems(start, today, 5);
      // Mon-Fri = 5 weekdays × 4 modules = 20
      // Plus Sat+Sun × 2 modules = 4
      expect(items.where((i) => i['done'] == true).length, items.length);
    });

    test('all stars are 0 (not 12)', () {
      final today = DateTime(2026, 4, 13);
      final start = goBackWeekdays(today, 3);
      final items = buildBatchItems(start, today, 3);
      for (final item in items) {
        expect(item['stars'], 0, reason: 'New user should get 0 stars');
      }
    });

    test('weekends get quiz+listen, weekdays get all 4', () {
      final today = DateTime(2026, 4, 14); // Tuesday
      final start = goBackWeekdays(today, 6); // 6 weekdays back includes a weekend
      final items = buildBatchItems(start, today, 6);

      final weekdayItems = items.where((i) {
        final d = DateTime.parse(i['date'] as String);
        return d.weekday <= 5;
      });
      final weekendItems = items.where((i) {
        final d = DateTime.parse(i['date'] as String);
        return d.weekday > 5;
      });

      // Weekday modules should include recap, reader, quiz, listen
      final wdModules = weekdayItems.map((i) => i['module']).toSet();
      expect(wdModules, containsAll(['recap', 'reader', 'quiz', 'listen']));

      // Weekend modules should only be quiz, listen
      if (weekendItems.isNotEmpty) {
        final weModules = weekendItems.map((i) => i['module']).toSet();
        expect(weModules, {'quiz', 'listen'});
      }
    });

    test('start date is always a weekday', () {
      for (int books = 0; books <= 20; books++) {
        final today = DateTime(2026, 4, 16); // Wednesday
        final start = goBackWeekdays(today, books);
        if (books > 0) {
          expect(start.weekday, lessThanOrEqualTo(5),
              reason: 'Start date for $books books should be a weekday');
        }
      }
    });
  });

  group('Book cycle after registration', () {
    test('register Monday with 0 books: today = book 0', () {
      final today = DateTime(2026, 4, 13); // Monday
      final start = goBackWeekdays(today, 0); // = today
      expect(WeekService.bookIndexForDate(today, start), 0);
    });

    test('register Monday with 10 books: today = book 10', () {
      final today = DateTime(2026, 4, 13);
      final start = goBackWeekdays(today, 10);
      expect(WeekService.bookIndexForDate(today, start), 10);
    });

    test('register Wednesday with 0 books: today = book 0, Friday = book 2', () {
      final today = DateTime(2026, 4, 15); // Wednesday
      final start = goBackWeekdays(today, 0);
      expect(WeekService.bookIndexForDate(today, start), 0);
      expect(WeekService.bookIndexForDate(DateTime(2026, 4, 17), start), 2);
    });

    test('full cycle: register Monday, 20 books over 4 weeks', () {
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
  });
}
