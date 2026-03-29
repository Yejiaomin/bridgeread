#!/usr/bin/env node
// BridgeRead — Step 2: Generate CN narration in Amy's style via Claude API
//
// Usage:
//   node gen_narration.js <book_input.json> [--out=<output.json>]
//
// Input format (book_input.json):
// {
//   "bookId": "curious_george",
//   "bookTitle": "Curious George",
//   "pages": [
//     { "en": "This is George.", "keywords": ["George"] },
//     ...
//   ]
// }
//
// Output: same structure with "cn" field added to each page

const fs   = require('fs');
const path = require('path');

// ── Config ────────────────────────────────────────────────────────────────────

const envPath = path.join(__dirname, '..', '.env');
const envText = fs.existsSync(envPath) ? fs.readFileSync(envPath, 'utf8') : '';
const ANTHROPIC_KEY = envText.match(/ANTHROPIC_API_KEY=(.+)/)?.[1]?.trim()
                   || process.env.ANTHROPIC_API_KEY;

if (!ANTHROPIC_KEY) {
  console.error('❌ 需要 ANTHROPIC_API_KEY（在 .env 或环境变量中）');
  process.exit(1);
}

// ── Args ──────────────────────────────────────────────────────────────────────

const args = process.argv.slice(2);
if (args.length < 1) {
  console.error('Usage: node gen_narration.js <book_input.json> [--out=<output.json>]');
  process.exit(1);
}

const inputPath = path.resolve(args[0]);
let outPath = inputPath.replace(/\.json$/, '_narrated.json');
for (const arg of args.slice(1)) {
  if (arg.startsWith('--out=')) outPath = path.resolve(arg.replace('--out=', ''));
}

const input = JSON.parse(fs.readFileSync(inputPath, 'utf8'));

// ── Style examples from Book 1 (Amy's voice) ─────────────────────────────────

const STYLE_EXAMPLES = [
  {
    en: 'This is Biscuit. Biscuit is small. Biscuit is yellow.',
    keywords: ['small', 'yellow'],
    cn: '呀~ 你们看到了吗？这就是今天的小主角，一只叫Biscuit的小狗！你知道biscuit是什么意思吗？哈哈，没错，就是饼干的意思，你看他个子小小的，毛是黄色的，是不是很像黄油饼干呀！',
  },
  {
    en: 'Time for bed, Biscuit! Woof, woof! Biscuit wants to play.',
    keywords: ['bed', 'play'],
    cn: '好像要到睡觉时间啦！小女孩叫Biscuit去睡觉。这个bed就是小床，Time for bed就是该上床睡觉啦！但是你说Biscuit想不想睡啊？对了，他可不想睡，他大声的说 —— Woof woof！他想玩，他想玩！',
  },
  {
    en: 'Biscuit wants a drink of water.',
    keywords: ['water'],
    cn: '哎，Biscuit要喝水了！Water就是水，a drink of water就是要喝一口水。你也喝水了吗？',
  },
  {
    en: 'Biscuit wants a hug.',
    keywords: ['hug'],
    cn: '哇，Biscuit还要抱抱！Hug就是抱抱的意思，小狗也需要爱呢！你喜欢给小动物抱抱吗？',
  },
];

// ── Claude API call ───────────────────────────────────────────────────────────

async function generateCN(pageEn, keywords, bookTitle, isIntro) {
  const examplesText = STYLE_EXAMPLES.map((ex, i) =>
    `例${i + 1}:\nEN: "${ex.en}"\n关键词: ${ex.keywords.join(', ')}\nCN旁白: "${ex.cn}"`
  ).join('\n\n');

  const systemPrompt = `你是BridgeRead英语绘本app里的主持人Amy，专门给3-7岁中国小朋友用中文讲解英语绘本。

Amy的风格：
- 活泼热情，像和孩子玩耍一样
- 用"你""你们""你知道吗""是不是""对不对"等词直接互动
- 遇到关键词时，用中文解释它的意思（比如："small就是小小的意思"）
- 用"呀""啊""哦""哈哈""哎"等语气词，口语化
- 每段旁白80-150字，不能太长
- 不要说"让我们"，要说"我们"
- 不要生硬地翻译，要讲故事感
- 中英文混用自然，英文单词用原文不要翻译拼写`;

  const userPrompt = isIntro
    ? `这是绘本《${bookTitle}》的开场介绍页。
写一段Amy风格的中文旁白，欢迎小朋友，介绍这本书。
格式要像："Hello Hello, my dear friend！I am Amy! 我们又见面啦！今天我们要讲${bookTitle}的故事..."
只输出旁白文字，不要加任何解释。`
    : `这是绘本《${bookTitle}》的一页内容。

英文原文：
"${pageEn}"

本页关键词（需要重点解释）：${keywords.join('、')}

参考Amy的风格示例：
${examplesText}

请写一段Amy风格的中文旁白，解释这页内容并重点讲解关键词。
只输出旁白文字，不要加任何解释或引号。`;

  const response = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'x-api-key': ANTHROPIC_KEY,
      'anthropic-version': '2023-06-01',
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      model: 'claude-haiku-4-5-20251001',
      max_tokens: 400,
      system: systemPrompt,
      messages: [{ role: 'user', content: userPrompt }],
    }),
  });

  if (!response.ok) {
    const err = await response.text();
    throw new Error(`Claude API error ${response.status}: ${err}`);
  }

  const data = await response.json();
  return data.content[0].text.trim();
}

// ── Main ──────────────────────────────────────────────────────────────────────

async function main() {
  console.log(`\n✍️  BridgeRead CN 旁白生成器`);
  console.log(`📖  书名: ${input.bookTitle}`);
  console.log(`📄  页数: ${input.pages.length} 页\n`);

  const result = {
    ...input,
    pages: [],
  };

  // Intro page (always first)
  process.stdout.write(`  [封面] 生成开场旁白...`);
  const introCN = await generateCN('', [], input.bookTitle, true);
  result.pages.push({
    en: '',
    cn: introCN,
    keywords: [],
    isIntro: true,
  });
  console.log(` ✅`);
  console.log(`  → "${introCN.slice(0, 50)}..."\n`);

  // Story pages
  for (let i = 0; i < input.pages.length; i++) {
    const page = input.pages[i];
    process.stdout.write(`  [第 ${i + 1} 页] "${page.en.slice(0, 40)}..." 生成旁白...`);

    try {
      const cn = await generateCN(page.en, page.keywords || [], input.bookTitle, false);
      result.pages.push({ ...page, cn });
      console.log(` ✅`);
      console.log(`  → "${cn.slice(0, 60)}..."\n`);
    } catch (err) {
      console.log(` ❌ ${err.message}`);
      result.pages.push({ ...page, cn: '[生成失败，请手动填写]' });
    }

    // Rate limit: pause between calls
    if (i < input.pages.length - 1) {
      await new Promise(r => setTimeout(r, 300));
    }
  }

  fs.writeFileSync(outPath, JSON.stringify(result, null, 2), 'utf8');

  console.log(`\n🎉 完成！旁白已保存到:`);
  console.log(`   ${outPath}`);
  console.log(`\n📝 下一步: 检查旁白内容，然后运行 gen_audio.js\n`);
}

main().catch(err => {
  console.error('❌', err.message);
  process.exit(1);
});
