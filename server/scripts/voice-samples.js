// Образцы голосов: npm run voices → voice-samples/*.mp3. Послушай и впиши понравившийся в .env.
import { mkdirSync, writeFileSync } from 'node:fs';
import { closeEdge, edgeSynth } from '../tts.js';

const PHRASE = 'Ну, допустим. Сделала, вывела на экран. Хотя задача хлопотная.';

// [файл, голос, скорость, высота]
const VARIANTS = [
  ['01-vivienne', 'fr-FR-VivienneMultilingualNeural', '+15%', '+0Hz'],
  ['02-vivienne-lower', 'fr-FR-VivienneMultilingualNeural', '+10%', '-2st'],
  ['03-vivienne-higher', 'fr-FR-VivienneMultilingualNeural', '+15%', '+2st'],
  ['04-ava', 'en-US-AvaMultilingualNeural', '+10%', '+0Hz'],
  ['05-emma', 'en-US-EmmaMultilingualNeural', '+10%', '+0Hz'],
  ['06-svetlana', 'ru-RU-SvetlanaNeural', '+10%', '+0Hz'],
];

const dir = new URL('../voice-samples/', import.meta.url);
mkdirSync(dir, { recursive: true });
for (const [name, voice, rate, pitch] of VARIANTS) {
  try {
    const audio = await edgeSynth(PHRASE, voice, rate, pitch);
    writeFileSync(new URL(`${name}.mp3`, dir), audio);
    console.log(`✓ ${name}.mp3  EDGE_VOICE=${voice} EDGE_RATE=${rate} EDGE_PITCH=${pitch}`);
  } catch (e) {
    console.log(`✗ ${name}: ${e?.message || e}`);
  }
}
await closeEdge();
