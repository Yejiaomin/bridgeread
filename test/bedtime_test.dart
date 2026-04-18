import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:async';

// Minimal bedtime timer logic extracted for testing
class BedtimeController {
  final int durationSeconds;
  final VoidCallback onComplete;

  int remaining;
  Timer? _timer;
  bool completed = false;

  BedtimeController({
    this.durationSeconds = 20 * 60,
    required this.onComplete,
  }) : remaining = durationSeconds;

  void start() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      remaining--;
      if (remaining <= 0) {
        _timer?.cancel();
        completed = true;
        onComplete();
      }
    });
  }

  void dispose() {
    _timer?.cancel();
  }
}

void main() {
  group('Bedtime auto-close', () {
    test('timer starts at 20 minutes (1200 seconds)', () {
      bool closed = false;
      final ctrl = BedtimeController(
        durationSeconds: 20 * 60,
        onComplete: () => closed = true,
      );
      expect(ctrl.remaining, 1200);
      expect(ctrl.completed, false);
      ctrl.dispose();
    });

    test('timer counts down each second', () {
      fakeAsync((async) {
        bool closed = false;
        final ctrl = BedtimeController(
          durationSeconds: 10,
          onComplete: () => closed = true,
        );
        ctrl.start();

        async.elapse(const Duration(seconds: 3));
        expect(ctrl.remaining, 7);
        expect(closed, false);

        ctrl.dispose();
      });
    });

    test('auto-close triggers at exactly 0 seconds', () {
      fakeAsync((async) {
        bool closed = false;
        final ctrl = BedtimeController(
          durationSeconds: 5,
          onComplete: () => closed = true,
        );
        ctrl.start();

        async.elapse(const Duration(seconds: 4));
        expect(ctrl.remaining, 1);
        expect(closed, false);

        async.elapse(const Duration(seconds: 1));
        expect(ctrl.remaining, 0);
        expect(closed, true);
        expect(ctrl.completed, true);

        ctrl.dispose();
      });
    });

    test('auto-close triggers after full 20 minutes', () {
      fakeAsync((async) {
        bool closed = false;
        final ctrl = BedtimeController(
          durationSeconds: 20 * 60,
          onComplete: () => closed = true,
        );
        ctrl.start();

        // 19 minutes: not yet
        async.elapse(const Duration(minutes: 19));
        expect(closed, false);
        expect(ctrl.remaining, 60);

        // 20 minutes: should close
        async.elapse(const Duration(minutes: 1));
        expect(closed, true);
        expect(ctrl.remaining, 0);

        ctrl.dispose();
      });
    });

    test('dispose cancels timer without triggering close', () {
      fakeAsync((async) {
        bool closed = false;
        final ctrl = BedtimeController(
          durationSeconds: 5,
          onComplete: () => closed = true,
        );
        ctrl.start();

        async.elapse(const Duration(seconds: 2));
        ctrl.dispose();

        async.elapse(const Duration(seconds: 10));
        expect(closed, false);
        expect(ctrl.completed, false);
      });
    });

    test('onComplete callback is called exactly once', () {
      fakeAsync((async) {
        int callCount = 0;
        final ctrl = BedtimeController(
          durationSeconds: 3,
          onComplete: () => callCount++,
        );
        ctrl.start();

        async.elapse(const Duration(seconds: 5));
        expect(callCount, 1);

        ctrl.dispose();
      });
    });
  });

  group('Bedtime time check', () {
    test('20:30 China time triggers bedtime', () {
      // Simulate checking: hour=20, minute=30
      expect(_isBedtime(20, 30), true);
    });

    test('21:00 China time triggers bedtime', () {
      expect(_isBedtime(21, 0), true);
    });

    test('23:59 China time triggers bedtime', () {
      expect(_isBedtime(23, 59), true);
    });

    test('20:29 China time does NOT trigger bedtime', () {
      expect(_isBedtime(20, 29), false);
    });

    test('08:00 morning does NOT trigger bedtime', () {
      expect(_isBedtime(8, 0), false);
    });

    test('20:00 does NOT trigger bedtime', () {
      expect(_isBedtime(20, 0), false);
    });
  });
}

/// Mirror of HomeScreen._isBedtime() logic
bool _isBedtime(int hour, int minute) {
  return (hour == 20 && minute >= 30) || hour >= 21;
}

/// Fake async helper
void fakeAsync(void Function(FakeAsync async) callback) {
  final async = FakeAsync();
  async.run((_) => callback(async));
}

class FakeAsync {
  final List<_PendingTimer> _timers = [];
  Duration _elapsed = Duration.zero;

  void run(void Function(FakeAsync) callback) {
    Zone.current.fork(specification: ZoneSpecification(
      createPeriodicTimer: (self, parent, zone, period, callback) {
        final timer = _FakePeriodicTimer(period, callback);
        _timers.add(_PendingTimer(timer, period));
        return timer;
      },
    )).run(() => callback(this));
  }

  void elapse(Duration duration) {
    final end = _elapsed + duration;
    while (_elapsed < end) {
      _elapsed += const Duration(seconds: 1);
      for (final pt in List.of(_timers)) {
        if (!pt.timer.isActive) {
          _timers.remove(pt);
          continue;
        }
        if (_elapsed.inMilliseconds % pt.period.inMilliseconds == 0 ||
            _elapsed >= end) {
          pt.timer._tick();
        }
      }
    }
  }
}

class _PendingTimer {
  final _FakePeriodicTimer timer;
  final Duration period;
  _PendingTimer(this.timer, this.period);
}

class _FakePeriodicTimer implements Timer {
  final Duration period;
  final void Function(Timer) _callback;
  bool _active = true;
  int _count = 0;

  _FakePeriodicTimer(this.period, this._callback);

  void _tick() {
    if (_active) {
      _count++;
      _callback(this);
    }
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => _count;
}
