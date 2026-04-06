const express = require('express');
const { query, queryOne, run, debugUser } = require('../db');

const router = express.Router();

// ── Get progress ────────────────────────────────────────────────────────────
router.get('/', (req, res) => {
  const userId = req.userId;

  const user = queryOne(
    'SELECT total_stars, book_start_date, start_series_index, lock_status, unlock_count, last_active_date FROM users WHERE id = ?',
    [userId]
  );

  const progress = query(
    'SELECT date, module, done, stars, lesson_id FROM daily_progress WHERE user_id = ? ORDER BY date',
    [userId]
  );

  const owed = queryOne(
    'SELECT COUNT(*) as count FROM daily_progress WHERE user_id = ? AND done = 0',
    [userId]
  );

  res.json({ success: true, user, progress, totalOwed: owed.count });
});

// ── Sync one module ─────────────────────────────────────────────────────────
router.post('/', (req, res) => {
  const userId = req.userId;
  const { date, module, done, stars, lessonId } = req.body;

  if (!date || !module) return res.status(400).json({ error: 'date and module required' });

  run(`INSERT INTO daily_progress (user_id, date, module, done, stars, lesson_id)
       VALUES (?, ?, ?, ?, ?, ?)
       ON CONFLICT(user_id, date, module) DO UPDATE SET done=?, stars=?, lesson_id=?`,
    [userId, date, module, done ? 1 : 0, stars || 0, lessonId || null, done ? 1 : 0, stars || 0, lessonId || null]);

  debugUser(userId);
  if (done) {
    run('UPDATE users SET last_active_date = ? WHERE id = ?', [date, userId]);
    if (stars > 0) run('UPDATE users SET total_stars = total_stars + ? WHERE id = ?', [stars, userId]);
  }

  checkAndLock(userId);

  const user = queryOne('SELECT total_stars, lock_status FROM users WHERE id = ?', [userId]);
  const owed = queryOne('SELECT COUNT(*) as count FROM daily_progress WHERE user_id = ? AND done = 0', [userId]);

  res.json({ success: true, totalStars: user.total_stars, totalOwed: owed.count, lockStatus: user.lock_status });
});

// ── Batch sync ──────────────────────────────────────────────────────────────
router.post('/batch', (req, res) => {
  const userId = req.userId;
  const { items } = req.body;
  if (!Array.isArray(items)) return res.status(400).json({ error: 'items array required' });

  let totalNewStars = 0, latestDate = '';
  for (const item of items) {
    run(`INSERT INTO daily_progress (user_id, date, module, done, stars, lesson_id)
         VALUES (?, ?, ?, ?, ?, ?)
         ON CONFLICT(user_id, date, module) DO UPDATE SET done=?, stars=?, lesson_id=?`,
      [userId, item.date, item.module, item.done ? 1 : 0, item.stars || 0, item.lessonId || null,
       item.done ? 1 : 0, item.stars || 0, item.lessonId || null]);
    if (item.done && item.stars) totalNewStars += item.stars;
    if (item.date > latestDate) latestDate = item.date;
  }

  if (totalNewStars > 0) run('UPDATE users SET total_stars = total_stars + ? WHERE id = ?', [totalNewStars, userId]);
  if (latestDate) run('UPDATE users SET last_active_date = ? WHERE id = ?', [latestDate, userId]);

  checkAndLock(userId);

  const user = queryOne('SELECT total_stars, lock_status FROM users WHERE id = ?', [userId]);
  const owed = queryOne('SELECT COUNT(*) as count FROM daily_progress WHERE user_id = ? AND done = 0', [userId]);

  res.json({ success: true, totalStars: user.total_stars, totalOwed: owed.count, lockStatus: user.lock_status });
});

// ── Setup (book start date, series index) ───────────────────────────────────
router.post('/setup', (req, res) => {
  const { bookStartDate, startSeriesIndex } = req.body;
  const sets = [], params = [];
  if (bookStartDate) { sets.push('book_start_date = ?'); params.push(bookStartDate); }
  if (startSeriesIndex !== undefined) { sets.push('start_series_index = ?'); params.push(startSeriesIndex); }
  if (sets.length) { params.push(req.userId); run(`UPDATE users SET ${sets.join(', ')} WHERE id = ?`, params); }
  res.json({ success: true });
});

// ── Lock check ──────────────────────────────────────────────────────────────
function checkAndLock(userId) {
  const owed = queryOne('SELECT COUNT(*) as count FROM daily_progress WHERE user_id = ? AND done = 0', [userId]);
  if (owed && owed.count >= 15) { run('UPDATE users SET lock_status = 1 WHERE id = ? AND lock_status = 0', [userId]); return; }

  const user = queryOne('SELECT last_active_date FROM users WHERE id = ?', [userId]);
  if (user && user.last_active_date) {
    const diff = Math.floor((Date.now() - new Date(user.last_active_date)) / 86400000);
    if (diff >= 3) run('UPDATE users SET lock_status = 1 WHERE id = ? AND lock_status = 0', [userId]);
  }
}

module.exports = router;
