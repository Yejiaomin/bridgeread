/**
 * Ranking / Leaderboard Tests
 *
 * Tests:
 * - Weekly group creation and lazy assignment
 * - Fake user generation
 * - Daily / weekly / monthly ranking queries
 * - API endpoint with auth
 */

const request = require('supertest');
const { app, getDb } = require('../index');
const { query, queryOne, run, runNoSave, saveDb } = require('../db');

// Helper: china-time-aware date formatting (mirrors ranking.js)
function fmtDate(d) {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

beforeAll(async () => {
  await getDb();
});

// ── Helpers ────────────────────────────────────────────────────────────────

function cleanAll() {
  run('DELETE FROM weekly_group_members');
  run('DELETE FROM weekly_groups');
  run('DELETE FROM daily_progress');
  run('DELETE FROM users');
  run('DELETE FROM sms_codes');
  try { run("DELETE FROM sqlite_sequence"); } catch (_) {}
}

async function registerAndGetToken(phone = '13800001111', childName = 'TestKid') {
  const res = await request(app)
    .post('/api/auth/register')
    .send({ phone, code: '123456', password: '12345678', childName });
  return { token: res.body.token, userId: res.body.userId };
}

function insertProgress(userId, date, module, stars, done = 1) {
  run(
    `INSERT INTO daily_progress (user_id, date, module, done, stars)
     VALUES (?, ?, ?, ?, ?)
     ON CONFLICT(user_id, date, module) DO UPDATE SET done=?, stars=?`,
    [userId, date, module, done, stars, done, stars]
  );
}

// ── Unit tests for internals ──────────────────────────────────────────────

describe('Ranking internals', () => {
  const { getWeekMonday, getMonthStart, generateFakeStars, FAKE_NAMES } = require('../routes/ranking')._internals;

  test('getWeekMonday returns Monday', () => {
    // Wednesday 2026-04-08
    const wed = new Date('2026-04-08T00:00:00');
    const mon = getWeekMonday(wed);
    expect(mon.getDay()).toBe(1); // Monday
    expect(fmtDate(mon)).toBe('2026-04-06');
  });

  test('getWeekMonday for Sunday returns previous Monday', () => {
    const sun = new Date('2026-04-12T00:00:00');
    const mon = getWeekMonday(sun);
    expect(fmtDate(mon)).toBe('2026-04-06');
  });

  test('getWeekMonday for Monday returns itself', () => {
    const mon = new Date('2026-04-06T00:00:00');
    const result = getWeekMonday(mon);
    expect(fmtDate(result)).toBe('2026-04-06');
  });

  test('getMonthStart returns first of month', () => {
    const d = new Date('2026-04-15T00:00:00');
    const first = getMonthStart(d);
    expect(fmtDate(first)).toBe('2026-04-01');
  });

  test('generateFakeStars returns non-negative integer', () => {
    for (let i = 0; i < 20; i++) {
      const s = generateFakeStars(15);
      expect(Number.isInteger(s)).toBe(true);
      expect(s).toBeGreaterThanOrEqual(0);
    }
  });

  test('generateFakeStars with 0 average uses default base', () => {
    const stars = [];
    for (let i = 0; i < 50; i++) stars.push(generateFakeStars(0));
    const avg = stars.reduce((a, b) => a + b, 0) / stars.length;
    // Should cluster around 12 (the default base)
    expect(avg).toBeGreaterThan(2);
    expect(avg).toBeLessThan(30);
  });

  test('FAKE_NAMES has at least 50 entries', () => {
    expect(FAKE_NAMES.length).toBeGreaterThanOrEqual(50);
  });
});

// ── Weekly group tests ────────────────────────────────────────────────────

describe('Weekly group system', () => {
  const { ensureWeeklyGroup, GROUP_SIZE } = require('../routes/ranking')._internals;

  beforeEach(() => cleanAll());

  test('ensureWeeklyGroup creates a group and assigns user', async () => {
    const { userId } = await registerAndGetToken('13800002222', 'GroupKid');
    const user = queryOne('SELECT id FROM users WHERE phone = ?', ['13800002222']);

    const groupId = ensureWeeklyGroup(user.id);
    expect(groupId).toBeGreaterThan(0);

    // User should be in the group
    const member = queryOne(
      'SELECT * FROM weekly_group_members WHERE group_id = ? AND user_id = ?',
      [groupId, user.id]
    );
    expect(member).not.toBeNull();

    // Group should have fake members
    const fakes = query(
      'SELECT * FROM weekly_group_members WHERE group_id = ? AND user_id IS NULL',
      [groupId]
    );
    expect(fakes.length).toBe(GROUP_SIZE - 5); // 25 fake users
  });

  test('ensureWeeklyGroup returns same group on second call', async () => {
    const { userId } = await registerAndGetToken('13800003333', 'SameGroupKid');
    const user = queryOne('SELECT id FROM users WHERE phone = ?', ['13800003333']);

    const g1 = ensureWeeklyGroup(user.id);
    const g2 = ensureWeeklyGroup(user.id);
    expect(g1).toBe(g2);
  });

  test('second user joins existing group if space available', async () => {
    await registerAndGetToken('13800004444', 'Kid1');
    await registerAndGetToken('13800005555', 'Kid2');
    const u1 = queryOne('SELECT id FROM users WHERE phone = ?', ['13800004444']);
    const u2 = queryOne('SELECT id FROM users WHERE phone = ?', ['13800005555']);

    const g1 = ensureWeeklyGroup(u1.id);
    const g2 = ensureWeeklyGroup(u2.id);
    expect(g1).toBe(g2); // same group since there's room
  });
});

// ── API endpoint tests ────────────────────────────────────────────────────

describe('GET /api/ranking', () => {
  beforeEach(() => cleanAll());

  test('returns 401 without token', async () => {
    const res = await request(app).get('/api/ranking');
    expect(res.status).toBe(401);
  });

  test('returns daily ranking', async () => {
    const { token } = await registerAndGetToken('13800006666', 'DailyKid');
    const user = queryOne('SELECT id FROM users WHERE phone = ?', ['13800006666']);

    // Use a helper to get today's date in the same format the ranking module uses
    const { chinaToday: ct, fmtDate: fd } = require('../routes/ranking')._internals;
    const today = fd(ct());

    insertProgress(user.id, today, 'reader', 5);
    insertProgress(user.id, today, 'quiz', 3);

    const res = await request(app)
      .get('/api/ranking?period=day')
      .set('Authorization', `Bearer ${token}`);

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.period).toBe('day');
    expect(res.body.rankings.length).toBeGreaterThanOrEqual(1);

    const me = res.body.rankings.find(r => r.isCurrentUser);
    expect(me).toBeDefined();
    expect(me.stars).toBe(8);
    expect(me.childName).toBe('DailyKid');
    expect(res.body.myRank).toBe(me.rank);
  });

  test('returns weekly ranking with fake users', async () => {
    const { token } = await registerAndGetToken('13800007777', 'WeeklyKid');

    const res = await request(app)
      .get('/api/ranking?period=week')
      .set('Authorization', `Bearer ${token}`);

    expect(res.status).toBe(200);
    expect(res.body.period).toBe('week');
    // Should have fake users + the real user
    expect(res.body.rankings.length).toBeGreaterThan(1);
    expect(res.body.myRank).toBeDefined();

    const me = res.body.rankings.find(r => r.isCurrentUser);
    expect(me).toBeDefined();
    expect(me.childName).toBe('WeeklyKid');
  });

  test('returns monthly ranking', async () => {
    const { token } = await registerAndGetToken('13800008888', 'MonthKid');
    const user = queryOne('SELECT id FROM users WHERE phone = ?', ['13800008888']);

    const { chinaToday: ct, fmtDate: fd } = require('../routes/ranking')._internals;
    const today = fd(ct());

    insertProgress(user.id, today, 'reader', 10);

    const res = await request(app)
      .get('/api/ranking?period=month')
      .set('Authorization', `Bearer ${token}`);

    expect(res.status).toBe(200);
    expect(res.body.period).toBe('month');

    const me = res.body.rankings.find(r => r.isCurrentUser);
    expect(me).toBeDefined();
    expect(me.stars).toBe(10);
  });

  test('user with no stars still appears in daily ranking', async () => {
    const { token } = await registerAndGetToken('13800009999', 'NoStarsKid');

    const res = await request(app)
      .get('/api/ranking?period=day')
      .set('Authorization', `Bearer ${token}`);

    expect(res.status).toBe(200);
    const me = res.body.rankings.find(r => r.isCurrentUser);
    expect(me).toBeDefined();
    expect(me.stars).toBe(0);
    expect(res.body.myRank).toBe(me.rank);
  });

  test('default period is week', async () => {
    const { token } = await registerAndGetToken('13800010000', 'DefaultKid');

    const res = await request(app)
      .get('/api/ranking')
      .set('Authorization', `Bearer ${token}`);

    expect(res.status).toBe(200);
    expect(res.body.period).toBe('week');
  });

  test('daily ranking sorts by stars descending', async () => {
    const { token: t1 } = await registerAndGetToken('13800011111', 'TopKid');
    await registerAndGetToken('13800012222', 'MidKid');
    await registerAndGetToken('13800013333', 'LowKid');

    const u1 = queryOne('SELECT id FROM users WHERE phone = ?', ['13800011111']);
    const u2 = queryOne('SELECT id FROM users WHERE phone = ?', ['13800012222']);
    const u3 = queryOne('SELECT id FROM users WHERE phone = ?', ['13800013333']);

    const { chinaToday: ct, fmtDate: fd } = require('../routes/ranking')._internals;
    const today = fd(ct());

    insertProgress(u1.id, today, 'reader', 20);
    insertProgress(u2.id, today, 'reader', 10);
    insertProgress(u3.id, today, 'reader', 5);

    const res = await request(app)
      .get('/api/ranking?period=day')
      .set('Authorization', `Bearer ${t1}`);

    expect(res.status).toBe(200);
    // Find the real users in the ranking (fake users are mixed in)
    const realUsers = res.body.rankings.filter(r => ['TopKid', 'MidKid', 'LowKid'].includes(r.childName));
    expect(realUsers.length).toBe(3);
    // Real users should be in correct relative order (TopKid > MidKid > LowKid)
    const topIdx = res.body.rankings.findIndex(r => r.childName === 'TopKid');
    const midIdx = res.body.rankings.findIndex(r => r.childName === 'MidKid');
    const lowIdx = res.body.rankings.findIndex(r => r.childName === 'LowKid');
    expect(topIdx).toBeLessThan(midIdx);
    expect(midIdx).toBeLessThan(lowIdx);
    // Rankings should have fake users too
    expect(res.body.rankings.length).toBeGreaterThan(3);
  });

  test('user with 0 stars appears in ranking with isCurrentUser=true', async () => {
    // Register but don't earn any stars
    const { token } = await registerAndGetToken('13800099999', 'ZeroKid');

    const res = await request(app)
      .get('/api/ranking?period=day')
      .set('Authorization', `Bearer ${token}`);

    expect(res.status).toBe(200);
    const me = res.body.rankings.find(r => r.isCurrentUser === true);
    expect(me).toBeDefined();
    expect(me.childName).toBe('ZeroKid');
    expect(me.stars).toBe(0);
    expect(res.body.myRank).toBeDefined();
  });

  test('daily ranking includes fake users filling to ~20', async () => {
    const { token } = await registerAndGetToken('13800088888', 'OnlyKid');

    const res = await request(app)
      .get('/api/ranking?period=day')
      .set('Authorization', `Bearer ${token}`);

    expect(res.status).toBe(200);
    expect(res.body.rankings.length).toBeGreaterThanOrEqual(20);
  });

  test('monthly ranking includes fake users', async () => {
    const { token } = await registerAndGetToken('13800077777', 'MonthKid');

    const res = await request(app)
      .get('/api/ranking?period=month')
      .set('Authorization', `Bearer ${token}`);

    expect(res.status).toBe(200);
    expect(res.body.rankings.length).toBeGreaterThanOrEqual(20);
    const me = res.body.rankings.find(r => r.isCurrentUser === true);
    expect(me).toBeDefined();
  });

  test('fake users stars do not exceed real user max (ranking rule)', async () => {
    const { token: t1 } = await registerAndGetToken('13800066666', 'MaxKid');
    const u1 = queryOne('SELECT id FROM users WHERE phone = ?', ['13800066666']);
    const { chinaToday: ct, fmtDate: fd } = require('../routes/ranking')._internals;
    const today = fd(ct());

    // Give real user 40 stars (max daily)
    insertProgress(u1.id, today, 'reader', 10);
    insertProgress(u1.id, today, 'quiz', 20);
    insertProgress(u1.id, today, 'listen', 10);

    const res = await request(app)
      .get('/api/ranking?period=day')
      .set('Authorization', `Bearer ${t1}`);

    // All fake users should have fewer stars than 40
    const fakeUsers = res.body.rankings.filter(r => !r.isCurrentUser);
    for (const fake of fakeUsers) {
      expect(fake.stars).toBeLessThanOrEqual(40);
    }

    // Real user should be ranked #1 or near top
    expect(res.body.myRank).toBeLessThanOrEqual(3);
  });

  test('all three periods return data in single session', async () => {
    const { token } = await registerAndGetToken('13800055555', 'TriKid');

    const [day, week, month] = await Promise.all([
      request(app).get('/api/ranking?period=day').set('Authorization', `Bearer ${token}`),
      request(app).get('/api/ranking?period=week').set('Authorization', `Bearer ${token}`),
      request(app).get('/api/ranking?period=month').set('Authorization', `Bearer ${token}`),
    ]);

    expect(day.status).toBe(200);
    expect(week.status).toBe(200);
    expect(month.status).toBe(200);

    // Each should have rankings with current user
    for (const res of [day, week, month]) {
      expect(res.body.rankings.length).toBeGreaterThan(0);
      expect(res.body.myRank).toBeDefined();
    }
  });
});
