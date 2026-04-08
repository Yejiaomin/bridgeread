const initSqlJs = require('sql.js');
const fs = require('fs');

(async () => {
  const SQL = await initSqlJs();
  const db = new SQL.Database(fs.readFileSync('data/bridgeread.db'));

  console.log('Users:');
  const users = db.exec('SELECT id, phone, child_name, book_start_date FROM users');
  if (users.length) {
    for (const row of users[0].values) {
      console.log(`  User ${row[0]}: phone=${row[1]}, child=${row[2]}, start=${row[3]}`);

      // Debt per date for this user
      const debt = db.exec(`SELECT date, COUNT(*) as debt FROM daily_progress WHERE user_id = ${row[0]} AND done = 0 GROUP BY date ORDER BY date`);
      if (debt.length) {
        const total = debt[0].values.reduce((sum, r) => sum + r[1], 0);
        console.log(`    Total owed: ${total}`);
        for (const d of debt[0].values) {
          console.log(`    ${d[0]}: ${d[1]} owed`);
        }
      } else {
        console.log('    Total owed: 0');
      }

      // Today's modules
      const today = db.exec(`SELECT date, module, done FROM daily_progress WHERE user_id = ${row[0]} ORDER BY date DESC, module LIMIT 8`);
      if (today.length) {
        console.log('    Recent modules:');
        for (const m of today[0].values) {
          console.log(`      ${m[0]} ${m[1]}: ${m[2] ? 'done' : 'owed'}`);
        }
      }
      console.log('');
    }
  }

  db.close();
})();
