import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'chat_store.dart';
import 'chats_drawer.dart';
import 'models.dart';
import 'moon_orb.dart';
import 'reply_format.dart';
import 'settings.dart';
import 'settings_screen.dart';
import 'voice.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.settings,
    required this.store,
    required this.api,
    required this.voice,
  });

  final AppSettings settings;
  final ChatStore store;
  final LunaApi api;
  final VoiceIO voice;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final controller = TextEditingController();
  final scroll = ScrollController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  /// Открытый чат; null — новый, ещё не сохранённый (сохранится после первого ответа).
  String? chatId;
  List<ChatMessage> messages = [];

  bool isLoading = false;
  LunaState state = LunaState.idle;

  StreamSubscription<String>? _reply;
  Completer<void>? _replyDone;
  // Озвучка текущего ответа
  int _speechOffset = 0; // сколько символов speechText уже отдано голосу
  bool _speechFirst = true;
  bool _spokeShort = false;
  bool _speechMuted = false; // ■ или нажатие на луну — остаток ответа не озвучиваем

  AppSettings get settings => widget.settings;
  ChatStore get store => widget.store;
  VoiceIO get voice => widget.voice;

  @override
  void initState() {
    super.initState();
    final recent = store.chats;
    if (recent.isNotEmpty) {
      chatId = recent.first.id;
      messages = store.messages(chatId!);
    }
    voice.onSpeaking = (speaking) {
      if (!mounted) return;
      setState(() {
        if (speaking) {
          state = LunaState.speaking;
        } else if (state == LunaState.speaking) {
          state = isLoading ? LunaState.thinking : LunaState.idle;
        }
      });
    };
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollDown(jump: true));
  }

  @override
  void dispose() {
    _reply?.cancel();
    voice.onSpeaking = null;
    voice.stopSpeaking();
    voice.stopListening();
    controller.dispose();
    scroll.dispose();
    super.dispose();
  }

  // --- Отправка -------------------------------------------------------------

  Future<void> sendMessage([String? spoken]) async {
    final text = (spoken ?? controller.text).trim();
    if (text.isEmpty || isLoading) return;

    await voice.stopSpeaking();
    // Запоминаем, в какой чат пишем: пока идёт ответ, можно переключиться на другой.
    final id = chatId ??= store.newId();
    final list = messages;
    final history = List<ChatMessage>.of(list);
    final question = ChatMessage.user(text);
    final reply = ChatMessage.assistant('');
    _speechOffset = 0;
    _speechFirst = true;
    _spokeShort = false;
    _speechMuted = false;

    setState(() {
      list
        ..add(question)
        ..add(reply);
      isLoading = true;
      state = LunaState.thinking;
    });
    controller.clear();
    _scrollDown();

    try {
      if (settings.streaming) {
        await _receiveStream(text, history, reply);
      } else {
        final answer = await widget.api.sendMessage(text, history);
        if (mounted) setState(() => reply.text = answer);
      }
      if (reply.text.trim().isEmpty) {
        list.remove(reply); // остановили до первого слова
      } else if (mounted && identical(list, messages)) {
        _feedSpeech(reply.text, isFinal: true);
      }
      await store.save(id, list);
    } on LunaApiException catch (e) {
      if (mounted && identical(list, messages)) {
        _showError(e.message, question: question, reply: reply);
      } else {
        list.remove(reply);
        await store.save(id, list);
      }
    } finally {
      _reply = null;
      _replyDone = null;
      if (mounted) {
        setState(() {
          isLoading = false;
          if (state == LunaState.thinking) state = LunaState.idle;
        });
      }
    }
  }

  Future<void> _receiveStream(
    String text,
    List<ChatMessage> history,
    ChatMessage reply,
  ) {
    final done = _replyDone = Completer<void>();
    _reply = widget.api
        .streamChat(text, history)
        .listen(
          (chunk) {
            if (!mounted) return;
            setState(() => reply.text += chunk);
            _scrollDown();
            // Говорим законченные предложения, не дожидаясь конца ответа.
            _feedSpeech(reply.text, isFinal: false);
          },
          onError: (Object e) {
            if (!done.isCompleted) done.completeError(e);
          },
          onDone: () {
            if (!done.isCompleted) done.complete();
          },
          cancelOnError: true,
        );
    return done.future;
  }

  /// Остановить генерацию ответа (кнопка ■).
  Future<void> _stopReply() async {
    await _reply?.cancel();
    final done = _replyDone;
    if (done != null && !done.isCompleted) done.complete();
  }

  /// Отдать голосу новую часть ответа. Полная озвучка — по предложениям по мере
  /// генерации; короткая — первые 1–2 фразы, как только голосовая часть готова.
  void _feedSpeech(String replyText, {required bool isFinal}) {
    if (!settings.speakReplies || _speechMuted) return;
    if (!settings.fullVoice) {
      if (_spokeShort) return;
      final parts = splitReply(replyText);
      if (!isFinal && !parts.voiceComplete) return;
      _spokeShort = true;
      final say = speakable(parts.voice);
      if (say.isNotEmpty) unawaited(voice.speak(say));
      return;
    }
    final next = nextSpeechChunks(
      speechText(replyText),
      _speechOffset,
      isFinal: isFinal,
      first: _speechFirst,
    );
    if (next == null) return;
    final (chunks, offset) = next;
    _speechOffset = offset;
    _speechFirst = false;
    for (final chunk in chunks) {
      unawaited(voice.speak(chunk));
    }
  }

  void _muteSpeech() {
    _speechMuted = true;
    voice.stopSpeaking();
  }

  void _showError(
    String message, {
    required ChatMessage question,
    required ChatMessage reply,
  }) {
    final error = ChatMessage.error(message);
    setState(() {
      final i = messages.indexOf(reply);
      if (reply.text.isEmpty && i >= 0) {
        messages[i] = error;
      } else {
        messages.add(error);
      }
    });
    _scrollDown();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          action: SnackBarAction(
            label: 'Повторить',
            onPressed: () {
              setState(() {
                messages
                  ..remove(error)
                  ..remove(question);
                if (reply.text.isEmpty) messages.remove(reply);
              });
              sendMessage(question.text);
            },
          ),
        ),
      );
  }

  // --- Голос ----------------------------------------------------------------

  Future<void> _toggleListening() async {
    if (state == LunaState.listening) {
      await voice.stopListening();
      return;
    }
    if (isLoading) return;
    await voice.stopSpeaking();
    final ok = await voice.listen(
      onWords: (words, isFinal) {
        if (!mounted) return;
        controller.text = words;
        if (isFinal && words.trim().isNotEmpty) {
          sendMessage(words);
        }
      },
      onDone: () {
        if (mounted && state == LunaState.listening) {
          setState(() => state = LunaState.idle);
        }
      },
    );
    if (!mounted) return;
    if (ok) {
      setState(() => state = LunaState.listening);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Распознавание речи недоступно: нужен доступ к микрофону '
            'и сервис Google Speech на телефоне',
          ),
        ),
      );
    }
  }

  /// Клик по луне: говорит — замолчать, иначе — слушать.
  void _onOrbTap() {
    if (state == LunaState.speaking) {
      _muteSpeech();
    } else {
      _toggleListening();
    }
  }

  // --- Чаты -----------------------------------------------------------------

  Future<void> _leaveCurrentChat() async {
    await _stopReply();
    await voice.stopSpeaking();
    if (state == LunaState.listening) await voice.stopListening();
    controller.clear();
  }

  Future<void> _newChat() async {
    _closeDrawer();
    if (chatId == null && messages.isEmpty) return; // и так новый
    await _leaveCurrentChat();
    setState(() {
      chatId = null;
      messages = [];
      state = LunaState.idle;
    });
  }

  Future<void> _openChat(String id) async {
    _closeDrawer();
    if (id == chatId) return;
    await _leaveCurrentChat();
    setState(() {
      chatId = id;
      messages = store.messages(id);
      state = LunaState.idle;
    });
    _scrollDown(jump: true);
  }

  Future<void> _renameChat(String id, String title) async {
    await store.rename(id, title);
    if (mounted) setState(() {});
  }

  Future<void> _deleteChat(String id) async {
    if (id == chatId) {
      await _leaveCurrentChat();
      chatId = null;
      messages = [];
    }
    await store.delete(id);
    if (mounted) setState(() {});
  }

  void _closeDrawer() {
    final scaffold = _scaffoldKey.currentState;
    if (scaffold?.isDrawerOpen ?? false) scaffold!.closeDrawer();
  }

  // --- Прочее ---------------------------------------------------------------

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(settings: settings, api: widget.api),
      ),
    );
    if (mounted) setState(() {});
  }

  void _scrollDown({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scroll.hasClients) return;
      final end = scroll.position.maxScrollExtent;
      if (jump) {
        scroll.jumpTo(end);
      } else {
        scroll.animateTo(
          end,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String get _statusText => switch (state) {
    LunaState.idle => messages.isEmpty ? 'Нажми на луну и говори' : '',
    LunaState.listening => 'Слушаю…',
    LunaState.thinking => 'Думаю…',
    LunaState.speaking => 'Нажми на луну, чтобы замолчала',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chatTitle = chatId == null ? null : store.find(chatId!)?.title;
    return Scaffold(
      key: _scaffoldKey,
      drawer: ChatsDrawer(
        chats: store.chats,
        currentId: chatId,
        onNew: _newChat,
        onOpen: _openChat,
        onRename: _renameChat,
        onDelete: _deleteChat,
      ),
      appBar: AppBar(
        title: Text(
          chatTitle ?? 'Луна',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Новый чат',
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: messages.isEmpty ? null : _newChat,
          ),
          IconButton(
            tooltip: 'Настройки',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            MoonOrb(state: state, size: 104, onTap: _onOrbTap),
            SizedBox(
              height: 20,
              child: Text(
                _statusText,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                itemCount: messages.length,
                itemBuilder: (context, i) => MessageBubble(
                  message: messages[i],
                  pending: isLoading && i == messages.length - 1,
                ),
              ),
            ),
            _InputBar(
              controller: controller,
              isLoading: isLoading,
              listening: state == LunaState.listening,
              onSend: sendMessage,
              onStop: () {
                _muteSpeech();
                _stopReply();
              },
              onMic: _toggleListening,
            ),
          ],
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.isLoading,
    required this.listening,
    required this.onSend,
    required this.onStop,
    required this.onMic,
  });

  final TextEditingController controller;
  final bool isLoading;
  final bool listening;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final VoidCallback onMic;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Row(
        children: [
          IconButton(
            tooltip: listening ? 'Хватит слушать' : 'Сказать голосом',
            onPressed: isLoading ? null : onMic,
            icon: Icon(listening ? Icons.mic : Icons.mic_none),
            color: listening ? scheme.primary : null,
          ),
          Expanded(
            child: TextField(
              controller: controller,
              enabled: !isLoading,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(
                hintText: 'Напишите сообщение…',
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          isLoading
              ? IconButton.filledTonal(
                  tooltip: 'Остановить',
                  onPressed: onStop,
                  icon: const Icon(Icons.stop),
                )
              : IconButton.filled(
                  tooltip: 'Отправить',
                  onPressed: onSend,
                  icon: const Icon(Icons.send),
                ),
        ],
      ),
    );
  }
}

class MessageBubble extends StatelessWidget {
  const MessageBubble({super.key, required this.message, this.pending = false});

  final ChatMessage message;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isUser = message.isUser;

    final Color bg;
    final Color fg;
    if (message.isError) {
      bg = scheme.errorContainer;
      fg = scheme.onErrorContainer;
    } else if (isUser) {
      bg = scheme.primaryContainer;
      fg = scheme.onPrimaryContainer;
    } else {
      bg = scheme.surfaceContainerHigh;
      fg = scheme.onSurface;
    }

    final Widget content;
    if (!isUser && !message.isError && message.text.isEmpty && pending) {
      content = const SizedBox.square(
        dimension: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else if (isUser || message.isError) {
      content = SelectableText(message.text, style: TextStyle(color: fg));
    } else {
      final parts = splitReply(message.text);
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (parts.voice.isNotEmpty)
            SelectableText(parts.voice, style: TextStyle(color: fg)),
          if (parts.hasScreen) ...[
            Divider(color: fg.withValues(alpha: 0.2), height: 16),
            for (final block in screenBlocks(parts.screen))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: block.isCode
                    ? _CodeBlock(code: block.text, color: fg)
                    : SelectableText.rich(
                        TextSpan(
                          children: [
                            for (final (text, bold) in boldSpans(block.text))
                              TextSpan(
                                text: text,
                                style: bold
                                    ? const TextStyle(fontWeight: FontWeight.w600)
                                    : null,
                              ),
                          ],
                        ),
                        style: TextStyle(color: fg, height: 1.35),
                      ),
              ),
          ],
        ],
      );
    }

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 18),
          ),
        ),
        child: content,
      ),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.code, required this.color});

  final String code;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SelectableText(
          code,
          style: TextStyle(
            color: color,
            fontFamily: 'monospace',
            fontSize: 13,
            height: 1.35,
          ),
        ),
      ),
    );
  }
}
