#!/usr/bin/env node
/**
 * OCR book pages using Google Vision API to extract English text.
 * Output: one JSON per book with page texts.
 */

const fs = require('fs');
const path = require('path');

const envPath = path.join(__dirname, '..', '.env');
const env = fs.readFileSync(envPath, 'utf8');
const apiKey = env.match(/GOOGLE_CLOUD_API_KEY=(.+)/)?.[1]?.trim();
if (!apiKey) { console.error('No API key'); process.exit(1); }

const BOOKS_DIR = path.join(__dirname, '..', 'assets', 'books');
const books = ['03Biscuit_Loves_the_Library', '04Biscuit_Finds_a_Friend', '05Biscuits_New_Trick'];

async function ocrImage(imagePath) {
  const imageBytes = fs.readFileSync(imagePath).toString('base64');
  const res = await fetch(
    `https://vision.googleapis.com/v1/images:annotate?key=${apiKey}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        requests: [{
          image: { content: imageBytes },
          features: [{ type: 'TEXT_DETECTION' }],
        }],
      }),
    }
  );
  const data = await res.json();
  const text = data.responses?.[0]?.fullTextAnnotation?.text || '';
  return text.trim();
}

async function processBook(bookFolder) {
  const bookDir = path.join(BOOKS_DIR, bookFolder);
  const pages = fs.readdirSync(bookDir)
    .filter(f => f.endsWith('.webp') || f.endsWith('.jpg') || f.endsWith('.png'))
    .sort();

  console.log(`\n📖 ${bookFolder} (${pages.length} pages)`);

  const results = [];
  for (const page of pages) {
    const pagePath = path.join(bookDir, page);
    const text = await ocrImage(pagePath);
    results.push({ page, text });
    const preview = text.replace(/\n/g, ' ').slice(0, 80);
    console.log(`  ${page}: "${preview}${text.length > 80 ? '...' : ''}"`);
    await new Promise(r => setTimeout(r, 300)); // rate limit
  }

  // Save results
  const outPath = path.join(bookDir, '_ocr.json');
  fs.writeFileSync(outPath, JSON.stringify(results, null, 2));
  console.log(`  Saved: ${outPath}`);
  return results;
}

async function main() {
  for (const book of books) {
    await processBook(book);
  }
  console.log('\nDone!');
}

main().catch(console.error);
