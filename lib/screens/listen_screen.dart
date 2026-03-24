import 'dart:async';
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

// ── Playlist ──────────────────────────────────────────────────────────────────

class _Track {
  final String label, path;
  const _Track(this.label, this.path);
}

const _kTracks = [
  _Track('Biscuit · 原版听力', 'assets/audio/biscuit01_original.mp3'),
];

// ── Screen ────────────────────────────────────────────────────────────────────

class ListenScreen extends StatefulWidget {
  const ListenScreen({super.key});
  @override
  State<ListenScreen> createState() => _ListenScreenState();
}

class _ListenScreenState extends State<ListenScreen>
    with TickerProviderStateMixin {
  final _player = AudioPlayer();

  // Vinyl spin
  late final AnimationController _spinCtrl;
  // Tonearm swing
  late final AnimationController _armCtrl;
  late final Animation<double>   _armAnim;

  bool     _playing     = false;
  int      _trackIdx    = 0;
  Duration _position    = Duration.zero;
  Duration _duration    = Duration.zero;
  bool     _seeking     = false;

  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();

    // Vinyl spins continuously at ~0.3 rev/sec
    _spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );

    // Tonearm: 0 = lifted (parked), 1 = on record
    _armCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _armAnim = CurvedAnimation(parent: _armCtrl, curve: Curves.easeInOut);

    _subs.addAll([
      _player.onPositionChanged.listen((p) {
        if (!_seeking && mounted) setState(() => _position = p);
      }),
      _player.onDurationChanged.listen((d) {
        if (mounted) setState(() => _duration = d);
      }),
      _player.onPlayerComplete.listen((_) => _nextTrack()),
    ]);

    // Auto-play first track
    WidgetsBinding.instance.addPostFrameCallback((_) => _playTrack(_trackIdx));
  }

  @override
  void dispose() {
    for (final s in _subs) s.cancel();
    _player.dispose();
    _spinCtrl.dispose();
    _armCtrl.dispose();
    super.dispose();
  }

  // ── Playback control ────────────────────────────────────────────────────────

  Future<void> _playTrack(int idx) async {
    if (idx < 0 || idx >= _kTracks.length) return;
    setState(() {
      _trackIdx = idx;
      _position = Duration.zero;
      _duration = Duration.zero;
    });
    await _player.stop();
    await _player.play(
        AssetSource(_kTracks[idx].path.replaceFirst('assets/', '')));
    _setPlaying(true);
  }

  void _setPlaying(bool playing) {
    setState(() => _playing = playing);
    if (playing) {
      _spinCtrl.repeat();
      _armCtrl.forward();
    } else {
      _spinCtrl.stop();
      _armCtrl.reverse();
    }
  }

  Future<void> _togglePlay() async {
    if (_playing) {
      await _player.pause();
      _setPlaying(false);
    } else {
      await _player.resume();
      _setPlaying(true);
    }
  }

  void _nextTrack() {
    if (_trackIdx < _kTracks.length - 1) {
      _playTrack(_trackIdx + 1);
    } else {
      _setPlaying(false);
    }
  }

  void _prevTrack() {
    if (_position.inSeconds > 2) {
      _player.seek(Duration.zero);
    } else if (_trackIdx > 0) {
      _playTrack(_trackIdx - 1);
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 8),
                  _buildTurntable(),
                  const SizedBox(height: 36),
                  _buildTrackInfo(),
                  const SizedBox(height: 24),
                  _buildProgressBar(),
                  const SizedBox(height: 20),
                  _buildControls(),
                  const SizedBox(height: 32),
                  _buildTrackList(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded,
                color: Color(0xFFFF8C42)),
            onPressed: () {
              _player.stop();
              Navigator.pop(context);
            },
          ),
          const Expanded(
            child: Text(
              '磨耳朵  👂',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF333333)),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  // ── Turntable (vinyl + tonearm) ─────────────────────────────────────────────

  Widget _buildTurntable() {
    const size = 220.0;
    const armLength = 130.0;

    return SizedBox(
      width: size + armLength * 0.6,
      height: size + 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Platter (subtle shadow base)
          Positioned(
            left: 0,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFF0F0F0),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 20,
                      offset: const Offset(0, 8)),
                ],
              ),
            ),
          ),
          // Spinning vinyl
          Positioned(
            left: 0,
            child: AnimatedBuilder(
              animation: _spinCtrl,
              builder: (_, __) => Transform.rotate(
                angle: _spinCtrl.value * 2 * pi,
                child: CustomPaint(
                  size: const Size(size, size),
                  painter: _VinylPainter(),
                ),
              ),
            ),
          ),
          // Tonearm pivot at top-right
          Positioned(
            right: 0,
            top: 8,
            child: AnimatedBuilder(
              animation: _armAnim,
              builder: (_, __) {
                // Arm swings from -30° (parked) to -10° (on record)
                final angle = (-30 + _armAnim.value * 20) * pi / 180;
                return Transform.rotate(
                  alignment: Alignment.topCenter,
                  angle: angle,
                  child: _buildArm(armLength),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArm(double length) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Pivot circle
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF555555),
            border: Border.all(color: Colors.grey.shade300, width: 2),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 4)
            ],
          ),
        ),
        // Arm shaft
        Container(
          width: 6,
          height: length,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            gradient: const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [Color(0xFF888888), Color(0xFFCCCCCC), Color(0xFF888888)],
            ),
          ),
        ),
        // Stylus head
        Container(
          width: 14,
          height: 10,
          decoration: BoxDecoration(
            color: const Color(0xFF444444),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        // Needle tip
        Container(
          width: 2,
          height: 8,
          color: const Color(0xFF333333),
        ),
      ],
    );
  }

  // ── Track info ──────────────────────────────────────────────────────────────

  Widget _buildTrackInfo() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          Text(
            'Biscuit · 小饼干',
            style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade400,
                fontWeight: FontWeight.w600,
                letterSpacing: 1),
          ),
          const SizedBox(height: 6),
          Text(
            _kTracks[_trackIdx].label,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Color(0xFF222222)),
          ),
          const SizedBox(height: 4),
          Text(
            '${_trackIdx + 1} / ${_kTracks.length}',
            style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }

  // ── Progress bar ────────────────────────────────────────────────────────────

  Widget _buildProgressBar() {
    final pos   = _position.inMilliseconds.toDouble();
    final total = _duration.inMilliseconds.toDouble();
    final max   = total > 0 ? total : 1.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape:
                  const RoundSliderOverlayShape(overlayRadius: 16),
              activeTrackColor: const Color(0xFFFF8C42),
              inactiveTrackColor: Colors.grey.shade200,
              thumbColor: const Color(0xFFFF8C42),
              overlayColor:
                  const Color(0xFFFF8C42).withValues(alpha: 0.15),
            ),
            child: Slider(
              value: pos.clamp(0, max),
              min: 0,
              max: max,
              onChangeStart: (_) => _seeking = true,
              onChanged: (v) =>
                  setState(() => _position = Duration(milliseconds: v.toInt())),
              onChangeEnd: (v) {
                _seeking = false;
                _player.seek(Duration(milliseconds: v.toInt()));
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_fmt(_position),
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade500)),
                Text(_fmt(_duration),
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade500)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Controls ────────────────────────────────────────────────────────────────

  Widget _buildControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Previous
        IconButton(
          iconSize: 36,
          icon: const Icon(Icons.skip_previous_rounded),
          color: const Color(0xFF555555),
          onPressed: _prevTrack,
        ),
        const SizedBox(width: 16),
        // Play / Pause
        GestureDetector(
          onTap: _togglePlay,
          child: Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFFF8C42),
              boxShadow: [
                BoxShadow(
                    color: const Color(0xFFFF8C42).withValues(alpha: 0.45),
                    blurRadius: 16,
                    offset: const Offset(0, 5)),
              ],
            ),
            child: Icon(
              _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: Colors.white,
              size: 38,
            ),
          ),
        ),
        const SizedBox(width: 16),
        // Next
        IconButton(
          iconSize: 36,
          icon: const Icon(Icons.skip_next_rounded),
          color: const Color(0xFF555555),
          onPressed: _nextTrack,
        ),
      ],
    );
  }

  // ── Mini track list ─────────────────────────────────────────────────────────

  Widget _buildTrackList() {
    // Show 3 tracks around current
    final start = (_trackIdx - 1).clamp(0, _kTracks.length - 1);
    final end   = (_trackIdx + 2).clamp(0, _kTracks.length);
    final visible = _kTracks.sublist(start, end);

    return Column(
      children: [
        Divider(color: Colors.grey.shade100, height: 1),
        ...visible.asMap().entries.map((e) {
          final realIdx = start + e.key;
          final isActive = realIdx == _trackIdx;
          return ListTile(
            dense: true,
            leading: Icon(
              isActive && _playing
                  ? Icons.graphic_eq_rounded
                  : Icons.music_note_rounded,
              color: isActive
                  ? const Color(0xFFFF8C42)
                  : Colors.grey.shade400,
              size: 20,
            ),
            title: Text(
              e.value.label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isActive ? FontWeight.w800 : FontWeight.normal,
                color: isActive
                    ? const Color(0xFFFF8C42)
                    : const Color(0xFF555555),
              ),
            ),
            onTap: () => _playTrack(realIdx),
          );
        }),
      ],
    );
  }
}

