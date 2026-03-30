import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/lesson.dart';

class LessonService {
  static final LessonService _instance = LessonService._internal();
  factory LessonService() => _instance;
  LessonService._internal();

  Lesson? _currentLesson;
  String _currentLessonId = 'biscuit_book1_day1';

  /// The currently active lesson (loaded via setCurrentLesson or loadLesson).
  Lesson? get currentLesson => _currentLesson;
  String get currentLessonId => _currentLessonId;

  /// Load a lesson from assets/lessons/{lessonId}.json
  Future<Lesson> loadLesson(String lessonId) async {
    if (_currentLesson != null && _currentLessonId == lessonId) {
      return _currentLesson!;
    }
    final jsonString =
        await rootBundle.loadString('assets/lessons/$lessonId.json');
    final Map<String, dynamic> jsonMap =
        json.decode(jsonString) as Map<String, dynamic>;
    final lesson = Lesson.fromJson(jsonMap);
    _currentLesson = lesson;
    _currentLessonId = lessonId;
    return lesson;
  }

  /// Set the current lesson by ID and persist to SharedPreferences.
  Future<Lesson> setCurrentLesson(String lessonId) async {
    final lesson = await loadLesson(lessonId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('current_lesson_id', lessonId);
    return lesson;
  }

  /// Restore the last active lesson from SharedPreferences.
  Future<String> restoreCurrentLessonId() async {
    final prefs = await SharedPreferences.getInstance();
    _currentLessonId = prefs.getString('current_lesson_id') ?? 'biscuit_book1_day1';
    return _currentLessonId;
  }
}
