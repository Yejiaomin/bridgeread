// Whisper-tiny speech recognition using transformers.js
// Runs entirely in the browser — no API calls needed after model download

let whisperPipeline = null;
let whisperLoading = false;
let whisperLoadPromise = null;
let readAudioFn = null;

async function initWhisper() {
  if (whisperPipeline) return whisperPipeline;
  if (whisperLoadPromise) return whisperLoadPromise;

  whisperLoading = true;
  whisperLoadPromise = (async () => {
    try {
      const mod = await import(
        'https://cdn.jsdelivr.net/npm/@huggingface/transformers@3.4.1'
      );
      whisperPipeline = await mod.pipeline(
        'automatic-speech-recognition',
        'Xenova/whisper-tiny.en',
      );
      readAudioFn = mod.read_audio;
      console.log('[Whisper] Model loaded and cached');
    } catch (e) {
      console.error('[Whisper] Failed to load model:', e);
      whisperPipeline = null;
    }
    whisperLoading = false;
    return whisperPipeline;
  })();

  return whisperLoadPromise;
}

// Transcribe audio and score against reference text
// Returns: { text: string, score: 0-100, details: { similarity, wordOrder, confidence } }
async function transcribeAndScore(audioBlobUrl, referenceText) {
  try {
    const recognizer = await initWhisper();
    if (!recognizer) {
      return { text: '', score: -1, error: 'Model not loaded' };
    }

    // Fetch audio from the blob URL returned by record package
    // (Now recording in WAV format at 16kHz for best compatibility)
    let audioData;
    try {
      audioData = await readAudioFn(audioBlobUrl, 16000);
    } catch (e1) {
      console.log('[Whisper] read_audio failed, trying AudioContext...', e1);
      // Fallback: manual decode
      const resp = await fetch(audioBlobUrl);
      const buf = await resp.arrayBuffer();
      const ctx = new AudioContext();
      const decoded = await ctx.decodeAudioData(buf);
      const raw = decoded.getChannelData(0);
      // Resample to 16kHz if needed
      if (decoded.sampleRate === 16000) {
        audioData = raw;
      } else {
        const ratio = 16000 / decoded.sampleRate;
        const newLen = Math.round(raw.length * ratio);
        audioData = new Float32Array(newLen);
        for (let i = 0; i < newLen; i++) {
          const si = i / ratio;
          const idx = Math.floor(si);
          const f = si - idx;
          audioData[i] = idx + 1 < raw.length ? raw[idx] * (1 - f) + raw[idx + 1] * f : raw[idx] || 0;
        }
      }
      ctx.close();
    }

    // Debug volume
    let maxVal = 0, sumAbs = 0;
    for (let i = 0; i < audioData.length; i++) {
      const v = Math.abs(audioData[i]);
      if (v > maxVal) maxVal = v;
      sumAbs += v;
    }
    console.log(`[Whisper] Audio: ${audioData.length} samples, ${(audioData.length/16000).toFixed(1)}s`);
    console.log(`[Whisper] Volume: max=${maxVal.toFixed(4)}, avg=${(sumAbs/audioData.length).toFixed(4)}`);

    // Transcribe
    const result = await recognizer(audioData, {
      return_timestamps: false,
    });

    const transcribed = (result.text || '').trim();
    const reference = (referenceText || '').trim();

    // Three-layer scoring
    const details = calculateDetailedScore(transcribed, reference);

    console.log('[Whisper] Reference:', reference);
    console.log('[Whisper] Transcribed:', transcribed);
    console.log('[Whisper] Details:', JSON.stringify(details));

    return {
      text: transcribed,
      score: details.finalScore,
      details: details
    };
  } catch (e) {
    console.error('[Whisper] Transcription error:', e);
    return { text: '', score: -1, error: e.toString() };
  }
}

