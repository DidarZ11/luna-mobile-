import 'package:flutter_test/flutter_test.dart';
import 'package:luna_mobile/reply_format.dart';

void main() {
  group('splitReply', () {
    test('без ### — всё голосом', () {
      final p = splitReply('Готово.');
      expect(p.voice, 'Готово.');
      expect(p.hasScreen, isFalse);
      expect(p.voiceComplete, isFalse);
    });

    test('### делит на голос и экран', () {
      final p = splitReply('Вывела на экран.\n###\n```dart\nprint(1);\n```');
      expect(p.voice, 'Вывела на экран.');
      expect(p.screen, '```dart\nprint(1);\n```');
      expect(p.voiceComplete, isTrue);
    });

    test('### внутри строки не считается разделителем', () {
      expect(splitReply('Заголовок ### тут').hasScreen, isFalse);
    });
  });

  group('screenBlocks', () {
    test('текст и код из ``` разделяются, язык срезается', () {
      final b = screenBlocks('Вот:\n```dart\nprint(1);\n```\nГотово.');
      expect(b.map((x) => (x.text, x.isCode)), [
        ('Вот:', false),
        ('print(1);', true),
        ('Готово.', false),
      ]);
    });

    test('заголовки → жирный, дефисы → точки', () {
      final b = screenBlocks('## Сказка\n- раз\n- два');
      expect(b.single.text, '**Сказка**\n• раз\n• два');
    });

    test('незакрытый блок кода (ответ ещё пишется) — код', () {
      final b = screenBlocks('```\nvoid main');
      expect(b.single.isCode, isTrue);
      expect(b.single.text, 'void main');
    });
  });

  test('boldSpans', () {
    expect(boldSpans('**Сказка** подлиннее'), [('Сказка', true), (' подлиннее', false)]);
    expect(boldSpans('звёзды ** без пары'), [('звёзды ** без пары', false)]);
  });

  group('полная озвучка', () {
    test('speechText: голос + экран, без кода и разметки, заголовок с точкой', () {
      const reply =
          'Вывела на экран.\n###\n**Сказка**\nЖила-была травница.\n'
          '```dart\nprint(1);\n```\nПодробнее: [тут](https://x.ru) и https://y.ru';
      expect(
        speechText(reply),
        'Вывела на экран. Сказка. Жила-была травница. Подробнее: тут и ссылка',
      );
    });

    test('speechText: дописывающаяся строка не получает точку', () {
      expect(speechText('Жила-была трав'), 'Жила-была трав');
    });

    void expectChunks((List<String>, int)? r, List<String> chunks, int offset) {
      expect(r, isNotNull);
      expect(r!.$1, chunks);
      expect(r.$2, offset);
    }

    test('первый кусок — первое же предложение', () {
      final r = nextSpeechChunks('Ну. Сделала всё как ', 0, isFinal: false, first: true);
      expectChunks(r, ['Ну.'], 4);
    });

    test('дальше ждём minChars, незаконченное не трогаем', () {
      const s = 'Раз. Два. Три недоска';
      expect(nextSpeechChunks(s, 4, isFinal: false, first: false, minChars: 50), isNull);
      expectChunks(
        nextSpeechChunks(s, 4, isFinal: false, first: false, minChars: 3),
        ['Два.'],
        10,
      );
    });

    test('в конце отдаём остаток', () {
      const s = 'Раз. Два. Три';
      expectChunks(nextSpeechChunks(s, 5, isFinal: true, first: false), ['Два. Три'], s.length);
      expect(nextSpeechChunks(s, s.length, isFinal: true, first: false), isNull);
    });

    test('splitForSpeech: куски не длиннее max, длинная фраза режется по словам', () {
      final chunks = splitForSpeech('${'слово ' * 30}конец. Ещё.', max: 50);
      expect(chunks.every((c) => c.length <= 50), isTrue);
      expect(chunks.join(' '), '${'слово ' * 30}конец. Ещё.');
    });
  });

  group('speakable', () {
    test('не больше двух предложений', () {
      expect(speakable('Раз. Два! Три? Четыре.'), 'Раз. Два!');
    });

    test('убирает разметку', () {
      expect(speakable('**Жирно** и `код`.'), 'Жирно и код.');
    });

    test('числа с точкой не режут фразу', () {
      expect(speakable('Версия 3.5 вышла. Обнови. Потом.'), 'Версия 3.5 вышла. Обнови.');
    });
  });
}
