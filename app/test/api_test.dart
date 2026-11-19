import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luna_mobile/api.dart';
import 'package:luna_mobile/models.dart';
import 'package:luna_mobile/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppSettings settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await AppSettings.load()
      ..token = 'secret';
  });

  test('sendMessage: POST /chat с токеном, читает reply', () async {
    final api = LunaApi(
      settings,
      clientFactory: () => MockClient((request) async {
        expect(request.url.toString(), 'http://10.0.2.2:3000/chat');
        expect(request.headers['Authorization'], 'Bearer secret');
        final body = jsonDecode(request.body);
        expect(body['message'], 'Привет');
        expect(body['history'], [
          {'role': 'user', 'content': 'раньше'},
        ]);
        return http.Response.bytes(
          utf8.encode('{"reply":"Ну привет."}'),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final history = [ChatMessage.user('раньше'), ChatMessage.error('сбой')];
    expect(await api.sendMessage('Привет', history), 'Ну привет.');
  });

  test('streamChat: ошибка внутри потока превращается в исключение', () async {
    final api = LunaApi(
      settings,
      clientFactory: () => MockClient.streaming(
        (request, body) async => http.StreamedResponse(
          Stream.value(
            utf8.encode(
              'data: {"text":"Нач"}\n\ndata: {"error":"Claude перегружен"}\n\n',
            ),
          ),
          200,
        ),
      ),
    );
    final got = <String>[];
    await expectLater(
      api.streamChat('x', const []).forEach(got.add),
      throwsA(
        isA<LunaApiException>().having(
          (e) => e.message,
          'message',
          'Claude перегружен',
        ),
      ),
    );
    expect(got, ['Нач']);
  });

  test('streamChat: обрыв без done — ошибка', () async {
    final api = LunaApi(
      settings,
      clientFactory: () => MockClient.streaming(
        (request, body) async => http.StreamedResponse(
          Stream.value(utf8.encode('data: {"text":"а"}\n\n')),
          200,
        ),
      ),
    );
    expect(api.streamChat('x', const []).toList(), throwsA(isA<LunaApiException>()));
  });

  test('нет сети — понятное сообщение', () async {
    final api = LunaApi(
      settings,
      clientFactory: () => MockClient((_) async => throw http.ClientException('refused')),
    );
    expect(
      api.sendMessage('x', const []),
      throwsA(
        isA<LunaApiException>().having(
          (e) => e.message,
          'message',
          contains('Нет связи'),
        ),
      ),
    );
  });

  test('история обрезается до последних 40 реплик', () async {
    late List<dynamic> history;
    final api = LunaApi(
      settings,
      clientFactory: () => MockClient((request) async {
        history = jsonDecode(request.body)['history'] as List<dynamic>;
        return http.Response('{"reply":"ok"}', 200);
      }),
    );
    final long = [for (var i = 0; i < 50; i++) ChatMessage.user('m$i')];
    await api.sendMessage('x', long);
    expect(history.length, 40);
    expect(history.first['content'], 'm10');
  });

  test('tts: POST /tts с токеном, возвращает байты mp3', () async {
    final api = LunaApi(
      settings,
      clientFactory: () => MockClient((request) async {
        expect(request.url.path, '/tts');
        expect(request.headers['Authorization'], 'Bearer secret');
        expect(jsonDecode(request.body), {'text': 'Готово.'});
        return http.Response.bytes([1, 2, 3], 200, headers: {'content-type': 'audio/mpeg'});
      }),
    );
    expect(await api.tts('Готово.'), [1, 2, 3]);
  });

  test('tts: ошибка сервера — исключение с его текстом', () async {
    final api = LunaApi(
      settings,
      clientFactory: () => MockClient(
        (_) async => http.Response.bytes(
          utf8.encode('{"error":"Не получилось озвучить"}'),
          502,
        ),
      ),
    );
    expect(
      api.tts('x'),
      throwsA(isA<LunaApiException>().having((e) => e.message, 'm', 'Не получилось озвучить')),
    );
  });

  test('normalizeUrl', () {
    expect(AppSettings.normalizeUrl(' 192.168.1.5:3000/ '), 'http://192.168.1.5:3000');
    expect(AppSettings.normalizeUrl('https://luna.example.com'), 'https://luna.example.com');
  });

  test('timeout → «Сервер не отвечает»', () async {
    final api = LunaApi(
      settings,
      clientFactory: () => MockClient((_) async => throw TimeoutException('t')),
    );
    expect(
      api.sendMessage('x', const []),
      throwsA(isA<LunaApiException>().having((e) => e.message, 'm', contains('не отвечает'))),
    );
  });
}
