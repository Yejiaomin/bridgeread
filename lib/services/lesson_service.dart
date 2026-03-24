import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/lesson.dart';

class LessonService {
  /// Load a lesson from assets/lessons/{lessonId}.json
  Future<Lesson> loadLesson(String lessonId) async {
    final jsonString =
        await rootBundle.loadString('assets/lessons/$lessonId.json');
    final Map<String, dynamic> jsonMap =
        json.decode(jsonString) as Map<String, dynamic>;
    return Lesson.fromJson(jsonMap);
  }
}
