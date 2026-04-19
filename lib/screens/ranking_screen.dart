import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/cdn_asset.dart';
import '../utils/responsive_utils.dart';
import '../services/progress_service.dart';

const _kAvatarEmojis = [
  '🐱', '🐶', '🐰', '🐼', '🦊', '🐨', '🦁', '🐸', '🐧', '🦄', '🐮', '🐷',
  '🐻', '🐯', '🐹', '🐰', '🦋', '🐢',
  '🌻', '🍓', '🌈', '⭐', '🎀', '🧸', '🎨', '🎵', '🚀', '🌸', '🍭', '🦖', '🐊',
  '🐝', '🦀', '🐙', '🦩', '🐳', '🦜', '🍀',
];
const _kAvatarColors = [
  Color(0xFFF48FB1), Color(0xFF90CAF9), Color(0xFFCE93D8), Color(0xFFA5D6A7),
  Color(0xFFFFCC80), Color(0xFF80CBC4), Color(0xFFFFE082), Color(0xFFDCE775),
  Color(0xFF9FA8DA), Color(0xFFF8BBD0), Color(0xFFBCAAA4), Color(0xFFEF9A9A),
  Color(0xFFD7CCC8), Color(0xFFFFE0B2), Color(0xFFFFF9C4), Color(0xFFE1BEE7),
  Color(0xFFB3E5FC), Color(0xFFC8E6C9),
  Color(0xFFFFF176), Color(0xFFEF9A9A), Color(0xFFB2EBF2), Color(0xFFFFE082),
  Color(0xFFF8BBD0), Color(0xFFD7CCC8), Color(0xFFE6EE9C), Color(0xFFCE93D8),
  Color(0xFF90CAF9), Color(0xFFF48FB1), Color(0xFFFFAB91), Color(0xFFA5D6A7), Color(0xFF80CBC4),
  Color(0xFFFFE082), Color(0xFFEF9A9A), Color(0xFFCE93D8), Color(0xFFF48FB1),
  Color(0xFF90CAF9), Color(0xFFA5D6A7), Color(0xFFC8E6C9),
];

