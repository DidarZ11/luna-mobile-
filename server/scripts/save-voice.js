// Сохранить вариант из Voice Design как постоянный голос Луны и включить его в .env.
//   npm run save-voice -- <generated_voice_id>
import 'dotenv/config';
import { readFileSync, writeFileSync } from 'node:fs';

const KEY = process.env.ELEVENLABS_API_KEY;
const generatedId = process.argv[2];
if (!KEY) throw new Error('Нет ELEVENLABS_API_KEY в server/.env');
if (!generatedId) throw new Error('Укажи id варианта: npm run save-voice -- <generated_voice_id>');

const index = JSON.parse(readFileSync(new URL('../voice-samples/design/index.json', import.meta.url), 'utf8'));
const entry = index.find((e) => e.generated_voice_id === generatedId);
if (!entry) throw new Error('Такого id нет в voice-samples/design/index.json');

const r = await fetch('https://api.elevenlabs.io/v1/text-to-voice', {
  method: 'POST',
  headers: { 'xi-api-key': KEY, 'Content-Type': 'application/json' },
  body: JSON.stringify({
    voice_name: 'Луна',
    voice_description: entry.description,
    generated_voice_id: generatedId,
  }),
});
if (!r.ok) throw new Error(`ElevenLabs ${r.status}: ${await r.text()}`);
const { voice_id } = await r.json();

const envFile = new URL('../.env', import.meta.url);
let env = readFileSync(envFile, 'utf8');
const set = (key, value) => {
  const line = `${key}=${value}`;
  env = new RegExp(`^${key}=.*$`, 'm').test(env) ? env.replace(new RegExp(`^${key}=.*$`, 'm'), line) : `${env.trimEnd()}\n${line}\n`;
};
set('ELEVENLABS_VOICE_ID', voice_id);
set('LUNA_TTS', 'elevenlabs');
writeFileSync(envFile, env);
console.log(`✓ Голос «Луна» сохранён: ${voice_id}. В .env включён LUNA_TTS=elevenlabs — перезапусти сервер.`);
