// BridgeRead — Generate "You got a [item]!" audio via ElevenLabs (same voice as lessons)

const fs   = require('fs');
const path = require('path');

// Read API key from .env
const envPath = path.join(__dirname, '..', '.env');
const env     = fs.readFileSync(envPath, 'utf8');
const apiKey  = env.match(/ELEVENLABS_API_KEY=(.+)/)?.[1]?.trim();

if (!apiKey) {
  console.error('❌  ELEVENLABS_API_KEY not found in .env');
  process.exit(1);
}

const VOICE_ID   = 'kbFeB8Ko2KgpldlKCYQA'; // same cloned voice used in lessons
const OUTPUT_DIR = path.join(__dirname, '..', 'assets', 'audio', 'items');

if (!fs.existsSync(OUTPUT_DIR)) fs.mkdirSync(OUTPUT_DIR, { recursive: true });

const items = [
  { id: 'glass',               text: "You got Glasses!" },
  { id: 'hat_birthday',        text: "You got a Birthday Hat!" },
  { id: 'hat_birthday_cute',   text: "You got a Cute Party Hat!" },
  { id: 'hat_birthday_golden', text: "You got a Golden Crown!" },
  { id: 'Lollipop',            text: "You got a Lollipop!" },
  { id: 'alarm',               text: "You got an Alarm Clock!" },
  { id: 'car',                 text: "You got a Race Car!" },
  { id: 'dinosaur',            text: "You got a Dinosaur!" },
  { id: 'fly',                 text: "You got a Dragonfly!" },
  { id: 'frame',               text: "You got a Picture Frame!" },
  { id: 'globe',               text: "You got a Globe!" },
  { id: 'robot',               text: "You got a Robot!" },
  { id: 'rocket',              text: "You got a Rocket!" },
  { id: 'shark',               text: "You got a Shark!" },
  { id: 'soccer',              text: "You got a Soccer Ball!" },
  { id: 'teddyw',              text: "You got a Teddy Bear!" },
  { id: 'telescope',           text: "You got a Telescope!" },
  { id: 'Ultraman',            text: "You got Ultraman!" },
  { id: 'dragon',              text: "You got a Dragon!" },
  { id: 'gun',                 text: "You got a Water Gun!" },
  { id: 'monkey',              text: "You got a Monkey!" },
  { id: 'nezha',               text: "You got Nezha!" },
  { id: 'pig',                 text: "You got a Piggy!" },
  { id: 'rainbow',             text: "You got a Rainbow!" },
  { id: 'trophy',              text: "You got a Trophy!" },
  { id: 'vase',                text: "You got a Vase!" },
];

async function generate(item) {
  const outPath = path.join(OUTPUT_DIR, `${item.id}.mp3`);
  if (fs.existsSync(outPath)) {
    console.log(`⏭️   Skip (exists): ${item.id}.mp3`);
    return true;
  }
  console.log(`🎙️   Generating: "${item.text}"`);

  try {
    const res = await fetch(
      `https://api.elevenlabs.io/v1/text-to-speech/${VOICE_ID}`,
      {
        method: 'POST',
        headers: {
          'xi-api-key': apiKey,
          'Content-Type': 'application/json',
          'Accept': 'audio/mpeg',
        },
        body: JSON.stringify({
          text: item.text,
          model_id: 'eleven_turbo_v2',
          voice_settings: { stability: 0.5, similarity_boost: 0.8 },
        }),
      }
    );

    if (!res.ok) {
      console.error(`❌  HTTP ${res.status}: ${await res.text()}`);
      return false;
    }

    const buffer = await res.arrayBuffer();
    fs.writeFileSync(outPath, Buffer.from(buffer));
    console.log(`✅  Done: ${item.id}.mp3 (${buffer.byteLength} bytes)`);
    return true;

  } catch (e) {
    console.error(`❌  Error: ${e.message}`);
    return false;
  }
}

async function main() {
  console.log(`\n🎁  BridgeRead — Item audio generator (ElevenLabs)`);
  console.log(`    Voice: ${VOICE_ID}`);
  console.log(`    Output: ${OUTPUT_DIR}\n`);

  let ok = 0, fail = 0;
  for (const item of items) {
    if (await generate(item)) ok++; else fail++;
    await new Promise(r => setTimeout(r, 300));
  }

  console.log(`\n🎉  Done! Success: ${ok}  Failed: ${fail}`);
  console.log(`    Files saved to: ${OUTPUT_DIR}`);
}

main().catch(console.error);
