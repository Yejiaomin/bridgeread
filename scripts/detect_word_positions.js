// BridgeRead — Detect word bounding boxes in a book spread image
// Usage: node detect_word_positions.js <image_path> [word1 word2 ...]
// Example: node detect_word_positions.js ../assets/books/biscuit_spread_01.png small yellow

const path = require('path');
const Tesseract = require('tesseract.js');

const args = process.argv.slice(2);
if (args.length < 1) {
  console.error('Usage: node detect_word_positions.js <image_path> [word1 word2 ...]');
  process.exit(1);
}

const imagePath = path.resolve(args[0]);
const targetWords = args.slice(1).map(w => w.toLowerCase());

async function main() {
  console.log(`\n📖  Scanning: ${imagePath}`);
  if (targetWords.length > 0) {
    console.log(`🔍  Looking for words: ${targetWords.join(', ')}\n`);
  }

  const result = await Tesseract.recognize(imagePath, 'eng', {
    logger: m => {
      if (m.status === 'recognizing text') {
        process.stdout.write(`\r⏳  Progress: ${(m.progress * 100).toFixed(0)}%   `);
      }
    },
  });

  console.log('\n');

  // Parse TSV output for word-level bounding boxes
  // TSV columns: level page_num block_num par_num line_num word_num left top width height conf text
  const tsv = result.data.tsv ?? '';
  if (!tsv) { console.error('No TSV output from Tesseract'); process.exit(1); }
  const lines = tsv.trim().split('\n').slice(1); // skip header

  // Get image dimensions from imageColor data URL
  const jimp = require('jimp');
  const img = await jimp.read(imagePath);
  const imgWidth  = img.bitmap.width;
  const imgHeight = img.bitmap.height;
  console.log(`📐  Image size: ${imgWidth} x ${imgHeight}\n`);

  const allWords = [];
  for (const line of lines) {
    const cols = line.split('\t');
    if (cols.length < 12) continue;
    const level = parseInt(cols[0]);
    if (level !== 5) continue; // level 5 = word
    const left   = parseInt(cols[6]);
    const top    = parseInt(cols[7]);
    const w      = parseInt(cols[8]);
    const h      = parseInt(cols[9]);
    const conf   = parseFloat(cols[10]);
    const text   = cols[11]?.trim() ?? '';
    if (!text || conf < 0) continue;
    allWords.push({
      word: text,
      normalized: {
        x:      +(left / imgWidth).toFixed(4),
        y:      +(top  / imgHeight).toFixed(4),
        width:  +(w    / imgWidth).toFixed(4),
        height: +(h    / imgHeight).toFixed(4),
      },
      conf,
    });
  }

  // Filter to target words if provided, otherwise show all
  const matches = targetWords.length > 0
    ? allWords.filter(w => targetWords.includes(w.word.toLowerCase().replace(/[^a-z']/g, '')))
    : allWords;

  if (matches.length === 0) {
    console.log('⚠️  No matches found. Showing all detected words:\n');
    for (const w of allWords) {
      console.log(`  "${w.word}"  conf:${w.conf.toFixed(0)}  x:${w.normalized.x} y:${w.normalized.y} w:${w.normalized.width} h:${w.normalized.height}`);
    }
    return;
  }

  console.log('✅  Results (copy into JSON highlights array):\n');
  const jsonOutput = matches.map(w => ({
    word:       w.word.toLowerCase().replace(/[^a-z']/g, ''),
    x:          w.normalized.x,
    y:          w.normalized.y,
    width:      w.normalized.width,
    height:     w.normalized.height,
    color:      '#FFD93D',
    positionMs: 0,
  }));

  console.log(JSON.stringify(jsonOutput, null, 2));

  if (targetWords.length > 0) {
    const found = new Set(matches.map(w => w.word.toLowerCase().replace(/[^a-z']/g, '')));
    const missing = targetWords.filter(w => !found.has(w));
    if (missing.length > 0) {
      console.log(`\n⚠️  Not found (OCR may have missed them): ${missing.join(', ')}`);
      console.log('💡  Try running without target words to see all detected text.');
    }
  }
}

main().catch(console.error);
