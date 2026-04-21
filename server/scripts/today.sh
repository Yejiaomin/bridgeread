#!/bin/bash
# 今天每个用户做了哪些模块
# Usage: bash today.sh

cd "$(dirname "$0")/.."
node -e "
const Database = require('better-sqlite3');
const { chinaToday, fmtDate } = require('./lib/china_time');
const today = fmtDate(chinaToday());

const db = new Database('data/bridgeread.db', { readonly: true });
const rows = db.prepare(\`
  SELECT u.id, u.child_name,
    MAX(CASE WHEN dp.module='recap'  AND dp.done=1 THEN 1 ELSE 0 END) as recap,
    MAX(CASE WHEN dp.module='reader' AND dp.done=1 THEN 1 ELSE 0 END) as reader,
    MAX(CASE WHEN dp.module='quiz'   AND dp.done=1 THEN 1 ELSE 0 END) as quiz,
    MAX(CASE WHEN dp.module='listen' AND dp.done=1 THEN 1 ELSE 0 END) as listen,
    SUM(dp.stars) as today_stars
  FROM users u
  LEFT JOIN daily_progress dp ON dp.user_id=u.id AND dp.date=?
  GROUP BY u.id
  ORDER BY u.id
\`).all(today);

console.log('今日(' + today + ') 用户活动:');
console.log('');
console.log('id | child  | recap | story | game | listen | today_stars');
console.log('---+--------+-------+-------+------+--------+------------');
let activeCount = 0;
rows.forEach(r => {
  const total = (r.recap||0)+(r.reader||0)+(r.quiz||0)+(r.listen||0);
  if (total > 0) activeCount++;
  const m = (n) => n ? '✓' : '·';
  console.log([r.id, r.child_name||'-', m(r.recap), m(r.reader), m(r.quiz), m(r.listen),
               r.today_stars||0].join(' | '));
});
console.log('');
console.log('今日活跃: ' + activeCount + '/' + rows.length);
"
