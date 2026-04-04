import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'utils/cdn_asset.dart';
import 'screens/home_screen.dart';
import 'screens/study_screen.dart';
import 'screens/reader_screen.dart';
import 'screens/phonics_screen.dart';
import 'screens/quiz_screen.dart';
import 'screens/recording_screen.dart';
import 'screens/listen_screen.dart';
import 'screens/card_gacha_screen.dart';
import 'screens/study_room_screen.dart';

final routeObserver = RouteObserver<ModalRoute<void>>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
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
      navigatorObservers: [routeObserver],
      initialRoute: '/',
      routes: {
        '/':          (context) => const _OrientationGate(child: HomeScreen()),
        '/home':      (context) => const _OrientationGate(child: HomeScreen()),
        '/study':     (context) => const _OrientationGate(child: StudyScreen()),
        '/calendar':  (context) => const _OrientationGate(child: CalendarScreen()),
        '/reader':    (context) => const _OrientationGate(child: ReaderScreen()),
        '/phonics':   (context) => const _OrientationGate(child: PhonicsScreen()),
        '/quiz':      (context) => const _OrientationGate(child: QuizScreen()),
        '/recording': (context) => const _OrientationGate(child: RecordingScreen()),
        '/gacha':     (context) => const _OrientationGate(child: CardGachaScreen()),
        '/listen':    (context) => _OrientationGate(child: ListenScreen()),
        '/studyroom': (context) => const _OrientationGate(child: StudyRoomScreen()),
      },
    );
  }
}

class _OrientationGate extends StatelessWidget {
  final Widget child;
  const _OrientationGate({required this.child});

  @override
  Widget build(BuildContext context) {
    return OrientationBuilder(
      builder: (context, orientation) {
        if (orientation == Orientation.portrait) {
          return Scaffold(
            backgroundColor: const Color(0xFFFFF8F0),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    cdnImage(
                      'assets/pet/eggy_transparent_bg.webp',
                      width: 120,
                      height: 120,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.screen_rotation,
                        size: 80,
                        color: Color(0xFFFF8C42),
                      ),
                    ),
                    const SizedBox(height: 32),
                    const Text(
                      'Hi~ 请把手机横过来',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFFF8C42),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '横屏体验更好哦！',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: Color(0xFF999999),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Please rotate your device to landscape',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFFBBBBBB),
                      ),
                    ),
                    const SizedBox(height: 40),
                    const Icon(
                      Icons.screen_rotation_rounded,
                      size: 48,
                      color: Color(0xFFFFD93D),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return child;
      },
    );
  }
}
