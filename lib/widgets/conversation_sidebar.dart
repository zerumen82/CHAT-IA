import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/conversation.dart';
import '../services/chat_service_ollama.dart';

/// Barra lateral con las conversaciones guardadas: abrir, renombrar y borrar.
class ConversationSidebar extends StatelessWidget {
  const ConversationSidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Consumer<ChatServiceOllama>(
      builder: (context, chatService, _) {
        final conversations = chatService.conversations;

        return Container(
          color: colorScheme.surfaceContainerLow,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.forum_outlined,
                      size: 18,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Conversaciones',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: chatService.isLoading
                          ? 'Detén la generación para crear otra conversación'
                          : 'Nueva conversación',
                      onPressed: chatService.isLoading
                          ? null
                          : () => chatService.newConversation(),
                      icon: const Icon(Icons.add_comment_outlined, size: 18),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: colorScheme.outlineVariant),
              Expanded(
                child: conversations.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'No hay conversaciones guardadas.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        itemCount: conversations.length,
                        itemBuilder: (context, index) => _ConversationTile(
                          conversation: conversations[index],
                          isActive: conversations[index].id ==
                              chatService.activeConversationId,
                          isBusy: chatService.isLoading,
                        ),
                      ),
              ),
              Divider(height: 1, color: colorScheme.outlineVariant),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: Text(
                  conversations.length == 1
                      ? '1 conversación · se guarda automáticamente'
                      : '${conversations.length} conversaciones · se guardan '
                          'automáticamente',
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final ConversationSummary conversation;
  final bool isActive;
  final bool isBusy;

  const _ConversationTile({
    required this.conversation,
    required this.isActive,
    required this.isBusy,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final chatService = context.read<ChatServiceOllama>();

    return Material(
      color: isActive
          ? colorScheme.primaryContainer.withValues(alpha: 0.45)
          : Colors.transparent,
      child: InkWell(
        onTap: isBusy
            ? null
            : () => chatService.selectConversation(conversation.id),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 2, 8),
          child: Row(
            children: [
              Icon(
                isActive ? Icons.chat_bubble : Icons.chat_bubble_outline,
                size: 16,
                color: isActive
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      conversation.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            isActive ? FontWeight.w600 : FontWeight.w400,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${conversation.messageCount} '
                      '${conversation.messageCount == 1 ? 'mensaje' : 'mensajes'}'
                      ' · ${_formatWhen(conversation.updatedAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Opciones de la conversación',
                icon: Icon(
                  Icons.more_horiz,
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
                padding: EdgeInsets.zero,
                onSelected: (action) {
                  switch (action) {
                    case 'rename':
                      _showRenameDialog(context, chatService);
                      break;
                    case 'delete':
                      _showDeleteDialog(context, chatService);
                      break;
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'rename',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.drive_file_rename_outline, size: 18),
                      title: Text('Renombrar'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.delete_outline, size: 18),
                      title: Text('Eliminar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showRenameDialog(
    BuildContext context,
    ChatServiceOllama chatService,
  ) async {
    final controller = TextEditingController(text: conversation.title);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Renombrar conversación'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(labelText: 'Título'),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (result == null) return;
    await chatService.renameConversation(conversation.id, result);
  }

  Future<void> _showDeleteDialog(
    BuildContext context,
    ChatServiceOllama chatService,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar conversación'),
        content: Text(
          '¿Eliminar «${conversation.title}» y todos sus mensajes?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await chatService.deleteConversation(conversation.id);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Conversación eliminada'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _formatWhen(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    if (difference.inMinutes < 1) return 'ahora';
    if (difference.inHours < 1) return 'hace ${difference.inMinutes} min';
    if (now.year == date.year &&
        now.month == date.month &&
        now.day == date.day) {
      final hour = date.hour.toString().padLeft(2, '0');
      final minute = date.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    }
    if (difference.inDays < 7) return 'hace ${difference.inDays} d';
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }
}
