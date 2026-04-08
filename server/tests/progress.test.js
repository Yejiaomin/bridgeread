/**
 * Progress & Debt System Tests
 *
 * Tests the core debt/backfill logic:
 * - Backfill creates done=0 records for weekdays between book_start_date and today
 * - Weekends are skipped
 * - Completing a module sets done=1 and reduces totalOwed
 * - debtByDate returns correct per-day counts
 * - Completing a module for a past date (debt makeup) works correctly
 * - Lock triggers at >= 15 owed
 */

const initSqlJs = require('sql.js');

// ── In-memory DB helpers (same interface as db.js) ─────────────────────────
let db;

function setupDb() {
  const SQL = require('sql.js');
  // sql.js returns a promise in newer versions but sync in others
  // We'll initialize in beforeAll
}

function query(sql, params = []) {
  const stmt = db.prepare(sql);
  if (params.length) stmt.bind(params);
  const rows = [];
  while (stmt.step()) rows.push(stmt.getAsObject());
  stmt.free();
  return rows;
}

function queryOne(sql, params = []) {
  const rows = query(sql, params);
  return rows[0] || null;
}

function run(sql, params = []) {
  db.run(sql, params);
}

// ── Progress logic (extracted from routes/progress.js) ─────────────────────
const MODULES = ['recap', 'reader', 'quiz', 'listen'];

function fmtDate(d) {
  return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
}

function backfillDebt(userId, referenceDate = new Date()) {
  const user = queryOne('SELECT book_start_date FROM users WHERE id = ?', [userId]);
  if (!user || !user.book_start_date) return;

  const start = new Date(user.book_start_date + 'T00:00:00');
  const today = new Date(referenceDate);
  today.setHours(0, 0, 0, 0);

  for (let d = new Date(start); d <= today; d.setDate(d.getDate() + 1)) {
    const dow = d.getDay();
    if (dow === 0 || dow === 6) continue;

    const dateStr = fmtDate(d);
    for (const mod of MODULES) {
      run(`INSERT OR IGNORE INTO daily_progress (user_id, date, module, done, stars)
           VALUES (?, ?, ?, 0, 0)`, [userId, dateStr, mod]);
    }
  }
}

function completeModule(userId, date, module, stars = 10) {
  run(`INSERT INTO daily_progress (user_id, date, module, done, stars)
       VALUES (?, ?, ?, 1, ?)
       ON CONFLICT(user_id, date, module) DO UPDATE SET done=1, stars=?`,
    [userId, date, module, stars, stars]);
}

function getTotalOwed(userId) {
  const row = queryOne('SELECT COUNT(*) as count FROM daily_progress WHERE user_id = ? AND done = 0', [userId]);
  return row ? row.count : 0;
}

function getDebtByDate(userId) {
  return query(
    `SELECT date, COUNT(*) as debt FROM daily_progress
     WHERE user_id = ? AND done = 0 GROUP BY date ORDER BY date`,
    [userId]
  );
}

function getDebtForDate(userId, date) {
  const row = queryOne(
    'SELECT COUNT(*) as count FROM daily_progress WHERE user_id = ? AND date = ? AND done = 0',
    [userId, date]
  );
  return row ? row.count : 0;
}

function checkAndLock(userId) {
  const owed = getTotalOwed(userId);
  if (owed >= 15) {
    run('UPDATE users SET lock_status = 1 WHERE id = ? AND lock_status = 0', [userId]);
    return true;
  }
  return false;
}

// ── Tests ──────────────────────────────────────────────────────────────────

beforeAll(async () => {
  const SQL = await initSqlJs();
  db = new SQL.Database();

  db.run(`
    CREATE TABLE users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      phone TEXT UNIQUE NOT NULL,
      password_hash TEXT NOT NULL,
      child_name TEXT NOT NULL,
      book_start_date TEXT,
      start_series_index INTEGER DEFAULT 0,
      total_stars INTEGER DEFAULT 0,
      lock_status INTEGER DEFAULT 0,
      unlock_count INTEGER DEFAULT 0,
      last_active_date TEXT,
      assessment_result TEXT,
      created_at TEXT DEFAULT (datetime('now'))
    )
  `);

  db.run(`
    CREATE TABLE daily_progress (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL,
      date TEXT NOT NULL,
      module TEXT NOT NULL,
      done INTEGER DEFAULT 0,
      stars INTEGER DEFAULT 0,
      lesson_id TEXT,
      FOREIGN KEY (user_id) REFERENCES users(id),
      UNIQUE(user_id, date, module)
    )
  `);
});

