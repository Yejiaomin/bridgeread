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

class _RankingScreenState extends State<RankingScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _dayEntries = [];
  List<Map<String, dynamic>> _weekEntries = [];
  List<Map<String, dynamic>> _monthEntries = [];

  int _countdown = 30;
  Timer? _countdownTimer;

  final Map<String, int> _eggCache = {};

  @override
  void initState() {
    super.initState();
    _fetchAll();
    _startCountdown();
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      setState(() => _countdown--);
      if (_countdown <= 0) {
        timer.cancel();
        _goHome();
      }
    });
  }

  void _goHome() {
    _countdownTimer?.cancel();
    if (mounted) Navigator.pushReplacementNamed(context, '/home');
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  int _eggMonth(String name) {
    return _eggCache.putIfAbsent(name, () => Random().nextInt(6) + 1);
  }

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
        _dayEntries = _normalize(results[0]);
        _weekEntries = _normalize(results[1]);
        _monthEntries = _normalize(results[2]);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    R.init(context);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFF5E6), Color(0xFFFFE8CC), Color(0xFFFFF0DB)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Top bar — just the button
              Padding(
                padding: EdgeInsets.symmetric(horizontal: R.s(16), vertical: R.s(6)),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: _goHome,
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: R.s(14), vertical: R.s(8)),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF8C42),
                          borderRadius: BorderRadius.circular(R.s(20)),
                        ),
                        child: Text('进入学习 $_countdown',
                          style: TextStyle(color: Colors.white, fontSize: R.s(14), fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: R.s(40)),
              // Title — right above the columns
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('🏆', style: TextStyle(fontSize: R.s(24))),
                  SizedBox(width: R.s(6)),
                  Text('排行榜', style: TextStyle(fontSize: R.s(22), fontWeight: FontWeight.bold, color: const Color(0xFFFF8C42))),
                ],
              ),
              SizedBox(height: R.s(8)),
              // 3 columns
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF8C42)))
                    : Padding(
                        padding: EdgeInsets.only(left: R.s(170), right: R.s(170), bottom: R.s(80)),
                        child: Row(
                          children: [
                            Expanded(flex: 4, child: _buildColumn('📆 本周', _weekEntries, false)),
                            SizedBox(width: R.s(24)),
                            Expanded(flex: 5, child: _buildColumn('📅 今日', _dayEntries, true)),
                            SizedBox(width: R.s(24)),
                            Expanded(flex: 4, child: _buildColumn('🗓️ 本月', _monthEntries, false)),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildColumn(String title, List<Map<String, dynamic>> entries, bool highlight) {
    // Show top 10
    final show = entries.take(20).toList();
    final myIdx = entries.indexWhere((e) => e['isMe'] == true);

    return Container(
      decoration: BoxDecoration(
        color: highlight ? Colors.white.withOpacity(0.95) : Colors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(R.s(16)),
        border: Border.all(
          color: highlight ? const Color(0xFFFF8C42) : const Color(0xFFE0E0E0),
          width: highlight ? 2.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: (highlight ? const Color(0xFFFF8C42) : Colors.black).withOpacity(highlight ? 0.25 : 0.06),
            blurRadius: highlight ? R.s(16) : R.s(8),
            offset: Offset(0, R.s(4)),
          ),
        ],
      ),
      child: Column(
        children: [
          // Title
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: R.s(10)),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFB74D), Color(0xFFFF8C42)],
              ),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(R.s(16)),
                topRight: Radius.circular(R.s(16)),
              ),
            ),
            child: Text(title,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: R.s(15), fontWeight: FontWeight.w900, color: Colors.white),
            ),
          ),
          // List
          Expanded(
            child: show.isEmpty
                ? Center(child: Text('暂无数据', style: TextStyle(fontSize: R.s(12), color: const Color(0xFF999999))))
                : ListView.builder(
                    padding: EdgeInsets.symmetric(vertical: R.s(4)),
                    itemCount: show.length,
                    itemBuilder: (_, i) => _buildRow(show[i], i + 1),
                  ),
          ),
          // My rank — always show at bottom
          if (myIdx >= 0)
            Container(
              padding: EdgeInsets.symmetric(horizontal: R.s(8), vertical: R.s(6)),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(R.s(16)),
                  bottomRight: Radius.circular(R.s(16)),
                ),
                border: const Border(top: BorderSide(color: Color(0xFFFFE0B2))),
              ),
              child: Row(
                children: [
                  Text('${myIdx + 1}', style: TextStyle(fontSize: R.s(13), fontWeight: FontWeight.bold, color: const Color(0xFFFF8C42))),
                  SizedBox(width: R.s(4)),
                  Text('👉 我 👈', style: TextStyle(fontSize: R.s(13), fontWeight: FontWeight.w900, color: const Color(0xFFFF8C42))),
                  const Spacer(),
                  Text('⭐ ${entries[myIdx]['stars'] ?? 0}', style: TextStyle(fontSize: R.s(13), fontWeight: FontWeight.bold, color: const Color(0xFFFF8C42))),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRow(Map<String, dynamic> entry, int rank) {
    final name = entry['name'] as String? ?? '';
    final stars = entry['stars'] as int? ?? 0;
    final isMe = entry['isMe'] == true;

    final rankWidget = rank <= 3
        ? Text(['🥇', '🥈', '🥉'][rank - 1], style: TextStyle(fontSize: R.s(18)))
        : Text('$rank', textAlign: TextAlign.center,
            style: TextStyle(fontSize: R.s(15), fontWeight: FontWeight.bold, color: const Color(0xFF999999)));

    final bgColor = isMe
        ? const Color(0xFFFFF3E0)
        : rank == 1 ? const Color(0xFFFFFDE7).withOpacity(0.6)
        : rank == 2 ? const Color(0xFFF5F5F5).withOpacity(0.5)
        : rank == 3 ? const Color(0xFFFBE9E7).withOpacity(0.5)
        : Colors.transparent;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: R.s(4), vertical: R.s(2)),
      padding: EdgeInsets.symmetric(horizontal: R.s(4), vertical: R.s(5)),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(R.s(8)),
        border: isMe ? Border.all(color: const Color(0xFFFF8C42), width: 1.5) : null,
      ),
      child: Row(
        children: [
          SizedBox(width: R.s(22), child: rankWidget),
          ClipOval(
            child: cdnImage(
              'assets/pet/costumes/base/egg_month${_eggMonth(name)}.png',
              width: R.s(20), height: R.s(20), fit: BoxFit.cover,
            ),
          ),
          SizedBox(width: R.s(2)),
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
          Text('⭐$stars', style: TextStyle(fontSize: R.s(15), fontWeight: FontWeight.bold, color: const Color(0xFFFF8C42))),
        ],
      ),
    );
  }
}
