#!/usr/bin/env node
/**
 * Flatten all phonics_sounds subdirectories into one flat directory.
 * Rename special characters in filenames to be code-friendly.
 */

const fs = require('fs');
const path = require('path');

const BASE = path.join(__dirname, '..', 'assets', 'audio', 'phonics_sounds');

// Rename mapping for special filenames
const renameMap = {
  'c(soft).mp3': 'c_soft.mp3',
  'g(soft).mp3': 'g_soft.mp3',
  'u(under).mp3': 'u_under.mp3',
  'y(ai).mp3': 'y_ai.mp3',
  'ow2.mp3': 'ow_ou.mp3', // ow as in "cow" (ou sound)
};

function getAllFiles(dir) {
  const results = [];
  const items = fs.readdirSync(dir, { withFileTypes: true });
  for (const item of items) {
    const full = path.join(dir, item.name);
    if (item.isDirectory()) {
      results.push(...getAllFiles(full));
    } else if (item.name.endsWith('.mp3')) {
      results.push(full);
    }
  }
  return results;
}

const files = getAllFiles(BASE);
console.log(`Found ${files.length} mp3 files\n`);

let moved = 0;
for (const src of files) {
  const origName = path.basename(src);
  const newName = renameMap[origName] || origName;
  const dest = path.join(BASE, newName);

  // Skip if already in root
  if (path.dirname(src) === BASE && origName === newName) continue;

  // Check conflict
  if (fs.existsSync(dest) && path.dirname(src) !== BASE) {
    console.log(`⚠ Conflict: ${newName} (keeping new from ${path.relative(BASE, src)})`);
    fs.unlinkSync(dest);
  }

  fs.renameSync(src, dest);
  if (origName !== newName) {
    console.log(`✓ ${path.relative(BASE, src)} → ${newName} (renamed)`);
  } else {
    console.log(`✓ ${path.relative(BASE, src)} → ${newName}`);
  }
  moved++;
}

// Remove empty subdirectories
function removeEmptyDirs(dir) {
  const items = fs.readdirSync(dir, { withFileTypes: true });
  for (const item of items) {
    if (item.isDirectory()) {
      const full = path.join(dir, item.name);
      removeEmptyDirs(full);
      try { fs.rmdirSync(full); console.log(`🗑 Removed empty dir: ${item.name}/`); } catch {}
    }
  }
}
removeEmptyDirs(BASE);

console.log(`\nDone! Moved ${moved} files.`);
