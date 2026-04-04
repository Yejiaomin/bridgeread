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
 *   - assets/books/<bookNum><FolderName>/book.pdf  (绘本 PDF)
 *   - assets/books/<bookNum><FolderName>/audio.mp3 (原版朗读音频)
 *
 * This script will:
 *   1. Split PDF into single pages
 *   2. Merge pages into two-page spreads
 *   3. OCR all pages (Google Vision API)
 *   4. STT analyze audio for page timing (Google Speech-to-Text)
 *   5. Generate lesson JSON skeleton
 *   6. Print what you need to do manually (write narrativeCN, register in app)
 */

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

// ── Args ────────────────────────────────────────────────────────────────────
const [,, bookNum, bookTitle, prefix, titleCN] = process.argv;

if (!bookNum || !bookTitle || !prefix) {
  console.log('Usage: node scripts/add_new_book.js <bookNum> "<Book Title>" <prefix> "<中文名>"');
  console.log('Example: node scripts/add_new_book.js 04 "Biscuit Finds a Friend" friend "小饼干找朋友"');
  process.exit(1);
}

const FFMPEG = 'C:/Users/llc88/AppData/Local/Microsoft/WinGet/Packages/Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe/ffmpeg-8.1-full_build/bin/ffmpeg.exe';
const MAGICK = 'magick';
const BOOKS_DIR = path.join(__dirname, '..', 'assets', 'books');
const LESSONS_DIR = path.join(__dirname, '..', 'assets', 'lessons');

// Find book folder
const folders = fs.readdirSync(BOOKS_DIR).filter(f =>
  f.startsWith(bookNum) && fs.statSync(path.join(BOOKS_DIR, f)).isDirectory()
);

if (folders.length === 0) {
  console.error(`No folder found starting with ${bookNum} in assets/books/`);
  process.exit(1);
}

const folderName = folders[0];
const bookDir = path.join(BOOKS_DIR, folderName);
const pdfPath = path.join(bookDir, 'book.pdf');
const audioPath = path.join(bookDir, 'audio.mp3');
const lessonId = `${prefix}_book${bookNum}_day1`;
const lessonFile = path.join(LESSONS_DIR, `${lessonId}.json`);

console.log(`\n📖 Adding: ${bookTitle} (${folderName})`);
console.log(`   Lesson ID: ${lessonId}`);
console.log(`   Prefix: ${prefix}`);

// ── Env ─────────────────────────────────────────────────────────────────────
const envPath = path.join(__dirname, '..', '.env');
const env = fs.readFileSync(envPath, 'utf8');
const apiKey = env.match(/GOOGLE_CLOUD_API_KEY=(.+)/)?.[1]?.trim();

// ── Step 1: Split PDF ───────────────────────────────────────────────────────
async function splitPdf() {
  if (!fs.existsSync(pdfPath)) {
    console.log('\n⏭ No book.pdf found, skipping PDF split');
    return;
  }

  const existing = fs.readdirSync(bookDir).filter(f => f.startsWith('spread_') && f.endsWith('.webp'));
  if (existing.length > 0) {
    console.log(`\n⏭ Already has ${existing.length} spreads, skipping PDF split`);
    return;
  }

  console.log('\n── Step 1: Splitting PDF into pages ──');
  const tmpDir = path.join(bookDir, '_tmp');
  if (!fs.existsSync(tmpDir)) fs.mkdirSync(tmpDir);

  execSync(`${MAGICK} -density 200 "${pdfPath}" -quality 90 "${tmpDir}/page_%02d.png"`,
    { stdio: 'pipe', timeout: 120000 });

  const pages = fs.readdirSync(tmpDir).filter(f => f.startsWith('page_') && f.endsWith('.png')).sort();
  console.log(`  Found ${pages.length} pages`);

  // Convert to webp: first page = cover, rest = single pages
  const sharp = require('sharp');
  let pageNum = 0;
  const singlePages = [];

  for (const pagePng of pages) {
    pageNum++;
    const pngPath = path.join(tmpDir, pagePng);
    const outName = pageNum === 1 ? 'cover.webp' : `_single_${String(pageNum).padStart(2, '0')}.webp`;
    const outPath = path.join(bookDir, outName);
    await sharp(pngPath).webp({ quality: 82 }).toFile(outPath);
    fs.unlinkSync(pngPath);
    if (pageNum > 1) singlePages.push(outName);
  }
  fs.rmdirSync(tmpDir);
  console.log(`  ✓ cover.webp + ${singlePages.length} single pages`);

  // Step 2: Merge into spreads
  console.log('\n── Step 2: Merging into two-page spreads ──');
  let spreadNum = 1;
  for (let i = 0; i < singlePages.length; i += 2) {
    const leftFile = path.join(bookDir, singlePages[i]);
    const rightFile = (i + 1 < singlePages.length) ? path.join(bookDir, singlePages[i + 1]) : null;
    const outName = `spread_${String(spreadNum).padStart(2, '0')}.webp`;
    const outPath = path.join(bookDir, outName);

    if (!rightFile) {
      fs.renameSync(leftFile, outPath);
    } else {
      const leftMeta = await sharp(leftFile).metadata();
      const rightMeta = await sharp(rightFile).metadata();
      const height = Math.max(leftMeta.height, rightMeta.height);
      const totalWidth = leftMeta.width + rightMeta.width;
      const leftBuf = await sharp(leftFile).resize({ height, fit: 'contain' }).toBuffer();
      const rightBuf = await sharp(rightFile).resize({ height, fit: 'contain' }).toBuffer();

      await sharp({
        create: { width: totalWidth, height, channels: 3, background: { r: 255, g: 255, b: 255 } }
      }).composite([
        { input: leftBuf, left: 0, top: 0 },
        { input: rightBuf, left: leftMeta.width, top: 0 },
      ]).webp({ quality: 82 }).toFile(outPath);

      fs.unlinkSync(leftFile);
      fs.unlinkSync(rightFile);
    }
    const size = (fs.statSync(outPath).size / 1024).toFixed(0);
    console.log(`  ✓ ${outName} (${size}KB)`);
    spreadNum++;
  }
  console.log(`  Done! ${spreadNum - 1} spreads`);
}

