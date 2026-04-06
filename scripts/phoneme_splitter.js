/**
 * Split English words into phonemes for phonics teaching.
 *
 * Rules (layered):
 *   Layer 1 — CVC: split every letter individually (p-i-g, c-a-t)
 *   Layer 2 — Digraphs/Blends: keep multi-letter units together (sh-i-p, ch-i-n)
 *   Layer 3 — Long vowels: vowel teams stay together (b-oa-t, r-ai-n)
 *
 * Digraphs (never split): sh, ch, th, ph, wh, ck, ng, nk, tch
 * Blends (keep together): bl, br, cl, cr, dr, fl, fr, gl, gr, pl, pr, sc, sk, sl, sm, sn, sp, st, sw, tr, tw
 * Double consonants: ll, ss, ff, zz, dd, mm, nn, pp, rr, tt
 * Vowel teams: ai, ay, ea, ee, oa, oo, ou, ow, oi, oy, igh, ar, er, ir, or, ur
 */

const fs = require('fs');
const path = require('path');

// Load available phoneme audio files
const PHONICS_DIR = path.join(__dirname, '..', 'assets', 'audio', 'phonics_sounds');
const availablePhonemes = new Set(
  fs.readdirSync(PHONICS_DIR)
    .filter(f => f.endsWith('.mp3') && !f.startsWith('word_') && !f.startsWith('_'))
    .map(f => f.replace('.mp3', ''))
);

// Multi-letter units sorted longest first
const DIGRAPHS = ['tch', 'sh', 'ch', 'th', 'ph', 'wh', 'ck', 'ng', 'nk'];
const BLENDS = ['spl', 'spr', 'str', 'scr', 'bl', 'br', 'cl', 'cr', 'dr', 'fl', 'fr', 'gl', 'gr', 'pl', 'pr', 'sc', 'sk', 'sl', 'sm', 'sn', 'sp', 'st', 'sw', 'tr', 'tw'];
const DOUBLES = ['ll', 'ss', 'ff', 'zz', 'dd', 'mm', 'nn', 'pp', 'rr', 'tt'];
const VOWEL_TEAMS = ['igh', 'ai', 'ay', 'ea', 'ee', 'oa', 'oo', 'ou', 'ow', 'oi', 'oy', 'ar', 'er', 'ir', 'or', 'ur'];

// All multi-letter units, longest first
const UNITS = [...new Set([...DIGRAPHS, ...BLENDS, ...DOUBLES, ...VOWEL_TEAMS])]
  .sort((a, b) => b.length - a.length);

/**
 * Split a word into phonemes.
 * Scans left-to-right, matching multi-letter units first, single letters as fallback.
 */
function splitWord(word) {
  word = word.toLowerCase().trim();
  if (!word) return [];

  const result = [];
  let i = 0;

  while (i < word.length) {
    let matched = false;

    // Try multi-letter units (longest first)
    for (const unit of UNITS) {
      if (i + unit.length <= word.length && word.substring(i, i + unit.length) === unit) {
        result.push(unit);
        i += unit.length;
        matched = true;
        break;
      }
    }

    if (!matched) {
      result.push(word[i]);
      i++;
    }
  }

  return result;
}

/**
 * Strip common suffixes to get base form for phonics.
 * pigs → pig, runs → run, played → play
 */
function baseForm(word) {
  word = word.toLowerCase().trim();
  // Don't strip if word is too short
  if (word.length <= 3) return word;
  // Don't strip words where 's' is part of the word (bus, his, this)
  const keepS = new Set(['bus', 'his', 'this', 'yes', 'us', 'gas', 'plus']);
  if (keepS.has(word)) return word;
  // Strip trailing 's' for plurals (pigs→pig, hens→hen)
  if (word.endsWith('s') && !word.endsWith('ss')) return word.slice(0, -1);
  return word;
}

/**
 * Check if all phonemes have corresponding audio files.
 */
function validateSplit(phonemes) {
  return phonemes.every(p => availablePhonemes.has(p));
}

/**
 * Check if a word is good for phonics teaching.
 * Rejects irregular words where letters don't match their standard sounds.
 * Returns { ok: true } or { ok: false, reason: string }
 */
