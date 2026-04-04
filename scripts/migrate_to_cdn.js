#!/usr/bin/env node
/**
 * Migrate Image.asset → cdnImage and AssetSource → cdnAudioSource
 * across all screen files.
 */

const fs = require('fs');
const path = require('path');

const screensDir = path.join(__dirname, '..', 'lib', 'screens');
const files = fs.readdirSync(screensDir).filter(f => f.endsWith('.dart'));

const cdnImport = "import '../utils/cdn_asset.dart';";

let totalChanges = 0;

for (const file of files) {
  const filePath = path.join(screensDir, file);
  let content = fs.readFileSync(filePath, 'utf8');
  const orig = content;
  let changes = 0;

  // 1. Replace Image.asset('assets/...' with cdnImage('assets/...
  //    Handles: Image.asset('assets/xxx', fit: ..., width: ..., height: ...)
  //    → cdnImage('assets/xxx', fit: ..., width: ..., height: ...)
  content = content.replace(/Image\.asset\(\s*\n?\s*/g, (match) => {
    changes++;
    return 'cdnImage(';
  });

  // 2. Replace AssetSource(xxx) with cdnAudioSource(xxx)
  //    But handle the 'assets/' prefix stripping:
  //    AssetSource('audio/xxx.mp3') → cdnAudioSource('audio/xxx.mp3')
  //    AssetSource(path.replaceFirst('assets/', '')) → cdnAudioFromAssetPath(path)
  //    AssetSource(audioPath) → cdnAudioSource(audioPath)

  // Pattern A: AssetSource('audio/...') — literal string
  content = content.replace(/AssetSource\('(audio\/[^']+)'\)/g, (match, p1) => {
    changes++;
    return `cdnAudioSource('${p1}')`;
  });

  // Pattern B: AssetSource(variable.replaceFirst('assets/', ''))
  content = content.replace(/AssetSource\((\w+)\.replaceFirst\('assets\/', ''\)\)/g, (match, varName) => {
    changes++;
    return `cdnAudioFromAssetPath(${varName})`;
  });

  // Pattern C: AssetSource(variable) — simple variable
  content = content.replace(/AssetSource\((\w+)\)/g, (match, varName) => {
    changes++;
    return `cdnAudioSource(${varName})`;
  });

  // Pattern D: AssetSource(_tracks[i].path) — complex expression
  content = content.replace(/AssetSource\(([^)]+)\)/g, (match, expr) => {
    // Skip if already replaced
    if (expr.includes('cdn')) return match;
    changes++;
    return `cdnAudioSource(${expr})`;
  });

  if (changes === 0) continue;

  // Add import if not already there
  if (!content.includes(cdnImport) && !content.includes('cdn_asset.dart')) {
    // Add after last import line
    const lines = content.split('\n');
    let lastImportIdx = 0;
    for (let i = 0; i < lines.length; i++) {
      if (lines[i].startsWith('import ')) lastImportIdx = i;
    }
    lines.splice(lastImportIdx + 1, 0, cdnImport);
    content = lines.join('\n');
  }

  fs.writeFileSync(filePath, content);
  console.log(`✓ ${file}: ${changes} changes`);
  totalChanges += changes;
}

console.log(`\nTotal: ${totalChanges} changes across ${files.length} files`);
