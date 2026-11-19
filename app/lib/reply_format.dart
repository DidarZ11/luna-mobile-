/// Ответ Луны: до строки `###` — то, что говорится вслух, после — текст только для экрана.
class ReplyParts {
  const ReplyParts(this.voice, this.screen, {required this.voiceComplete});

  final String voice;
  final String screen;

  /// Голосовая часть дописана (уже встретился `###`) — её можно озвучивать, не дожидаясь конца.
  final bool voiceComplete;

  bool get hasScreen => screen.isNotEmpty;
}

final _separator = RegExp(r'^[ \t]*###[ \t]*$', multiLine: true);

ReplyParts splitReply(String text) {
  final match = _separator.firstMatch(text);
  if (match == null) return ReplyParts(text.trim(), '', voiceComplete: false);
  return ReplyParts(
    text.substring(0, match.start).trim(),
    text.substring(match.end).trim(),
    voiceComplete: true,
  );
}

/// Кусок экранной части ответа: обычный текст или код из блока ```.
class ScreenBlock {
  const ScreenBlock(this.text, {required this.isCode});
  final String text;
  final bool isCode;
}

/// Делит экранную часть на текст и код. Незакрытый ``` (ответ ещё пишется) — код до конца.
List<ScreenBlock> screenBlocks(String screen) {
  final parts = screen.split('```');
  final blocks = <ScreenBlock>[];
  for (var i = 0; i < parts.length; i++) {
    var part = parts[i];
    final isCode = i.isOdd;
    if (isCode) {
      // Первая строка вида ```dart — язык, не код.
      final firstBreak = part.indexOf('\n');
      if (firstBreak >= 0 && !part.substring(0, firstBreak).contains(' ')) {
        part = part.substring(firstBreak + 1);
      }
      part = part.replaceAll(RegExp(r'\s+$'), '');
    } else {
      part = part
          .replaceAllMapped(
            RegExp(r'^#{1,6}\s*(.+)$', multiLine: true),
            (m) => '**${m[1]}**',
          )
          .replaceAll(RegExp(r'^[ \t]*[-*][ \t]+', multiLine: true), '• ')
          .trim();
    }
    if (part.isNotEmpty) blocks.add(ScreenBlock(part, isCode: isCode));
  }
  return blocks;
}

/// `**жирный**` → куски (текст, жирный?). Непарные ** остаются как есть.
List<(String, bool)> boldSpans(String text) {
  final pieces = text.split('**');
  if (pieces.length.isEven) return [(text, false)]; // непарные — не трогаем
  return [
    for (var i = 0; i < pieces.length; i++)
      if (pieces[i].isNotEmpty) (pieces[i], i.isOdd),
  ];
}

// --- Полная озвучка ------------------------------------------------------------

/// Весь ответ для чтения вслух: голосовая часть + текст с экрана, без кода и разметки.
/// Законченные строки получают точку, чтобы заголовок не слипался со следующей фразой.
/// Последняя строка (ещё может дописываться) остаётся как есть.
String speechText(String reply) {
  final parts = splitReply(reply);
  final pieces = <String>[
    if (parts.voice.isNotEmpty) parts.voice,
    for (final b in screenBlocks(parts.screen))
      if (!b.isCode) b.text,
  ];
  final lines = pieces.join('\n').split('\n');
  final out = StringBuffer();
  for (var i = 0; i < lines.length; i++) {
    var line = _cleanForSpeech(lines[i]);
    if (line.isEmpty) continue;
    final isLast = i == lines.length - 1;
    if (!isLast) {
      if (!RegExp(r'[.!?…:;,]$').hasMatch(line)) line += '.';
      line += ' ';
    }
    out.write(line);
  }
  return out.toString();
}

String _cleanForSpeech(String line) => line
    .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m[1]!) // [текст](ссылка)
    .replaceAll(RegExp(r'https?://\S+'), 'ссылка')
    .replaceAll(RegExp(r'[*_`#>•]'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

final _sentenceEnd = RegExp(r'[.!?…]+["»)]*\s+');

/// Следующие куски для озвучки, начиная с позиции [from] в [speech].
/// Пока ответ пишется — только законченные предложения: первый кусок — первое же
/// предложение (чтобы Луна заговорила сразу), дальше — от [minChars] символов.
/// [isFinal] — ответ дописан, отдаём остаток. Возвращает куски и новую позицию.
(List<String>, int)? nextSpeechChunks(
  String speech,
  int from, {
  required bool isFinal,
  required bool first,
  int minChars = 120,
}) {
  if (from >= speech.length) return null;
  final rest = speech.substring(from);
  if (isFinal) {
    final pieces = splitForSpeech(rest);
    return pieces.isEmpty ? null : (pieces, speech.length);
  }
  RegExpMatch? cut;
  for (final m in _sentenceEnd.allMatches(rest)) {
    if (first || m.end >= minChars) {
      cut = m;
      break;
    }
  }
  if (cut == null) return null;
  final pieces = splitForSpeech(rest.substring(0, cut.end));
  return (pieces, from + cut.end);
}

/// Режет текст по предложениям на куски до [max] символов (длинные фразы — по пробелам).
List<String> splitForSpeech(String text, {int max = 400}) {
  final sentences = text
      .split(RegExp(r'(?<=[.!?…]["»)]*)\s+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty);
  final chunks = <String>[];
  var current = '';
  void push(String s) {
    if (current.isEmpty) {
      current = s;
    } else if (current.length + 1 + s.length <= max) {
      current = '$current $s';
    } else {
      chunks.add(current);
      current = s;
    }
  }

  for (final sentence in sentences) {
    if (sentence.length <= max) {
      push(sentence);
      continue;
    }
    for (final word in sentence.split(' ')) {
      push(word);
    }
  }
  if (current.isNotEmpty) chunks.add(current);
  return chunks;
}

/// Текст для синтеза речи: без разметки и не длиннее [maxSentences] предложений.
String speakable(String voice, {int maxSentences = 2}) {
  final clean = voice
      .replaceAll(RegExp(r'[*_`#>]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (clean.isEmpty) return '';
  final sentences = clean
      .split(RegExp(r'(?<=[.!?…])\s+'))
      .where((s) => s.isNotEmpty);
  return sentences.take(maxSentences).join(' ');
}
