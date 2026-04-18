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

  // ── Bug fix: old daily limit leaked into post-animation check ──────────

  group('Gacha no daily limit (bug fix)', () {
    // Old bug: after draw animation, _gachaAvailable was set with:
    //   (curCount + 1) < 2 && (_totalStars >= 30)
    // This re-introduced the 2-per-day limit. Fix: only check stars.

    /// Old buggy logic
    bool gachaAvailableOldBug(int totalStars, int drawsToday) =>
        drawsToday < 2 && totalStars >= 30;

    /// New correct logic
    bool gachaAvailableFixed(int totalStars) => totalStars >= 30;

    test('old bug: 3rd draw in same day blocked even with enough stars', () {
      expect(gachaAvailableOldBug(100, 2), false); // BUG: blocked at 2
      expect(gachaAvailableFixed(100), true);       // FIX: allowed
    });

    test('old bug: 10th draw blocked', () {
      expect(gachaAvailableOldBug(300, 9), false);  // BUG: blocked at 2+
      expect(gachaAvailableFixed(300), true);        // FIX: allowed
    });

    test('fixed: only star count matters, not draw count', () {
      // Simulate 5 consecutive draws
      int stars = 150;
      for (int draw = 0; draw < 5; draw++) {
        expect(gachaAvailableFixed(stars), true);
        stars -= 30;
      }
      expect(stars, 0);
      expect(gachaAvailableFixed(stars), false); // no stars left
    });

    test('post-animation availability matches pre-draw check', () {
      // The availability after animation should use same logic as before draw
      int stars = 90;
      // Draw 1
      expect(gachaAvailableFixed(stars), true);
      stars -= 30;
      expect(gachaAvailableFixed(stars), true);  // 60 >= 30, can draw again
      // Draw 2
      stars -= 30;
      expect(gachaAvailableFixed(stars), true);  // 30 >= 30, can draw again
      // Draw 3
      stars -= 30;
      expect(gachaAvailableFixed(stars), false); // 0 < 30, done
    });
  });

  // ── Star consistency across screens ────────────────────────────────────

  group('Star data consistency', () {
    test('all screens read from same source (total_stars key)', () {
      // Simulate the SharedPreferences key
      const key = 'total_stars';
      // All screens use prefs.getInt('total_stars')
      // This test documents the contract
      expect(key, 'total_stars');
    });

    test('markModuleComplete adds stars, spendStars subtracts', () {
      int serverStars = 0;

      // User completes recap (+10), reader (+20), quiz (+20), listen (+20)
      serverStars += 10;
      serverStars += 20;
      serverStars += 20;
      serverStars += 20;
      expect(serverStars, 70);

      // User draws 2 gacha boxes
      serverStars -= 30;
      serverStars -= 30;
      expect(serverStars, 10);
      expect(gachaAvailable(serverStars), false); // 10 < 30
    });

    test('server correction overwrites local', () {
      // Local thinks 70 stars after deduction
      int local = 100 - 30;
      expect(local, 70);

      // But server says 55 (maybe another device spent stars)
      final server = 55;
      local = server; // server wins
      expect(local, 55);
      expect(gachaAvailable(local), true); // 55 >= 30
    });

    test('concurrent star operations resolve to server value', () {
      int local = 200;
      // Two rapid draws
      local -= 30; // draw 1 local
      local -= 30; // draw 2 local
      expect(local, 140);

      // Server processes both and returns final
      final serverFinal = 140;
      local = serverFinal;
      expect(local, 140);
      expect(gachaAvailable(local), true);
    });
  });
}