function isGoodForPhonics(word) {
  word = word.toLowerCase().trim();

  // Irregular pronunciation — letters don't match sounds
  const irregular = new Set([
    // silent letters
    'walk','talk','chalk','half','calm','palm','could','would','should','know','knee','knit','knife',
    'write','wrong','wrap','lamb','climb','comb','doubt','debt','island','listen','castle','whistle',
    // vowel not standard
    'many','any','some','come','done','gone','give','live','love','move','none','once','only',
    'other','water','want','what','were','where','who','why','said','says','does','sure','sugar',
    'put','push','pull','full','bull','busy','built','buy','eye','friend','great','break',
    'city','nice','rice','ice','face','race','place','cent','cell','age','page','cage','huge',
    'heart','learn','earn','earth','heard','pearl','bear','pear','wear','swear',
    // too short or ambiguous
    'the','are','is','am','was','to','do','go','no','so',
  ]);
  if (irregular.has(word)) return { ok: false, reason: 'irregular pronunciation' };

  // Must be 3-5 letters
  if (word.length < 3 || word.length > 5) return { ok: false, reason: 'length not 3-5' };

  // Must be only letters
  if (!/^[a-z]+$/.test(word)) return { ok: false, reason: 'non-letter chars' };

  // All phonemes must have audio files
  const phonemes = splitWord(word);
  if (!validateSplit(phonemes)) return { ok: false, reason: 'missing phoneme audio: ' + phonemes.filter(p => !availablePhonemes.has(p)).join(',') };

  // Phonemes should reconstruct the original word
  if (phonemes.join('') !== word) return { ok: false, reason: 'phonemes don\'t reconstruct word' };

  // Rule-based pronunciation checks:

  // "c" before e/i/y makes /s/ not /k/ (city, cell, cycle)
  if (/c[eiy]/i.test(word)) return { ok: false, reason: 'soft c (c before e/i/y = /s/)' };

  // "g" before e/i makes /j/ not /g/ (gem, giant) — but not always (get, give)
  const softGExceptions = new Set(['get','got','give','girl','gift','gig']);
  if (/g[ei]/i.test(word) && !softGExceptions.has(word)) return { ok: false, reason: 'possible soft g (g before e/i)' };

  // Silent e at end: changes vowel sound (cake, bone, cute — not simple CVC)
  if (word.length >= 4 && word.endsWith('e') && /[bcdfghjklmnpqrstvwxyz]e$/.test(word)) {
    // Check if it's a_e, i_e, o_e, u_e pattern (magic e)
    const beforeE = word[word.length - 2];
    const twoBeforeE = word[word.length - 3];
    if ('aeiou'.includes(twoBeforeE) && !'aeiou'.includes(beforeE)) {
      return { ok: false, reason: 'magic e (silent e changes vowel)' };
    }
  }

  // Double vowels that don't follow standard rules
  if (/[aeiou]{3}/.test(word)) return { ok: false, reason: 'triple vowel cluster' };

  // "tion", "sion" endings
  if (/[ts]ion/.test(word)) return { ok: false, reason: 'tion/sion ending' };

  // "ght" — the gh is silent
  if (word.includes('ght')) return { ok: false, reason: 'silent gh in ght' };

  return { ok: true };
}

module.exports = { splitWord, validateSplit, availablePhonemes, baseForm, isGoodForPhonics };

// CLI test mode
if (require.main === module) {
  const testWords = [
    // Layer 1: CVC
    'pig', 'cat', 'dog', 'bed', 'hug', 'fun', 'pet', 'nap', 'big', 'wet', 'got', 'mud', 'sit',
    // Layer 2: Digraphs & Blends
    'ship', 'chin', 'thin', 'fish', 'duck', 'back', 'kick', 'lock', 'bath',
    'play', 'tree', 'frog', 'stop', 'swim', 'bring', 'splash',
    // Layer 2: Double consonants
    'ball', 'bell', 'hill', 'miss',
    // Layer 3: Vowel teams
    'boat', 'rain', 'moon', 'food', 'night',
    // Plurals (should use baseForm first)
    'pigs', 'hens', 'dogs',
  ];

  console.log('Phoneme Splitter Test:\n');
  for (const w of testWords) {
    const base = baseForm(w);
    const split = splitWord(base);
    const valid = validateSplit(split);
    const baseNote = base !== w ? ` (${w}→${base})` : '';
    console.log(`  ${w.padEnd(10)} → [${split.join('-')}]${baseNote} ${valid ? '✓' : '✗ missing: ' + split.filter(p => !availablePhonemes.has(p)).join(',')}`);
  }
}
