const express = require('express');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const db = require('../db');

const router = express.Router();

// Storage config: save to server/data/recordings/{userId}/
const storage = multer.diskStorage({
  destination: (req, _file, cb) => {
    const dir = path.join(__dirname, '..', 'data', 'recordings', String(req.userId));
    fs.mkdirSync(dir, { recursive: true });
    cb(null, dir);
  },
  filename: (_req, file, cb) => {
    const name = `${Date.now()}_${file.originalname}`;
    cb(null, name);
  },
});

const upload = multer({
  storage,
  limits: { fileSize: 5 * 1024 * 1024 }, // 5MB max
  fileFilter: (_req, file, cb) => {
    if (file.mimetype.startsWith('audio/')) cb(null, true);
    else cb(new Error('只能上传音频文件'));
  },
});

// ── Upload recording ────────────────────────────────────────────────────────
router.post('/upload', upload.single('audio'), (req, res) => {
  const userId = req.userId;
  const { date, lessonId, sentence } = req.body;

  if (!req.file) {
    return res.status(400).json({ error: '请上传音频文件' });
  }

  const filePath = `recordings/${userId}/${req.file.filename}`;

  db.prepare(
    'INSERT INTO recordings (user_id, date, lesson_id, sentence, file_path) VALUES (?, ?, ?, ?, ?)'
  ).run(userId, date || new Date().toISOString().slice(0, 10), lessonId || '', sentence || '', filePath);

  res.json({ success: true, filePath });
});

// ── Get recordings for a user ───────────────────────────────────────────────
router.get('/', (req, res) => {
  const userId = req.userId;
  const { date, lessonId } = req.query;

  let query = 'SELECT * FROM recordings WHERE user_id = ?';
  const params = [userId];

  if (date) { query += ' AND date = ?'; params.push(date); }
  if (lessonId) { query += ' AND lesson_id = ?'; params.push(lessonId); }
  query += ' ORDER BY created_at DESC';

  const recordings = db.prepare(query).all(...params);
  res.json({ success: true, recordings });
});

module.exports = router;
