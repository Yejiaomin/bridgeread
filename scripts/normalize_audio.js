// BridgeRead - 英文音频音量调整
// 把英文音频降低5dB，和中文火山引擎音量匹配

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const FFMPEG = 'C:\\Users\\llc88\\AppData\\Local\\Microsoft\\WinGet\\Packages\\Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe\\ffmpeg-8.1-full_build\\bin\\ffmpeg.exe';

const AUDIO_DIR = path.join(__dirname, '..', 'assets', 'audio');
const DB_ADJUST = '-5dB'; // 降低5dB，可以调整

// 所有英文音频
const enFiles = [
  'biscuit_intro.mp3',  // 如果intro也大可以加
  'biscuit_p1_en.mp3',
  'biscuit_p2_en.mp3',
  'biscuit_p3_en.mp3',
  'biscuit_p4_en.mp3',
  'biscuit_p5_en.mp3',
  'biscuit_p6_en.mp3',
  'biscuit_p7_en.mp3',
  'biscuit_p8_en.mp3',
  'biscuit_p9_en.mp3',
  'biscuit_p10_en.mp3',
  'biscuit_p11_en.mp3',
  'biscuit_done.mp3',
];

console.log(`\n🔊 调整英文音频音量 (${DB_ADJUST})\n`);

for (const file of enFiles) {
  const inputPath = path.join(AUDIO_DIR, file);
  if (!fs.existsSync(inputPath)) {
    console.log(`⏭️  跳过（不存在）: ${file}`);
    continue;
  }

  const tempPath = path.join(AUDIO_DIR, `_temp_${file}`);
  try {
    execSync(`"${FFMPEG}" -y -i "${inputPath}" -filter:a "volume=${DB_ADJUST}" "${tempPath}" -loglevel quiet`);
    fs.renameSync(tempPath, inputPath);
    console.log(`✅ 完成: ${file}`);
  } catch (err) {
    console.error(`❌ 失败: ${file}`, err.message);
    if (fs.existsSync(tempPath)) fs.unlinkSync(tempPath);
  }
}

console.log('\n🎉 完成！按 R 重启App听听效果');
