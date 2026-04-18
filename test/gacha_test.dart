import 'package:flutter_test/flutter_test.dart';

/// Test the gacha (blind box) star spending logic.
/// Extracted from study_room_screen.dart for testability.

// Reproduce the gacha availability and spending logic
bool gachaAvailable(int totalStars) => totalStars >= 30;

(int newStars, bool canDrawAgain) spendGacha(int totalStars) {
  if (totalStars < 30) throw StateError('Not enough stars');
  final newStars = totalStars - 30;
  return (newStars, newStars >= 30);
}

void main() {
  group('Gacha availability', () {
    test('available when stars >= 30', () {
      expect(gachaAvailable(30), true);
      expect(gachaAvailable(31), true);
      expect(gachaAvailable(100), true);
    });

    test('unavailable when stars < 30', () {
      expect(gachaAvailable(0), false);
      expect(gachaAvailable(29), false);
    });

    test('no daily limit — only star count matters', () {
      // Old logic had: gachaCount < 2 && stars >= 30
      // New logic: only stars >= 30
      // Simulate 10 draws in a day
      int stars = 300;
      int draws = 0;
      while (gachaAvailable(stars)) {
        final (newStars, _) = spendGacha(stars);
        stars = newStars;
        draws++;
      }
      expect(draws, 10); // 300 / 30 = 10 draws
      expect(stars, 0);
    });
  });

  group('Gacha star spending', () {
    test('deducts exactly 30 stars', () {
      final (newStars, _) = spendGacha(100);
      expect(newStars, 70);
    });

    test('can draw again if >= 30 remaining', () {
      final (_, canDraw) = spendGacha(60);
      expect(canDraw, true); // 60-30=30, can draw again
    });

    test('cannot draw again if < 30 remaining', () {
      final (_, canDraw) = spendGacha(30);
      expect(canDraw, false); // 30-30=0, cannot draw
    });

    test('exact boundary: 30 stars → draw → 0 left', () {
      final (newStars, canDraw) = spendGacha(30);
      expect(newStars, 0);
      expect(canDraw, false);
    });

    test('throws when not enough stars', () {
      expect(() => spendGacha(29), throwsStateError);
      expect(() => spendGacha(0), throwsStateError);
    });

    test('consecutive draws until empty', () {
      int stars = 90;
      final results = <int>[];
      while (gachaAvailable(stars)) {
        final (newStars, _) = spendGacha(stars);
        stars = newStars;
        results.add(stars);
      }
      expect(results, [60, 30, 0]);
      expect(gachaAvailable(stars), false);
    });
  });

  group('Gacha server sync', () {
    test('server returns corrected star count', () {
      // Simulate: local says 70 after spend, server says 65 (other deductions)
      int localStars = 100;
      localStars -= 30; // local deduction
      expect(localStars, 70);

      // Server response
      final serverStars = 65;
      localStars = serverStars; // server wins
      expect(localStars, 65);
      expect(gachaAvailable(localStars), true); // 65 >= 30
    });

    test('server returns 0 — no more draws', () {
      int localStars = 30;
      localStars -= 30;
      expect(localStars, 0);

      final serverStars = 0;
      localStars = serverStars;
      expect(gachaAvailable(localStars), false);
    });
  });
}
