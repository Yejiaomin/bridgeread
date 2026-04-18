import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/week_service.dart' show initDebugOffset;
import 'services/analytics_service.dart';
import 'services/progress_service.dart';
import 'services/api_service.dart';
import 'utils/cdn_asset.dart';
import 'utils/responsive_utils.dart';
import 'screens/home_screen.dart';
import 'screens/study_screen.dart';
import 'screens/reader_screen.dart';
import 'screens/phonics_screen.dart';
import 'screens/quiz_screen.dart';
import 'screens/recording_screen.dart';
import 'screens/login_screen.dart';
import 'screens/assessment_screen.dart';
import 'screens/listen_screen.dart';
import 'screens/card_gacha_screen.dart';
import 'screens/study_room_screen.dart';
import 'screens/weekend_game_screen.dart';
import 'screens/ranking_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/night_candle_screen.dart';

final routeObserver = RouteObserver<ModalRoute<void>>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Read debug time offset from SharedPreferences (set by timeTravel JS)
  try {
    final prefs = await SharedPreferences.getInstance();
    final offset = prefs.getInt('debug_day_offset') ?? 0;
    initDebugOffset(offset);
  } catch (_) {}
  // Initialize Umeng analytics (Android only)
  if (!kIsWeb) {
    await AnalyticsService.init();
    AnalyticsService.logEvent('app_open');
  }
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
        '/':          (context) => const _AuthGate(),
        '/login':     (context) => const LoginScreen(),
        '/assessment': (context) => const AssessmentScreen(),
        '/home':      (context) => const _OrientationGate(child: HomeScreen()),
        '/study':     (context) => const _OrientationGate(child: StudyScreen()),
        '/calendar':  (context) => const _OrientationGate(child: CalendarScreen()),
        '/reader':    (context) => const _OrientationGate(child: ReaderScreen()),
        '/phonics':   (context) => const _OrientationGate(child: PhonicsScreen()),
        '/quiz':      (context) => const _OrientationGate(child: QuizScreen()),
        '/recording': (context) => const _OrientationGate(child: RecordingScreen()),
        '/gacha':     (context) => const _OrientationGate(child: CardGachaScreen()),
        '/listen':       (context) => _OrientationGate(child: ListenScreen()),
        '/night-candle': (context) => const _OrientationGate(child: NightCandleScreen()),
        '/bedtime':      (context) => _OrientationGate(child: ListenScreen(bedtimeMode: true)),
        '/weekend-game': (context) => const _OrientationGate(child: WeekendGameScreen()),
        '/studyroom':    (context) => const _OrientationGate(child: StudyRoomScreen()),
        '/ranking':      (context) => const _OrientationGate(child: RankingScreen()),
        '/profile':      (context) => const _OrientationGate(child: ProfileScreen()),
      },
    );
  }
}

/// Check auth token — if logged in go to home, otherwise show login
class _AuthGate extends StatefulWidget {
  const _AuthGate();
  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (!mounted) return;

    if (token != null && token.isNotEmpty) {
      // Try to validate JWT by fetching progress from server
      try {
        final data = await ApiService().getProgress()
            .timeout(const Duration(seconds: 8));
        if (!mounted) return;
        if (data != null && data['success'] == true) {
          // Token valid — sync server data to local cache
          await ProgressService.syncFromServer();
          Navigator.pushReplacementNamed(context, '/ranking');
        } else if (data != null && data['success'] != true) {
          // Server responded but token invalid — clear and go to login
          await prefs.remove('auth_token');
          Navigator.pushReplacementNamed(context, '/login');
        } else {
          // Network error (null response) — keep token, enter offline
          Navigator.pushReplacementNamed(context, '/home');
        }
      } catch (_) {
        // Network timeout/error — keep token, enter with cached data
        if (mounted) Navigator.pushReplacementNamed(context, '/home');
      }
    } else {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFFFF8F0),
      body: Center(child: CircularProgressIndicator(color: Color(0xFFFF8C42))),
    );
  }
}

class _OrientationGate extends StatelessWidget {
  final Widget child;
  const _OrientationGate({required this.child});

  @override
  Widget build(BuildContext context) {
    // Initialize responsive scaling for all child screens
    R.init(context);
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
