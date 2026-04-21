// SQLite via better-sqlite3 — direct file I/O, ~100x faster than sql.js for
// our write-heavy progress sync workload. Same .db file format as before, so
// migration is a drop-in: existing data file works as-is.
const Database = require('better-sqlite3');
const path = require('path');

const DB_PATH = path.join(__dirname, 'data', 'bridgeread.db');

let db;

async function getDb() {
  if (db) return db;

  db = new Database(DB_PATH);
  // WAL mode = better concurrent read perf, smaller fsync footprint
  db.pragma('journal_mode = WAL');
  db.pragma('synchronous = NORMAL');
  // Match prior sql.js behavior: don't enforce FK constraints. Existing
  // tables and code paths rely on lax FK semantics (e.g. progress rows
  // outliving deleted users). Enable later only after auditing all routes.
  db.pragma('foreign_keys = OFF');

  db.exec(`
    CREATE TABLE IF NOT EXISTS users (
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
    );

    CREATE TABLE IF NOT EXISTS daily_progress (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL,
      date TEXT NOT NULL,
      module TEXT NOT NULL,
      done INTEGER DEFAULT 0,
      stars INTEGER DEFAULT 0,
      lesson_id TEXT,
      FOREIGN KEY (user_id) REFERENCES users(id),
      UNIQUE(user_id, date, module)
    );

    CREATE TABLE IF NOT EXISTS recordings (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL,
      date TEXT NOT NULL,
      lesson_id TEXT NOT NULL,
      sentence TEXT,
      file_path TEXT NOT NULL,
      created_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY (user_id) REFERENCES users(id)
    );

    CREATE TABLE IF NOT EXISTS sms_codes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      phone TEXT NOT NULL,
      code TEXT NOT NULL,
      expires_at TEXT NOT NULL,
      used INTEGER DEFAULT 0,
      created_at TEXT DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS study_room (
      user_id INTEGER PRIMARY KEY,
      placed_items TEXT DEFAULT '{}',
      treasure_box_items TEXT DEFAULT '[]',
      equipped_accessory TEXT DEFAULT '',
      gacha_date TEXT,
      gacha_count INTEGER DEFAULT 0,
      today_eggy TEXT DEFAULT '',
      FOREIGN KEY (user_id) REFERENCES users(id)
    );

    CREATE TABLE IF NOT EXISTS weekly_groups (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      week_start TEXT NOT NULL,
      created_at TEXT DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS weekly_group_members (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      group_id INTEGER NOT NULL,
      user_id INTEGER,
      fake_name TEXT,
      fake_stars INTEGER DEFAULT 0,
      avatar_month INTEGER DEFAULT 1,
      FOREIGN KEY (group_id) REFERENCES weekly_groups(id),
      FOREIGN KEY (user_id) REFERENCES users(id)
    );
  `);

  // Profile columns added later — safe to re-run, ignore "duplicate column" errors
  const profileCols = [
    ['profile_avatar', 'INTEGER DEFAULT 0'],
    ['profile_birthday', 'TEXT'],
    ['profile_gender', 'TEXT'],
    ['profile_hobbies', 'TEXT'],
    ['profile_goal', 'TEXT'],
    ['profile_custom_avatar', 'TEXT'],
    ['listen_date', 'TEXT'],
    ['listen_seconds', 'INTEGER DEFAULT 0'],
    ['app_start_date', 'TEXT'],
  ];
  for (const [col, def] of profileCols) {
    try { db.exec(`ALTER TABLE users ADD COLUMN ${col} ${def}`); } catch (_) {}
  }
  try { db.exec("ALTER TABLE study_room ADD COLUMN today_eggy TEXT DEFAULT ''"); } catch (_) {}

  return db;
}

// Helper: SELECT rows
function query(sql, params = []) {
  return db.prepare(sql).all(...params);
}

// Helper: SELECT first row
function queryOne(sql, params = []) {
  return db.prepare(sql).get(...params) || null;
}

// Helper: INSERT/UPDATE/DELETE — returns { lastInsertRowid, changes }
function run(sql, params = []) {
  return db.prepare(sql).run(...params);
}

// Kept for API compatibility — better-sqlite3 persists immediately,
// no manual save needed.
function runNoSave(sql, params = []) {
  db.prepare(sql).run(...params);
}

function saveDb() {
  // No-op — better-sqlite3 writes synchronously to the WAL on every commit.
}

function debugUser(userId) {
  const all = query('SELECT id, phone, child_name FROM users');
  console.log('[DEBUG] All users:', all, 'looking for:', userId);
}

module.exports = { getDb, query, queryOne, run, runNoSave, saveDb, debugUser };
