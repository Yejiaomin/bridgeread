import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bridgeread/services/sync_queue.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SyncQueue.enqueue', () {
    test('persists item to prefs', () async {
      await SyncQueue.enqueue(
        date: '2026-04-19', module: 'listen', done: true, stars: 20,
      );
      expect(await SyncQueue.pending(), 1);
    });

    test('multiple enqueues accumulate', () async {
      await SyncQueue.enqueue(date: '2026-04-19', module: 'listen', done: true, stars: 20);
      await SyncQueue.enqueue(date: '2026-04-19', module: 'reader', done: true, stars: 20);
      await SyncQueue.enqueue(date: '2026-04-19', module: 'quiz', done: true, stars: 20);
      expect(await SyncQueue.pending(), 3);
    });

    test('items get unique ids', () async {
      await SyncQueue.enqueue(date: '2026-04-19', module: 'listen', done: true, stars: 20);
      await SyncQueue.enqueue(date: '2026-04-19', module: 'listen', done: true, stars: 20);
      final prefs = await SharedPreferences.getInstance();
      final list = jsonDecode(prefs.getString('sync_queue')!) as List;
      expect(list[0]['id'], isNot(equals(list[1]['id'])));
    });

    test('survives reading after raw write', () async {
      // Simulate persisted queue from a previous session
      SharedPreferences.setMockInitialValues({
        'sync_queue': jsonEncode([
          {'id': 'old-1', 'queuedAt': DateTime.now().toIso8601String(),
           'date': '2026-04-19', 'module': 'recap', 'done': true, 'stars': 10},
        ]),
      });
      expect(await SyncQueue.pending(), 1);
    });
  });

  group('SyncQueue.flush', () {
    test('returns zero counts on empty queue', () async {
      final r = await SyncQueue.flush();
      expect(r.sent, 0);
      expect(r.failed, 0);
      expect(r.dropped, 0);
    });

    test('drops items older than 30 days', () async {
      final old = DateTime.now().subtract(const Duration(days: 31)).toIso8601String();
      SharedPreferences.setMockInitialValues({
        'sync_queue': jsonEncode([
          {'id': 'old-1', 'queuedAt': old,
           'date': '2026-03-15', 'module': 'listen', 'done': true, 'stars': 20},
        ]),
      });
      final r = await SyncQueue.flush();
      expect(r.dropped, 1);
      expect(await SyncQueue.pending(), 0);
    });

    test('drops items with invalid queuedAt', () async {
      SharedPreferences.setMockInitialValues({
        'sync_queue': jsonEncode([
          {'id': 'bad-1', 'queuedAt': 'not-a-date',
           'date': '2026-04-19', 'module': 'listen', 'done': true, 'stars': 20},
        ]),
      });
      final r = await SyncQueue.flush();
      expect(r.dropped, 1);
    });

    // Note: testing actual API success/failure requires mocking ApiService,
    // which the existing test setup doesn't do. The integration behavior
    // (sent vs failed) is exercised manually via app testing.
  });

  group('SyncQueue parsing robustness', () {
    test('returns empty for missing key', () async {
      expect(await SyncQueue.pending(), 0);
    });

    test('returns empty for malformed JSON', () async {
      SharedPreferences.setMockInitialValues({'sync_queue': 'not valid json'});
      expect(await SyncQueue.pending(), 0);
    });

    test('returns empty for non-list JSON', () async {
      SharedPreferences.setMockInitialValues({'sync_queue': '{"oops": true}'});
      expect(await SyncQueue.pending(), 0);
    });
  });
}
