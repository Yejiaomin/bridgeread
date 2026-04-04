#!/usr/bin/env node
/**
 * BridgeRead — One-click new book pipeline.
 *
 * Usage:
 *   node scripts/add_new_book.js <bookNum> "<Book Title>" <prefix> "<中文名>"
 *
 * Example:
 *   node scripts/add_new_book.js 04 "Biscuit Finds a Friend" friend "小饼干找朋友"
 *
 * Prerequisites:
 *   - assets/books/<folder>/book.pdf + audio.mp3
 *
 * Automates ALL steps:
 *   1. Split PDF → merge spreads
 *   2. OCR pages (Google Vision)
 *   3. STT page timing (Google Speech-to-Text)
 *   4. Generate lesson JSON with Chinese narration
 *   5. Generate all audio (火山引擎 CN + ElevenLabs EN)
 *   6. Register in 4 Dart files + pubspec.yaml
 */

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { execSync } = require('child_process');

// ── Args ────────────────────────────────────────────────────────────────────
const [,, bookNum, bookTitle, prefix, titleCN] = process.argv;

if (!bookNum || !bookTitle || !prefix) {
  console.log('Usage: node scripts/add_new_book.js <bookNum> "<Book Title>" <prefix> "<中文名>"');
  process.exit(1);
}

// ── Config ──────────────────────────────────────────────────────────────────
const FFMPEG = 'C:/Users/llc88/AppData/Local/Microsoft/WinGet/Packages/Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe/ffmpeg-8.1-full_build/bin/ffmpeg.exe';
const MAGICK = 'magick';
const BOOKS_DIR = path.join(__dirname, '..', 'assets', 'books');
const LESSONS_DIR = path.join(__dirname, '..', 'assets', 'lessons');
const AUDIO_DIR = path.join(__dirname, '..', 'assets', 'audio');
const LIB_DIR = path.join(__dirname, '..', 'lib');

const envPath = path.join(__dirname, '..', '.env');
const env = fs.readFileSync(envPath, 'utf8');
const apiKey = env.match(/GOOGLE_CLOUD_API_KEY=(.+)/)?.[1]?.trim();
const elevenLabsKey = env.match(/ELEVENLABS_API_KEY=(.+)/)?.[1]?.trim();
const ttsApiKey = env.match(/TTS_API_KEY=(.+)/)?.[1]?.trim();
const ttsAppId = env.match(/TTS_APP_ID=(.+)/)?.[1]?.trim();
const ttsVoiceId = 'S_MnneA1cX1';
const VOICE_ID_EN = 'kbFeB8Ko2KgpldlKCYQA';

// Find book folder
const folders = fs.readdirSync(BOOKS_DIR).filter(f =>
  f.startsWith(bookNum) && fs.statSync(path.join(BOOKS_DIR, f)).isDirectory()
);
if (folders.length === 0) { console.error(`No folder starting with ${bookNum}`); process.exit(1); }

const folderName = folders[0];
const bookDir = path.join(BOOKS_DIR, folderName);
const pdfPath = path.join(bookDir, 'book.pdf');
const audioPath = path.join(bookDir, 'audio.mp3');
const lessonId = `${prefix}_book${bookNum}_day1`;
const lessonFile = path.join(LESSONS_DIR, `${lessonId}.json`);

console.log(`\n📖 Adding: ${bookTitle}`);
console.log(`   Folder: ${folderName}`);
console.log(`   Lesson: ${lessonId}\n`);

