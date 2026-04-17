require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const express = require('express');
const cors = require('cors');
const path = require('path');
const { getDb } = require('./db');

const authRoutes = require('./routes/auth');
const progressRoutes = require('./routes/progress');
const recordingsRoutes = require('./routes/recordings');
const rankingRoutes = require('./routes/ranking');
const speechEvalRoutes = require('./routes/speech-eval');
const profileRoutes = require('./routes/profile');
const studyroomRoutes = require('./routes/studyroom');
const authMiddleware = require('./middleware/auth');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors({ origin: true, credentials: true }));
app.use(express.json({ limit: '10mb' }));

// Request logger
app.use((req, _res, next) => {
  if (req.path !== '/api/health') {
    console.log(`[${new Date().toLocaleTimeString()}] ${req.method} ${req.path}`);
  }
  next();
});
app.use('/recordings', express.static(path.join(__dirname, 'data', 'recordings')));

// Public
app.use('/api/auth', authRoutes);

// Protected
app.use('/api/progress', authMiddleware, progressRoutes);
app.use('/api/recordings', authMiddleware, recordingsRoutes);
app.use('/api/ranking', authMiddleware, rankingRoutes);
app.use('/api/speech-eval', authMiddleware, speechEvalRoutes);
app.use('/api/profile', authMiddleware, profileRoutes);
app.use('/api/studyroom', authMiddleware, studyroomRoutes);

// Error/loading report (public, no auth)
app.post('/api/report', (req, res) => {
  const { logs, ua, screen, url, time } = req.body;
  const report = { time: time || new Date().toISOString(), ua, screen, url, logs };
  const fs = require('fs');
  const path = require('path');
  const dir = path.join(__dirname, 'data', 'reports');
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  const filename = `report_${Date.now()}.json`;
  fs.writeFileSync(path.join(dir, filename), JSON.stringify(report, null, 2));
  console.log('[Report]', filename, ua?.substring(0, 60));
  res.json({ success: true });
});

// Health check
app.get('/api/health', (_req, res) => {
  res.json({ status: 'ok', time: new Date().toISOString() });
});

// Init DB then start server (only when run directly, not when imported for tests)
if (require.main === module) {
  getDb().then(() => {
    app.listen(PORT, () => {
      console.log(`BridgeRead API running on port ${PORT}`);
    });
  });
}

module.exports = { app, getDb };
