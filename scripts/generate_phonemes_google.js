#!/usr/bin/env node
// BridgeRead - 自然拼读音素音频生成 (Google Cloud TTS + SSML phoneme tags)
// 使用 IPA 精确发音

const fs = require('fs');
const path = require('path');

const envPath = path.join(__dirname, '..', '.env');
const env = fs.readFileSync(envPath, 'utf8');
const apiKey = env.match(/GOOGLE_VISION_API_KEY=(.+)/)?.[1]?.trim()
            || env.match(/GOOGLE_CLOUD_API_KEY=(.+)/)?.[1]?.trim();

if (!apiKey) {
  console.error('❌ 需要 GOOGLE_CLOUD_API_KEY 或 GOOGLE_VISION_API_KEY（在 .env 里）');
  process.exit(1);
}

const OUTPUT_DIR = path.join(__dirname, '..', 'assets', 'audio', 'phonemes');
if (!fs.existsSync(OUTPUT_DIR)) fs.mkdirSync(OUTPUT_DIR, { recursive: true });

// Voice config
const VOICE = { languageCode: 'en-US', name: 'en-US-Studio-Q' }; // Clear female voice
const AUDIO_CONFIG = { audioEncoding: 'MP3', speakingRate: 0.85 };

// ── Phoneme definitions with IPA ─────────────────────────────────────────────
const phonemes = [
  // Consonants — using IPA with minimal schwa for natural phonics sound
  { id: 'b', ssml: '<speak><phoneme alphabet="ipa" ph="bə">buh</phoneme>REMOVEME<phoneme alphabet="ipa" ph="bə">buh</phoneme>REMOVEME<phoneme alphabet="ipa" ph="bə">buh</phoneme></speak>' },
  { id: 'c', ssml: '<speak><phoneme alphabet="ipa" ph="kə">cuh</phoneme>REMOVEME<phoneme alphabet="ipa" ph="kə">cuh</phoneme>REMOVEME<phoneme alphabet="ipa" ph="kə">cuh</phoneme></speak>' },
  { id: 'd', ssml: '<speak><phoneme alphabet="ipa" ph="də">duh</phoneme>REMOVEME<phoneme alphabet="ipa" ph="də">duh</phoneme>REMOVEME<phoneme alphabet="ipa" ph="də">duh</phoneme></speak>' },
  { id: 'f', ssml: '<speak><phoneme alphabet="ipa" ph="fː">fff</phoneme>REMOVEME<phoneme alphabet="ipa" ph="fː">fff</phoneme>REMOVEME<phoneme alphabet="ipa" ph="fː">fff</phoneme></speak>' },
  { id: 'g', ssml: '<speak><phoneme alphabet="ipa" ph="ɡə">guh</phoneme>REMOVEME<phoneme alphabet="ipa" ph="ɡə">guh</phoneme>REMOVEME<phoneme alphabet="ipa" ph="ɡə">guh</phoneme></speak>' },
  { id: 'h', ssml: '<speak><phoneme alphabet="ipa" ph="hə">huh</phoneme>REMOVEME<phoneme alphabet="ipa" ph="hə">huh</phoneme>REMOVEME<phoneme alphabet="ipa" ph="hə">huh</phoneme></speak>' },
  { id: 'j', ssml: '<speak><phoneme alphabet="ipa" ph="dʒə">juh</phoneme>REMOVEME<phoneme alphabet="ipa" ph="dʒə">juh</phoneme>REMOVEME<phoneme alphabet="ipa" ph="dʒə">juh</phoneme></speak>' },
  { id: 'k', ssml: '<speak><phoneme alphabet="ipa" ph="kə">kuh</phoneme>REMOVEME<phoneme alphabet="ipa" ph="kə">kuh</phoneme>REMOVEME<phoneme alphabet="ipa" ph="kə">kuh</phoneme></speak>' },
  { id: 'l', ssml: '<speak><phoneme alphabet="ipa" ph="lː">lll</phoneme>REMOVEME<phoneme alphabet="ipa" ph="lː">lll</phoneme>REMOVEME<phoneme alphabet="ipa" ph="lː">lll</phoneme></speak>' },
  { id: 'm', ssml: '<speak><phoneme alphabet="ipa" ph="mː">mmm</phoneme>REMOVEME<phoneme alphabet="ipa" ph="mː">mmm</phoneme>REMOVEME<phoneme alphabet="ipa" ph="mː">mmm</phoneme></speak>' },
  { id: 'n', ssml: '<speak><phoneme alphabet="ipa" ph="nː">nnn</phoneme>REMOVEME<phoneme alphabet="ipa" ph="nː">nnn</phoneme>REMOVEME<phoneme alphabet="ipa" ph="nː">nnn</phoneme></speak>' },
  { id: 'p', ssml: '<speak><phoneme alphabet="ipa" ph="pə">puh</phoneme>REMOVEME<phoneme alphabet="ipa" ph="pə">puh</phoneme>REMOVEME<phoneme alphabet="ipa" ph="pə">puh</phoneme></speak>' },
  { id: 'r', ssml: '<speak><phoneme alphabet="ipa" ph="ɹː">rrr</phoneme>REMOVEME<phoneme alphabet="ipa" ph="ɹː">rrr</phoneme>REMOVEME<phoneme alphabet="ipa" ph="ɹː">rrr</phoneme></speak>' },
  { id: 's', ssml: '<speak><phoneme alphabet="ipa" ph="sː">sss</phoneme>REMOVEME<phoneme alphabet="ipa" ph="sː">sss</phoneme>REMOVEME<phoneme alphabet="ipa" ph="sː">sss</phoneme></speak>' },
  { id: 't', ssml: '<speak><phoneme alphabet="ipa" ph="tə">tuh</phoneme>REMOVEME<phoneme alphabet="ipa" ph="tə">tuh</phoneme>REMOVEME<phoneme alphabet="ipa" ph="tə">tuh</phoneme></speak>' },
  { id: 'v', ssml: '<speak><phoneme alphabet="ipa" ph="vː">vvv</phoneme>REMOVEME<phoneme alphabet="ipa" ph="vː">vvv</phoneme>REMOVEME<phoneme alphabet="ipa" ph="vː">vvv</phoneme></speak>' },
  { id: 'w', ssml: '<speak><phoneme alphabet="ipa" ph="wə">wuh</phoneme>REMOVEME<phoneme alphabet="ipa" ph="wə">wuh</phoneme>REMOVEME<phoneme alphabet="ipa" ph="wə">wuh</phoneme></speak>' },
  { id: 'x', ssml: '<speak><phoneme alphabet="ipa" ph="ks">ks</phoneme>REMOVEME<phoneme alphabet="ipa" ph="ks">ks</phoneme>REMOVEME<phoneme alphabet="ipa" ph="ks">ks</phoneme></speak>' },
  { id: 'y', ssml: '<speak><phoneme alphabet="ipa" ph="jə">yuh</phoneme>REMOVEME<phoneme alphabet="ipa" ph="jə">yuh</phoneme>REMOVEME<phoneme alphabet="ipa" ph="jə">yuh</phoneme></speak>' },
  { id: 'z', ssml: '<speak><phoneme alphabet="ipa" ph="zː">zzz</phoneme>REMOVEME<phoneme alphabet="ipa" ph="zː">zzz</phoneme>REMOVEME<phoneme alphabet="ipa" ph="zː">zzz</phoneme></speak>' },

  // Short vowels
  { id: 'a_short', ssml: '<speak><phoneme alphabet="ipa" ph="æː">aaa</phoneme>REMOVEME<phoneme alphabet="ipa" ph="æː">aaa</phoneme>REMOVEME<phoneme alphabet="ipa" ph="æː">aaa</phoneme></speak>' },
  { id: 'e_short', ssml: '<speak><phoneme alphabet="ipa" ph="ɛː">eee</phoneme>REMOVEME<phoneme alphabet="ipa" ph="ɛː">eee</phoneme>REMOVEME<phoneme alphabet="ipa" ph="ɛː">eee</phoneme></speak>' },
  { id: 'i_short', ssml: '<speak><phoneme alphabet="ipa" ph="ɪː">iii</phoneme>REMOVEME<phoneme alphabet="ipa" ph="ɪː">iii</phoneme>REMOVEME<phoneme alphabet="ipa" ph="ɪː">iii</phoneme></speak>' },
  { id: 'o_short', ssml: '<speak><phoneme alphabet="ipa" ph="ɒː">ooo</phoneme>REMOVEME<phoneme alphabet="ipa" ph="ɒː">ooo</phoneme>REMOVEME<phoneme alphabet="ipa" ph="ɒː">ooo</phoneme></speak>' },
  { id: 'u_short', ssml: '<speak><phoneme alphabet="ipa" ph="ʌː">uuu</phoneme>REMOVEME<phoneme alphabet="ipa" ph="ʌː">uuu</phoneme>REMOVEME<phoneme alphabet="ipa" ph="ʌː">uuu</phoneme></speak>' },

  // Long vowels
  { id: 'a_long', ssml: '<speak><phoneme alphabet="ipa" ph="eɪː">aaa</phoneme>REMOVEME<phoneme alphabet="ipa" ph="eɪː">aaa</phoneme>REMOVEME<phoneme alphabet="ipa" ph="eɪː">aaa</phoneme></speak>' },
  { id: 'e_long', ssml: '<speak><phoneme alphabet="ipa" ph="iːː">eee</phoneme>REMOVEME<phoneme alphabet="ipa" ph="iːː">eee</phoneme>REMOVEME<phoneme alphabet="ipa" ph="iːː">eee</phoneme></speak>' },
  { id: 'i_long', ssml: '<speak><phoneme alphabet="ipa" ph="aɪː">iii</phoneme>REMOVEME<phoneme alphabet="ipa" ph="aɪː">iii</phoneme>REMOVEME<phoneme alphabet="ipa" ph="aɪː">iii</phoneme></speak>' },
  { id: 'o_long', ssml: '<speak><phoneme alphabet="ipa" ph="oʊː">ooo</phoneme>REMOVEME<phoneme alphabet="ipa" ph="oʊː">ooo</phoneme>REMOVEME<phoneme alphabet="ipa" ph="oʊː">ooo</phoneme></speak>' },
  { id: 'u_long', ssml: '<speak><phoneme alphabet="ipa" ph="juːː">uuu</phoneme>REMOVEME<phoneme alphabet="ipa" ph="juːː">uuu</phoneme>REMOVEME<phoneme alphabet="ipa" ph="juːː">uuu</phoneme></speak>' },

  // Digraphs
  { id: 'sh', ssml: '<speak><phoneme alphabet="ipa" ph="ʃ">sh</phoneme>, <phoneme alphabet="ipa" ph="ʃ">sh</phoneme>, <phoneme alphabet="ipa" ph="ʃ">sh</phoneme></speak>' },
  { id: 'ch', ssml: '<speak><phoneme alphabet="ipa" ph="tʃ">ch</phoneme>, <phoneme alphabet="ipa" ph="tʃ">ch</phoneme>, <phoneme alphabet="ipa" ph="tʃ">ch</phoneme></speak>' },
  { id: 'th', ssml: '<speak><phoneme alphabet="ipa" ph="θ">th</phoneme>, <phoneme alphabet="ipa" ph="θ">th</phoneme>, <phoneme alphabet="ipa" ph="θ">th</phoneme></speak>' },
  { id: 'wh', ssml: '<speak><phoneme alphabet="ipa" ph="w">wh</phoneme>, <phoneme alphabet="ipa" ph="w">wh</phoneme>, <phoneme alphabet="ipa" ph="w">wh</phoneme></speak>' },
  { id: 'ph', ssml: '<speak><phoneme alphabet="ipa" ph="f">ph</phoneme>, <phoneme alphabet="ipa" ph="f">ph</phoneme>, <phoneme alphabet="ipa" ph="f">ph</phoneme></speak>' },
  { id: 'ng', ssml: '<speak><phoneme alphabet="ipa" ph="ŋ">ng</phoneme>, <phoneme alphabet="ipa" ph="ŋ">ng</phoneme>, <phoneme alphabet="ipa" ph="ŋ">ng</phoneme></speak>' },

  // Words (plain text, no SSML needed)
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

// ── Google Cloud TTS API ─────────────────────────────────────────────────────
async function generateAudio(phoneme) {
  const outputPath = path.join(OUTPUT_DIR, `${phoneme.id}.mp3`);
  if (fs.existsSync(outputPath)) {
    console.log(`⏭️  跳过: ${phoneme.id}.mp3`);
    return;
  }

  console.log(`🎙️  生成: ${phoneme.id} ...`);

  const input = phoneme.ssml
    ? { ssml: phoneme.ssml }
    : { text: phoneme.text };

  const response = await fetch(
    `https://texttospeech.googleapis.com/v1/text:synthesize?key=${apiKey}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        input,
        voice: VOICE,
        audioConfig: AUDIO_CONFIG,
      }),
    }
  );

  if (!response.ok) {
    const err = await response.text();
    console.error(`❌ 失败 ${phoneme.id}: ${response.status} ${err}`);
    return;
  }

  const data = await response.json();
  fs.writeFileSync(outputPath, Buffer.from(data.audioContent, 'base64'));
  console.log(`✅ 完成: ${phoneme.id}.mp3`);

  // Rate limit
  await new Promise(r => setTimeout(r, 200));
}

// ── Main ─────────────────────────────────────────────────────────────────────
async function main() {
  console.log(`\n🔤 BridgeRead 音素生成器 (Google Cloud TTS + IPA)`);
  console.log(`共 ${phonemes.length} 个音素\n`);

  for (const p of phonemes) {
    await generateAudio(p);
  }

  console.log(`\n🎉 完成！音素文件在 ${OUTPUT_DIR}\n`);
}

main().catch(console.error);
