import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Голос: распознавание речи и синтез. Интерфейс — чтобы в тестах подставлять заглушку.
abstract class VoiceIO {
  /// Начать слушать. [onWords] получает распознанный текст (частичный и финальный),
  /// [onDone] — когда микрофон выключился. false — распознавание недоступно.
  Future<bool> listen({
    required void Function(String words, bool isFinal) onWords,
    required VoidCallback onDone,
  });
  Future<void> stopListening();

  /// Поставить фразу в очередь: фразы звучат по порядку, одна за другой.
  Future<void> speak(String text);

  /// Замолчать и очистить очередь.
  Future<void> stopSpeaking();

  /// true — началась речь, false — очередь доиграла или речь прервана.
  set onSpeaking(ValueChanged<bool>? callback);
}

class _Utterance {
  _Utterance(this.text, this.audio);
  final String text;

  /// mp3 с сервера (качается сразу при постановке в очередь); null — системный голос.
  final Future<Uint8List?>? audio;
}

/// Микрофон — распознавание Android. Голос — mp3 с сервера (ElevenLabs/edge),
/// а если сервер не смог или голос с сервера выключен — системный синтез телефона.
class DeviceVoice implements VoiceIO {
  DeviceVoice({this.fetchVoice, this.useServerVoice}) {
    _player.onPlayerComplete.listen((_) {
      final done = _playDone;
      if (done != null && !done.isCompleted) done.complete();
    });
  }

  final Future<Uint8List> Function(String text)? fetchVoice;
  final bool Function()? useServerVoice;

  final _stt = SpeechToText();
  final _tts = FlutterTts();
  final _player = AudioPlayer();
  bool _sttReady = false;
  bool _ttsReady = false;
  VoidCallback? _onListenDone;
  ValueChanged<bool>? _onSpeaking;

  final _queue = <_Utterance>[];
  int _speakId = 0; // растёт при каждой остановке — старая очередь замолкает
  int _drainingId = -1; // какая очередь сейчас играет
  bool _playing = false;
  Completer<void>? _playDone;
  Completer<void> _stopSignal = Completer<void>();

  @override
  set onSpeaking(ValueChanged<bool>? callback) => _onSpeaking = callback;

  void _setPlaying(bool playing) {
    if (_playing == playing) return;
    _playing = playing;
    _onSpeaking?.call(playing);
  }

  // --- Микрофон ---------------------------------------------------------------

  Future<bool> _initStt() async {
    if (_sttReady) return true;
    try {
      _sttReady = await _stt.initialize(
        onStatus: (status) {
          if (status == SpeechToText.doneStatus ||
              status == SpeechToText.notListeningStatus) {
            _onListenDone?.call();
          }
        },
        onError: (_) => _onListenDone?.call(),
      );
    } catch (_) {
      _sttReady = false;
    }
    return _sttReady;
  }

  @override
  Future<bool> listen({
    required void Function(String words, bool isFinal) onWords,
    required VoidCallback onDone,
  }) async {
    if (!await _initStt()) return false;
    _onListenDone = onDone;
    await _stt.listen(
      onResult: (r) => onWords(r.recognizedWords, r.finalResult),
      listenOptions: SpeechListenOptions(
        localeId: 'ru_RU',
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.dictation,
        pauseFor: const Duration(seconds: 3),
        listenFor: const Duration(seconds: 60),
      ),
    );
    return true;
  }

  @override
  Future<void> stopListening() async {
    if (_sttReady) await _stt.stop();
  }

  // --- Речь -------------------------------------------------------------------

  bool get _serverVoiceOn =>
      fetchVoice != null && (useServerVoice?.call() ?? false);

  Future<Uint8List?> _fetch(String text) async {
    try {
      return await fetchVoice!(text);
    } catch (_) {
      return null; // скажем системным голосом
    }
  }

  @override
  Future<void> speak(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    _queue.add(_Utterance(t, _serverVoiceOn ? _fetch(t) : null));
    if (_drainingId != _speakId) {
      _drainingId = _speakId;
      unawaited(_drain(_speakId));
    }
  }

  Future<void> _drain(int id) async {
    final stop = _stopSignal.future;
    try {
      while (id == _speakId && _queue.isNotEmpty) {
        final u = _queue.removeAt(0);
        final audio = await u.audio;
        if (id != _speakId) return;
        _setPlaying(true);
        if (audio != null) {
          final done = _playDone = Completer<void>();
          await _player.play(BytesSource(audio, mimeType: 'audio/mpeg'));
          await Future.any([done.future, stop]);
        } else {
          await _initTts();
          await Future.any([_tts.speak(u.text), stop]);
        }
      }
    } catch (_) {
      // плеер или синтез упали — эта очередь замолкает, следующая начнётся заново
    } finally {
      if (_drainingId == id) _drainingId = -1;
      if (id == _speakId) _setPlaying(false);
    }
  }

  Future<void> _initTts() async {
    if (_ttsReady) return;
    await _tts.setLanguage('ru-RU');
    await _tts.setSpeechRate(0.55);
    await _tts.awaitSpeakCompletion(true);
    _ttsReady = true;
  }

  @override
  Future<void> stopSpeaking() async {
    _speakId++;
    _queue.clear();
    if (!_stopSignal.isCompleted) _stopSignal.complete();
    _stopSignal = Completer<void>();
    _setPlaying(false);
    await _player.stop();
    if (_ttsReady) await _tts.stop();
  }
}
