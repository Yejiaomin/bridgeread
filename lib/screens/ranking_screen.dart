import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../utils/cdn_asset.dart';
import '../utils/responsive_utils.dart';

class RankingScreen extends StatefulWidget {
  const RankingScreen({super.key});

  @override
  State<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends State<RankingScreen>
    with TickerProviderStateMixin {
  // Data
  String _period = 'week';
  bool _loading = true;
  Map<String, List<Map<String, dynamic>>> _data = {};

  // Countdown
  int _countdown = 30;
  Timer? _countdownTimer;

  // Egg avatar cache
  final Map<String, int> _eggCache = {};

  // Podium animations (3 controllers: gold, silver, bronze)
  late final List<AnimationController> _podiumCtrls;
  late final List<Animation<Offset>> _podiumSlides;
  late final List<Animation<double>> _podiumFades;

  // List item animations
  late AnimationController _listCtrl;

  // Star breathing animation
  late final AnimationController _starBreathCtrl;
  late final Animation<double> _starBreathAnim;

  // "Me" floating animation
  late final AnimationController _meFloatCtrl;
  late final Animation<double> _meFloatAnim;

  final _tabs = [
    {'label': '今日', 'value': 'day'},
    {'label': '本周', 'value': 'week'},
    {'label': '本月', 'value': 'month'},
  ];

  @override
  void initState() {
    super.initState();

    // Podium: 3 controllers with staggered delays
    _podiumCtrls = List.generate(3, (i) => AnimationController(
      vsync: this, duration: const Duration(milliseconds: 600),
    ));
    _podiumSlides = _podiumCtrls.map((c) =>
      Tween<Offset>(begin: const Offset(0, 1.5), end: Offset.zero)
          .animate(CurvedAnimation(parent: c, curve: Curves.elasticOut))
    ).toList();
    _podiumFades = _podiumCtrls.map((c) =>
      Tween<double>(begin: 0, end: 1)
          .animate(CurvedAnimation(parent: c, curve: Curves.easeIn))
    ).toList();

    // List stagger
    _listCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 800),
    );

    // Star breathing
    _starBreathCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _starBreathAnim = Tween<double>(begin: 0.7, end: 1.0)
        .animate(CurvedAnimation(parent: _starBreathCtrl, curve: Curves.easeInOut));

    // Me floating
    _meFloatCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _meFloatAnim = Tween<double>(begin: -2, end: 2)
        .animate(CurvedAnimation(parent: _meFloatCtrl, curve: Curves.easeInOut));

