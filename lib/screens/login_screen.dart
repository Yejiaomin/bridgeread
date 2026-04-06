import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const _kOrange = Color(0xFFFF8C42);
const _kCream = Color(0xFFFFF8F0);

// TODO: Change to production URL when deployed
const _kApiBase = 'http://localhost:3000/api';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLogin = true; // true = login, false = register
  bool _isLoading = false;
  bool _codeSent = false;
  String? _error;

  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();

  Future<void> _sendCode() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.length != 11) {
      setState(() => _error = '请输入11位手机号');
      return;
    }
    setState(() { _isLoading = true; _error = null; });
    try {
      final res = await http.post(
        Uri.parse('$_kApiBase/auth/send-code'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone}),
      );
      final data = jsonDecode(res.body);
      if (res.statusCode == 200) {
        setState(() => _codeSent = true);
      } else {
        setState(() => _error = data['error'] ?? '发送失败');
      }
    } catch (e) {
      setState(() => _error = '网络错误，请检查连接');
    }
    setState(() => _isLoading = false);
  }

  Future<void> _register() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final res = await http.post(
        Uri.parse('$_kApiBase/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone': _phoneCtrl.text.trim(),
          'code': _codeCtrl.text.trim(),
          'password': _passwordCtrl.text.trim(),
          'childName': _nameCtrl.text.trim(),
        }),
      );
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['success'] == true) {
        await _saveToken(data['token'], data['user']);
        if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/home', (r) => false);
      } else {
        setState(() => _error = data['error'] ?? '注册失败');
      }
    } catch (e) {
      setState(() => _error = '网络错误，请检查连接');
    }
    setState(() => _isLoading = false);
  }

  Future<void> _login() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final res = await http.post(
        Uri.parse('$_kApiBase/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone': _phoneCtrl.text.trim(),
          'password': _passwordCtrl.text.trim(),
        }),
      );
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['success'] == true) {
        await _saveToken(data['token'], data['user']);
        if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/home', (r) => false);
      } else {
        setState(() => _error = data['error'] ?? '登录失败');
      }
    } catch (e) {
      setState(() => _error = '网络错误，请检查连接');
    }
    setState(() => _isLoading = false);
  }

  Future<void> _saveToken(String token, Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
    await prefs.setString('child_name', user['childName'] ?? '');
    await prefs.setInt('user_id', user['id'] ?? 0);
    if (user['bookStartDate'] != null) {
      await prefs.setString('book_start_date', user['bookStartDate']);
    }
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kCream,
      body: Center(
        child: SizedBox(
          width: MediaQuery.of(context).size.width / 3,
          child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Logo
              Image.asset('assets/pet/eggy_transparent_bg.webp', width: 180, height: 180),
              const SizedBox(height: 12),
              const Text('BridgeRead', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: _kOrange)),
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

              // Register: code + name
              if (!_isLogin) ...[
                Row(
                  children: [
                    Expanded(child: _inputField(_codeCtrl, '验证码（测试用123456）', TextInputType.number, Icons.sms)),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _isLoading || _codeSent ? null : _sendCode,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kOrange,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(_codeSent ? '已发送' : '发送', style: const TextStyle(fontSize: 14)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _inputField(_nameCtrl, '孩子的名字', TextInputType.text, Icons.child_care),
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
