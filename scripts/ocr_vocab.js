#!/usr/bin/env node
// OCR the 1400-word vocabulary PDF pages using Google Vision API

const fs = require('fs');
const path = require('path');

const envPath = path.join(__dirname, '..', '.env');
const env = fs.readFileSync(envPath, 'utf8');
const apiKey = env.match(/GOOGLE_CLOUD_API_KEY=(.+)/)?.[1]?.trim();

async function ocrImage(imagePath) {
  const imageBytes = fs.readFileSync(imagePath).toString('base64');
  const res = await fetch(
    `https://vision.googleapis.com/v1/images:annotate?key=${apiKey}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        requests: [{ image: { content: imageBytes }, features: [{ type: 'TEXT_DETECTION' }] }],
      }),
    }
  );
  const data = await res.json();
  return data.responses?.[0]?.fullTextAnnotation?.text || '';
}

async function main() {
  const pages = [];
  for (let i = 0; i < 8; i++) {
    const file = `_temp_vocab_page_${String(i).padStart(2, '0')}.png`;
    if (!fs.existsSync(file)) continue;
    console.log(`OCR page ${i + 1}...`);
    const text = await ocrImage(file);
    pages.push(text);
    await new Promise(r => setTimeout(r, 500));
  }
  fs.writeFileSync('_temp_vocab_1400.txt', pages.join('\n\n=== PAGE BREAK ===\n\n'));
  console.log('Saved to _temp_vocab_1400.txt');
}

main().catch(console.error);
