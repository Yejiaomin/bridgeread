#!/usr/bin/env node
/**
 * Use Google STT to analyze original audio and extract page timing.
 * Match STT words to each page's English text to find page boundaries.
 */

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const FFMPEG = 'C:/Users/llc88/AppData/Local/Microsoft/WinGet/Packages/Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe/ffmpeg-8.1-full_build/bin/ffmpeg.exe';

const envPath = path.join(__dirname, '..', '.env');
const env = fs.readFileSync(envPath, 'utf8');
const apiKey = env.match(/GOOGLE_CLOUD_API_KEY=(.+)/)?.[1]?.trim();
if (!apiKey) { console.error('No API key'); process.exit(1); }

const bookDir = process.argv[2] || 'assets/books/03Biscuit_Loves_the_Library';
const lessonFile = process.argv[3] || 'assets/lessons/biscuit_library_book3_day1.json';
const audioFile = path.join(bookDir, 'audio.mp3');

if (!fs.existsSync(audioFile)) { console.error('Audio not found:', audioFile); process.exit(1); }

// Get duration
let durationStr = '';
try { durationStr = execSync(`"${FFMPEG}" -i "${audioFile}" 2>&1`).toString(); } catch (e) { durationStr = e.stdout?.toString() || ''; }
const durMatch = durationStr.match(/Duration: (\d+):(\d+):(\d+\.\d+)/);
const totalDuration = durMatch
  ? parseInt(durMatch[1]) * 3600 + parseInt(durMatch[2]) * 60 + parseFloat(durMatch[3])
  : 0;
console.log(`Audio: ${audioFile} (${totalDuration.toFixed(1)}s)\n`);

// Split into 55-second segments for STT
const SEGMENT_DURATION = 55;

async function processSegment(segStart, index) {
  const dur = Math.min(SEGMENT_DURATION, totalDuration - segStart);
  const flacPath = `_temp_page_seg_${index}.flac`;

  execSync(`"${FFMPEG}" -y -ss ${segStart} -t ${dur} -i "${audioFile}" -ac 1 -ar 16000 "${flacPath}"`, { stdio: 'pipe' });
  const audioBytes = fs.readFileSync(flacPath).toString('base64');

  const res = await fetch(
    `https://speech.googleapis.com/v1/speech:recognize?key=${apiKey}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        config: {
          encoding: 'FLAC', sampleRateHertz: 16000, languageCode: 'en-US',
          enableWordTimeOffsets: true, model: 'latest_long', useEnhanced: true,
        },
        audio: { content: audioBytes },
      }),
    }
  );

  const data = await res.json();
  fs.unlinkSync(flacPath);

  if (data.error) { console.error(`Seg ${index} error:`, data.error.message); return []; }

  const words = [];
  for (const r of data.results || []) {
    const alt = r.alternatives?.[0];
    if (!alt?.words) continue;
    for (const w of alt.words) {
      const s = parseFloat(w.startTime?.replace('s', '') || '0') + segStart;
      const e = parseFloat(w.endTime?.replace('s', '') || '0') + segStart;
      words.push({ word: w.word.toLowerCase(), start: s, end: e });
    }
  }
  return words;
}

async function main() {
  // 1. Run STT
  console.log('Running STT...');
  const allWords = [];
  for (let s = 0, i = 0; s < totalDuration; s += SEGMENT_DURATION, i++) {
    process.stdout.write(`  Segment ${i + 1}... `);
    const words = await processSegment(s, i);
    allWords.push(...words);
    console.log(`${words.length} words`);
  }

  console.log(`\nTotal: ${allWords.length} words\n`);

  // Print timeline
  for (const w of allWords) {
    const m = Math.floor(w.start / 60);
    const s = (w.start % 60).toFixed(1);
    console.log(`  ${m}:${s.padStart(4, '0')} "${w.word}"`);
  }

  // 2. Load lesson JSON to get page texts
  const lesson = JSON.parse(fs.readFileSync(lessonFile, 'utf8'));
  const pages = lesson.pages.filter(p => p.narrativeEN && p.narrativeEN.trim().length > 0);

  console.log(`\n=== Matching ${pages.length} pages ===\n`);

  // 3. Match each page's first few keywords to the STT timeline
  const pageTimes = [];
  let searchFrom = 0;

  for (const page of pages) {
    const text = page.narrativeEN.toLowerCase();
    // Get first 3 significant words (skip short words)
    const pageWords = text.split(/\s+/).filter(w => w.replace(/[^a-z]/g, '').length > 2);
    const searchWord = pageWords[0]?.replace(/[^a-z]/g, '') || '';

    if (!searchWord) {
      pageTimes.push({ page: page.imageAsset.split('/').pop(), startTime: null, text: text.slice(0, 50) });
      continue;
    }

    // Find this word in STT results after current position
    let found = null;
    for (let i = searchFrom; i < allWords.length; i++) {
      if (allWords[i].word.replace(/[^a-z]/g, '') === searchWord) {
        found = allWords[i];
        searchFrom = i + 1;
        break;
      }
    }

    const startTime = found ? found.start : null;
    pageTimes.push({
      page: page.imageAsset.split('/').pop(),
      startTime: startTime,
      text: text.slice(0, 60),
    });

    const timeStr = startTime !== null
      ? `${Math.floor(startTime / 60)}:${(startTime % 60).toFixed(1).padStart(4, '0')}`
      : '???';
    console.log(`  ${timeStr}  ${page.imageAsset.split('/').pop()} — "${text.slice(0, 50)}"`);
  }

  // 4. Output timing array
  console.log('\n=== Page Timings (seconds) ===\n');
  console.log(JSON.stringify(pageTimes.map(p => ({
    page: p.page,
    startTime: p.startTime !== null ? Math.round(p.startTime * 10) / 10 : null,
  })), null, 2));
}

main().catch(console.error);
