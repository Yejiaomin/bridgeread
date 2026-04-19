import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Posts Flutter runtime errors to /api/report so we can debug
/// production issues users can't surface themselves.
class ErrorReporter {
  static final _recent = <String, DateTime>{};
  static const _dedupWindow = Duration(seconds: 60);

  static void install() {
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      _send(details.exceptionAsString(), details.stack, label: 'flutter_error');
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      _send(error.toString(), stack, label: 'platform_error');
      return true;
    };
  }

  static Future<void> _send(String message, StackTrace? stack, {required String label}) async {
    final firstFrames = (stack?.toString() ?? '').split('\n').take(3).join('|');
    final key = '$label::$message::$firstFrames';
    final now = DateTime.now();
    final last = _recent[key];
    if (last != null && now.difference(last) < _dedupWindow) return;
    _recent[key] = now;

    try {
      await http.post(
        Uri.parse('/api/report'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'type': label,
          'time': now.toIso8601String(),
          'url': Uri.base.toString(),
          'logs': [message, if (stack != null) stack.toString()],
        }),
      ).timeout(const Duration(seconds: 5));
    } catch (_) {/* swallow — we're already in an error path */}
  }
}
