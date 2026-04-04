#!/usr/bin/env node
/**
 * Organize Biscuit book series from baidunetdiskdownload into assets/books/
 * Match MP3 audio files with PDF files by book name.
 */

const fs = require('fs');
const path = require('path');

const SRC = path.join(__dirname, '..', 'baidunetdiskdownload');
const DEST = path.join(__dirname, '..', 'assets', 'books');

// Map MP3 number → folder name + PDF name
// MP3 files are numbered 01-24, PDF names vary slightly
const books = [
  { num: '01', folder: '01Biscuit', mp3: '01-Biscuit.mp3', pdf: 'Biscuit.pdf' },
  { num: '02', folder: '02Biscuit_and_the_Baby', mp3: '02-Biscuit and the baby.mp3', pdf: 'Biscuit and the Baby.pdf' },
  { num: '03', folder: '03Biscuit_Loves_the_Library', mp3: '03-Biscuit Loves the Library.mp3', pdf: null }, // already in folder
  { num: '04', folder: '04Biscuit_Finds_a_Friend', mp3: '04-Biscuit Finds a Friend.mp3', pdf: 'Biscuit Finds a Friend.pdf' },
  { num: '05', folder: '05Biscuits_New_Trick', mp3: "05-Biscuit's New Trick.mp3", pdf: "Biscuit's New Trick.pdf" },
  { num: '06', folder: '06Biscuits_Day_at_the_Farm', mp3: "06-Biscuit's Day at the Farm.mp3", pdf: "Biscuit's Day at the Farm.pdf" },
  { num: '07', folder: '07Bathtime_for_Biscuit', mp3: '07-Bath time for Biscuit.mp3', pdf: 'Bathtime for Biscuit.pdf' },
  { num: '08', folder: '08Biscuit_Wins_a_Prize', mp3: '08-Biscuit Wins a Prize.mp3', pdf: 'Biscuit Wins a Prize.pdf' },
  { num: '09', folder: '09Biscuit_Visits_the_Big_City', mp3: '09-Biscuit Visits the Big City.mp3', pdf: 'Biscuit Visits the Big City.pdf' },
  { num: '10', folder: '10Biscuit_Feeds_the_Pets', mp3: '10-Biscuit feeds the pets.mp3', pdf: null },
  { num: '11', folder: '11Biscuit_Plays_Ball', mp3: '11-Biscuit plays ball.mp3', pdf: 'Biscuit Plays Ball.pdf' },
  { num: '12', folder: '12Biscuit_and_the_Little_Pup', mp3: '12-Biscuit and the Little Pup.mp3', pdf: 'Biscuit and the Little Pup.pdf' },
  { num: '13', folder: '13Biscuits_Big_Friend', mp3: "13-Biscuit's Big Friend.mp3", pdf: "Biscuit's Big Friend.pdf" },
  { num: '14', folder: '14Biscuit_Goes_to_School', mp3: '14-Biscuit Goes to School.mp3', pdf: 'Biscuit Goes to School.pdf' },
  { num: '15', folder: '15Biscuit_in_the_Garden', mp3: '15-Biscuit in the garden.mp3', pdf: 'Biscuit in the Garden.pdf' },
  { num: '16', folder: '16Biscuit_Takes_a_Walk', mp3: '16-Biscuit Takes a Walk.mp3', pdf: 'Biscuit Takes a Walk.pdf' },
  { num: '17', folder: '17Biscuit_Meets_the_Class_Pet', mp3: '17-Biscuit Meets the Class Pet.mp3', pdf: 'Biscuit Meets the Class Pet.pdf' },
  { num: '18', folder: '18Biscuit_Wants_to_Play', mp3: '18-Biscuit Wants to Play.mP3', pdf: 'Biscuit Wants to Play.pdf' },
  { num: '19', folder: '19Biscuit_and_the_Lost_Teddy_Bear', mp3: '19-Biscuit and the Lost Teddy Bear.mp3', pdf: 'Biscuit and the Lost Teddy Bear.pdf' },
  { num: '20', folder: '20Biscuit_Flies_a_Kite', mp3: '20-Biscuit flies a kite.mp3', pdf: null },
  { num: '21', folder: '21Biscuit_Goes_Camping', mp3: '21-Biscuit Goes Camping.mp3', pdf: null },
  { num: '22', folder: '22Biscuit_and_the_Big_Parade', mp3: '22-Biscuit and the big parade.mp3', pdf: null },
  { num: '23', folder: '23Biscuit_Loves_the_Park', mp3: '23-Biscuit Loves the Park.mp3', pdf: null },
  { num: '24', folder: '24Biscuit_Snow_Day_Race', mp3: '24-Biscuit Snow Day Race.mp3', pdf: null },
];

console.log('Organizing Biscuit book series...\n');

for (const book of books) {
  const destDir = path.join(DEST, book.folder);
  if (!fs.existsSync(destDir)) fs.mkdirSync(destDir, { recursive: true });

  // Copy MP3
  const mp3Src = path.join(SRC, book.mp3);
  const mp3Dest = path.join(destDir, 'audio.mp3');
  if (fs.existsSync(mp3Src) && !fs.existsSync(mp3Dest)) {
    fs.copyFileSync(mp3Src, mp3Dest);
    console.log(`✓ ${book.folder}/audio.mp3`);
  } else if (fs.existsSync(mp3Dest)) {
    console.log(`⏭ ${book.folder}/audio.mp3 (exists)`);
  } else {
    console.log(`✗ ${book.folder}/audio.mp3 — MP3 not found: ${book.mp3}`);
  }

  // Copy PDF
  if (book.pdf) {
    const pdfSrc = path.join(SRC, book.pdf);
    const pdfDest = path.join(destDir, 'book.pdf');
    if (fs.existsSync(pdfSrc) && !fs.existsSync(pdfDest)) {
      fs.copyFileSync(pdfSrc, pdfDest);
      console.log(`✓ ${book.folder}/book.pdf`);
    } else if (fs.existsSync(pdfDest)) {
      console.log(`⏭ ${book.folder}/book.pdf (exists)`);
    } else {
      console.log(`✗ ${book.folder}/book.pdf — PDF not found: ${book.pdf}`);
    }
  } else {
    // Check if PDF already exists in dest folder
    const existing = fs.readdirSync(destDir).find(f => f.endsWith('.pdf'));
    if (existing) {
      console.log(`⏭ ${book.folder}/${existing} (already there)`);
    } else {
      console.log(`⚠ ${book.folder} — no PDF available`);
    }
  }
}

// Summary
console.log('\n=== Summary ===');
const folders = fs.readdirSync(DEST).filter(f => fs.statSync(path.join(DEST, f)).isDirectory());
let withPdf = 0, withMp3 = 0;
for (const f of folders) {
  const files = fs.readdirSync(path.join(DEST, f));
  const hasPdf = files.some(x => x.endsWith('.pdf'));
  const hasMp3 = files.some(x => x.endsWith('.mp3'));
  if (hasPdf) withPdf++;
  if (hasMp3) withMp3++;
}
console.log(`Total: ${folders.length} books, ${withMp3} with audio, ${withPdf} with PDF`);
