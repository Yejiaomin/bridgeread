const initSqlJs = require('sql.js');
const fs = require('fs');
const path = require('path');

const DB_PATH = path.join(__dirname, 'data', 'bridgeread.db');

let db;

async function getDb() {
  if (db) return db;

  const SQL = await initSqlJs();

  // Load existing DB or create new
  if (fs.existsSync(DB_PATH)) {
    const buffer = fs.readFileSync(DB_PATH);
    db = new SQL.Database(buffer);
  } else {
    db = new SQL.Database();
  }

  // Create tables
  db.run(`
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
    )
  `);

  db.run(`
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
    )
  `);

  db.run(`
    CREATE TABLE IF NOT EXISTS recordings (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL,
      date TEXT NOT NULL,
      lesson_id TEXT NOT NULL,
      sentence TEXT,
      file_path TEXT NOT NULL,
      created_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY (user_id) REFERENCES users(id)
    )
  `);

  db.run(`
    CREATE TABLE IF NOT EXISTS sms_codes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      phone TEXT NOT NULL,
      code TEXT NOT NULL,
      expires_at TEXT NOT NULL,
      used INTEGER DEFAULT 0,
      created_at TEXT DEFAULT (datetime('now'))
    )
  `);

  // Add profile columns to users (safe to re-run, uses try/catch)
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
    try { db.run(`ALTER TABLE users ADD COLUMN ${col} ${def}`); } catch (_) {}
  }

  db.run(`
    CREATE TABLE IF NOT EXISTS study_room (
      user_id INTEGER PRIMARY KEY,
      placed_items TEXT DEFAULT '{}',
      treasure_box_items TEXT DEFAULT '[]',
      equipped_accessory TEXT DEFAULT '',
      gacha_date TEXT,
      gacha_count INTEGER DEFAULT 0,
      today_eggy TEXT DEFAULT '',
      FOREIGN KEY (user_id) REFERENCES users(id)
    )
  `);
  // Add today_eggy column for existing DBs
  try { db.run("ALTER TABLE study_room ADD COLUMN today_eggy TEXT DEFAULT ''"); } catch (_) {}

  db.run(`
    CREATE TABLE IF NOT EXISTS weekly_groups (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      week_start TEXT NOT NULL,
      created_at TEXT DEFAULT (datetime('now'))
    )
  `);

  db.run(`
    CREATE TABLE IF NOT EXISTS weekly_group_members (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      group_id INTEGER NOT NULL,
      user_id INTEGER,
      fake_name TEXT,
      fake_stars INTEGER DEFAULT 0,
      avatar_month INTEGER DEFAULT 1,
      FOREIGN KEY (group_id) REFERENCES weekly_groups(id),
      FOREIGN KEY (user_id) REFERENCES users(id)
    )
  `);

  // Auto-save every 30 seconds
  setInterval(() => saveDb(), 30000);

  return db;
}

function saveDb() {
  if (!db) return;
  const data = db.export();
  const buffer = Buffer.from(data);
  fs.writeFileSync(DB_PATH, buffer);
}

// Helper: run query and return rows
function query(sql, params = []) {
  const stmt = db.prepare(sql);
  if (params.length) stmt.bind(params);
  const rows = [];
  while (stmt.step()) rows.push(stmt.getAsObject());
  stmt.free();
  return rows;
}

// Helper: run query and return first row
function queryOne(sql, params = []) {
  const rows = query(sql, params);
  return rows[0] || null;
}

// Helper: run statement (INSERT/UPDATE/DELETE)
function run(sql, params = []) {
  db.run(sql, params);
  saveDb(); // save after writes
  // sql.js returns last_insert_rowid differently
  const stmt = db.prepare("SELECT last_insert_rowid()");
  stmt.step();
  const id = stmt.get()[0];
  stmt.free();
  return { lastInsertRowid: id };
}

// Helper: run statement without saving (for batch operations)
function runNoSave(sql, params = []) {
  db.run(sql, params);
}

// Debug: log userId lookup
function debugUser(userId) {
  const all = query('SELECT id, phone, child_name FROM users');
  console.log('[DEBUG] All users:', all, 'looking for:', userId);
}

module.exports = { getDb, query, queryOne, run, runNoSave, saveDb, debugUser };
