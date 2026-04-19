// Timezone-safe China time helpers.
// All logic uses Asia/Shanghai via Intl.DateTimeFormat so behavior is
// independent of the Node process timezone (UTC, China, US, etc).
// Date objects returned represent midnight UTC of the China date — using
// UTC midnight makes downstream date math (getUTCDate/setUTCDate/getUTCDay)
// consistent across server timezones.

const TZ = 'Asia/Shanghai';
const _chinaDateFmt = new Intl.DateTimeFormat('en-CA', {
  timeZone: TZ,
  year: 'numeric', month: '2-digit', day: '2-digit',
});

function chinaTodayStr() {
  return _chinaDateFmt.format(new Date());  // "YYYY-MM-DD"
}

function parseDate(str) {
  // "YYYY-MM-DD" → Date at midnight UTC
  const [y, m, d] = str.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d));
}

function chinaToday() {
  return parseDate(chinaTodayStr());
}

function fmtDate(d) {
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth()+1).padStart(2,'0')}-${String(d.getUTCDate()).padStart(2,'0')}`;
}

module.exports = { TZ, chinaTodayStr, chinaToday, parseDate, fmtDate };
