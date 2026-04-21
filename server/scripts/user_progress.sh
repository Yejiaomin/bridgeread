#!/bin/bash
# 单个用户完整进度（按日期）
# Usage: bash user_progress.sh <userId>

if [ -z "$1" ]; then
  echo "Usage: bash user_progress.sh <userId>"
  exit 1
fi

cd "$(dirname "$0")/.."
node -e "
const Database = require('better-sqlite3');
const userId = parseInt('$1');

const db = new Database('data/bridgeread.db', { readonly: true });

const u = db.prepare('SELECT id, phone, child_name, book_start_date, total_stars, last_active_date FROM users WHERE id=?').get(userId);
if (!u) { console.log('User ' + userId + ' not found'); process.exit(0); }
console.log('=== User ' + u.id + ' (' + (u.child_name||'-') + ') ===');
console.log('  phone:', u.phone);
console.log('  注册日:', u.book_start_date);
console.log('  总星星:', u.total_stars);
console.log('  最后活跃:', u.last_active_date || '-');
console.log('');

const rows = db.prepare(\`
  SELECT date,
    MAX(CASE WHEN module='recap'     AND done=1 THEN 1 ELSE 0 END) as recap,
    MAX(CASE WHEN module='reader'    AND done=1 THEN 1 ELSE 0 END) as reader,
    MAX(CASE WHEN module='quiz'      AND done=1 THEN 1 ELSE 0 END) as quiz,
    MAX(CASE WHEN module='listen'    AND done=1 THEN 1 ELSE 0 END) as listen,
    MAX(CASE WHEN module='phonics'   AND done=1 THEN 1 ELSE 0 END) as phonics,
    MAX(CASE WHEN module='recording' AND done=1 THEN 1 ELSE 0 END) as recording,
    SUM(stars) as day_stars
  FROM daily_progress
  WHERE user_id=?
  GROUP BY date
  ORDER BY date DESC
\`).all(userId);

if (rows.length === 0) { console.log('  no progress yet'); process.exit(0); }
console.log('date       | recap | story | game | listen | phonics | recording | stars');
console.log('-----------+-------+-------+------+--------+---------+-----------+------');
const m = (n) => n ? '✓' : '·';
rows.forEach(r => {
  console.log([r.date, m(r.recap), m(r.reader), m(r.quiz), m(r.listen), m(r.phonics), m(r.recording), r.day_stars||0].join(' | '));
});
"
