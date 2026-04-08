const express = require('express');
const cors = require('cors');
const path = require('path');
const { getDb } = require('./db');

const authRoutes = require('./routes/auth');
const progressRoutes = require('./routes/progress');
const recordingsRoutes = require('./routes/recordings');
const authMiddleware = require('./middleware/auth');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors({ origin: true, credentials: true }));
app.use(express.json());

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
