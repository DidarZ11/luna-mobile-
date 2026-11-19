import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:luna_mobile/chat_store.dart';
import 'package:luna_mobile/chats_drawer.dart';
import 'package:luna_mobile/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('новый чат получает название из первого вопроса', () async {
    final store = await ChatStore.load();
    await store.save('a', [
      ChatMessage.user('  как   настроить flutter на windows и не сойти с ума?'),
      ChatMessage.assistant('Ну, допустим.'),
    ]);
    expect(store.chats.single.title, 'Как настроить flutter на windows и не со…');
    expect(store.messages('a').length, 2);
  });

  test('ошибки и пустые не сохраняются, пустой чат не создаётся', () async {
    final store = await ChatStore.load();
    await store.save('a', [ChatMessage.error('сбой'), ChatMessage.assistant('')]);
    expect(store.chats, isEmpty);
  });

  test('свежий чат — сверху, переименование и удаление', () async {
    final store = await ChatStore.load();
    await store.save('old', [ChatMessage.user('старый')]);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await store.save('new', [ChatMessage.user('новый')]);
    expect(store.chats.map((c) => c.id), ['new', 'old']);

    await Future<void>.delayed(const Duration(milliseconds: 5));
    await store.save('old', [ChatMessage.user('старый'), ChatMessage.assistant('ответ')]);
    expect(store.chats.first.id, 'old');
    expect(store.chats.first.title, 'Старый', reason: 'название не меняется при дописывании');

    await store.rename('old', ' Про Flutter ');
    await store.delete('new');
    final reloaded = await ChatStore.load();
    expect(reloaded.chats.single.title, 'Про Flutter');
    expect(reloaded.messages('new'), isEmpty);
  });

  test('история из первой версии переезжает в первый чат', () async {
    SharedPreferences.setMockInitialValues({
      'history': jsonEncode([
        {'role': 'user', 'content': 'привет'},
        {'role': 'assistant', 'content': 'Ну привет.'},
      ]),
    });
    final store = await ChatStore.load();
    expect(store.chats.single.title, 'Привет');
    expect(store.messages(store.chats.single.id).length, 2);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('history'), isNull);
  });

  test('formatChatTime', () {
    final now = DateTime(2026, 11, 20, 15, 0);
    expect(formatChatTime(DateTime(2026, 11, 20, 9, 5), now), 'сегодня 09:05');
    expect(formatChatTime(DateTime(2026, 11, 19, 23, 59), now), 'вчера 23:59');
    expect(formatChatTime(DateTime(2026, 3, 2), now), '02.03');
    expect(formatChatTime(DateTime(2025, 12, 31), now), '31.12.2025');
  });
}
