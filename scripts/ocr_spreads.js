#!/usr/bin/env node
// BridgeRead — OCR spread images with Google Cloud Vision REST API
//
// Usage:
//   node ocr_spreads.js <book_id>
//
// 前提：.env 里有 GOOGLE_VISION_API_KEY=xxx

const fs   = require('fs');
const path = require('path');

// ── Config ────────────────────────────────────────────────────────────────────

const envPath = path.join(__dirname, '..', '.env');
const envText = fs.existsSync(envPath) ? fs.readFileSync(envPath, 'utf8') : '';
const API_KEY = envText.match(/GOOGLE_VISION_API_KEY=(.+)/)?.[1]?.trim()
             || process.env.GOOGLE_VISION_API_KEY;

if (!API_KEY) {
  console.error('❌ 需要 GOOGLE_VISION_API_KEY（在 .env 里添加）');
  process.exit(1);
}

const args = process.argv.slice(2);
if (args.length < 1) {
  console.error('Usage: node ocr_spreads.js <book_id>');
  process.exit(1);
}

const bookId    = args[0];
const BOOKS_DIR = path.join(__dirname, '..', 'assets', 'books');
const OUT_DIR   = path.join(__dirname, '..', 'assets', 'lessons', '_ocr');
fs.mkdirSync(OUT_DIR, { recursive: true });

// ── Helpers ───────────────────────────────────────────────────────────────────

function toNorm(vertices, imgW, imgH) {
  const xs = vertices.map(v => v.x || 0);
  const ys = vertices.map(v => v.y || 0);
  return {
    x:      +(Math.min(...xs) / imgW).toFixed(4),
    y:      +(Math.min(...ys) / imgH).toFixed(4),
    width:  +((Math.max(...xs) - Math.min(...xs)) / imgW).toFixed(4),
    height: +((Math.max(...ys) - Math.min(...ys)) / imgH).toFixed(4),
  };
}

function cleanWord(w) {
  return w.toLowerCase().replace(/[^a-z']/g, '');
}

// ── OCR one image via REST ────────────────────────────────────────────────────

async function ocrImage(imagePath) {
  const imageBytes = fs.readFileSync(imagePath).toString('base64');

  const response = await fetch(
    `https://vision.googleapis.com/v1/images:annotate?key=${API_KEY}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        requests: [{
          image: { content: imageBytes },
          features: [{ type: 'DOCUMENT_TEXT_DETECTION' }],
        }],
      }),
    }
  );

  if (!response.ok) {
    const err = await response.text();
    throw new Error(`Vision API ${response.status}: ${err}`);
  }

  const data = await response.json();
  const anno = data.responses[0];

  if (anno.error) throw new Error(anno.error.message);
  if (!anno.fullTextAnnotation) return { fullText: '', words: [] };

  const page = anno.fullTextAnnotation.pages[0];
  const imgW = page.width;
  const imgH = page.height;

  const words = [];
  for (const block of page.blocks) {
    for (const para of block.paragraphs) {
      for (const word of para.words) {
        const text = word.symbols.map(s => s.text).join('');
        if (!text.trim()) continue;
        const norm = toNorm(word.boundingBox.vertices, imgW, imgH);
        words.push({ word: text, clean: cleanWord(text), ...norm });
      }
    }
  }

  const fullText = anno.fullTextAnnotation.text
    .replace(/\n/g, ' ').replace(/\s+/g, ' ').trim();

  return { fullText, words };
}

// ── Main ──────────────────────────────────────────────────────────────────────

async function main() {
  console.log(`\n🔍 BridgeRead OCR — Google Cloud Vision`);
  console.log(`📚 Book: ${bookId}\n`);

  const files = fs.readdirSync(BOOKS_DIR)
    .filter(f => f.startsWith(`${bookId}_spread_`) && /\.(jpg|jpeg|png)$/i.test(f))
    .sort();

  if (files.length === 0) {
    console.error(`❌ 找不到图片: ${BOOKS_DIR}/${bookId}_spread_*.jpg`);
    console.error(`   先运行 pdf_to_spreads.js`);
    process.exit(1);
  }

  console.log(`📄 找到 ${files.length} 张图片\n`);

  const pages = [];

  for (const file of files) {
    const imagePath = path.join(BOOKS_DIR, file);
    process.stdout.write(`  OCR: ${file} ...`);

    try {
      const { fullText, words } = await ocrImage(imagePath);

      // Strip trailing page numbers
      const enText = fullText.replace(/\s*\d+\s*$/, '').trim();

      console.log(` ✅`);
      if (enText) {
        console.log(`  → "${enText}"`);
      } else {
        console.log(`  → (no text detected)`);
      }
      console.log(`  → ${words.length} words\n`);

      pages.push({ image: file, en: enText, keywords: [], words });

    } catch (err) {
      console.log(` ❌ ${err.message}\n`);
      pages.push({ image: file, en: '', keywords: [], words: [] });
    }

    await new Promise(r => setTimeout(r, 200));
  }

  // Save full OCR data (with word coordinates)
  const ocrOut = path.join(OUT_DIR, `${bookId}_ocr.json`);
  fs.writeFileSync(ocrOut, JSON.stringify({ bookId, pages }, null, 2), 'utf8');
  console.log(`💾 OCR 坐标数据: ${ocrOut}`);

  // Save book_input.json (for gen_narration.js)
  const inputOut = path.join(__dirname, `${bookId}_input.json`);
  fs.writeFileSync(inputOut, JSON.stringify({
    bookId,
    bookTitle: bookId.replace(/_/g, ' '),
    pages: pages.map(p => ({ image: p.image, en: p.en, keywords: p.keywords })),
  }, null, 2), 'utf8');

  console.log(`📝 book_input:    ${inputOut}\n`);
  console.log(`✅ 完成！下一步：`);
  console.log(`   1. 打开 ${path.basename(inputOut)}`);
  console.log(`   2. 检查每页 en 文字，填入 keywords`);
  console.log(`   3. node gen_narration.js ${path.basename(inputOut)}\n`);
}

main().catch(err => {
  console.error('❌', err.message);
  process.exit(1);
});
