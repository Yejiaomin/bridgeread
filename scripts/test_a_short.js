#!/usr/bin/env node
// 测试不同方式生成 /æ/ 音素

const fs = require('fs');
const path = require('path');

const envPath = path.join(__dirname, '..', '.env');
const env = fs.readFileSync(envPath, 'utf8');
const apiKey = env.match(/GOOGLE_CLOUD_API_KEY=(.+)/)?.[1]?.trim();

const OUTPUT_DIR = path.join(__dirname, '..', 'assets', 'audio', 'phonics_sounds');
const VOICE = { languageCode: 'en-US', name: 'en-US-Studio-Q' };
const AUDIO_CONFIG = { audioEncoding: 'MP3', speakingRate: 0.8 };

const tests = [
  { id: 'a_short_v1', ssml: '<speak><phoneme alphabet="ipa" ph="æ">a</phoneme></speak>', desc: 'IPA æ' },
  { id: 'a_short_v2', ssml: '<speak><phoneme alphabet="ipa" ph="æː">aah</phoneme></speak>', desc: 'IPA æː 长一点' },
  { id: 'a_short_v3', text: 'aah', desc: '纯文本 aah' },
  { id: 'a_short_v4', ssml: '<speak><phoneme alphabet="ipa" ph="æ">cat</phoneme></speak>', desc: 'IPA æ fallback cat' },
  { id: 'a_short_v5', ssml: '<speak><prosody rate="slow"><phoneme alphabet="ipa" ph="æ">ah</phoneme></prosody></speak>', desc: 'IPA æ 慢速' },
  { id: 'a_short_v6', ssml: '<speak><say-as interpret-as="characters">a</say-as></speak>', desc: 'say-as characters a' },
];

async function gen(t) {
  const outPath = path.join(OUTPUT_DIR, `${t.id}.mp3`);
  const input = t.ssml ? { ssml: t.ssml } : { text: t.text };
  const res = await fetch(
    `https://texttospeech.googleapis.com/v1/text:synthesize?key=${apiKey}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ input, voice: VOICE, audioConfig: AUDIO_CONFIG }),
    }
  );
  if (!res.ok) { console.error(`✗ ${t.id}: ${res.status}`); return; }
  const data = await res.json();
  fs.writeFileSync(outPath, Buffer.from(data.audioContent, 'base64'));
  console.log(`✓ ${t.id} — ${t.desc}`);
  await new Promise(r => setTimeout(r, 250));
}

async function main() {
  console.log('生成 a_short 测试版本:\n');
  for (const t of tests) await gen(t);
  console.log('\n请逐个试听，告诉我哪个最接近你要的 /æ/ 音。');
}

main().catch(console.error);
