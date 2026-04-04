#!/usr/bin/env node
/**
 * Convert all large PNG files to WebP for much smaller file sizes.
 * Keeps the original .png extension but replaces content with WebP-compressed version.
 * Actually: renames to .webp and updates all Dart references.
 *
 * Strategy: convert PNG → WebP in-place (same filename but .webp),
 * then update all .dart files that reference the old .png path.
 */

const sharp = require('sharp');
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const ASSETS_DIR = path.join(__dirname, '..', 'assets');
const MIN_SIZE = 500 * 1024; // 500KB threshold
const WEBP_QUALITY = 82; // Good quality, big size reduction

async function findLargePngs(dir) {
  const results = [];
  const items = fs.readdirSync(dir, { withFileTypes: true });
  for (const item of items) {
    const fullPath = path.join(dir, item.name);
    if (item.isDirectory()) {
      results.push(...await findLargePngs(fullPath));
    } else if (item.name.endsWith('.png')) {
      const stat = fs.statSync(fullPath);
      if (stat.size >= MIN_SIZE) {
        results.push({ path: fullPath, size: stat.size });
      }
    }
  }
  return results;
}

async function main() {
  const files = await findLargePngs(ASSETS_DIR);
  files.sort((a, b) => b.size - a.size);

  console.log(`Found ${files.length} PNG files > 500KB (total: ${(files.reduce((s, f) => s + f.size, 0) / 1024 / 1024).toFixed(0)}MB)\n`);

  let totalBefore = 0, totalAfter = 0;
  const renames = []; // { oldRef, newRef }

  for (const file of files) {
    const webpPath = file.path.replace(/\.png$/, '.webp');
    const relOld = path.relative(path.join(__dirname, '..'), file.path).replace(/\\/g, '/');
    const relNew = path.relative(path.join(__dirname, '..'), webpPath).replace(/\\/g, '/');

    try {
      await sharp(file.path)
        .webp({ quality: WEBP_QUALITY })
        .toFile(webpPath);

      const newSize = fs.statSync(webpPath).size;
      const ratio = ((1 - newSize / file.size) * 100).toFixed(0);

      totalBefore += file.size;
      totalAfter += newSize;

      // Delete original PNG
      fs.unlinkSync(file.path);

      renames.push({ oldRef: relOld, newRef: relNew });

      const mb = (s) => (s / 1024 / 1024).toFixed(1);
      console.log(`✓ ${path.basename(file.path)}: ${mb(file.size)}MB → ${mb(newSize)}MB (-${ratio}%)`);
    } catch (e) {
      console.error(`✗ ${path.basename(file.path)}: ${e.message}`);
    }
  }

  console.log(`\n=== Total: ${(totalBefore / 1024 / 1024).toFixed(0)}MB → ${(totalAfter / 1024 / 1024).toFixed(0)}MB (saved ${((totalBefore - totalAfter) / 1024 / 1024).toFixed(0)}MB) ===\n`);

  // Update all .dart files
  console.log('Updating Dart references...');
  const dartDir = path.join(__dirname, '..', 'lib');
  const pubspec = path.join(__dirname, '..', 'pubspec.yaml');

  function updateRefs(dir) {
    const items = fs.readdirSync(dir, { withFileTypes: true });
    for (const item of items) {
      const fullPath = path.join(dir, item.name);
      if (item.isDirectory()) {
        updateRefs(fullPath);
      } else if (item.name.endsWith('.dart')) {
        let content = fs.readFileSync(fullPath, 'utf8');
        let changed = false;
        for (const { oldRef, newRef } of renames) {
          // Match both full path and just the filename portion
          const oldName = path.basename(oldRef);
          const newName = path.basename(newRef);
          if (content.includes(oldName)) {
            content = content.replaceAll(oldName, newName);
            changed = true;
          }
        }
        if (changed) {
          fs.writeFileSync(fullPath, content);
          console.log(`  Updated: ${path.relative(path.join(__dirname, '..'), fullPath)}`);
        }
      }
    }
  }

  updateRefs(dartDir);

  // Also update pubspec.yaml if it references specific images
  if (fs.existsSync(pubspec)) {
    let content = fs.readFileSync(pubspec, 'utf8');
    let changed = false;
    for (const { oldRef, newRef } of renames) {
      const oldName = path.basename(oldRef);
      const newName = path.basename(newRef);
      if (content.includes(oldName)) {
        content = content.replaceAll(oldName, newName);
        changed = true;
      }
    }
    if (changed) {
      fs.writeFileSync(pubspec, content);
      console.log('  Updated: pubspec.yaml');
    }
  }

  console.log('\nDone!');
}

main().catch(console.error);