class RankingScreen extends StatefulWidget {
  const RankingScreen({super.key});
  @override
  State<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends State<RankingScreen>
    with TickerProviderStateMixin {
  String _period = 'week';
  bool _loading = true;
  bool _navigating = false;
  int _countdown = 15;
  Timer? _countdownTimer;
  Map<String, List<Map<String, dynamic>>> _data = {};
  bool _listenDone = false;
  final Map<String, int> _eggCache = {};

  int _myAvatarIndex = -1;
  Uint8List? _myCustomAvatar;

  late final AnimationController _starGlowCtrl;
  late final Animation<double> _starGlow;

  // Rank-up climb animation
  bool _showRankUp = false;
  bool _rankUpCelebrate = false;
  List<Map<String, dynamic>> _rankUpEntries = [];
  Map<int, int> _rankUpPositions = {}; // entryIndex -> visual slot
  int _rankUpUserIdx = 0;
  int _rankUpNewRank = 0;
  Timer? _rankUpStepTimer;
  AnimationController? _rankUpFadeCtrl;


  // Persistent star orbit on user's row (top 3)
  AnimationController? _persistGlowCtrl;

  static const _circleInfo = {
    1: {'cx': 0.504, 'cy': 0.415, 'diam': 0.46},
    2: {'cx': 0.488, 'cy': 0.357, 'diam': 0.52},
    3: {'cx': 0.50, 'cy': 0.395, 'diam': 0.55},
  };

  final _tabs = [
    {'label': '今日', 'value': 'day'},
    {'label': '本周', 'value': 'week'},
    {'label': '本月', 'value': 'month'},
  ];

  @override
  void initState() {
    super.initState();
    _starGlowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _starGlow = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _starGlowCtrl, curve: Curves.easeInOut),
    );
    _loadMyAvatar();
    _fetchAll();
    _startCountdown();
  }

  Future<void> _loadMyAvatar() async {
    final prefs = await SharedPreferences.getInstance();
    final idx = prefs.getInt('profile_avatar') ?? -1;
    Uint8List? custom;
    if (idx == -1) {
      final b64 = prefs.getString('profile_custom_avatar');
      if (b64 != null && b64.isNotEmpty) {
        custom = base64Decode(b64);
      }
    }
    if (mounted) {
      setState(() {
        _myAvatarIndex = idx;
        _myCustomAvatar = custom;
      });
    }
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _navigating) {
        t.cancel();
        return;
      }
      setState(() => _countdown--);
      if (_countdown <= 0) {
        t.cancel();
        _goHome();
      }
    });
  }

  void _goHome() {
    if (_navigating) return;
    _navigating = true;
    _countdownTimer?.cancel();
    _starGlowCtrl.stop();
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/home');
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _starGlowCtrl.dispose();
    _rankUpStepTimer?.cancel();
    _rankUpFadeCtrl?.dispose();
    _persistGlowCtrl?.dispose();
    super.dispose();
  }

  String _maskName(String name) {
    if (name.isEmpty) return '*';
    return '${name.characters.first}${'*' * (name.characters.length - 1).clamp(1, 5)}';
  }

  static const _fakeNames = ['小明', '甜甜', '鹏鹏', '帅帅', '小花', '大宝', '乐乐', '豆豆', '果果', '欢欢'];

  Future<void> _fetchAll() async {
    setState(() => _loading = true);

    final prefs = await SharedPreferences.getInstance();
    final myStars = prefs.getInt('total_stars') ?? 0;
    final childName = prefs.getString('child_name') ?? '我';
    _listenDone = await ProgressService.isDoneToday('listen');

    final rng = Random();

    List<Map<String, dynamic>> _generate(int starVariation) {
      final entries = <Map<String, dynamic>>[];
      if (_listenDone) {
        // After study: fake stars lower than me, so I'm #1
        for (final name in _fakeNames) {
          final fakeStars = (myStars - 2 - rng.nextInt(15) + starVariation).clamp(1, 99999);
          entries.add({'name': name, 'stars': fakeStars, 'isMe': false});
        }
        entries.add({'name': childName, 'stars': myStars, 'isMe': true});
        entries.sort((a, b) => (b['stars'] as int).compareTo(a['stars'] as int));
      } else {
        // Before study: fake stars much higher, me at 8th+ place
        for (final name in _fakeNames) {
          final fakeStars = (myStars + 10 + rng.nextInt(30) + starVariation).clamp(1, 99999);
          entries.add({'name': name, 'stars': fakeStars, 'isMe': false});
        }
        entries.add({'name': childName, 'stars': myStars, 'isMe': true});
        entries.sort((a, b) => (b['stars'] as int).compareTo(a['stars'] as int));
      }
      return entries;
    }

    final generated = {
      'day': _generate(0),
      'week': _generate(2),
      'month': _generate(5),
    };

    // Check rank improvement for default period
    final currentEntries = generated[_period] ?? [];
    final myIdx = currentEntries.indexWhere((e) => e['isMe'] == true);
    final currentRank = myIdx >= 0 ? myIdx + 1 : 99;
    final prevRank = prefs.getInt('last_rank_$_period') ?? 0;

    // Save current rank
    await prefs.setInt('last_rank_$_period', currentRank);

    if (mounted) {
      setState(() {
        _data = generated;
        _loading = false;
      });

      // Start star orbit if user is in top 3
      if (currentRank <= 3) {
        _startPersistentGlow();
      }

      // Trigger rank-up animation if improved (and had a previous rank)
      if (prevRank > 0 && currentRank < prevRank) {
        _triggerRankUpAnimation(prevRank, currentRank);
      }
    }
  }

  List<Map<String, dynamic>> get _entries => _data[_period] ?? [];

  bool get _todayDone {
    final dayEntries = _data['day'] ?? [];
    final me = dayEntries.where((e) => e['isMe'] == true).firstOrNull;
    return me != null && (me['stars'] as int? ?? 0) > 0;
  }

  Widget _buildAvatar(Map<String, dynamic> entry, double size) {
    final isMe = entry['isMe'] == true;
    final name = entry['name'] as String? ?? '';

    if (isMe) {
      if (_myAvatarIndex >= 0 && _myAvatarIndex < _kAvatarEmojis.length) {
        final emoji = _kAvatarEmojis[_myAvatarIndex];
        final color = _kAvatarColors[_myAvatarIndex % _kAvatarColors.length];
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          alignment: Alignment.center,
          child: Text(emoji, style: TextStyle(fontSize: size * 0.55)),
        );
      } else if (_myCustomAvatar != null) {
        return ClipOval(
          child: Image.memory(_myCustomAvatar!,
              width: size, height: size, fit: BoxFit.cover),
        );
      }
      // Fallback for "me" with no avatar set
      return Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0xFFFFCC80),
        ),
        alignment: Alignment.center,
        child: Text('🐱', style: TextStyle(fontSize: size * 0.55)),
      );
    }

    // Others: use first 12 animal emojis
    final idx = name.hashCode.abs() % 12;
    final emoji = _kAvatarEmojis[idx];
    final color = _kAvatarColors[idx];
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      alignment: Alignment.center,
      child: Text(emoji, style: TextStyle(fontSize: size * 0.55)),
    );
  }

  Widget _buildPodiumWidget({
    required Map<String, dynamic> entry,
    required int rank,
    required double podiumHeight,
    required double aspect,
  }) {
    final info = _circleInfo[rank]!;
    final podiumWidth = podiumHeight * aspect;
    final circleDiam = podiumWidth * info['diam']!;
    final circleCx = podiumWidth * info['cx']!;
    final circleCy = podiumHeight * info['cy']!;
    final stars = entry['stars'] as int? ?? 0;
    final name = entry['name'] as String? ?? '';
    final isMe = entry['isMe'] == true;
    final displayName = isMe ? '我' : _maskName(name);

    final imageName = rank == 1
        ? 'first.png'
        : rank == 2
            ? 'second.png'
            : 'third.png';

    return SizedBox(
      width: podiumWidth,
      height: podiumHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Podium image
          Positioned.fill(
            child: cdnImage(
              'assets/home/ranking/$imageName',
              fit: BoxFit.contain,
              width: podiumWidth,
              height: podiumHeight,
              errorBuilder: (_, __, ___) => const SizedBox(),
            ),
          ),
          // Persistent colorful star orbit behind avatar
          if (isMe && _persistGlowCtrl != null)
            Positioned(
              left: circleCx - circleDiam * 0.75,
              top: circleCy - circleDiam * 0.75,
              width: circleDiam * 1.5,
              height: circleDiam * 1.5,
              child: CustomPaint(
                painter: _StarOrbitPainter(_persistGlowCtrl!.value),
              ),
            ),
          // Avatar clipped oval
          Positioned(
            left: circleCx - circleDiam * 0.45,
            top: circleCy - circleDiam * 0.45,
            width: circleDiam * 0.9,
            height: circleDiam * 0.9,
            child: ClipOval(child: _buildAvatar(entry, circleDiam * 0.9)),
          ),
          // Name + score on the podium cylinder
          Positioned(
            left: podiumWidth * 0.06,
            right: 0,
            bottom: podiumHeight * 0.05,
            child: isMe
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      // Brush stroke behind name
                      CustomPaint(
                        size: Size(podiumWidth * 0.35, podiumHeight * 0.12),
                        painter: const _BrushStrokePainter(),
                      ),
                      Text.rich(
                        TextSpan(children: [
                          TextSpan(
                            text: displayName,
                            style: TextStyle(
                              fontSize: podiumHeight * 0.085,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF2266AA),
                            ),
                          ),
                          TextSpan(
                            text: ' $stars⭐',
                            style: TextStyle(
                              fontSize: podiumHeight * 0.065,
                              fontWeight: FontWeight.w700,
                              color: Colors.black54,
                            ),
                          ),
                        ]),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  )
                : Text.rich(
                    TextSpan(children: [
                      TextSpan(
                        text: displayName,
                        style: TextStyle(
                          fontSize: podiumHeight * 0.085,
                          fontWeight: FontWeight.w900,
                          color: Colors.black87,
                        ),
                      ),
                      TextSpan(
                        text: ' $stars⭐',
                        style: TextStyle(
                          fontSize: podiumHeight * 0.065,
                          fontWeight: FontWeight.w700,
                          color: Colors.black54,
                        ),
                      ),
                    ]),
                    textAlign: TextAlign.center,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<Map<String, dynamic>> rest, bool meInTop7, int myIdx) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) => true,
      child: ListView.builder(
        padding: EdgeInsets.symmetric(horizontal: R.s(100), vertical: R.s(2)),
        itemCount: rest.length,
        itemBuilder: (_, i) => _buildListTile(
          rest[i],
          (rest[i]['isMe'] == true && !meInTop7) ? myIdx + 1 : i + 4,
        ),
      ),
    );
  }

  Widget _buildListTile(Map<String, dynamic> entry, int rank) {
    final name = entry['name'] as String? ?? '';
    final stars = entry['stars'] as int? ?? 0;
    final isMe = entry['isMe'] == true;

    final hasOrbit = isMe && _persistGlowCtrl != null;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Star orbit behind the tile
        if (hasOrbit)
          Positioned(
            left: -R.s(12),
            right: -R.s(12),
            top: -R.s(10),
            bottom: -R.s(5),
            child: CustomPaint(
              painter: _StarOrbitPainter(_persistGlowCtrl!.value),
            ),
          ),
        Container(
      margin: EdgeInsets.only(bottom: R.s(5)),
      padding: EdgeInsets.symmetric(horizontal: R.s(14), vertical: R.s(9)),
      decoration: BoxDecoration(
        color: isMe ? const Color(0xFFFFF3E0) : Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(R.s(14)),
        border: isMe
            ? Border.all(color: const Color(0xFFFF8C42), width: 2.5)
            : null,
        boxShadow: isMe
            ? [
                BoxShadow(
                    color: const Color(0xFFFF8C42).withOpacity(0.3),
                    blurRadius: R.s(14),
                    offset: Offset(0, R.s(4))),
                BoxShadow(
                    color: const Color(0xFFFF8C42).withOpacity(0.1),
                    blurRadius: R.s(24)),
              ]
            : [
                BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: R.s(4),
                    offset: Offset(0, R.s(1))),
              ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: R.s(28),
            child: Text('$rank',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: R.s(16),
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF999999))),
          ),
          SizedBox(width: R.s(8)),
          ClipOval(child: _buildAvatar(entry, R.s(32))),
          SizedBox(width: R.s(10)),
          Expanded(
            child: isMe
                ? Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      CustomPaint(
                        size: Size(R.s(26), R.s(26)),
                        painter: const _BrushStrokePainter(),
                      ),
                      Padding(
                        padding: EdgeInsets.only(left: R.s(10)),
                        child: Text(
                          '我',
                          style: TextStyle(
                            fontSize: R.s(16),
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF2266AA),
                          ),
                        ),
                      ),
                    ],
                  )
                : Text(
                    _maskName(name),
                    style: TextStyle(
                      fontSize: R.s(16),
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF333333),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
          Text('⭐', style: TextStyle(fontSize: R.s(20))),
          SizedBox(width: R.s(4)),
          Text('$stars',
              style: TextStyle(
                  fontSize: R.s(17),
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFFFF8C42))),
        ],
      ),
    ),
      ],
    );
  }

  void _triggerRankUpAnimation(int fromRank, int toRank) {
    final entries = List<Map<String, dynamic>>.from(_data[_period] ?? []);
    // Only show entries from rank 1 to fromRank
    final visible = entries.take(fromRank).toList();

    // User is currently at toRank-1 in the sorted list.
    // Move user to fromRank-1 (bottom) for animation start.
    final userEntry = visible.removeAt(toRank - 1);
    visible.insert(fromRank - 1, userEntry);

    _rankUpEntries = visible;
    _rankUpUserIdx = fromRank - 1;
    _rankUpNewRank = toRank;
    _rankUpCelebrate = false;
    _rankUpPositions = {for (int i = 0; i < visible.length; i++) i: i};

    setState(() => _showRankUp = true);

    // Pause 600ms then start climbing, one swap every 800ms
    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      _rankUpStepTimer = Timer.periodic(const Duration(milliseconds: 800), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }

        final userPos = _rankUpPositions[_rankUpUserIdx]!;
        if (userPos <= _rankUpNewRank - 1) {
          // Reached final position — celebrate with halo
          timer.cancel();
          setState(() => _rankUpCelebrate = true);
          // Hold celebration for 2.5s then fade out
          _rankUpFadeCtrl?.dispose();
          _rankUpFadeCtrl = AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 800),
          );
          _rankUpFadeCtrl!.addListener(() {
            if (mounted) setState(() {});
          });
          Future.delayed(const Duration(milliseconds: 1000), () {
            if (!mounted) return;
            _rankUpFadeCtrl!.forward().then((_) {
              if (mounted) {
                setState(() => _showRankUp = false);
              }
            });
          });
          return;
        }

        // Find the entry currently at userPos - 1
        final aboveIdx = _rankUpPositions.entries
            .firstWhere((e) => e.value == userPos - 1)
            .key;

        // Swap positions
        setState(() {
          _rankUpPositions[_rankUpUserIdx] = userPos - 1;
          _rankUpPositions[aboveIdx] = userPos;
        });
      });
    });
  }

  void _startPersistentGlow() {
    if (_persistGlowCtrl != null) return; // already running
    _persistGlowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 6000), // slow orbit
    )..repeat();
    _persistGlowCtrl!.addListener(() {
      if (mounted) setState(() {});
    });
  }

  Widget _buildRankUpOverlay(double w, double h) {
    final tileH = R.s(52);
    final gap = R.s(6);
    final totalEntries = _rankUpEntries.length;
    final listHeight = totalEntries * tileH + (totalEntries - 1) * gap;
    final fadeOut = _rankUpFadeCtrl?.value ?? 0.0;
    final opacity = (1.0 - fadeOut).clamp(0.0, 1.0);

    return Positioned.fill(
      child: IgnorePointer(
        child: Opacity(
          opacity: opacity,
          child: Container(
            color: Colors.black.withOpacity(0.55),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Title
                Text(
                  _rankUpCelebrate ? '🎉 排名提升！🎉' : '⬆️ 排名提升中...',
                  style: TextStyle(
                    fontSize: R.s(20),
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
                  ),
                ),
                SizedBox(height: R.s(16)),
                // Animated leaderboard
                Container(
                  width: w * 0.7,
                  height: listHeight.clamp(0.0, h * 0.55),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(R.s(16)),
                  ),
                  padding: EdgeInsets.symmetric(
                      horizontal: R.s(10), vertical: R.s(8)),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ...List.generate(totalEntries, (i) {
                      final slot = _rankUpPositions[i] ?? i;
                      final isMe = i == _rankUpUserIdx;
                      final entry = _rankUpEntries[i];
                      final name = entry['name'] as String? ?? '';
                      final stars = entry['stars'] as int? ?? 0;
                      final displayName =
                          isMe ? '我' : _maskName(name);
                      final displayRank = slot + 1;

                      return AnimatedPositioned(
                        duration: const Duration(milliseconds: 500),
                        curve: Curves.easeInOutCubic,
                        left: 0,
                        right: 0,
                        top: slot * (tileH + gap),
                        height: tileH,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 400),
                          decoration: BoxDecoration(
                            color: isMe
                                ? (_rankUpCelebrate
                                    ? const Color(0xFFFFD700)
                                        .withOpacity(0.95)
                                    : const Color(0xFFFF8C42)
                                        .withOpacity(0.9))
                                : Colors.white.withOpacity(0.85),
                            borderRadius: BorderRadius.circular(R.s(12)),
                            border: isMe
                                ? Border.all(
                                    color: _rankUpCelebrate
                                        ? const Color(0xFFFFD700)
                                        : const Color(0xFFFF8C42),
                                    width: 2.5)
                                : null,
                            boxShadow: isMe
                                ? [
                                    BoxShadow(
                                      color: (_rankUpCelebrate
                                              ? const Color(0xFFFFD700)
                                              : const Color(0xFFFF8C42))
                                          .withOpacity(0.5),
                                      blurRadius: R.s(12),
                                      spreadRadius: R.s(2),
                                    ),
                                  ]
                                : null,
                          ),
                          padding: EdgeInsets.symmetric(
                              horizontal: R.s(10)),
                          child: Row(
                            children: [
                              SizedBox(
                                width: R.s(28),
                                child: Text(
                                  '$displayRank',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: R.s(15),
                                    fontWeight: FontWeight.bold,
                                    color: isMe
                                        ? Colors.white
                                        : const Color(0xFF999999),
                                  ),
                                ),
                              ),
                              SizedBox(width: R.s(6)),
                              ClipOval(
                                  child: _buildAvatar(entry, R.s(30))),
                              SizedBox(width: R.s(8)),
                              Expanded(
                                child: isMe
                                    ? Stack(
                                        alignment: Alignment.centerLeft,
                                        children: [
                                          CustomPaint(
                                            size: Size(R.s(23), R.s(22)),
                                            painter:
                                                const _BrushStrokePainter(),
                                          ),
                                          Padding(
                                            padding: EdgeInsets.only(
                                                left: R.s(8)),
                                            child: Text(
                                              '我',
                                              style: TextStyle(
                                                fontSize: R.s(14),
                                                fontWeight: FontWeight.w900,
                                                color: const Color(0xFF2266AA),
                                              ),
                                            ),
                                          ),
                                        ],
                                      )
                                    : Text(
                                        displayName,
                                        style: TextStyle(
                                          fontSize: R.s(14),
                                          fontWeight: FontWeight.w600,
                                          color: const Color(0xFF333333),
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                              ),
                              Text('⭐',
                                  style: TextStyle(fontSize: R.s(16))),
                              SizedBox(width: R.s(3)),
                              Text(
                                '$stars',
                                style: TextStyle(
                                  fontSize: R.s(14),
                                  fontWeight: FontWeight.w900,
                                  color: isMe
                                      ? Colors.white
                                      : const Color(0xFFFF8C42),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    ],
                  ),
                ),
                if (_rankUpCelebrate) ...[
                  SizedBox(height: R.s(14)),
                  Text(
                    '⭐ 太棒了！继续加油！⭐',
                    style: TextStyle(
                      fontSize: R.s(20),
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFFFFD700),
                      shadows: [
                        Shadow(color: Colors.black54, blurRadius: 8),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    R.init(context);
    final entries = _entries;
    final top3 = entries.take(3).toList();
    final myIdx = entries.indexWhere((e) => e['isMe'] == true);
    final meInTop7 = myIdx >= 0 && myIdx < 7;
    List<Map<String, dynamic>> rest;
    if (entries.length <= 3) {
      rest = [];
    } else if (meInTop7) {
      rest = entries.sublist(3).take(4).toList();
    } else {
      rest = entries.sublist(3).take(3).toList();
      if (myIdx >= 0) rest.add(entries[myIdx]);
    }

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;

          return Stack(
            fit: StackFit.expand,
            children: [
              // Layer 1: Background
              Positioned.fill(
                child: cdnImage(
                  'assets/home/ranking/ranking_bg.png',
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  errorBuilder: (_, __, ___) => Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFFFFE0B2), Color(0xFFFFF8E1)],
                      ),
                    ),
                  ),
                ),
              ),

              // Layer 2: Podiums (2nd first, then 3rd, then 1st on top)
              if (!_loading && top3.length >= 2) ...[
                // Use smaller podiums on mobile
                () {
                  final ps = R.isMobile ? 0.7 : 1.0; // podium scale
                  final h1 = h * 0.38 * ps;
                  final h2 = h * 0.28 * ps;
                  final h3 = h * 0.26 * ps;
                  return Positioned(
                    left: w * 0.5 - h1 * (374 / 383) / 2 - h2 * (257 / 271) + w * 0.06,
                    bottom: R.isMobile ? h * 0.48 : h * 0.45,
                    child: _buildPodiumWidget(entry: top3[1], rank: 2, podiumHeight: h2, aspect: 257 / 271),
                  );
                }(),
              ],
              if (!_loading && top3.length >= 3) ...[
                () {
                  final ps = R.isMobile ? 0.7 : 1.0;
                  final h1 = h * 0.38 * ps;
                  final h3 = h * 0.26 * ps;
                  return Positioned(
                    right: w * 0.5 - h1 * (374 / 383) / 2 - h3 * (188 / 201) + w * 0.03,
                    bottom: R.isMobile ? h * 0.49 : h * 0.46,
                    child: _buildPodiumWidget(entry: top3[2], rank: 3, podiumHeight: h3, aspect: 188 / 201),
                  );
                }(),
              ],
              if (!_loading && top3.isNotEmpty) ...[
                () {
                  final ps = R.isMobile ? 0.7 : 1.0;
                  final h1 = h * 0.38 * ps;
                  return Positioned(
                    left: w * 0.5 - h1 * (374 / 383) / 2 + w * 0.01,
                    bottom: R.isMobile ? h * 0.47 : h * 0.44,
                    child: _buildPodiumWidget(entry: top3[0], rank: 1, podiumHeight: h1, aspect: 374 / 383),
                  );
                }(),
              ],

              // Layer 3: Eggy mascot bottom-right
              Positioned(
                right: R.s(16),
                bottom: R.s(12),
                child: cdnImage(
                  _todayDone
                      ? 'assets/home/ranking/eggy_after_study.png'
                      : 'assets/home/ranking/eggy_before_study.png',
                  height: h * 0.27,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const SizedBox(),
                ),
              ),

              // Layer 4: Countdown button top-left
              Positioned(
                left: R.s(16),
                top: R.s(16),
                child: GestureDetector(
                  onTap: _goHome,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: R.s(14), vertical: R.s(7)),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF8C42),
                      borderRadius: BorderRadius.circular(R.s(20)),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.orange.withOpacity(0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2)),
                      ],
                    ),
                    child: Text(
                      '回到主页 $_countdown',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: R.s(13),
                          fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ),

              // Layer 5: Tab bar
              Positioned(
                left: R.isMobile ? w * 0.05 : w * 0.25,
                right: R.isMobile ? w * 0.05 : w * 0.25,
                top: h * 0.14,
                child: Container(
                  padding: EdgeInsets.all(R.s(3)),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(R.s(25)),
                  ),
                  child: Row(
                    children: _tabs.map((tab) {
                      final sel = _period == tab['value'];
                      return Expanded(
                        child: GestureDetector(
                          onTap: () {
                            if (_period != tab['value']) {
                              setState(() => _period = tab['value']!);
                            }
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: EdgeInsets.symmetric(vertical: R.s(7)),
                            decoration: BoxDecoration(
                              color: sel
                                  ? const Color(0xFFFF8C42)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(R.s(22)),
                            ),
                            child: Text(
                              tab['label']!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: R.s(14),
                                fontWeight: FontWeight.w800,
                                color: sel
                                    ? Colors.white
                                    : const Color(0xFF666666),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),

              // Layer 6: List area
              Positioned(
                left: R.isMobile ? w * 0.02 : w * 0.1,
                right: R.isMobile ? w * 0.02 : w * 0.1,
                top: h * 0.60,
                bottom: 0,
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: Color(0xFFFF8C42)))
                    : Column(
                        children: [
                          // Divider line
                          Container(
                            margin: EdgeInsets.symmetric(horizontal: R.isMobile ? R.s(20) : R.s(100)),
                            height: 1,
                            color: const Color(0xFFE0C9A6).withOpacity(0.5),
                          ),
                          Expanded(
                            child: rest.isEmpty
                                ? const SizedBox()
                                : _buildList(rest, meInTop7, myIdx),
                          ),
                        ],
                      ),
              ),

              // Layer 7: Rank-up animation overlay
              if (_showRankUp) _buildRankUpOverlay(w, h),
            ],
          );
        },
      ),
    );
  }
}

class _StarOrbitPainter extends CustomPainter {
  final double t; // 0.0 → 1.0, repeating
  _StarOrbitPainter(this.t);

  static const _starColors = [
    Color(0xFFFF4E8C), // pink
    Color(0xFFFF9900), // orange
    Color(0xFFFFE600), // yellow
    Color(0xFF44FF88), // green
    Color(0xFF44CCFF), // cyan
    Color(0xFFCC44FF), // violet
    Color(0xFFFF6644), // red-orange
    Color(0xFFFFFFFF), // white
    Color(0xFF00FFD4), // teal
    Color(0xFFFF44CC), // magenta
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final rx = size.width * 0.40;
    final ry = size.height * 0.40;

    for (int i = 0; i < 10; i++) {
      final phase = (i / 10.0);
      final speed = 0.7 + (i % 3) * 0.2;
      final angle = (t * speed + phase) * 2 * pi;
      final px = cx + cos(angle) * rx;
      final py = cy + sin(angle) * ry;
      final color = _starColors[i];
      final radius = 3.5 + (i % 3) * 1.2;

      // Glow
      final glowPaint = Paint()
        ..color = color.withOpacity(0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
      canvas.drawCircle(Offset(px, py), radius * 2.0, glowPaint);

      // 4-point star
      final path = Path();
      final inner = radius * 0.42;
      for (int j = 0; j < 8; j++) {
        final a = (j * pi / 4) - pi / 2;
        final rad = (j.isEven) ? radius : inner;
        final x = px + cos(a) * rad;
        final y = py + sin(a) * rad;
        if (j == 0) path.moveTo(x, y); else path.lineTo(x, y);
      }
      path.close();
      canvas.drawPath(path, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_StarOrbitPainter old) => old.t != t;
}

/// Hand-drawn brush stroke highlight behind "我"
class _BrushStrokePainter extends CustomPainter {
  const _BrushStrokePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final paint = Paint()
      ..color = const Color(0x559DD4F0) // gentle light sky blue, very transparent
      ..style = PaintingStyle.fill;

    // Irregular brush stroke shape — wider, organic edges
    final path = Path()
      ..moveTo(w * 0.02, h * 0.35)
      ..cubicTo(w * 0.08, h * 0.05, w * 0.25, h * 0.10, w * 0.45, h * 0.08)
      ..cubicTo(w * 0.65, h * 0.04, w * 0.82, h * 0.12, w * 0.96, h * 0.22)
      ..cubicTo(w * 1.02, h * 0.35, w * 1.01, h * 0.55, w * 0.97, h * 0.68)
      ..cubicTo(w * 0.88, h * 0.92, w * 0.70, h * 0.96, w * 0.50, h * 0.95)
      ..cubicTo(w * 0.30, h * 0.98, w * 0.12, h * 0.88, w * 0.04, h * 0.72)
      ..cubicTo(-w * 0.01, h * 0.55, -w * 0.01, h * 0.45, w * 0.02, h * 0.35)
      ..close();

    canvas.drawPath(path, paint);

    // Second layer — slightly offset for texture
    final paint2 = Paint()
      ..color = const Color(0x159DD4F0)
      ..style = PaintingStyle.fill;

    final path2 = Path()
      ..moveTo(w * 0.06, h * 0.30)
      ..cubicTo(w * 0.15, h * 0.15, w * 0.35, h * 0.18, w * 0.55, h * 0.14)
      ..cubicTo(w * 0.75, h * 0.10, w * 0.90, h * 0.25, w * 0.94, h * 0.40)
      ..cubicTo(w * 0.98, h * 0.60, w * 0.85, h * 0.85, w * 0.60, h * 0.88)
      ..cubicTo(w * 0.35, h * 0.92, w * 0.10, h * 0.75, w * 0.06, h * 0.30)
      ..close();

    canvas.drawPath(path2, paint2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
