#!/bin/bash
# 列出所有用户 + 注册日期 + 星星 + 当前书本进度
# Usage: bash users.sh

cd "$(dirname "$0")/.."
node -e "
const initSqlJs = require('sql.js');
const fs = require('fs');
initSqlJs().then(SQL => {
  const db = new SQL.Database(fs.readFileSync('data/bridgeread.db'));
  const users = db.exec(\`
    SELECT u.id, u.phone, u.child_name, u.book_start_date, u.total_stars,
           u.last_active_date,
           (SELECT COUNT(*) FROM daily_progress WHERE user_id=u.id AND done=1) as done_count,
           (SELECT COUNT(DISTINCT date) FROM daily_progress WHERE user_id=u.id AND done=1) as active_days
    FROM users u
    ORDER BY u.id
  \`)[0];
  if (!users) { console.log('No users'); return; }
  console.log('总用户数:', users.values.length);
  console.log('');
  console.log('id | phone | child | reg_date | stars | done_modules | active_days | last_active');
  console.log('---+-------+-------+----------+-------+--------------+-------------+------------');
  users.values.forEach(v => {
    const [id, phone, name, regDate, stars, lastActive, done, activeDays] = v;
    const phoneShort = phone ? phone.slice(0, 3) + '****' + phone.slice(-4) : '-';
    console.log([id, phoneShort, name || '-', regDate || '-',
                 stars || 0, done || 0, activeDays || 0, lastActive || '-'].join(' | '));
  });
});
"
