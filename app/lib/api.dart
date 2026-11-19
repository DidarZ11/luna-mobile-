import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'settings.dart';

class LunaApiException implements Exception {
  LunaApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// HTTP-клиент нашего сервера. Ключ Claude API здесь не нужен и не хранится.
class LunaApi {
  LunaApi(this.settings, {http.Client Function()? clientFactory})
    : _newClient = clientFactory ?? http.Client.new;

  final AppSettings settings;
  final http.Client Function() _newClient;

  static const maxContext = 40;
  static const _connectTimeout = Duration(seconds: 15);
  static const _replyTimeout = Duration(seconds: 90);

  Uri _uri(String path) => Uri.parse('${settings.serverUrl}$path');

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (settings.token.isNotEmpty) 'Authorization': 'Bearer ${settings.token}',
  };

  /// Тело запроса: новое сообщение + последние реплики, чтобы Луна помнила контекст.
  String _body(String message, List<ChatMessage> history) {
    final context = history
        .where((m) => !m.isError && m.text.trim().isNotEmpty)
        .toList();
    final tail = context.length > maxContext
        ? context.sublist(context.length - maxContext)
        : context;
    return jsonEncode({
      'message': message,
      'history': tail.map((m) => m.toJson()).toList(),
    });
  }

  /// Как в лекции: POST /chat → {"reply": "..."}.
  Future<String> sendMessage(String message, List<ChatMessage> history) async {
    final client = _newClient();
    try {
      final response = await client
          .post(
            _uri('/chat'),
            headers: _headers,
            body: _body(message, history),
          )
          .timeout(_replyTimeout);
      final data = _decode(utf8.decode(response.bodyBytes));
      if (response.statusCode != 200) {
        throw LunaApiException(_errorText(response.statusCode, data));
      }
      final reply = data?['reply'];
      if (reply is! String) {
        throw LunaApiException('Сервер вернул непонятный ответ');
      }
      return reply;
    } on LunaApiException {
      rethrow;
    } catch (e) {
      throw _networkError(e);
    } finally {
      client.close();
    }
  }

  /// Потоковый ответ (POST /chat/stream, Server-Sent Events): куски текста по мере генерации.
  /// Отмена подписки закрывает соединение — сервер перестаёт генерировать.
  Stream<String> streamChat(String message, List<ChatMessage> history) async* {
    final client = _newClient();
    try {
      final request = http.Request('POST', _uri('/chat/stream'))
        ..headers.addAll(_headers)
        ..body = _body(message, history);

      final http.StreamedResponse response;
      try {
        response = await client.send(request).timeout(_connectTimeout);
      } catch (e) {
        throw _networkError(e);
      }
      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString();
        throw LunaApiException(_errorText(response.statusCode, _decode(body)));
      }

      final lines = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      // Сторож: если сервер замолчал на [_replyTimeout], закрываем соединение.
      var timedOut = false;
      Timer? idle;
      void resetIdle() {
        idle?.cancel();
        idle = Timer(_replyTimeout, () {
          timedOut = true;
          client.close();
        });
      }

      // После {"done": true} сервер сам закрывает ответ — дочитываем до конца, а не рвём.
      var done = false;
      resetIdle();
      try {
        await for (final line in lines) {
          resetIdle();
          if (done || !line.startsWith('data:')) continue;
          final data = _decode(line.substring(5).trim());
          if (data == null) continue;
          if (data['error'] is String) throw LunaApiException(data['error']);
          if (data['text'] is String) yield data['text'] as String;
          if (data['done'] == true) done = true;
        }
      } on LunaApiException {
        rethrow;
      } catch (e) {
        throw _networkError(timedOut ? TimeoutException(null) : e);
      } finally {
        idle?.cancel();
      }
      if (timedOut) throw _networkError(TimeoutException(null));
      if (!done) {
        throw LunaApiException('Соединение оборвалось до конца ответа');
      }
    } finally {
      client.close();
    }
  }

  /// Голос Луны, синтезированный на сервере (ElevenLabs или edge): mp3.
  Future<Uint8List> tts(String text) async {
    final client = _newClient();
    try {
      final response = await client
          .post(
            _uri('/tts'),
            headers: _headers,
            body: jsonEncode({'text': text}),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        final data = _decode(utf8.decode(response.bodyBytes));
        throw LunaApiException(_errorText(response.statusCode, data));
      }
      return response.bodyBytes;
    } on LunaApiException {
      rethrow;
    } catch (e) {
      throw _networkError(e);
    } finally {
      client.close();
    }
  }

  /// Проверка связи: модель и голос на сервере.
  Future<String> health() async {
    final client = _newClient();
    try {
      final response = await client
          .get(_uri('/health'))
          .timeout(_connectTimeout);
      final data = _decode(utf8.decode(response.bodyBytes));
      if (response.statusCode != 200 || data?['ok'] != true) {
        throw LunaApiException('Сервер ответил ${response.statusCode}');
      }
      return 'модель ${data!['model'] ?? '?'}, голос ${data['tts'] ?? '?'}';
    } on LunaApiException {
      rethrow;
    } catch (e) {
      throw _networkError(e);
    } finally {
      client.close();
    }
  }

  static Map<String, dynamic>? _decode(String body) {
    try {
      final v = jsonDecode(body);
      return v is Map<String, dynamic> ? v : null;
    } catch (_) {
      return null;
    }
  }

  static String _errorText(int status, Map<String, dynamic>? data) {
    final serverText = data?['error'];
    if (serverText is String && serverText.isNotEmpty) return serverText;
    return switch (status) {
      401 => 'Неверный токен приложения — проверь настройки',
      404 => 'По этому адресу не Луна-сервер',
      429 => 'Слишком много запросов, подожди минуту',
      _ => 'Ошибка сервера ($status)',
    };
  }

  LunaApiException _networkError(Object e) {
    if (e is TimeoutException) {
      return LunaApiException('Сервер не отвечает. Он запущен?');
    }
    return LunaApiException(
      'Нет связи с ${settings.serverUrl}. Проверь адрес в настройках '
      'и что телефон в той же Wi-Fi сети.',
    );
  }
}
