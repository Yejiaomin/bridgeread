import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'screens/study_screen.dart';
import 'screens/reader_screen.dart';
import 'screens/phonics_screen.dart';
import 'screens/quiz_screen.dart';
import 'screens/recording_screen.dart';
import 'screens/listen_screen.dart';

void main() {
  runApp(const BridgeReadApp());
}

class BridgeReadApp extends StatelessWidget {
  const BridgeReadApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BridgeRead',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF8C42),
          primary: const Color(0xFFFF8C42),
          secondary: const Color(0xFFFFD93D),
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFF8C42),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      initialRoute: '/',
      routes: {
        '/':          (context) => const HomeScreen(),
        '/home':      (context) => const HomeScreen(),
        '/study':     (context) => const StudyScreen(),
        '/calendar':  (context) => const CalendarScreen(),
        '/reader':    (context) => const ReaderScreen(),
        '/phonics':   (context) => const PhonicsScreen(),
        '/quiz':      (context) => const QuizScreen(),
        '/recording': (context) => const RecordingScreen(),
        '/listen':    (context) => const ListenScreen(),
      },
    );
  }
}