beforeEach(() => {
  db.run('DELETE FROM daily_progress');
  db.run('DELETE FROM users');
  // Reset autoincrement so user always gets id=1
  db.run("DELETE FROM sqlite_sequence");
  // Create a test user with book_start_date = Monday 2026-03-30
  db.run(`INSERT INTO users (phone, password_hash, child_name, book_start_date)
          VALUES ('13800000000', 'hash', 'TestChild', '2026-03-30')`);
});

afterAll(() => {
  db.close();
});

describe('backfillDebt', () => {
  test('creates 4 modules per weekday from start to today', () => {
    // Reference date: Friday 2026-04-03 (Mon-Fri = 5 weekdays)
    backfillDebt(1, new Date('2026-04-03T12:00:00'));

    const total = getTotalOwed(1);
    expect(total).toBe(20); // 5 days × 4 modules
  });

  test('skips weekends', () => {
    // Start: Monday 2026-03-30, Reference: Sunday 2026-04-05
    // Weekdays: Mon 30, Tue 31, Wed 1, Thu 2, Fri 3 = 5 days
    // Sat 4, Sun 5 skipped
    backfillDebt(1, new Date('2026-04-05T12:00:00'));

    const total = getTotalOwed(1);
    expect(total).toBe(20); // only 5 weekdays × 4 modules
  });

  test('includes today if today is a weekday', () => {
    // Reference: Monday 2026-03-30 (same as start date)
    backfillDebt(1, new Date('2026-03-30T12:00:00'));

    const total = getTotalOwed(1);
    expect(total).toBe(4); // 1 day × 4 modules
  });

  test('does not create duplicates on repeated calls', () => {
    backfillDebt(1, new Date('2026-04-03T12:00:00'));
    backfillDebt(1, new Date('2026-04-03T12:00:00'));

    const total = getTotalOwed(1);
    expect(total).toBe(20); // still 20, no duplicates
  });

  test('does nothing if no book_start_date', () => {
    run("UPDATE users SET book_start_date = NULL WHERE id = 1");
    backfillDebt(1, new Date('2026-04-03T12:00:00'));

    const total = getTotalOwed(1);
    expect(total).toBe(0);
  });

  test('handles start date on Saturday correctly', () => {
    run("UPDATE users SET book_start_date = '2026-04-04' WHERE id = 1"); // Saturday
    // Reference: Monday 2026-04-06
    backfillDebt(1, new Date('2026-04-06T12:00:00'));

    const total = getTotalOwed(1);
    expect(total).toBe(4); // only Monday Apr 6
  });
});

describe('completeModule', () => {
  test('completing a module reduces totalOwed by 1', () => {
    backfillDebt(1, new Date('2026-03-30T12:00:00'));
    expect(getTotalOwed(1)).toBe(4);

    completeModule(1, '2026-03-30', 'reader');
    expect(getTotalOwed(1)).toBe(3);
  });

  test('completing all 4 modules for a day makes debt 0 for that day', () => {
    backfillDebt(1, new Date('2026-03-30T12:00:00'));

    for (const mod of MODULES) {
      completeModule(1, '2026-03-30', mod);
    }

    expect(getTotalOwed(1)).toBe(0);
    expect(getDebtForDate(1, '2026-03-30')).toBe(0);
  });

  test('completing a module for a past date (debt makeup) works', () => {
    // Backfill Mon-Fri, then complete reader for Tuesday
    backfillDebt(1, new Date('2026-04-03T12:00:00'));
    expect(getTotalOwed(1)).toBe(20);

    completeModule(1, '2026-03-31', 'reader'); // Tuesday
    expect(getTotalOwed(1)).toBe(19);
    expect(getDebtForDate(1, '2026-03-31')).toBe(3); // 4 - 1 = 3
  });

  test('completing same module twice does not reduce debt further', () => {
    backfillDebt(1, new Date('2026-03-30T12:00:00'));

    completeModule(1, '2026-03-30', 'reader');
    expect(getTotalOwed(1)).toBe(3);

    completeModule(1, '2026-03-30', 'reader'); // duplicate
    expect(getTotalOwed(1)).toBe(3); // unchanged
  });
});

