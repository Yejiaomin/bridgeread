const express = require('express');
const { queryOne, run } = require('../db');

const router = express.Router();

// ── Ensure study_room row exists for user ──────────────────────────────────
function ensureRow(userId) {
  const existing = queryOne('SELECT user_id FROM study_room WHERE user_id = ?', [userId]);
  if (!existing) {
    run('INSERT INTO study_room (user_id) VALUES (?)', [userId]);
  }
}

// ── Get study room data ────────────────────────────────────────────────────
router.get('/', (req, res) => {
  ensureRow(req.userId);
  const row = queryOne('SELECT * FROM study_room WHERE user_id = ?', [req.userId]);

  res.json({
    success: true,
    studyRoom: {
      placedItems: row.placed_items ?? '{}',
      treasureBoxItems: row.treasure_box_items ?? '[]',
      equippedAccessory: row.equipped_accessory ?? '',
      gachaDate: row.gacha_date ?? '',
      gachaCount: row.gacha_count ?? 0,
      todayEggy: row.today_eggy ?? '',
    },
  });
});

// ── Update study room data ─────────────────────────────────────────────────
router.put('/', (req, res) => {
  ensureRow(req.userId);
  const { placedItems, treasureBoxItems, equippedAccessory, gachaDate, gachaCount } = req.body;
  const sets = [], params = [];

  if (placedItems !== undefined) { sets.push('placed_items = ?'); params.push(placedItems); }
  if (treasureBoxItems !== undefined) { sets.push('treasure_box_items = ?'); params.push(treasureBoxItems); }
  if (equippedAccessory !== undefined) { sets.push('equipped_accessory = ?'); params.push(equippedAccessory); }
  if (gachaDate !== undefined) { sets.push('gacha_date = ?'); params.push(gachaDate); }
  if (gachaCount !== undefined) { sets.push('gacha_count = ?'); params.push(gachaCount); }
  if (req.body.todayEggy !== undefined) { sets.push('today_eggy = ?'); params.push(req.body.todayEggy); }

  if (sets.length === 0) return res.status(400).json({ error: '没有要更新的字段' });

  params.push(req.userId);
  run(`UPDATE study_room SET ${sets.join(', ')} WHERE user_id = ?`, params);

  res.json({ success: true });
});

module.exports = router;