// ── Step 1 & 2: Split PDF + Merge Spreads ──────────────────────────────────
async function splitAndMerge() {
  const existing = fs.readdirSync(bookDir).filter(f => f.startsWith('spread_') && f.endsWith('.webp'));
  if (existing.length > 0) { console.log(`⏭ Step 1-2: Already has ${existing.length} spreads`); return; }
  if (!fs.existsSync(pdfPath)) { console.log('⏭ Step 1-2: No book.pdf'); return; }

  console.log('── Step 1: Splitting PDF ──');
  const sharp = require('sharp');
  const tmpDir = path.join(bookDir, '_tmp');
  if (!fs.existsSync(tmpDir)) fs.mkdirSync(tmpDir);
  execSync(`${MAGICK} -density 200 "${pdfPath}" -quality 90 "${tmpDir}/page_%02d.png"`, { stdio: 'pipe', timeout: 120000 });

  const pngFiles = fs.readdirSync(tmpDir).filter(f => f.endsWith('.png')).sort();
  console.log(`  ${pngFiles.length} pages`);

  // Convert: page 1 = cover, rest = singles
  const singles = [];
  for (let i = 0; i < pngFiles.length; i++) {
    const src = path.join(tmpDir, pngFiles[i]);
    const outName = i === 0 ? 'cover.webp' : `_s_${String(i + 1).padStart(2, '0')}.webp`;
    await sharp(src).webp({ quality: 82 }).toFile(path.join(bookDir, outName));
    fs.unlinkSync(src);
    if (i > 0) singles.push(outName);
  }
  fs.rmdirSync(tmpDir);

  console.log('── Step 2: Merging spreads ──');
  let num = 1;
  for (let i = 0; i < singles.length; i += 2) {
    const left = path.join(bookDir, singles[i]);
    const right = i + 1 < singles.length ? path.join(bookDir, singles[i + 1]) : null;
    const out = path.join(bookDir, `spread_${String(num).padStart(2, '0')}.webp`);

    if (!right) {
      fs.renameSync(left, out);
    } else {
      const lm = await sharp(left).metadata();
      const rm = await sharp(right).metadata();
      const h = Math.max(lm.height, rm.height);
      const lb = await sharp(left).resize({ height: h, fit: 'contain' }).toBuffer();
      const rb = await sharp(right).resize({ height: h, fit: 'contain' }).toBuffer();
      await sharp({ create: { width: lm.width + rm.width, height: h, channels: 3, background: { r: 255, g: 255, b: 255 } } })
        .composite([{ input: lb, left: 0, top: 0 }, { input: rb, left: lm.width, top: 0 }])
        .webp({ quality: 82 }).toFile(out);
      fs.unlinkSync(left);
      fs.unlinkSync(right);
    }
    num++;
  }
  console.log(`  ✓ ${num - 1} spreads`);
}

// ── Step 3: OCR ─────────────────────────────────────────────────────────────
async function ocrPages() {
  const ocrFile = path.join(bookDir, '_ocr.json');
  if (fs.existsSync(ocrFile)) {
    console.log('⏭ Step 3: OCR exists');
    return JSON.parse(fs.readFileSync(ocrFile, 'utf8'));
  }
  console.log('── Step 3: OCR ──');
  const imgs = fs.readdirSync(bookDir).filter(f => (f.startsWith('spread_') || f === 'cover.webp') && f.endsWith('.webp')).sort();
  const results = [];
  for (const img of imgs) {
    const bytes = fs.readFileSync(path.join(bookDir, img)).toString('base64');
    const res = await fetch(`https://vision.googleapis.com/v1/images:annotate?key=${apiKey}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ requests: [{ image: { content: bytes }, features: [{ type: 'TEXT_DETECTION' }] }] }),
    });
    const text = ((await res.json()).responses?.[0]?.fullTextAnnotation?.text || '').trim();
    results.push({ page: img, text });
    console.log(`  ${img}: "${text.replace(/\n/g, ' ').slice(0, 50)}..."`);
    await new Promise(r => setTimeout(r, 300));
  }
  fs.writeFileSync(ocrFile, JSON.stringify(results, null, 2));
  return results;
}

// ── Step 4: STT ─────────────────────────────────────────────────────────────
async function sttTiming() {
  if (!fs.existsSync(audioPath)) { console.log('⏭ Step 4: No audio'); return []; }
  console.log('── Step 4: STT timing ──');
  let durStr = ''; try { durStr = execSync(`"${FFMPEG}" -i "${audioPath}" 2>&1`).toString(); } catch (e) { durStr = e.stdout?.toString() || ''; }
  const dm = durStr.match(/Duration: (\d+):(\d+):(\d+\.\d+)/);
  const dur = dm ? parseInt(dm[1]) * 3600 + parseInt(dm[2]) * 60 + parseFloat(dm[3]) : 0;
  console.log(`  Duration: ${dur.toFixed(1)}s`);

  const words = [];
  for (let s = 0, i = 0; s < dur; s += 55, i++) {
    const d = Math.min(55, dur - s);
    const flac = path.join(bookDir, `_seg${i}.flac`);
    execSync(`"${FFMPEG}" -y -ss ${s} -t ${d} -i "${audioPath}" -ac 1 -ar 16000 "${flac}"`, { stdio: 'pipe' });
    const res = await fetch(`https://speech.googleapis.com/v1/speech:recognize?key=${apiKey}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        config: { encoding: 'FLAC', sampleRateHertz: 16000, languageCode: 'en-US', enableWordTimeOffsets: true, model: 'latest_long', useEnhanced: true },
        audio: { content: fs.readFileSync(flac).toString('base64') },
      }),
    });
    const data = await res.json();
    fs.unlinkSync(flac);
    for (const r of data.results || []) {
      for (const w of r.alternatives?.[0]?.words || []) {
        words.push({ word: w.word.toLowerCase(), start: parseFloat(w.startTime?.replace('s', '') || '0') + s });
      }
    }
    process.stdout.write(`  Seg ${i + 1}... `);
  }
  console.log(`\n  ${words.length} words`);
  return words;
}

