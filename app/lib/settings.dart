import 'package:shared_preferences/shared_preferences.dart';

/// Настройки приложения (SharedPreferences). История чатов — в ChatStore.
class AppSettings {
  AppSettings._(this._prefs)
    : serverUrl = _prefs.getString(_kServer) ?? defaultServerUrl,
      token = _prefs.getString(_kToken) ?? '',
      speakReplies = _prefs.getBool(_kSpeak) ?? true,
      streaming = _prefs.getBool(_kStreaming) ?? true,
      serverVoice = _prefs.getBool(_kServerVoice) ?? true,
      fullVoice = _prefs.getBool(_kFullVoice) ?? true;

  /// Адрес компьютера с сервером, как его видит эмулятор Android.
  static const defaultServerUrl = 'http://10.0.2.2:3000';

  static const _kServer = 'server_url';
  static const _kToken = 'app_token';
  static const _kSpeak = 'speak_replies';
  static const _kStreaming = 'streaming';
  static const _kServerVoice = 'server_voice';
  static const _kFullVoice = 'full_voice';

  final SharedPreferences _prefs;

  String serverUrl;

  /// Токен приложения для нашего сервера. Это НЕ ключ Claude API — тот живёт только на сервере.
  String token;
  bool speakReplies;
  bool streaming;

  /// Голос Луны синтезирует сервер (ElevenLabs/edge); false — системный голос телефона.
  bool serverVoice;

  /// Читать вслух весь ответ (кроме кода); false — только первые 1–2 фразы.
  bool fullVoice;

  static Future<AppSettings> load() async =>
      AppSettings._(await SharedPreferences.getInstance());

  Future<void> save() async {
    serverUrl = normalizeUrl(serverUrl);
    await _prefs.setString(_kServer, serverUrl);
    await _prefs.setString(_kToken, token.trim());
    await _prefs.setBool(_kSpeak, speakReplies);
    await _prefs.setBool(_kStreaming, streaming);
    await _prefs.setBool(_kServerVoice, serverVoice);
    await _prefs.setBool(_kFullVoice, fullVoice);
  }

  static String normalizeUrl(String url) {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    if (u.isNotEmpty && !u.contains('://')) u = 'http://$u';
    return u;
  }
}
