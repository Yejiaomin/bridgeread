import 'package:flutter/foundation.dart';
import 'package:fl_umeng/fl_umeng.dart';

class AnalyticsService {
  static bool _initialized = false;
  static final FlUMeng _umeng = FlUMeng();

  static Future<void> init() async {
    if (_initialized) return;
    try {
      final result = await _umeng.init(
        androidAppKey: '69daee776f259537c7966a8f',
        iosAppKey: '',
        channel: 'default',
      );
      if (result) {
        await _umeng.setPageCollectionModeManual();
        _initialized = true;
        debugPrint('[Analytics] Umeng initialized');
      } else {
        debugPrint('[Analytics] Umeng init returned false');
      }
    } catch (e) {
      debugPrint('[Analytics] Umeng init failed: $e');
    }
  }

  /// Log a custom event with optional properties
  static void logEvent(String eventId, [Map<String, String>? properties]) {
    if (!_initialized) return;
    try {
      _umeng.onEvent(eventId, properties ?? {});
    } catch (e) {
      debugPrint('[Analytics] logEvent error: $e');
    }
  }

  /// Track page start
  static void pageStart(String pageName) {
    if (!_initialized) return;
    try {
      _umeng.onPageStart(pageName);
    } catch (e) {
      debugPrint('[Analytics] pageStart error: $e');
    }
  }

  /// Track page end
  static void pageEnd(String pageName) {
    if (!_initialized) return;
    try {
      _umeng.onPageEnd(pageName);
    } catch (e) {
      debugPrint('[Analytics] pageEnd error: $e');
    }
  }
}
