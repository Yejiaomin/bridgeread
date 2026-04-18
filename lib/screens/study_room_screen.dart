import 'dart:async';
import 'dart:convert';
import 'dart:math' show sin, pi, cos, Random;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/cdn_asset.dart';
import '../utils/responsive_utils.dart';
import '../services/api_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Item pools & helpers
// ─────────────────────────────────────────────────────────────────────────────

const _accessoryPool = [
  'glass', 'Beanie', 'Crown', 'Graduation_cap', 'Lollipop', 'stick',
];
const _decorationPool = [
  'alarm', 'car', 'dinosaur', 'fly', 'frame', 'globe',
  'robot', 'rocket', 'shark', 'soccer', 'teddyw', 'telescope',
  'Ultraman', 'dragon', 'gun', 'monkey', 'nezha', 'pig', 'rainbow_', 'trophy', 'vase',
  // New items
  'airplane_1', 'bear_1',
  'bunny_1', 'bunny_2', 'bunny_3', 'bunny_4', 'bunny_5',
  'bunny_6', 'bunny_7', 'bunny_8', 'bunny_9', 'bunny_10',
  'bus_1', 'cat_1', 'cat_2', 'cow_1', 'dinosaur_2', 'doll_1',
  'elephant_1', 'fox_1', 'goldfish_1', 'lego_1', 'lion_1',
  'penguin_1', 'plant_1',
  'princess_1', 'princess_2', 'princess_3', 'princess_4', 'princess_5', 'princess_6',
  'rubik_1', 'ship_1', 'truck_1', 'turtle_1',
];

bool _isAccessory(String id) => _accessoryPool.contains(id);

String _itemPath(String id) => _isAccessory(id)
    ? 'assets/pet/costumes/accessories/$id.png'
    : 'assets/shop/items/1month/$id.png';

const _itemNames = <String, String>{
  'glass': 'Glasses',
  'Beanie': 'Beanie',
  'Crown': 'Crown',
  'Graduation_cap': 'Graduation Cap',
  'Lollipop': 'Lollipop',
  'stick': 'Magic Stick',
  'alarm': 'Alarm Clock',
  'car': 'Race Car',
  'dinosaur': 'Dinosaur',
  'fly': 'Dragonfly',
  'frame': 'Picture Frame',
  'globe': 'Globe',
  'robot': 'Robot',
  'rocket': 'Rocket',
  'shark': 'Shark',
  'soccer': 'Soccer Ball',
  'teddyw': 'Teddy Bear',
  'telescope': 'Telescope',
  'Ultraman': 'Ultraman',
  'dragon': 'Dragon',
  'gun': 'Water Gun',
  'monkey': 'Monkey',
  'nezha': 'Nezha',
  'pig': 'Piggy',
  'rainbow_': 'Rainbow',
  'trophy': 'Trophy',
  'vase': 'Vase',
  // New items
  'airplane_1': 'Airplane',
  'bear_1': 'Bear',
  'bunny_1': 'Bunny', 'bunny_2': 'Bunny', 'bunny_3': 'Bunny', 'bunny_4': 'Bunny',
  'bunny_5': 'Bunny', 'bunny_6': 'Bunny', 'bunny_7': 'Bunny', 'bunny_8': 'Bunny',
  'bunny_9': 'Bunny', 'bunny_10': 'Bunny',
  'bus_1': 'Bus',
  'cat_1': 'Kitty', 'cat_2': 'Kitty',
  'cow_1': 'Cow',
  'dinosaur_2': 'Dinosaur',
  'doll_1': 'Doll',
  'elephant_1': 'Elephant',
  'fox_1': 'Fox',
  'goldfish_1': 'Goldfish',
  'lego_1': 'Lego',
  'lion_1': 'Lion',
  'penguin_1': 'Penguin',
  'plant_1': 'Plant',
  'princess_1': 'Princess', 'princess_2': 'Princess', 'princess_3': 'Princess',
  'princess_4': 'Princess', 'princess_5': 'Princess', 'princess_6': 'Princess',
  'rubik_1': "Rubik's Cube",
  'ship_1': 'Ship',
  'truck_1': 'Truck',
  'turtle_1': 'Turtle',
};

String _itemName(String id) => _itemNames[id] ?? id;

// ─────────────────────────────────────────────────────────────────────────────
// StudyRoomScreen
// ─────────────────────────────────────────────────────────────────────────────

