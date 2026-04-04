#!/usr/bin/env node
/**
 * Smart merge: detect which pages are already spreads (wide) vs single pages.
 * Wide pages stay as-is, narrow pages get merged in pairs.
 *
 * Usage: node scripts/smart_merge.js assets/books/04Biscuit_Finds_a_Friend
 */

const sharp = require('sharp');
const fs = require('fs');
const path = require('path');

const bookDir = process.argv[2];
if (!bookDir) { console.log('Usage: node scripts/smart_merge.js <bookDir>'); process.exit(1); }

const singlesDir = path.join(bookDir, '_singles');
if (!fs.existsSync(singlesDir)) { console.error('No _singles/ directory'); process.exit(1); }

async function main() {
  const files = fs.readdirSync(singlesDir).filter(f => f.endsWith('.webp')).sort();

  // Get dimensions of all pages
  const pages = [];
  for (const f of files) {
    const meta = await sharp(path.join(singlesDir, f)).metadata();
    pages.push({ file: f, width: meta.width, height: meta.height });
  }

  // Determine threshold: if width > 1.5x average, it's already a spread
  const avgWidth = pages.reduce((s, p) => s + p.width, 0) / pages.length;
  const threshold = avgWidth * 1.3;

  console.log(`Average width: ${Math.round(avgWidth)}, threshold: ${Math.round(threshold)}`);
  pages.forEach(p => console.log(`  ${p.file}: ${p.width}x${p.height} ${p.width > threshold ? '[SPREAD]' : '[SINGLE]'}`));

  // Delete old spreads
  for (const f of fs.readdirSync(bookDir)) {
    if (f.startsWith('spread_') && f.endsWith('.webp')) {
      fs.unlinkSync(path.join(bookDir, f));
    }
  }

  // Build new spreads
  let spreadNum = 1;
  let i = 0;

  while (i < pages.length) {
    const outName = `spread_${String(spreadNum).padStart(2, '0')}.webp`;
    const outPath = path.join(bookDir, outName);
    const p = pages[i];

    if (p.width > threshold) {
      // Already a spread — just copy
      fs.copyFileSync(path.join(singlesDir, p.file), outPath);
      const size = (fs.statSync(outPath).size / 1024).toFixed(0);
      console.log(`✓ ${outName} ← ${p.file} (spread, ${size}KB)`);
      i++;
    } else if (i + 1 < pages.length && pages[i + 1].width <= threshold) {
      // Two single pages — merge
      const left = path.join(singlesDir, p.file);
      const right = path.join(singlesDir, pages[i + 1].file);
      const lm = await sharp(left).metadata();
      const rm = await sharp(right).metadata();
      const h = Math.max(lm.height, rm.height);
      const lb = await sharp(left).resize({ height: h, fit: 'fill' }).toBuffer();
      const rb = await sharp(right).resize({ height: h, fit: 'fill' }).toBuffer();

      await sharp({
        create: { width: lm.width + rm.width, height: h, channels: 3, background: { r: 255, g: 255, b: 255 } }
      }).composite([
        { input: lb, left: 0, top: 0 },
        { input: rb, left: lm.width, top: 0 },
      ]).webp({ quality: 82 }).toFile(outPath);

      const size = (fs.statSync(outPath).size / 1024).toFixed(0);
      console.log(`✓ ${outName} ← ${p.file} + ${pages[i + 1].file} (merged, ${size}KB)`);
      i += 2;
    } else {
      // Last single page alone
      fs.copyFileSync(path.join(singlesDir, p.file), outPath);
      console.log(`✓ ${outName} ← ${p.file} (single)`);
      i++;
    }
    spreadNum++;
  }

  console.log(`\nDone! ${spreadNum - 1} spreads`);
}

main().catch(console.error);
