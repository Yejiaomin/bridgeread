const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { query, queryOne, run } = require('../db');

const router = express.Router();
const JWT_SECRET = process.env.JWT_SECRET || 'bridgeread_secret_change_in_production';
const TOKEN_EXPIRY = '90d';

// ── Send SMS code ───────────────────────────────────────────────────────────
router.post('/send-code', (req, res) => {
  const { phone } = req.body;
  if (!phone || !/^1\d{10}$/.test(phone)) {
    return res.status(400).json({ error: '请输入正确的手机号' });
  }

  const recent = queryOne(
    "SELECT id FROM sms_codes WHERE phone = ? AND created_at > datetime('now', '-1 minute')", [phone]
  );
  if (recent) return res.status(429).json({ error: '发送太频繁，请 1 分钟后再试' });

  const code = String(Math.floor(100000 + Math.random() * 900000));
  const expiresAt = new Date(Date.now() + 5 * 60 * 1000).toISOString();

  run('INSERT INTO sms_codes (phone, code, expires_at) VALUES (?, ?, ?)', [phone, code, expiresAt]);

  // DEV MODE: accept 123456 as universal code, skip real SMS
  // TODO: Send SMS via Aliyun when ready for production
  const DEV_MODE = process.env.NODE_ENV !== 'production';
  if (DEV_MODE) {
    console.log(`[SMS-DEV] ${phone}: ${code} (use 123456 to bypass)`);
  }

  res.json({ success: true, message: '验证码已发送' });
});

// ── Verify code helper ──────────────────────────────────────────────────────
function verifyCode(phone, code) {
  // DEV MODE: 123456 always works
  const DEV_MODE = process.env.NODE_ENV !== 'production';
  if (DEV_MODE && code === '123456') return true;

  const record = queryOne(
    "SELECT id FROM sms_codes WHERE phone = ? AND code = ? AND used = 0 AND expires_at > datetime('now') ORDER BY id DESC LIMIT 1",
    [phone, code]
  );
  if (!record) return false;
  run('UPDATE sms_codes SET used = 1 WHERE id = ?', [record.id]);
  return true;
}

// ── Register ────────────────────────────────────────────────────────────────
router.post('/register', (req, res) => {
  const { phone, code, password, childName } = req.body;

  if (!phone || !code || !password || !childName) {
    return res.status(400).json({ error: '请填写所有字段' });
  }
  if (!/^1\d{10}$/.test(phone)) return res.status(400).json({ error: '请输入正确的手机号' });
  if (!/^\d{8}$/.test(password)) return res.status(400).json({ error: '密码必须是 8 位数字' });

  if (!verifyCode(phone, code)) return res.status(400).json({ error: '验证码错误或已过期' });

  const existing = queryOne('SELECT id FROM users WHERE phone = ?', [phone]);
  if (existing) return res.status(400).json({ error: '该手机号已注册' });

  const hash = bcrypt.hashSync(password, 10);
  run('INSERT INTO users (phone, password_hash, child_name) VALUES (?, ?, ?)', [phone, hash, childName]);

  // Get the newly created user by phone (sql.js last_insert_rowid is unreliable)
  const newUser = queryOne('SELECT id FROM users WHERE phone = ?', [phone]);
  const userId = newUser.id;

  const token = jwt.sign({ userId }, JWT_SECRET, { expiresIn: TOKEN_EXPIRY });

  res.json({ success: true, token, user: { id: userId, phone, childName, totalStars: 0 } });
});

// ── Login ───────────────────────────────────────────────────────────────────
router.post('/login', (req, res) => {
  const { phone, password } = req.body;
  if (!phone || !password) return res.status(400).json({ error: '请输入手机号和密码' });

  const user = queryOne('SELECT * FROM users WHERE phone = ?', [phone]);
  if (!user) return res.status(400).json({ error: '手机号未注册' });
  if (!bcrypt.compareSync(password, user.password_hash)) return res.status(400).json({ error: '密码错误' });

  if (user.lock_status === 1) {
    return res.status(403).json({ error: '账户已锁定', unlockCount: user.unlock_count, maxUnlocks: 10 });
  }

  const token = jwt.sign({ userId: user.id }, JWT_SECRET, { expiresIn: TOKEN_EXPIRY });

  res.json({
    success: true, token,
    user: {
      id: user.id, phone: user.phone, childName: user.child_name,
      totalStars: user.total_stars, bookStartDate: user.book_start_date,
      startSeriesIndex: user.start_series_index, lockStatus: user.lock_status,
      unlockCount: user.unlock_count,
    },
  });
});

// ── Reset password ──────────────────────────────────────────────────────────
router.post('/reset-password', (req, res) => {
  const { phone, code, newPassword } = req.body;
  if (!phone || !code || !newPassword) return res.status(400).json({ error: '请填写所有字段' });
  if (!/^\d{8}$/.test(newPassword)) return res.status(400).json({ error: '密码必须是 8 位数字' });
  if (!verifyCode(phone, code)) return res.status(400).json({ error: '验证码错误或已过期' });

  const user = queryOne('SELECT id FROM users WHERE phone = ?', [phone]);
  if (!user) return res.status(400).json({ error: '手机号未注册' });

  run('UPDATE users SET password_hash = ? WHERE id = ?', [bcrypt.hashSync(newPassword, 10), user.id]);
  res.json({ success: true, message: '密码重设成功' });
});

// ── Unlock account ──────────────────────────────────────────────────────────
router.post('/unlock', (req, res) => {
  const userId = req.userId;
  const user = queryOne('SELECT * FROM users WHERE id = ?', [userId]);
  if (!user || user.lock_status !== 1) return res.status(400).json({ error: '账户未锁定' });
  if (user.unlock_count >= 10) return res.status(403).json({ error: '解锁次数已用完，请联系管理员' });

  run('UPDATE users SET lock_status = 0, unlock_count = unlock_count + 1 WHERE id = ?', [userId]);
  res.json({ success: true, unlockCount: user.unlock_count + 1, remaining: 9 - user.unlock_count });
});

module.exports = router;
module.exports.JWT_SECRET = JWT_SECRET;
