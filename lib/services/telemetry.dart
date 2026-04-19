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

  /// Log an event. [type] controls the server-side filename prefix
  /// (e.g. 'event' for normal telemetry, 'user_report' for user-submitted
  /// feedback). Defaults to 'event'.
  static void log(String event, [Map<String, dynamic>? data, String type = 'event']) {
    final time = DateTime.now().toIso8601String();
    debugPrint('[Telemetry] $event ${data ?? ''}');
    _post(type: type, event: event, data: data, time: time);
  }

  static Future<void> _post({required String type, required String event, Map<String, dynamic>? data, required String time}) async {
    try {
      await http.post(
        Uri.parse('/api/report'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'type': type,
          'sessionId': sessionId,
          if (_userId != null) 'userId': _userId,
          'time': time,
          'url': Uri.base.toString(),
          'logs': [event, if (data != null) jsonEncode(data)],
        }),
      ).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }
}
