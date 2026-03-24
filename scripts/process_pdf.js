// BridgeRead - PDF页面处理脚本
// 功能：把绘本PDF转成适合横屏平板的双页图片
// 规则：第1页单页，第2-3页跳过，第4+5页合并，第6+7页合并，以此类推

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const PDF_DIR = path.join(__dirname, '..', 'assets', 'pdf');
const OUTPUT_DIR = path.join(__dirname, '..', 'assets', 'books');

// 确保输出目录存在
if (!fs.existsSync(OUTPUT_DIR)) {
  fs.mkdirSync(OUTPUT_DIR, { recursive: true });
}

// 找到PDF文件
const pdfFiles = fs.readdirSync(PDF_DIR).filter(f => f.toLowerCase().endsWith('.pdf'));
if (pdfFiles.length === 0) {
  console.error('❌ 没有找到PDF文件，请确认路径：' + PDF_DIR);
  process.exit(1);
}

const pdfPath = path.join(PDF_DIR, pdfFiles[0]);
console.log(`\n📖 处理PDF: ${pdfFiles[0]}`);

// 临时目录存放单页图片
const TEMP_DIR = path.join(__dirname, '..', 'assets', '_temp_pages');
if (!fs.existsSync(TEMP_DIR)) {
  fs.mkdirSync(TEMP_DIR, { recursive: true });
}

// 检查是否有pdftoppm或其他工具
function checkTools() {
  const tools = ['pdftoppm', 'convert', 'magick'];
  for (const tool of tools) {
    try {
      execSync(`${tool} --version 2>&1`, { stdio: 'pipe' });
      return tool;
    } catch {}
  }
  return null;
}

const tool = checkTools();

if (!tool) {
  // 没有命令行工具，提供替代方案
  console.log('\n⚠️  没有检测到PDF处理工具（pdftoppm/ImageMagick）');
  console.log('\n请按以下步骤手动处理：');
  console.log('1. 用浏览器打开PDF（Chrome/Edge）');
  console.log('2. 打印 → 另存为PDF，或截图每一页');
  console.log('3. 或者安装 ImageMagick: https://imagemagick.org/script/download.php#windows');
  console.log('\n安装ImageMagick后重新运行此脚本');
  console.log('\n📋 页面合并规则：');
  console.log('  第1页  → biscuit_cover.png（封面，单页）');
  console.log('  第2-3页 → 跳过');
  console.log('  第4-5页 → biscuit_spread_01.png（左右合并）');
  console.log('  第6-7页 → biscuit_spread_02.png（左右合并）');
  console.log('  第8-9页 → biscuit_spread_03.png');
  console.log('  ...以此类推');
  process.exit(0);
}

console.log(`✅ 使用工具: ${tool}`);

// 用ImageMagick提取PDF页面
console.log('\n📄 提取PDF页面...');
try {
  if (tool === 'magick' || tool === 'convert') {
    execSync(`${tool} -density 150 "${pdfPath}" "${TEMP_DIR}/page-%03d.png"`, { stdio: 'inherit' });
  } else if (tool === 'pdftoppm') {
    execSync(`pdftoppm -png -r 150 "${pdfPath}" "${TEMP_DIR}/page"`, { stdio: 'inherit' });
  }
} catch (err) {
  console.error('❌ 提取失败:', err.message);
  process.exit(1);
}

// 获取所有页面文件
const pageFiles = fs.readdirSync(TEMP_DIR)
  .filter(f => f.endsWith('.png'))
  .sort();

console.log(`✅ 提取了 ${pageFiles.length} 页`);

// 处理页面
// 第0页（index）= 封面 → 单页
// 第1、2页 = 跳过
// 第3+4页 合并 → spread_01
// 第5+6页 合并 → spread_02
// ...

let spreadCount = 1;

for (let i = 0; i < pageFiles.length; i++) {
  const pageFile = path.join(TEMP_DIR, pageFiles[i]);
  
  if (i === 0) {
    // 封面单页
    const output = path.join(OUTPUT_DIR, 'biscuit_cover.png');
    fs.copyFileSync(pageFile, output);
    console.log(`✅ 封面: biscuit_cover.png`);
    
  } else if (i === 1 || i === 2) {
    // 跳过第2、3页
    console.log(`⏭️  跳过第 ${i + 1} 页`);
    
  } else if (i % 2 === 1) {
    // 奇数页（左页），等右页
    continue;
    
  } else {
    // 偶数页（右页），和上一页合并
    const leftFile = path.join(TEMP_DIR, pageFiles[i - 1]);
    const rightFile = pageFile;
    const output = path.join(OUTPUT_DIR, `biscuit_spread_${String(spreadCount).padStart(2, '0')}.png`);
    
    try {
      execSync(`${tool === 'magick' ? 'magick' : 'convert'} "${leftFile}" "${rightFile}" +append "${output}"`, 
        { stdio: 'inherit' });
      console.log(`✅ 合并: biscuit_spread_${String(spreadCount).padStart(2, '0')}.png (第${i}+${i+1}页)`);
      spreadCount++;
    } catch (err) {
      console.error(`❌ 合并失败 第${i}+${i+1}页:`, err.message);
    }
  }
}

// 清理临时文件
console.log('\n🧹 清理临时文件...');
fs.rmSync(TEMP_DIR, { recursive: true });

console.log(`\n🎉 完成！共生成 ${spreadCount} 个跨页图片`);
console.log(`📁 文件保存在: ${OUTPUT_DIR}`);
console.log('\n生成的文件：');
fs.readdirSync(OUTPUT_DIR)
  .filter(f => f.startsWith('biscuit_'))
  .sort()
  .forEach(f => console.log(`  - ${f}`));
