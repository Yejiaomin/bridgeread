#!/usr/bin/env node
/**
 * Generate word audio using ElevenLabs (same voice as story narration).
 * Replaces the video-clipped word_*.mp3 in phonics_sounds/.
 */

const fs = require('fs');
const path = require('path');

const envPath = path.join(__dirname, '..', '.env');
const env = fs.readFileSync(envPath, 'utf8');
const elevenLabsKey = env.match(/ELEVENLABS_API_KEY=(.+)/)?.[1]?.trim();
if (!elevenLabsKey) { console.error('No ELEVENLABS_API_KEY'); process.exit(1); }

const VOICE_ID = 'kbFeB8Ko2KgpldlKCYQA'; // Same cloned voice as story narration
const OUTPUT_DIR = path.join(__dirname, '..', 'assets', 'audio', 'phonics_sounds');

// All words that need audio
const words = [
  'bed', 'dog', 'fun', 'hug', 'light', 'met', 'nap', 'pet',
  'play', 'small', 'snack', 'story', 'yellow',
];

async function generateWord(word) {
  const outPath = path.join(OUTPUT_DIR, `word_${word}.mp3`);

  const res = await fetch(
    `https://api.elevenlabs.io/v1/text-to-speech/${VOICE_ID}`,
    {
      method: 'POST',
      headers: { 'xi-api-key': elevenLabsKey, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        text: word,
        model_id: 'eleven_multilingual_v2',
        voice_settings: { stability: 0.6, similarity_boost: 0.75, style: 0.2, use_speaker_boost: false, speed: 0.9 },
      }),
    }
  );

  if (!res.ok) {
    console.error(`✗ ${word}: ${res.status}`);
    return;
  }

  const buffer = await res.arrayBuffer();
  fs.writeFileSync(outPath, Buffer.from(buffer));
  console.log(`✓ word_${word}.mp3`);
  await new Promise(r => setTimeout(r, 500));
}

async function main() {
  console.log(`Generating ${words.length} word audio files with ElevenLabs...\n`);

  // Backup old files
  const backupDir = path.join(OUTPUT_DIR, '_old_word_clips');
  if (!fs.existsSync(backupDir)) fs.mkdirSync(backupDir);
  for (const w of words) {
    const src = path.join(OUTPUT_DIR, `word_${w}.mp3`);
    const dst = path.join(backupDir, `word_${w}.mp3`);
    if (fs.existsSync(src) && !fs.existsSync(dst)) {
      fs.copyFileSync(src, dst);
    }
  }

  for (const w of words) {
    await generateWord(w);
  }
  console.log('\nDone!');
}

main().catch(console.error);
