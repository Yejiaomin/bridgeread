#!/usr/bin/env node
// BridgeRead — PDF 单页转双页展开图
//
// Usage:
//   node pdf_to_spreads.js <pdf_path> <book_id> [options]
//
// Options:
//   --skip=N        跳过封面后的前 N 页（默认 2，通常是版权页+扉页）
//   --quality=N     JPEG 质量 1-100（默认 85）
//   --width=N       输出宽度 px（默认 2400，单页 1200）
//   --out=DIR       输出目录（默认 assets/books）
//
// Example:
//   node pdf_to_spreads.js ../assets/pdf/biscuit.pdf biscuit
//   node pdf_to_spreads.js ../assets/pdf/curious_george.pdf curious_george --skip=1

const { execSync, spawnSync } = require('child_process');
const fs   = require('fs');
const path = require('path');

// ── Parse args ────────────────────────────────────────────────────────────────

const args = process.argv.slice(2);
if (args.length < 2) {
  console.error('Usage: node pdf_to_spreads.js <pdf_path> <book_id> [--skip=N] [--quality=N] [--width=N] [--out=DIR]');
  process.exit(1);
}

const pdfPath  = path.resolve(args[0]);
const bookId   = args[1];

const opts = { skip: 2, quality: 85, width: 2400 };
let outDir = path.join(__dirname, '..', 'assets', 'books');

for (const arg of args.slice(2)) {
  const [key, val] = arg.replace('--', '').split('=');
  if (key === 'skip')    opts.skip    = parseInt(val);
  if (key === 'quality') opts.quality = parseInt(val);
  if (key === 'width')   opts.width   = parseInt(val);
  if (key === 'out')     outDir       = path.resolve(val);
}

if (!fs.existsSync(pdfPath)) {
  console.error(`❌ 找不到 PDF: ${pdfPath}`);
  process.exit(1);
}

// ── Setup ─────────────────────────────────────────────────────────────────────

const TEMP_DIR = path.join(__dirname, '_temp_pages_' + Date.now());
fs.mkdirSync(TEMP_DIR, { recursive: true });
fs.mkdirSync(outDir,   { recursive: true });

const halfWidth  = Math.round(opts.width / 2);
const jpegOpts   = `-quality ${opts.quality}`;

console.log(`\n📖  PDF:    ${path.basename(pdfPath)}`);
console.log(`📚  Book:   ${bookId}`);
console.log(`⏭️   Skip:   ${opts.skip} pages after cover`);
console.log(`🖼️   Output: ${opts.width}px wide  JPEG ${opts.quality}%\n`);

// ── Step 1: Extract pages ─────────────────────────────────────────────────────

console.log('📄 Extracting pages from PDF...');
try {
  // -density 200 gives ~1600px for a typical A4 page — enough for 1200px target
  execSync(
    `magick -density 200 "${pdfPath}" "${TEMP_DIR}/page-%04d.png"`,
    { stdio: 'inherit' }
  );
} catch (err) {
  console.error('❌ magick failed. Make sure ImageMagick is installed.');
  fs.rmSync(TEMP_DIR, { recursive: true });
  process.exit(1);
}

const pageFiles = fs.readdirSync(TEMP_DIR)
  .filter(f => f.endsWith('.png'))
  .sort()
  .map(f => path.join(TEMP_DIR, f));

console.log(`✅ Extracted ${pageFiles.length} pages\n`);

if (pageFiles.length < 1) {
  console.error('❌ No pages extracted.');
  fs.rmSync(TEMP_DIR, { recursive: true });
  process.exit(1);
}

// ── Step 2: Cover (page 0) ────────────────────────────────────────────────────

const coverOut = path.join(outDir, `${bookId}_cover.jpg`);
execSync(
  `magick "${pageFiles[0]}" -resize ${halfWidth}x -strip ${jpegOpts} "${coverOut}"`,
  { stdio: 'pipe' }
);
console.log(`✅ Cover  → ${path.basename(coverOut)}`);

// ── Step 3: Skip pages, then pair remaining ───────────────────────────────────

// After cover (index 0), skip opts.skip pages, then pair the rest
const storyPages = pageFiles.slice(1 + opts.skip);

// If odd number of story pages, ignore the last one (usually back cover)
const pairCount = Math.floor(storyPages.length / 2);

let spreadNum = 1;
for (let i = 0; i < pairCount * 2; i += 2) {
  const leftFile  = storyPages[i];
  const rightFile = storyPages[i + 1];
  const spreadId  = String(spreadNum).padStart(2, '0');
  const spreadOut = path.join(outDir, `${bookId}_spread_${spreadId}.jpg`);

  // +append combines left+right horizontally, then resize to target width
  execSync(
    `magick "${leftFile}" "${rightFile}" +append -resize ${opts.width}x -strip ${jpegOpts} "${spreadOut}"`,
    { stdio: 'pipe' }
  );

  const size = Math.round(fs.statSync(spreadOut).size / 1024);
  console.log(`✅ Spread ${spreadId} → ${path.basename(spreadOut)}  (${size} KB)`);
  spreadNum++;
}

// ── Cleanup ───────────────────────────────────────────────────────────────────

fs.rmSync(TEMP_DIR, { recursive: true });

// ── Summary ───────────────────────────────────────────────────────────────────

console.log(`\n🎉 Done!  1 cover + ${spreadNum - 1} spreads`);
console.log(`📁 ${outDir}\n`);

const generated = fs.readdirSync(outDir)
  .filter(f => f.startsWith(bookId + '_'))
  .sort();
for (const f of generated) {
  const size = Math.round(fs.statSync(path.join(outDir, f)).size / 1024);
  console.log(`   ${f.padEnd(40)} ${size} KB`);
}
console.log('');
