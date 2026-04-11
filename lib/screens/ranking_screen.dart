import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/cdn_asset.dart';
import '../utils/responsive_utils.dart';

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
    with SingleTickerProviderStateMixin {
  String _period = 'week';
  bool _loading = true;
  bool _navigating = false;
  int _countdown = 30;
  Timer? _countdownTimer;
  Map<String, List<Map<String, dynamic>>> _data = {};
  final Map<String, int> _eggCache = {};

  int _myAvatarIndex = -1;
  Uint8List? _myCustomAvatar;

  late final AnimationController _starGlowCtrl;
  late final Animation<double> _starGlow;

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
    if (mounted) Navigator.pushReplacementNamed(context, '/home');
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _starGlowCtrl.dispose();
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

    final rng = Random();

    List<Map<String, dynamic>> _generate(int starVariation) {
      // Create fake entries
      final entries = <Map<String, dynamic>>[];
      for (final name in _fakeNames) {
        final fakeStars = (myStars - 5 + rng.nextInt(21) + starVariation).clamp(0, 99999);
        entries.add({'name': name, 'stars': fakeStars, 'isMe': false});
      }
      // Add "me" entry with real stars
      entries.add({'name': childName, 'stars': myStars, 'isMe': true});
      // Sort descending by stars
      entries.sort((a, b) => (b['stars'] as int).compareTo(a['stars'] as int));

      // Ensure "me" is in position 1, 2, or 3 (randomly)
      final meIdx = entries.indexWhere((e) => e['isMe'] == true);
      if (meIdx >= 0) {
        final me = entries.removeAt(meIdx);
        final targetPos = rng.nextInt(3); // 0, 1, or 2
        entries.insert(targetPos, me);
      }
      return entries;
    }

    if (mounted) {
      setState(() {
        _data = {
          'day': _generate(0),
          'week': _generate(2),
          'month': _generate(5),
        };
        _loading = false;
      });
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
            child: Text.rich(
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

    return Container(
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
            child: Text(
              isMe ? '我' : _maskName(name),
              style: TextStyle(
                fontSize: R.s(16),
                fontWeight: isMe ? FontWeight.w900 : FontWeight.w600,
                color: isMe
                    ? const Color(0xFFFF8C42)
                    : const Color(0xFF333333),
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
              if (!_loading && top3.length >= 2)
                Positioned(
                  left: w * 0.5 -
                      h * 0.38 * (374 / 383) / 2 -
                      h * 0.28 * (257 / 271) +
                      w * 0.06,
                  bottom: h * 0.45,
                  child: _buildPodiumWidget(
                    entry: top3[1],
                    rank: 2,
                    podiumHeight: h * 0.28,
                    aspect: 257 / 271,
                  ),
                ),
              if (!_loading && top3.length >= 3)
                Positioned(
                  right: w * 0.5 -
                      h * 0.38 * (374 / 383) / 2 -
                      h * 0.26 * (188 / 201) +
                      w * 0.03,
                  bottom: h * 0.46,
                  child: _buildPodiumWidget(
                    entry: top3[2],
                    rank: 3,
                    podiumHeight: h * 0.26,
                    aspect: 188 / 201,
                  ),
                ),
              if (!_loading && top3.isNotEmpty)
                Positioned(
                  left: w * 0.5 - h * 0.38 * (374 / 383) / 2 + w * 0.01,
                  bottom: h * 0.44,
                  child: _buildPodiumWidget(
                    entry: top3[0],
                    rank: 1,
                    podiumHeight: h * 0.38,
                    aspect: 374 / 383,
                  ),
                ),

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
                      '进入学习 $_countdown',
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
                left: w * 0.25,
                right: w * 0.25,
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
                left: w * 0.1,
                right: w * 0.1,
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
                            margin: EdgeInsets.symmetric(horizontal: R.s(100)),
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
            ],
          );
        },
      ),
    );
  }
}
