// BridgeRead - 从Starfall下载标准自然拼读音素
const https = require('https');
const fs = require('fs');
const path = require('path');

const OUTPUT_DIR = path.join(__dirname, '..', 'assets', 'audio', 'phonemes');
if (!fs.existsSync(OUTPUT_DIR)) fs.mkdirSync(OUTPUT_DIR, { recursive: true });

// Starfall音素URL规律: https://www.starfall.com/h/abcs/letter-X/sounds/Xwav.mp3
const phonemes = [
  { id: 'b', letter: 'b' },
  { id: 'd', letter: 'd' },
  { id: 'e_short', letter: 'e', customUrl: 'https://www.starfall.com/h/abcs/letter-e/sounds/e_ehwav.mp3' },
  { id: 'g', letter: 'g', customUrl: 'https://www.starfall.com/h/abcs/letter-g/sounds/gSnd.mp3' },
  { id: 'h', letter: 'h' },
  { id: 'u_short', letter: 'u', customUrl: 'https://www.starfall.com/h/abcs/letter-u/sounds/sunu1wav.mp3' },
  // 其他字母备用
  { id: 'a_short', letter: 'a' },
  { id: 'c', letter: 'c' },
  { id: 'f', letter: 'f' },
  { id: 'i_short', letter: 'i' },
  { id: 'j', letter: 'j' },
  { id: 'k', letter: 'k' },
  { id: 'l', letter: 'l' },
  { id: 'm', letter: 'm' },
  { id: 'n', letter: 'n' },
  { id: 'o_short', letter: 'o' },
  { id: 'p', letter: 'p' },
  { id: 'r', letter: 'r' },
  { id: 's', letter: 's' },
  { id: 't', letter: 't' },
  { id: 'v', letter: 'v' },
  { id: 'w', letter: 'w' },
  { id: 'y', letter: 'y' },
  { id: 'z', letter: 'z' },
];

function download(url, dest) {
  return new Promise((resolve, reject) => {
    const file = fs.createWriteStream(dest);
    https.get(url, { headers: { 'User-Agent': 'Mozilla/5.0' } }, res => {
      if (res.statusCode === 302 || res.statusCode === 301) {
        file.close();
        download(res.headers.location, dest).then(resolve).catch(reject);
        return;
      }
      res.pipe(file);
      file.on('finish', () => { file.close(); resolve(); });
    }).on('error', err => {
      fs.unlink(dest, () => {});
      reject(err);
    });
  });
}

async function main() {
  console.log('\n🔤 从Starfall下载自然拼读音素\n');
  for (const p of phonemes) {
    const url = p.customUrl || `https://www.starfall.com/h/abcs/letter-${p.letter}/sounds/${p.letter}wav.mp3`;
    const dest = path.join(OUTPUT_DIR, `${p.id}.mp3`);
    try {
      console.log(`⬇️  下载: ${p.id} (${p.letter})...`);
      await download(url, dest);
      const size = fs.statSync(dest).size;
      console.log(`✅ ${p.id}.mp3 (${(size/1024).toFixed(1)}KB)`);
    } catch (err) {
      console.error(`❌ 失败: ${p.id} - ${err.message}`);
    }
    await new Promise(r => setTimeout(r, 300));
  }
  console.log('\n🎉 完成！');
}

main().catch(console.error);