describe('debtByDate', () => {
  test('returns correct debt per date', () => {
    backfillDebt(1, new Date('2026-03-31T12:00:00')); // Mon + Tue = 8

    const debt = getDebtByDate(1);
    expect(debt).toHaveLength(2);
    expect(debt[0]).toEqual({ date: '2026-03-30', debt: 4 });
    expect(debt[1]).toEqual({ date: '2026-03-31', debt: 4 });
  });

  test('completed modules reduce per-date debt', () => {
    backfillDebt(1, new Date('2026-03-31T12:00:00'));

    completeModule(1, '2026-03-30', 'reader');
    completeModule(1, '2026-03-30', 'quiz');

    const debt = getDebtByDate(1);
    const mon = debt.find(d => d.date === '2026-03-30');
    const tue = debt.find(d => d.date === '2026-03-31');

    expect(mon.debt).toBe(2);  // 4 - 2
    expect(tue.debt).toBe(4);  // untouched
  });

  test('fully completed date disappears from debtByDate', () => {
    backfillDebt(1, new Date('2026-03-31T12:00:00'));

    for (const mod of MODULES) {
      completeModule(1, '2026-03-30', mod);
    }

    const debt = getDebtByDate(1);
    const mon = debt.find(d => d.date === '2026-03-30');
    expect(mon).toBeUndefined(); // no debt for that day
    expect(debt).toHaveLength(1); // only Tuesday left
  });
});

describe('checkAndLock', () => {
  test('locks user when owed >= 15', () => {
    // 4 weekdays = 16 owed modules
    backfillDebt(1, new Date('2026-04-02T12:00:00')); // Mon-Thu = 4 days × 4 = 16

    const locked = checkAndLock(1);
    expect(locked).toBe(true);

    const user = queryOne('SELECT lock_status FROM users WHERE id = 1');
    expect(user.lock_status).toBe(1);
  });

  test('does not lock when owed < 15', () => {
    // 3 weekdays = 12 owed modules
    backfillDebt(1, new Date('2026-04-01T12:00:00')); // Mon-Wed = 3 days × 4 = 12

    const locked = checkAndLock(1);
    expect(locked).toBe(false);

    const user = queryOne('SELECT lock_status FROM users WHERE id = 1');
    expect(user.lock_status).toBe(0);
  });

  test('completing modules can prevent lock', () => {
    // 4 weekdays = 16 owed, complete 2 to bring to 14
    backfillDebt(1, new Date('2026-04-02T12:00:00'));
    completeModule(1, '2026-03-30', 'reader');
    completeModule(1, '2026-03-30', 'quiz');

    const locked = checkAndLock(1);
    expect(locked).toBe(false); // 14 < 15
  });
});

describe('edge cases', () => {
  test('book_start_date in the future generates no debt', () => {
    run("UPDATE users SET book_start_date = '2099-01-01' WHERE id = 1");
    backfillDebt(1, new Date('2026-04-07T12:00:00'));
    expect(getTotalOwed(1)).toBe(0);
  });

  test('book_start_date same as reference date (today only)', () => {
    run("UPDATE users SET book_start_date = '2026-04-07' WHERE id = 1"); // Tuesday
    backfillDebt(1, new Date('2026-04-07T12:00:00'));
    expect(getTotalOwed(1)).toBe(4);
  });

  test('cross-month boundary works', () => {
    run("UPDATE users SET book_start_date = '2026-03-30' WHERE id = 1"); // Monday
    // Reference: April 1 (Wednesday) = Mon + Tue + Wed = 3 weekdays
    backfillDebt(1, new Date('2026-04-01T12:00:00'));
    expect(getTotalOwed(1)).toBe(12); // 3 × 4
  });
});

describe('full workflow', () => {
  test('new user starts study on Monday, checks on Friday', () => {
    // User started Monday Mar 30, now it's Friday Apr 3
    backfillDebt(1, new Date('2026-04-03T12:00:00'));

    // 5 weekdays × 4 modules = 20 owed
    expect(getTotalOwed(1)).toBe(20);

    // User completes all of today (Friday Apr 3)
    for (const mod of MODULES) {
      completeModule(1, '2026-04-03', mod);
    }
    expect(getTotalOwed(1)).toBe(16); // 4 past days still owed

    // User makes up Monday
    for (const mod of MODULES) {
      completeModule(1, '2026-03-30', mod);
    }
    expect(getTotalOwed(1)).toBe(12); // 3 days still owed

    // debtByDate should show 3 remaining days
    const debt = getDebtByDate(1);
    expect(debt).toHaveLength(3);
    expect(debt.map(d => d.date)).toEqual(['2026-03-31', '2026-04-01', '2026-04-02']);
  });
});
