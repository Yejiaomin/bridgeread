#!/usr/bin/env node
/**
 * Clip a single clean phoneme sound for each letter A-Z from the YouTube chant.
 * Uses subtitle-derived start times + silence detection to find each beat precisely.
 */

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const FFMPEG = 'C:/Users/llc88/AppData/Local/Microsoft/WinGet/Packages/Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe/ffmpeg-8.1-full_build/bin/ffmpeg.exe';
const INPUT = path.join(__dirname, '..', '_temp_phonics_full.mp3');
const SILENCE_FILE = path.join(__dirname, '..', '_temp_silence_data.txt');
const OUTPUT_DIR = path.join(__dirname, '..', 'assets', 'audio', 'phonics_sounds');

if (!fs.existsSync(OUTPUT_DIR)) fs.mkdirSync(OUTPUT_DIR, { recursive: true });

// Parse silence data
const raw = fs.readFileSync(SILENCE_FILE, 'utf8');
const lines = raw.trim().split('\n');
const silences = [];
let pendingStart = null;

for (const line of lines) {
  const sm = line.match(/silence_start:\s*([\d.]+)/);
  const em = line.match(/silence_end:\s*([\d.]+)\s*\|\s*silence_duration:\s*([\d.]+)/);
  if (sm) pendingStart = parseFloat(sm[1]);
  if (em) {
    silences.push({ start: pendingStart, end: parseFloat(em[1]), dur: parseFloat(em[2]) });
    pendingStart = null;
  }
}

// Build sound segments (gaps between silences)
const sounds = [];
let prevEnd = 0;
for (const s of silences) {
  if (s.start > prevEnd + 0.02) {
    sounds.push({ start: prevEnd, end: s.start, dur: s.start - prevEnd });
  }
  prevEnd = s.end;
}
sounds.push({ start: prevEnd, end: 263, dur: 263 - prevEnd });

// Approximate start of the phoneme-sound portion for each letter.
// Derived from subtitle timing + the ~10s/letter rhythm of the chant.
// Each letter block: [start, start+5] has 3 phoneme beats, [start+5, start+10] has word beats.
const letterStarts = {
  a: 0.0,    b: 10.2,   c: 20.2,   d: 30.0,
  e: 40.5,   f: 50.6,   g: 60.6,   h: 70.7,
  i: 80.8,   j: 91.0,   k: 101.0,  l: 111.0,
  m: 121.0,  n: 131.0,  o: 141.0,  p: 151.0,
  q: 161.0,  r: 171.0,  s: 181.0,  t: 192.0,
  u: 202.0,  v: 212.0,  w: 222.0,  x: 232.0,
  y: 242.0,  z: 252.0,
};

console.log('Clipping single phoneme per letter...\n');

for (const [letter, startTime] of Object.entries(letterStarts)) {
  // Find sound segments within the first 5 seconds of this letter block
  const endTime = startTime + 5.0;
  const candidates = sounds.filter(s => s.start >= startTime - 0.1 && s.start < endTime);

  if (candidates.length < 2) {
    // Fallback: take the first candidate
    if (candidates.length === 0) {
      console.error(`✗ ${letter}: no sound found at ${startTime}s`);
      continue;
    }
  }

  // Pick the 2nd beat (index 1) — typically cleanest; fall back to 1st
  const beat = candidates.length >= 2 ? candidates[1] : candidates[0];

  // Add tiny padding
  const clipStart = Math.max(0, beat.start - 0.03);
  const clipEnd = beat.end + 0.05;
  const clipDur = clipEnd - clipStart;

  const outFile = path.join(OUTPUT_DIR, `${letter}.mp3`);
  const cmd = [
    `"${FFMPEG}"`, '-y',
    `-ss ${clipStart.toFixed(3)}`,
    `-t ${clipDur.toFixed(3)}`,
    `-i "${INPUT}"`,
    `-af "afade=t=in:st=0:d=0.01,afade=t=out:st=${Math.max(0, clipDur - 0.03).toFixed(3)}:d=0.03"`,
    '-q:a 2',
    `"${outFile}"`,
  ].join(' ');

  try {
    execSync(cmd, { stdio: 'pipe' });
    console.log(`✓ ${letter}: ${clipStart.toFixed(2)}s - ${clipEnd.toFixed(2)}s (${(clipDur * 1000).toFixed(0)}ms)`);
  } catch (e) {
    console.error(`✗ ${letter}: FAILED`);
  }
}

console.log('\nDone! Listen to verify each clip.');
