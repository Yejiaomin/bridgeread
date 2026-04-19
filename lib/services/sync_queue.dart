import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'telemetry.dart';

/// Queue of pending progress syncs that survive process restarts.
///
/// Why: previously [ProgressService.markModuleComplete] did fire-and-forget
/// `_api.syncProgress(...)`. If the network blipped at the wrong moment, the
/// server never learned the module was completed — local cache + server drifted
/// apart. With the queue, every completion is persisted to prefs first; flush
/// retries until the server confirms.
class SyncQueue {
  static const _kQueue = 'sync_queue';
  static const _maxAge = Duration(days: 30);
  static bool _flushing = false;
  static final _api = ApiService();

  /// Persist a completion to the queue and return immediately.
  static Future<void> enqueue({
    required String date,
    required String module,
    required bool done,
    required int stars,
    String? lessonId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final list = _read(prefs);
    list.add({
      'id': '${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(99)}',
      'queuedAt': DateTime.now().toIso8601String(),
      'date': date,
      'module': module,
      'done': done,
      'stars': stars,
      'lessonId': lessonId,
    });
    await prefs.setString(_kQueue, jsonEncode(list));
  }

  /// Try to flush all pending items. Successes removed; failures stay for
  /// next attempt. Items older than [_maxAge] are dropped.
  ///
  /// Concurrent calls are deduped — only one flush runs at a time.
  static Future<({int sent, int failed, int dropped})> flush() async {
    if (_flushing) return (sent: 0, failed: 0, dropped: 0);
    _flushing = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      var list = _read(prefs);
      if (list.isEmpty) return (sent: 0, failed: 0, dropped: 0);

      final cutoff = DateTime.now().subtract(_maxAge);
      final remaining = <Map<String, dynamic>>[];
      int sent = 0, failed = 0, dropped = 0;
      int? latestServerStars, latestServerOwed, latestServerStreak;

      for (final item in list) {
        final queuedAt = DateTime.tryParse(item['queuedAt'] as String? ?? '');
        if (queuedAt == null || queuedAt.isBefore(cutoff)) {
          dropped++;
          Telemetry.log('sync_queue_dropped_stale', {'item': item});
          continue;
        }
        final res = await _api.syncProgress(
          date: item['date'] as String,
          module: item['module'] as String,
          done: item['done'] as bool,
          stars: item['stars'] as int? ?? 0,
          lessonId: item['lessonId'] as String?,
        );
        if (res != null) {
          sent++;
          if (res['totalStars'] is int) latestServerStars = res['totalStars'];
          if (res['totalOwed'] is int) latestServerOwed = res['totalOwed'];
          if (res['streak'] is int) latestServerStreak = res['streak'];
        } else {
          failed++;
          remaining.add(item);
        }
      }

      // Persist whatever's left
      await prefs.setString(_kQueue, jsonEncode(remaining));

      // Reconcile server-authoritative values:
      // - total_stars: only override if server >= local (defends against
      //   in-flight completion not yet sync'd from being clobbered)
      // - total_owed / streak_days: server is single source of truth, take
      //   directly (no possibility of regression — they don't grow locally)
      if (latestServerStars != null) {
        final localStars = prefs.getInt('total_stars') ?? 0;
        if (latestServerStars >= localStars) {
          await prefs.setInt('total_stars', latestServerStars);
        }
      }
      if (latestServerOwed != null) {
        await prefs.setInt('total_owed', latestServerOwed);
      }
      if (latestServerStreak != null) {
        await prefs.setInt('streak_days', latestServerStreak);
      }

      if (sent > 0 || failed > 0 || dropped > 0) {
        debugPrint('[SyncQueue] flushed: sent=$sent failed=$failed dropped=$dropped');
      }
      return (sent: sent, failed: failed, dropped: dropped);
    } finally {
      _flushing = false;
    }
  }

  /// How many items are currently waiting.
  static Future<int> pending() async {
    final prefs = await SharedPreferences.getInstance();
    return _read(prefs).length;
  }

  static List<Map<String, dynamic>> _read(SharedPreferences prefs) {
    final raw = prefs.getString(_kQueue);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }
}
