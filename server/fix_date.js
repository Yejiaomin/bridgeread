const initSqlJs = require('sql.js');
const fs = require('fs');

(async () => {
  const SQL = await initSqlJs();
  const buf = fs.readFileSync('data/bridgeread.db');
  const db = new SQL.Database(buf);

  // Use China time (UTC+8) for consistency with app
  const now = new Date();
  const utcMs = now.getTime() + now.getTimezoneOffset() * 60000;
  const chinaMs = utcMs + 8 * 3600000;
  const china = new Date(chinaMs);
  china.setDate(china.getDate() - 5);
  const dateStr = `${china.getFullYear()}-${String(china.getMonth()+1).padStart(2,'0')}-${String(china.getDate()).padStart(2,'0')}`;
  console.log('Setting book_start_date to:', dateStr, '(China time, 5 days ago)');
  db.run("UPDATE users SET book_start_date = ? WHERE id = 1", [dateStr]);

  const r = db.exec('SELECT id, phone, child_name, book_start_date FROM users');
  console.log('Updated:', JSON.stringify(r, null, 2));

  fs.writeFileSync('data/bridgeread.db', Buffer.from(db.export()));
  db.close();
  console.log('Done!');
})();
