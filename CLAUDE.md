# BridgeRead - 儿童英语绘本阅读 PWA

## 项目概述
Flutter Web PWA 儿童英语学习应用。每天学一本 Biscuit 系列绘本，包含讲解、消消乐、自然拼读、录音、听力五个模块。周末复习。20本书为一个系列，每套必须是5的倍数。

## 技术栈
- **前端**: Flutter Web (Dart), 部署为 PWA
- **后端**: Node.js + Express + sql.js (SQLite in JS)
- **部署**: GitHub → GitHub Actions build → Gitee deploy 分支 → 阿里云中国服务器
- **域名**: mybridgeread.com, ICP备案: 闽ICP备2026011901号
- **服务器**: 120.79.16.89 (阿里云中国站, Ubuntu 24.04, admin用户)

## 关键路径
```
前端代码: lib/screens/*.dart, lib/services/*.dart, lib/utils/*.dart
后端代码: server/routes/*.dart, server/db.js, server/index.js
测试: test/*.dart (Flutter), server/tests/*.test.js (Jest)
部署配置: .github/workflows/deploy.yml
静态资源: web/index.html, web/cache-sw.js, web/web-audio-engine.js
```

## 部署流程
```
开发者 push → GitHub production 分支
  ↓ GitHub Actions 自动:
  1. flutter build web
  2. cp cache-sw.js → flutter_service_worker.js
  3. 生成 version.json (时间戳版本号)
  4. git archive server/ → push 到 Gitee production (orphan, 只有 server/)
  5. build/web → push 到 Gitee deploy (增量)
  6. 也部署到 GitHub Pages
  ↓ 服务器 cron (每小时) 或手动:
  bash ~/auto-deploy.sh
```

### 手动部署后端
```bash
cd /opt/bridgeread-server && git fetch origin production && git reset --hard origin/production && cd server && npm install --omit=dev && pm2 restart bridgeread-api
```

### 手动部署前端
```bash
bash ~/auto-deploy.sh
```

## ⚠️ 关键注意事项

### 数据库安全
- **绝对不能** 让 git 覆盖 `server/data/bridgeread.db`
- 已加入 `.gitignore` 和服务器 `.git/info/exclude`
- 每日凌晨3点自动备份 (cron)
- 2026-04-18 因 git reset --hard 丢失过全部用户数据

### Gitee 仓库大小限制 1GB
- production 分支只推 server/ 目录 (orphan, ~5MB)
- deploy 分支推 build/web (增量, ~240MB)
- 音频/图片在 git history 中已清理过 (filter-repo)
- 不要再往 Gitee 推完整源码

### iOS Safari 音频
- 使用 Web Audio API (web-audio-engine.js), 不用 audioplayers 的 HTML5 Audio
- AudioContext 需要一次用户手势解锁, 之后所有播放不受限
- Story/Quiz/Phonics 用 GameAudioPlayer, SFX 用 GameSfxPlayer
- 听力/Recap 仍用原生 audioplayers (它们没有 autoplay 问题)
- 异常中断检测: onended 检查播放进度 <85% 则自动恢复 (最多3次)
- 残缺缓存检测: buffer.duration <2s 则 bypass cache 重新下载

## 数据库表
```
users         - 用户信息、星星、锁定状态、profile
daily_progress - 每日模块完成记录 (recap/reader/quiz/listen)
recordings    - 录音文件
sms_codes     - 短信验证码 (已停用)
study_room    - 装饰/扭蛋/配件
weekly_groups - 排行榜分组
weekly_group_members - 排行榜成员
```

## API 端点
```
公开:
  POST /api/auth/register    - 注册 (phone + password + childName, 无需验证码)
  POST /api/auth/login       - 登录
  POST /api/report           - 加载错误报告

需认证 (JWT):
  GET/POST /api/progress     - 进度同步
  POST /api/progress/batch   - 批量同步
  POST /api/progress/setup   - 设置 book_start_date
  POST /api/progress/spend-stars - 花费星星 (盲盒)
  GET/PUT /api/profile       - 用户资料
  GET/PUT /api/studyroom     - 书房数据
  GET /api/ranking           - 排行榜
  POST /api/recordings/upload - 录音上传
  POST /api/speech-eval      - 语音评测
```

