// Голос Луны: текст → mp3. Движок выбирается в .env (LUNA_TTS):
//   edge       — Microsoft Edge TTS, бесплатно, без ключа (по умолчанию Vivienne, как у Луны на Windows)
//   elevenlabs — свой голос из ElevenLabs Voice Design (нужны ELEVENLABS_API_KEY и ELEVENLABS_VOICE_ID)
//   off        — сервер не озвучивает, приложение говорит системным голосом телефона
import { MsEdgeTTS, OUTPUT_FORMAT } from 'msedge-tts';

const EDGE_VOICE = process.env.EDGE_VOICE || 'fr-FR-VivienneMultilingualNeural';
const EDGE_RATE = process.env.EDGE_RATE || '+15%';
const EDGE_PITCH = process.env.EDGE_PITCH || '+0Hz';

const ELEVEN_KEY = process.env.ELEVENLABS_API_KEY || '';
const ELEVEN_VOICE = process.env.ELEVENLABS_VOICE_ID || '';
// flash_v2_5 — самая быстрая (замер: ~0.3 с до первого звука, ~0.4 с весь файл на короткую фразу)
// и вдвое дешевле multilingual_v2. eleven_v3 выразительнее, но ~1.5 с.
const ELEVEN_MODEL = process.env.ELEVENLABS_MODEL || 'eleven_flash_v2_5';

export const MAX_TTS_TEXT = 600;

function pickEngine() {
  const wanted = (process.env.LUNA_TTS || 'edge').toLowerCase();
  if (wanted === 'elevenlabs' && !(ELEVEN_KEY && ELEVEN_VOICE)) {
    console.warn('⚠ LUNA_TTS=elevenlabs, но нет ELEVENLABS_API_KEY / ELEVENLABS_VOICE_ID — беру edge');
    return 'edge';
  }
  return ['edge', 'elevenlabs', 'off'].includes(wanted) ? wanted : 'edge';
}

export const ttsEngine = pickEngine();

export function ttsDescription() {
  if (ttsEngine === 'edge') return `edge: ${EDGE_VOICE} ${EDGE_RATE} ${EDGE_PITCH}`;
  if (ttsEngine === 'elevenlabs') return `elevenlabs: ${ELEVEN_VOICE} ${ELEVEN_MODEL}`;
  return 'off';
}

// --- Кэш: короткие фразы («Хм.», «Готово.») повторяются — второй раз мгновенно ---------
const cache = new Map();
const CACHE_SIZE = 300;

export async function synthesize(text) {
  const key = `${ttsDescription()}|${text}`;
  const hit = cache.get(key);
  if (hit) {
    cache.delete(key);
    cache.set(key, hit); // свежий — в конец
    return hit;
  }
  let audio;
  if (ttsEngine === 'elevenlabs') {
    try {
      audio = await elevenSynth(text);
    } catch (e) {
      // Кончились кредиты или сеть — Луна не немеет, а говорит бесплатным голосом. Не кэшируем.
      console.warn('⚠ ElevenLabs недоступен, говорю через edge:', e?.message || e);
      return edgeSynth(text, EDGE_VOICE, EDGE_RATE, EDGE_PITCH);
    }
  } else {
    audio = await edgeSynth(text, EDGE_VOICE, EDGE_RATE, EDGE_PITCH);
  }
  cache.set(key, audio);
  if (cache.size > CACHE_SIZE) cache.delete(cache.keys().next().value);
  return audio;
}

// --- Edge TTS -----------------------------------------------------------------

const escapeXml = (s) =>
  s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&apos;');

const edgeClients = new Map(); // голос → Promise<MsEdgeTTS>, соединение переиспользуется

function edgeClient(voice) {
  if (!edgeClients.has(voice)) {
    const ready = (async () => {
      const c = new MsEdgeTTS({ connectionTimeoutMs: 8000, synthesisTimeoutMs: 20000 });
      await c.setMetadata(voice, OUTPUT_FORMAT.AUDIO_24KHZ_48KBITRATE_MONO_MP3);
      return c;
    })();
    edgeClients.set(voice, ready);
    ready.catch(() => edgeClients.delete(voice));
  }
  return edgeClients.get(voice);
}

export async function edgeSynth(text, voice, rate, pitch) {
  for (let attempt = 0; ; attempt++) {
    try {
      const client = await edgeClient(voice);
      const { audioStream } = client.toStream(escapeXml(text), { rate, pitch });
      const chunks = [];
      for await (const chunk of audioStream) chunks.push(chunk);
      const audio = Buffer.concat(chunks);
      if (!audio.length) throw new Error('Edge TTS вернул пустой звук');
      return audio;
    } catch (e) {
      // Соединение могло протухнуть — пересоздаём и пробуем ещё раз.
      const stale = edgeClients.get(voice);
      edgeClients.delete(voice);
      stale?.then((c) => c.close()).catch(() => {});
      if (attempt >= 1) throw e;
    }
  }
}

export async function closeEdge() {
  const clients = [...edgeClients.values()];
  edgeClients.clear();
  await Promise.allSettled(clients.map((p) => p.then((c) => c.close())));
}

// --- ElevenLabs ---------------------------------------------------------------

async function elevenSynth(text) {
  const url = `https://api.elevenlabs.io/v1/text-to-speech/${encodeURIComponent(ELEVEN_VOICE)}?output_format=mp3_44100_64`;
  const r = await fetch(url, {
    method: 'POST',
    headers: { 'xi-api-key': ELEVEN_KEY, 'Content-Type': 'application/json', Accept: 'audio/mpeg' },
    body: JSON.stringify({ text, model_id: ELEVEN_MODEL }),
    signal: AbortSignal.timeout(30_000),
  });
  if (!r.ok) throw new Error(`ElevenLabs ${r.status}: ${(await r.text()).slice(0, 300)}`);
  return Buffer.from(await r.arrayBuffer());
}