// ── Step 3: OCR ─────────────────────────────────────────────────────────────
async function ocrPages() {
  const ocrFile = path.join(bookDir, '_ocr.json');
  if (fs.existsSync(ocrFile)) {
    console.log('\n⏭ _ocr.json already exists, skipping OCR');
    return JSON.parse(fs.readFileSync(ocrFile, 'utf8'));
  }

  console.log('\n── Step 3: OCR pages ──');
  const imageFiles = fs.readdirSync(bookDir)
    .filter(f => (f.startsWith('spread_') || f === 'cover.webp') && f.endsWith('.webp'))
    .sort();

  const results = [];
  for (const img of imageFiles) {
    const imgPath = path.join(bookDir, img);
    const imageBytes = fs.readFileSync(imgPath).toString('base64');
    const res = await fetch(`https://vision.googleapis.com/v1/images:annotate?key=${apiKey}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ requests: [{ image: { content: imageBytes }, features: [{ type: 'TEXT_DETECTION' }] }] }),
    });
    const data = await res.json();
    const text = (data.responses?.[0]?.fullTextAnnotation?.text || '').trim();
    results.push({ page: img, text });
    const preview = text.replace(/\n/g, ' ').slice(0, 60);
    console.log(`  ${img}: "${preview}${text.length > 60 ? '...' : ''}"`);
    await new Promise(r => setTimeout(r, 300));
  }

  fs.writeFileSync(ocrFile, JSON.stringify(results, null, 2));
  console.log(`  Saved: _ocr.json`);
  return results;
}

// ── Step 4: STT page timing ─────────────────────────────────────────────────
async function sttPageTiming() {
  if (!fs.existsSync(audioPath)) {
    console.log('\n⏭ No audio.mp3, skipping STT');
    return [];
  }

  console.log('\n── Step 4: STT page timing ──');

  // Get duration
  let durStr = '';
  try { durStr = execSync(`"${FFMPEG}" -i "${audioPath}" 2>&1`).toString(); } catch (e) { durStr = e.stdout?.toString() || ''; }
  const durMatch = durStr.match(/Duration: (\d+):(\d+):(\d+\.\d+)/);
  const totalDuration = durMatch ? parseInt(durMatch[1]) * 3600 + parseInt(durMatch[2]) * 60 + parseFloat(durMatch[3]) : 0;
  console.log(`  Audio duration: ${totalDuration.toFixed(1)}s`);

  const SEGMENT = 55;
  const allWords = [];

  for (let s = 0, i = 0; s < totalDuration; s += SEGMENT, i++) {
    const dur = Math.min(SEGMENT, totalDuration - s);
    const flacPath = path.join(bookDir, `_seg_${i}.flac`);
    execSync(`"${FFMPEG}" -y -ss ${s} -t ${dur} -i "${audioPath}" -ac 1 -ar 16000 "${flacPath}"`, { stdio: 'pipe' });
    const audioBytes = fs.readFileSync(flacPath).toString('base64');

    const res = await fetch(`https://speech.googleapis.com/v1/speech:recognize?key=${apiKey}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        config: { encoding: 'FLAC', sampleRateHertz: 16000, languageCode: 'en-US', enableWordTimeOffsets: true, model: 'latest_long', useEnhanced: true },
        audio: { content: audioBytes },
      }),
    });
    const data = await res.json();
    fs.unlinkSync(flacPath);
    if (data.error) { console.error(`  Seg ${i} error:`, data.error.message); continue; }

    for (const r of data.results || []) {
      const alt = r.alternatives?.[0];
      if (!alt?.words) continue;
      for (const w of alt.words) {
        const start = parseFloat(w.startTime?.replace('s', '') || '0') + s;
        allWords.push({ word: w.word.toLowerCase(), start });
      }
    }
    process.stdout.write(`  Seg ${i + 1}...\r`);
  }
  console.log(`  Total: ${allWords.length} words from STT`);
  return allWords;
}

