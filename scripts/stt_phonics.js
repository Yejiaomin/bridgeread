#!/usr/bin/env node
/**
 * Use Google Speech-to-Text to get precise word-level timestamps
 * from the phonics chant video audio.
 * Splits audio into <1min segments to use sync API.
 */

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const FFMPEG = 'C:/Users/llc88/AppData/Local/Microsoft/WinGet/Packages/Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe/ffmpeg-8.1-full_build/bin/ffmpeg.exe';
const INPUT = path.join(__dirname, '..', '_temp_phonics_full.mp3');
const OUTPUT_JSON = path.join(__dirname, '..', '_temp_stt_result.json');

const envPath = path.join(__dirname, '..', '.env');
const env = fs.readFileSync(envPath, 'utf8');
const apiKey = env.match(/GOOGLE_CLOUD_API_KEY=(.+)/)?.[1]?.trim();
if (!apiKey) { console.error('No API key'); process.exit(1); }

// Split audio into 55-second segments (under 1-min sync limit)
const SEGMENT_DURATION = 55;
const TOTAL_DURATION = 263;
const segments = [];
for (let start = 0; start < TOTAL_DURATION; start += SEGMENT_DURATION) {
  segments.push({ start, duration: Math.min(SEGMENT_DURATION, TOTAL_DURATION - start) });
}

async function processSegment(seg, index) {
  const flacPath = path.join(__dirname, '..', `_temp_seg_${index}.flac`);

  // Convert segment to FLAC
  execSync(
    `"${FFMPEG}" -y -ss ${seg.start} -t ${seg.duration} -i "${INPUT}" -ac 1 -ar 16000 "${flacPath}"`,
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
    console.error(`Segment ${index} error:`, data.error.message);
    return [];
  }

  // Extract words and adjust timestamps to absolute time
  const words = [];
  for (const r of data.results || []) {
    const alt = r.alternatives?.[0];
    if (!alt?.words) continue;
    for (const w of alt.words) {
      const startSec = parseFloat(w.startTime?.replace('s', '') || '0') + seg.start;
      const endSec = parseFloat(w.endTime?.replace('s', '') || '0') + seg.start;
      words.push({
        word: w.word,
        start: startSec,
        end: endSec,
        duration: endSec - startSec,
      });
    }
  }
  return words;
}

async function main() {
  console.log(`Processing ${segments.length} segments...\n`);

  const allWords = [];
  for (let i = 0; i < segments.length; i++) {
    const seg = segments[i];
    console.log(`Segment ${i + 1}/${segments.length}: ${seg.start}s - ${seg.start + seg.duration}s`);
    const words = await processSegment(seg, i);
    allWords.push(...words);
    console.log(`  → ${words.length} words found`);
  }

  console.log(`\n=== Total: ${allWords.length} words/sounds ===\n`);
  for (const w of allWords) {
    const mins = Math.floor(w.start / 60);
    const secs = (w.start % 60).toFixed(2);
    console.log(`  ${mins}:${secs.padStart(5, '0')}  "${w.word}" (${(w.duration * 1000).toFixed(0)}ms)`);
  }

  fs.writeFileSync(OUTPUT_JSON, JSON.stringify(allWords, null, 2));
  console.log(`\nSaved to ${OUTPUT_JSON}`);
}

main().catch(e => { console.error(e); process.exit(1); });
