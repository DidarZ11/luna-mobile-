import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luna_mobile/api.dart';
import 'package:luna_mobile/chat_store.dart';
import 'package:luna_mobile/main.dart';
import 'package:luna_mobile/settings.dart';
import 'package:luna_mobile/voice.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeVoice implements VoiceIO {
  final spoken = <String>[];
  void Function(String, bool)? lastOnWords;

  @override
  set onSpeaking(ValueChanged<bool>? callback) {}

  @override
  Future<bool> listen({
    required void Function(String words, bool isFinal) onWords,
    required VoidCallback onDone,
  }) async {
    lastOnWords = onWords;
    return true;
  }

  @override
  Future<void> stopListening() async {}

  @override
  Future<void> speak(String text) async => spoken.add(text);

  @override
  Future<void> stopSpeaking() async {}
}

http.StreamedResponse sse(List<Map<String, Object>> events, {int status = 200}) {
  final body = events.map((e) => 'data: ${jsonEncode(e)}\n\n').join();
  return http.StreamedResponse(
    Stream.value(utf8.encode(body)),
    status,
    headers: {'content-type': 'text/event-stream; charset=utf-8'},
  );
}

Future<(ChatStore, FakeVoice)> pumpApp(
  WidgetTester tester,
  MockClientStreamHandler handler, {
  bool fullVoice = true,
}) async {
  SharedPreferences.setMockInitialValues({});
  final settings = await AppSettings.load()..fullVoice = fullVoice;
  final store = await ChatStore.load();
  final voice = FakeVoice();
  final api = LunaApi(settings, clientFactory: () => MockClient.streaming(handler));
  await tester.pumpWidget(
    LunaApp(settings: settings, store: store, api: api, voice: voice),
  );
  await tester.pump();
  return (store, voice);
}

Future<void> ask(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.tap(find.byIcon(Icons.send));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('короткая озвучка: вслух только голосовая часть', (tester) async {
    final (_, voice) = await pumpApp(
      tester,
      (request, body) async => sse([
        {'text': 'Сделала. '},
        {'text': 'Вывела на экран.\n###\n'},
        {'text': 'Длинные подробности.'},
        {'done': true},
      ]),
      fullVoice: false,
    );
    await ask(tester, 'Расскажи');
    expect(voice.spoken, ['Сделала. Вывела на экран.']);
  });

  testWidgets('полная озвучка: весь ответ по кускам, код не читается', (tester) async {
    final (_, voice) = await pumpApp(
      tester,
      (request, body) async => sse([
        {'text': 'Готово. '},
        {'text': 'Вот код.\n###\n## Пример\n'},
        {'text': '```dart\nprint(1);\n```\n'},
        {'text': 'Запусти и смотри.'},
        {'done': true},
      ]),
    );
    await ask(tester, 'Покажи код');
    expect(voice.spoken, ['Готово.', 'Вот код. Пример. Запусти и смотри.']);
    expect(voice.spoken.join(' '), isNot(contains('print')));
  });

  testWidgets('вопрос → потоковый ответ в чате и в истории', (tester) async {
    late Map<String, dynamic> sent;
    final (store, voice) = await pumpApp(tester, (request, body) async {
      sent = jsonDecode(await body.bytesToString()) as Map<String, dynamic>;
      expect(request.url.path, '/chat/stream');
      return sse([
        {'text': 'Сделала. '},
        {'text': 'Вывела на экран.\n###\n'},
        {'text': 'print(1)'},
        {'done': true},
      ]);
    });

    await ask(tester, 'Помоги с Flutter');

    expect(sent['message'], 'Помоги с Flutter');
    expect(find.text('Помоги с Flutter'), findsNWidgets(2)); // сообщение + название чата
    expect(find.text('Сделала. Вывела на экран.'), findsOneWidget);
    expect(find.text('print(1)'), findsOneWidget);
    expect(voice.spoken, ['Сделала.', 'Вывела на экран. print(1)']);
    expect(store.chats.single.title, 'Помоги с Flutter');
    expect(store.messages(store.chats.single.id).length, 2);
    expect(find.byIcon(Icons.send), findsOneWidget); // загрузка закончилась
  });

  testWidgets('история уходит на сервер как контекст', (tester) async {
    final requests = <Map<String, dynamic>>[];
    await pumpApp(tester, (request, body) async {
      requests.add(jsonDecode(await body.bytesToString()) as Map<String, dynamic>);
      return sse([
        {'text': 'Ответ ${requests.length}.'},
        {'done': true},
      ]);
    });

    for (final q in ['Первый', 'Второй']) {
      await tester.enterText(find.byType(TextField), q);
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    expect(requests[1]['history'], [
      {'role': 'user', 'content': 'Первый'},
      {'role': 'assistant', 'content': 'Ответ 1.'},
    ]);
  });

  testWidgets('ошибка сервера показывается в чате и не попадает в историю', (
    tester,
  ) async {
    final (store, _) = await pumpApp(
      tester,
      (request, body) async => http.StreamedResponse(
        Stream.value(utf8.encode('{"error":"Неверный токен приложения"}')),
        401,
      ),
    );

    await tester.enterText(find.byType(TextField), 'Привет');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Неверный токен приложения'), findsWidgets);
    expect(find.text('Повторить'), findsOneWidget);
    expect(store.chats, isEmpty);
  });

  testWidgets('новый чат и переключение между чатами через меню', (tester) async {
    final requests = <Map<String, dynamic>>[];
    final (store, _) = await pumpApp(tester, (request, body) async {
      requests.add(jsonDecode(await body.bytesToString()) as Map<String, dynamic>);
      return sse([
        {'text': 'Ответ ${requests.length}.'},
        {'done': true},
      ]);
    });

    await ask(tester, 'Про котов');
    await tester.tap(find.byTooltip('Новый чат'));
    await tester.pump();
    expect(find.text('Ответ 1.'), findsNothing);

    await ask(tester, 'Про собак');
    expect(requests[1]['history'], isEmpty, reason: 'новый чат — без старого контекста');
    expect(store.chats.map((c) => c.title), ['Про собак', 'Про котов']);

    // Открыть меню и вернуться в первый чат
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Про котов').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Ответ 1.'), findsOneWidget);
    expect(find.text('Ответ 2.'), findsNothing);

    await ask(tester, 'Ещё про котов');
    expect(requests[2]['history'], [
      {'role': 'user', 'content': 'Про котов'},
      {'role': 'assistant', 'content': 'Ответ 1.'},
    ]);
  });

  testWidgets('финальная фраза из микрофона отправляется сама', (tester) async {
    final (_, voice) = await pumpApp(
      tester,
      (request, body) async => sse([
        {'text': 'Слышу.'},
        {'done': true},
      ]),
    );

    await tester.tap(find.byIcon(Icons.mic_none));
    await tester.pump();
    voice.lastOnWords!('который час', false);
    await tester.pump();
    expect(find.text('который час'), findsOneWidget); // частичный текст в поле
    voice.lastOnWords!('который час', true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Слышу.'), findsOneWidget);
  });
}
