import 'package:flutter/material.dart';

import 'api.dart';
import 'settings.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.settings, required this.api});

  final AppSettings settings;
  final LunaApi api;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final _url = TextEditingController(text: widget.settings.serverUrl);
  late final _token = TextEditingController(text: widget.settings.token);
  late bool _speak = widget.settings.speakReplies;
  late bool _streaming = widget.settings.streaming;
  late bool _serverVoice = widget.settings.serverVoice;
  late bool _fullVoice = widget.settings.fullVoice;
  String? _check;
  bool _checking = false;

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = widget.settings
      ..serverUrl = _url.text
      ..token = _token.text
      ..speakReplies = _speak
      ..streaming = _streaming
      ..serverVoice = _serverVoice
      ..fullVoice = _fullVoice;
    await s.save();
    _url.text = s.serverUrl;
  }

  Future<void> _checkConnection() async {
    setState(() {
      _checking = true;
      _check = null;
    });
    await _save();
    String result;
    try {
      result = '✓ Сервер на связи: ${await widget.api.health()}';
    } on LunaApiException catch (e) {
      result = '✗ ${e.message}';
    }
    if (mounted) {
      setState(() {
        _checking = false;
        _check = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _save();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Настройки')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Адрес сервера',
                helperText:
                    'Эмулятор: http://10.0.2.2:3000\n'
                    'Телефон: http://<IP компьютера в Wi-Fi>:3000',
                helperMaxLines: 2,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _token,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Токен приложения (APP_TOKEN)',
                helperText:
                    'Тот же, что в server/.env. Это не ключ Claude — '
                    'ключ хранится только на сервере.',
                helperMaxLines: 2,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.tonal(
                  onPressed: _checking ? null : _checkConnection,
                  child: const Text('Проверить связь'),
                ),
                const SizedBox(width: 12),
                if (_checking)
                  const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            if (_check != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_check!),
              ),
            const Divider(height: 32),
            SwitchListTile(
              title: const Text('Озвучивать ответы'),
              value: _speak,
              onChanged: (v) => setState(() => _speak = v),
            ),
            SwitchListTile(
              title: const Text('Читать ответ целиком'),
              subtitle: const Text(
                'Кроме кода. Выкл — вслух только первые фразы, остальное на экране',
              ),
              value: _fullVoice,
              onChanged: _speak ? (v) => setState(() => _fullVoice = v) : null,
            ),
            SwitchListTile(
              title: const Text('Голос Луны с сервера'),
              subtitle: const Text(
                'ElevenLabs или edge — как настроено на сервере. '
                'Выкл — системный голос телефона',
              ),
              value: _serverVoice,
              onChanged: _speak
                  ? (v) => setState(() => _serverVoice = v)
                  : null,
            ),
            SwitchListTile(
              title: const Text('Потоковый ответ'),
              subtitle: const Text('Текст появляется по мере генерации'),
              value: _streaming,
              onChanged: (v) => setState(() => _streaming = v),
            ),
          ],
        ),
      ),
    );
  }
}
