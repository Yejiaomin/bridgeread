import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/responsive_utils.dart';
import '../services/api_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ProfileScreen — child profile / personal center (landscape two-column)
// ─────────────────────────────────────────────────────────────────────────────

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _AvatarOption {
  final String emoji;
  final Color color;
  const _AvatarOption(this.emoji, this.color);
}

const _kPrimary = Color(0xFFFF8C42);
const _kBg = Color(0xFFFFF8E8);
const _kBeigeFill = Color(0xFFFFF0DC);
const _kBorder = Color(0xFFEED6B5);
const _kGrayBorder = Color(0xFFD4C4B0);
const _kChipBg = Color(0xFFFAF4ED);

const List<_AvatarOption> _avatarOptions = [
  // Animals
  _AvatarOption('🐱', Color(0xFFF48FB1)),
  _AvatarOption('🐶', Color(0xFF90CAF9)),
  _AvatarOption('🐰', Color(0xFFCE93D8)),
  _AvatarOption('🐼', Color(0xFFA5D6A7)),
  _AvatarOption('🦊', Color(0xFFFFCC80)),
  _AvatarOption('🐨', Color(0xFF80CBC4)),
  _AvatarOption('🦁', Color(0xFFFFE082)),
  _AvatarOption('🐸', Color(0xFFDCE775)),
  _AvatarOption('🐧', Color(0xFF9FA8DA)),
  _AvatarOption('🦄', Color(0xFFF8BBD0)),
  _AvatarOption('🐮', Color(0xFFBCAAA4)),
  _AvatarOption('🐷', Color(0xFFEF9A9A)),
  // More animals
  _AvatarOption('🐻', Color(0xFFD7CCC8)),
  _AvatarOption('🐯', Color(0xFFFFE0B2)),
  _AvatarOption('🐹', Color(0xFFFFF9C4)),
  _AvatarOption('🐰', Color(0xFFE1BEE7)),
  _AvatarOption('🦋', Color(0xFFB3E5FC)),
  _AvatarOption('🐢', Color(0xFFC8E6C9)),
  // Cute things
  _AvatarOption('🌻', Color(0xFFFFF176)),
  _AvatarOption('🍓', Color(0xFFEF9A9A)),
  _AvatarOption('🌈', Color(0xFFB2EBF2)),
  _AvatarOption('⭐', Color(0xFFFFE082)),
  _AvatarOption('🎀', Color(0xFFF8BBD0)),
  _AvatarOption('🧸', Color(0xFFD7CCC8)),
  _AvatarOption('🎨', Color(0xFFE6EE9C)),
  _AvatarOption('🎵', Color(0xFFCE93D8)),
  _AvatarOption('🚀', Color(0xFF90CAF9)),
  _AvatarOption('🌸', Color(0xFFF48FB1)),
  _AvatarOption('🍭', Color(0xFFFFAB91)),
  _AvatarOption('🦖', Color(0xFFA5D6A7)),
  _AvatarOption('🐊', Color(0xFF80CBC4)),
  // Extra column
  _AvatarOption('🐝', Color(0xFFFFE082)),
  _AvatarOption('🦀', Color(0xFFEF9A9A)),
  _AvatarOption('🐙', Color(0xFFCE93D8)),
  _AvatarOption('🦩', Color(0xFFF48FB1)),
  _AvatarOption('🐳', Color(0xFF90CAF9)),
  _AvatarOption('🦜', Color(0xFFA5D6A7)),
  _AvatarOption('🍀', Color(0xFFC8E6C9)),
];

const List<String> _hobbyOptions = [
  '阅读', '画画', '运动', '音乐', '游戏', '游泳', '爬山', '唱歌', '跳舞', '编程',
  '做饭', '旅行', '摄影', '手工', '棋类', '滑板', '骑车', '钓鱼', '种植', '看电影',
];

const List<String> _goalOptions = [
  '7天', '14天', '30天', '60天', '100天', '200天', '300天', 'Forever',
];

