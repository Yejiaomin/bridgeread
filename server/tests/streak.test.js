/**
 * Server-side streak computation tests.
 *
 * computeStreak counts back from today over distinct dates with at least one
 * `done = 1` module. If today has no completion, counts from yesterday.
 *
 * These tests exercise the function directly (not via HTTP) — they need
 * the real DB so we use the same setup pattern as ranking.test.js.
 */

const { getDb } = require('../index');
const { query, queryOne, run } = require('../db');
const { computeStreak } = require('../routes/progress')._internals;
const { chinaToday, fmtDate } = require('../lib/china_time');

beforeAll(async () => { await getDb(); });

function cleanAll() {
  run('DELETE FROM daily_progress');
  run('DELETE FROM users');
  try { run('DELETE FROM sqlite_sequence'); } catch (_) {}
}

function createUser(id = 1, phone = '13800000001') {
  run(
    'INSERT INTO users (id, phone, password_hash, child_name, book_start_date) VALUES (?, ?, ?, ?, ?)',
    [id, phone, 'x', 'TestKid', '2026-01-01']
  );
}

/** Insert a done=1 record for [user, date, module]. */
function markDone(userId, date, module = 'reader') {
  run(
    `INSERT INTO daily_progress (user_id, date, module, done, stars)
     VALUES (?, ?, ?, 1, 10)
     ON CONFLICT(user_id, date, module) DO UPDATE SET done=1, stars=10`,
    [userId, date, module]
  );
}

/** Returns "YYYY-MM-DD" for N days ago in China time. */
function daysAgo(n) {
  const d = chinaToday();
  d.setUTCDate(d.getUTCDate() - n);
  return fmtDate(d);
}

describe('computeStreak', () => {
  beforeEach(() => {
    cleanAll();
    createUser(1);
  });

  test('no completions → streak 0', () => {
    expect(computeStreak(1)).toBe(0);
  });

  test('today only → streak 1', () => {
    markDone(1, daysAgo(0));
    expect(computeStreak(1)).toBe(1);
  });

  test('today + yesterday → streak 2', () => {
    markDone(1, daysAgo(0));
    markDone(1, daysAgo(1));
    expect(computeStreak(1)).toBe(2);
  });

  test('today + yesterday + day before → streak 3', () => {
    markDone(1, daysAgo(0));
    markDone(1, daysAgo(1));
    markDone(1, daysAgo(2));
    expect(computeStreak(1)).toBe(3);
  });

  test('yesterday only (no today) → streak 1, counted from yesterday', () => {
    markDone(1, daysAgo(1));
    expect(computeStreak(1)).toBe(1);
  });

  test('yesterday + day before (no today) → streak 2', () => {
    markDone(1, daysAgo(1));
    markDone(1, daysAgo(2));
    expect(computeStreak(1)).toBe(2);
  });

  test('today + gap + day before → streak 1 (gap breaks chain)', () => {
    markDone(1, daysAgo(0));
    markDone(1, daysAgo(2)); // gap: yesterday missing
    expect(computeStreak(1)).toBe(1);
  });

  test('long 7-day streak', () => {
    for (let i = 0; i < 7; i++) markDone(1, daysAgo(i));
    expect(computeStreak(1)).toBe(7);
  });

  test('multiple modules same day count as one streak day', () => {
    markDone(1, daysAgo(0), 'reader');
    markDone(1, daysAgo(0), 'quiz');
    markDone(1, daysAgo(0), 'listen');
    expect(computeStreak(1)).toBe(1);
  });

  test('only counts the specified user', () => {
    createUser(2, '13800000002');
    markDone(1, daysAgo(0));
    markDone(2, daysAgo(0));
    markDone(2, daysAgo(1));
    expect(computeStreak(1)).toBe(1);
    expect(computeStreak(2)).toBe(2);
  });

  test('done=0 records do not contribute', () => {
    run(
      `INSERT INTO daily_progress (user_id, date, module, done, stars)
       VALUES (?, ?, ?, 0, 0)`,
      [1, daysAgo(0), 'reader']
    );
    expect(computeStreak(1)).toBe(0);
  });
});
