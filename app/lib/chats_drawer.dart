import 'package:flutter/material.dart';

import 'chat_store.dart';

/// Боковое меню: «Новый чат» и список чатов (свежие сверху).
class ChatsDrawer extends StatelessWidget {
  const ChatsDrawer({
    super.key,
    required this.chats,
    required this.currentId,
    required this.onNew,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  final List<ChatSummary> chats;
  final String? currentId;
  final VoidCallback onNew;
  final ValueChanged<String> onOpen;
  final void Function(String id, String title) onRename;
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NavigationDrawer(
      selectedIndex: null,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: FilledButton.tonalIcon(
            onPressed: onNew,
            icon: const Icon(Icons.add),
            label: const Text('Новый чат'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ),
        if (chats.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Чатов пока нет',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        for (final chat in chats)
          _ChatTile(
            chat: chat,
            selected: chat.id == currentId,
            onTap: () => onOpen(chat.id),
            onRename: () => _rename(context, chat),
            onDelete: () => _confirmDelete(context, chat),
          ),
      ],
    );
  }

  Future<void> _rename(BuildContext context, ChatSummary chat) async {
    final controller = TextEditingController(text: chat.title);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Название чата'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 60,
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title != null && title.trim().isNotEmpty) onRename(chat.id, title);
  }

  Future<void> _confirmDelete(BuildContext context, ChatSummary chat) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить чат?'),
        content: Text('«${chat.title}» удалится насовсем.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok == true) onDelete(chat.id);
  }
}

class _ChatTile extends StatelessWidget {
  const _ChatTile({
    required this.chat,
    required this.selected,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  final ChatSummary chat;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: ListTile(
        selected: selected,
        selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Text(chat.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(formatChatTime(chat.updatedAt, DateTime.now())),
        onTap: onTap,
        trailing: PopupMenuButton<String>(
          tooltip: 'Действия',
          onSelected: (action) =>
              action == 'rename' ? onRename() : onDelete(),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'rename', child: Text('Переименовать')),
            PopupMenuItem(value: 'delete', child: Text('Удалить')),
          ],
        ),
      ),
    );
  }
}

/// «сегодня 14:05», «вчера 09:30», «12.11», «12.11.2025».
String formatChatTime(DateTime t, DateTime now) {
  String two(int n) => n.toString().padLeft(2, '0');
  final day = DateTime(t.year, t.month, t.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(day).inDays;
  final hm = '${two(t.hour)}:${two(t.minute)}';
  if (diff == 0) return 'сегодня $hm';
  if (diff == 1) return 'вчера $hm';
  if (t.year == now.year) return '${two(t.day)}.${two(t.month)}';
  return '${two(t.day)}.${two(t.month)}.${t.year}';
}
