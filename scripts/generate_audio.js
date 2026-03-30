// BridgeRead - 音频生成脚本
// 中文: 火山引擎TTS (potato克隆声音) | 英文: ElevenLabs (含时间戳)

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

// 从.env读取凭证
const envPath = path.join(__dirname, '..', '.env');
const env = fs.readFileSync(envPath, 'utf8');
const elevenLabsKey = env.match(/ELEVENLABS_API_KEY=(.+)/)?.[1]?.trim();
const ttsApiKey    = env.match(/TTS_API_KEY=(.+)/)?.[1]?.trim();
const ttsAppId     = env.match(/TTS_APP_ID=(.+)/)?.[1]?.trim();
const ttsVoiceId   = 'S_MnneA1cX1'; // 复刻cat clone voice

if (!elevenLabsKey) { console.error('找不到ELEVENLABS_API_KEY'); process.exit(1); }
if (!ttsApiKey || !ttsAppId) { console.error('找不到火山引擎TTS配置'); process.exit(1); }

const VOICE_ID_EN = 'kbFeB8Ko2KgpldlKCYQA'; // ElevenLabs cloned voice
const OUTPUT_DIR  = path.join(__dirname, '..', 'assets', 'audio');
const TS_DIR      = path.join(OUTPUT_DIR, 'timestamps');

if (!fs.existsSync(OUTPUT_DIR)) fs.mkdirSync(OUTPUT_DIR, { recursive: true });
if (!fs.existsSync(TS_DIR)) fs.mkdirSync(TS_DIR, { recursive: true });