// ── Step 5: Generate Chinese narration ──────────────────────────────────────
function generateNarrativeCN(englishText) {
  // Amy 老师风格的中文讲解模板
  const text = englishText.replace(/\n/g, ' ').replace(/\d+\s*$/, '').trim();
  if (!text) return '';

  // Extract key words (nouns, adjectives, verbs > 3 chars)
  const words = text.split(/\s+/).filter(w => w.replace(/[^a-zA-Z]/g, '').length > 3);
  const keyword = words.find(w => !['biscuit', 'woof', 'that', 'this', 'what', 'where', 'there', 'here'].includes(w.toLowerCase().replace(/[^a-z]/g, '')));
  const kwClean = keyword ? keyword.replace(/[^a-zA-Z]/g, '') : '';

  // Simple templates based on content patterns
  if (text.toLowerCase().includes('woof') && text.length < 30) {
    return `Biscuit又在叫啦！Woof woof！你觉得他在说什么呢？`;
  }
  if (kwClean) {
    return `你听到了吗？${kwClean}就是${kwClean}的意思。${text.split('.')[0].trim()}。你能跟我说一遍 ${kwClean} 吗？`;
  }
  return `我们来听听看发生了什么。${text.split('.')[0].trim()}。`;
}

// ── Step 6: Build lesson JSON ───────────────────────────────────────────────
function buildLesson(ocrResults, sttWords) {
  if (fs.existsSync(lessonFile)) { console.log('⏭ Step 5: Lesson JSON exists'); return; }
  console.log('── Step 5: Building lesson JSON ──');

  const storyPages = ocrResults.filter(p =>
    p.page.startsWith('spread_') && p.text.length > 10 &&
    !p.text.includes('ISBN') && !p.text.includes('HOORAY') &&
    !p.text.includes('HarperCollins') && !p.text.includes('copyright')
  );

  const pages = [{
    imageAsset: `assets/books/${folderName}/cover.webp`,
    narrativeCN: `Hello Hello, my dear friend！I am Amy! How are you？...... I'm good！Good！今天我们要讲${bookTitle}的故事！Are you ready？Let's go！`,
    narrativeEN: '', keywords: [], audioCN: `${prefix}_intro`, audioEN: null,
    highlights: [], characterPos: { x: 0.75, y: 0.7, action: 'excited' },
  }];

  let searchFrom = 0;
  for (let i = 0; i < storyPages.length; i++) {
    const sp = storyPages[i];
    const text = sp.text.replace(/\n/g, ' ').replace(/\d+\s*$/, '').trim();
    const searchWord = text.toLowerCase().split(/\s+/).filter(w => w.replace(/[^a-z]/g, '').length > 2)[0]?.replace(/[^a-z]/g, '') || '';

    let startMs = null;
    if (searchWord) {
      for (let j = searchFrom; j < sttWords.length; j++) {
        if (sttWords[j].word.replace(/[^a-z]/g, '') === searchWord) {
          startMs = Math.round(sttWords[j].start * 1000);
          searchFrom = j + 1;
          break;
        }
      }
    }

    // Extract keywords (words > 3 chars, not common)
    const common = new Set(['biscuit','woof','that','this','what','where','there','here','with','have','does','will','your','they','them','just','very','come','more','over','even','found','want','wants','time','it\'s']);
    const keywords = [...new Set(text.toLowerCase().split(/[^a-z]+/).filter(w => w.length > 3 && !common.has(w)))].slice(0, 2);

    const page = {
      imageAsset: `assets/books/${folderName}/${sp.page}`,
      teacherExpression: 'happy',
      narrativeCN: generateNarrativeCN(text),
      narrativeEN: text,
      keywords,
      audioCN: `${prefix}_p${i + 1}_cn`,
      audioEN: `${prefix}_p${i + 1}_en`,
      highlights: [],
      characterPos: { x: 0.75, y: 0.7, action: 'excited' },
    };
    if (startMs !== null) page.pageStartMs = startMs;
    pages.push(page);
  }

  // Done page
  pages.push({
    imageAsset: `assets/books/${folderName}/${storyPages[storyPages.length - 1]?.page || 'cover.webp'}`,
    narrativeCN: `今天的故事讲完啦！${bookTitle}真是太有趣了！你学会了哪些新单词呀？我们明天再见哦！`,
    narrativeEN: '', keywords: [], audioCN: `${prefix}_done`, audioEN: null,
    highlights: [], characterPos: { x: 0.75, y: 0.7, action: 'excited' },
  });

  const lesson = {
    id: lessonId, bookTitle, characterName: 'Biscuit',
    characterAsset: 'assets/characters/teacher_default.webp',
    featuredSentence: storyPages[0]?.text.split('\n')[0].replace(/\d+\s*$/, '').trim() || bookTitle,
    originalAudio: `books/${folderName}/audio.mp3`,
    pages,
    phonicsWords: [],
  };

  fs.writeFileSync(lessonFile, JSON.stringify(lesson, null, 2));
  console.log(`  ✓ ${storyPages.length} story pages`);
}

