const express = require('express');
const { query, queryOne, run, runNoSave, saveDb, debugUser } = require('../db');
const { chinaToday, parseDate, fmtDate } = require('../lib/china_time');

const router = express.Router();

const MODULES = ['recap', 'reader', 'quiz', 'listen', 'phonics', 'recording'];
const REQUIRED_MODULES = ['recap', 'reader', 'quiz', 'listen']; // count toward debt

// ── Clean up old module records not in current MODULES list ────────────────
function cleanOldModules(userId) {
  const placeholders = MODULES.map(() => '?').join(',');
  run(`DELETE FROM daily_progress WHERE user_id = ? AND module NOT IN (${placeholders})`,
    [userId, ...MODULES]);
}

// ── Compute consecutive-day streak (for user feedback / UI) ────────────────
// Counts back from today over distinct dates with at least one done module.
// If today has no completion yet, starts counting from yesterday.
function computeStreak(userId) {
  const todayStr = fmtDate(chinaToday());
  const activeDays = query(
    `SELECT DISTINCT date FROM daily_progress WHERE user_id = ? AND done = 1 ORDER BY date DESC`,
    [userId]
  ).map(r => r.date);

  let streak = 0;
  const checkDate = chinaToday();
  if (!activeDays.includes(todayStr)) {
    checkDate.setUTCDate(checkDate.getUTCDate() - 1);
  }
  while (activeDays.includes(fmtDate(checkDate))) {
    streak++;
    checkDate.setUTCDate(checkDate.getUTCDate() - 1);
  }
  return streak;
}

// ── Backfill missing days with done=0 records ──────────────────────────────
function backfillDebt(userId) {
  const user = queryOne('SELECT book_start_date FROM users WHERE id = ?', [userId]);
  if (!user || !user.book_start_date) return;

  const start = parseDate(user.book_start_date);
  const today = chinaToday();

  let inserted = 0;
  for (let d = new Date(start); d <= today; d.setUTCDate(d.getUTCDate() + 1)) {
    const dow = d.getUTCDay(); // 0=Sun, 6=Sat
    if (dow === 0 || dow === 6) continue; // skip weekends

    const dateStr = fmtDate(d);
    for (const mod of REQUIRED_MODULES) {
      // Insert done=0 only if no record exists yet
      runNoSave(`INSERT OR IGNORE INTO daily_progress (user_id, date, module, done, stars)
           VALUES (?, ?, ?, 0, 0)`, [userId, dateStr, mod]);
      inserted++;
    }
  }
  if (inserted > 0) saveDb();
}

// ── Get progress ────────────────────────────────────────────────────────────
router.get('/', (req, res) => {
  const userId = req.userId;

  // Clean old modules (e.g. after module rename) then backfill
  cleanOldModules(userId);
  backfillDebt(userId);

  const user = queryOne(
    'SELECT total_stars, book_start_date, start_series_index, lock_status, unlock_count, last_active_date, listen_date, listen_seconds, app_start_date FROM users WHERE id = ?',
    [userId]
  );

  const progress = query(
    'SELECT date, module, done, stars, lesson_id FROM daily_progress WHERE user_id = ? ORDER BY date',
    [userId]
  );

  // Today in China time
  const todayStr = fmtDate(chinaToday());

  const owed = queryOne(
    'SELECT COUNT(*) as count FROM daily_progress WHERE user_id = ? AND done = 0 AND date < ?',
    [userId, todayStr]
  );

  const todayOwed = queryOne(
    'SELECT COUNT(*) as count FROM daily_progress WHERE user_id = ? AND done = 0 AND date = ?',
    [userId, todayStr]
  );

  // Debt per date (for calendar display) — exclude today
  const debtByDate = query(
    `SELECT date, COUNT(*) as debt FROM daily_progress
     WHERE user_id = ? AND done = 0 AND date < ? GROUP BY date ORDER BY date`,
    [userId, todayStr]
  );

  const streak = computeStreak(userId);
  res.json({ success: true, user, progress, totalOwed: owed.count, todayOwed: todayOwed.count, debtByDate, streak });
});

