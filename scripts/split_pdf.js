#!/usr/bin/env node
/**
 * Split book PDFs into individual page images using ImageMagick + Sharp.
 * Converts each page to WebP for small file size.
 */

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const sharp = require('sharp');

const MAGICK = 'magick';
const BOOKS_DIR = path.join(__dirname, '..', 'assets', 'books');

// Books that need PDF splitting (3, 4, 5)
const booksToSplit = [
  '03Biscuit_Loves_the_Library',
  '04Biscuit_Finds_a_Friend',
  '05Biscuits_New_Trick',
];

async function splitBook(bookFolder) {
  const bookDir = path.join(BOOKS_DIR, bookFolder);
  const pdfPath = path.join(bookDir, 'book.pdf');

  if (!fs.existsSync(pdfPath)) {
    console.log(`✗ ${bookFolder}: no book.pdf found`);
    return;
  }

  // Check if already has page images
  const existing = fs.readdirSync(bookDir).filter(f => f.startsWith('spread_'));
  if (existing.length > 0) {
    console.log(`⏭ ${bookFolder}: already has ${existing.length} pages`);
    return;
  }

  console.log(`\n📖 ${bookFolder}`);

  // Get page count
  const identifyOut = execSync(
    `${MAGICK} identify -format "%n\n" "${pdfPath}[0]"`,
    { encoding: 'utf8', timeout: 30000 }
  ).trim();

  // Convert all pages to PNG first (temp), then to WebP
  const tmpDir = path.join(bookDir, '_tmp');
  if (!fs.existsSync(tmpDir)) fs.mkdirSync(tmpDir);

  console.log('  Converting pages...');
  execSync(
    `${MAGICK} -density 200 "${pdfPath}" -quality 90 "${tmpDir}/page_%02d.png"`,
    { stdio: 'pipe', timeout: 120000 }
  );

  // Find generated pages
  const pages = fs.readdirSync(tmpDir)
    .filter(f => f.startsWith('page_') && f.endsWith('.png'))
    .sort();

  console.log(`  Found ${pages.length} pages`);

  // Convert each to WebP with sharp
  let pageNum = 0;
  for (const pagePng of pages) {
    pageNum++;
    const pngPath = path.join(tmpDir, pagePng);
    const num = String(pageNum).padStart(2, '0');

    // First page is cover, rest are spreads
    const outName = pageNum === 1 ? 'cover.webp' : `spread_${num}.webp`;
    const outPath = path.join(bookDir, outName);

    await sharp(pngPath)
      .webp({ quality: 82 })
      .toFile(outPath);

    const size = (fs.statSync(outPath).size / 1024).toFixed(0);
    console.log(`  ✓ ${outName} (${size}KB)`);

    fs.unlinkSync(pngPath);
  }

  // Cleanup
  fs.rmdirSync(tmpDir);
  console.log(`  Done! ${pageNum} pages`);
}

async function main() {
  for (const book of booksToSplit) {
    await splitBook(book);
  }
  console.log('\nAll done!');
}

main().catch(console.error);