// ── Vinyl record painter ──────────────────────────────────────────────────────

class _VinylPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;

    // Outer disc
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFF1C1C28));

    // Grooves — concentric rings with alternating shades
    final groovePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    for (double gr = r * 0.30; gr < r * 0.94; gr += r * 0.028) {
      groovePaint.color = (gr ~/ (r * 0.028)).isEven
          ? const Color(0xFF2A2A38)
          : const Color(0xFF141420);
      canvas.drawCircle(c, gr, groovePaint);
    }

    // Shimmer arc
    final shimmer = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.0),
          Colors.white.withValues(alpha: 0.06),
          Colors.white.withValues(alpha: 0.0),
        ],
        stops: const [0.3, 0.6, 1.0],
        center: const Alignment(-0.4, -0.5),
      ).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawCircle(c, r, shimmer);

    // Label area (orange circle)
    canvas.drawCircle(
        c, r * 0.30, Paint()..color = const Color(0xFFFF8C42));

    // Label text ring
    canvas.drawCircle(
        c,
        r * 0.28,
        Paint()
          ..color = const Color(0xFFE67A30)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);

    // Center spindle hole
    canvas.drawCircle(c, r * 0.045, Paint()..color = const Color(0xFF0D0D18));

    // Tiny highlight on label
    canvas.drawCircle(
        Offset(c.dx - r * 0.08, c.dy - r * 0.10),
        r * 0.06,
        Paint()..color = Colors.white.withValues(alpha: 0.18));
  }

  @override
  bool shouldRepaint(_VinylPainter _) => false;
}