function calculateDetailedScore(transcribed, reference) {
  const cleanText = (s) => s.toLowerCase().replace(/[^a-z0-9\s']/g, '').trim();
  const refClean = cleanText(reference);
  const spokenClean = cleanText(transcribed);

  const refWords = refClean.split(/\s+/).filter(w => w.length > 0);
  const spokenWords = spokenClean.split(/\s+/).filter(w => w.length > 0);

  if (refWords.length === 0) return { finalScore: 0, coverage: 0, matchedWords: 0, totalWords: 0 };
  if (spokenWords.length === 0) return { finalScore: 0, coverage: 0, matchedWords: 0, totalWords: refWords.length };

  // ── Step 1: Word Coverage (base score) ──
  // Find matched words with fuzzy matching (lenient for children's speech)
  let matchedWords = 0;
  const matchedIndices = []; // spoken indices of matched words, for order check
  const usedSpoken = new Set();

  for (const refWord of refWords) {
    let bestMatch = -1;
    let bestDist = Infinity;

    for (let j = 0; j < spokenWords.length; j++) {
      if (usedSpoken.has(j)) continue;
      const dist = levenshtein(refWord, spokenWords[j]);
      // Lenient thresholds for children: short words allow 1 edit, longer words allow 2
      const threshold = refWord.length <= 2 ? 0 : refWord.length <= 4 ? 1 : 2;
      if (dist <= threshold && dist < bestDist) {
        bestDist = dist;
        bestMatch = j;
      }
    }

    if (bestMatch >= 0) {
      matchedWords++;
      matchedIndices.push(bestMatch);
      usedSpoken.add(bestMatch);
    }
  }

  // Base score = word coverage percentage, generous for children's learning
  const coverage = matchedWords / refWords.length;
  let baseScore;
  if (spokenWords.length === 0) {
    baseScore = 0;
  } else if (coverage >= 0.8) {
    baseScore = 90 + Math.round(coverage * 10); // 90-100
  } else if (coverage >= 0.5) {
    baseScore = 75 + Math.round((coverage - 0.5) / 0.3 * 15); // 75-90
  } else if (coverage > 0) {
    baseScore = 55 + Math.round(coverage / 0.5 * 20); // 55-75
  } else {
    baseScore = spokenWords.length > 0 ? 45 : 0; // spoke but nothing matched
  }

  // ── Step 2: Deductions ──

  // 2a. Word order penalty (up to -5, gentle for kids)
  let orderPenalty = 0;
  if (matchedIndices.length >= 3) {
    let outOfOrder = 0;
    for (let i = 1; i < matchedIndices.length; i++) {
      if (matchedIndices[i] <= matchedIndices[i - 1]) outOfOrder++;
    }
    const orderErrorRate = outOfOrder / (matchedIndices.length - 1);
    orderPenalty = Math.round(orderErrorRate * 5);
  }

  // 2b. Extra words penalty (up to -5) — very gentle, kids ramble
  const extraWords = Math.max(0, spokenWords.length - refWords.length);
  const extraPenalty = Math.min(5, Math.round(extraWords / refWords.length * 5));

  // 2c. Pronunciation penalty removed — Whisper mis-transcription ≠ bad pronunciation
  const pronPenalty = 0;

  const totalPenalty = orderPenalty + extraPenalty + pronPenalty;
  const finalScore = Math.max(0, Math.min(100, baseScore - totalPenalty));

  console.log(`[Score] base=${baseScore} (${matchedWords}/${refWords.length}), orderPen=-${orderPenalty}, extraPen=-${extraPenalty}, pronPen=-${pronPenalty}, final=${finalScore}`);

  return {
    finalScore: finalScore,
    coverage: Math.round(coverage * 100),
    matchedWords: matchedWords,
    totalWords: refWords.length,
    orderPenalty: orderPenalty,
    extraPenalty: extraPenalty,
    pronPenalty: pronPenalty,
  };
}

// Levenshtein distance
function levenshtein(a, b) {
  if (a === b) return 0;
  if (!a.length) return b.length;
  if (!b.length) return a.length;

  const matrix = [];
  for (let i = 0; i <= b.length; i++) matrix[i] = [i];
  for (let j = 0; j <= a.length; j++) matrix[0][j] = j;

  for (let i = 1; i <= b.length; i++) {
    for (let j = 1; j <= a.length; j++) {
      matrix[i][j] = b[i - 1] === a[j - 1]
        ? matrix[i - 1][j - 1]
        : Math.min(matrix[i - 1][j - 1] + 1, matrix[i][j - 1] + 1, matrix[i - 1][j] + 1);
    }
  }
  return matrix[b.length][a.length];
}

// Pre-load model in background
function preloadWhisper() {
  initWhisper().then(() => {
    console.log('[Whisper] Pre-loaded successfully');
  }).catch(() => {
    console.log('[Whisper] Pre-load failed, will retry on first use');
  });
}

// ── Separate mic capture for Whisper ──
let _whisperStream = null;
let _whisperRecorder = null;
let _whisperChunks = [];

async function startWhisperCapture() {
  try {
    _whisperChunks = [];
    _whisperStream = await navigator.mediaDevices.getUserMedia({ audio: true });
    _whisperRecorder = new MediaRecorder(_whisperStream);
    _whisperRecorder.ondataavailable = (e) => {
      if (e.data && e.data.size > 0) _whisperChunks.push(e.data);
    };
    _whisperRecorder.start();
    console.log('[Whisper] Capture started');
  } catch (e) {
    console.error('[Whisper] Capture start error:', e);
  }
}

function stopWhisperCapture() {
  return new Promise((resolve) => {
    if (!_whisperRecorder || _whisperRecorder.state === 'inactive') {
      resolve(null);
      return;
    }
    _whisperRecorder.onstop = () => {
      const blob = _whisperChunks.length > 0
        ? new Blob(_whisperChunks, { type: _whisperChunks[0].type })
        : null;
      if (blob) console.log(`[Whisper] Captured: ${blob.size} bytes`);
      // Cleanup
      if (_whisperStream) _whisperStream.getTracks().forEach(t => t.stop());
      _whisperStream = null;
      _whisperRecorder = null;
      _whisperChunks = [];
      window._lastRecordingBlob = blob;
      resolve(blob);
    };
    _whisperRecorder.stop();
  });
}

window.startWhisperCapture = startWhisperCapture;
window.stopWhisperCapture = stopWhisperCapture;

// Expose to Flutter/Dart
window.transcribeAndScore = transcribeAndScore;
window.preloadWhisper = preloadWhisper;
window.isWhisperReady = () => whisperPipeline !== null;
window.isWhisperLoading = () => whisperLoading;