class _ProfileScreenState extends State<ProfileScreen> {
  SharedPreferences? _prefs;

  final _nameCtrl = TextEditingController();
  int _avatarIndex = 0;
  Uint8List? _customAvatar;
  String _childName = '';
  String _birthday = '';
  int _totalStars = 0;
  int _streakDays = 0;
  String _gender = '';
  Set<String> _selectedHobbies = {};
  String _goal = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    // Load from local cache first
    setState(() {
      _prefs = prefs;
      _avatarIndex = prefs.getInt('profile_avatar') ?? 0;
      _childName = prefs.getString('child_name') ?? '';
      _nameCtrl.text = _childName;
      _birthday = prefs.getString('profile_birthday') ?? '';
      _gender = prefs.getString('profile_gender') ?? '';
      _totalStars = prefs.getInt('total_stars') ?? 0;
      _streakDays = prefs.getInt('streak_days') ?? 0;
      final hobbiesStr = prefs.getString('profile_hobbies') ?? '';
      _selectedHobbies =
          hobbiesStr.isEmpty ? {} : hobbiesStr.split(',').toSet();
      _goal = prefs.getString('profile_goal') ?? '';
      final avatarBase64 = prefs.getString('profile_custom_avatar');
      if (avatarBase64 != null && avatarBase64.isNotEmpty) {
        _customAvatar = base64Decode(avatarBase64);
        _avatarIndex = -1;
      }
    });

