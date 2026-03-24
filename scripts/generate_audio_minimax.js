// BridgeRead - MiniMax T2A 音频生成脚本
// 声音: moss_audio_4d21f24c-2314-11f1-a876-4a9c6fb96b53 (全部语言)

const fs = require('fs');
const path = require('path');

// 从环境变量读取key
const apiKey = process.env.MINIMAX_API_KEY;

if (!apiKey) {
  console.error('找不到MINIMAX_API_KEY 环境变量');
  process.exit(1);
}

const VOICE_ID = 'moss_audio_4d21f24c-2314-11f1-a876-4a9c6fb96b53';
const OUTPUT_DIR = path.join(__dirname, '..', 'assets', 'audio');
const GROUP_ID = ''; // MiniMax T2A Pro 需要 group_id，如果不需要留空

// MiniMax T2A API endpoint
// 国内用 api.minimaxi.com，国际用 api.minimax.io
const BASE_URL = 'https://api.minimaxi.com/v1/t2a_v2';

if (!fs.existsSync(OUTPUT_DIR)) {
  fs.mkdirSync(OUTPUT_DIR, { recursive: true });
}

const audioScripts = [
  { id: 'biscuit_p1_cn', text: '你们看！这就是今天的小主角，一只叫Biscuit的小狗！他个子小小的，毛是黄色的，超级可爱！' },
  { id: 'biscuit_p1_en', text: 'This is Biscuit. Biscuit is small. Biscuit is yellow.' },
  { id: 'biscuit_p2_cn', text: '到睡觉时间啦！小女孩叫Biscuit去睡觉。bed就是小床，Time for bed就是该上床睡觉啦！' },
  { id: 'biscuit_p2_en', text: 'Time for bed, Biscuit!' },
  { id: 'biscuit_p3_cn', text: '哎，Biscuit不睡！他想玩！play就是玩耍。Biscuit wants to play——小饼干想要玩！' },
  { id: 'biscuit_p3_en', text: 'Woof, woof! Biscuit wants to play.' },
  { id: 'biscuit_intro', text: "Hello! I am Biscuit! Are you ready for a story? Let's go!" },
  { id: 'biscuit_done', text: 'Great job! You finished today\'s story! See you tomorrow!' }
];

async function generateAudio(script) {
  const outputPath = path.join(OUTPUT_DIR, `${script.id}.mp3`);
  console.log(`🎙️  生成中: ${script.id} ...`);

  try {
    const body = {
      model: 'speech-02-hd',
      text: script.text,
      stream: false,
      voice_setting: {
        voice_id: VOICE_ID,
        speed: 1.0,
        vol: 1.0,
        pitch: 0
      },
      audio_setting: {
        sample_rate: 32000,
        bitrate: 128000,
        format: 'mp3',
        channel: 1
      }
    };

    const headers = {
      'Authorization': `Bearer ${apiKey}`,
      'Content-Type': 'application/json'
    };

    const response = await fetch(BASE_URL, {
      method: 'POST',
      headers,
      body: JSON.stringify(body)
    });

    if (!response.ok) {
      const err = await response.text();
      console.error(`❌ 失败 ${script.id}: HTTP ${response.status} ${err}`);
      return false;
    }

    const data = await response.json();

    // MiniMax T2A v2 返回 base64 编码的音频
    if (data.data?.audio) {
      const audioBuffer = Buffer.from(data.data.audio, 'hex');
      fs.writeFileSync(outputPath, audioBuffer);
      console.log(`✅ 完成: ${script.id}.mp3 (${audioBuffer.length} bytes)`);
      return true;
    } else if (data.audio_file) {
      // 旧版API返回URL，需要下载
      const audioResp = await fetch(data.audio_file);
      const buffer = await audioResp.arrayBuffer();
      fs.writeFileSync(outputPath, Buffer.from(buffer));
      console.log(`✅ 完成: ${script.id}.mp3 (${buffer.byteLength} bytes)`);
      return true;
    } else {
      console.error(`❌ 未知响应格式 ${script.id}:`, JSON.stringify(data).slice(0, 300));
      return false;
    }

  } catch (err) {
    console.error(`❌ 错误 ${script.id}:`, err.message);
    return false;
  }
}

async function main() {
  console.log(`\n🎵 BridgeRead MiniMax 音频生成器`);
  console.log(`声音ID: ${VOICE_ID}`);
  console.log(`文件数: ${audioScripts.length}\n`);

  let success = 0;
  let failed = 0;

  for (const script of audioScripts) {
    const ok = await generateAudio(script);
    if (ok) success++;
    else failed++;
    // 避免触发rate limit
    await new Promise(r => setTimeout(r, 500));
  }

  console.log(`\n🎉 完成！成功: ${success} / 失败: ${failed}`);
  console.log(`音频文件在: ${OUTPUT_DIR}`);
}

main().catch(console.error);
