// Придумать голос по описанию (ElevenLabs Voice Design).
//   npm run design                       — описание Луны по умолчанию
//   npm run design -- "описание голоса"  — своё описание (лучше по-английски)
//   npm run design -- "..." eleven_multilingual_ttv_v2
// Каждый запуск — 3 варианта в voice-samples/design/. Понравился — npm run save-voice -- <id>
import 'dotenv/config';
import { mkdirSync, writeFileSync, readFileSync, existsSync } from 'node:fs';

const KEY = process.env.ELEVENLABS_API_KEY;
if (!KEY) throw new Error('Нет ELEVENLABS_API_KEY в server/.env');

export const LUNA_DESCRIPTION =
  'Young woman in her early twenties speaking Russian. Calm, dry, deadpan delivery with lazy irony, ' +
  'unhurried and a little bored, minimal emotion, slightly low and soft voice, clear diction, ' +
  'close microphone, clean studio quality.';

const SAMPLE_TEXT =
  'Ну, допустим. Сделала, вывела на экран. Задача, конечно, хлопотная, но интересная: ' +
  'ошибка пряталась в самом неожиданном месте. Если что-то ещё сломается — зови, посмотрю. ' +
  'Только не всё сразу, ладно?';

const description = process.argv[2] || LUNA_DESCRIPTION;
const model = process.argv[3] || 'eleven_ttv_v3';

const r = await fetch('https://api.elevenlabs.io/v1/text-to-voice/design?output_format=mp3_44100_128', {
  method: 'POST',
  headers: { 'xi-api-key': KEY, 'Content-Type': 'application/json' },
  body: JSON.stringify({ voice_description: description, text: SAMPLE_TEXT, model_id: model }),
});
if (!r.ok) {
  const body = await r.text();
  throw new Error(
    body.includes('voice_generation')
      ? 'У ключа ElevenLabs нет права Voice Generation — включи его в настройках ключа на elevenlabs.io'
      : `ElevenLabs ${r.status}: ${body}`,
  );
}
const { previews } = await r.json();

const dir = new URL('../voice-samples/design/', import.meta.url);
mkdirSync(dir, { recursive: true });
const indexFile = new URL('index.json', dir);
const index = existsSync(indexFile) ? JSON.parse(readFileSync(indexFile, 'utf8')) : [];

const stamp = new Date().toISOString().slice(5, 16).replace(/[-T:]/g, '');
previews.forEach((p, i) => {
  const name = `${stamp}-${model.replace('eleven_', '')}-${i + 1}.mp3`;
  writeFileSync(new URL(name, dir), Buffer.from(p.audio_base_64, 'base64'));
  index.push({ file: name, generated_voice_id: p.generated_voice_id, model, description });
  console.log(`✓ ${name}  id=${p.generated_voice_id}`);
});
writeFileSync(indexFile, JSON.stringify(index, null, 2));
console.log('\nПонравился вариант → npm run save-voice -- <id>');
