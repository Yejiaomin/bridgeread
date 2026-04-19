import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// API service for backend communication.
/// All progress sync and auth calls go through here.
class ApiService {
  static final ApiService _instance = ApiService._();
  factory ApiService() => _instance;
  ApiService._();

  static const _baseUrl = '/api';

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

  /// Register a new user. Returns token + user data on success.
  Future<Map<String, dynamic>?> register({
    required String phone,
    required String password,
    required String childName,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone': phone,
          'password': password,
          'childName': childName,
        }),
      ).timeout(const Duration(seconds: 10));
      debugPrint('[API] register ${res.statusCode}: ${res.body}');
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['token'] != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_token', data['token']);
        await prefs.setString('child_name', data['user']['childName'] ?? childName);
        return data;
      }
      return data; // contains error message
    } catch (e) {
      debugPrint('[API] register error: $e');
      return {'error': '网络连接失败，请检查网络'};
    }
  }

  /// Login with phone + password. Returns token + user data on success.
  Future<Map<String, dynamic>?> login({
    required String phone,
    required String password,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone, 'password': password}),
      ).timeout(const Duration(seconds: 10));
      debugPrint('[API] login ${res.statusCode}: ${res.body}');
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['token'] != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_token', data['token']);
        await prefs.setString('child_name', data['user']['childName'] ?? '');
        return data;
      }
      return data; // contains error message
    } catch (e) {
      debugPrint('[API] login error: $e');
      return {'error': '网络连接失败，请检查网络'};
    }
  }

  /// Send SMS verification code.
  Future<Map<String, dynamic>?> sendCode(String phone) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/auth/send-code'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone}),
      ).timeout(const Duration(seconds: 10));
      return jsonDecode(res.body);
    } catch (e) {
      return {'error': '网络连接失败，请检查网络'};
    }
  }

  /// Sync a single module completion to server.
  /// Called by ProgressService after marking a module complete.
  /// Pass [done] = null for telemetry-only updates (e.g. periodic listen-time
  /// saves) — server will not touch daily_progress in that case.
  Future<Map<String, dynamic>?> syncProgress({
    required String date,
    required String module,
    bool? done,
    int stars = 0,
    String? lessonId,
    int? listenSeconds,
  }) async {
    try {
      final body = <String, dynamic>{
        'date': date,
        'module': module,
        'stars': stars,
        'lessonId': lessonId,
      };
      if (done != null) body['done'] = done;
      if (listenSeconds != null) body['listenSeconds'] = listenSeconds;
      final res = await http.post(
        Uri.parse('$_baseUrl/progress'),
        headers: await _authHeaders(),
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 5));
      debugPrint('[API] syncProgress ${res.statusCode}: ${res.body}');
      if (res.statusCode == 200) return jsonDecode(res.body);
    } catch (e) {
      debugPrint('[API] syncProgress error: $e');
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
  Future<bool> setupProgress({String? bookStartDate, int? startSeriesIndex, String? appStartDate}) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/progress/setup'),
        headers: await _authHeaders(),
        body: jsonEncode({
          if (bookStartDate != null) 'bookStartDate': bookStartDate,
          if (startSeriesIndex != null) 'startSeriesIndex': startSeriesIndex,
          if (appStartDate != null) 'appStartDate': appStartDate,
        }),
      ).timeout(const Duration(seconds: 5));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Spend stars (gacha). Returns (stars: newTotal) on success,
  /// (error: code) on failure. Codes: 'insufficient' | 'unauthorized' | 'network'.
  Future<({int? stars, String? error})> spendStars(int amount) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/progress/spend-stars'),
        headers: await _authHeaders(),
        body: jsonEncode({'amount': amount}),
      ).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return (stars: data['totalStars'] as int?, error: null);
      }
      if (res.statusCode == 401) return (stars: null, error: 'unauthorized');
      if (res.statusCode == 400) {
        final body = res.body;
        if (body.contains('not enough stars')) return (stars: null, error: 'insufficient');
      }
    } catch (_) {}
    return (stars: null, error: 'network');
  }

  /// Get ranking/leaderboard data.
  Future<Map<String, dynamic>?> getRanking({String period = 'week'}) async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/ranking?period=$period'),
        headers: await _authHeaders(),
      ).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) return jsonDecode(res.body);
    } catch (_) {}
    return null;
  }

  /// Get user profile from server.
  Future<Map<String, dynamic>?> getProfile() async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/profile'),
        headers: await _authHeaders(),
      ).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) return jsonDecode(res.body);
    } catch (_) {}
    return null;
  }

  /// Update user profile on server.
  Future<bool> updateProfile(Map<String, dynamic> data) async {
    try {
      final res = await http.put(
        Uri.parse('$_baseUrl/profile'),
        headers: await _authHeaders(),
        body: jsonEncode(data),
      ).timeout(const Duration(seconds: 5));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Get study room data from server.
  Future<Map<String, dynamic>?> getStudyRoom() async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/studyroom'),
        headers: await _authHeaders(),
      ).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) return jsonDecode(res.body);
    } catch (_) {}
    return null;
  }

  /// Update study room data on server.
  Future<bool> updateStudyRoom(Map<String, dynamic> data) async {
    try {
      final res = await http.put(
        Uri.parse('$_baseUrl/studyroom'),
        headers: await _authHeaders(),
        body: jsonEncode(data),
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
