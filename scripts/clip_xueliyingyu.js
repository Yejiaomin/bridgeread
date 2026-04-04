#!/usr/bin/env node
/**
 * Clip individual phoneme sounds from xueliyingyu phonics audio.
 * Based on Google STT timestamps.
 *
 * Pattern: letter name x2, phoneme sound x2, example words
 * We want just the phoneme sound (2nd occurrence for cleaner audio).
 */

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const FFMPEG = 'C:/Users/llc88/AppData/Local/Microsoft/WinGet/Packages/Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe/ffmpeg-8.1-full_build/bin/ffmpeg.exe';
const INPUT = path.join(__dirname, '..', '_temp_xueliyingyu.mp3');
const OUTPUT_DIR = path.join(__dirname, '..', 'assets', 'audio', 'phonics_sounds');
const sttData = require('../_temp_stt_xly.json');

if (!fs.existsSync(OUTPUT_DIR)) fs.mkdirSync(OUTPUT_DIR, { recursive: true });

// From STT analysis, the phoneme sound timing for each letter.
// Format: { id, start, end } — targeting one clean phoneme utterance.
// The pattern is: letter name (e.g. "A") then phoneme sound (e.g. /æ/).
// STT often misrecognizes the phoneme, but timestamps are accurate.
//
// STT timeline analysis:
// A: 0:00 "ah","ah" (letter name), then phoneme /æ/ before "Apple" at 4.8s
//    → phoneme is between ~2.0-4.5s area. STT shows "ah" at 3.2s
// B: 0:19 "b","b" (letter+phoneme together since b sounds like the letter name)
//    → phoneme at ~20.0s
// etc.

