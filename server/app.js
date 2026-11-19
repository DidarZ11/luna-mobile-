// Бэкенд Луны: хранит ключ Claude API и проксирует чат из Flutter-приложения.
// Схема из лекции: Flutter → этот сервер → Claude API → обратно.
import 'dotenv/config';
import express from 'express';
import Anthropic from '@anthropic-ai/sdk';
import { readFileSync } from 'node:fs';
import { MAX_TTS_TEXT, synthesize, ttsDescription, ttsEngine } from './tts.js';

const PORT = Number(process.env.PORT || 3000);
const MODEL = process.env.LUNA_MODEL || 'claude-opus-5-5';
const EFFORT = process.env.LUNA_EFFORT || 'low'; // голосовой помощник: важнее скорость
const APP_TOKEN = process.env.APP_TOKEN || ''; // пусто — без авторизации (только для локальной разработки)

const MAX_MESSAGE = 4000; // символов в одном сообщении
const MAX_HISTORY = 40; // сообщений контекста
const RATE_LIMIT = Number(process.env.RATE_LIMIT_PER_MIN || 20);

const PERSONA = readFileSync(new URL('./persona.md', import.meta.url), 'utf8');

if (!process.env.ANTHROPIC_API_KEY) {
  console.warn('⚠ ANTHROPIC_API_KEY не задан — положи его в server/.env (см. .env.example)');
}
const ai = new Anthropic();

const app = express();
app.use(express.json({ limit: '200kb' }));

// --- Защита: токен приложения и лимит запросов -------------------------------

function auth(req, res, next) {
  if (!APP_TOKEN) return next();
  if (req.get('authorization') === `Bearer ${APP_TOKEN}`) return next();
  res.status(401).json({ error: 'Неверный токен приложения' });
}

function makeRateLimit(perMinute) {
  const hits = new Map(); // ip → [время запросов за последнюю минуту]
  return (req, res, next) => {
    const now = Date.now();
    const list = (hits.get(req.ip) || []).filter((t) => now - t < 60_000);
    if (list.length >= perMinute) {
      return res.status(429).json({ error: 'Слишком много запросов, подожди минуту' });
    }
    list.push(now);
    hits.set(req.ip, list);
    next();
  };
}
const rateLimit = makeRateLimit(RATE_LIMIT);
const ttsRateLimit = makeRateLimit(RATE_LIMIT * 3); // на один ответ бывает несколько фраз

// --- Проверка входных данных -------------------------------------------------

// Принимает { message, history? } — history: [{ role: 'user'|'assistant', content }].
// Возвращает массив messages для Claude или строку с ошибкой.
export function buildMessages(body) {
  const message = typeof body?.message === 'string' ? body.message.trim() : '';
  if (!message) return 'Пустое сообщение';
  if (message.length > MAX_MESSAGE) return `Сообщение длиннее ${MAX_MESSAGE} символов`;

  const history = Array.isArray(body.history) ? body.history.slice(-MAX_HISTORY) : [];
  const messages = [];
  for (const m of history) {
    if (!m || (m.role !== 'user' && m.role !== 'assistant')) return 'Неверная роль в истории';
    if (typeof m.content !== 'string' || !m.content.trim()) continue;
    messages.push({ role: m.role, content: m.content.slice(0, MAX_MESSAGE * 2) });
  }
  while (messages.length && messages[0].role !== 'user') messages.shift(); // первым должен быть user
  messages.push({ role: 'user', content: message });
  return messages;
}

function requestParams(messages) {
  return {
    model: MODEL,
    max_tokens: 8000,
    system: PERSONA,
    output_config: { effort: EFFORT },
    // Кэш истории: в длинном разговоре повторная часть стоит в 20 раз дешевле.
    // Пока разговор короче минимального порога кэша, ничего не меняется и не стоит дороже.
    cache_control: { type: 'ephemeral' },
    // Если классификатор безопасности откажет, API сам повторит запрос на запасной модели.
    betas: ['server-side-fallback-2026-07-01'],
    fallbacks: 'default',
    messages,
  };
}

function describeError(e) {
  if (e instanceof Anthropic.AuthenticationError) return [500, 'Сервер: неверный ключ Claude API'];
  if (e instanceof Anthropic.RateLimitError) return [503, 'Claude перегружен, попробуй через минуту'];
  if (e instanceof Anthropic.BadRequestError) return [500, 'Claude не принял запрос'];
  if (e instanceof Anthropic.APIConnectionError) return [502, 'Сервер не достучался до Claude'];
  if (e instanceof Anthropic.APIError) return [502, `Ошибка Claude API (${e.status})`];
  return [500, 'Ошибка AI-сервера'];
}

