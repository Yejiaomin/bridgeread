// BridgeRead - ElevenLabs音频生成（含词级时间戳）
// 使用 /with-timestamps 接口获取每个词的精确时间

const fs = require('fs');
const path = require('path');

const envPath = path.join(__dirname, '..', '.env');
const env = fs.readFileSync(envPath, 'utf8');
const apiKey = env.match(/ELEVENLABS_API_KEY=(.+)/)?.[1]?.trim();

if (!apiKey) { console.error('找不到ELEVENLABS_API_KEY'); process.exit(1); }

const VOICE_ID = 'Jc4YwsPLA7v0dPpX2dEN'; // potato的克隆声音
const OUTPUT_DIR = path.join(__dirname, '..', 'assets', 'audio');
const TIMESTAMPS_DIR = path.join(__dirname, '..', 'assets', 'audio', 'timestamps');

if (!fs.existsSync(OUTPUT_DIR)) fs.mkdirSync(OUTPUT_DIR, { recursive: true });
if (!fs.existsSync(TIMESTAMPS_DIR)) fs.mkdirSync(TIMESTAMPS_DIR, { recursive: true });

// 需要生成的英文音频（中文不需要时间戳，词高亮只在英文时触发）
const enScripts = [
  { id: 'biscuit_p1_en', text: 'This is Biscuit. Biscuit is small. Biscuit is yellow.', keywords: ['small', 'yellow'] },
  { id: 'biscuit_p2_en', text: 'Time for bed, Biscuit!', keywords: ['bed'] },
  { id: 'biscuit_p3_en', text: 'Woof, woof! Biscuit wants to play.', keywords: ['play'] },
];

async function generateWithTimestamps(script) {
  const audioPath = path.join(OUTPUT_DIR, `${script.id}.mp3`);
  const tsPath = path.join(TIMESTAMPS_DIR, `${script.id}.json`);

  console.log(`🎙️  生成: ${script.id} ...`);

  try {
    const response = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${VOICE_ID}/with-timestamps`, {
      method: 'POST',
      headers: {
        'xi-api-key': apiKey,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        text: script.text,
        model_id: 'eleven_multilingual_v2',
        voice_settings: {
          stability: 0.6,
          similarity_boost: 0.75,
          style: 0.2,
          use_speaker_boost: true,
          speed: 0.85
        }
      })
    });

    if (!response.ok) {
      const err = await response.text();
      console.error(`❌ 失败 ${script.id}: ${response.status} ${err}`);
      return null;
    }

    const data = await response.json();

    // 保存音频
    const audioBuffer = Buffer.from(data.audio_base64, 'base64');
    fs.writeFileSync(audioPath, audioBuffer);
    console.log(`✅ 音频保存: ${script.id}.mp3`);

    // 提取关键词时间戳
    const alignment = data.alignment;
    const keywordTimings = {};

    if (alignment && alignment.characters) {
      // 重建词级时间戳
      let words = [];
      let currentWord = '';
      let wordStart = null;
      let wordEnd = null;

      for (let i = 0; i < alignment.characters.length; i++) {
        const char = alignment.characters[i];
        const startTime = alignment.character_start_times_seconds[i];
        const endTime = alignment.character_end_times_seconds[i];

        if (char === ' ' || char === '.' || char === ',' || char === '!' || char === '?') {
          if (currentWord) {
            words.push({ word: currentWord.toLowerCase(), start: wordStart, end: wordEnd });
            currentWord = '';
            wordStart = null;
          }
        } else {
          if (!wordStart) wordStart = startTime;
          currentWord += char;
          wordEnd = endTime;
        }
      }
      if (currentWord) {
        words.push({ word: currentWord.toLowerCase(), start: wordStart, end: wordEnd });
      }

      // 找到关键词的时间戳
      for (const keyword of script.keywords) {
        const match = words.find(w => w.word === keyword.toLowerCase());
        if (match) {
          keywordTimings[keyword] = {
            startMs: Math.round(match.start * 1000),
            endMs: Math.round(match.end * 1000)
          };
          console.log(`  📍 "${keyword}" 出现在 ${match.start.toFixed(2)}s - ${match.end.toFixed(2)}s`);
        } else {
          console.log(`  ⚠️  未找到关键词: "${keyword}"`);
        }
      }

      // 保存时间戳文件
      const tsData = { text: script.text, keywords: keywordTimings, allWords: words };
      fs.writeFileSync(tsPath, JSON.stringify(tsData, null, 2));
      console.log(`✅ 时间戳保存: timestamps/${script.id}.json`);
    }

    await new Promise(r => setTimeout(r, 500));
    return keywordTimings;

  } catch (err) {
    console.error(`❌ 错误 ${script.id}:`, err.message);
    return null;
  }
}

async function main() {
  console.log('\n🎵 BridgeRead音频生成器（含时间戳）\n');

  const allTimings = {};

  for (const script of enScripts) {
    const timings = await generateWithTimestamps(script);
    if (timings) allTimings[script.id] = timings;
  }

  // 输出JSON更新建议
  console.log('\n\n📋 请将以下时间戳更新到JSON的highlights里：\n');
  for (const [audioId, timings] of Object.entries(allTimings)) {
    console.log(`${audioId}:`);
    for (const [word, timing] of Object.entries(timings)) {
      console.log(`  "${word}" → delayMs: ${timing.startMs}`);
    }
  }

  // 自动更新JSON
  const jsonPath = path.join(__dirname, '..', 'assets', 'lessons', 'biscuit_book1_day1.json');
  const lesson = JSON.parse(fs.readFileSync(jsonPath, 'utf8'));

  const audioToPageIndex = {
    'biscuit_p1_en': 1,
    'biscuit_p2_en': 2,
    'biscuit_p3_en': 3,
  };

  for (const [audioId, timings] of Object.entries(allTimings)) {
    const pageIdx = audioToPageIndex[audioId];
    if (pageIdx !== undefined && lesson.pages[pageIdx]?.highlights) {
      lesson.pages[pageIdx].highlights.forEach(h => {
        if (timings[h.word]) {
          h.delayMs = timings[h.word].startMs;
          console.log(`✅ 更新 ${h.word} delayMs = ${h.delayMs}ms`);
        }
      });
    }
  }

  fs.writeFileSync(jsonPath, JSON.stringify(lesson, null, 2));
  console.log('\n✅ JSON自动更新完成！');
  console.log('\n⚠️  还需要更新Flutter代码使用delayMs字段触发高亮');
}

main().catch(console.error);
