import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Строка в списке чатов.
class ChatSummary {
  ChatSummary({required this.id, required this.title, required this.updatedAt});

  final String id;
  String title;
  DateTime updatedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
  };

  factory ChatSummary.fromJson(Map<String, dynamic> json) => ChatSummary(
    id: json['id'] as String,
    title: json['title'] as String? ?? 'Чат',
    updatedAt: DateTime.fromMillisecondsSinceEpoch(
      json['updatedAt'] as int? ?? 0,
    ),
  );
}

/// Все чаты на телефоне: список (id, название, время) + сообщения каждого чата отдельно.
class ChatStore {
  ChatStore._(this._prefs) {
    _chats = _readIndex();
  }

  static const maxMessagesPerChat = 100;
  static const _kIndex = 'chats_index';
  static const _kMessagesPrefix = 'chat_messages_';
  static const _kLegacyHistory = 'history'; // единая история из первой версии

  final SharedPreferences _prefs;
  late List<ChatSummary> _chats;

  static Future<ChatStore> load() async {
    final store = ChatStore._(await SharedPreferences.getInstance());
    await store._migrateLegacyHistory();
    return store;
  }

  /// Чаты, свежие сверху.
  List<ChatSummary> get chats =>
      List.unmodifiable(_chats..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)));

  ChatSummary? find(String id) {
    for (final c in _chats) {
      if (c.id == id) return c;
    }
    return null;
  }

  String newId() => DateTime.now().microsecondsSinceEpoch.toString();

  List<ChatMessage> messages(String id) {
    final raw = _prefs.getString('$_kMessagesPrefix$id');
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .cast<Map<String, dynamic>>()
          .map(ChatMessage.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Сохраняет сообщения чата (без ошибок и пустых) и поднимает его наверх списка.
  /// Новый чат получает название из первого вопроса.
  Future<void> save(String id, List<ChatMessage> messages) async {
    final keep = messages
        .where((m) => !m.isError && m.text.trim().isNotEmpty)
        .toList();
    if (keep.isEmpty) return;
    final tail = keep.length > maxMessagesPerChat
        ? keep.sublist(keep.length - maxMessagesPerChat)
        : keep;
    await _prefs.setString(
      '$_kMessagesPrefix$id',
      jsonEncode(tail.map((m) => m.toJson()).toList()),
    );

    final existing = find(id);
    if (existing != null) {
      existing.updatedAt = DateTime.now();
    } else {
      final firstQuestion = keep.firstWhere(
        (m) => m.isUser,
        orElse: () => keep.first,
      );
      _chats.add(
        ChatSummary(
          id: id,
          title: titleFrom(firstQuestion.text),
          updatedAt: DateTime.now(),
        ),
      );
    }
    await _writeIndex();
  }

  Future<void> rename(String id, String title) async {
    final chat = find(id);
    final clean = title.trim();
    if (chat == null || clean.isEmpty) return;
    chat.title = clean;
    await _writeIndex();
  }

  Future<void> delete(String id) async {
    _chats.removeWhere((c) => c.id == id);
    await _prefs.remove('$_kMessagesPrefix$id');
    await _writeIndex();
  }

  static String titleFrom(String text, {int maxLength = 40}) {
    final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) return 'Новый чат';
    final capitalized = clean[0].toUpperCase() + clean.substring(1);
    return capitalized.length <= maxLength
        ? capitalized
        : '${capitalized.substring(0, maxLength).trimRight()}…';
  }

  List<ChatSummary> _readIndex() {
    final raw = _prefs.getString(_kIndex);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .cast<Map<String, dynamic>>()
          .map(ChatSummary.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeIndex() => _prefs.setString(
    _kIndex,
    jsonEncode(_chats.map((c) => c.toJson()).toList()),
  );

  Future<void> _migrateLegacyHistory() async {
    final raw = _prefs.getString(_kLegacyHistory);
    if (raw == null) return;
    try {
      final old = (jsonDecode(raw) as List)
          .cast<Map<String, dynamic>>()
          .map(ChatMessage.fromJson)
          .toList();
      await save(newId(), old);
    } catch (_) {
      // повреждённая старая история — просто отбрасываем
    }
    await _prefs.remove(_kLegacyHistory);
  }
}
