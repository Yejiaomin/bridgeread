import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Lightweight session-scoped event logger. Posts to /api/report so we can
/// correlate user actions when debugging issues like white-screen reports.
///
/// Usage:
///   Telemetry.log('study_enter');
///   Telemetry.log('listen_complete', {'seconds': 1234});
///
/// Errors from ErrorReporter automatically pick up the session ID too.
class Telemetry {
  static late final String sessionId;
  static int? _userId;
  static bool _installed = false;

  static void install() {
    if (_installed) return;
    _installed = true;
    final r = Random.secure();
    sessionId = List.generate(8, (_) => r.nextInt(36).toRadixString(36)).join();
  }

  static void setUser(int? userId) => _userId = userId;

  static void log(String event, [Map<String, dynamic>? data]) {
    final payload = {
      'sessionId': sessionId,
      if (_userId != null) 'userId': _userId,
      'event': event,
      'time': DateTime.now().toIso8601String(),
      'url': Uri.base.toString(),
      if (data != null) 'data': data,
    };
    debugPrint('[Telemetry] $event ${data ?? ''}');
    _post(payload);
  }

  static Future<void> _post(Map<String, dynamic> payload) async {
    try {
      await http.post(
        Uri.parse('/api/report'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'type': 'event',
          'sessionId': sessionId,
          if (_userId != null) 'userId': _userId,
          'time': payload['time'],
          'url': payload['url'],
          'logs': [payload['event'], if (payload['data'] != null) jsonEncode(payload['data'])],
        }),
      ).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }
}
