#!/usr/bin/env node
// BridgeRead - 自然拼读音素音频 (Google Cloud TTS + IPA)
// 每个音素只发一次，清晰准确

const fs = require('fs');
const path = require('path');

const envPath = path.join(__dirname, '..', '.env');
const env = fs.readFileSync(envPath, 'utf8');
const apiKey = env.match(/GOOGLE_VISION_API_KEY=(.+)/)?.[1]?.trim()
            || env.match(/GOOGLE_CLOUD_API_KEY=(.+)/)?.[1]?.trim();

if (!apiKey) { console.error('❌ 需要 Google Cloud API key'); process.exit(1); }

const OUTPUT_DIR = path.join(__dirname, '..', 'assets', 'audio', 'phonics_sounds');
if (!fs.existsSync(OUTPUT_DIR)) fs.mkdirSync(OUTPUT_DIR, { recursive: true });

const VOICE = { languageCode: 'en-US', name: 'en-US-Studio-Q' };
const AUDIO_CONFIG = { audioEncoding: 'MP3', speakingRate: 0.75 };

const phonemes = [
  // ── 辅音 (consonants) ──
  { id: 'b', ssml: '<speak><phoneme alphabet="ipa" ph="bə">buh</phoneme></speak>' },
  { id: 'c', ssml: '<speak><phoneme alphabet="ipa" ph="kə">cuh</phoneme></speak>' },
  { id: 'd', ssml: '<speak><phoneme alphabet="ipa" ph="də">duh</phoneme></speak>' },
  { id: 'f', ssml: '<speak><phoneme alphabet="ipa" ph="fː">ff</phoneme></speak>' },
  { id: 'g', ssml: '<speak><phoneme alphabet="ipa" ph="ɡə">guh</phoneme></speak>' },
  { id: 'h', ssml: '<speak><phoneme alphabet="ipa" ph="hə">huh</phoneme></speak>' },
  { id: 'j', ssml: '<speak><phoneme alphabet="ipa" ph="dʒə">juh</phoneme></speak>' },
  { id: 'k', ssml: '<speak><phoneme alphabet="ipa" ph="kə">kuh</phoneme></speak>' },
  { id: 'l', ssml: '<speak><phoneme alphabet="ipa" ph="lː">ll</phoneme></speak>' },
  { id: 'm', ssml: '<speak><phoneme alphabet="ipa" ph="mː">mm</phoneme></speak>' },
  { id: 'n', ssml: '<speak><phoneme alphabet="ipa" ph="nː">nn</phoneme></speak>' },
  { id: 'p', ssml: '<speak><phoneme alphabet="ipa" ph="pə">puh</phoneme></speak>' },
  { id: 'r', ssml: '<speak><phoneme alphabet="ipa" ph="ɹː">rr</phoneme></speak>' },
  { id: 's', ssml: '<speak><phoneme alphabet="ipa" ph="sː">ss</phoneme></speak>' },
  { id: 't', ssml: '<speak><phoneme alphabet="ipa" ph="tə">tuh</phoneme></speak>' },
  { id: 'v', ssml: '<speak><phoneme alphabet="ipa" ph="vː">vv</phoneme></speak>' },
  { id: 'w', ssml: '<speak><phoneme alphabet="ipa" ph="wə">wuh</phoneme></speak>' },
  { id: 'x', ssml: '<speak><phoneme alphabet="ipa" ph="ks">x</phoneme></speak>' },
  { id: 'y', ssml: '<speak><phoneme alphabet="ipa" ph="jə">yuh</phoneme></speak>' },
  { id: 'z', ssml: '<speak><phoneme alphabet="ipa" ph="zː">zz</phoneme></speak>' },

  // ── 短元音 (short vowels) ──
  // 用 prosody 延长，让 TTS 有足够时间渲染清晰的元音
  { id: 'a_short', ssml: '<speak><prosody rate="slow"><phoneme alphabet="ipa" ph="æː">aah</phoneme></prosody></speak>' },
  { id: 'e_short', ssml: '<speak><prosody rate="slow"><phoneme alphabet="ipa" ph="ɛː">ehh</phoneme></prosody></speak>' },
  { id: 'i_short', ssml: '<speak><prosody rate="slow"><phoneme alphabet="ipa" ph="ɪː">ihh</phoneme></prosody></speak>' },
  { id: 'o_short', ssml: '<speak><prosody rate="slow"><phoneme alphabet="ipa" ph="ɑː">ahh</phoneme></prosody></speak>' },
  { id: 'u_short', ssml: '<speak><prosody rate="slow"><phoneme alphabet="ipa" ph="ʌː">uhh</phoneme></prosody></speak>' },

  // ── 长元音 (long vowels) ──
  { id: 'a_long', ssml: '<speak><prosody rate="slow"><phoneme alphabet="ipa" ph="eɪː">ay</phoneme></prosody></speak>' },
  { id: 'e_long', ssml: '<speak><prosody rate="slow"><phoneme alphabet="ipa" ph="iːː">ee</phoneme></prosody></speak>' },
  { id: 'i_long', ssml: '<speak><prosody rate="slow"><phoneme alphabet="ipa" ph="aɪː">eye</phoneme></prosody></speak>' },
  { id: 'o_long', ssml: '<speak><prosody rate="slow"><phoneme alphabet="ipa" ph="oʊː">oh</phoneme></prosody></speak>' },
  { id: 'u_long', ssml: '<speak><prosody rate="slow"><phoneme alphabet="ipa" ph="juːː">you</phoneme></prosody></speak>' },

  // ── 双字母组合 (digraphs) ── fallback 用含该音的词，防止 TTS 拆字母读
  { id: 'sh', ssml: '<speak><phoneme alphabet="ipa" ph="ʃː">shh</phoneme></speak>' },
  { id: 'ch', ssml: '<speak><phoneme alphabet="ipa" ph="tʃ">church</phoneme></speak>' },
  { id: 'th', ssml: '<speak><phoneme alphabet="ipa" ph="θː">think</phoneme></speak>' },
  { id: 'wh', ssml: '<speak><phoneme alphabet="ipa" ph="wə">what</phoneme></speak>' },
  { id: 'ph', ssml: '<speak><phoneme alphabet="ipa" ph="fː">phone</phoneme></speak>' },
  { id: 'ng', ssml: '<speak><phoneme alphabet="ipa" ph="ŋː">sing</phoneme></speak>' },

  // ── 单词 (words) ──
  { id: 'word_bed', text: 'bed' },
  { id: 'word_hug', text: 'hug' },
  { id: 'word_nap', text: 'nap' },
  { id: 'word_pet', text: 'pet' },
  { id: 'word_fun', text: 'fun' },
  { id: 'word_play', text: 'play' },
  { id: 'word_story', text: 'story' },
  { id: 'word_small', text: 'small' },
  { id: 'word_yellow', text: 'yellow' },
  { id: 'word_snack', text: 'snack' },
  { id: 'word_dog', text: 'dog' },
  { id: 'word_met', text: 'met' },
  { id: 'word_light', text: 'light' },
];

