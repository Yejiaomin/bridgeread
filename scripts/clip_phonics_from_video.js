#!/usr/bin/env node
/**
 * Clip individual phoneme sounds from the YouTube phonics chant video.
 * Source: "ABC Phonics Chant for Children | Sounds and Actions from A to Z"
 *
 * Each letter in the video follows the pattern:
 *   [sound] [sound] [sound] [word] [word]
 * We extract the "sound" portion for each letter.
 *
 * Usage: node scripts/clip_phonics_from_video.js
 */

const { execSync } = require('child_process');
const path = require('path');
const fs = require('fs');

const FFMPEG = 'C:/Users/llc88/AppData/Local/Microsoft/WinGet/Packages/Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe/ffmpeg-8.1-full_build/bin/ffmpeg.exe';
const INPUT = path.join(__dirname, '..', '_temp_phonics_full.mp3');
const OUTPUT_DIR = path.join(__dirname, '..', 'assets', 'audio', 'phonics_sounds');

if (!fs.existsSync(OUTPUT_DIR)) fs.mkdirSync(OUTPUT_DIR, { recursive: true });

// Each letter: { id, start (of the sound portion), end (before the word starts) }
// Derived from subtitle analysis + silence detection of the chant rhythm.
// The chant has ~10s per letter: 3 beats sound (~0-4.5s) + 2 beats word (~5-9s)
// We clip just the 3 sound beats for each letter.
const letters = [
  // From subtitle: "a a a a a ah" starts at 0.0s, "apple" at ~5s
  { id: 'a', start: 0.0, end: 4.5 },
  // "b" sounds around 10-14s, "bowl" at ~15s
  { id: 'b', start: 10.2, end: 14.5 },
  // "c" sounds around 20-24s, "cat" at ~25s
  { id: 'c', start: 20.2, end: 24.5 },
  // "d d" at 30.26s, "dog" at ~35s
  { id: 'd', start: 30.0, end: 34.5 },
  // There's a music break, then "e" sounds at ~43s, "elephant" at ~46s
  { id: 'e', start: 40.5, end: 45.0 },
  // "f" sounds, "fish" at 55.56s
  { id: 'f', start: 50.6, end: 55.0 },
  // "g g g" at 1:00.6
  { id: 'g', start: 60.6, end: 65.0 },
  // "h h" at 1:10.7, "hat" at ~1:16
  { id: 'h', start: 70.7, end: 75.0 },
  // "I I" at 1:20.76, "igloo" at ~1:26
  { id: 'i', start: 80.8, end: 85.0 },
  // J sounds ~1:31, "juice" at ~1:36
  { id: 'j', start: 91.0, end: 95.5 },
  // "k k k" at 1:41.04, "kangaroo" at ~1:46
  { id: 'k', start: 101.0, end: 105.5 },
  // L sounds ~1:51, "lion" at ~1:56
  { id: 'l', start: 111.0, end: 115.5 },
  // M sounds ~2:01, subtitle at 2:02
  { id: 'm', start: 121.0, end: 125.5 },
  // N sounds ~2:09, "nose" at ~2:16
  { id: 'n', start: 129.0, end: 133.5 },
  // O sounds ~2:21, "octopus" at ~2:27
  { id: 'o', start: 141.0, end: 145.5 },
  // P sounds ~2:33, "pig" at ~2:37
  { id: 'p', start: 151.0, end: 155.5 },
  // "q q q" at 2:41.7, "queen" at ~2:47
  { id: 'q', start: 161.0, end: 165.5 },
  // "r r r" at 2:51.86, "ring" at ~2:57
  { id: 'r', start: 171.0, end: 175.5 },
  // "s s s" at 3:01.86, "sun" at ~3:07
  { id: 's', start: 181.0, end: 185.5 },
  // "t t t" at 3:12, "train" at ~3:17
  { id: 't', start: 192.0, end: 196.0 },
  // "u u u" at 3:22, "umbrella" at ~3:28
  { id: 'u', start: 202.0, end: 206.0 },
  // "v v v" at 3:32, "van" at ~3:37
  { id: 'v', start: 212.0, end: 216.0 },
  // "w w w" at 3:42, "watch" at ~3:47
  { id: 'w', start: 222.0, end: 226.0 },
  // "x x" at 3:52, "box" at ~3:57
  { id: 'x', start: 232.0, end: 236.0 },
  // "y y y" at 4:02, "yo-yo" at ~4:07
  { id: 'y', start: 242.0, end: 246.0 },
  // "z z z" at 4:12, "zoo" at ~4:18
  { id: 'z', start: 252.0, end: 258.0 },
];

console.log('Clipping phoneme sounds from video...\n');

for (const { id, start, end } of letters) {
  const outFile = path.join(OUTPUT_DIR, `${id}.mp3`);
  const duration = end - start;

  const cmd = [
    `"${FFMPEG}"`,
    '-y',
    `-ss ${start}`,
    `-t ${duration}`,
    `-i "${INPUT}"`,
    // Fade in/out to avoid clicks
    `-af "afade=t=in:st=0:d=0.05,afade=t=out:st=${duration - 0.1}:d=0.1"`,
    '-q:a 2',
    `"${outFile}"`,
  ].join(' ');

  try {
    execSync(cmd, { stdio: 'pipe' });
    console.log(`✓ ${id}: ${start}s - ${end}s (${duration.toFixed(1)}s)`);
  } catch (e) {
    console.error(`✗ ${id}: FAILED - ${e.message.slice(0, 100)}`);
  }
}

console.log('\nDone! Files saved to:', OUTPUT_DIR);
console.log('\nPlease listen to each clip and verify the timing.');
console.log('If any clip is off, adjust the start/end times in this script.');
