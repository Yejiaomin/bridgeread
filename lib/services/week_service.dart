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
  // 新书追加到这里
];

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

  /// Today's book index (0-based) in kAllBooks.
  /// Returns null on weekends or if all books are finished.
  static Future<int?> todayBookIndex() async {
    final prefs = await SharedPreferences.getInstance();
    final startStr = prefs.getString('book_start_date');
    if (startStr == null) return 0;
    final parts = startStr.split('-');
    final start = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
    final now = _chinaTime();
    if (now.weekday > 5) return null; // weekend
    final idx = _weekdaysBetween(start, now) - 1; // 0-based
    if (idx < 0 || idx >= kAllBooks.length) return null;
    return idx;
  }

  /// This week's books (the books studied Mon-Fri of current calendar week).
  /// On weekends, returns all books from Mon-Fri of this week.
  static Future<List<BookInfo>> thisWeekBooks() async {
    final prefs = await SharedPreferences.getInstance();
    final startStr = prefs.getString('book_start_date');
    if (startStr == null) return kAllBooks.take(5).toList();
    final parts = startStr.split('-');
    final start = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
    final now = _chinaTime();

    // Find this week's Monday and Friday
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    final friday = monday.add(const Duration(days: 4));

    // Effective start: max(start_date, this_monday)
    final effectiveStart = start.isAfter(monday) ? start : monday;

    // If start is after Friday, no books this week
    if (effectiveStart.isAfter(friday)) return [];

    // Book index for effectiveStart = weekdays from original start to effectiveStart
    final startIdx = _weekdaysBetween(start, effectiveStart) - 1;

    // Book index for Friday (or today if weekday)
    final effectiveEnd = now.weekday <= 5 ? now : friday;
    final endIdx = _weekdaysBetween(start, effectiveEnd) - 1;

    // Clamp to available books
    final from = startIdx.clamp(0, kAllBooks.length);
    final to = (endIdx + 1).clamp(0, kAllBooks.length);
    if (from >= to) return [];
    return kAllBooks.sublist(from, to);
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
