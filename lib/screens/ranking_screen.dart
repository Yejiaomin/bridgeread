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
  String _period = 'week';
  bool _loading = true;
  Map<String, List<Map<String, dynamic>>> _data = {};

  int _countdown = 30;
  Timer? _countdownTimer;
  final Map<String, int> _eggCache = {};

  // Podium animations
  late final List<AnimationController> _podiumCtrls;
  late final List<Animation<Offset>> _podiumSlides;
  late final List<Animation<double>> _podiumFades;

  // List animation
  late AnimationController _listCtrl;

  // Star glow
  late final AnimationController _starGlowCtrl;
  late final Animation<double> _starGlow;

  // Me float
  late final AnimationController _meFloatCtrl;
  late final Animation<double> _meFloat;

  final _tabs = [
    {'label': '今日', 'value': 'day'},
    {'label': '本周', 'value': 'week'},
    {'label': '本月', 'value': 'month'},
  ];

  @override
  void initState() {
    super.initState();

    _podiumCtrls = List.generate(3, (_) => AnimationController(
      vsync: this, duration: const Duration(milliseconds: 700),
    ));
    _podiumSlides = _podiumCtrls.map((c) =>
      Tween<Offset>(begin: const Offset(0, 2), end: Offset.zero)
          .animate(CurvedAnimation(parent: c, curve: Curves.elasticOut))
    ).toList();
    _podiumFades = _podiumCtrls.map((c) =>
      Tween<double>(begin: 0, end: 1)
          .animate(CurvedAnimation(parent: c, curve: Curves.easeIn))
    ).toList();

    _listCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

    _starGlowCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);
    _starGlow = Tween<double>(begin: 0.6, end: 1.0)
        .animate(CurvedAnimation(parent: _starGlowCtrl, curve: Curves.easeInOut));

    _meFloatCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000))
      ..repeat(reverse: true);
    _meFloat = Tween<double>(begin: -2, end: 2)
        .animate(CurvedAnimation(parent: _meFloatCtrl, curve: Curves.easeInOut));

    _fetchAll();
    _startCountdown();
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _countdown--);
      if (_countdown <= 0) { t.cancel(); _goHome(); }
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
    _starGlowCtrl.dispose();
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
            ?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [];
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
    for (final c in _podiumCtrls) c.reset();
    _listCtrl.reset();
    Future.delayed(const Duration(milliseconds: 100), () { if (mounted) _podiumCtrls[0].forward(); });
    Future.delayed(const Duration(milliseconds: 350), () { if (mounted) _podiumCtrls[1].forward(); });
    Future.delayed(const Duration(milliseconds: 600), () { if (mounted) _podiumCtrls[2].forward(); });
    Future.delayed(const Duration(milliseconds: 500), () { if (mounted) _listCtrl.forward(); });
  }

  void _switchTab(String p) {
    if (_period == p) return;
    setState(() => _period = p);
    _playAnimations();
  }

  List<Map<String, dynamic>> get _entries => _data[_period] ?? [];

  // Check if today's modules are all done
  bool get _todayDone {
    final dayEntries = _data['day'] ?? [];
    final me = dayEntries.where((e) => e['isMe'] == true).firstOrNull;
    return me != null && (me['stars'] as int? ?? 0) > 0;
  }

  @override
  Widget build(BuildContext context) {
    R.init(context);
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background
          Positioned.fill(
            child: cdnImage('assets/home/ranking/ranking_bg.png',
              fit: BoxFit.cover, width: double.infinity, height: double.infinity,
              errorBuilder: (_, __, ___) => Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [Color(0xFFFFE0B2), Color(0xFFFFF8E1)],
                  ),
                ),
              ),
            ),
          ),

          // Content
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                _buildTabBar(),
                SizedBox(height: R.s(4)),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF8C42)))
                      : _buildBody(),
                ),
                _buildMyRankBar(),
                SizedBox(height: R.s(4)),
              ],
            ),
          ),

          // Eggy mascot bottom-right
          Positioned(
            right: R.s(16),
            bottom: R.s(12),
            child: cdnImage(
              _todayDone
                  ? 'assets/home/ranking/eggy_after_study.png'
                  : 'assets/home/ranking/eggy_before_study.png',
              width: R.s(90), height: R.s(90), fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const SizedBox(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: R.s(16), vertical: R.s(4)),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('🏆', style: TextStyle(fontSize: R.s(26))),
              SizedBox(width: R.s(6)),
              Text('排行榜', style: TextStyle(
                fontSize: R.s(24), fontWeight: FontWeight.w900,
                color: const Color(0xFFE65100),
              )),
            ],
          ),
          Positioned(
            left: 0,
            child: GestureDetector(
              onTap: _goHome,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: R.s(14), vertical: R.s(7)),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF8C42),
                  borderRadius: BorderRadius.circular(R.s(20)),
                  boxShadow: [BoxShadow(color: Colors.orange.withOpacity(0.3), blurRadius: 6, offset: const Offset(0, 2))],
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
      margin: EdgeInsets.symmetric(horizontal: R.s(200)),
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
              onTap: () => _switchTab(tab['value']!),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: EdgeInsets.symmetric(vertical: R.s(7)),
                decoration: BoxDecoration(
                  color: sel ? const Color(0xFFFF8C42) : Colors.transparent,
                  borderRadius: BorderRadius.circular(R.s(22)),
                ),
                child: Text(tab['label']!, textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: R.s(14), fontWeight: FontWeight.w800,
                    color: sel ? Colors.white : const Color(0xFF666666),
                  )),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBody() {
    final entries = _entries;
    final top3 = entries.take(3).toList();
    final rest = entries.length > 3 ? entries.sublist(3).take(17).toList() : <Map<String, dynamic>>[];

    return Column(
      children: [
        // Podium
        SizedBox(
          height: R.s(180),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: R.s(150)),
            child: _buildPodium(top3),
          ),
        ),
        // Divider
        Container(
          margin: EdgeInsets.symmetric(horizontal: R.s(100)),
          height: 1,
          color: const Color(0xFFE0C9A6).withOpacity(0.5),
        ),
        SizedBox(height: R.s(4)),
        // List
        Expanded(
          child: rest.isEmpty
              ? const SizedBox()
              : _buildList(rest),
        ),
      ],
    );
  }

  Widget _buildPodium(List<Map<String, dynamic>> top3) {
    if (top3.isEmpty) return const SizedBox();

    // Order: [silver(idx1), gold(idx0), bronze(idx2)]
    final items = <_PodiumItem>[];
    if (top3.length >= 2) items.add(_PodiumItem(top3[1], 2, const Color(0xFFC0C0C0), R.s(65), R.s(44), 1));
    items.add(_PodiumItem(top3[0], 1, const Color(0xFFFFD700), R.s(85), R.s(56), 0));
    if (top3.length >= 3) items.add(_PodiumItem(top3[2], 3, const Color(0xFFCD7F32), R.s(55), R.s(40), 2));

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: items.map((p) {
        final name = p.entry['name'] as String? ?? '';
        final stars = p.entry['stars'] as int? ?? 0;
        final isMe = p.entry['isMe'] == true;
        final ai = p.animIdx;

        return Expanded(
          child: SlideTransition(
            position: _podiumSlides[ai],
            child: FadeTransition(
              opacity: _podiumFades[ai],
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Crown for #1
                  if (p.rank == 1) Text('👑', style: TextStyle(fontSize: R.s(22))),
                  // Avatar with colored ring
                  Container(
                    padding: EdgeInsets.all(R.s(3)),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: p.color.withOpacity(0.3),
                      border: Border.all(color: p.color, width: R.s(3)),
                      boxShadow: [
                        if (p.rank == 1) BoxShadow(color: const Color(0xFFFFD700).withOpacity(0.6), blurRadius: R.s(16), spreadRadius: R.s(4)),
                        if (isMe) BoxShadow(color: const Color(0xFFFF8C42).withOpacity(0.5), blurRadius: R.s(12)),
                      ],
                    ),
                    child: ClipOval(
                      child: cdnImage(
                        'assets/pet/costumes/base/egg_month${_eggMonth(name)}.png',
                        width: p.avatarSize, height: p.avatarSize, fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  SizedBox(height: R.s(2)),
                  // Name
                  Text(isMe ? '👉我👈' : _maskName(name),
                    style: TextStyle(fontSize: R.s(12), fontWeight: FontWeight.w800,
                      color: isMe ? const Color(0xFFFF8C42) : const Color(0xFF5D4037)),
                    overflow: TextOverflow.ellipsis,
                  ),
                  // Podium cylinder
                  Container(
                    height: p.podiumH,
                    width: R.s(100),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter, end: Alignment.bottomCenter,
                        colors: [
                          p.color.withOpacity(p.rank == 1 ? 0.9 : 0.6),
                          p.color.withOpacity(p.rank == 1 ? 0.5 : 0.25),
                        ],
                      ),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(R.s(14)),
                        topRight: Radius.circular(R.s(14)),
                      ),
                      boxShadow: [BoxShadow(color: p.color.withOpacity(0.3), blurRadius: R.s(6))],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Rank number in circle
                        Container(
                          width: R.s(28), height: R.s(28),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: p.color.withOpacity(0.8),
                            border: Border.all(color: Colors.white.withOpacity(0.6), width: 2),
                          ),
                          child: Center(child: Text('${p.rank}',
                            style: TextStyle(fontSize: R.s(14), fontWeight: FontWeight.w900, color: Colors.white))),
                        ),
                        SizedBox(height: R.s(2)),
                        // Stars
                        AnimatedBuilder(
                          animation: _starGlow,
                          builder: (_, __) => Opacity(
                            opacity: p.rank == 1 ? _starGlow.value : 1.0,
                            child: Text('$stars',
                              style: TextStyle(fontSize: R.s(14), fontWeight: FontWeight.w900, color: Colors.white)),
                          ),
                        ),
                      ],
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
        padding: EdgeInsets.symmetric(horizontal: R.s(100), vertical: R.s(2)),
        itemCount: rest.length,
        itemBuilder: (_, i) {
          final delay = (i / rest.length).clamp(0.0, 1.0);
          final t = ((_listCtrl.value - delay * 0.4) / 0.6).clamp(0.0, 1.0);
          return Transform.translate(
            offset: Offset((1.0 - t) * R.s(80), 0),
            child: Opacity(opacity: t, child: _buildListTile(rest[i], i + 4)),
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
      margin: EdgeInsets.only(bottom: R.s(5)),
      padding: EdgeInsets.symmetric(horizontal: R.s(14), vertical: R.s(9)),
      decoration: BoxDecoration(
        color: isMe ? const Color(0xFFFFF3E0) : Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(R.s(14)),
        border: isMe ? Border.all(color: const Color(0xFFFF8C42), width: 2.5) : null,
        boxShadow: isMe
            ? [
                BoxShadow(color: const Color(0xFFFF8C42).withOpacity(0.3), blurRadius: R.s(14), offset: Offset(0, R.s(4))),
                BoxShadow(color: const Color(0xFFFF8C42).withOpacity(0.1), blurRadius: R.s(24)),
              ]
            : [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: R.s(4), offset: Offset(0, R.s(1)))],
      ),
      child: Row(
        children: [
          SizedBox(width: R.s(28),
            child: Text('$rank', textAlign: TextAlign.center,
              style: TextStyle(fontSize: R.s(16), fontWeight: FontWeight.bold, color: const Color(0xFF999999)))),
          SizedBox(width: R.s(8)),
          ClipOval(child: cdnImage(
            'assets/pet/costumes/base/egg_month${_eggMonth(name)}.png',
            width: R.s(32), height: R.s(32), fit: BoxFit.cover)),
          SizedBox(width: R.s(10)),
          if (isMe) ...[
            Text('👍', style: TextStyle(fontSize: R.s(16))),
            SizedBox(width: R.s(4)),
          ],
          Expanded(child: Text(
            isMe ? '我' : _maskName(name),
            style: TextStyle(fontSize: R.s(16), fontWeight: isMe ? FontWeight.w900 : FontWeight.w600,
              color: isMe ? const Color(0xFFFF8C42) : const Color(0xFF333333)),
            overflow: TextOverflow.ellipsis,
          )),
          // Star icon (bigger)
          Text('⭐', style: TextStyle(fontSize: R.s(20))),
          SizedBox(width: R.s(4)),
          Text('$stars', style: TextStyle(fontSize: R.s(17), fontWeight: FontWeight.w900, color: const Color(0xFFFF8C42))),
        ],
      ),
    );

    if (isMe) {
      tile = AnimatedBuilder(
        animation: _meFloat,
        builder: (_, __) => Transform.translate(offset: Offset(0, _meFloat.value), child: tile),
      );
    }
    return tile;
  }

  Widget _buildMyRankBar() {
    final entries = _entries;
    final myIdx = entries.indexWhere((e) => e['isMe'] == true);
    if (myIdx < 0) return const SizedBox.shrink();

    final me = entries[myIdx];
    return Container(
      margin: EdgeInsets.symmetric(horizontal: R.s(100), vertical: R.s(2)),
      padding: EdgeInsets.symmetric(horizontal: R.s(16), vertical: R.s(8)),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFFFF3E0), Color(0xFFFFE0B2)]),
        borderRadius: BorderRadius.circular(R.s(14)),
        border: Border.all(color: const Color(0xFFFF8C42), width: 2),
        boxShadow: [BoxShadow(color: const Color(0xFFFF8C42).withOpacity(0.15), blurRadius: R.s(8))],
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: R.s(10), vertical: R.s(3)),
            decoration: BoxDecoration(color: const Color(0xFFFF8C42), borderRadius: BorderRadius.circular(R.s(10))),
            child: Text('我的排名', style: TextStyle(fontSize: R.s(12), fontWeight: FontWeight.bold, color: Colors.white)),
          ),
          SizedBox(width: R.s(10)),
          Text('#${myIdx + 1}', style: TextStyle(fontSize: R.s(18), fontWeight: FontWeight.w900, color: const Color(0xFFFF8C42))),
          const Spacer(),
          ClipOval(child: cdnImage('assets/pet/costumes/base/egg_month${_eggMonth(me['name'] as String? ?? '')}.png',
            width: R.s(28), height: R.s(28), fit: BoxFit.cover)),
          SizedBox(width: R.s(6)),
          Text('👍 我', style: TextStyle(fontSize: R.s(14), fontWeight: FontWeight.w900, color: const Color(0xFFFF8C42))),
          SizedBox(width: R.s(10)),
          Text('⭐ ${me['stars'] ?? 0}', style: TextStyle(fontSize: R.s(15), fontWeight: FontWeight.bold, color: const Color(0xFFFF8C42))),
        ],
      ),
    );
  }
}

class _PodiumItem {
  final Map<String, dynamic> entry;
  final int rank;
  final Color color;
  final double podiumH, avatarSize;
  final int animIdx;
  const _PodiumItem(this.entry, this.rank, this.color, this.podiumH, this.avatarSize, this.animIdx);
}
