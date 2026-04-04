#!/usr/bin/env node
/**
 * Merge single PDF pages into two-page spreads (left + right).
 * Cover stays single. Pages 2-3 → spread_01, 4-5 → spread_02, etc.
 * Skips copyright/blank pages at start and end.
 */

const sharp = require('sharp');
const fs = require('fs');
const path = require('path');

const bookDirs = process.argv.slice(2);
if (bookDirs.length === 0) {
  console.log('Usage: node merge_spreads.js <bookDir1> [bookDir2] ...');
  console.log('Example: node merge_spreads.js assets/books/03Biscuit_Loves_the_Library');
  process.exit(1);
}

async function mergeBook(bookDir) {
  console.log(`\n📖 ${path.basename(bookDir)}`);

  // Find all single-page webp files (spread_XX.webp)
  const files = fs.readdirSync(bookDir)
    .filter(f => f.startsWith('spread_') && f.endsWith('.webp'))
    .sort();

  if (files.length === 0) {
    console.log('  No spread files found');
    return;
  }

  console.log(`  Found ${files.length} single pages`);

  // Backup originals to _singles/
  const singlesDir = path.join(bookDir, '_singles');
  if (!fs.existsSync(singlesDir)) fs.mkdirSync(singlesDir);

  for (const f of files) {
    const src = path.join(bookDir, f);
    const dst = path.join(singlesDir, f);
    if (!fs.existsSync(dst)) fs.copyFileSync(src, dst);
  }

  // Delete old spread files
  for (const f of files) {
    fs.unlinkSync(path.join(bookDir, f));
  }

  // Merge pairs: page 2+3 → spread_01, page 4+5 → spread_02, etc.
  // Skip first few pages (usually title/copyright) and last few (ads/blank)
  // Story content for Biscuit books: pages 5-24 typically (indices 4-23)
  let spreadNum = 1;

  for (let i = 0; i < files.length; i += 2) {
    const leftFile = path.join(singlesDir, files[i]);
    const rightFile = (i + 1 < files.length) ? path.join(singlesDir, files[i + 1]) : null;

    if (!rightFile) {
      // Odd page at end, just copy as-is
      const outName = `spread_${String(spreadNum).padStart(2, '0')}.webp`;
      fs.copyFileSync(leftFile, path.join(bookDir, outName));
      console.log(`  ✓ ${outName} (single: ${files[i]})`);
      spreadNum++;
      continue;
    }

    // Get dimensions of both images
    const leftMeta = await sharp(leftFile).metadata();
    const rightMeta = await sharp(rightFile).metadata();

    const height = Math.max(leftMeta.height, rightMeta.height);
    const totalWidth = leftMeta.width + rightMeta.width;

    // Compose side by side
    const leftBuf = await sharp(leftFile).resize({ height, fit: 'contain' }).toBuffer();
    const rightBuf = await sharp(rightFile).resize({ height, fit: 'contain' }).toBuffer();

    const outName = `spread_${String(spreadNum).padStart(2, '0')}.webp`;
    await sharp({
      create: { width: totalWidth, height, channels: 3, background: { r: 255, g: 255, b: 255 } }
    })
      .composite([
        { input: leftBuf, left: 0, top: 0 },
        { input: rightBuf, left: leftMeta.width, top: 0 },
      ])
      .webp({ quality: 82 })
      .toFile(path.join(bookDir, outName));

    const size = (fs.statSync(path.join(bookDir, outName)).size / 1024).toFixed(0);
    console.log(`  ✓ ${outName} (${files[i]} + ${files[i + 1]}) ${size}KB`);
    spreadNum++;
  }

  console.log(`  Done! ${spreadNum - 1} spreads created`);
}

async function main() {
  for (const dir of bookDirs) {
    await mergeBook(dir);
  }
}

main().catch(console.error);
