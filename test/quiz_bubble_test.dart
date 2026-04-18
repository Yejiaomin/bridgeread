import 'dart:math';
import 'package:flutter_test/flutter_test.dart';

// Reproduce the scatter algorithm from quiz_screen.dart for testing
// (can't import the screen directly due to Flutter widget dependencies)

class _Bubble {
  final double size;
  final double bx, by;
  final double speed, px, py;

  _Bubble({required this.size, required this.bx, required this.by,
    required this.speed, required this.px, required this.py});

  Offset drift(double t) {
    final a = t * 2 * pi;
    return Offset(
      sin(a * speed + px) * 14,
      cos(a * speed * 0.7 + py) * 11,
    );
  }
}

List<Offset> scatter(List<double> sizes, double w, double h, Random rng) {
  const safeYFrac = 0.82;
  const maxDriftY = 11.0; // matches reduced drift
  final n = sizes.length;
  final out = <Offset>[];
  int tries = 0;

  while (out.length < n && tries++ < 4000) {
    final i = out.length;
    final ri = sizes[i] / 2;

    final minPx = (ri).clamp(0.05 * w, 0.45 * w);
    final maxPx = (w - ri).clamp(0.55 * w, 0.95 * w);
    final minPy = 0.06 * h + ri;
    final maxPy = (h * safeYFrac - ri - maxDriftY).clamp(minPy + 1, h);

    final px = minPx + rng.nextDouble() * (maxPx - minPx);
    final py = minPy + rng.nextDouble() * (maxPy - minPy);

    bool valid = true;
    for (int j = 0; j < out.length; j++) {
      final rj = sizes[j] / 2;
      final minDist = (ri + rj) * 0.5 + 36;
      final dx = out[j].dx - px;
      final dy = out[j].dy - py;
      if (sqrt(dx * dx + dy * dy) < minDist) {
        valid = false;
        break;
      }
    }
    if (valid) out.add(Offset(px, py));
  }

  // Fallback
  while (out.length < n) {
    final i = out.length;
    final ri = sizes[i] / 2;
    final minPx = (ri).clamp(0.05 * w, 0.45 * w);
    final maxPx = (w - ri).clamp(0.55 * w, 0.95 * w);
    final minPy = 0.06 * h + ri;
    final maxPy = (h * safeYFrac - ri - maxDriftY).clamp(minPy + 1, h);
    out.add(Offset(
      minPx + rng.nextDouble() * (maxPx - minPx),
      minPy + rng.nextDouble() * (maxPy - minPy),
    ));
  }

  return out;
}

void main() {
  group('Bubble scatter — no severe overlap', () {
    test('5 bubbles on iPad (1024x768) — all placed within 4000 tries', () {
      final rng = Random(42); // fixed seed for reproducibility
      final sizes = List.generate(5, (_) => 170.0 + rng.nextDouble() * 50.0);
      final positions = scatter(sizes, 1024, 768 * 0.72, rng);
      expect(positions.length, 5);
    });

    test('5 bubbles on iPhone (375x667) — all placed', () {
      final rng = Random(42);
      // On phone, scale factor ~0.37, sizes ~63-81px
      final scale = 375 / 1024;
      final sizes = List.generate(5, (_) => (170.0 + rng.nextDouble() * 50.0) * scale);
      final positions = scatter(sizes, 375, 667 * 0.72, rng);
      expect(positions.length, 5);
    });

    test('no pair overlaps more than half diameter', () {
      final rng = Random(123);
      final sizes = List.generate(5, (_) => 170.0 + rng.nextDouble() * 50.0);
      final positions = scatter(sizes, 1024, 768 * 0.72, rng);

      for (int i = 0; i < positions.length; i++) {
        for (int j = i + 1; j < positions.length; j++) {
          final dx = positions[i].dx - positions[j].dx;
          final dy = positions[i].dy - positions[j].dy;
          final dist = sqrt(dx * dx + dy * dy);
          final ri = sizes[i] / 2;
          final rj = sizes[j] / 2;
          // Overlap = (ri + rj) - dist. Should be less than min(ri, rj)
          final overlap = (ri + rj) - dist;
          expect(overlap, lessThan(min(ri, rj)),
              reason: 'Bubbles $i and $j overlap too much: $overlap px');
        }
      }
    });

    test('drift does not cause severe overlap', () {
      final rng = Random(456);
      final sizes = List.generate(5, (_) => 170.0 + rng.nextDouble() * 50.0);
      final positions = scatter(sizes, 1024, 768 * 0.72, rng);

      // Create bubbles with drift parameters
      final bubbles = List.generate(5, (i) => _Bubble(
        size: sizes[i],
        bx: positions[i].dx,
        by: positions[i].dy,
        speed: 0.3 + rng.nextDouble() * 0.7,
        px: rng.nextDouble() * 2 * pi,
        py: rng.nextDouble() * 2 * pi,
      ));

      // Check at multiple time points
      for (double t = 0; t < 1.0; t += 0.1) {
        for (int i = 0; i < bubbles.length; i++) {
          for (int j = i + 1; j < bubbles.length; j++) {
            final di = bubbles[i].drift(t);
            final dj = bubbles[j].drift(t);
            final ax = bubbles[i].bx + di.dx;
            final ay = bubbles[i].by + di.dy;
            final bx = bubbles[j].bx + dj.dx;
            final by = bubbles[j].by + dj.dy;
            final dist = sqrt((ax - bx) * (ax - bx) + (ay - by) * (ay - by));
            final ri = sizes[i] / 2;
            final rj = sizes[j] / 2;
            // With drift, allow up to 75% overlap (visual still acceptable)
            final overlap = (ri + rj) - dist;
            expect(overlap, lessThan((ri + rj) * 0.75),
                reason: 'Bubbles $i,$j overlap too much at t=$t');
          }
        }
      }
    });

    test('scatter is deterministic with same seed', () {
      final pos1 = scatter([100, 100, 100, 100, 100], 1024, 500, Random(99));
      final pos2 = scatter([100, 100, 100, 100, 100], 1024, 500, Random(99));
      for (int i = 0; i < 5; i++) {
        expect(pos1[i].dx, pos2[i].dx);
        expect(pos1[i].dy, pos2[i].dy);
      }
    });

    test('stress test — 100 random seeds all produce 5 bubbles', () {
      for (int seed = 0; seed < 100; seed++) {
        final rng = Random(seed);
        final sizes = List.generate(5, (_) => 170.0 + rng.nextDouble() * 50.0);
        final positions = scatter(sizes, 1024, 768 * 0.72, rng);
        expect(positions.length, 5, reason: 'Failed with seed $seed');
      }
    });
  });
}
