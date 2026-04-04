/**
 * Split English words into phonemes based on available audio files.
 * Only uses phoneme units that have corresponding .mp3 files in phonics_sounds/.
 *
 * Usage:
 *   const { splitWord } = require('./phoneme_splitter');
 *   splitWord('duck')  // → ['d', 'u', 'ck']
 *   splitWord('ball')  // → ['b', 'all']
 *   splitWord('bone')  // → ['b', 'o', 'n', 'e']  (silent e treated as separate for now)
 *   splitWord('ship')  // → ['sh', 'i', 'p']
 */

const fs = require('fs');
const path = require('path');

// Load all available phoneme units from audio files
const PHONICS_DIR = path.join(__dirname, '..', 'assets', 'audio', 'phonics_sounds');
const availablePhonemes = new Set(
  fs.readdirSync(PHONICS_DIR)
    .filter(f => f.endsWith('.mp3') && !f.startsWith('word_') && !f.startsWith('_'))
    .map(f => f.replace('.mp3', ''))
);

// Multi-character phonemes sorted by length (longest first for greedy matching)
const multiPhonemes = [...availablePhonemes]
  .filter(p => p.length > 1 && !p.includes('_')) // exclude a_e style (magic e patterns)
  .sort((a, b) => b.length - a.length);

// Common word family endings (from our audio files)
const wordFamilies = [...availablePhonemes]
  .filter(p => p.length >= 2 && /^[aeiou]/.test(p)) // starts with vowel: all, ell, ill, igh, etc.
  .sort((a, b) => b.length - a.length);

/**
 * Split a word into phonemes using greedy matching from right to left.
 * Strategy:
 * 1. First check if the word ends with a known word family (all, ell, igh, etc.)
 * 2. Then scan left-to-right for multi-char consonant blends/digraphs
 * 3. Single letters as fallback
 */
function splitWord(word) {
  word = word.toLowerCase().trim();
  if (!word) return [];

  const result = [];
  let i = 0;

  // Check for word family ending first
  let familyMatch = null;
  for (const fam of wordFamilies) {
    if (word.endsWith(fam) && word.length > fam.length) {
      familyMatch = fam;
      break;
    }
  }

  const endIdx = familyMatch ? word.length - familyMatch.length : word.length;

  // Scan left to right for the beginning/middle part
  while (i < endIdx) {
    let matched = false;

    // Try multi-character phonemes (longest first): sh, ch, th, ck, bl, tr, str, etc.
    for (const mp of multiPhonemes) {
      if (i + mp.length <= endIdx && word.substring(i, i + mp.length) === mp) {
        result.push(mp);
        i += mp.length;
        matched = true;
        break;
      }
    }

    if (!matched) {
      // Single letter
      result.push(word[i]);
      i++;
    }
  }

  // Add word family ending
  if (familyMatch) {
    result.push(familyMatch);
  }

  return result;
}

/**
 * Check if all phonemes in the split have corresponding audio files.
 */
function validateSplit(phonemes) {
  return phonemes.every(p => availablePhonemes.has(p));
}

// Export
module.exports = { splitWord, validateSplit, availablePhonemes };

// CLI test mode
if (require.main === module) {
  const testWords = [
    'bed', 'hug', 'fun', 'pet', 'nap', 'big', 'wet', 'got', 'mud', 'dog', 'cat', 'sit',
    'ball', 'duck', 'bone', 'ship', 'chin', 'thin', 'fish', 'bell', 'hill', 'miss',
    'play', 'tree', 'frog', 'stop', 'swim', 'bring', 'splash',
    'lost', 'pond', 'back', 'kick', 'lock',
  ];

  console.log('Phoneme Splitter Test:\n');
  for (const w of testWords) {
    const split = splitWord(w);
    const valid = validateSplit(split);
    console.log(`  ${w.padEnd(10)} → [${split.join('-')}] ${valid ? '✓' : '✗ missing: ' + split.filter(p => !availablePhonemes.has(p)).join(',')}`);
  }
}
