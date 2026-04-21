#!/bin/bash
# 列出所有用户 + 注册日期 + 星星 + 当前书本进度
# Usage: bash users.sh

cd "$(dirname "$0")/.."
node -e "
const Database = require('better-sqlite3');
const db = new Database('data/bridgeread.db', { readonly: true });
const users = db.prepare(\`
  SELECT u.id, u.phone, u.child_name, u.book_start_date, u.total_stars,
         u.last_active_date,
         (SELECT COUNT(*) FROM daily_progress WHERE user_id=u.id AND done=1) as done_count,
         (SELECT COUNT(DISTINCT date) FROM daily_progress WHERE user_id=u.id AND done=1) as active_days
  FROM users u
  ORDER BY u.id
\`).all();
console.log('总用户数:', users.length);
console.log('');
console.log('id | phone        | child | reg_date   | stars | done | active | last_active');
console.log('---+--------------+-------+------------+-------+------+--------+------------');
users.forEach(u => {
  const phone = u.phone || '';
  const phoneShort = phone ? phone.slice(0, 3) + '****' + phone.slice(-4) : '-';
  console.log([u.id, phoneShort, u.child_name || '-', u.book_start_date || '-',
               u.total_stars || 0, u.done_count || 0, u.active_days || 0,
               u.last_active_date || '-'].join(' | '));
});
"