// ── Step 7: Generate audio ──────────────────────────────────────────────────
async function generateAudio() {
  console.log('── Step 6: Generating audio ──');
  const lesson = JSON.parse(fs.readFileSync(lessonFile, 'utf8'));

  const scripts = [];
  for (const page of lesson.pages) {
    if (page.audioCN) {
      scripts.push({ id: page.audioCN, text: page.narrativeCN, lang: 'cn' });
    }
    if (page.audioEN && page.narrativeEN) {
      scripts.push({ id: page.audioEN, text: page.narrativeEN, lang: 'en', keywords: page.keywords || [] });
    }
  }
  // Featured sentence for recording
  scripts.push({ id: `${prefix}_featured`, text: lesson.featuredSentence, lang: 'en', keywords: [] });

  for (const s of scripts) {
    const outPath = path.join(AUDIO_DIR, `${s.id}.mp3`);
    if (fs.existsSync(outPath)) { console.log(`  ⏭ ${s.id}`); continue; }

    try {
      if (s.lang === 'cn') {
        const res = await fetch('https://openspeech.bytedance.com/api/v1/tts', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer;${ttsApiKey}` },
          body: JSON.stringify({
            app: { appid: ttsAppId, token: ttsApiKey, cluster: 'volcano_icl' },
            user: { uid: 'bridgeread' },
            audio: { voice_type: ttsVoiceId, encoding: 'mp3', speed_ratio: 1.0, volume_ratio: 1.0, pitch_ratio: 1.0 },
            request: { reqid: crypto.randomUUID(), text: s.text, text_type: 'plain', operation: 'query' },
          }),
        });
        const json = await res.json();
        if (!json.data) throw new Error('火山引擎无数据');
        fs.writeFileSync(outPath, Buffer.from(json.data, 'base64'));
      } else {
        const endpoint = s.keywords?.length > 0
          ? `https://api.elevenlabs.io/v1/text-to-speech/${VOICE_ID_EN}/with-timestamps`
          : `https://api.elevenlabs.io/v1/text-to-speech/${VOICE_ID_EN}`;
        const res = await fetch(endpoint, {
          method: 'POST',
          headers: { 'xi-api-key': elevenLabsKey, 'Content-Type': 'application/json' },
          body: JSON.stringify({
            text: s.text, model_id: 'eleven_multilingual_v2',
            voice_settings: { stability: 0.6, similarity_boost: 0.75, style: 0.2, use_speaker_boost: false, speed: 1.0 },
          }),
        });
        if (!res.ok) throw new Error(`ElevenLabs ${res.status}`);
        if (s.keywords?.length > 0) {
          const data = await res.json();
          fs.writeFileSync(outPath, Buffer.from(data.audio_base64, 'base64'));
        } else {
          fs.writeFileSync(outPath, Buffer.from(await res.arrayBuffer()));
        }
      }
      console.log(`  ✓ ${s.id} (${s.lang})`);
      await new Promise(r => setTimeout(r, 500));
    } catch (e) {
      console.error(`  ✗ ${s.id}: ${e.message}`);
    }
  }
}

// ── Step 8: Register in app ─────────────────────────────────────────────────
function registerInApp() {
  console.log('── Step 7: Registering in app ──');

  // Find previous book's lesson ID and audio
  const lessonOrderFile = path.join(LIB_DIR, 'screens', 'listen_screen.dart');
  const listenContent = fs.readFileSync(lessonOrderFile, 'utf8');
  const orderMatch = [...listenContent.matchAll(/\('([^']+)',\s*'([^']+)',\s*'([^']+)'\)/g)];
  const prevEntry = orderMatch[orderMatch.length - 1];
  const prevLessonId = prevEntry ? prevEntry[1] : 'biscuit_book1_day1';
  const prevAudio = prevEntry ? prevEntry[3] : 'audio/biscuit_original.mp3';
  const bookNumInt = parseInt(bookNum);

  // 1. home_screen.dart → _kBooks
  const homeFile = path.join(LIB_DIR, 'screens', 'home_screen.dart');
  let home = fs.readFileSync(homeFile, 'utf8');
  const homeEntry = `  _BookDay(${bookNumInt}, '${bookTitle}', '${titleCN || bookTitle}', '${lessonId}', 'assets/books/${folderName}/cover.webp'),`;
  if (!home.includes(lessonId)) {
    home = home.replace('  // 后续书籍在这里添加', `${homeEntry}\n  // 后续书籍在这里添加`);
    fs.writeFileSync(homeFile, home);
    console.log('  ✓ home_screen.dart');
  }

  // 2. recording_screen.dart → _featuredAudioMap
  const recFile = path.join(LIB_DIR, 'screens', 'recording_screen.dart');
  let rec = fs.readFileSync(recFile, 'utf8');
  if (!rec.includes(lessonId)) {
    rec = rec.replace(/(_featuredAudioMap = \{[^}]*)(};)/s, `$1    '${lessonId}': 'audio/${prefix}_featured.mp3',\n  $2`);
    fs.writeFileSync(recFile, rec);
    console.log('  ✓ recording_screen.dart');
  }

  // 3. study_screen.dart → _prevBookMap
  const studyFile = path.join(LIB_DIR, 'screens', 'study_screen.dart');
  let study = fs.readFileSync(studyFile, 'utf8');
  if (!study.includes(lessonId)) {
    study = study.replace(/(_prevBookMap = \{[^}]*)(};)/s, `$1    '${lessonId}': ('${prevLessonId}', '${prevAudio}'),\n  $2`);
    fs.writeFileSync(studyFile, study);
    console.log('  ✓ study_screen.dart');
  }

  // 4. listen_screen.dart → _kLessonOrder
  if (!listenContent.includes(lessonId)) {
    const newEntry = `    ('${lessonId}', '${bookTitle}', 'books/${folderName}/audio.mp3'),`;
    const updated = listenContent.replace(/(static const _kLessonOrder = \[[^\]]*)(];)/s, `$1${newEntry}\n  $2`);
    fs.writeFileSync(lessonOrderFile, updated);
    console.log('  ✓ listen_screen.dart');
  }

  // 5. pubspec.yaml
  const pubFile = path.join(__dirname, '..', 'pubspec.yaml');
  let pub = fs.readFileSync(pubFile, 'utf8');
  const assetLine = `    - assets/books/${folderName}/`;
  if (!pub.includes(assetLine)) {
    pub = pub.replace('    - assets/video/', `${assetLine}\n    - assets/video/`);
    fs.writeFileSync(pubFile, pub);
    console.log('  ✓ pubspec.yaml');
  }
}

// ── Main ────────────────────────────────────────────────────────────────────
async function main() {
  if (!fs.existsSync(bookDir)) { console.error(`Folder not found: ${bookDir}`); process.exit(1); }

  await splitAndMerge();
  const ocr = await ocrPages();
  const stt = await sttTiming();
  buildLesson(ocr, stt);
  await generateAudio();
  registerInApp();

  console.log(`
══════════════════════════════════════════════
  ✅ Book ${bookNum} "${bookTitle}" complete!

  📝 Please review:
  1. ${lessonFile}
     - Check narrativeCN (auto-generated, may need polish)
     - Check pageStartMs timing
     - Add phonicsWords if needed
  2. Run: flutter run -d chrome (test all modules)
  3. Push: git add -A && git commit && git push
══════════════════════════════════════════════
`);
}

main().catch(e => { console.error(e); process.exit(1); });