const audioScripts = [
  // 开场
  { id: 'biscuit_intro', text: 'Hello Hello, my dear friend！I am Amy! 我们又见面啦！今天我们要讲Biscuit的故事。Are you ready？让我们开始吧，let\'s go！', lang: 'cn' },
  // 第1页
  { id: 'biscuit_p1_cn', text: '呀~ 你们看到了吗？这就是今天的小主角，一只叫Biscuit的小狗！你知道biscuit是什么意思吗？哈哈，没错，就是饼干的意思，你看他个子小小的，毛是黄色的，是不是很像黄油饼干呀！', lang: 'cn' },
  { id: 'biscuit_p1_en', text: 'This is Biscuit. Biscuit is small. Biscuit is yellow.', lang: 'en', keywords: ['small', 'yellow'] },
  // 第2页
  { id: 'biscuit_p2_cn', text: '好像要到睡觉时间啦！小女孩叫Biscuit去睡觉。这个bed就是小床，Time for bed就是该上床睡觉啦！但是你说Biscuit想不想睡啊？对了，他可不想睡，他大声的说 —— Woof woof！他想玩，他想玩！', lang: 'cn' },
  { id: 'biscuit_p2_en', text: 'Time for bed, Biscuit! Woof, woof! Biscuit wants to play.', lang: 'en', keywords: ['bed', 'play'] },
  // 第3页
  { id: 'biscuit_p3_cn', text: 'Biscuit还是不想睡觉，他想干嘛呀，哈哈，Biscuit说我要吃零食！snack就是小零食小点心。然后他又说我要喝水！这里的drink就是喝水。Biscuit怎么一会儿要这个，一会儿要那个呀，哈哈！', lang: 'cn' },
  { id: 'biscuit_p3_en', text: 'Biscuit wants a snack. Biscuit wants a drink.', lang: 'en', keywords: ['snack', 'drink'] },
  // 第4页
  { id: 'biscuit_p4_cn', text: '那我们看看吃完喝完以后biscuit要睡觉了吗？Biscuit又说了什么？——他说要听故事！story就是故事。小女孩只好又给他讲起了故事，是不是就像我们现在这样啊？', lang: 'cn' },
  { id: 'biscuit_p4_en', text: 'Biscuit wants to hear a story.', lang: 'en', keywords: ['story'] },
  // 第5页
  { id: 'biscuit_p5_cn', text: '故事听完了，Biscuit看了看，又说到——我想要我的小毯子！blanket就是小毯子。结果他还要什么呀？他说——我要我的玩偶！doll就是布娃娃玩偶！你睡觉的时候是不是总有一个小玩偶陪着你呀', lang: 'cn' },
  { id: 'biscuit_p5_en', text: 'Biscuit wants his blanket. Biscuit wants his doll.', lang: 'en', keywords: ['blanket', 'doll'] },
  // 第6页
  { id: 'biscuit_p6_cn', text: '你看现在毯子有了，小玩偶有了，Biscuit又想到了什么呀？他说——我要抱抱！我要亲亲！hug是抱抱，kiss是亲亲。你们睡前有没有亲亲抱抱你家的小宠物，小狗狗或者小猫咪，然后跟他说晚安呀？', lang: 'cn' },
  { id: 'biscuit_p6_en', text: 'Biscuit wants a hug. Biscuit wants a kiss.', lang: 'en', keywords: ['hug', 'kiss'] },
  // 第7页
  { id: 'biscuit_p7_cn', text: '还没结束呢，Biscuit又说——我要开灯！light就是灯。light on就是把灯开着。biscuit是不是怕黑呀？你怕不怕黑呀？其实老师也总是在睡觉的时候开着小夜灯呢', lang: 'cn' },
  { id: 'biscuit_p7_en', text: 'Biscuit wants a light on.', lang: 'en', keywords: ['light'] },
  // 第8页
  { id: 'biscuit_p8_cn', text: '小女孩把灯开着，然后把Biscuit好好地盖进被子里。tucked in就是把被子掖好。其实在你睡觉的时候，爸爸妈妈也会来悄悄的给你掖被子哦？', lang: 'cn' },
  { id: 'biscuit_p8_en', text: 'Biscuit wants to be tucked in.', lang: 'en', keywords: [] },
  // 第9页
  { id: 'biscuit_p9_cn', text: '盖好了被子，好像还不够！Biscuit说——再亲一次！再抱一次！哈哈哈! one more kiss，one more 哈格。one more就是再来一个！你猜猜看，现在biscuit是不是真的要睡觉啦？', lang: 'cn' },
  { id: 'biscuit_p9_en', text: 'Biscuit wants one more kiss. Biscuit wants one more hug.', lang: 'en', keywords: [] },
  // 第10页
  { id: 'biscuit_p10_cn', text: '……Biscuit说了最后一声Woof！终于，他蜷起身体准备睡觉啦！curl up就是蜷成一团。你们睡觉是不是也喜欢蜷成小球球？', lang: 'cn' },
  { id: 'biscuit_p10_en', text: 'Woof! Biscuit wants to curl up.', lang: 'en', keywords: [] },
  // 第11页
  { id: 'biscuit_p11_cn', text: '小饼干狗Biscuit终于睡着了！sleepy就是困困的瞌睡的。Good night Biscuit——晚安小饼干！', lang: 'cn' },
  { id: 'biscuit_p11_en', text: 'Sleepy puppy. Good night, Biscuit.', lang: 'en', keywords: ['sleepy'] },
  // 完成
  { id: 'biscuit_done', text: '今天我们认识了Biscuit！你还记得他睡前要了哪些东西吗？是不是也有你喜欢的呢？那我们明天再见哦！看看小Biscuit明天又有什么新鲜事吧！', lang: 'cn' },
  // 录音页示范句
  { id: 'featured_time_for_bed', text: 'Time for bed, Biscuit!', lang: 'en', keywords: [] },
  // Quiz bubble pop SFX — short punchy English
  { id: 'bubble_pop', text: 'Pop!', lang: 'en', keywords: [] },

  // ═══════════════════════════════════════════════════════════════════════════
  // Book 2: Biscuit and the Baby
  // ═══════════════════════════════════════════════════════════════════════════

  // 开场
  { id: 'biscuit_baby_intro', text: 'Hello Hello！我们又见面啦！今天Amy要给你们讲一个新故事——Biscuit and the Baby！Biscuit要认识一个小宝宝啦，你猜猜会发生什么呢？Let\'s find out！', lang: 'cn' },
  // 第1页
  { id: 'biscuit_baby_p1_cn', text: '哎呀，Biscuit看到了什么呀？Woof woof！他好兴奋！see就是看到的意思。你看他的小尾巴是不是都摇起来了？他到底看到了什么呢，我们翻过去看看！', lang: 'cn' },
  { id: 'biscuit_baby_p1_en', text: 'Woof, woof! What does Biscuit see?', lang: 'en', keywords: ['see'] },
  // 第2页
  { id: 'biscuit_baby_p2_cn', text: '原来Biscuit看到了一个baby！baby就是小宝宝！你们家里有没有小宝宝呀？Biscuit看到小宝宝好开心呢！', lang: 'cn' },
  { id: 'biscuit_baby_p2_en', text: 'Woof, woof! Biscuit sees the baby.', lang: 'en', keywords: ['baby'] },
  // 第3页
  { id: 'biscuit_baby_p3_cn', text: 'Biscuit好想去认识小宝宝呀！meet就是见面、认识的意思。但是呢，嘘——小声点！小宝宝正在sleeping，sleeping就是睡觉！小宝宝在睡觉呢，我们要安静哦！', lang: 'cn' },
  { id: 'biscuit_baby_p3_en', text: 'Biscuit wants to meet the baby! Woof, woof! Sshhh! Quiet, Biscuit. The baby is sleeping.', lang: 'en', keywords: ['meet', 'sleeping'] },
  // 第4页
  { id: 'biscuit_baby_p4_cn', text: '现在还不能去见小宝宝哦！但是Biscuit看到了什么？他看到了baby的rattle！rattle就是小摇铃，就是那种摇一摇会响的小玩具！你小时候是不是也有一个小摇铃呀？', lang: 'cn' },
  { id: 'biscuit_baby_p4_en', text: 'It\'s not time to meet the baby yet. Woof, woof! Biscuit sees the baby\'s rattle.', lang: 'en', keywords: ['rattle'] },
  // 第5页
  { id: 'biscuit_baby_p5_cn', text: 'Biscuit又看到了小宝宝的bunny！bunny就是小兔子，一个毛茸茸的小兔子玩偶！Biscuit好想去认识小宝宝呀，他一直在说Woof woof！', lang: 'cn' },
  { id: 'biscuit_baby_p5_en', text: 'Woof, woof! Biscuit sees the baby\'s bunny. Woof, woof! Biscuit wants to meet the baby!', lang: 'en', keywords: ['bunny'] },
  // 第6页
  { id: 'biscuit_baby_p6_cn', text: '嘘！quiet！quiet就是安静的意思。小宝宝还在睡觉呢！哎呀，Biscuit你在干什么？你拿了小宝宝的blanket！blanket就是小毯子！silly puppy，你真是个小傻瓜！那不是你的毯子呀！', lang: 'cn' },
  { id: 'biscuit_baby_p6_en', text: 'Sshhh! Quiet, Biscuit. The baby is still sleeping. It\'s not time to meet the baby yet. Woof, woof! Silly puppy! That\'s not your blanket.', lang: 'en', keywords: ['quiet', 'blanket'] },
  // 第7页
  { id: 'biscuit_baby_p7_cn', text: '哈哈，Biscuit又拿了什么？他拿了小宝宝的booties！booties就是小婴儿穿的那种小鞋子小袜子。funny puppy，funny就是搞笑的意思。Biscuit你真是太搞笑啦，你那么想见小宝宝，但是现在还不行哦！', lang: 'cn' },
  { id: 'biscuit_baby_p7_en', text: 'Oh no, Biscuit. Those booties are for the baby. Woof, woof! Funny puppy! You want to meet the baby. But it\'s not time to meet the baby yet.', lang: 'en', keywords: ['booties', 'funny'] },
  // 第8页
  { id: 'biscuit_baby_p8_cn', text: 'Woof！Biscuit叫了一大声！哎呀，发生什么事了？', lang: 'cn' },
  { id: 'biscuit_baby_p8_en', text: 'Woof!', lang: 'en', keywords: [] },
  // 第9页
  { id: 'biscuit_baby_p9_cn', text: '哎呀不好了！小宝宝被吵醒了！Waa Waa Waa！小宝宝在哭呢！Biscuit也在一直叫Woof Woof Woof！你说他们两个谁的声音更大呀？哈哈！', lang: 'cn' },
  { id: 'biscuit_baby_p9_en', text: 'Waa! Waa! Waa! Waa! Woof! Woof! Woof! Woof!', lang: 'en', keywords: [] },
  // 第10页
  { id: 'biscuit_baby_p10_cn', text: 'Biscuit吓了一跳想跑掉！come back就是回来的意思！小女孩说，回来呀Biscuit，这只是小宝宝呀，不用害怕！', lang: 'cn' },
  { id: 'biscuit_baby_p10_en', text: 'Biscuit, come back. It\'s only the baby! Woof, woof!', lang: 'en', keywords: ['come back'] },
  // 第11页
  { id: 'biscuit_baby_p11_cn', text: '终于到时间啦！sweet puppy，sweet就是甜甜的可爱的。现在可以认识小宝宝了！最棒的是，小宝宝也认识了一个new friend，一个新朋友！你说这个新朋友是谁呀？对了，就是Biscuit！', lang: 'cn' },
  { id: 'biscuit_baby_p11_en', text: 'Here, sweet puppy. Now it\'s time to meet the baby. Woof, woof! Best of all, it\'s time for the baby to meet a new friend!', lang: 'en', keywords: ['sweet', 'friend'] },
  // 第12页（结尾）
  { id: 'biscuit_baby_p12_cn', text: 'Woof！Biscuit和小宝宝成为好朋友啦！', lang: 'cn' },
  // 完成
  { id: 'biscuit_baby_done', text: '今天Biscuit认识了一个新朋友——小宝宝！你还记得Biscuit看到了小宝宝的哪些东西吗？有rattle小摇铃，有bunny小兔子，还有blanket小毯子和booties小鞋子！下次我们再来听Biscuit的新故事吧！', lang: 'cn' },
  // 录音页示范句
  { id: 'biscuit_baby_featured', text: 'Biscuit wants to meet the baby!', lang: 'en', keywords: [] },
];