## 学习周期逻辑
```
工作日: recap → story → quiz → phonics → recording → listen (4个追踪模块)
周末: quiz(消消乐) + listen (全周书复习, 周六周日内容一样)
新用户周末注册: 当作工作日, 直接学第一本书
20本读完后: 剩余工作日 + 周末 → 复习最后5本 (消消乐 + 听力)
书本分配: bookForWeekdayCount() 按工作日递增, 跳过周末
MODULES = ['recap', 'reader', 'quiz', 'listen', 'phonics', 'recording']
REQUIRED_MODULES = ['recap', 'reader', 'quiz', 'listen'] (算欠债)
```

## Service Worker 策略
```
cache-sw.js:
  音频/图片/字体 → Cache-First (永久缓存, 不会更新)
  HTML/JS/CSS → Network-First (5秒超时 → fallback cache)
  残缺音频检测 → content-length <10KB 自动重新下载

version.json:
  每次 deploy 生成新时间戳
  用户打开 APP 直接 fetch 检查
  版本不同 → 注销所有 SW + 清代码缓存 → reload
  每分钟最多 reload 一次 (防无限循环)
```

## 音频预加载
```
主页加载 → 预加载 Story 音频
Recap 播放 → 预加载全天所有任务音频 (Story + Quiz + Phonics + SFX)
消消乐 → 预加载 Phonics 音频
AudioPreloader: 后台 fetch 触发 SW 缓存, 每批3个并行
```

## 盲盒 (Gacha)
```
花费: 30 星/次, 无每日限制
流程: await 服务器确认 → 成功才扣 UI → 失败显示错误
星星来源: 学习模块完成时服务器加星
星星唯一源: 服务器 total_stars, 本地是缓存
```

## 响应式布局
```
R.init(context) → R.s(px) 缩放, R.isMobile 判断
iPad (1024px): scale ≈ 1.0
iPhone (375px): scale ≈ 0.37
LoginScreen: 手机全宽, iPad 1/3宽
ProfileScreen: 手机单列, iPad 双列
RankingScreen: 手机领奖台缩小70%
```

## 测试
```
flutter test  → 164 tests (week_service, progress, gacha, quiz_bubble, registration, bedtime)
cd server && npm test → 81 tests (auth, progress, ranking, spend-stars)
总计 245 tests
```

## 常用命令
```bash
# 本地开发
flutter build web --release
flutter test
flutter analyze lib/

# 后端测试
cd server && npm test

# 推送到 GitHub (Actions 自动部署)
git push origin production

# 推送到 Gitee (手动, 需要 token)
git push --force https://oauth2:TOKEN@gitee.com/Yejiaomin_e351/bridge-read.git production

# 时间旅行 (浏览器控制台)
timeTravel(5)   # 跳到5天后
timeTravel(0)   # 恢复

# 查看用户数据 (服务器)
cd /opt/bridgeread-server/server && node -e "
const initSqlJs = require('sql.js');
const fs = require('fs');
initSqlJs().then(SQL => {
  const db = new SQL.Database(fs.readFileSync('data/bridgeread.db'));
  const r = db.exec('SELECT id,phone,child_name,total_stars FROM users');
  r[0].values.forEach(v => console.log(v));
});
"

# 查看错误报告
ls /opt/bridgeread-server/server/data/reports/
cat /opt/bridgeread-server/server/data/reports/$(ls -t /opt/bridgeread-server/server/data/reports/ | head -1)
```

## 已知限制
- PWA 在 iOS Safari 有音频 autoplay 限制 (Web Audio API 已缓解)
- 微信内置浏览器不完全支持 Flutter Web
- 从美国无法直连中国服务器 (防火墙), 必须通过 Gitee 中转
- 用户在 Apple 工作, 不能发 App Store, PWA 是唯一分发路径