const REFUSAL_TEXT = 'С этим не помогу.';

// Расход на каждый ответ — чтобы видеть реальные токены, а не оценку.
function logUsage(route, final, startedAt, firstTextAt) {
  const u = final.usage || {};
  const first = firstTextAt ? ` · первый текст ${firstTextAt - startedAt} мс` : '';
  console.log(
    `${route}: ${Date.now() - startedAt} мс${first} · токены: вход ${u.input_tokens ?? '?'}` +
      ` + кэш ${u.cache_read_input_tokens ?? 0}/${u.cache_creation_input_tokens ?? 0}, выход ${u.output_tokens ?? '?'}`,
  );
}

// --- Маршруты ----------------------------------------------------------------

app.get('/health', (req, res) => res.json({ ok: true, model: MODEL, tts: ttsDescription() }));

// Голос Луны: POST /tts { text } → audio/mpeg.
app.post('/tts', auth, ttsRateLimit, async (req, res) => {
  const text = typeof req.body?.text === 'string' ? req.body.text.trim() : '';
  if (!text) return res.status(400).json({ error: 'Пустой текст' });
  if (text.length > MAX_TTS_TEXT) return res.status(400).json({ error: `Текст длиннее ${MAX_TTS_TEXT} символов` });
  if (ttsEngine === 'off') return res.status(404).json({ error: 'Голос на сервере выключен' });
  try {
    const startedAt = Date.now();
    const audio = await synthesize(text);
    console.log(`tts: ${Date.now() - startedAt} мс · ${text.length} симв. · ${ttsDescription()}`);
    res.set({ 'Content-Type': 'audio/mpeg', 'Cache-Control': 'no-store' }).send(audio);
  } catch (e) {
    console.error('tts:', e?.message || e);
    res.status(502).json({ error: 'Не получилось озвучить' });
  }
});

// Как в лекции: POST /chat { message } → { reply }. Дополнительно принимает history.
app.post('/chat', auth, rateLimit, async (req, res) => {
  const messages = buildMessages(req.body);
  if (typeof messages === 'string') return res.status(400).json({ error: messages });
  try {
    const startedAt = Date.now();
    const stream = ai.beta.messages.stream(requestParams(messages));
    const final = await stream.finalMessage();
    logUsage('chat', final, startedAt);
    const reply =
      final.stop_reason === 'refusal'
        ? REFUSAL_TEXT
        : final.content.filter((b) => b.type === 'text').map((b) => b.text).join('');
    res.json({ reply });
  } catch (e) {
    const [status, error] = describeError(e);
    console.error('chat:', e?.message || e);
    res.status(status).json({ error });
  }
});

// Потоковый вариант (Server-Sent Events): ответ появляется по мере генерации.
// События: data: {"text": "..."} · data: {"done": true} · data: {"error": "..."}
app.post('/chat/stream', auth, rateLimit, async (req, res) => {
  const messages = buildMessages(req.body);
  if (typeof messages === 'string') return res.status(400).json({ error: messages });

  res.set({
    'Content-Type': 'text/event-stream; charset=utf-8',
    'Cache-Control': 'no-cache',
    Connection: 'keep-alive',
  });
  res.flushHeaders();
  const send = (obj) => res.write(`data: ${JSON.stringify(obj)}\n\n`);

  const stream = ai.beta.messages.stream(requestParams(messages));
  res.on('close', () => {
    if (!res.writableEnded) stream.abort(); // приложение закрыло соединение — не тратим токены
  });

  const startedAt = Date.now();
  let firstTextAt = 0;
  try {
    for await (const event of stream) {
      if (event.type === 'content_block_delta' && event.delta.type === 'text_delta') {
        firstTextAt ||= Date.now();
        send({ text: event.delta.text });
      }
    }
    const final = await stream.finalMessage();
    logUsage('chat/stream', final, startedAt, firstTextAt);
    if (final.stop_reason === 'refusal') send({ text: REFUSAL_TEXT });
    send({ done: true });
  } catch (e) {
    if (stream.aborted) return;
    const [, error] = describeError(e);
    console.error('chat/stream:', e?.message || e);
    send({ error });
  }
  res.end();
});

export function start() {
  return app.listen(PORT, '0.0.0.0', () => {
    console.log(`Луна-сервер: http://localhost:${PORT} · модель ${MODEL}`);
    console.log(`Эмулятор Android: http://10.0.2.2:${PORT} · телефон: http://<IP компьютера>:${PORT}`);
    if (!APP_TOKEN) console.warn('⚠ APP_TOKEN не задан — сервер открыт для всех в сети');
  });
}

export default app;
