const express = require('express');
const { query, queryOne, run, runNoSave, saveDb } = require('../db');

const router = express.Router();

// ── China time helpers (same as progress.js) ─────────────────────────────────
function chinaToday() {
  const now = new Date();
  const utcMs = now.getTime() + now.getTimezoneOffset() * 60000;
  const chinaMs = utcMs + 8 * 3600000;
  const china = new Date(chinaMs);
  china.setHours(0, 0, 0, 0);
  return china;
}

function fmtDate(d) {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

/** Get Monday of the week containing `date` (China time) */
function getWeekMonday(date) {
  const d = new Date(date);
  const day = d.getDay(); // 0=Sun ... 6=Sat
  const diff = day === 0 ? 6 : day - 1; // days since Monday
  d.setDate(d.getDate() - diff);
  d.setHours(0, 0, 0, 0);
  return d;
}

/** Get first day of month for `date` */
function getMonthStart(date) {
  const d = new Date(date);
  d.setDate(1);
  d.setHours(0, 0, 0, 0);
  return d;
}

// ── Fake user names pool ─────────────────────────────────────────────────────
const FAKE_NAMES = [
  '小明', '小红', '小刚', '小芳', '小强', '小丽', '小杰', '小燕', '小龙', '小凤',
  '大宝', '二宝', '甜甜', '乐乐', '朵朵', '多多', '豆豆', '果果', '糖糖', '悠悠',
  '星星', '月月', '阳阳', '安安', '贝贝', '晨晨', '丹丹', '菲菲', '浩浩', '佳佳',
  '凯凯', '兰兰', '萌萌', '妮妮', '鹏鹏', '琪琪', '蕊蕊', '帅帅', '婷婷', '薇薇',
  '小雨', '小雪', '小熊', '小虎', '小鱼', '小鹿', '小象', '小兔', '小猫', '小狗',
];

/**
 * Generate fake stars that look realistic.
 * Base: average real user stars for the week, with random variance.
 * If no real data, use 5-25 range (typical daily 1-5 stars * 5 weekdays).
 */
// Max daily stars ≈ 40 (recap 0 + reader ~10 + quiz 20 + listen 10)
const MAX_DAILY_STARS = 40;

function generateFakeStars(realStarsAvg, period = 'week') {
  const base = realStarsAvg > 0 ? realStarsAvg : 12;
  // Generate between 30-95% of base — ensures real user who completes everything ranks #1
  const factor = 0.3 + Math.random() * 0.65;
  const stars = Math.max(1, Math.round(base * factor));
  // Cap: daily max ~40, weekly ~200, monthly ~800
  const cap = period === 'day' ? MAX_DAILY_STARS * 0.9
            : period === 'week' ? MAX_DAILY_STARS * 5 * 0.9
            : MAX_DAILY_STARS * 22 * 0.9;
  return Math.min(stars, Math.round(cap));
}

// ── Weekly group logic ───────────────────────────────────────────────────────

const GROUP_SIZE = 30;

/**
 * Ensure user has a group for this week. Creates groups lazily on first request.
 * Returns the group_id for the current user.
 */
function ensureWeeklyGroup(userId) {
  const today = chinaToday();
  const monday = getWeekMonday(today);
  const weekStart = fmtDate(monday);

  // Check if user already assigned to a group this week
  const existing = queryOne(
    `SELECT gm.group_id FROM weekly_group_members gm
     JOIN weekly_groups g ON g.id = gm.group_id
     WHERE gm.user_id = ? AND g.week_start = ?`,
    [userId, weekStart]
  );
  if (existing) return existing.group_id;

  // Find a group for this week that has room
  const openGroup = queryOne(
    `SELECT g.id, COUNT(gm.id) as member_count FROM weekly_groups g
     LEFT JOIN weekly_group_members gm ON gm.group_id = g.id
     WHERE g.week_start = ?
     GROUP BY g.id
     HAVING member_count < ?
     ORDER BY g.id
     LIMIT 1`,
    [weekStart, GROUP_SIZE]
  );

  let groupId;
  if (openGroup) {
    groupId = openGroup.id;
  } else {
    // Create a new group
    run(
      'INSERT INTO weekly_groups (week_start) VALUES (?)',
      [weekStart]
    );
    // sql.js last_insert_rowid is unreliable, query by week_start instead
    const newGroup = queryOne(
      'SELECT id FROM weekly_groups WHERE week_start = ? ORDER BY id DESC LIMIT 1',
      [weekStart]
    );
    groupId = newGroup.id;

    // Fill with fake users
    fillGroupWithFakes(groupId, weekStart);
  }

  // Add real user to the group
  runNoSave(
    'INSERT INTO weekly_group_members (group_id, user_id) VALUES (?, ?)',
    [groupId, userId]
  );
  saveDb();

  return groupId;
}

/**
 * Fill a newly created group with fake users (up to GROUP_SIZE - some slots for real users).
 * Leave ~5 slots open for real users to join.
 */
function fillGroupWithFakes(groupId, weekStart) {
  // Calculate average real stars this week for realistic fakes
  const sunday = new Date(weekStart + 'T00:00:00');
  sunday.setDate(sunday.getDate() + 6);
  const weekEnd = fmtDate(sunday);

  const avgRow = queryOne(
    `SELECT AVG(total) as avg_stars FROM (
       SELECT SUM(stars) as total FROM daily_progress
       WHERE date >= ? AND date <= ? AND done = 1
       GROUP BY user_id
     )`,
    [weekStart, weekEnd]
  );
  const realAvg = avgRow && avgRow.avg_stars ? avgRow.avg_stars : 0;

  // Pick random fake names (shuffle and take)
  const shuffled = [...FAKE_NAMES].sort(() => Math.random() - 0.5);
  const fakeCount = GROUP_SIZE - 5; // leave 5 slots for real users

  for (let i = 0; i < fakeCount && i < shuffled.length; i++) {
    const stars = generateFakeStars(realAvg, 'week');
    const avatarMonth = Math.floor(Math.random() * 6) + 1;
    runNoSave(
      'INSERT INTO weekly_group_members (group_id, fake_name, fake_stars, avatar_month) VALUES (?, ?, ?, ?)',
      [groupId, shuffled[i], stars, avatarMonth]
    );
  }
  saveDb();
}

// ── Ranking queries ──────────────────────────────────────────────────────────

function getDailyRanking(userId) {
  const today = fmtDate(chinaToday());

  const rows = query(
    `SELECT u.id as user_id, u.child_name, SUM(dp.stars) as stars
     FROM users u
     JOIN daily_progress dp ON dp.user_id = u.id
     WHERE dp.date = ? AND dp.done = 1
     GROUP BY u.id
     ORDER BY stars DESC`,
    [today]
  );

  return buildRankingResponse(rows, userId, 'day');
}

function getMonthlyRanking(userId) {
  const today = chinaToday();
  const monthStart = fmtDate(getMonthStart(today));
  const todayStr = fmtDate(today);

  const rows = query(
    `SELECT u.id as user_id, u.child_name, SUM(dp.stars) as stars
     FROM users u
     JOIN daily_progress dp ON dp.user_id = u.id
     WHERE dp.date >= ? AND dp.date <= ? AND dp.done = 1
     GROUP BY u.id
     ORDER BY stars DESC`,
    [monthStart, todayStr]
  );

  return buildRankingResponse(rows, userId, 'month');
}

function getWeeklyRanking(userId) {
  const groupId = ensureWeeklyGroup(userId);
  const today = chinaToday();
  const monday = getWeekMonday(today);
  const weekStart = fmtDate(monday);
  const sunday = new Date(monday);
  sunday.setDate(sunday.getDate() + 6);
  const weekEnd = fmtDate(sunday);

  // Get real users in this group with their weekly stars
  const realMembers = query(
    `SELECT gm.user_id, u.child_name,
            COALESCE((SELECT SUM(dp.stars) FROM daily_progress dp
                      WHERE dp.user_id = gm.user_id AND dp.date >= ? AND dp.date <= ? AND dp.done = 1), 0) as stars
     FROM weekly_group_members gm
     JOIN users u ON u.id = gm.user_id
     WHERE gm.group_id = ? AND gm.user_id IS NOT NULL`,
    [weekStart, weekEnd, groupId]
  );

  // Get fake users in this group
  const fakeMembers = query(
    `SELECT fake_name as child_name, fake_stars as stars, avatar_month
     FROM weekly_group_members
     WHERE group_id = ? AND user_id IS NULL`,
    [groupId]
  );

  // Merge and sort
  const all = [];
  for (const r of realMembers) {
    all.push({
      userId: r.user_id,
      childName: r.child_name,
      stars: r.stars,
      isCurrentUser: r.user_id == userId,
      avatarMonth: null, // real users use their own avatar
    });
  }
  for (const f of fakeMembers) {
    all.push({
      userId: null,
      childName: f.child_name,
      stars: f.stars,
      isCurrentUser: false,
      avatarMonth: f.avatar_month,
    });
  }

  all.sort((a, b) => b.stars - a.stars);

  // Assign ranks
  let myRank = null;
  const rankings = all.map((item, idx) => {
    const rank = idx + 1;
    if (item.isCurrentUser) myRank = rank;
    return {
      rank,
      childName: item.childName,
      stars: item.stars,
      isCurrentUser: item.isCurrentUser,
      avatarMonth: item.avatarMonth,
    };
  });

  return { rankings, myRank, period: 'week' };
}

/** Build ranking response for daily/monthly with fake users mixed in */
function buildRankingResponse(rows, userId, period) {
  // Real users
  const all = rows.map(row => ({
    childName: row.child_name,
    stars: row.stars || 0,
    isCurrentUser: row.user_id == userId,
    avatarMonth: Math.floor(Math.random() * 6) + 1,
  }));

  // Ensure current user is in the list
  if (!all.some(r => r.isCurrentUser)) {
    const user = queryOne('SELECT child_name FROM users WHERE id = ?', [userId]);
    if (user) {
      all.push({ childName: user.child_name, stars: 0, isCurrentUser: true, avatarMonth: 1 });
    }
  }

  // Add fake users to fill up to ~20
  const myStars = all.find(r => r.isCurrentUser)?.stars || 0;
  const realAvg = myStars > 0 ? myStars : 30;
  const fakeCount = Math.max(0, 20 - all.length);
  const shuffled = [...FAKE_NAMES].sort(() => Math.random() - 0.5).slice(0, fakeCount);
  for (const name of shuffled) {
    all.push({
      childName: name,
      stars: generateFakeStars(realAvg, period),
      isCurrentUser: false,
      avatarMonth: Math.floor(Math.random() * 6) + 1,
    });
  }

  // Sort by stars desc
  all.sort((a, b) => b.stars - a.stars);

  let myRank = null;
  const rankings = all.map((item, idx) => {
    const rank = idx + 1;
    if (item.isCurrentUser) myRank = rank;
    return { rank, ...item };
  });

  return { rankings, myRank, period };
}

// ── Route handler ────────────────────────────────────────────────────────────

router.get('/', (req, res) => {
  const userId = req.userId;
  const period = req.query.period || 'week';

  let result;
  switch (period) {
    case 'day':
      result = getDailyRanking(userId);
      break;
    case 'month':
      result = getMonthlyRanking(userId);
      break;
    case 'week':
    default:
      result = getWeeklyRanking(userId);
      break;
  }

  res.json({ success: true, ...result });
});

// Export internals for testing
module.exports = router;
module.exports._internals = {
  chinaToday, fmtDate, getWeekMonday, getMonthStart,
  ensureWeeklyGroup, generateFakeStars, getDailyRanking,
  getWeeklyRanking, getMonthlyRanking, FAKE_NAMES, GROUP_SIZE,
};
