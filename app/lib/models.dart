enum Role { user, assistant }

/// Одно сообщение чата. [text] у ответа Луны растёт по мере потоковой генерации.
class ChatMessage {
  ChatMessage({required this.role, required this.text, this.isError = false});

  ChatMessage.user(this.text) : role = Role.user, isError = false;
  ChatMessage.assistant(this.text) : role = Role.assistant, isError = false;
  ChatMessage.error(this.text) : role = Role.assistant, isError = true;

  final Role role;
  String text;

  /// Ошибки показываются в чате, но не сохраняются и не уходят в контекст.
  final bool isError;

  bool get isUser => role == Role.user;

  Map<String, dynamic> toJson() => {'role': role.name, 'content': text};

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    role: json['role'] == 'user' ? Role.user : Role.assistant,
    text: json['content'] as String? ?? '',
  );
}
