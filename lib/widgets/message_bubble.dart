import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lightchat/models/message.dart';

/// Burbuja de mensaje con diseño estilo mensajería moderna
class MessageBubble extends StatelessWidget {
  final Message message;

  const MessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Avatar para el asistente
          if (!isUser) ...[
            _buildAssistantAvatar(context),
            const SizedBox(width: 8),
          ],
          
          // Burbuja del mensaje
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isUser
                    ? colorScheme.primary.withAlpha((0.15 * 255).round())
                    : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: isUser ? const Radius.circular(20) : const Radius.circular(4),
                  bottomRight: isUser ? const Radius.circular(4) : const Radius.circular(20),
                ),
                border: Border.all(
                  color: isUser
                      ? colorScheme.primary.withAlpha((0.3 * 255).round())
                      : Colors.transparent,
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(13),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Texto del mensaje
                  SelectableText(
                    message.text,
                    style: TextStyle(
                      color: isUser
                          ? colorScheme.onSurface
                          : colorScheme.onSurface,
                      fontSize: 15,
                      height: 1.5,
                    ),
                  ),
                  
                  const SizedBox(height: 8),
                  
                  // Fila inferior: hora, modelo y botón copiar
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Modelo usado (solo para respuestas)
                      if (!isUser && message.model != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer.withAlpha(128),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            message.model!,
                            style: TextStyle(
                              fontSize: 10,
                              color: colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      
                      // Hora
                      Text(
                        _formatTime(message.timestamp),
                        style: TextStyle(
                          fontSize: 11,
                          color: isUser
                              ? colorScheme.onSurfaceVariant
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                      
                      // Indicador de error
                      if (message.isError) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.error_outline,
                          size: 14,
                          color: colorScheme.error,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          // Botón copiar (solo visible al hover)
          if (!isUser) ...[
            const SizedBox(width: 4),
            _CopyButton(text: message.text),
          ],
        ],
      ),
    );
  }

  Widget _buildAssistantAvatar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        shape: BoxShape.circle,
        border: Border.all(
          color: colorScheme.primary.withAlpha((0.3 * 255).round()),
          width: 1,
        ),
      ),
      child: Icon(
        Icons.auto_awesome,
        size: 20,
        color: colorScheme.onPrimaryContainer,
      ),
    );
  }

  String _formatTime(DateTime timestamp) {
    final hour = timestamp.hour.toString().padLeft(2, '0');
    final minute = timestamp.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

/// Botón de copiar con efecto hover
class _CopyButton extends StatefulWidget {
  final String text;

  const _CopyButton({required this.text});

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _isHovered = false;
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: _isHovered ? 1.0 : 0.0,
        child: GestureDetector(
          onTap: () {
            Clipboard.setData(ClipboardData(text: widget.text));
            setState(() => _copied = true);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Respuesta copiada'),
                duration: const Duration(milliseconds: 1500),
                behavior: SnackBarBehavior.floating,
                margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
              ),
            );
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted) setState(() => _copied = false);
            });
          },
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(
              _copied ? Icons.check : Icons.copy,
              size: 14,
              color: _copied
                  ? Colors.green
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