// ── Step 5: Generate lesson JSON skeleton ────────────────────────────────────
function generateLessonJson(ocrResults, sttWords) {
  if (fs.existsSync(lessonFile)) {
    console.log('\n⏭ Lesson JSON already exists');
    return;
  }

  console.log('\n── Step 5: Generating lesson JSON ──');

  // Filter to story pages (spreads with text)
  const storyPages = ocrResults.filter(p =>
    p.page.startsWith('spread_') && p.text.length > 10 &&
    !p.text.includes('ISBN') && !p.text.includes('HOORAY') &&
    !p.text.includes('HarperCollins') && !p.text.includes('copyright')
  );

  // Match page text to STT timing
  const pages = [
    // Cover page (no pageStartMs)
    {
      imageAsset: `assets/books/${folderName}/cover.webp`,
      narrativeCN: `Hello Hello, my dear friend！I am Amy! How are you？...... I'm good！Good！今天我们要讲${bookTitle}的故事！Are you ready？Let's go！`,
      narrativeEN: '',
      keywords: [],
      audioCN: `${prefix}_intro`,
      audioEN: null,
      highlights: [],
      characterPos: { x: 0.75, y: 0.7, action: 'excited' },
    },
  ];

  let searchFrom = 0;
  for (let i = 0; i < storyPages.length; i++) {
    const sp = storyPages[i];
    const text = sp.text.replace(/\n/g, ' ').replace(/\d+\s*$/, '').trim();
    const pageWords = text.toLowerCase().split(/\s+/).filter(w => w.replace(/[^a-z]/g, '').length > 2);
    const searchWord = pageWords[0]?.replace(/[^a-z]/g, '') || '';

    let startMs = null;
    if (searchWord && sttWords.length > 0) {
      for (let j = searchFrom; j < sttWords.length; j++) {
        if (sttWords[j].word.replace(/[^a-z]/g, '') === searchWord) {
          startMs = Math.round(sttWords[j].start * 1000);
          searchFrom = j + 1;
          break;
        }
      }
    }

    const page = {
      imageAsset: `assets/books/${folderName}/${sp.page}`,
      teacherExpression: 'happy',
      narrativeCN: `【TODO: 写中文讲解】${text}`,
      narrativeEN: text,
      keywords: [],
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
    narrativeCN: `【TODO: 写结尾】今天的故事讲完啦！你学会了哪些新单词呀？`,
    narrativeEN: '',
    keywords: [],
    audioCN: `${prefix}_done`,
    audioEN: null,
    highlights: [],
    characterPos: { x: 0.75, y: 0.7, action: 'excited' },
  });

  const lesson = {
    id: lessonId,
    bookTitle: bookTitle,
    characterName: 'Biscuit',
    characterAsset: 'assets/characters/teacher_default.webp',
    featuredSentence: storyPages[0]?.text.split('\n')[0] || bookTitle,
    originalAudio: `books/${folderName}/audio.mp3`,
    pages,
    phonicsWords: [],
  };

  fs.writeFileSync(lessonFile, JSON.stringify(lesson, null, 2));
  console.log(`  ✓ ${lessonFile}`);
  console.log(`  ⚠ ${storyPages.length} pages — narrativeCN needs manual writing`);
}

// ── Step 6: Print remaining manual tasks ────────────────────────────────────
function printManualTasks() {
  console.log(`
══════════════════════════════════════════════
  ✅ Automated steps complete!

  📝 Manual tasks remaining:

  1. Edit ${lessonId}.json:
     - Write narrativeCN for each page (replace 【TODO】)
     - Add keywords for each page
     - Add phonicsWords (check vocab_phonics.json)
     - Verify pageStartMs timing (adjust if STT was inaccurate)
     - Set featuredSentence to a good sentence from this book

  2. Add audio scripts to scripts/generate_audio.js:
     - ${prefix}_intro, ${prefix}_p1_cn, ${prefix}_p1_en, ... ${prefix}_done, ${prefix}_featured

  3. Run: node scripts/generate_audio.js

  4. Register in 4 files:
     - home_screen.dart → _kBooks
     - recording_screen.dart → _featuredAudioMap
     - study_screen.dart → _prevBookMap
     - listen_screen.dart → _kLessonOrder
     - pubspec.yaml → assets

  5. Run: flutter run -d chrome  (test all modules)
══════════════════════════════════════════════
`);
}

// ── Main ────────────────────────────────────────────────────────────────────
async function main() {
  // Verify prerequisites
  if (!fs.existsSync(bookDir)) {
    console.error(`Book folder not found: ${bookDir}`);
    process.exit(1);
  }

  await splitPdf();
  const ocrResults = await ocrPages();
  const sttWords = await sttPageTiming();
  generateLessonJson(ocrResults, sttWords);
  printManualTasks();
}

main().catch(e => { console.error(e); process.exit(1); });
