// Тесты без обращения к Claude: проверка входных данных, токена и ошибок.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';

process.env.APP_TOKEN = 'secret';
process.env.ANTHROPIC_API_KEY ||= 'sk-ant-test';
const { default: app, buildMessages } = await import('./app.js');

let server, base;
before(async () => {
  server = app.listen(0);
  await new Promise((r) => server.once('listening', r));
  base = `http://127.0.0.1:${server.address().port}`;
});
after(() => server.close());

const post = (path, body, token = 'secret') =>
  fetch(base + path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify(body),
  });

test('buildMessages: сообщение добавляется после истории', () => {
  const m = buildMessages({
    message: ' Как дела? ',
    history: [
      { role: 'user', content: 'Привет' },
      { role: 'assistant', content: 'Ну привет.' },
    ],
  });
  assert.deepEqual(m, [
    { role: 'user', content: 'Привет' },
    { role: 'assistant', content: 'Ну привет.' },
    { role: 'user', content: 'Как дела?' },
  ]);
});

test('buildMessages: история не может начинаться с ответа помощника', () => {
  const m = buildMessages({ message: 'ещё', history: [{ role: 'assistant', content: 'старое' }] });
  assert.deepEqual(m, [{ role: 'user', content: 'ещё' }]);
});

test('buildMessages: отклоняет пустое, длинное и чужие роли', () => {
  assert.equal(typeof buildMessages({ message: '   ' }), 'string');
  assert.equal(typeof buildMessages({ message: 'x'.repeat(4001) }), 'string');
  assert.equal(typeof buildMessages({ message: 'hi', history: [{ role: 'system', content: 'x' }] }), 'string');
});

test('buildMessages: история обрезается до 40 последних', () => {
  const history = Array.from({ length: 60 }, (_, i) => ({
    role: i % 2 ? 'assistant' : 'user',
    content: `m${i}`,
  }));
  const m = buildMessages({ message: 'last', history });
  assert.equal(m.length, 41);
  assert.equal(m[0].content, 'm20');
});

test('без токена — 401', async () => {
  const r = await post('/chat', { message: 'hi' }, 'wrong');
  assert.equal(r.status, 401);
});

test('пустое сообщение — 400 с текстом ошибки', async () => {
  const r = await post('/chat', { message: '' });
  assert.equal(r.status, 400);
  assert.ok((await r.json()).error);
});

test('tts: пустой и слишком длинный текст — 400, без токена — 401', async () => {
  assert.equal((await post('/tts', { text: '' })).status, 400);
  assert.equal((await post('/tts', { text: 'а'.repeat(601) })).status, 400);
  assert.equal((await post('/tts', { text: 'привет' }, 'wrong')).status, 401);
});

test('health отвечает без токена', async () => {
  const r = await fetch(base + '/health');
  assert.equal(r.status, 200);
  assert.equal((await r.json()).ok, true);
});