    // Then sync from server
    final data = await ApiService().getProfile();
    if (data != null && data['success'] == true && mounted) {
      final p = data['profile'] as Map<String, dynamic>;
      setState(() {
        _childName = p['childName'] ?? _childName;
        _nameCtrl.text = _childName;
        _avatarIndex = p['avatar'] ?? _avatarIndex;
        _birthday = p['birthday'] ?? _birthday;
        _gender = p['gender'] ?? _gender;
        _totalStars = p['totalStars'] ?? _totalStars;
        final hobbies = p['hobbies'] as String? ?? '';
        _selectedHobbies = hobbies.isEmpty ? _selectedHobbies : hobbies.split(',').toSet();
        _goal = p['goal'] ?? _goal;
        final customAv = p['customAvatar'] as String? ?? '';
        if (customAv.isNotEmpty) {
          _customAvatar = base64Decode(customAv);
          _avatarIndex = -1;
        }
      });
      // Update local cache
      await prefs.setInt('profile_avatar', _avatarIndex);
      await prefs.setString('child_name', _childName);
      await prefs.setString('profile_birthday', _birthday);
      await prefs.setString('profile_gender', _gender);
      await prefs.setString('profile_hobbies', _selectedHobbies.join(','));
      await prefs.setString('profile_goal', _goal);
      await prefs.setInt('total_stars', _totalStars);
    }
  }

  void _syncToServer(Map<String, dynamic> data) {
    ApiService().updateProfile(data).then((ok) {
      debugPrint('[Profile] sync ${ok ? 'ok' : 'failed'}: $data');
    });
  }

  Future<void> _saveAvatar(int index) async {
    setState(() => _avatarIndex = index);
    await _prefs?.setInt('profile_avatar', index);
    _syncToServer({'avatar': index});
  }

  Future<void> _pickCustomAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 256,
      maxHeight: 256,
      imageQuality: 80,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final b64 = base64Encode(bytes);
    setState(() {
      _customAvatar = bytes;
      _avatarIndex = -1;
    });
    await _prefs?.setString('profile_custom_avatar', b64);
    await _prefs?.setInt('profile_avatar', -1);
    _syncToServer({'avatar': -1, 'customAvatar': b64});
  }

  Future<void> _saveName(String value) async {
    setState(() => _childName = value);
    await _prefs?.setString('child_name', value);
    _syncToServer({'childName': value});
  }

  Future<void> _saveGender(String value) async {
    setState(() => _gender = value);
    await _prefs?.setString('profile_gender', value);
    _syncToServer({'gender': value});
  }

  Future<void> _saveBirthday(String value) async {
    setState(() => _birthday = value);
    await _prefs?.setString('profile_birthday', value);
    _syncToServer({'birthday': value});
  }

  Future<void> _toggleHobby(String hobby) async {
    setState(() {
      if (_selectedHobbies.contains(hobby)) {
        _selectedHobbies.remove(hobby);
      } else {
        _selectedHobbies.add(hobby);
      }
    });
    final hobbiesStr = _selectedHobbies.join(',');
    await _prefs?.setString('profile_hobbies', hobbiesStr);
    _syncToServer({'hobbies': hobbiesStr});
  }

  Future<void> _saveGoal(String value) async {
    setState(() => _goal = value);
    await _prefs?.setString('profile_goal', value);
    _syncToServer({'goal': value});
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final initial = _birthday.isNotEmpty
        ? DateTime.tryParse(_birthday) ?? DateTime(now.year - 7)
        : DateTime(now.year - 7);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2010),
      lastDate: now,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: _kPrimary,
            onPrimary: Colors.white,
            surface: _kBg,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      final formatted =
          '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      _saveBirthday(formatted);
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('确认退出'),
        content: const Text('退出后需要重新登录哦'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _prefs?.remove('auth_token');
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
      }
    }
  }

  int get _booksCompleted => (_totalStars / 10).floor();

  // ─── Build ───

  @override
  Widget build(BuildContext context) {
    R.init(context);
    return Scaffold(
      backgroundColor: _kBg,
      body: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _DoodleBgPainter()),
          ),
          SafeArea(
            child: _prefs == null
                ? const Center(
                    child: CircularProgressIndicator(color: _kPrimary))
                : Row(
                    children: [
                      SizedBox(width: MediaQuery.of(context).size.width * 0.05),
                      SizedBox(
                        width: R.s(360),
                        child: _buildLeftColumn(),
                      ),
                      SizedBox(width: MediaQuery.of(context).size.width * 0.05),
                      Expanded(child: _buildRightColumn()),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // ─── Left Column: Avatar Selection ───

  Widget _buildLeftColumn() {
    final hasCustom = _avatarIndex == -1 && _customAvatar != null;
    final avatar = hasCustom
        ? null
        : _avatarOptions[_avatarIndex.clamp(0, _avatarOptions.length - 1)];

    return Padding(
      padding: EdgeInsets.all(R.s(16)),
      child: Column(
        children: [
          // Back arrow
          Align(
            alignment: Alignment.topLeft,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Padding(
                padding: EdgeInsets.only(bottom: R.s(4)),
                child: Icon(Icons.arrow_back_rounded,
                    size: R.s(26), color: Colors.brown.shade400),
              ),
            ),
          ),
          SizedBox(height: R.s(8)),

          // Large selected avatar
          Container(
            width: R.s(100),
            height: R.s(100),
            decoration: BoxDecoration(
              color: hasCustom
                  ? Colors.grey.shade200
                  : avatar!.color.withOpacity(0.5),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: R.s(3.5)),
              boxShadow: [
                BoxShadow(
                  color: Colors.brown.withOpacity(0.1),
                  blurRadius: R.s(8),
                  offset: Offset(0, R.s(2)),
                ),
              ],
            ),
            child: hasCustom
                ? ClipOval(
                    child: Image.memory(_customAvatar!,
                        width: R.s(100),
                        height: R.s(100),
                        fit: BoxFit.cover))
                : Center(
                    child: Text(avatar!.emoji,
                        style: TextStyle(fontSize: R.s(46)))),
          ),
          SizedBox(height: R.s(8)),

          // Name
          Text(
            _childName.isNotEmpty ? _childName : 'Name',
            style: TextStyle(
              fontSize: R.s(17),
              fontWeight: FontWeight.bold,
              color: Colors.brown.shade700,
            ),
          ),
          SizedBox(height: R.s(22)),

          // Avatar grid: 5 cols, camera overlaid on top-left 2x2
          Expanded(
            child: LayoutBuilder(
              builder: (_, constraints) {
                final gridW = constraints.maxWidth;
                final spacing = R.s(8);
                final cellSize = (gridW - spacing * 5) / 6;

                return Stack(
                  children: [
                    // Full grid of all avatars (first 4 slots are invisible, behind camera)
                    SingleChildScrollView(
                      child: Wrap(
                        spacing: spacing,
                        runSpacing: spacing,
                        children: () {
                          final widgets = <Widget>[];
                          int avatarIdx = 0;
                          final totalSlots = _avatarOptions.length + 4; // 4 empty for camera
                          // Camera occupies grid positions: row0 col0, row0 col1, row1 col0, row1 col1
                          final cameraSlots = {0, 1, 6, 7}; // positions in 6-col grid
                          for (int i = 0; i < totalSlots; i++) {
                            if (cameraSlots.contains(i)) {
                              // Empty placeholder behind camera
                              widgets.add(SizedBox(width: cellSize, height: cellSize));
                            } else {
                              if (avatarIdx < _avatarOptions.length) {
                                widgets.add(SizedBox(
                                  width: cellSize,
                                  height: cellSize,
                                  child: _buildAvatarItem(avatarIdx),
                                ));
                                avatarIdx++;
                              }
                            }
                          }
                          return widgets;
                        }(),
                      ),
                    ),
                    // Camera button overlaid on top-left 2x2
                    Positioned(
                      left: 0,
                      top: 0,
                      width: cellSize * 2 + spacing,
                      height: cellSize * 2 + spacing,
                      child: GestureDetector(
                        onTap: _pickCustomAvatar,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _avatarIndex == -1 ? _kPrimary : _kGrayBorder,
                              width: _avatarIndex == -1 ? R.s(2.5) : 1.5,
                            ),
                          ),
                          child: Center(
                            child: hasCustom
                                ? ClipOval(
                                    child: Image.memory(_customAvatar!,
                                        width: cellSize * 2 - R.s(10),
                                        height: cellSize * 2 - R.s(10),
                                        fit: BoxFit.cover))
                                : Icon(Icons.camera_alt_rounded,
                                    size: R.s(32),
                                    color: _avatarIndex == -1 ? _kPrimary : Colors.brown.shade300),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ─── Right Column: Profile Form ───

  Widget _buildRightColumn() {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(R.s(4), R.s(50), R.s(60), R.s(20)),
      child: Column(
        children: [
          // Title
          Text('~ Profile ~',
              style: TextStyle(
                  fontSize: R.s(36),
                  fontWeight: FontWeight.w900,
                  fontStyle: FontStyle.italic,
                  letterSpacing: 1.5,
                  color: _kPrimary,
                  shadows: [
                    Shadow(
                      color: _kPrimary.withOpacity(0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ])),
          SizedBox(height: R.s(16)),

          // Stats banner
          _buildStatsRow(),
          SizedBox(height: R.s(14)),

          // Name card
          // Name + Gender side by side
          Row(
            children: [
              Expanded(
                child: _buildFormCard(
                  icon: Icons.person_rounded,
                  label: 'Name',
                  child: _buildInputField(
                    child: TextField(
                      controller: _nameCtrl,
                      decoration: InputDecoration(
                        hintText: '中文名/英文名',
                        hintStyle: TextStyle(
                            color: Colors.brown.shade300, fontSize: R.s(12)),
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: R.s(10), vertical: R.s(10)),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                      style: TextStyle(
                          fontSize: R.s(12), color: Colors.brown.shade700),
                      onChanged: _saveName,
                    ),
                  ),
                ),
              ),
              SizedBox(width: R.s(20)),
              Expanded(
                child: _buildFormCard(
                  icon: Icons.wc_rounded,
                  label: 'Gender',
                  child: Row(
                    children: [
                      _buildGenderChip('Girl', '👧'),
                      SizedBox(width: R.s(6)),
                      _buildGenderChip('Boy', '👦'),
                    ],
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: R.s(10)),

          // Birthday + Goal side by side
          Row(
            children: [
              Expanded(
                child: _buildFormCard(
                  icon: Icons.cake_rounded,
                  label: 'Birthday',
                  child: GestureDetector(
                    onTap: _pickBirthday,
                    child: _buildInputField(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: R.s(10), vertical: R.s(8)),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today_rounded,
                                size: R.s(14), color: Colors.brown.shade400),
                            SizedBox(width: R.s(6)),
                            Expanded(
                              child: Text(
                                _birthday.isNotEmpty ? _birthday : '选择生日',
                                style: TextStyle(
                                  fontSize: R.s(12),
                                  color: _birthday.isNotEmpty
                                      ? Colors.brown.shade700
                                      : Colors.brown.shade300,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(width: R.s(20)),
              Expanded(
                child: _buildFormCard(
                  icon: Icons.flag_rounded,
                  label: 'Goal',
                  child: _buildInputField(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: R.s(10), vertical: R.s(8)),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _goal.isEmpty ? null : _goal,
                          hint: Text('选择坚持天数',
                              style: TextStyle(
                                  fontSize: R.s(12),
                                  color: Colors.brown.shade300)),
                          icon: Icon(Icons.keyboard_arrow_down_rounded,
                              color: Colors.brown.shade400, size: R.s(18)),
                          style: TextStyle(
                              fontSize: R.s(12), color: Colors.brown.shade700),
                          dropdownColor: _kBg,
                          borderRadius: BorderRadius.circular(R.s(12)),
                          isDense: true,
                          isExpanded: true,
                          items: _goalOptions
                              .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) _saveGoal(v);
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: R.s(10)),

          // Hobbies card
          _buildFormCard(
            icon: Icons.favorite_rounded,
            label: 'Hobbies',
            child: Wrap(
              spacing: R.s(8),
              runSpacing: R.s(8),
              children: _hobbyOptions.map((h) {
                final selected = _selectedHobbies.contains(h);
                return GestureDetector(
                  onTap: () => _toggleHobby(h),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: R.s(14), vertical: R.s(6)),
                    decoration: BoxDecoration(
                      color: selected ? _kPrimary : _kChipBg,
                      borderRadius: BorderRadius.circular(R.s(18)),
                      border: Border.all(
                        color: selected ? _kPrimary : _kGrayBorder,
                        width: 1,
                      ),
                    ),
                    child: Text(h,
                        style: TextStyle(
                          fontSize: R.s(12),
                          fontWeight:
                              selected ? FontWeight.bold : FontWeight.normal,
                          color: selected
                              ? Colors.white
                              : Colors.brown.shade500,
                        )),
                  ),
                );
              }).toList(),
            ),
          ),
          SizedBox(height: R.s(20)),

          // Logout button
          GestureDetector(
            onTap: _logout,
            child: Container(
              padding: EdgeInsets.symmetric(
                  horizontal: R.s(32), vertical: R.s(10)),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(R.s(20)),
                border: Border.all(color: Colors.red.shade200, width: 1),
              ),
              child: Text('退出登录',
                  style: TextStyle(
                      fontSize: R.s(13),
                      color: Colors.red.shade400,
                      fontWeight: FontWeight.w600)),
            ),
          ),
          SizedBox(height: R.s(16)),
        ],
      ),
    );
  }

  // ─── Reusable Widgets ───

  /// White rounded card for each form section
  Widget _buildAvatarItem(int idx) {
    if (idx < 0 || idx >= _avatarOptions.length) return const SizedBox();
    final opt = _avatarOptions[idx];
    final selected = idx == _avatarIndex;
    return GestureDetector(
      onTap: () => _saveAvatar(idx),
      child: Container(
        decoration: BoxDecoration(
          color: opt.color.withOpacity(0.5),
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? _kPrimary : opt.color.withOpacity(0.7),
            width: selected ? R.s(2.5) : 1.5,
          ),
        ),
        child: Center(
          child: Text(opt.emoji, style: TextStyle(fontSize: R.s(25))),
        ),
      ),
    );
  }

  Widget _buildGenderChip(String label, String emoji) {
    final selected = _gender == label;
    return Expanded(
      child: GestureDetector(
        onTap: () => _saveGender(label),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: R.s(8)),
          decoration: BoxDecoration(
            color: selected ? _kPrimary : _kBeigeFill,
            borderRadius: BorderRadius.circular(R.s(12)),
            border: Border.all(
              color: selected ? _kPrimary : _kGrayBorder, width: 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(emoji, style: TextStyle(fontSize: R.s(14))),
              SizedBox(width: R.s(4)),
              Text(label, style: TextStyle(
                fontSize: R.s(12),
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: selected ? Colors.white : Colors.brown.shade500,
              )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFormCard({
    required IconData icon,
    required String label,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: R.s(14), vertical: R.s(10)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(R.s(20)),
        border: Border.all(color: _kBorder.withOpacity(0.8), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD4B896).withOpacity(0.35),
            blurRadius: R.s(16),
            spreadRadius: R.s(2),
            offset: Offset(0, R.s(6)),
          ),
          BoxShadow(
            color: Colors.brown.withOpacity(0.12),
            blurRadius: R.s(6),
            offset: Offset(0, R.s(2)),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: R.s(17), color: _kPrimary),
              SizedBox(width: R.s(6)),
              Text(label,
                  style: TextStyle(
                      fontSize: R.s(14),
                      fontWeight: FontWeight.w700,
                      color: Colors.brown.shade600)),
            ],
          ),
          SizedBox(height: R.s(6)),
          child,
        ],
      ),
    );
  }

  /// Warm beige input field container
  Widget _buildInputField({required Widget child}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _kBeigeFill,
        borderRadius: BorderRadius.circular(R.s(12)),
        border: Border.all(color: _kBorder, width: 1),
      ),
      child: child,
    );
  }

  /// Stats banner
  Widget _buildStatsRow() {
    return Row(
      children: [
        _buildStatItem('🌟', '$_totalStars', '累计星星', Colors.amber),
        SizedBox(width: R.s(30)),
        _buildStatItem('🔥', '$_streakDays天', '连续学习', Colors.deepOrange),
        SizedBox(width: R.s(30)),
        _buildStatItem('📚', '$_booksCompleted', '完成绘本', Colors.teal),
      ],
    );
  }

  Widget _buildStatItem(
      String emoji, String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(vertical: R.s(6)),
        decoration: BoxDecoration(
          color: _kBeigeFill,
          borderRadius: BorderRadius.circular(R.s(16)),
          border: Border.all(color: _kBorder, width: 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(emoji, style: TextStyle(fontSize: R.s(36))),
            SizedBox(width: R.s(6)),
            Text(value,
                style: TextStyle(
                    fontSize: R.s(15),
                    fontWeight: FontWeight.bold,
                    color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildStatDivider() {
    return Container(
      width: 1,
      height: R.s(36),
      color: _kBorder.withOpacity(0.5),
    );
  }
}

// ─── Doodle Background Painter ───

class _DoodleBgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(42);
    final paint = Paint()
      ..color = const Color(0xFFD4B896).withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    // Draw doodles: each is a simple line-art icon
    final drawFns = <void Function(Canvas, Offset, double)>[
      _drawBook, _drawStar, _drawNote, _drawFlame, _drawPencil,
      _drawCamera, _drawHeart, _drawCloud, _drawPaw, _drawFlower,
    ];

    // Grid-based placement for even distribution
    const cols = 9;
    const rows = 5;
    final cellW = size.width / cols;
    final cellH = size.height / rows;

    for (int i = 0; i < cols * rows; i++) {
      final col = i % cols;
      final row = i ~/ cols;
      // Center of cell + random offset within cell
      final x = (col + 0.2 + rng.nextDouble() * 0.6) * cellW;
      final y = (row + 0.2 + rng.nextDouble() * 0.6) * cellH;
      final s = 21.0 + rng.nextDouble() * 18; // size 21-39
      final rotation = (rng.nextDouble() - 0.5) * 0.4;
      final fn = drawFns[i % drawFns.length];

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(rotation);
      fn(canvas, Offset.zero, s);
      canvas.restore();
    }
  }

  Paint get _p => Paint()
    ..color = const Color(0xFFD4B896).withOpacity(0.5)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..strokeCap = StrokeCap.round;

  // Open book
  void _drawBook(Canvas c, Offset o, double s) {
    final p = _p;
    // Left page
    c.drawLine(Offset(o.dx, o.dy - s * 0.3), Offset(o.dx - s * 0.4, o.dy - s * 0.2), p);
    c.drawLine(Offset(o.dx - s * 0.4, o.dy - s * 0.2), Offset(o.dx - s * 0.4, o.dy + s * 0.3), p);
    c.drawLine(Offset(o.dx - s * 0.4, o.dy + s * 0.3), Offset(o.dx, o.dy + s * 0.2), p);
    // Right page
    c.drawLine(Offset(o.dx, o.dy - s * 0.3), Offset(o.dx + s * 0.4, o.dy - s * 0.2), p);
    c.drawLine(Offset(o.dx + s * 0.4, o.dy - s * 0.2), Offset(o.dx + s * 0.4, o.dy + s * 0.3), p);
    c.drawLine(Offset(o.dx + s * 0.4, o.dy + s * 0.3), Offset(o.dx, o.dy + s * 0.2), p);
    // Spine
    c.drawLine(Offset(o.dx, o.dy - s * 0.3), Offset(o.dx, o.dy + s * 0.2), p);
  }

  // 5-point star outline
  void _drawStar(Canvas c, Offset o, double s) {
    final p = _p;
    final r = s * 0.4;
    final ir = r * 0.4;
    final path = Path();
    for (int i = 0; i < 10; i++) {
      final a = (i * pi / 5) - pi / 2;
      final rad = i.isEven ? r : ir;
      final pt = Offset(o.dx + cos(a) * rad, o.dy + sin(a) * rad);
      if (i == 0) path.moveTo(pt.dx, pt.dy); else path.lineTo(pt.dx, pt.dy);
    }
    path.close();
    c.drawPath(path, p);
  }

  // Music note
  void _drawNote(Canvas c, Offset o, double s) {
    final p = _p;
    // Stem
    c.drawLine(Offset(o.dx, o.dy - s * 0.35), Offset(o.dx, o.dy + s * 0.2), p);
    // Flag
    c.drawLine(Offset(o.dx, o.dy - s * 0.35), Offset(o.dx + s * 0.2, o.dy - s * 0.15), p);
    // Note head
    c.drawOval(Rect.fromCenter(
      center: Offset(o.dx - s * 0.06, o.dy + s * 0.25), width: s * 0.22, height: s * 0.15), p);
  }

  // Flame
  void _drawFlame(Canvas c, Offset o, double s) {
    final p = _p;
    final path = Path()
      ..moveTo(o.dx, o.dy - s * 0.4)
      ..quadraticBezierTo(o.dx + s * 0.3, o.dy - s * 0.1, o.dx + s * 0.15, o.dy + s * 0.3)
      ..quadraticBezierTo(o.dx, o.dy + s * 0.15, o.dx, o.dy + s * 0.3)
      ..quadraticBezierTo(o.dx, o.dy + s * 0.15, o.dx - s * 0.15, o.dy + s * 0.3)
      ..quadraticBezierTo(o.dx - s * 0.3, o.dy - s * 0.1, o.dx, o.dy - s * 0.4);
    c.drawPath(path, p);
  }

  // Pencil
  void _drawPencil(Canvas c, Offset o, double s) {
    final p = _p;
    // Body
    c.drawLine(Offset(o.dx - s * 0.3, o.dy + s * 0.3), Offset(o.dx + s * 0.2, o.dy - s * 0.2), p);
    c.drawLine(Offset(o.dx - s * 0.25, o.dy + s * 0.22), Offset(o.dx + s * 0.25, o.dy - s * 0.28), p);
    // Tip
    c.drawLine(Offset(o.dx - s * 0.3, o.dy + s * 0.3), Offset(o.dx - s * 0.38, o.dy + s * 0.38), p);
    // Eraser end
    c.drawLine(Offset(o.dx + s * 0.2, o.dy - s * 0.2), Offset(o.dx + s * 0.25, o.dy - s * 0.28), p);
  }

  // Camera
  void _drawCamera(Canvas c, Offset o, double s) {
    final p = _p;
    // Body
    c.drawRRect(RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(o.dx, o.dy + s * 0.05), width: s * 0.7, height: s * 0.45),
      Radius.circular(s * 0.06)), p);
    // Lens
    c.drawCircle(Offset(o.dx, o.dy + s * 0.05), s * 0.13, p);
    // Top bump
    c.drawLine(Offset(o.dx - s * 0.1, o.dy - s * 0.18), Offset(o.dx + s * 0.1, o.dy - s * 0.18), p);
    c.drawLine(Offset(o.dx + s * 0.1, o.dy - s * 0.18), Offset(o.dx + s * 0.15, o.dy - s * 0.1), p);
    c.drawLine(Offset(o.dx - s * 0.1, o.dy - s * 0.18), Offset(o.dx - s * 0.15, o.dy - s * 0.1), p);
  }

  // Heart
  void _drawHeart(Canvas c, Offset o, double s) {
    final p = _p;
    final path = Path()
      ..moveTo(o.dx, o.dy + s * 0.3)
      ..cubicTo(o.dx - s * 0.4, o.dy, o.dx - s * 0.4, o.dy - s * 0.3, o.dx, o.dy - s * 0.1)
      ..cubicTo(o.dx + s * 0.4, o.dy - s * 0.3, o.dx + s * 0.4, o.dy, o.dx, o.dy + s * 0.3);
    c.drawPath(path, p);
  }

  // Cloud
  void _drawCloud(Canvas c, Offset o, double s) {
    final p = _p;
    c.drawOval(Rect.fromCenter(center: Offset(o.dx - s * 0.15, o.dy), width: s * 0.35, height: s * 0.25), p);
    c.drawOval(Rect.fromCenter(center: Offset(o.dx + s * 0.1, o.dy - s * 0.05), width: s * 0.4, height: s * 0.3), p);
    c.drawOval(Rect.fromCenter(center: Offset(o.dx + s * 0.3, o.dy + s * 0.02), width: s * 0.3, height: s * 0.22), p);
  }

  // Paw print
  void _drawPaw(Canvas c, Offset o, double s) {
    final p = _p;
    // Main pad
    c.drawOval(Rect.fromCenter(center: Offset(o.dx, o.dy + s * 0.1), width: s * 0.3, height: s * 0.25), p);
    // Toes
    c.drawCircle(Offset(o.dx - s * 0.15, o.dy - s * 0.12), s * 0.08, p);
    c.drawCircle(Offset(o.dx + s * 0.15, o.dy - s * 0.12), s * 0.08, p);
    c.drawCircle(Offset(o.dx - s * 0.06, o.dy - s * 0.22), s * 0.07, p);
    c.drawCircle(Offset(o.dx + s * 0.06, o.dy - s * 0.22), s * 0.07, p);
  }

  // Simple flower
  void _drawFlower(Canvas c, Offset o, double s) {
    final p = _p;
    // Center
    c.drawCircle(o, s * 0.1, p);
    // Petals
    for (int i = 0; i < 5; i++) {
      final a = i * 2 * pi / 5 - pi / 2;
      final px = o.dx + cos(a) * s * 0.22;
      final py = o.dy + sin(a) * s * 0.22;
      c.drawCircle(Offset(px, py), s * 0.1, p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