// 火山引擎TTS（中文）
async function generateCN(script, outputPath) {
  const reqId = crypto.randomUUID();
  const response = await fetch('https://openspeech.bytedance.com/api/v1/tts', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer;${ttsApiKey}`,
    },
    body: JSON.stringify({
      app: { appid: ttsAppId, token: ttsApiKey, cluster: 'volcano_icl' },
      user: { uid: 'bridgeread' },
      audio: {
        voice_type: ttsVoiceId,
        encoding: 'mp3',
        speed_ratio: 1.0,
        volume_ratio: 1.0,
        pitch_ratio: 1.0,
      },
      request: {
        reqid: reqId,
        text: script.text,
        text_type: 'plain',
        operation: 'query',
      },
    }),
  });

  const json = await response.json();
  if (!json.data) throw new Error(`火山引擎返回错误: ${JSON.stringify(json)}`);
  fs.writeFileSync(outputPath, Buffer.from(json.data, 'base64'));
}

// ElevenLabs TTS（英文，含时间戳）
async function generateEN(script, outputPath) {
  const useTimestamps = script.keywords && script.keywords.length > 0;
  const endpoint = useTimestamps
    ? `https://api.elevenlabs.io/v1/text-to-speech/${VOICE_ID_EN}/with-timestamps`
    : `https://api.elevenlabs.io/v1/text-to-speech/${VOICE_ID_EN}`;

  const response = await fetch(endpoint, {
    method: 'POST',
    headers: { 'xi-api-key': elevenLabsKey, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      text: script.text,
      model_id: 'eleven_multilingual_v2',
      voice_settings: { stability: 0.6, similarity_boost: 0.75, style: 0.2, use_speaker_boost: false, speed: 1.0 },
    }),
  });

  if (!response.ok) throw new Error(`ElevenLabs错误: ${response.status} ${await response.text()}`);

  if (useTimestamps) {
    const data = await response.json();
    fs.writeFileSync(outputPath, Buffer.from(data.audio_base64, 'base64'));

    // 提取关键词时间戳
    const alignment = data.alignment;
    if (alignment?.characters) {
      let words = [], currentWord = '', wordStart = null, wordEnd = null;
      for (let i = 0; i < alignment.characters.length; i++) {
        const char = alignment.characters[i];
        const startTime = alignment.character_start_times_seconds[i];
        const endTime = alignment.character_end_times_seconds[i];
        if (' .,!?'.includes(char)) {
          if (currentWord) { words.push({ word: currentWord.toLowerCase(), start: wordStart, end: wordEnd }); currentWord = ''; wordStart = null; }
        } else {
          if (!wordStart) wordStart = startTime;
          currentWord += char;
          wordEnd = endTime;
        }
      }
      if (currentWord) words.push({ word: currentWord.toLowerCase(), start: wordStart, end: wordEnd });

      const timings = {};
      for (const keyword of script.keywords) {
        const match = words.find(w => w.word === keyword.toLowerCase());
        if (match) {
          timings[keyword] = Math.round(match.start * 1000);
          console.log(`  📍 "${keyword}" → ${match.start.toFixed(2)}s (${timings[keyword]}ms)`);
        }
      }

      // 自动更新JSON
      if (Object.keys(timings).length > 0) {
        const jsonPath = path.join(__dirname, '..', 'assets', 'lessons', 'biscuit_book1_day1.json');
        const lesson = JSON.parse(fs.readFileSync(jsonPath, 'utf8'));
        for (const page of lesson.pages) {
          if (page.audioEN === script.id && page.highlights) {
            page.highlights.forEach(h => {
              if (timings[h.word] !== undefined) {
                h.positionMs = timings[h.word];
                console.log(`  ✅ JSON更新: ${h.word} = ${h.positionMs}ms`);
              }
            });
          }
        }
        fs.writeFileSync(jsonPath, JSON.stringify(lesson, null, 2));
      }
    }
  } else {
    const buffer = await response.arrayBuffer();
    fs.writeFileSync(outputPath, Buffer.from(buffer));
  }
}

async function generateAudio(script) {
  const outputPath = path.join(OUTPUT_DIR, `${script.id}.mp3`);
  if (fs.existsSync(outputPath)) { console.log(`⏭️  跳过: ${script.id}.mp3`); return; }
  console.log(`🎙️  生成: ${script.id} (${script.lang === 'cn' ? '火山引擎' : 'ElevenLabs'}) ...`);
  try {
    if (script.lang === 'cn') await generateCN(script, outputPath);
    else await generateEN(script, outputPath);
    console.log(`✅ 完成: ${script.id}.mp3`);
    await new Promise(r => setTimeout(r, 600));
  } catch (err) {
    console.error(`❌ 错误 ${script.id}:`, err.message);
  }
}

async function main() {
  console.log('\n🎵 BridgeRead音频生成器');
  console.log('中文: 火山引擎 | 英文: ElevenLabs (含时间戳)\n');
  for (const script of audioScripts) await generateAudio(script);
  console.log('\n🎉 全部完成！');
}

main().catch(console.error);
