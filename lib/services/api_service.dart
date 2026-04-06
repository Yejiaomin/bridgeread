import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// API service for backend communication.
/// All progress sync and auth calls go through here.
class ApiService {
  static final ApiService _instance = ApiService._();
  factory ApiService() => _instance;
  ApiService._();

  // TODO: Change to production URL when deployed
  static const _baseUrl = 'http://localhost:3000/api';

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  Future<Map<String, String>> _authHeaders() async {
    final token = await _getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Sync a single module completion to server.
  /// Called by ProgressService after marking a module complete.
  Future<Map<String, dynamic>?> syncProgress({
    required String date,
    required String module,
    required bool done,
    int stars = 0,
    String? lessonId,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/progress'),
        headers: await _authHeaders(),
        body: jsonEncode({
          'date': date,
          'module': module,
          'done': done,
          'stars': stars,
          'lessonId': lessonId,
        }),
      ).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) return jsonDecode(res.body);
    } catch (_) {
      // Offline — silently fail, local progress still saved
    }
    return null;
  }

  /// Batch sync multiple modules at once.
  /// Used when coming back online after offline usage.
  Future<Map<String, dynamic>?> syncBatch(List<Map<String, dynamic>> items) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/progress/batch'),
        headers: await _authHeaders(),
        body: jsonEncode({'items': items}),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return jsonDecode(res.body);
    } catch (_) {}
    return null;
  }

  /// Get all progress from server (used on login / app start).
  Future<Map<String, dynamic>?> getProgress() async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/progress'),
        headers: await _authHeaders(),
      ).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) return jsonDecode(res.body);
    } catch (_) {}
    return null;
  }

  /// Set book start date and series index.
  Future<bool> setupProgress({String? bookStartDate, int? startSeriesIndex}) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/progress/setup'),
        headers: await _authHeaders(),
        body: jsonEncode({
          if (bookStartDate != null) 'bookStartDate': bookStartDate,
          if (startSeriesIndex != null) 'startSeriesIndex': startSeriesIndex,
        }),
      ).timeout(const Duration(seconds: 5));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Upload recording file.
  Future<bool> uploadRecording({
    required String filePath,
    required String date,
    required String lessonId,
    String? sentence,
  }) async {
    try {
      final token = await _getToken();
      final req = http.MultipartRequest('POST', Uri.parse('$_baseUrl/recordings/upload'));
      req.headers['Authorization'] = 'Bearer $token';
      req.fields['date'] = date;
      req.fields['lessonId'] = lessonId;
      if (sentence != null) req.fields['sentence'] = sentence;
      req.files.add(await http.MultipartFile.fromPath('audio', filePath));
      final res = await req.send().timeout(const Duration(seconds: 15));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
