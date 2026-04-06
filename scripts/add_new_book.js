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
 *   - If PDF has wide pages (MediaBox > CropBox), use pdf:use-cropbox flag
 *   - If auto split fails, put manually cropped pages in <folder>/single/0.jpg, 1.jpg...
 *
 * This script automates:
 *   1. Split PDF → merge spreads (with cropbox support)
 *   2. OCR pages (Google Vision, with word positions for left/right detection)
 *   3. STT page timing (Google Speech-to-Text)
 *   4. Generate lesson JSON skeleton (narrativeCN = TODO placeholders)
 *   5. Generate EN audio only (ElevenLabs) + phonics word audio + recording sentence audio
 *   6. Register in week_service.dart + pubspec.yaml
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * AFTER SCRIPT: Claude must complete these manually:
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * 【中文讲解 — Amy风格】
 *   - Claude 参考 Book 1 (biscuit_book1_day1.json) 的 narrativeCN 风格
 *   - 语气活泼亲切，像跟小朋友面对面说话
 *   - 每页选1-2个关键英文单词，用"xxx就是xxx"自然解释
 *   - 前后页有故事连贯性，经常问互动问题
 *   - 中英文自然穿插，不要生硬翻译
 *   - 每页50-100字，不要太长
 *   - 写完后用火山引擎 TTS 生成 CN 音频
 *   - ❌ 不要用 fallback 模板（"你听到了吗？X就是X的意思"）
 *
 * 【Phonics 选词规则】
 *   - 选有意义的实词（名词、动词、形容词），孩子能记住的
 *   - ❌ 不选: 功能词(the/is/are/was/were)、代词(you/he/she)、
 *     助动词(can/could/will)、介词(with/from/into)、语气词(woof/oink)
 *   - 自动去掉复数 -s (pigs → pig)，用 baseForm()
 *   - 选词来自绘本左半页 (leftWords)，3-5个字母
 *   - ⚠ 两个词的 phoneme 数量必须相同（防止 RangeError）
 *   - 优先选 3-phoneme CVC 词（如 pig, dog, run）
 *
 * 【Phonics 拆分规则 — 三层】
 *   Layer 1 — CVC: 每个字母独立拆 (pig → p-i-g, cat → c-a-t)
 *   Layer 2 — Digraphs/Blends: 保持组合 (ship → sh-i-p, play → pl-ay)
 *     - Digraphs: sh, ch, th, ph, wh, ck, ng, nk, tch
 *     - Blends: bl, br, cl, cr, dr, fl, fr, gl, gr, pl, pr, sc, sk, sl, sm, sn, sp, st, sw, tr
 *     - Doubles: ll, ss, ff, zz
 *   Layer 3 — Vowel teams: 保持元音组合 (boat → b-oa-t, rain → r-ai-n)
 *     - ai, ay, ea, ee, oa, oo, ou, ow, oi, oy, igh, ar, er, ir, or, ur
 *   ❌ 不要用 word family 合并 (-ig, -ed, -at)
 *
 * 【Recording 录音页】
 *   - 脚本自动选一个左右都有文字的 spread
 *   - 用 OCR leftWords/rightWords 检测每句在哪边
 *   - 提取2-4个有意义的句子，跳过 Woof/Oink 等
 *   - 生成每句的英文音频 {prefix}_rec_1.mp3, _rec_2.mp3...
 * ═══════════════════════════════════════════════════════════════════════════
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

  const sharp = require('sharp');
  const singleDir = path.join(bookDir, 'single');

  // ── Option A: Use manually prepared single pages (from website PDF→image conversion)
  if (fs.existsSync(singleDir)) {
    console.log('── Step 1-2: Using manually prepared single/ pages ──');
    const files = fs.readdirSync(singleDir)
      .filter(f => /\.(jpg|jpeg|png|webp)$/i.test(f))
      .sort((a, b) => parseInt(a) - parseInt(b));
    console.log(`  ${files.length} pages found`);

    // Page 0 = cover
    await sharp(path.join(singleDir, files[0])).webp({ quality: 82 }).toFile(path.join(bookDir, 'cover.webp'));
    console.log('  cover done');

    // Validate: each page should be portrait (height > width)
    const firstMeta = await sharp(path.join(singleDir, files[1] || files[0])).metadata();
    if (firstMeta.width > firstMeta.height) {
      console.warn(`  ⚠ WARNING: pages are landscape (${firstMeta.width}x${firstMeta.height}), expected portrait. Check single/ images.`);
    } else {
      console.log(`  Page size: ${firstMeta.width}x${firstMeta.height} (portrait ✓)`);
    }

    // Merge remaining pairs into spreads
    const singles = files.slice(1);
    let num = 1;
    for (let i = 0; i < singles.length; i += 2) {
      const out = path.join(bookDir, `spread_${String(num).padStart(2, '0')}.webp`);
      const left = path.join(singleDir, singles[i]);
      const right = i + 1 < singles.length ? path.join(singleDir, singles[i + 1]) : null;
      if (!right) {
        await sharp(left).webp({ quality: 82 }).toFile(out);
      } else {
        const lm = await sharp(left).metadata();
        const rm = await sharp(right).metadata();
        const h = Math.max(lm.height, rm.height);
        const lb = await sharp(left).resize({ height: h, fit: 'contain' }).toBuffer();
        const rb = await sharp(right).resize({ height: h, fit: 'contain' }).toBuffer();
        await sharp({ create: { width: lm.width + rm.width, height: h, channels: 3, background: { r: 255, g: 255, b: 255 } } })
          .composite([{ input: lb, left: 0, top: 0 }, { input: rb, left: lm.width, top: 0 }])
          .webp({ quality: 82 }).toFile(out);
      }
      num++;
    }
    console.log(`  ✓ ${num - 1} spreads from single/ pages`);
    return;
  }

  // ── Option B: Auto-split PDF with ImageMagick
  if (!fs.existsSync(pdfPath)) { console.log('⏭ Step 1-2: No book.pdf and no single/ folder'); return; }

  console.log('── Step 1: Splitting PDF (auto, cropbox) ──');
  const tmpDir = path.join(bookDir, '_tmp');
  if (!fs.existsSync(tmpDir)) fs.mkdirSync(tmpDir);
  execSync(`${MAGICK} -density 200 -define pdf:use-cropbox=true "${pdfPath}" -quality 90 "${tmpDir}/page_%02d.png"`, { stdio: 'pipe', timeout: 300000 });

  const pngFiles = fs.readdirSync(tmpDir).filter(f => f.endsWith('.png')).sort();
  console.log(`  ${pngFiles.length} pages`);

  // Validate page dimensions — should be portrait (single page, not spread)
  const firstPage = path.join(tmpDir, pngFiles[1] || pngFiles[0]);
  const meta = await sharp(firstPage).metadata();
  if (meta.width > meta.height * 1.3) {
    console.error(`  ✗ Pages are too wide (${meta.width}x${meta.height}). PDF may have spread-sized MediaBox.`);
    console.error(`  → Convert PDF to images manually and put them in ${singleDir}/0.jpg, 1.jpg, ...`);
    console.error(`  → Each image should be a single portrait page (height > width).`);
    // Cleanup
    for (const f of pngFiles) fs.unlinkSync(path.join(tmpDir, f));
    fs.rmdirSync(tmpDir);
    process.exit(1);
  }
  console.log(`  Page size: ${meta.width}x${meta.height} (portrait ✓)`);

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
  console.log('── Step 3: OCR (with word positions) ──');
  const imgs = fs.readdirSync(bookDir).filter(f => (f.startsWith('spread_') || f === 'cover.webp') && f.endsWith('.webp')).sort();
  const results = [];
  for (const img of imgs) {
    const bytes = fs.readFileSync(path.join(bookDir, img)).toString('base64');
    const res = await fetch(`https://vision.googleapis.com/v1/images:annotate?key=${apiKey}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ requests: [{ image: { content: bytes }, features: [{ type: 'TEXT_DETECTION' }] }] }),
    });
    const response = (await res.json()).responses?.[0] || {};
    const text = (response.fullTextAnnotation?.text || '').trim();
    // Save word positions: { word, x } for each detected word
    const annotations = response.textAnnotations || [];
    const imgWidth = annotations[0]?.boundingPoly?.vertices?.[1]?.x || 1;
    const midX = imgWidth / 2;
    const leftWords = []; // words on left half of spread
    const rightWords = [];
    for (let i = 1; i < annotations.length; i++) {
      const w = annotations[i];
      const x = w.boundingPoly?.vertices?.[0]?.x || 0;
      const word = w.description.toLowerCase().replace(/[^a-z]/g, '');
      if (word.length >= 3) {
        if (x < midX) leftWords.push(word);
        else rightWords.push(word);
      }
    }
    results.push({ page: img, text, leftWords: [...new Set(leftWords)], rightWords: [...new Set(rightWords)] });
    console.log(`  ${img}: "${text.replace(/\n/g, ' ').slice(0, 50)}..." (L:${leftWords.length} R:${rightWords.length})`);
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

// ── Step 5: Generate Chinese narration via Gemini AI ────────────────────────

// Few-shot examples from Book 1 (the gold standard)
const NARRATIVE_EXAMPLES = `
示例（Book 1: Biscuit）：

英文第1页: This is Biscuit. Biscuit is small. Biscuit is yellow.
中文讲解: 呀~ 你们看到了吗？这就是今天的小主角，一只叫Biscuit的小狗！你知道biscuit是什么意思吗？哈哈，没错，就是饼干的意思，你看他个子小小的，毛是黄色的，是不是很像黄油饼干呀！

英文第2页: Time for bed, Biscuit! Woof, woof! Biscuit wants to play.
中文讲解: 好像要到睡觉时间啦！小女孩叫Biscuit去睡觉。这个bed就是小床，Time for bed就是该上床睡觉啦！但是你说Biscuit想不想睡啊？对了，他可不想睡，他大声的说——Woof woof！他想玩，他想玩！

英文第3页: Biscuit wants a snack. Biscuit wants a drink.
中文讲解: Biscuit还是不想睡觉，他想干嘛呀，哈哈，Biscuit说我要吃零食！snack就是小零食小点心。然后他又说我要喝水！这里的drink就是喝水。Biscuit怎么一会儿要这个，一会儿要那个呀，哈哈！

英文第4页: Biscuit wants to hear a story.
中文讲解: 那我们看看吃完喝完以后biscuit要睡觉了吗？Biscuit又说了什么？——他说要听故事！story就是故事。小女孩只好又给他讲起了故事，是不是就像我们现在这样啊？

英文第5页: Biscuit wants his blanket. Biscuit wants his doll.
中文讲解: 故事听完了，Biscuit看了看，又说到——我想要我的小毯子！blanket就是小毯子。结果他还要什么呀？他说——我要我的玩偶！doll就是布娃娃玩偶！你睡觉的时候是不是总有一个小玩偶陪着你呀

英文第6页: Biscuit wants a hug. Biscuit wants a kiss.
中文讲解: 你看现在毯子有了，小玩偶有了，Biscuit又想到了什么呀？他说——我要抱抱！我要亲亲！hug是抱抱，kiss是亲亲。你们睡前有没有亲亲抱抱你家的小宠物，小狗狗或者小猫咪，然后跟他说晚安呀？
`;

async function generateNarrativesWithAI(storyPages) {
  console.log('── Step 5a: Generating narratives with Gemini AI ──');

  // Build the full story text for context
  const fullStory = storyPages.map((sp, i) => {
    // Clean OCR text: remove page numbers (standalone 1-3 digit numbers) and extra whitespace
    const text = sp.text.replace(/\n/g, ' ').replace(/\b\d{1,3}\b/g, '').replace(/\s+/g, ' ').trim();
    return `第${i + 1}页: ${text}`;
  }).join('\n');

  const prompt = `你是Amy老师，一个非常受小朋友喜欢的英语启蒙老师。你要给5-8岁中国小朋友用中文讲解英文绘本"${bookTitle}"。

你的讲解风格：
- 语气活泼亲切，像跟小朋友面对面说话
- 每页选1-2个关键英文单词自然融入讲解，用"xxx就是xxx"的方式解释
- 根据故事情节有情绪变化（惊讶、搞笑、温馨、紧张）
- 经常问互动问题（"你觉得呢？"、"是不是很有趣呀？"、"你猜猜看会怎样？"）
- 前后页之间要有故事连贯性，不要每页独立
- 中英文自然穿插，不要生硬翻译
- 不要说"这一页"、"让我们看看这一页"这种话

${NARRATIVE_EXAMPLES}

现在请按同样的风格，为下面这本新书写每页的中文讲解。
注意：每页讲解控制在50-100字左右，不要太长。

这本书的完整内容：
${fullStory}

请按以下JSON格式输出，只输出JSON数组，不要输出其他内容：
[
  {"page": 1, "narrativeCN": "讲解内容", "keywords": ["关键词1", "关键词2"]},
  {"page": 2, "narrativeCN": "讲解内容", "keywords": ["关键词1"]},
  ...
]`;

  for (let attempt = 1; attempt <= 3; attempt++) {
    try {
      console.log(`  Attempt ${attempt}/3...`);
      const res = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${apiKey}`,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            contents: [{ parts: [{ text: prompt }] }],
            generationConfig: { temperature: 0.7, maxOutputTokens: 8192, responseMimeType: 'application/json' },
          }),
        }
      );

      const data = await res.json();
      const allParts = data.candidates?.[0]?.content?.parts || [];
      const text = allParts.map(p => p.text || '').join('');

      let narratives;
      try {
        narratives = JSON.parse(text);
      } catch {
        const jsonMatch = text.match(/\[[\s\S]*\]/);
        if (!jsonMatch) {
          console.error(`  ✗ Attempt ${attempt}: Gemini did not return valid JSON`);
          if (attempt < 3) { console.log('  Waiting 65s for rate limit...'); await new Promise(r => setTimeout(r, 65000)); continue; }
          console.error('  ✗ All 3 attempts failed. Stopping.');
          process.exit(1);
        }
        narratives = JSON.parse(jsonMatch[0]);
      }
      console.log(`  ✓ Generated ${narratives.length} page narratives`);
      return narratives;
    } catch (e) {
      console.error(`  ✗ Attempt ${attempt}: ${e.message}`);
      if (attempt < 3) { console.log('  Waiting 65s for rate limit...'); await new Promise(r => setTimeout(r, 65000)); continue; }
      console.error('  ✗ All 3 attempts failed. Stopping.');
      process.exit(1);
    }
  }
}

