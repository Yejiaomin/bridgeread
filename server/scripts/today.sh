#!/bin/bash
# 今天每个用户做了哪些模块
# Usage: bash today.sh

cd "$(dirname "$0")/.."
node -e "
const initSqlJs = require('sql.js');
const fs = require('fs');
const { chinaToday, fmtDate } = require('./lib/china_time');
const today = fmtDate(chinaToday());

initSqlJs().then(SQL => {
  const db = new SQL.Database(fs.readFileSync('data/bridgeread.db'));
  console.log('今日(' + today + ') 用户活动:');
  console.log('');

  const r = db.exec(\`
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
  \`, [today]);

  if (!r[0]) { console.log('No users'); return; }
  console.log('id | child | recap | story | game | listen | today_stars');
  console.log('---+-------+-------+-------+------+--------+------------');
  let activeCount = 0;
  r[0].values.forEach(v => {
    const [id, name, recap, reader, quiz, listen, stars] = v;
    const total = (recap||0)+(reader||0)+(quiz||0)+(listen||0);
    if (total > 0) activeCount++;
    const m = (n) => n ? '✓' : '·';
    console.log([id, name||'-', m(recap), m(reader), m(quiz), m(listen), stars||0].join(' | '));
  });
  console.log('');
  console.log('今日活跃: ' + activeCount + '/' + r[0].values.length);
});
"