// ── Sync one module ─────────────────────────────────────────────────────────
router.post('/', (req, res) => {
  const userId = req.userId;
  const { date, module, done, stars, lessonId, listenSeconds } = req.body;

  if (!date || !module) return res.status(400).json({ error: 'date and module required' });

  // Save listening time if provided
  if (listenSeconds != null) {
    run('UPDATE users SET listen_date = ?, listen_seconds = ? WHERE id = ?',
      [date, listenSeconds, userId]);
  }

  // Telemetry-only update (e.g. periodic listen-time save) — skip daily_progress
  if (done === undefined || done === null) {
    const user = queryOne('SELECT total_stars, lock_status FROM users WHERE id = ?', [userId]);
    const owed = queryOne('SELECT COUNT(*) as count FROM daily_progress WHERE user_id = ? AND done = 0', [userId]);
    return res.json({ success: true, totalStars: user.total_stars, totalOwed: owed.count, lockStatus: user.lock_status, streak: computeStreak(userId) });
  }

  // Check if already completed (to avoid double-counting stars + protect against downgrade)
  const existing = queryOne(
    'SELECT done, stars FROM daily_progress WHERE user_id = ? AND date = ? AND module = ?',
    [userId, date, module]
  );
  const wasAlreadyDone = existing && existing.done === 1;

  // Once a module is done, never downgrade it to undone (defense-in-depth
  // even though clients now omit `done` for telemetry-only updates)
  const finalDone = (wasAlreadyDone || done) ? 1 : 0;
  const finalStars = Math.max(existing?.stars || 0, stars || 0);

  run(`INSERT INTO daily_progress (user_id, date, module, done, stars, lesson_id)
       VALUES (?, ?, ?, ?, ?, ?)
       ON CONFLICT(user_id, date, module) DO UPDATE SET done=?, stars=?, lesson_id=?`,
    [userId, date, module, finalDone, finalStars, lessonId || null, finalDone, finalStars, lessonId || null]);

  debugUser(userId);
  if (done && !wasAlreadyDone) {
    run('UPDATE users SET last_active_date = ? WHERE id = ?', [date, userId]);
    if (stars > 0) run('UPDATE users SET total_stars = total_stars + ? WHERE id = ?', [stars, userId]);
  }

  checkAndLock(userId);

  const user = queryOne('SELECT total_stars, lock_status FROM users WHERE id = ?', [userId]);
  const owed = queryOne('SELECT COUNT(*) as count FROM daily_progress WHERE user_id = ? AND done = 0', [userId]);

  res.json({ success: true, totalStars: user.total_stars, totalOwed: owed.count, lockStatus: user.lock_status, streak: computeStreak(userId) });
});

// ── Batch sync ──────────────────────────────────────────────────────────────
router.post('/batch', (req, res) => {
  const userId = req.userId;
  const { items } = req.body;
  if (!Array.isArray(items)) return res.status(400).json({ error: 'items array required' });

  let totalNewStars = 0, latestDate = '';
  for (const item of items) {
    // Check if already completed (to avoid double-counting stars + protect against downgrade)
    const existing = queryOne(
      'SELECT done, stars FROM daily_progress WHERE user_id = ? AND date = ? AND module = ?',
      [userId, item.date, item.module]
    );
    const wasAlreadyDone = existing && existing.done === 1;
    const finalDone = (wasAlreadyDone || item.done) ? 1 : 0;
    const finalStars = Math.max(existing?.stars || 0, item.stars || 0);

    run(`INSERT INTO daily_progress (user_id, date, module, done, stars, lesson_id)
         VALUES (?, ?, ?, ?, ?, ?)
         ON CONFLICT(user_id, date, module) DO UPDATE SET done=?, stars=?, lesson_id=?`,
      [userId, item.date, item.module, finalDone, finalStars, item.lessonId || null,
       finalDone, finalStars, item.lessonId || null]);
    if (item.done && !wasAlreadyDone && item.stars) totalNewStars += item.stars;
    if (item.date > latestDate) latestDate = item.date;
  }

  if (totalNewStars > 0) run('UPDATE users SET total_stars = total_stars + ? WHERE id = ?', [totalNewStars, userId]);
  if (latestDate) run('UPDATE users SET last_active_date = ? WHERE id = ?', [latestDate, userId]);

  checkAndLock(userId);

  const user = queryOne('SELECT total_stars, lock_status FROM users WHERE id = ?', [userId]);
  const owed = queryOne('SELECT COUNT(*) as count FROM daily_progress WHERE user_id = ? AND done = 0', [userId]);

  res.json({ success: true, totalStars: user.total_stars, totalOwed: owed.count, lockStatus: user.lock_status, streak: computeStreak(userId) });
});

// ── Spend stars (gacha etc.) ─────────────────────────────────────────────────
router.post('/spend-stars', (req, res) => {
  const { amount } = req.body;
  if (!amount || amount <= 0) return res.status(400).json({ error: 'invalid amount' });
  const user = queryOne('SELECT total_stars FROM users WHERE id = ?', [req.userId]);
  if (!user || user.total_stars < amount) {
    return res.status(400).json({ error: 'not enough stars' });
  }
  run('UPDATE users SET total_stars = total_stars - ? WHERE id = ?', [amount, req.userId]);
  const updated = queryOne('SELECT total_stars FROM users WHERE id = ?', [req.userId]);
  res.json({ success: true, totalStars: updated.total_stars });
});

// ── Setup (book start date, series index) ───────────────────────────────────
router.post('/setup', (req, res) => {
  const { bookStartDate, startSeriesIndex, appStartDate } = req.body;
  const sets = [], params = [];
  if (bookStartDate) { sets.push('book_start_date = ?'); params.push(bookStartDate); }
  if (startSeriesIndex !== undefined) { sets.push('start_series_index = ?'); params.push(startSeriesIndex); }
  if (appStartDate) { sets.push('app_start_date = ?'); params.push(appStartDate); }
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
module.exports._internals = { computeStreak };
