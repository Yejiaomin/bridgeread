import 'dart:math' show min;
import 'package:shared_preferences/shared_preferences.dart';

/// Book metadata for the ordered book list.
class BookInfo {
  final String title;
  final String titleCN;
  final String lessonId;
  final String coverAsset;
  final String originalAudio;
  const BookInfo(this.title, this.titleCN, this.lessonId, this.coverAsset, this.originalAudio);
}

/// All books in learning order. New books are appended here.
const kAllBooks = [
  BookInfo('Biscuit', '小饼干', 'biscuit_book1_day1', 'assets/books/01Biscuit/cover.webp', 'audio/biscuit_original.mp3'),
  BookInfo('Biscuit and the Baby', '小饼干和宝宝', 'biscuit_baby_book2_day1', 'assets/books/02Biscuit_and_the_Baby/cover.webp', 'audio/biscuit_baby_original.mp3'),
  BookInfo('Biscuit Loves the Library', '小饼干爱图书馆', 'biscuit_library_book3_day1', 'assets/books/03Biscuit_Loves_the_Library/cover.webp', 'books/03Biscuit_Loves_the_Library/audio.mp3'),
  BookInfo('Biscuit Finds a Friend', '小饼干找朋友', 'friend_book04_day1', 'assets/books/04Biscuit_Finds_a_Friend/cover.webp', 'books/04Biscuit_Finds_a_Friend/audio.mp3'),
  BookInfo("Biscuit's New Trick", '小饼干的新把戏', 'trick_book05_day1', 'assets/books/05Biscuits_New_Trick/cover.webp', 'books/05Biscuits_New_Trick/audio.mp3'),
  BookInfo("Biscuit's Day at the Farm", '小饼干的农场日', 'farm_book06_day1', 'assets/books/06Biscuits_Day_at_the_Farm/cover.webp', 'books/06Biscuits_Day_at_the_Farm/audio.mp3'),
  BookInfo('Bathtime for Biscuit', '小饼干洗澡啦', 'bath_book07_day1', 'assets/books/07Bathtime_for_Biscuit/cover.webp', 'books/07Bathtime_for_Biscuit/audio.mp3'),
  BookInfo('Biscuit Wins a Prize', '小饼干赢奖啦', 'prize_book08_day1', 'assets/books/08Biscuit_Wins_a_Prize/cover.webp', 'books/08Biscuit_Wins_a_Prize/audio.mp3'),
  BookInfo('Biscuit Visits the Big City', '小饼干游大城市', 'city_book09_day1', 'assets/books/09Biscuit_Visits_the_Big_City/cover.webp', 'books/09Biscuit_Visits_the_Big_City/audio.mp3'),
  BookInfo('Biscuit Plays Ball', '小饼干打球', 'ball_book10_day1', 'assets/books/10Biscuit_Plays_Ball/cover.webp', 'books/10Biscuit_Plays_Ball/audio.mp3'),
  // 新书追加到这里
];

/// Series sizes. Each entry = number of books in that series.
/// Example: [5, 15] → books 0-4 are series 1, books 5-19 are series 2.
/// When series ends mid-week, remaining weekdays are review (复习).
/// Next series always starts on Monday.
const kSeriesSizes = [20];

DateTime _chinaTime() => DateTime.now().toUtc().add(const Duration(hours: 8));

class WeekService {
  /// Count weekdays (Mon-Fri) from [start] to [end], inclusive.
  static int _weekdaysBetween(DateTime start, DateTime end) {
    int count = 0;
    var d = DateTime(start.year, start.month, start.day);
    final e = DateTime(end.year, end.month, end.day);
    while (!d.isAfter(e)) {
      if (d.weekday <= 5) count++;
      d = d.add(const Duration(days: 1));
    }
    return count;
  }

  /// Core scheduling: map a weekday count (1-based) to a book index in kAllBooks.
  /// Returns null if it's a review/padding day (series ended mid-week)
  /// or if all books are exhausted.
  ///
  /// [startWeekday]: 1=Mon..5=Fri, the day the child first started.
  static int? _bookForWeekdayCount(int weekdayCount, int startWeekday) {
    int bookIdx = 0;         // next book to assign
    int daysProcessed = 0;   // weekday slots consumed so far
    int weekCapacity = 5 - startWeekday + 1; // first week may be partial

    int seriesStart = 0;
    int si = 0;

    while (seriesStart < kAllBooks.length) {
      // Current series size
      final seriesSize = si < kSeriesSizes.length
          ? kSeriesSizes[si]
          : kAllBooks.length - seriesStart;
      final seriesEnd = min(seriesStart + seriesSize, kAllBooks.length);

      // Assign books to weeks within this series
      while (bookIdx < seriesEnd) {
        final booksLeft = seriesEnd - bookIdx;
        final booksThisWeek = min(booksLeft, weekCapacity);

        // Target day is in the "new book" portion of this week?
        if (weekdayCount <= daysProcessed + booksThisWeek) {
          return bookIdx + (weekdayCount - daysProcessed - 1);
        }

        // Target day is in the "review padding" portion of this week?
        if (weekdayCount <= daysProcessed + weekCapacity) {
          return null; // review day
        }

        // Move to next week
        bookIdx += booksThisWeek;
        daysProcessed += weekCapacity;
        weekCapacity = 5; // subsequent weeks are always full
      }

      // Series done → next series starts next Monday (padding already handled above)
      si++;
      seriesStart = seriesEnd;
    }

    return null; // all books exhausted
  }

  /// Today's book index (0-based) in kAllBooks.
  /// Returns null on weekends, review days, or if all books are finished.
  static Future<int?> todayBookIndex() async {
    final prefs = await SharedPreferences.getInstance();
    final startStr = prefs.getString('book_start_date');
    if (startStr == null) return 0;
    final start = parseDate(startStr)!;
    final now = _chinaTime();
    if (now.weekday > 5) return null; // weekend
    final wdCount = _weekdaysBetween(start, now);
    if (wdCount <= 0) return null;
    return _bookForWeekdayCount(wdCount, start.weekday);
  }

  /// Whether today is a review/padding day (series ended but week hasn't).
  static Future<bool> isReviewDay() async {
    final now = _chinaTime();
    if (now.weekday > 5) return false; // weekends are handled separately
    final idx = await todayBookIndex();
    return idx == null;
  }

  /// This week's books (only actual new-book days, not review padding).
  /// Works for both weekdays and weekends.
  static Future<List<BookInfo>> thisWeekBooks() async {
    final prefs = await SharedPreferences.getInstance();
    final startStr = prefs.getString('book_start_date');
    if (startStr == null) return kAllBooks.take(5).toList();
    final start = parseDate(startStr)!;
    final now = _chinaTime();

    // This week's Monday and Friday
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    final friday = monday.add(const Duration(days: 4));

    final books = <BookInfo>[];
    var day = start.isAfter(monday) ? start : monday;
    while (!day.isAfter(friday)) {
      if (day.weekday <= 5) {
        final wdCount = _weekdaysBetween(start, day);
        final idx = _bookForWeekdayCount(wdCount, start.weekday);
        if (idx != null && idx < kAllBooks.length) {
          books.add(kAllBooks[idx]);
        }
      }
      day = day.add(const Duration(days: 1));
    }
    return books;
  }

  /// This week's lesson IDs (convenience).
  static Future<List<String>> thisWeekLessonIds() async {
    final books = await thisWeekBooks();
    return books.map((b) => b.lessonId).toList();
  }

  /// Parse start date from prefs string.
  static DateTime? parseDate(String? s) {
    if (s == null) return null;
    final parts = s.split('-');
    return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
  }
}
