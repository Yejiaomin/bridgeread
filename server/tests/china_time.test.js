// Verifies china_time helpers behave correctly regardless of process timezone.
// The original chinaToday() relied on setHours/getDate which use the host
// timezone — broke on non-UTC, non-China servers around midnight.

const { chinaToday, chinaTodayStr, parseDate, fmtDate } = require('../lib/china_time');

describe('china_time', () => {
  test('chinaTodayStr is YYYY-MM-DD format', () => {
    expect(chinaTodayStr()).toMatch(/^\d{4}-\d{2}-\d{2}$/);
  });

  test('parseDate returns UTC midnight Date', () => {
    const d = parseDate('2026-04-19');
    expect(d.getUTCFullYear()).toBe(2026);
    expect(d.getUTCMonth()).toBe(3);  // 0-indexed = April
    expect(d.getUTCDate()).toBe(19);
    expect(d.getUTCHours()).toBe(0);
    expect(d.getUTCMinutes()).toBe(0);
  });

  test('fmtDate roundtrips with parseDate', () => {
    expect(fmtDate(parseDate('2026-04-19'))).toBe('2026-04-19');
    expect(fmtDate(parseDate('2026-12-31'))).toBe('2026-12-31');
    expect(fmtDate(parseDate('2026-01-01'))).toBe('2026-01-01');
  });

  test('chinaToday returns same string as chinaTodayStr', () => {
    expect(fmtDate(chinaToday())).toBe(chinaTodayStr());
  });

  test('chinaToday is timezone-safe — matches Asia/Shanghai date', () => {
    // Compare against an independent computation using the same Intl trick
    const expected = new Intl.DateTimeFormat('en-CA', {
      timeZone: 'Asia/Shanghai',
      year: 'numeric', month: '2-digit', day: '2-digit',
    }).format(new Date());
    expect(chinaTodayStr()).toBe(expected);
  });

  test('parseDate + setUTCDate arithmetic crosses month boundary correctly', () => {
    const d = parseDate('2026-01-31');
    d.setUTCDate(d.getUTCDate() + 1);
    expect(fmtDate(d)).toBe('2026-02-01');
  });

  test('parseDate + setUTCDate arithmetic crosses year boundary', () => {
    const d = parseDate('2026-12-31');
    d.setUTCDate(d.getUTCDate() + 1);
    expect(fmtDate(d)).toBe('2027-01-01');
  });
});
