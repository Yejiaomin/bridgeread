const express = require('express');
const { queryOne, run } = require('../db');
const { _internals: { computeStreak } } = require('./progress');

const router = express.Router();

// ── Get profile ────────────────────────────────────────────────────────────
router.get('/', (req, res) => {
  const user = queryOne(
    `SELECT phone, child_name, profile_avatar, profile_birthday, profile_gender,
            profile_hobbies, profile_goal, profile_custom_avatar, total_stars
     FROM users WHERE id = ?`, [req.userId]
  );
  if (!user) return res.status(404).json({ error: '用户不存在' });

  // 完成绘本 = reader 模块 done=1 的天数。UNIQUE(user_id,date,module) 保证 1 行 = 1 本。
  const books = queryOne(
    `SELECT COUNT(*) AS n FROM daily_progress
     WHERE user_id = ? AND module = 'reader' AND done = 1`,
    [req.userId]
  );

  res.json({
    success: true,
    profile: {
      phone: user.phone,
      childName: user.child_name,
      avatar: user.profile_avatar ?? 0,
      birthday: user.profile_birthday ?? '',
      gender: user.profile_gender ?? '',
      hobbies: user.profile_hobbies ?? '',
      goal: user.profile_goal ?? '',
      customAvatar: user.profile_custom_avatar ?? '',
      totalStars: user.total_stars ?? 0,
      booksCompleted: books?.n ?? 0,
      streakDays: computeStreak(req.userId),
    },
  });
});

// ── Update profile ─────────────────────────────────────────────────────────
router.put('/', (req, res) => {
  const { childName, avatar, birthday, gender, hobbies, goal, customAvatar } = req.body;
  const sets = [], params = [];

  if (childName !== undefined) { sets.push('child_name = ?'); params.push(childName); }
  if (avatar !== undefined) { sets.push('profile_avatar = ?'); params.push(avatar); }
  if (birthday !== undefined) { sets.push('profile_birthday = ?'); params.push(birthday); }
  if (gender !== undefined) { sets.push('profile_gender = ?'); params.push(gender); }
  if (hobbies !== undefined) { sets.push('profile_hobbies = ?'); params.push(hobbies); }
  if (goal !== undefined) { sets.push('profile_goal = ?'); params.push(goal); }
  if (customAvatar !== undefined) { sets.push('profile_custom_avatar = ?'); params.push(customAvatar); }

  if (sets.length === 0) return res.status(400).json({ error: '没有要更新的字段' });

  params.push(req.userId);
  run(`UPDATE users SET ${sets.join(', ')} WHERE id = ?`, params);

  res.json({ success: true });
});

module.exports = router;