class StudyRoomScreen extends StatefulWidget {
  const StudyRoomScreen({super.key});
  @override
  State<StudyRoomScreen> createState() => _StudyRoomScreenState();
}

class _StudyRoomScreenState extends State<StudyRoomScreen>
    with TickerProviderStateMixin {

  // ── Shelf slot positions (fractional centre coords) ────────────────────────
  static const List<List<double>> _slots = [
    [0.163, 0.325], [0.322, 0.325], [0.481, 0.325], [0.640, 0.325], [0.799, 0.325], // top row
    [0.163, 0.455], [0.322, 0.455], [0.481, 0.455], [0.640, 0.455], [0.799, 0.455], // middle row
    [0.163, 0.587], [0.322, 0.587], [0.481, 0.587], [0.640, 0.587], [0.799, 0.587], // bottom row
  ];

  // ── Persistent state ───────────────────────────────────────────────────────
  int _totalStars = 0;
  String? _equippedAccessory; // single slot — hat/glasses share; future: add slots for far-body items
  Map<int, String> _placed = {};        // shelf slot → decoration id
  List<String> _treasureBoxItems = [];  // all collected items
  int _eggyMonth = 1;                   // 1–6

  // ── UI state ───────────────────────────────────────────────────────────────
  bool _gachaAvailable = false;
  bool _showCollection = false;
  String? _droppedItem;
  bool _showDropResult = false;

  // ── Animation controllers ──────────────────────────────────────────────────
  late final AnimationController _breathCtrl;
  late final Animation<double>   _breathAnim;

  late final AnimationController _boxCtrl;
  late final Animation<double>   _boxAnim;



  late final AnimationController _jarShakeCtrl;
  late final Animation<double>   _jarShakeAnim;

  late final AnimationController _jarSparkleCtrl;

  final _player    = AudioPlayer();
  final _rng       = Random();
  final _jarKey    = GlobalKey();
  final _boxKey    = GlobalKey();
  final List<GlobalKey>    _slotKeys  = List.generate(15, (_) => GlobalKey());
  final List<OverlayEntry> _flyEntries = [];

  // ── Init ───────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    _breathCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2200))
      ..repeat(reverse: true);
    _breathAnim = Tween<double>(begin: 1.0, end: 1.07)
        .animate(CurvedAnimation(parent: _breathCtrl, curve: Curves.easeInOut));

    _boxCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 480));
    _boxAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.32), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 1.32, end: 0.86), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 0.86, end: 1.0),  weight: 1),
    ]).animate(CurvedAnimation(parent: _boxCtrl, curve: Curves.easeOut));

    _jarShakeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _jarShakeAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end:  10.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 10.0, end: -10.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin:-10.0, end:  10.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 10.0, end: -10.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin:-10.0, end:   0.0), weight: 1),
    ]).animate(_jarShakeCtrl);

    _jarSparkleCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2000))
      ..repeat();

    _loadData();

    // 5-minute auto-return timer
    _roomTimer = Timer(const Duration(minutes: 5), () {
      if (mounted) Navigator.pushReplacementNamed(context, '/home');
    });
  }

  Timer? _roomTimer;

  @override
  void dispose() {
    _roomTimer?.cancel();
    _breathCtrl.dispose();
    _boxCtrl.dispose();
    _jarShakeCtrl.dispose();
    _jarSparkleCtrl.dispose();
    _player.dispose();
    for (final e in _flyEntries) e.remove();
    super.dispose();
  }

  // ── Persistence ────────────────────────────────────────────────────────────

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();

    final int stars = prefs.getInt('total_stars') ?? 0;

    final placedJson = prefs.getString('placed_items') ?? '{}';
    final raw   = Map<String, dynamic>.from(jsonDecode(placedJson) as Map);
    final placed = raw.map((k, v) => MapEntry(int.parse(k), v as String));

    final boxJson   = prefs.getString('treasure_box_items') ?? '[]';
    final boxItems  = List<String>.from(jsonDecode(boxJson) as List);

    final equippedAccessory = prefs.getString('equipped_accessory');

    // Daily gacha check: 2 per day
    final today      = DateTime.now().toIso8601String().substring(0, 10);
    final gachaDate  = prefs.getString('gacha_date') ?? '';
    final gachaCount = (gachaDate == today) ? (prefs.getInt('gacha_count') ?? 0) : 0;
    final gachaAvail = stars >= 30; // no daily limit, just need 30 stars

    // Eggy month: switch every 30 days from first launch
    if (!prefs.containsKey('app_start_date')) {
      await prefs.setString('app_start_date', today);
      ApiService().setupProgress(appStartDate: today);
    }
    final startStr  = prefs.getString('app_start_date') ?? today;
    final startDate = DateTime.tryParse(startStr) ?? DateTime.now();
    final daysSince = DateTime.now().difference(startDate).inDays;
    final eggyMonth = (daysSince ~/ 30) % 6 + 1;

    if (mounted) {
      setState(() {
        _totalStars      = stars;
        _placed          = placed;
        _treasureBoxItems = boxItems;
        _equippedAccessory = equippedAccessory;
        _gachaAvailable  = gachaAvail;
        _eggyMonth       = eggyMonth;
      });
    }

    // Sync from server
    final data = await ApiService().getStudyRoom();
    if (data != null && data['success'] == true && mounted) {
      final sr = data['studyRoom'] as Map<String, dynamic>;
      final serverPlaced = sr['placedItems'] as String? ?? '{}';
      final serverBox = sr['treasureBoxItems'] as String? ?? '[]';
      final serverAccessory = sr['equippedAccessory'] as String? ?? '';
      final serverGachaDate = sr['gachaDate'] as String? ?? '';
      final serverGachaCount = sr['gachaCount'] as int? ?? 0;

      final serverPlacedMap = Map<String, dynamic>.from(jsonDecode(serverPlaced) as Map);
      final serverBoxList = List<String>.from(jsonDecode(serverBox) as List);

      // Only apply server data if it has content (avoid overwriting with empty defaults)
      if (serverPlacedMap.isNotEmpty || serverBoxList.isNotEmpty) {
        setState(() {
          _placed = serverPlacedMap.map((k, v) => MapEntry(int.parse(k), v as String));
          _treasureBoxItems = serverBoxList;
          if (serverAccessory.isNotEmpty) _equippedAccessory = serverAccessory;
          final sGachaCount = (serverGachaDate == today) ? serverGachaCount : 0;
          _gachaAvailable = _totalStars >= 30;
        });
        // Update local cache
        await prefs.setString('placed_items', serverPlaced);
        await prefs.setString('treasure_box_items', serverBox);
        if (serverAccessory.isNotEmpty) {
          await prefs.setString('equipped_accessory', serverAccessory);
        }
        await prefs.setString('gacha_date', serverGachaDate);
        await prefs.setInt('gacha_count', serverGachaCount);
        final serverEggy = sr['todayEggy'] as String? ?? '';
        if (serverEggy.isNotEmpty) {
          await prefs.setString('today_eggy', serverEggy);
        }
      }
    }
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('total_stars', _totalStars);
    final placedStr = jsonEncode(_placed.map((k, v) => MapEntry(k.toString(), v)));
    final boxStr = jsonEncode(_treasureBoxItems);
    await prefs.setString('placed_items', placedStr);
    await prefs.setString('treasure_box_items', boxStr);
    if (_equippedAccessory != null) {
      await prefs.setString('equipped_accessory', _equippedAccessory!);
    } else {
      await prefs.remove('equipped_accessory');
    }
    // Sync to server (fire-and-forget)
    ApiService().updateStudyRoom({
      'placedItems': placedStr,
      'treasureBoxItems': boxStr,
      'equippedAccessory': _equippedAccessory ?? '',
    }).then((ok) => debugPrint('[StudyRoom] sync ${ok ? 'ok' : 'failed'}'));
  }

  // ── Gacha ──────────────────────────────────────────────────────────────────

  Future<void> _onJarTap() async {
    if (!_gachaAvailable || _totalStars < 30) return;

    setState(() {
      _totalStars -= 30;
      _gachaAvailable = _totalStars >= 30; // can draw again if still enough
    });
    _saveData();

    // Sync star deduction to server
    ApiService().spendStars(30).then((serverStars) {
      if (serverStars != null && mounted) {
        setState(() {
          _totalStars = serverStars;
          _gachaAvailable = _totalStars >= 30;
        });
      }
    });

    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    await prefs.setString('gacha_date', today);
    final curDate = prefs.getString('gacha_date') ?? '';
    final curCount = (curDate == today) ? (prefs.getInt('gacha_count') ?? 0) : 0;
    await prefs.setInt('gacha_count', curCount + 1);
    ApiService().updateStudyRoom({'gachaDate': today, 'gachaCount': curCount + 1});

    // Only decoration items (shelf items), no accessories (wearable)
    final pool = _decorationPool;
    final dropped = pool[_rng.nextInt(pool.length)];

    // Shake jar, play sound
    _jarShakeCtrl.forward(from: 0);
    _player.play(cdnAudioSource('audio/sfx/magic-sparkle.wav'));

    // Fly animation from jar upward
    await Future.delayed(const Duration(milliseconds: 300));
    _flyGachaItem(dropped);

    // Show result card after fly
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;

    setState(() {
      _droppedItem    = dropped;
      _showDropResult = true;
      _gachaAvailable = _totalStars >= 30;
    });
    await _player.stop();
    // Use base name for audio: e.g. bunny_3 → bunny, princess_2 → princess
    final audioId = dropped.replaceAll(RegExp(r'_\d+$'), '');
    await _player.play(cdnAudioSource('audio/items/$audioId.mp3'));
  }

  void _flyGachaItem(String itemId) {
    final jarBox = _jarKey.currentContext?.findRenderObject() as RenderBox?;
    if (jarBox == null) return;

    final jarCenter = jarBox.localToGlobal(
        Offset(jarBox.size.width / 2, jarBox.size.height / 2));
    final dest  = jarCenter - const Offset(0, 200);
    final ctrl  = Offset(jarCenter.dx, jarCenter.dy - 80);

    final flyCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 750));
    final progress = CurvedAnimation(parent: flyCtrl, curve: Curves.easeOut);
    final scaleAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.3, end: 1.5), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 1.5, end: 1.0), weight: 1),
    ]).animate(flyCtrl);

    final starAngles = List.generate(8, (i) => i * pi / 4);

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => AnimatedBuilder(
        animation: flyCtrl,
        builder: (_, __) {
          final t   = progress.value;
          final pos = _bezier(jarCenter, ctrl, dest, t);

          // Star burst particles (early phase only)
          final particles = <Widget>[];
          if (t < 0.45) {
            for (final angle in starAngles) {
              final d  = t * 70;
              final px = jarCenter.dx + cos(angle) * d;
              final py = jarCenter.dy + sin(angle) * d;
              final op = ((1.0 - t / 0.45) * 0.9).clamp(0.0, 1.0);
              particles.add(Positioned(
                left: px - 8, top: py - 8,
                child: Opacity(
                  opacity: op,
                  child: const Icon(Icons.star, color: Color(0xFFFFD700), size: 16),
                ),
              ));
            }
          }

          return Stack(children: [
            ...particles,
            Positioned(
              left: pos.dx - 36,
              top:  pos.dy - 36,
              child: IgnorePointer(
                child: Transform.scale(
                  scale: scaleAnim.value,
                  child: Container(
                    width: 72, height: 72,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.92),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(
                        color: const Color(0xFFFFD700).withOpacity(0.65),
                        blurRadius: 18, spreadRadius: 4,
                      )],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: cdnImage(_itemPath(itemId), fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.star, color: Colors.amber)),
                    ),
                  ),
                ),
              ),
            ),
          ]);
        },
      ),
    );

    _flyEntries.add(entry);
    Overlay.of(context).insert(entry);
    flyCtrl.forward().then((_) {
      entry.remove();
      flyCtrl.dispose();
      _flyEntries.remove(entry);
    });
  }

  static Offset _bezier(Offset p0, Offset p1, Offset p2, double t) {
    final mt = 1 - t;
    return Offset(
      mt * mt * p0.dx + 2 * mt * t * p1.dx + t * t * p2.dx,
      mt * mt * p0.dy + 2 * mt * t * p1.dy + t * t * p2.dy,
    );
  }

  // Tap treasure box: collect only when shelf is full, otherwise view collection
  void _collectShelfToBox() {
    if (_placed.length < 15) {
      _boxCtrl.forward(from: 0);
      setState(() => _showCollection = true);
      return;
    }

    // Capture positions BEFORE clearing state
    final boxBox = _boxKey.currentContext?.findRenderObject() as RenderBox?;
    final boxCenter = boxBox != null
        ? boxBox.localToGlobal(Offset(boxBox.size.width / 2, boxBox.size.height / 2))
        : Offset(MediaQuery.of(context).size.width * 0.9,
                 MediaQuery.of(context).size.height * 0.9);

    final placedSnapshot = Map<int, String>.from(_placed);

    // Clear shelf and save immediately — no async blocking
    setState(() {
      _treasureBoxItems.addAll(placedSnapshot.values);
      _placed.clear();
    });
    _saveData();
    _player.play(cdnAudioSource('audio/sfx/cartoon-whistle.wav'));

    // Fire fly animations from captured slot positions (purely visual)
    int delay = 0;
    for (final entry in placedSnapshot.entries) {
      final slotBox = _slotKeys[entry.key].currentContext?.findRenderObject() as RenderBox?;
      if (slotBox == null) continue;
      final src = slotBox.localToGlobal(Offset(slotBox.size.width / 2, slotBox.size.height / 2));
      Future.delayed(Duration(milliseconds: delay), () {
        if (mounted) _flyToBox(entry.value, src, boxCenter);
      });
      delay += 60;
    }

    // Bounce box after all items land, then play close sound
    Future.delayed(Duration(milliseconds: delay + 480), () {
      if (mounted) {
        _boxCtrl.forward(from: 0);
        _player.play(cdnAudioSource('audio/pop.wav'));
      }
    });
  }

  void _flyToBox(String itemId, Offset src, Offset dest) {
    final ctrl = Offset((src.dx + dest.dx) / 2, src.dy - 60); // arc upward

    final flyCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 480));
    final progress = CurvedAnimation(parent: flyCtrl, curve: Curves.easeIn);
    final scale    = Tween<double>(begin: 1.0, end: 0.3).animate(flyCtrl);
    final opacity  = Tween<double>(begin: 1.0, end: 0.0)
        .animate(CurvedAnimation(parent: flyCtrl,
            curve: const Interval(0.6, 1.0)));

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => AnimatedBuilder(
        animation: flyCtrl,
        builder: (_, __) {
          final t   = progress.value;
          final mt  = 1 - t;
          final pos = Offset(
            mt * mt * src.dx + 2 * mt * t * ctrl.dx + t * t * dest.dx,
            mt * mt * src.dy + 2 * mt * t * ctrl.dy + t * t * dest.dy,
          );
          return Positioned(
            left: pos.dx - 30,
            top:  pos.dy - 30,
            child: IgnorePointer(
              child: Opacity(
                opacity: opacity.value,
                child: Transform.scale(
                  scale: scale.value,
                  child: cdnImage(_itemPath(itemId),
                      width: 60, height: 60, fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.star, color: Colors.amber, size: 60)),
                ),
              ),
            ),
          );
        },
      ),
    );

    _flyEntries.add(entry);
    Overlay.of(context).insert(entry);
    flyCtrl.forward().then((_) {
      entry.remove();
      flyCtrl.dispose();
      _flyEntries.remove(entry);
    });
  }

  // Fill order: bottom row first (indices 10-14), then middle (5-9), then top (0-4)
  static const _slotFillOrder = [10, 11, 12, 13, 14, 5, 6, 7, 8, 9, 0, 1, 2, 3, 4];

  void _autoPlaceDecoration(String itemId) {
    final slot = _slotFillOrder.firstWhere(
      (i) => !_placed.containsKey(i),
      orElse: () => -1,
    );
    if (slot == -1) return; // all slots full
    _placed[slot] = itemId;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (ctx, box) {
          final w = box.maxWidth;
          final h = box.maxHeight;
          return Stack(
            fit: StackFit.expand,
            children: [

              // ── Background ────────────────────────────────────────────────
              cdnImage('assets/home/study_room_bg.webp',
                  fit: BoxFit.cover, width: w, height: h),

              // ── Back button ───────────────────────────────────────────────
              Positioned(
                left: 8, top: 8,
                child: SafeArea(
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_ios_rounded,
                        color: Colors.white, size: 24),
                    onPressed: () {
                      if (Navigator.canPop(context)) {
                        Navigator.pop(context);
                      } else {
                        Navigator.pushReplacementNamed(context, '/home');
                      }
                    },
                  ),
                ),
              ),

              // ── Star badge (top-right) ────────────────────────────────────
              Positioned(
                right: 16,
                top: MediaQuery.of(ctx).padding.top + 10,
                child: _StarBadge(stars: _totalStars),
              ),

              // ── Shelf slots ───────────────────────────────────────────────
              ..._buildSlots(w, h),

              // ── Eggy with costume overlays ────────────────────────────────
              _buildEggy(w, h),

              // ── Star jar (top-right of eggy) ──────────────────────────────
              _buildStarJar(w, h),

              // ── Treasure box (bottom-right) ───────────────────────────────
              // Tap = collect shelf items into box | Long-press = view collection
              Positioned(
                left:   w * 0.751,
                top:    h * 0.809,
                width:  w * 0.2916,
                height: h * 0.2196,
                child: GestureDetector(
                  key: _boxKey,
                  onTap: _collectShelfToBox,
                  onLongPress: () {
                    _boxCtrl.forward(from: 0);
                    _player.play(cdnAudioSource('audio/sfx/book-open.wav'));
                    setState(() => _showCollection = true);
                  },
                  child: AnimatedBuilder(
                    animation: _boxAnim,
                    builder: (_, child) =>
                        Transform.scale(scale: _boxAnim.value, child: child),
                    child: _placed.length >= 15
                        ? AnimatedBuilder(
                            animation: _jarSparkleCtrl,
                            builder: (_, child) {
                              final s = 1.0 + sin(_jarSparkleCtrl.value * 2 * pi) * 0.06;
                              return Transform.scale(scale: s, child: child);
                            },
                            child: cdnImage(_placed.length >= 15
                                  ? 'assets/shop/items/box_opened.png'
                                  : 'assets/shop/items/box_closed.png',
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const SizedBox(),
                            ),
                          )
                        : cdnImage(_placed.length >= 15
                                ? 'assets/shop/items/box_opened.png'
                                : 'assets/shop/items/box_closed.png',
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const SizedBox(),
                          ),
                  ),
                ),
              ),

              // ── Shelf-full hint ───────────────────────────────────────────
              if (_placed.length >= 15 && !_showDropResult)
                _buildShelfFullHint(),

              // ── Drop result overlay ───────────────────────────────────────
              if (_showDropResult && _droppedItem != null)
                _buildDropResult(),

              // ── Collection overlay ────────────────────────────────────────
              if (_showCollection)
                _buildCollectionOverlay(w, h),
            ],
          );
        },
      ),
    );
  }

  // ── Eggy with costume overlays ─────────────────────────────────────────────

  Widget _buildEggy(double w, double h) {
    final size = R.s(300);
    return Positioned(
      left: w * 0.478 - size / 2,
      top:  h * 0.797 - size / 2,
      child: AnimatedBuilder(
        animation: _breathAnim,
        builder: (_, child) =>
            Transform.scale(scale: _breathAnim.value, child: child),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Base egg (monthly)
            cdnImage('assets/pet/costumes/base/egg_month$_eggyMonth.png',
              width: size, height: size, fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => cdnImage('assets/pet/eggy_transparent_bg.webp',
                width: size, height: size,
                errorBuilder: (_, __, ___) =>
                    SizedBox(width: size, height: size),
              ),
            ),
            // Accessory overlay (single slot — hat/glasses share)
            if (_equippedAccessory != null)
              cdnImage(_itemPath(_equippedAccessory!),
                width: size, height: size, fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => SizedBox(width: size, height: size),
              ),
          ],
        ),
      ),
    );
  }

  // ── Star jar ───────────────────────────────────────────────────────────────

  Widget _buildStarJar(double w, double h) {
    const jarSize = 108.0;
    return Positioned(
      left: w * 0.60,
      top:  h * 0.65,
      child: GestureDetector(
        key: _jarKey,
        onTap: _gachaAvailable ? _onJarTap : null,
        child: AnimatedBuilder(
          animation: Listenable.merge([_jarShakeAnim, _jarSparkleCtrl]),
          builder: (_, __) {
            final shake    = _jarShakeAnim.value;
            final sparkleT = _jarSparkleCtrl.value;
            return Transform.translate(
              offset: Offset(shake, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: jarSize, height: jarSize,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // Glow halo (available only)
                        if (_gachaAvailable)
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(
                                  color: const Color(0xFFFFD700).withOpacity(
                                      0.28 + sin(sparkleT * 2 * pi) * 0.18),
                                  blurRadius: 22, spreadRadius: 6,
                                )],
                              ),
                            ),
                          ),
                        // Jar body
                        Center(
                          child: Opacity(
                            opacity: _gachaAvailable ? 1.0 : 0.40,
                            child: Container(
                              width: 76, height: 84,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE8F4FF).withOpacity(0.88),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: _gachaAvailable
                                      ? const Color(0xFFFFD700)
                                      : Colors.grey.shade400,
                                  width: 2.2,
                                ),
                                boxShadow: _gachaAvailable
                                    ? [BoxShadow(
                                        color: const Color(0xFFFFD700).withOpacity(0.35),
                                        blurRadius: 14,
                                      )]
                                    : null,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Text('⭐', style: TextStyle(fontSize: 24)),
                                  Text(
                                    '$_totalStars',
                                    style: const TextStyle(
                                      fontSize: 14, fontWeight: FontWeight.w900,
                                      color: Color(0xFFD4521A),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Orbiting sparkle stars (available only)
                        if (_gachaAvailable)
                          ...List.generate(4, (i) {
                            final angle = sparkleT * 2 * pi + i * pi / 2;
                            final cx = jarSize / 2 + cos(angle) * 44.0;
                            final cy = jarSize / 2 + sin(angle) * 44.0;
                            final op = (sin(sparkleT * 2 * pi + i * pi / 2) * 0.45 + 0.55)
                                .clamp(0.1, 1.0);
                            return Positioned(
                              left: cx - 7, top: cy - 7,
                              child: Opacity(
                                opacity: op,
                                child: const Icon(Icons.star,
                                    color: Color(0xFFFFD700), size: 14),
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.58),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _gachaAvailable ? '-30⭐  Gacha!' : 'Used today',
                      style: TextStyle(
                        color: _gachaAvailable
                            ? const Color(0xFFFFD700)
                            : Colors.white38,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ── Shelf-full bubble above the treasure box ──────────────────────────────

  Widget _buildShelfFullHint() {
    return LayoutBuilder(builder: (ctx, constraints) {
      final w = constraints.maxWidth;
      final h = constraints.maxHeight;
      // Box: left=w*0.751, width=w*0.2916 → center-x = w*0.8968
      // Bubble centered above the box, bottom edge just above box top
      const bubbleW = 210.0;
      final bubbleLeft = w * 0.8968 - bubbleW / 2;
      final bubbleBottom = h * (1 - 0.809) + 6; // 6px above box top

      return Stack(children: [
        // Pulsing bubble
        Positioned(
          left: bubbleLeft,
          bottom: bubbleBottom,
          child: AnimatedBuilder(
            animation: _jarSparkleCtrl, // reuse existing repeating controller
            builder: (_, child) {
              final scale = 1.0 + sin(_jarSparkleCtrl.value * 2 * pi) * 0.04;
              return Transform.scale(scale: scale, child: child);
            },
            child: GestureDetector(
              onTap: _collectShelfToBox,
              child: CustomPaint(
                painter: _BubblePainter(),
                child: Container(
                  width: bubbleW,
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 18),
                  child: const Text(
                    "The shelf is full!\nTap the box to collect!",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF7B3F00),
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ]);
    });
  }

  // ── Drop result card ───────────────────────────────────────────────────────

  Widget _buildDropResult() {
    final item = _droppedItem!;
    final name = _itemName(item);
    return Container(  // no background dismiss — must tap OK
      color: Colors.black.withOpacity(0.56),
      child: Align(
        alignment: const Alignment(0, -0.2),
        child: GestureDetector(
            onTap: () {},
            child: Container(
              width: R.s(300),
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(26),
                boxShadow: [BoxShadow(
                  color: const Color(0xFFFFD700).withOpacity(0.55),
                  blurRadius: 32, spreadRadius: 6,
                )],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  Text(
                    'You got a $name!',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w900,
                        color: Color(0xFFD4521A))),
                  const SizedBox(height: 10),
                  cdnImage(_itemPath(item),
                    width: R.s(156), height: R.s(156), fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) =>
                        Icon(Icons.star, color: Colors.amber, size: R.s(156)),
                  ),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () {
                      _player.play(cdnAudioSource('audio/sfx/pop-click.wav'));
                      setState(() {
                        // Place decoration on shelf
                        _autoPlaceDecoration(item);
                        _treasureBoxItems.add(item);
                        _showDropResult = false;
                        _droppedItem    = null;
                      });
                      _saveData();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 30, vertical: 11),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF8C42), Color(0xFFFF6B35)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(26),
                        boxShadow: [BoxShadow(
                          color: const Color(0xFFFF6B35).withOpacity(0.40),
                          blurRadius: 10, offset: const Offset(0, 4),
                        )],
                      ),
                      child: const Text('OK!',
                          style: TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w900,
                              fontSize: 17)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
    );
  }

  // ── Collection overlay ─────────────────────────────────────────────────────

  Widget _buildCollectionOverlay(double w, double h) {
    return GestureDetector(
      onTap: () {
        _player.play(cdnAudioSource('audio/pop.wav'));
        setState(() => _showCollection = false);
      },
      child: Container(
        color: Colors.black.withOpacity(0.52),
        child: Center(
          child: GestureDetector(
            onTap: () {},
            child: Container(
              width:  w * 0.68,
              height: h * 0.74,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8F0),
                borderRadius: BorderRadius.circular(22),
                boxShadow: [BoxShadow(
                  color: Colors.black.withOpacity(0.32),
                  blurRadius: 22, offset: const Offset(0, 6),
                )],
              ),
              child: Column(
                children: [
                  // Title bar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text('Collection  收藏',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Color(0xFFD4521A), fontSize: 18,
                                  fontWeight: FontWeight.w900)),
                        ),
                        GestureDetector(
                          onTap: () {
                            _player.play(cdnAudioSource('audio/pop.wav'));
                            setState(() => _showCollection = false);
                          },
                          child: const Icon(Icons.close,
                              color: Color(0xFF8B5E3C), size: 20),
                        ),
                      ],
                    ),
                  ),
                  Container(height: 1,
                      color: const Color(0xFFFF8C42).withOpacity(0.28)),
                  // Grid or empty state
                  Expanded(
                    child: _treasureBoxItems.isEmpty
                        ? const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.inventory_2_outlined,
                                    color: Color(0xFFD4B896), size: 42),
                                SizedBox(height: 8),
                                Text('No items yet\n用星星罐每天抽一次！',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        color: Color(0xFF8B6040), fontSize: 12)),
                              ],
                            ),
                          )
                        : GridView.builder(
                            padding: const EdgeInsets.all(14),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 4,
                              childAspectRatio: 1.0,
                              mainAxisSpacing: 10,
                              crossAxisSpacing: 10,
                            ),
                            itemCount: _treasureBoxItems.length,
                            itemBuilder: (_, i) {
                              final id = _treasureBoxItems[i];
                              return Container(
                                decoration: BoxDecoration(
                                  color: const Color(0x0AFF8C42),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: const Color(0x38FF8C42), width: 1),
                                ),
                                padding: const EdgeInsets.all(7),
                                child: cdnImage(_itemPath(id), fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) =>
                                      const Icon(Icons.image_not_supported,
                                          color: Colors.grey),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Shelf slots ────────────────────────────────────────────────────────────

  List<Widget> _buildSlots(double w, double h) {
    return List.generate(_slots.length, (i) {
      final fx     = _slots[i][0];
      final fy     = _slots[i][1];
      final placed = _placed[i];

      final double itemSize = R.s(120);
      return Positioned(
        left: w * fx - itemSize / 2,
        top:  h * fy - itemSize / 2,
        child: SizedBox(
          key: _slotKeys[i],
          width: itemSize, height: itemSize,
          child: placed != null
              ? cdnImage(_itemPath(placed), fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.help_outline, color: Colors.white38))
              : null,
        ),
      );
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Speech bubble painter (tail pointing downward-right toward treasure box)
// ─────────────────────────────────────────────────────────────────────────────

class _BubblePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const r = 14.0;
    const tailH = 14.0;
    final bodyH = size.height - tailH;

    final paint = Paint()..color = const Color(0xFFFFF8E7);
    final border = Paint()
      ..color = const Color(0xFFD4A96A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final path = Path()
      ..moveTo(r, 0)
      ..lineTo(size.width - r, 0)
      ..arcToPoint(Offset(size.width, r), radius: const Radius.circular(r))
      ..lineTo(size.width, bodyH - r)
      ..arcToPoint(Offset(size.width - r, bodyH), radius: const Radius.circular(r))
      // tail: comes straight down from bottom-center
      ..lineTo(size.width * 0.55, bodyH)
      ..lineTo(size.width * 0.50, bodyH + tailH)
      ..lineTo(size.width * 0.45, bodyH)
      ..lineTo(r, bodyH)
      ..arcToPoint(Offset(0, bodyH - r), radius: const Radius.circular(r))
      ..lineTo(0, r)
      ..arcToPoint(Offset(r, 0), radius: const Radius.circular(r))
      ..close();

    canvas.drawPath(path, paint);
    canvas.drawPath(path, border);
  }

  @override
  bool shouldRepaint(_BubblePainter _) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Star badge (top-right HUD)
// ─────────────────────────────────────────────────────────────────────────────

class _StarBadge extends StatelessWidget {
  final int stars;
  const _StarBadge({required this.stars});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF1A0F07).withOpacity(0.85),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFFD700), width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('⭐', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 4),
          Text('$stars',
              style: const TextStyle(
                  color: Color(0xFFFFD700),
                  fontSize: 14,
                  fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}