    _fetchAll();
    _startCountdown();
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      setState(() => _countdown--);
      if (_countdown <= 0) { timer.cancel(); _goHome(); }
    });
  }

  void _goHome() {
    _countdownTimer?.cancel();
    if (mounted) Navigator.pushReplacementNamed(context, '/home');
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    for (final c in _podiumCtrls) c.dispose();
    _listCtrl.dispose();
    _starBreathCtrl.dispose();
    _meFloatCtrl.dispose();
    super.dispose();
  }

  int _eggMonth(String name) =>
      _eggCache.putIfAbsent(name, () => Random().nextInt(6) + 1);

  String _maskName(String name) {
    if (name.isEmpty) return '*';
    return '${name.characters.first}${'*' * (name.characters.length - 1).clamp(1, 5)}';
  }

  List<Map<String, dynamic>> _normalize(Map<String, dynamic>? data) {
    if (data == null) return [];
    final list = (data['rankings'] as List?)
            ?.map((e) => Map<String, dynamic>.from(e))
            .toList() ?? [];
    for (final e in list) {
      e['name'] = e['childName'] ?? e['name'] ?? '';
      e['isMe'] = e['isCurrentUser'] ?? e['isMe'] ?? false;
    }
    return list;
  }

  Future<void> _fetchAll() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      ApiService().getRanking(period: 'day'),
      ApiService().getRanking(period: 'week'),
      ApiService().getRanking(period: 'month'),
    ]);
    if (mounted) {
      setState(() {
        _data = {
          'day': _normalize(results[0]),
          'week': _normalize(results[1]),
          'month': _normalize(results[2]),
        };
        _loading = false;
      });
      _playAnimations();
    }
  }

  void _playAnimations() {
    // Reset
    for (final c in _podiumCtrls) c.reset();
    _listCtrl.reset();

    // Staggered podium: gold(0ms), silver(200ms), bronze(400ms)
    // Order: gold=index1, silver=index0, bronze=index2 in display
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _podiumCtrls[0].forward(); // gold
    });
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _podiumCtrls[1].forward(); // silver
    });
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _podiumCtrls[2].forward(); // bronze
    });

    // List stagger
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _listCtrl.forward();
    });
  }

  void _switchTab(String period) {
    if (_period == period) return;
    setState(() => _period = period);
    _playAnimations();
  }

  List<Map<String, dynamic>> get _currentEntries => _data[_period] ?? [];

  @override
  Widget build(BuildContext context) {
    R.init(context);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFE0B2), Color(0xFFFFF8E1), Color(0xFFFFF3E0)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildTopBar(),
              SizedBox(height: R.s(6)),
              _buildTabBar(),
              SizedBox(height: R.s(8)),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF8C42)))
                    : _buildBody(),
              ),
              _buildMyRankBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: R.s(16), vertical: R.s(6)),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('🏆', style: TextStyle(fontSize: R.s(28))),
              SizedBox(width: R.s(8)),
              Text('排行榜',
                style: TextStyle(
                  fontSize: R.s(24), fontWeight: FontWeight.w900,
                  color: const Color(0xFFE65100),
                  shadows: [Shadow(color: Colors.orange.withOpacity(0.3), blurRadius: 8)],
                ),
              ),
            ],
          ),
          Positioned(
            left: 0,
            child: GestureDetector(
              onTap: _goHome,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: R.s(14), vertical: R.s(8)),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF8C42),
                  borderRadius: BorderRadius.circular(R.s(20)),
                  boxShadow: [BoxShadow(color: Colors.orange.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3))],
                ),
                child: Text('进入学习 $_countdown',
                  style: TextStyle(color: Colors.white, fontSize: R.s(13), fontWeight: FontWeight.w800)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: R.s(120)),
      padding: EdgeInsets.all(R.s(3)),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(R.s(25)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6)],
      ),
      child: Row(
        children: _tabs.map((tab) {
          final selected = _period == tab['value'];
          return Expanded(
            child: GestureDetector(
              onTap: () => _switchTab(tab['value']!),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: EdgeInsets.symmetric(vertical: R.s(8)),
                decoration: BoxDecoration(
                  color: selected ? const Color(0xFFFF8C42) : Colors.transparent,
                  borderRadius: BorderRadius.circular(R.s(22)),
                  boxShadow: selected ? [BoxShadow(color: Colors.orange.withOpacity(0.3), blurRadius: 6)] : null,
                ),
                child: Text(
                  tab['label']!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: R.s(15), fontWeight: FontWeight.w800,
                    color: selected ? Colors.white : const Color(0xFF666666),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBody() {
    final entries = _currentEntries;
    final top3 = entries.take(3).toList();
    final rest = entries.length > 3 ? entries.sublist(3).take(17).toList() : <Map<String, dynamic>>[];

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: R.s(80)),
      child: Column(
        children: [
          // Podium
          SizedBox(
            height: R.s(200),
            child: _buildPodium(top3),
          ),
          SizedBox(height: R.s(8)),
          // List (4th onwards)
          Expanded(
            child: rest.isEmpty
                ? Center(child: Text('更多同学正在努力中...', style: TextStyle(fontSize: R.s(14), color: const Color(0xFF999999))))
                : _buildList(rest),
          ),
        ],
      ),
    );
  }

  Widget _buildPodium(List<Map<String, dynamic>> top3) {
    if (top3.isEmpty) {
      return Center(child: Text('暂无排行数据', style: TextStyle(fontSize: R.s(16), color: const Color(0xFF999999))));
    }

    // Display order: [silver(1), gold(0), bronze(2)]
    final podiumData = <_PodiumInfo>[];
    if (top3.length >= 2) {
      podiumData.add(_PodiumInfo(top3[1], 2, const Color(0xFFC0C0C0), R.s(90), R.s(50), 1));
    }
    podiumData.add(_PodiumInfo(top3[0], 1, const Color(0xFFFFD700), R.s(120), R.s(70), 0));
    if (top3.length >= 3) {
      podiumData.add(_PodiumInfo(top3[2], 3, const Color(0xFFCD7F32), R.s(75), R.s(45), 2));
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: podiumData.map((p) {
        final name = p.entry['name'] as String? ?? '';
        final stars = p.entry['stars'] as int? ?? 0;
        final isMe = p.entry['isMe'] == true;
        final animIdx = p.animIndex;

        return Expanded(
          child: SlideTransition(
            position: _podiumSlides[animIdx],
            child: FadeTransition(
              opacity: _podiumFades[animIdx],
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Crown/medal for #1
                  if (p.rank == 1)
                    Text('👑', style: TextStyle(fontSize: R.s(24))),
                  // Avatar
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: p.color, width: R.s(3)),
                      boxShadow: [
                        BoxShadow(color: p.color.withOpacity(0.5), blurRadius: R.s(12), spreadRadius: R.s(2)),
                        if (isMe) BoxShadow(color: const Color(0xFFFF8C42).withOpacity(0.6), blurRadius: R.s(16)),
                      ],
                    ),
                    child: ClipOval(
                      child: cdnImage(
                        'assets/pet/costumes/base/egg_month${_eggMonth(name)}.png',
                        width: p.avatarSize, height: p.avatarSize, fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  SizedBox(height: R.s(4)),
                  // Name
                  Text(
                    isMe ? '👉我👈' : _maskName(name),
                    style: TextStyle(
                      fontSize: R.s(13), fontWeight: FontWeight.w800,
                      color: isMe ? const Color(0xFFFF8C42) : const Color(0xFF333333),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  // Stars with breathing effect
                  AnimatedBuilder(
                    animation: _starBreathAnim,
                    builder: (_, __) => Opacity(
                      opacity: p.rank == 1 ? _starBreathAnim.value : 1.0,
                      child: Text('⭐ $stars',
                        style: TextStyle(
                          fontSize: R.s(13), fontWeight: FontWeight.bold,
                          color: const Color(0xFFFF8C42),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: R.s(4)),
                  // Podium block
                  Container(
                    height: p.podiumHeight,
                    width: double.infinity,
                    margin: EdgeInsets.symmetric(horizontal: R.s(8)),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          p.color.withOpacity(p.rank == 1 ? 0.7 : 0.4),
                          p.color.withOpacity(p.rank == 1 ? 0.3 : 0.15),
                        ],
                      ),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(R.s(12)),
                        topRight: Radius.circular(R.s(12)),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: p.color.withOpacity(0.3),
                          blurRadius: R.s(8),
                          offset: Offset(0, R.s(-2)),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        '${p.rank}',
                        style: TextStyle(
                          fontSize: R.s(28), fontWeight: FontWeight.w900,
                          color: p.color.withOpacity(0.8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildList(List<Map<String, dynamic>> rest) {
    return AnimatedBuilder(
      animation: _listCtrl,
      builder: (_, __) => ListView.builder(
        padding: EdgeInsets.symmetric(horizontal: R.s(40), vertical: R.s(4)),
        itemCount: rest.length,
        itemBuilder: (_, i) {
          final delay = (i / rest.length).clamp(0.0, 1.0);
          final t = (_listCtrl.value - delay * 0.5).clamp(0.0, 1.0) / 0.5;
          final slideOffset = Offset(1.0 - t.clamp(0.0, 1.0), 0);
          final opacity = t.clamp(0.0, 1.0);

          return Transform.translate(
            offset: Offset(slideOffset.dx * R.s(100), 0),
            child: Opacity(
              opacity: opacity,
              child: _buildListTile(rest[i], i + 4),
            ),
          );
        },
      ),
    );
  }

  Widget _buildListTile(Map<String, dynamic> entry, int rank) {
    final name = entry['name'] as String? ?? '';
    final stars = entry['stars'] as int? ?? 0;
    final isMe = entry['isMe'] == true;

    Widget tile = Container(
      margin: EdgeInsets.only(bottom: R.s(6)),
      padding: EdgeInsets.symmetric(horizontal: R.s(12), vertical: R.s(8)),
      decoration: BoxDecoration(
        color: isMe ? const Color(0xFFFFF3E0) : Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(R.s(12)),
        border: isMe ? Border.all(color: const Color(0xFFFF8C42), width: 2) : null,
        boxShadow: isMe
            ? [
                BoxShadow(color: const Color(0xFFFF8C42).withOpacity(0.25), blurRadius: R.s(12), spreadRadius: R.s(1), offset: Offset(0, R.s(4))),
                BoxShadow(color: const Color(0xFFFF8C42).withOpacity(0.1), blurRadius: R.s(20), spreadRadius: R.s(2)),
              ]
            : [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: R.s(4), offset: Offset(0, R.s(2)))],
      ),
      child: Row(
        children: [
          SizedBox(
            width: R.s(28),
            child: Text('$rank', textAlign: TextAlign.center,
              style: TextStyle(fontSize: R.s(15), fontWeight: FontWeight.bold, color: const Color(0xFF999999))),
          ),
          SizedBox(width: R.s(6)),
          ClipOval(
            child: cdnImage(
              'assets/pet/costumes/base/egg_month${_eggMonth(name)}.png',
              width: R.s(30), height: R.s(30), fit: BoxFit.cover,
            ),
          ),
          SizedBox(width: R.s(8)),
          Expanded(
            child: Text(
              isMe ? '👉 我 👈' : _maskName(name),
              style: TextStyle(
                fontSize: R.s(15),
                fontWeight: isMe ? FontWeight.w900 : FontWeight.w600,
                color: isMe ? const Color(0xFFFF8C42) : const Color(0xFF333333),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text('⭐', style: TextStyle(fontSize: R.s(15))),
          SizedBox(width: R.s(3)),
          Text('$stars', style: TextStyle(fontSize: R.s(15), fontWeight: FontWeight.bold, color: const Color(0xFFFF8C42))),
        ],
      ),
    );

    // "Me" row has floating animation
    if (isMe) {
      tile = AnimatedBuilder(
        animation: _meFloatAnim,
        builder: (_, __) => Transform.translate(
          offset: Offset(0, _meFloatAnim.value),
          child: tile,
        ),
      );
    }

    return tile;
  }

  Widget _buildMyRankBar() {
    final entries = _currentEntries;
    final myIdx = entries.indexWhere((e) => e['isMe'] == true);
    if (myIdx < 0) return const SizedBox.shrink();

    final myEntry = entries[myIdx];
    return Container(
      margin: EdgeInsets.symmetric(horizontal: R.s(80), vertical: R.s(6)),
      padding: EdgeInsets.symmetric(horizontal: R.s(16), vertical: R.s(10)),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFFFF3E0), Color(0xFFFFE0B2)]),
        borderRadius: BorderRadius.circular(R.s(14)),
        border: Border.all(color: const Color(0xFFFF8C42), width: 2),
        boxShadow: [BoxShadow(color: const Color(0xFFFF8C42).withOpacity(0.2), blurRadius: R.s(10), offset: Offset(0, R.s(-2)))],
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: R.s(10), vertical: R.s(4)),
            decoration: BoxDecoration(
              color: const Color(0xFFFF8C42),
              borderRadius: BorderRadius.circular(R.s(10)),
            ),
            child: Text('我的排名', style: TextStyle(fontSize: R.s(12), fontWeight: FontWeight.bold, color: Colors.white)),
          ),
          SizedBox(width: R.s(12)),
          Text('#${myIdx + 1}', style: TextStyle(fontSize: R.s(20), fontWeight: FontWeight.w900, color: const Color(0xFFFF8C42))),
          const Spacer(),
          ClipOval(
            child: cdnImage(
              'assets/pet/costumes/base/egg_month${_eggMonth(myEntry['name'] as String? ?? '')}.png',
              width: R.s(32), height: R.s(32), fit: BoxFit.cover,
            ),
          ),
          SizedBox(width: R.s(8)),
          Text('👉 我 👈', style: TextStyle(fontSize: R.s(14), fontWeight: FontWeight.w900, color: const Color(0xFFFF8C42))),
          SizedBox(width: R.s(12)),
          Text('⭐ ${myEntry['stars'] ?? 0}', style: TextStyle(fontSize: R.s(15), fontWeight: FontWeight.bold, color: const Color(0xFFFF8C42))),
        ],
      ),
    );
  }
}

class _PodiumInfo {
  final Map<String, dynamic> entry;
  final int rank;
  final Color color;
  final double podiumHeight;
  final double avatarSize;
  final int animIndex; // 0=gold, 1=silver, 2=bronze
  const _PodiumInfo(this.entry, this.rank, this.color, this.podiumHeight, this.avatarSize, this.animIndex);
}
