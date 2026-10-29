import 'package:flutter/material.dart';
import '../services/conversation_service.dart';
import 'file_actions.dart';
import 'package:provider/provider.dart';

import '../models/conversation.dart';
import '../services/chat_service_ollama.dart';

/// Barra lateral con las conversaciones guardadas: abrir, renombrar y borrar.
class ConversationSidebar extends StatefulWidget {
  final VoidCallback? onConversationSelected;
  const ConversationSidebar({super.key, this.onConversationSelected});

  @override
  State<ConversationSidebar> createState() => _ConversationSidebarState();
}

class _ConversationSidebarState extends State<ConversationSidebar> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Consumer<ChatServiceOllama>(
      builder: (context, chatService, _) {
        final conversations = chatService.conversations
            .where((conversation) =>
                conversation.title.toLowerCase().contains(_query.toLowerCase()))
            .toList();

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
                          : () async {
                              await chatService.newConversation();
                              if (mounted) {
                                widget.onConversationSelected?.call();
                              }
                            },
                      icon: const Icon(Icons.add_comment_outlined, size: 18),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: colorScheme.outlineVariant),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: TextField(
                  onChanged: (value) => setState(() => _query = value.trim()),
                  decoration: const InputDecoration(
                    hintText: 'Buscar conversaciones',
                    prefixIcon: Icon(Icons.search, size: 18),
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              Expanded(
                child: conversations.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            _query.isEmpty
                                ? 'No hay conversaciones guardadas.'
                                : 'No hay conversaciones que coincidan.',
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
                          onSelected: widget.onConversationSelected,
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
  final VoidCallback? onSelected;

  const _ConversationTile({
    required this.conversation,
    required this.isActive,
    required this.isBusy,
    this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final chatService = context.read<ChatServiceOllama>();

    final initial = conversation.title.isNotEmpty
        ? conversation.title[0].toUpperCase()
        : '?';
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isActive
            ? colorScheme.primaryContainer.withValues(alpha: 0.18)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: isActive
            ? Border.all(
                color: colorScheme.primary.withValues(alpha: 0.5), width: 1)
            : null,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: isBusy
            ? null
            : () async {
                await chatService.selectConversation(conversation.id);
                if (context.mounted) {
                  onSelected?.call();
                }
              },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: isActive
                    ? colorScheme.primary
                    : colorScheme.surfaceContainerLow,
                child: Text(
                  initial,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isActive
                        ? colorScheme.onPrimary
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
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
                enabled: !isBusy,
                tooltip: 'Opciones de la conversación',
                icon: Icon(
                  Icons.more_horiz,
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
                padding: EdgeInsets.zero,
                onSelected: (action) {
                  switch (action) {
                    case 'export':
                      final saved =
                          conversation.id == chatService.activeConversationId
                              ? List.of(chatService.messages)
                              : null;
                      () async {
                        final messages = saved ??
                            await ConversationService.loadMessages(
                                conversation.id);
                        if (context.mounted) {
                          await showExportDialog(context,
                              title: conversation.title, messages: messages);
                        }
                      }();
                      break;
                    case 'rename':
                      _showRenameDialog(context, chatService);
                      break;
                    case 'delete':
                      _showDeleteDialog(context, chatService);
                      break;
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                      value: 'export',
                      enabled: !chatService.isLoading,
                      child: const ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.save_alt, size: 18),
                          title: Text('Exportar'))),
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

    if (result == null) {
      return;
    }
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

    if (confirmed != true) {
      return;
    }
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
    if (difference.inMinutes < 1) {
      return 'ahora';
    }
    if (difference.inHours < 1) {
      return 'hace ${difference.inMinutes} min';
    }
    if (now.year == date.year &&
        now.month == date.month &&
        now.day == date.day) {
      final hour = date.hour.toString().padLeft(2, '0');
      final minute = date.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    }
    if (difference.inDays < 7) {
      return 'hace ${difference.inDays} d';
    }
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }
}
