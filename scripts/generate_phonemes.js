// BridgeRead - 自然拼读音素音频生成
// 使用ElevenLabs生成所有音素发音

const fs = require('fs');
const path = require('path');

const envPath = path.join(__dirname, '..', '.env');
const env = fs.readFileSync(envPath, 'utf8');
const apiKey = env.match(/ELEVENLABS_API_KEY=(.+)/)?.[1]?.trim();

const VOICE_ID = 'Xb7hH8MSUJpSbSDYk0k2'; // Alice - Clear, Engaging Educator
const OUTPUT_DIR = path.join(__dirname, '..', 'assets', 'audio', 'phonemes');

if (!fs.existsSync(OUTPUT_DIR)) fs.mkdirSync(OUTPUT_DIR, { recursive: true });

// 音素列表 - 用夸张清晰的发音方式
const phonemes = [
  // 辅音
  { id: 'b', text: 'b b b' },
  { id: 'c', text: 'k k k' },
  { id: 'd', text: 'd d d' },
  { id: 'f', text: 'fff' },
  { id: 'g', text: 'g g g' },
  { id: 'h', text: 'h h h' },
  { id: 'j', text: 'juh' },
  { id: 'k', text: 'kuh' },
  { id: 'l', text: 'lll' },
  { id: 'm', text: 'mmm' },
  { id: 'n', text: 'nnn' },
  { id: 'p', text: 'puh' },
  { id: 'r', text: 'rrr' },
  { id: 's', text: 'sss' },
  { id: 't', text: 'tuh' },
  { id: 'v', text: 'vvv' },
  { id: 'w', text: 'wuh' },
  { id: 'x', text: 'ksss' },
  { id: 'y', text: 'yuh' },
  { id: 'z', text: 'zzz' },
  // 短元音
  { id: 'a_short', text: 'a a a' },
  { id: 'e_short', text: 'e e e' },
  { id: 'i_short', text: 'i i i' },
  { id: 'o_short', text: 'o o o' },
  { id: 'u_short', text: 'u u u' },
  // 长元音
  { id: 'a_long', text: 'ay, as in cake' },
  { id: 'e_long', text: 'ee, as in feet' },
  { id: 'i_long', text: 'eye, as in bike' },
  { id: 'o_long', text: 'oh, as in boat' },
  { id: 'u_long', text: 'you, as in cube' },
  // 常见组合音
  { id: 'sh', text: 'shh' },
  { id: 'ch', text: 'chuh' },
  { id: 'th', text: 'th, as in think' },
  { id: 'wh', text: 'wh, as in when' },
  { id: 'ph', text: 'fff, as in phone' },
  { id: 'ng', text: 'ng, as in sing' },
  // 表扬音频（答对时）— 最多3词，语速适中
  { id: 'one_more_time', text: 'One more time.', settings: { stability: 0.35, similarity_boost: 0.75, style: 0.40, use_speaker_boost: true, speed: 0.85 } },
  { id: 'you_got_it',    text: 'You got it!',    settings: { stability: 0.30, similarity_boost: 0.75, style: 0.50, use_speaker_boost: true, speed: 0.85 } },
  { id: 'bingo',        text: 'Bingo!',          settings: { stability: 0.30, similarity_boost: 0.75, style: 0.50, use_speaker_boost: true, speed: 0.85 } },
  { id: 'great',        text: 'So great!',       settings: { stability: 0.30, similarity_boost: 0.75, style: 0.50, use_speaker_boost: true, speed: 0.85 } },
  { id: 'nice',         text: 'Very nice!',      settings: { stability: 0.30, similarity_boost: 0.75, style: 0.50, use_speaker_boost: true, speed: 0.85 } },
  { id: 'good_job',     text: 'Good job!',       settings: { stability: 0.30, similarity_boost: 0.75, style: 0.50, use_speaker_boost: true, speed: 0.85 } },
  { id: 'cool',         text: 'So cool!',        settings: { stability: 0.30, similarity_boost: 0.75, style: 0.50, use_speaker_boost: true, speed: 0.85 } },
  { id: 'excellent',    text: 'Excellent!',      settings: { stability: 0.30, similarity_boost: 0.75, style: 0.50, use_speaker_boost: true, speed: 0.85 } },
  // 鼓励音频（答错时）— 最多3词，语速慢
  { id: 'oops',         text: 'Oops!',           settings: { stability: 0.40, similarity_boost: 0.75, style: 0.30, use_speaker_boost: true, speed: 0.80 } },
  { id: 'try_again',    text: 'Try again!',      settings: { stability: 0.40, similarity_boost: 0.75, style: 0.30, use_speaker_boost: true, speed: 0.80 } },
  { id: 'very_close',   text: 'Almost there!',   settings: { stability: 0.40, similarity_boost: 0.75, style: 0.30, use_speaker_boost: true, speed: 0.80 } },
  { id: 'amazing',      text: 'Amazing!',        settings: { stability: 0.30, similarity_boost: 0.75, style: 0.50, use_speaker_boost: true, speed: 0.85 } },
  { id: 'lets_spell_it', text: "Let's spell it!", settings: { stability: 0.35, similarity_boost: 0.75, style: 0.40, use_speaker_boost: true, speed: 0.85 } },
  // 本书用到的完整单词发音
  { id: 'word_bed', text: 'bed' },
  { id: 'word_hug', text: 'hug' },
  { id: 'word_snack', text: 'snack' },
  { id: 'word_dog', text: 'dog' },
  { id: 'word_small', text: 'small' },
  { id: 'word_yellow', text: 'yellow' },
  { id: 'word_play', text: 'play' },
];

async function generatePhoneme(phoneme) {
  const outputPath = path.join(OUTPUT_DIR, `${phoneme.id}.mp3`);
  
  if (fs.existsSync(outputPath)) {
    console.log(`⏭️  跳过: ${phoneme.id}.mp3`);
    return;
  }

  console.log(`🎙️  生成: ${phoneme.id} (${phoneme.text}) ...`);

  const response = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${VOICE_ID}`, {
    method: 'POST',
    headers: { 'xi-api-key': apiKey, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      text: phoneme.text,
      model_id: 'eleven_multilingual_v2',
      voice_settings: phoneme.settings || { stability: 0.8, similarity_boost: 0.8, style: 0.0, use_speaker_boost: false, speed: 0.7 }
    })
  });

  if (!response.ok) {
    console.error(`❌ 失败 ${phoneme.id}: ${response.status}`);
    return;
  }

  const buffer = await response.arrayBuffer();
  fs.writeFileSync(outputPath, Buffer.from(buffer));
  console.log(`✅ 完成: ${phoneme.id}.mp3`);
  await new Promise(r => setTimeout(r, 300));
}

async function main() {
  console.log(`\n🔤 BridgeRead自然拼读音素生成器`);
  console.log(`共 ${phonemes.length} 个音素\n`);
  for (const p of phonemes) await generatePhoneme(p);
  console.log('\n🎉 完成！音素文件在 assets/audio/phonemes/');
}

main().catch(console.error);
