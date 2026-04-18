import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/progress_service.dart';
import '../services/week_service.dart' show chinaTime;
import '../services/analytics_service.dart';
import '../utils/responsive_utils.dart';

const _kOrange = Color(0xFFFF8C42);
const _kCream = Color(0xFFFFF8F0);

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLogin = true; // true = login, false = register
  bool _isLoading = false;
  String? _error;

  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();

  final _api = ApiService();

  Future<void> _register() async {
    final phone = _phoneCtrl.text.trim();
    final password = _passwordCtrl.text.trim();
    final childName = _nameCtrl.text.trim();

    if (phone.length != 11) {
      setState(() => _error = '请输入11位手机号');
      return;
    }
    if (password.length != 8) {
      setState(() => _error = '请输入8位数字密码');
      return;
    }
    if (childName.isEmpty) {
      setState(() => _error = '请输入孩子的名字');
      return;
    }

    setState(() { _isLoading = true; _error = null; });

    final res = await _api.register(
      phone: phone,
      password: password,
      childName: childName,
    );

    if (res == null || res['error'] != null) {
      setState(() { _isLoading = false; _error = res?['error'] ?? '注册失败'; });
      return;
    }

    // Registration succeeded, token already saved by ApiService
    final prefs = await SharedPreferences.getInstance();

    // New user always starts from today, book 1
    final now = chinaTime();
    final today = DateTime(now.year, now.month, now.day);
    final dateStr = _formatDate(today);
    await prefs.setString('book_start_date', dateStr);

    await _api.setupProgress(
      bookStartDate: dateStr,
      startSeriesIndex: 0,
    );

    await prefs.setBool('assessment_done', true);
    await prefs.setInt('start_series_index', 0);

    // Sync from server to ensure local state matches server
    await ProgressService.syncFromServer();

    AnalyticsService.logEvent('register', {'phone': phone, 'child_name': childName});
    setState(() => _isLoading = false);
    if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/ranking', (r) => false);
  }

  Future<void> _login() async {
    final phone = _phoneCtrl.text.trim();
    final password = _passwordCtrl.text.trim();

    if (phone.length != 11) {
      setState(() => _error = '请输入11位手机号');
      return;
    }

    setState(() { _isLoading = true; _error = null; });

    final res = await _api.login(phone: phone, password: password);

    if (res == null || res['error'] != null) {
      setState(() { _isLoading = false; _error = res?['error'] ?? '登录失败'; });
      return;
    }

    // Login succeeded, token already saved by ApiService
    final prefs = await SharedPreferences.getInstance();
    final user = res['user'] as Map<String, dynamic>;

    // Cache user data locally
    await prefs.setString('child_name', user['childName'] ?? '');
    if (user['bookStartDate'] != null) {
      await prefs.setString('book_start_date', user['bookStartDate']);
    }
    if (user['startSeriesIndex'] != null) {
      await prefs.setInt('start_series_index', user['startSeriesIndex']);
    }
    await prefs.setInt('total_stars', user['totalStars'] ?? 0);
    await prefs.setBool('assessment_done', true);

    // Sync full progress from server (server is source of truth)
    await ProgressService.syncFromServer();

    AnalyticsService.logEvent('login', {'phone': phone});
    setState(() => _isLoading = false);
    if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/home', (r) => false);
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    R.init(context);
    final w = MediaQuery.of(context).size.width;
    final formWidth = R.isMobile ? w - 48 : w / 3;
    final logoSize = R.isMobile ? 120.0 : 180.0;
    final titleSize = R.isMobile ? 22.0 : 28.0;

    return Scaffold(
      backgroundColor: _kCream,
      body: Center(
        child: SizedBox(
          width: formWidth,
          child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Logo
              Image.asset('assets/pet/eggy_transparent_bg.webp', width: logoSize, height: logoSize),
              const SizedBox(height: 12),
              Text('BridgeRead', style: TextStyle(fontSize: titleSize, fontWeight: FontWeight.w900, color: _kOrange)),
              const SizedBox(height: 32),

              // Toggle login/register
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _tabButton('登录', _isLogin, () => setState(() { _isLogin = true; _error = null; })),
                  const SizedBox(width: 16),
                  _tabButton('注册', !_isLogin, () => setState(() { _isLogin = false; _error = null; })),
                ],
              ),
              const SizedBox(height: 24),

              // Phone
              _inputField(_phoneCtrl, '手机号', TextInputType.phone, Icons.phone),
              const SizedBox(height: 12),

              // Register fields
              if (!_isLogin) ...[
                _inputField(_nameCtrl, '中文名/英文名', TextInputType.text, Icons.child_care),
                const SizedBox(height: 12),
              ],

              // Password
              _inputField(_passwordCtrl, '密码（8位数字）', TextInputType.number, Icons.lock, obscure: true),
              const SizedBox(height: 8),

              // Error
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 14)),
                ),

              const SizedBox(height: 16),

              // Submit button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : (_isLogin ? _login : _register),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kOrange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                  child: _isLoading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(_isLogin ? '登录' : '注册', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ),
              ),

              const SizedBox(height: 12),

              // Forgot password
              if (_isLogin)
                TextButton(
                  onPressed: () {
                    // TODO: navigate to reset password page
                  },
                  child: const Text('忘记密码？', style: TextStyle(color: _kOrange, fontSize: 14)),
                ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';



  Widget _tabButton(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        decoration: BoxDecoration(
          color: active ? _kOrange : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _kOrange),
        ),
        child: Text(label, style: TextStyle(
          color: active ? Colors.white : _kOrange,
          fontSize: 16, fontWeight: FontWeight.w700,
        )),
      ),
    );
  }

  Widget _inputField(TextEditingController ctrl, String hint, TextInputType type, IconData icon, {bool obscure = false}) {
    return TextField(
      controller: ctrl,
      keyboardType: type,
      obscureText: obscure,
      maxLength: type == TextInputType.phone ? 11 : (obscure ? 8 : null),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: _kOrange),
        counterText: '',
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kOrange, width: 1.5),
        ),
      ),
    );
  }
}
