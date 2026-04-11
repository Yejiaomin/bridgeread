const express = require('express');
const router = express.Router();
const https = require('https');
const crypto = require('crypto');

// ── Alibaba Cloud NLS Speech Evaluation ─────────────────────────────────────

const ACCESS_KEY_ID = process.env.ALIYUN_ACCESS_KEY_ID;
const ACCESS_KEY_SECRET = process.env.ALIYUN_ACCESS_KEY_SECRET;
const NLS_APPKEY = process.env.ALIYUN_NLS_APPKEY;

let _cachedToken = null;
let _tokenExpiry = 0;

// Get NLS access token (cached, refreshed before expiry)
async function getToken() {
  if (_cachedToken && Date.now() < _tokenExpiry - 60000) {
    return _cachedToken;
  }

  // Build signature for token request
  const params = {
    AccessKeyId: ACCESS_KEY_ID,
    Action: 'CreateToken',
    Format: 'JSON',
    RegionId: 'ap-southeast-1',
    SignatureMethod: 'HMAC-SHA1',
    SignatureNonce: crypto.randomUUID(),
    SignatureVersion: '1.0',
    Timestamp: new Date().toISOString().replace(/\.\d{3}Z$/, 'Z'),
    Version: '2019-07-17',
  };

  // Sort and encode params
  const sortedKeys = Object.keys(params).sort();
  const canonicalized = sortedKeys
    .map(k => `${encodeURIComponent(k)}=${encodeURIComponent(params[k])}`)
    .join('&');

  const stringToSign = `GET&${encodeURIComponent('/')}&${encodeURIComponent(canonicalized)}`;
  const signature = crypto
    .createHmac('sha1', ACCESS_KEY_SECRET + '&')
    .update(stringToSign)
    .digest('base64');

  const url = `https://nlsmeta.ap-southeast-1.aliyuncs.com/?${canonicalized}&Signature=${encodeURIComponent(signature)}`;

  const result = await fetchJSON(url);
  if (result.Token && result.Token.Id) {
    _cachedToken = result.Token.Id;
    _tokenExpiry = result.Token.ExpireTime * 1000; // convert to ms
    console.log('[NLS] Token obtained, expires:', new Date(_tokenExpiry).toISOString());
    return _cachedToken;
  }
  throw new Error('Failed to get NLS token: ' + JSON.stringify(result));
}

function fetchJSON(url) {
  return new Promise((resolve, reject) => {
    https.get(url, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try { resolve(JSON.parse(data)); }
        catch (e) { reject(new Error('Parse error: ' + data)); }
      });
    }).on('error', reject);
  });
}

// ── POST /api/speech-eval ───────────────────────────────────────────────────
// Body: { audio: base64-encoded WAV, refText: "reference text" }
// Returns: { score, details }
router.post('/', async (req, res) => {
  try {
    const { audio, refText } = req.body;
    if (!audio || !refText) {
      return res.status(400).json({ error: 'audio and refText required' });
    }

    const token = await getToken();
    const audioBuffer = Buffer.from(audio, 'base64');

    // Debug: log audio info
    console.log(`[SpeechEval] Audio size: ${audioBuffer.length} bytes`);
    // Check WAV header
    if (audioBuffer.length > 44 && audioBuffer.toString('ascii', 0, 4) === 'RIFF') {
      const sampleRate = audioBuffer.readUInt32LE(24);
      const bitsPerSample = audioBuffer.readUInt16LE(34);
      const channels = audioBuffer.readUInt16LE(22);
      console.log(`[SpeechEval] WAV: ${sampleRate}Hz, ${bitsPerSample}bit, ${channels}ch`);
    }

    // Call Alibaba Cloud NLS speech recognition via WebSocket
    const result = await evaluateSpeech(token, audioBuffer, refText);
    res.json(result);
  } catch (e) {
    console.error('[SpeechEval] Error:', e.message);
    res.status(500).json({ error: e.message });
  }
});