async function generateAudio(phoneme) {
  const outputPath = path.join(OUTPUT_DIR, `${phoneme.id}.mp3`);
  if (fs.existsSync(outputPath)) {
    console.log(`⏭️  跳过: ${phoneme.id}.mp3`);
    return;
  }

  console.log(`🎙️  生成: ${phoneme.id} ...`);

  const input = phoneme.ssml ? { ssml: phoneme.ssml } : { text: phoneme.text };

  const response = await fetch(
    `https://texttospeech.googleapis.com/v1/text:synthesize?key=${apiKey}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ input, voice: VOICE, audioConfig: AUDIO_CONFIG }),
    }
  );

  if (!response.ok) {
    console.error(`❌ 失败 ${phoneme.id}: ${response.status}`);
    return;
  }

  const data = await response.json();
  fs.writeFileSync(outputPath, Buffer.from(data.audioContent, 'base64'));
  console.log(`✅ 完成: ${phoneme.id}.mp3`);
  await new Promise(r => setTimeout(r, 250));
}

async function main() {
  console.log(`\n🔤 BridgeRead 音素生成器 (Google Cloud TTS + IPA)`);
  console.log(`输出: ${OUTPUT_DIR}`);
  console.log(`共 ${phonemes.length} 个\n`);
  for (const p of phonemes) await generateAudio(p);
  console.log(`\n🎉 完成！\n`);
}

main().catch(console.error);