// Fallback template (used only if Gemini fails)
function generateNarrativeCN(englishText) {
  const text = englishText.replace(/\n/g, ' ').replace(/\d+\s*$/, '').trim();
  if (!text) return '';
  const words = text.split(/\s+/).filter(w => w.replace(/[^a-zA-Z]/g, '').length > 3);
  const keyword = words.find(w => !['biscuit','woof','that','this','what','where','there','here'].includes(w.toLowerCase().replace(/[^a-z]/g, '')));
  const kwClean = keyword ? keyword.replace(/[^a-zA-Z]/g, '') : '';
  if (kwClean) return `你听到了吗？${kwClean}就是${kwClean}的意思。${text.split('.')[0].trim()}。`;
  return `我们来听听看发生了什么。${text.split('.')[0].trim()}。`;
}

// ── Step 6: Build lesson JSON ───────────────────────────────────────────────
async function buildLesson(ocrResults, sttWords) {
  if (fs.existsSync(lessonFile)) { console.log('⏭ Step 5: Lesson JSON exists'); return; }
  console.log('── Step 5: Building lesson JSON ──');

  const storyPages = ocrResults.filter(p =>
    p.page.startsWith('spread_') && p.text.length > 10 &&
    !p.text.includes('ISBN') && !p.text.includes('HOORAY') &&
    !p.text.includes('HarperCollins') && !p.text.includes('copyright')
  );

  // CN narratives are written by Claude after script runs — leave as TODO placeholders

  const pages = [{
    imageAsset: `assets/books/${folderName}/cover.webp`,
    narrativeCN: `Hello Hello, my dear friend！I am Amy! How are you？...... I'm good！Good！今天我们要讲${bookTitle}的故事！Are you ready？Let's go！`,
    narrativeEN: '', keywords: [], audioCN: `${prefix}_intro`, audioEN: null,
    highlights: [], characterPos: { x: 0.75, y: 0.7, action: 'excited' },
  }];

  let searchFrom = 0;
  for (let i = 0; i < storyPages.length; i++) {
    const sp = storyPages[i];
    // Clean OCR text: remove page numbers (standalone 1-3 digit numbers) and extra whitespace
    const text = sp.text.replace(/\n/g, ' ').replace(/\b\d{1,3}\b/g, '').replace(/\s+/g, ' ').trim();
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

    // Placeholder — Claude writes real narratives after script completes
    const narrativeCN = `TODO_PAGE_${i + 1}`;
    const aiKeywords = keywords;

    const page = {
      imageAsset: `assets/books/${folderName}/${sp.page}`,
      teacherExpression: 'happy',
      narrativeCN,
      narrativeEN: text,
      keywords: aiKeywords,
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

  // Auto-select phonicsWords: pick 2 simple CVC words from LEFT side of spreads
  // Then use Gemini to get correct phoneme splits
  // Skip function words, be/have/do forms, modals, pronouns, prepositions, etc.
  // Keep only concrete nouns, verbs, adjectives that kids can visualize
  const skipWords = new Set([
    // character/sound words
    'biscuit','woof','quack','meow','oink','honk',
    // be / have / do forms
    'is','am','are','was','were','been','being','has','have','had','does','did','done',
    // modals & auxiliaries
    'can','could','will','would','shall','should','may','might','must',
    // pronouns
    'you','your','yours','he','him','his','she','her','hers','they','them','their','its','our','ours','we',
    // prepositions & conjunctions
    'the','and','for','not','but','with','into','from','that','this','what','where','when','which','who','how',
    // common short function words
    'here','there','just','very','come','more','over','even','want','wants','time','back',
    'all','one','out','let','say','said','too','also','now','then','some','than',
    'got','get','put','see','saw','look','went','goes','going','come','came',
    // irregular pronunciation — bad for phonics (letter ≠ sound)
    'many','any','some','come','done','gone','give','live','love','move','none',
    'once','only','other','water','want','what','were','where','who','why',
    'said','says','does','sure','sugar',
  ]);
  let phonicsWords = [];
  const usedWords = new Set();

  // Find candidates: 3-5 letter words from left side of spreads
  // IMPORTANT: Both words MUST have the same number of phonemes to avoid
  // RangeError in phonics_screen when switching words (arrays sized for word 1
  // get accessed with word 2's indices if lengths differ).
  const { splitWord, validateSplit, baseForm } = require('./phoneme_splitter');
  const candidates = [];
  for (const sp of storyPages) {
    const leftWords = sp.leftWords || [];
    for (const w of leftWords) {
      const b = baseForm(w);
      if (b.length >= 3 && b.length <= 5 && !skipWords.has(b) && !usedWords.has(b) && /^[a-z]+$/.test(b)) {
        const phonemes = splitWord(b);
        if (validateSplit(phonemes)) {
          candidates.push({ word: b, page: sp.page, phonemes, count: phonemes.length });
          usedWords.add(b);
        }
      }
    }
  }

  // Pick 2 words with matching phoneme count (prefer 3-phoneme CVC words)
  if (candidates.length >= 2) {
    // Group by phoneme count
    const byCount = {};
    for (const c of candidates) {
      (byCount[c.count] = byCount[c.count] || []).push(c);
    }
    // Prefer groups with 2+ words, prefer 3-phoneme CVC words
    for (const count of [3, 4, 2, 5]) {
      if (byCount[count] && byCount[count].length >= 2) {
        phonicsWords = byCount[count].slice(0, 2);
        break;
      }
    }
    // Fallback: just take first 2 regardless of count match
    if (phonicsWords.length < 2) {
      phonicsWords = candidates.slice(0, 2);
      console.log(`  ⚠ Phonics words have different phoneme counts — may need manual fix`);
    }
  } else {
    phonicsWords = candidates.slice(0, 2);
  }

  phonicsWords = phonicsWords.map(pw => ({
    word: pw.word,
    phonemes: pw.phonemes,
    imageAsset: `assets/books/${folderName}/${pw.page}`,
  }));
  console.log(`  Phonics words: ${phonicsWords.map(w => `${w.word} [${w.phonemes.join('-')}] @ ${w.imageAsset.split('/').pop()}`).join(', ') || 'none'}`);


  // Auto-select recording page: find a spread with sentences on both left & right
  const skipRec = /^(woof|bow wow|oink|coo|honk|quack)/i;
  let recordingPage = null;
  for (const sp of storyPages) {
    const leftSet = new Set(sp.leftWords || []);
    const rightSet = new Set(sp.rightWords || []);
    if (leftSet.size < 2 || rightSet.size < 2) continue;
    const page = pages.find(p => p.imageAsset.includes(sp.page));
    if (!page || !page.narrativeEN) continue;
    const sents = page.narrativeEN.split(/[.!?]+/).map(s => s.trim())
      .filter(s => s.length > 10 && s.split(/\s+/).length >= 3 && !skipRec.test(s) && !s.match(/ISBN|HOORAY|copyright/i));
    if (sents.length >= 2) {
      // Detect side for each sentence based on OCR word positions
      function detectSide(sentence) {
        const words = sentence.toLowerCase().split(/[^a-z]+/).filter(w => w.length >= 3);
        let leftScore = 0, rightScore = 0;
        for (const w of words) {
          if (leftSet.has(w)) leftScore++;
          if (rightSet.has(w)) rightScore++;
        }
        return leftScore >= rightScore ? 'left' : 'right';
      }
      recordingPage = { imageAsset: page.imageAsset, sentences: [] };
      for (let si = 0; si < sents.length && si < 4; si++) {
        recordingPage.sentences.push({
          text: sents[si] + '.',
          audio: `audio/${prefix}_rec_${si + 1}.mp3`,
          side: detectSide(sents[si]),
        });
      }
      break;
    }
  }
  console.log(`  Recording page: ${recordingPage ? recordingPage.imageAsset.split('/').pop() + ' (' + recordingPage.sentences.length + ' sentences)' : 'NONE — add manually'}`);

  const lesson = {
    id: lessonId, bookTitle, characterName: 'Biscuit',
    characterAsset: 'assets/characters/teacher_default.webp',
    featuredSentence: recordingPage?.sentences?.[0]?.text || bookTitle,
    originalAudio: `books/${folderName}/audio.mp3`,
    pages,
    phonicsWords,
    recordingPage,
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
    // Skip CN audio — generated later after Claude writes narratives
    if (page.audioEN && page.narrativeEN) {
      scripts.push({ id: page.audioEN, text: page.narrativeEN, lang: 'en', keywords: page.keywords || [] });
    }
  }
  // Recording sentence audio (replaces old featured audio)
  for (const sent of lesson.recordingPage?.sentences || []) {
    const audioId = sent.audio.replace('audio/', '').replace('.mp3', '');
    scripts.push({ id: audioId, text: sent.text, lang: 'en', keywords: [] });
  }

  // Phonics word audio: generate with "The word is: X" then trim to just the word
  const PHONICS_DIR = path.join(__dirname, '..', 'assets', 'audio', 'phonics_sounds');
  for (const pw of lesson.phonicsWords || []) {
    const wordFile = path.join(PHONICS_DIR, `word_${pw.word}.mp3`);
    if (fs.existsSync(wordFile)) continue;

    console.log(`  Generating word audio: ${pw.word} ...`);
    try {
      // Step 1: Generate "The word is: [word]" for accurate pronunciation
      const res = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${VOICE_ID_EN}/with-timestamps`, {
        method: 'POST',
        headers: { 'xi-api-key': elevenLabsKey, 'Content-Type': 'application/json' },
        body: JSON.stringify({
          text: `The word is: ${pw.word}`,
          model_id: 'eleven_multilingual_v2',
          voice_settings: { stability: 0.7, similarity_boost: 0.75, style: 0.1, speed: 0.85 },
        }),
      });
      if (!res.ok) throw new Error(`ElevenLabs ${res.status}`);
      const data = await res.json();

      // Step 2: Find where the actual word starts using timestamps
      const alignment = data.alignment;
      let wordStartSec = 0;
      if (alignment?.characters) {
        // Find the start of the target word (after "The word is: ")
        const fullText = alignment.characters.join('');
        const colonIdx = fullText.indexOf(':');
        if (colonIdx >= 0) {
          // Word starts after ": " — find next non-space character
          for (let ci = colonIdx + 1; ci < alignment.characters.length; ci++) {
            if (alignment.characters[ci].trim()) {
              wordStartSec = alignment.character_start_times_seconds[ci];
              break;
            }
          }
        }
      }

      // Step 3: Save full audio, then trim with ffmpeg
      const fullPath = path.join(PHONICS_DIR, `_full_${pw.word}.mp3`);
      fs.writeFileSync(fullPath, Buffer.from(data.audio_base64, 'base64'));

      // Trim: start slightly before the word, keep the rest
      const trimStart = Math.max(0, wordStartSec - 0.05);
      execSync(`"${FFMPEG}" -y -ss ${trimStart.toFixed(3)} -i "${fullPath}" -af "afade=t=in:st=0:d=0.02,afade=t=out:st=1.5:d=0.05" -t 2.0 -q:a 2 "${wordFile}"`, { stdio: 'pipe' });
      fs.unlinkSync(fullPath);

      console.log(`  ✓ word_${pw.word}.mp3 (trimmed from ${wordStartSec.toFixed(2)}s)`);
      await new Promise(r => setTimeout(r, 500));
    } catch (e) {
      console.error(`  ✗ word_${pw.word}: ${e.message}`);
      // Fallback: generate just the word directly
      try {
        const res = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${VOICE_ID_EN}`, {
          method: 'POST',
          headers: { 'xi-api-key': elevenLabsKey, 'Content-Type': 'application/json' },
          body: JSON.stringify({ text: pw.word, model_id: 'eleven_multilingual_v2',
            voice_settings: { stability: 0.7, similarity_boost: 0.75, style: 0.1, speed: 0.85 } }),
        });
        if (res.ok) fs.writeFileSync(wordFile, Buffer.from(await res.arrayBuffer()));
      } catch (_) {}
    }
  }

  for (const s of scripts) {
    const outPath = s._outputDir ? path.join(s._outputDir, s._filename) : path.join(AUDIO_DIR, `${s.id}.mp3`);
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

  // 1. week_service.dart → kAllBooks (single source of truth for all books)
  const weekFile = path.join(LIB_DIR, 'services', 'week_service.dart');
  let week = fs.readFileSync(weekFile, 'utf8');
  if (!week.includes(lessonId)) {
    // Use double quotes for title to handle apostrophes (e.g. Biscuit's)
    const entry = `  BookInfo("${bookTitle}", '${titleCN || bookTitle}', '${lessonId}', 'assets/books/${folderName}/cover.webp', 'books/${folderName}/audio.mp3'),`;
    week = week.replace('  // 新书追加到这里', `${entry}\n  // 新书追加到这里`);
    fs.writeFileSync(weekFile, week);
    console.log('  ✓ week_service.dart (kAllBooks)');
  }

  // 2. pubspec.yaml
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
  await buildLesson(ocr, stt);
  await generateAudio();
  registerInApp();

  console.log(`
══════════════════════════════════════════════
  ✅ Book ${bookNum} "${bookTitle}" — Step 1 done!

  ⏭ Next: Ask Claude to write CN narratives + generate CN audio
     1. Claude reads ${lessonFile} and writes Amy-style narrativeCN
     2. Claude updates the JSON and generates CN TTS audio
     3. Check pageStartMs timing, phonicsWords
  2. Run: flutter run -d chrome (test all modules)
  3. Push: git add -A && git commit && git push
══════════════════════════════════════════════
`);
}

main().catch(e => { console.error(e); process.exit(1); });
