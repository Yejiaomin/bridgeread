#!/usr/bin/env node
/**
 * Use Google STT to transcribe the xueliyingyu phonics audio
 * and find timestamps for each letter's phoneme sound.
 * Splits 35-min audio into 55-second segments for sync API.
 */

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const FFMPEG = 'C:/Users/llc88/AppData/Local/Microsoft/WinGet/Packages/Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe/ffmpeg-8.1-full_build/bin/ffmpeg.exe';
const INPUT = path.join(__dirname, '..', '_temp_xueliyingyu.mp3');
const OUTPUT_JSON = path.join(__dirname, '..', '_temp_stt_xly.json');

const envPath = path.join(__dirname, '..', '.env');
const env = fs.readFileSync(envPath, 'utf8');
const apiKey = env.match(/GOOGLE_CLOUD_API_KEY=(.+)/)?.[1]?.trim();
if (!apiKey) { console.error('No API key'); process.exit(1); }

const SEGMENT_DURATION = 55;
const TOTAL_DURATION = 35 * 60 + 48; // 35:48

async function processSegment(segStart, index, total) {
  const dur = Math.min(SEGMENT_DURATION, TOTAL_DURATION - segStart);
  const flacPath = path.join(__dirname, '..', `_temp_xly_seg_${index}.flac`);

  execSync(
    `"${FFMPEG}" -y -ss ${segStart} -t ${dur} -i "${INPUT}" -ac 1 -ar 16000 "${flacPath}"`,
    { stdio: 'pipe' }
  );

  const audioBytes = fs.readFileSync(flacPath).toString('base64');

  const res = await fetch(
    `https://speech.googleapis.com/v1/speech:recognize?key=${apiKey}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        config: {
          encoding: 'FLAC',
          sampleRateHertz: 16000,
          languageCode: 'en-US',
          enableWordTimeOffsets: true,
          model: 'latest_long',
          useEnhanced: true,
        },
        audio: { content: audioBytes },
      }),
    }
  );

  const data = await res.json();
  fs.unlinkSync(flacPath);

  if (data.error) {
    console.error(`  Seg ${index} error: ${data.error.message}`);
    return [];
  }

  const words = [];
  for (const r of data.results || []) {
    const alt = r.alternatives?.[0];
    if (!alt?.words) continue;
    for (const w of alt.words) {
      const s = parseFloat(w.startTime?.replace('s', '') || '0') + segStart;
      const e = parseFloat(w.endTime?.replace('s', '') || '0') + segStart;
      words.push({ word: w.word, start: s, end: e, duration: e - s });
    }
  }
  return words;
}

async function main() {
  const segments = [];
  for (let s = 0; s < TOTAL_DURATION; s += SEGMENT_DURATION) segments.push(s);

  console.log(`Processing ${segments.length} segments (~35 min audio)...\n`);

  const allWords = [];
  for (let i = 0; i < segments.length; i++) {
    const segStart = segments[i];
    const mm = Math.floor(segStart / 60);
    const ss = segStart % 60;
    process.stdout.write(`  [${i + 1}/${segments.length}] ${mm}:${String(ss).padStart(2, '0')} `);
    const words = await processSegment(segStart, i, segments.length);
    allWords.push(...words);
    console.log(`→ ${words.length} words`);
  }

  console.log(`\nTotal: ${allWords.length} words\n`);

  // Print all words with timestamps
  for (const w of allWords) {
    const mm = Math.floor(w.start / 60);
    const ss = (w.start % 60).toFixed(1);
    console.log(`  ${mm}:${ss.padStart(4, '0')}  "${w.word}"`);
  }

  fs.writeFileSync(OUTPUT_JSON, JSON.stringify(allWords, null, 2));
  console.log(`\nSaved to ${OUTPUT_JSON}`);
}

main().catch(e => { console.error(e); process.exit(1); });
