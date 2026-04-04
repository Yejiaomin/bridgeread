#!/usr/bin/env node
/**
 * Clip single phoneme sounds using Google STT timestamps.
 * For each letter, pick one clean phoneme beat (not the example word).
 */

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const FFMPEG = 'C:/Users/llc88/AppData/Local/Microsoft/WinGet/Packages/Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe/ffmpeg-8.1-full_build/bin/ffmpeg.exe';
const INPUT = path.join(__dirname, '..', '_temp_phonics_full.mp3');
const OUTPUT_DIR = path.join(__dirname, '..', 'assets', 'audio', 'phonics_sounds');
const sttData = require('../_temp_stt_result.json');

if (!fs.existsSync(OUTPUT_DIR)) fs.mkdirSync(OUTPUT_DIR, { recursive: true });

// Map each letter to the STT word that represents its phoneme sound,
// and pick the best single occurrence (2nd if available, for cleaner sound).
// Based on STT output analysis:
const letterClips = [
  // A: "a" at 0.00s (900ms) — first occurrence, the pure /æ/ sound
  { id: 'a', word: 'a', start: 0.00, end: 0.90 },
  // B: "b" repeated at 10.9s — pick 2nd at 11.0s
  { id: 'b', word: 'b', start: 11.00, end: 11.50 },
  // C: "c" at 20.4s (700ms)
  { id: 'c', word: 'c', start: 20.40, end: 21.10 },
  // D: "d" at 30.7s (400ms)
  { id: 'd', word: 'd', start: 30.20, end: 30.70 },
  // E: "EE" at 40.3s (1100ms) — too long, take first half
  { id: 'e', word: 'EE', start: 40.30, end: 41.00 },
  // F: "f" at 50.4s — pick 2nd at 51.0s (300ms)
  { id: 'f', word: 'f', start: 51.00, end: 51.30 },
  // G: "g" at 61.0s (500ms)
  { id: 'g', word: 'g', start: 61.00, end: 61.50 },
  // H: "h" at 11.2s... wait, 1:11.2 = 71.2s (700ms)
  { id: 'h', word: 'h', start: 71.20, end: 71.90 },
  // I: "i" at 1:20.7 = 80.7s (600ms)
  { id: 'i', word: 'i', start: 80.70, end: 81.30 },
  // J: "j" at 1:31.3 = 91.3s (500ms)
  { id: 'j', word: 'j', start: 91.30, end: 91.80 },
  // K: "k" at 1:41.1 = 101.1s (700ms)
  { id: 'k', word: 'k', start: 101.10, end: 101.80 },
  // L: "l" at 1:52.2 = 112.2s (300ms) — the clean single "l"
  { id: 'l', word: 'l', start: 112.20, end: 112.50 },
  // M: "m" at 2:01.7 = 121.7s (600ms)
  { id: 'm', word: 'm', start: 121.70, end: 122.30 },
  // N: "and" at 2:11.7 = 131.7s (700ms) — STT heard "and" but it's /n/
  { id: 'n', word: 'and', start: 131.70, end: 132.40 },
  // O: "oh" at 2:21.4 = 141.4s (400ms)
  { id: 'o', word: 'oh', start: 141.40, end: 141.80 },
  // P: "b" at 2:31.9 = 151.9s (500ms) — STT confused p/b, but it's /p/
  { id: 'p', word: 'b', start: 151.90, end: 152.40 },
  // Q: "cute" at 2:42.1 = 162.1s (300ms) — STT heard "cute" for /kw/
  { id: 'q', word: 'cute', start: 162.10, end: 162.40 },
  // R: "r" at 2:52.9 = 172.9s (700ms)
  { id: 'r', word: 'r', start: 172.90, end: 173.60 },
  // S: "as" at 3:02.5 = 182.5s (300ms) — STT heard "as" for /s/
  { id: 's', word: 'as', start: 182.50, end: 182.80 },
  // T: "t" at 3:12.4 = 192.4s (300ms)
  { id: 't', word: 't', start: 192.40, end: 192.70 },
  // U: "you" at 3:22.5 = 202.5s (500ms) — STT heard "you" for /ʌ/
  { id: 'u', word: 'you', start: 202.50, end: 203.00 },
  // V: "v" at 3:32.5 = 212.5s (400ms)
  { id: 'v', word: 'v', start: 212.50, end: 212.90 },
  // W: "www" at 3:42.2 = 222.2s (1200ms) — take first portion
  { id: 'w', word: 'www', start: 222.20, end: 222.80 },
  // X: "axe" at 3:53.2 = 233.2s (400ms) — STT heard "axe" for /ks/
  { id: 'x', word: 'axe', start: 233.20, end: 233.60 },
  // Y: "why" at 4:03.0 = 243.0s (500ms)
  { id: 'y', word: 'why', start: 243.00, end: 243.50 },
  // Z: "z" at 4:13.2 = 253.2s (300ms)
  { id: 'z', word: 'z', start: 253.20, end: 253.50 },
];

console.log('Clipping single phoneme per letter using STT timestamps...\n');

for (const { id, start, end } of letterClips) {
  const duration = end - start;
  const outFile = path.join(OUTPUT_DIR, `${id}.mp3`);

  // Small padding + fade
  const padStart = Math.max(0, start - 0.03);
  const padDur = duration + 0.06;

  const cmd = [
    `"${FFMPEG}"`, '-y',
    `-ss ${padStart.toFixed(3)}`,
    `-t ${padDur.toFixed(3)}`,
    `-i "${INPUT}"`,
    `-af "afade=t=in:st=0:d=0.01,afade=t=out:st=${Math.max(0, padDur - 0.03).toFixed(3)}:d=0.03"`,
    '-q:a 2',
    `"${outFile}"`,
  ].join(' ');

  try {
    execSync(cmd, { stdio: 'pipe' });
    console.log(`✓ ${id}: ${start.toFixed(2)}s - ${end.toFixed(2)}s (${(duration * 1000).toFixed(0)}ms)`);
  } catch (e) {
    console.error(`✗ ${id}: FAILED`);
  }
}

console.log('\nDone!');
