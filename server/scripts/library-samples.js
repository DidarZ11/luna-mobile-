// Образцы женских голосов из библиотеки ElevenLabs: npm run library → voice-samples/eleven/*.mp3
// Понравился — впиши его id в .env: ELEVENLABS_VOICE_ID=<id> и LUNA_TTS=elevenlabs.
import 'dotenv/config';
import { mkdirSync, writeFileSync } from 'node:fs';

const KEY = process.env.ELEVENLABS_API_KEY;
if (!KEY) throw new Error('Нет ELEVENLABS_API_KEY в server/.env');
const LIMIT = Number(process.argv[2] || 8);
const PHRASE = 'Ну, допустим. Сделала, вывела на экран. Хотя задача хлопотная.';

const r = await fetch('https://api.elevenlabs.io/v1/voices', { headers: { 'xi-api-key': KEY } });
if (!r.ok) throw new Error(`ElevenLabs ${r.status}: ${await r.text()}`);
const female = (await r.json()).voices.filter((v) => v.labels?.gender === 'female').slice(0, LIMIT);

const dir = new URL('../voice-samples/eleven/', import.meta.url);
mkdirSync(dir, { recursive: true });
for (const v of female) {
  const res = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${v.voice_id}?output_format=mp3_44100_64`, {
    method: 'POST',
    headers: { 'xi-api-key': KEY, 'Content-Type': 'application/json' },
    body: JSON.stringify({ text: PHRASE, model_id: 'eleven_flash_v2_5' }),
  });
  if (!res.ok) {
    console.log(`✗ ${v.name}: ${res.status}`);
    continue;
  }
  const file = `${v.name.replace(/[^\p{L}\p{N}]+/gu, '_')}.mp3`;
  writeFileSync(new URL(file, dir), Buffer.from(await res.arrayBuffer()));
  const about = [v.labels?.age, v.labels?.accent, v.labels?.descriptive || v.labels?.description].filter(Boolean).join(', ');
  console.log(`✓ ${file.padEnd(22)} ELEVENLABS_VOICE_ID=${v.voice_id}  (${about})`);
}