const clips = [
  // A: STT: "ah" at 0.0, "ah" at 1.1, "ah" at 3.2 — the 3rd "ah" is the phoneme /æ/
  { id: 'a', start: 3.2, end: 4.5, note: '/æ/ as in apple' },
  // B: "b" at 19.2, "b" at 20.0 — 2nd is phoneme
  { id: 'b', start: 20.0, end: 20.8, note: '/b/' },
  // C: "c" at 38.5, "c" at 39.2 — phoneme at ~41-42 (between "c" names and "cat" at 43)
  // STT shows gap 39.2 → 53.4, the phoneme is in between but STT missed it
  // Let's take a slightly later clip, after the letter names
  { id: 'c', start: 41.0, end: 42.5, note: '/k/ — STT missed phoneme, estimate between letter name and "cat"' },
  // D: "d" at 57.1, "d" at 57.9 — phoneme before "dog" at 58.5
  // Actually d phoneme sounds come after letter names. Let's look: 57.1 d, 57.9 d, 58.5 dog
  // Very close together. The phoneme /d/ must be right around 59-60s area
  { id: 'd', start: 59.5, end: 60.5, note: '/d/' },
  // E: "e" at 75.6, "and" at 76.2 — phoneme /e/ heard as "and", 2nd occurrence
  { id: 'e', start: 76.2, end: 77.5, note: '/ɛ/' },
  // F: "f" at 95.3 — phoneme area ~96-97
  { id: 'f', start: 96.0, end: 97.5, note: '/f/' },
  // G: "g" at 111.8, "g" at 112.6 — phoneme after
  { id: 'g', start: 113.5, end: 114.5, note: '/ɡ/' },
  // H: "h" at 129.2, "h" at 130.7 — phoneme after
  { id: 'h', start: 131.5, end: 132.5, note: '/h/' },
  // I: area around 149-151, STT shows "India" at 151.8 — phoneme before
  { id: 'i', start: 149.5, end: 150.5, note: '/ɪ/' },
  // J: "J" at 162.4, "J" at 165.0 — phoneme after
  { id: 'j', start: 165.5, end: 166.5, note: '/dʒ/' },
  // K: "k" at 179.6... wait, that's wrong. Let me recalculate.
  // Actually from STT: "k" at 2:59.7=179.7, then "k" at 3:02.6=182.6
  { id: 'k', start: 183.5, end: 184.5, note: '/k/' },
  // L: "l" at 3:18.2=198.2 — phoneme after
  { id: 'l', start: 199.5, end: 200.5, note: '/l/' },
  // M: "m" at 3:37.9=217.9 — "oh" at 220.8 then "monkey" at 222.1
  { id: 'm', start: 219.0, end: 220.0, note: '/m/' },
  // N: "and" at 3:55.0=235.0, "and" at 3:57.4=237.4
  // "nah" at 3:58.8=238.8, "nah" at 3:59.6=239.6 — this is the /n/ phoneme
  { id: 'n', start: 239.6, end: 240.5, note: '/n/' },
  // O: "oh" at 4:13.8=253.8 — phoneme
  { id: 'o', start: 255.0, end: 256.0, note: '/ɒ/' },
  // P: "peep" at 4:35.3=275.3 — this is actually "p p" phoneme
  { id: 'p', start: 276.5, end: 277.5, note: '/p/' },
  // Q: "q" at 4:51.3=291.3, "q" at 4:51.9=291.9
  { id: 'q', start: 292.5, end: 293.5, note: '/kw/' },
  // R: "r" at 5:08.4=308.4, "r" at 5:11.1=311.1
  { id: 'r', start: 311.5, end: 312.5, note: '/r/' },
  // S: "s" at 5:27.6=327.6, "s" at 5:28.9=328.9
  { id: 's', start: 330.0, end: 331.0, note: '/s/' },
  // T: "t" at 5:45.8=345.8, "t" at 5:46.8=346.8
  { id: 't', start: 348.0, end: 349.0, note: '/t/' },
  // U: "you" at 6:03.8=363.8, "you" at 6:04.4=364.4 — letter name
  // phoneme /ʌ/ after letter names, before "under" at 368.5
  { id: 'u', start: 365.5, end: 366.5, note: '/ʌ/' },
  // V: "v" at 6:21.5=381.5, "v" at 6:22.2=382.2
  { id: 'v', start: 383.0, end: 384.0, note: '/v/' },
  // W: "w" at 6:40.5=400.5, "w" at 6:42.0=402.0
  // phoneme after letter names, before "witch" at 408.8
  { id: 'w', start: 403.0, end: 404.5, note: '/w/' },
  // X: "EX" at 6:58.3=418.3, "Acts" at 6:59.7=419.7 — these are letter name + phoneme
  { id: 'x', start: 420.5, end: 421.5, note: '/ks/' },
  // Y: "why" at 7:17.5=437.5, "why" at 7:19.1=439.1 — letter name
  // phoneme /j/ after, before "yeah" at 442.1
  { id: 'y', start: 440.0, end: 441.0, note: '/j/' },
  // Z: "the" at 7:35.5=455.5 — then phoneme /z/
  // "zoo" at 7:41.7=461.7
  { id: 'z', start: 458.0, end: 459.5, note: '/z/' },
];

console.log('Clipping phonemes from xueliyingyu audio...\n');

for (const { id, start, end, note } of clips) {
  const duration = end - start;
  const outFile = path.join(OUTPUT_DIR, `${id}.mp3`);

  const padStart = Math.max(0, start - 0.05);
  const padDur = duration + 0.1;

  const cmd = [
    `"${FFMPEG}"`, '-y',
    `-ss ${padStart.toFixed(3)}`,
    `-t ${padDur.toFixed(3)}`,
    `-i "${INPUT}"`,
    `-af "afade=t=in:st=0:d=0.02,afade=t=out:st=${Math.max(0, padDur - 0.05).toFixed(3)}:d=0.05"`,
    '-q:a 2',
    `"${outFile}"`,
  ].join(' ');

  try {
    execSync(cmd, { stdio: 'pipe' });
    const mm = Math.floor(start / 60);
    const ss = (start % 60).toFixed(1);
    console.log(`✓ ${id}: ${mm}:${ss.padStart(4,'0')} (${(duration * 1000).toFixed(0)}ms) — ${note}`);
  } catch (e) {
    console.error(`✗ ${id}: FAILED`);
  }
}

console.log('\nDone! Please verify each clip.');
