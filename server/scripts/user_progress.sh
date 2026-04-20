#!/bin/bash
# 单个用户完整进度（按日期）
# Usage: bash user_progress.sh <userId>

if [ -z "$1" ]; then
  echo "Usage: bash user_progress.sh <userId>"
  exit 1
fi

cd "$(dirname "$0")/.."
node -e "
const initSqlJs = require('sql.js');
const fs = require('fs');
const userId = parseInt('$1');

initSqlJs().then(SQL => {
  const db = new SQL.Database(fs.readFileSync('data/bridgeread.db'));

  const u = db.exec('SELECT id, phone, child_name, book_start_date, total_stars, last_active_date FROM users WHERE id=?', [userId])[0];
  if (!u) { console.log('User ' + userId + ' not found'); return; }
  const [id, phone, name, regDate, stars, lastActive] = u.values[0];
  console.log('=== User ' + id + ' (' + (name||'-') + ') ===');
  console.log('  phone:', phone);
  console.log('  注册日:', regDate);
  console.log('  总星星:', stars);
  console.log('  最后活跃:', lastActive || '-');
  console.log('');

  const r = db.exec(\`
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
  \`, [userId])[0];

  if (!r) { console.log('  no progress yet'); return; }
  console.log('date | recap | story | game | listen | phonics | recording | stars');
  console.log('-----+-------+-------+------+--------+---------+-----------+------');
  r.values.forEach(v => {
    const [date, recap, reader, quiz, listen, phonics, recording, ds] = v;
    const m = (n) => n ? '✓' : '·';
    console.log([date, m(recap), m(reader), m(quiz), m(listen), m(phonics), m(recording), ds||0].join(' | '));
  });
});
"
