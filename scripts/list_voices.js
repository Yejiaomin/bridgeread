// 列出ElevenLabs可用声音
const fs = require('fs');
const path = require('path');

// 从.env读取key
const envPath = path.join(__dirname, '..', '.env');
const env = fs.readFileSync(envPath, 'utf8');
const apiKey = env.match(/ELEVENLABS_API_KEY=(.+)/)?.[1]?.trim();

if (!apiKey) {
  console.error('找不到ELEVENLABS_API_KEY');
  process.exit(1);
}

async function listVoices() {
  const res = await fetch('https://api.elevenlabs.io/v1/voices', {
    headers: { 'xi-api-key': apiKey }
  });
  const data = await res.json();
  console.log('\n可用声音列表：\n');
  data.voices.forEach(v => {
    console.log(`名字: ${v.name}`);
    console.log(`ID:   ${v.voice_id}`);
    console.log(`类别: ${v.category}`);
    console.log('---');
  });
}

listVoices().catch(console.error);
