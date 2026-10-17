import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lightchat/models/message.dart';

/// Burbuja de mensaje unificada: texto + imágenes + acciones
class MessageBubble extends StatelessWidget {
  final Message message;
  final VoidCallback? onRetry;
  final VoidCallback? onCopy;
  final VoidCallback? onImageTap;

  const MessageBubble({
    super.key,
    required this.message,
    this.onRetry,
    this.onCopy,
    this.onImageTap,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final colorScheme = Theme.of(context).colorScheme;
    final maxWidth = MediaQuery.of(context).size.width * 0.75;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            _buildAssistantAvatar(context),
            const SizedBox(width: 8),
          ],

          Flexible(
            child: RepaintBoundary(
              child: Column(
                crossAxisAlignment:
                    isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (message.hasImages) ...[
                    _buildImagesGrid(context, maxWidth),
                    if (message.text.isNotEmpty) const SizedBox(height: 8),
                  ],

                  if (message.text.isNotEmpty) ...[
                    Container(
                      constraints: BoxConstraints(maxWidth: maxWidth),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: isUser
                            ? colorScheme.primary.withValues(
                                alpha: 0.15,
                              )
                            : colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(20),
                          topRight: const Radius.circular(20),
                          bottomLeft: isUser
                              ? const Radius.circular(20)
                              : const Radius.circular(4),
                          bottomRight: isUser
                              ? const Radius.circular(4)
                              : const Radius.circular(20),
                        ),
                        border: Border.all(
                          color: isUser
                              ? colorScheme.primary.withValues(alpha: 0.3)
                              : Colors.transparent,
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SelectableText(
                            message.text,
                            style: TextStyle(
                              color: colorScheme.onSurface,
                              fontSize: 15,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _buildFooter(context),
                        ],
                      ),
                    ),
                  ] else if (message.hasImages) ...[
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: isUser
                            ? colorScheme.primary.withValues(alpha: 0.15)
                            : colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isUser
                              ? colorScheme.primary.withValues(alpha: 0.3)
                              : Colors.transparent,
                          width: 1,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildFooter(context),
                        ],
                      ),
                    ),
                  ] else if (message.isError) ...[
                    Container(
                      constraints: BoxConstraints(maxWidth: maxWidth),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: colorScheme.errorContainer.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(20),
                          topRight: const Radius.circular(20),
                          bottomLeft: const Radius.circular(20),
                          bottomRight: const Radius.circular(4),
                        ),
                        border: Border.all(
                          color: colorScheme.error.withValues(alpha: 0.25),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SelectableText(
                            message.text,
                            style: TextStyle(
                              color: colorScheme.onErrorContainer,
                              fontSize: 15,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _formatTime(message.timestamp),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              if (onRetry != null) ...[
                                const SizedBox(width: 8),
                                _ActionChip(
                                  icon: Icons.refresh,
                                  label: 'Reintentar',
                                  onTap: onRetry!,
                                  color: colorScheme.error,
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          if (!isUser) ...[
            const SizedBox(width: 4),
            _CopyButton(
              text: message.text,
              onTap: onCopy,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildImagesGrid(BuildContext context, double maxWidth) {
    final imageCount = message.images?.length ?? 0;
    if (imageCount == 0) return const SizedBox.shrink();

    if (imageCount == 1) return _buildSingleImage(context, maxWidth * 0.6);
    if (imageCount == 2) return _buildTwoImages(context);
    return _buildMultipleImages(context);
  }

  Widget _buildSingleImage(BuildContext context, double width) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: _buildImageWidget(context, 0, width, 200),
    );
  }

  Widget _buildTwoImages(BuildContext context) {
    return SizedBox(
      height: 150,
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
              ),
              child: _buildImageWidget(context, 0, null, 150),
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(20),
              ),
              child: _buildImageWidget(context, 1, null, 150),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMultipleImages(BuildContext context) {
    final imageCount = message.images?.length ?? 0;
    return SizedBox(
      height: 200,
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 2,
          mainAxisSpacing: 2,
        ),
        itemCount: imageCount > 4 ? 4 : imageCount,
        itemBuilder: (context, index) {
          final isFirst = index == 0;
          return ClipRRect(
            borderRadius: BorderRadius.only(
              topLeft: isFirst ? const Radius.circular(20) : Radius.zero,
              topRight: index == 1 ? const Radius.circular(20) : Radius.zero,
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildImageWidget(context, index, null, null),
                if (index == 3 && imageCount > 4)
                  Container(
                    color: Colors.black.withValues(alpha: 0.5),
                    child: Center(
                      child: Text(
                        '+${imageCount - 4}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildImageWidget(BuildContext context, int index,
      double? width, double? height) {
    final images = message.images ?? [];
    if (index >= images.length) return _buildPlaceholder(context);

    final image = images[index];
    return GestureDetector(
      onTap: () => onImageTap?.call(),
      child: image.base64Data != null && image.base64Data!.isNotEmpty
          ? Image.memory(
              base64Decode(image.base64Data!),
              width: width,
              height: height,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _buildPlaceholder(context),
            )
          : image.localPath != null && image.localPath!.isNotEmpty
              ? Image.file(
                  File(image.localPath!),
                  width: width,
                  height: height,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _buildPlaceholder(context),
                )
              : _buildPlaceholder(context),
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.image,
          size: 40,
          color: Theme.of(context)
              .colorScheme
              .onSurfaceVariant
              .withValues(alpha: 0.5),
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (!message.isUser && message.model != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.5),
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
        Text(
          _formatTime(message.timestamp),
          style: TextStyle(
            fontSize: 11,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        if (message.isError) ...[
          const SizedBox(width: 4),
          Icon(
            Icons.error_outline,
            size: 14,
            color: colorScheme.error,
          ),
        ],
      ],
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
          color: colorScheme.primary.withValues(alpha: 0.3),
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

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.125),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CopyButton extends StatefulWidget {
  final String text;
  final VoidCallback? onTap;

  const _CopyButton({required this.text, this.onTap});

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
            widget.onTap?.call();
            setState(() => _copied = true);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Respuesta copiada'),
                duration: Duration(milliseconds: 1500),
                behavior: SnackBarBehavior.floating,
                margin: EdgeInsets.only(bottom: 80, left: 16, right: 16),
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