// ── WebSocket-based speech recognition + text comparison scoring ─────────────
function evaluateSpeech(token, audioBuffer, refText) {
  return new Promise((resolve, reject) => {
    const WebSocket = require('ws');
    const taskId = crypto.randomUUID().replace(/-/g, '');

    const ws = new WebSocket(
      'wss://nls-gateway-ap-southeast-1.aliyuncs.com/ws/v1',
      { headers: { 'X-NLS-Token': token } }
    );

    let transcribedText = '';
    const timeout = setTimeout(() => {
      ws.close();
      reject(new Error('Speech recognition timeout'));
    }, 30000);

    const sendAudio = () => {
      const chunkSize = 3200;
      let offset = 0;
      const sendChunk = () => {
        if (offset >= audioBuffer.length) {
          ws.send(JSON.stringify({
            header: {
              message_id: crypto.randomUUID().replace(/-/g, ''),
              task_id: taskId,
              namespace: 'SpeechRecognizer',
              name: 'StopRecognition',
              appkey: NLS_APPKEY,
            },
          }));
          return;
        }
        const chunk = audioBuffer.slice(offset, offset + chunkSize);
        ws.send(chunk);
        offset += chunkSize;
        setTimeout(sendChunk, 20);
      };
      sendChunk();
    };

    ws.on('open', () => {
      const startMsg = {
        header: {
          message_id: crypto.randomUUID().replace(/-/g, ''),
          task_id: taskId,
          namespace: 'SpeechRecognizer',
          name: 'StartRecognition',
          appkey: NLS_APPKEY,
        },
        payload: {
          format: 'wav',
          sample_rate: 16000,
          enable_inverse_text_normalization: false,
        },
      };
      ws.send(JSON.stringify(startMsg));
      // Don't send audio yet — wait for RecognitionStarted
    });

    ws.on('message', (data) => {
      try {
        const msg = JSON.parse(data.toString());
        const name = msg.header?.name;

        if (name === 'RecognitionStarted') {
          console.log('[SpeechEval] Recognition started, sending audio...');
          sendAudio();
        }
        if (name === 'RecognitionResultChanged') {
          transcribedText = msg.payload?.result || transcribedText;
        }
        if (name === 'RecognitionCompleted') {
          clearTimeout(timeout);
          transcribedText = msg.payload?.result || transcribedText;
          ws.close();

          // Score by comparing transcribed text with reference
          const scoreResult = calculateScore(transcribedText, refText);
          console.log(`[SpeechEval] Ref: "${refText}"`);
          console.log(`[SpeechEval] Got: "${transcribedText}"`);
          console.log(`[SpeechEval] Score: ${scoreResult.score}`);
          resolve(scoreResult);
        }
        if (name === 'TaskFailed') {
          clearTimeout(timeout);
          ws.close();
          reject(new Error('Recognition failed: ' + JSON.stringify(msg)));
        }
      } catch (e) {
        // Binary data, ignore
      }
    });

    ws.on('error', (err) => {
      clearTimeout(timeout);
      reject(err);
    });

    ws.on('close', () => {
      clearTimeout(timeout);
    });
  });
}

// ── Text comparison scoring ─────────────────────────────────────────────────
function calculateScore(transcribed, reference) {
  const clean = (s) => s.toLowerCase().replace(/[^a-z0-9\s']/g, '').trim();
  const refClean = clean(reference);
  const spokenClean = clean(transcribed);
  const refWords = refClean.split(/\s+/).filter(w => w.length > 0);
  const spokenWords = spokenClean.split(/\s+/).filter(w => w.length > 0);

  if (refWords.length === 0) return { score: 0, transcribed, matchedWords: 0, totalWords: 0 };
  if (spokenWords.length === 0) return { score: 0, transcribed, matchedWords: 0, totalWords: refWords.length };

  // Word matching with fuzzy tolerance
  let matched = 0;
  const matchedIndices = [];
  const used = new Set();

  for (const ref of refWords) {
    let best = -1, bestDist = Infinity;
    for (let j = 0; j < spokenWords.length; j++) {
      if (used.has(j)) continue;
      const spoken = spokenWords[j];
      const dist = levenshtein(ref, spoken);
      // Base threshold by word length
      let threshold = ref.length <= 2 ? 0 : ref.length <= 4 ? 1 : 2;
      // Bonus: if first letter matches AND word length is similar, allow more tolerance
      // This helps with ASR approximations like "biscuit" → "basically"
      if (ref[0] === spoken[0] && Math.abs(ref.length - spoken.length) <= 3) {
        threshold = Math.max(threshold, Math.ceil(ref.length * 0.6));
      }
      if (dist <= threshold && dist < bestDist) {
        bestDist = dist;
        best = j;
      }
    }
    if (best >= 0) {
      matched++;
      matchedIndices.push(best);
      used.add(best);
    }
  }

  // Base score = coverage
  const coverage = matched / refWords.length;
  let base = Math.round(coverage * 100);

  // Order penalty
  let orderPen = 0;
  if (matchedIndices.length >= 2) {
    let outOfOrder = 0;
    for (let i = 1; i < matchedIndices.length; i++) {
      if (matchedIndices[i] <= matchedIndices[i - 1]) outOfOrder++;
    }
    orderPen = Math.round((outOfOrder / (matchedIndices.length - 1)) * 15);
  }

  // Extra words penalty
  const extra = Math.max(0, spokenWords.length - refWords.length);
  const extraPen = Math.min(10, Math.round(extra / refWords.length * 10));

  const score = Math.max(0, Math.min(100, base - orderPen - extraPen));

  return {
    score,
    accuracy: Math.round(coverage * 100),
    fluency: 0,
    integrity: Math.round(coverage * 100),
    transcribed,
    matchedWords: matched,
    totalWords: refWords.length,
    details: { base, orderPen, extraPen },
  };
}

function levenshtein(a, b) {
  if (a === b) return 0;
  if (!a.length) return b.length;
  if (!b.length) return a.length;
  const m = [];
  for (let i = 0; i <= b.length; i++) m[i] = [i];
  for (let j = 0; j <= a.length; j++) m[0][j] = j;
  for (let i = 1; i <= b.length; i++)
    for (let j = 1; j <= a.length; j++)
      m[i][j] = b[i-1] === a[j-1] ? m[i-1][j-1] : Math.min(m[i-1][j-1]+1, m[i][j-1]+1, m[i-1][j]+1);
  return m[b.length][a.length];
}

module.exports = router;
