import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import '../config/ui_config.dart';
import 'package:flutter/material.dart';
import 'file_actions.dart';
import 'package:lightchat/models/document_attachment.dart';
import 'package:lightchat/models/message.dart';
import 'package:lightchat/widgets/assistant_markdown.dart';
import 'package:lightchat/widgets/document_text_dialog.dart';

/// Burbuja de mensaje unificada: texto + imágenes + acciones
class MessageBubble extends StatelessWidget {
  final Message message;
  final VoidCallback? onRetry;
  final VoidCallback? onCopy;
  final VoidCallback? onImageTap;

  /// Vuelve a pedir esta respuesta al modelo (solo en el último mensaje).
  final VoidCallback? onRegenerate;

  /// Abre el diálogo para editar este mensaje del usuario y reenviarlo.
  final VoidCallback? onEdit;
  final VoidCallback? onExport;
  final VoidCallback? onContinue;
  final bool canExport;

  const MessageBubble({
    super.key,
    required this.message,
    this.onRetry,
    this.onCopy,
    this.onImageTap,
    this.onRegenerate,
    this.onEdit,
    this.onExport,
    this.onContinue,
    this.canExport = true,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final colorScheme = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, constraints) {
      final available = constraints.maxWidth.isFinite
          ? constraints.maxWidth
          : UiConfig.bubbleWidth;
      final maxWidth = math.min(
          UiConfig.bubbleWidth, math.max(0.0, available - (isUser ? 24 : 68)));
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          mainAxisAlignment:
              isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isUser) ...[
              _buildAssistantAvatar(context),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: RepaintBoundary(
                child: Column(
                  crossAxisAlignment: isUser
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (message.hasImages) ...[
                      _buildImagesGrid(context, maxWidth),
                      if (message.text.isNotEmpty || message.hasDocuments)
                        const SizedBox(height: 8),
                    ],
                    if (message.generatedFiles.isNotEmpty) ...[
                      for (final file in message.generatedFiles)
                        Container(
                            constraints: BoxConstraints(maxWidth: maxWidth),
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                                color: colorScheme.secondaryContainer,
                                borderRadius: BorderRadius.circular(12)),
                            child: Wrap(
                                spacing: 12,
                                runSpacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Icon(file.format.extension == 'pdf'
                                      ? Icons.picture_as_pdf
                                      : Icons.table_chart),
                                  Text(file.name),
                                  Text(
                                      '${(file.sizeBytes / 1024).toStringAsFixed(1)} KB'),
                                  TextButton.icon(
                                      onPressed: canExport
                                          ? () =>
                                              saveGeneratedFile(context, file)
                                          : null,
                                      icon: const Icon(Icons.save_alt),
                                      label: const Text('Guardar')),
                                ])),
                    ],
                    if (message.isUser &&
                        (message.metadata?['contextSnapshot'] != null ||
                            (message.metadata?['contextText'] as String? ?? '')
                                .isNotEmpty))
                      TextButton.icon(
                          icon: const Icon(Icons.visibility_outlined, size: 16),
                          label: Text(
                              message.metadata?['contextPartial'] == true
                                  ? 'Ver contexto enviado · parcial'
                                  : 'Ver contexto enviado'),
                          onPressed: () => showSentContext(context, message)),
                    if (message.hasDocuments) ...[
                      _buildDocuments(context, maxWidth),
                      if (message.text.isNotEmpty) const SizedBox(height: 8),
                    ],
                    if (message.isUser &&
                        message.metadata?['historyPartial'] == true)
                      Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                              'Parte del historial guardado quedó fuera de este envío.',
                              style: TextStyle(
                                  fontSize: 12, color: colorScheme.tertiary))),
                    if (message.text.isNotEmpty &&
                        (!message.isError ||
                            message.metadata?['error'] != null)) ...[
                      Container(
                        constraints: BoxConstraints(maxWidth: maxWidth),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: isUser
                              ? colorScheme.primaryContainer
                              : colorScheme.surfaceContainerLow,
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
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isUser)
                              Text(
                                message.text,
                                style: TextStyle(
                                  color: colorScheme.onPrimaryContainer,
                                  fontSize: 16,
                                  height: 1.5,
                                ),
                              )
                            else
                              AssistantMarkdown(
                                text: message.text,
                                textColor: colorScheme.onSurface,
                              ),
                            if (message.metadata?['error'] != null) ...[
                              const SizedBox(height: 10),
                              Text(
                                  'Respuesta interrumpida: ${message.metadata!['error']}',
                                  style: TextStyle(color: colorScheme.error)),
                              if (onRetry != null)
                                TextButton.icon(
                                    onPressed: onRetry,
                                    icon: const Icon(Icons.refresh, size: 16),
                                    label: const Text('Reintentar')),
                            ],
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
                              ? colorScheme.primaryContainer
                              : colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isUser
                                ? colorScheme.primary.withValues(alpha: 0.45)
                                : colorScheme.outlineVariant,
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
                          color: colorScheme.errorContainer,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(20),
                            topRight: const Radius.circular(20),
                            bottomLeft: const Radius.circular(20),
                            bottomRight: const Radius.circular(4),
                          ),
                          border: Border.all(
                            color: colorScheme.error.withValues(alpha: 0.45),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              message.text,
                              style: TextStyle(
                                color: colorScheme.onErrorContainer,
                                fontSize: 16,
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
                                    fontSize: 12,
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
          ],
        ),
      );
    });
  }

  Widget _buildDocuments(BuildContext context, double maxWidth) {
    final colorScheme = Theme.of(context).colorScheme;
    final documents = message.documents ?? [];
    final foregroundColor =
        message.isUser ? colorScheme.onPrimaryContainer : colorScheme.onSurface;

    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: message.isUser
            ? colorScheme.primaryContainer
            : colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: message.isUser
              ? const Radius.circular(16)
              : const Radius.circular(4),
          bottomRight: message.isUser
              ? const Radius.circular(4)
              : const Radius.circular(16),
        ),
        border: Border.all(
          color: message.isUser
              ? colorScheme.primary.withValues(alpha: 0.45)
              : colorScheme.outlineVariant,
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final document in documents)
            Tooltip(
              message: 'Ver el texto que se envió al modelo',
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => showDocumentTextDialog(context, document),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _documentIcon(document.kind),
                        size: 16,
                        color: foregroundColor.withValues(alpha: 0.8),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          document.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: foregroundColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        document.truncated
                            ? '${document.sizeFormatted} · recortado'
                            : document.sizeFormatted,
                        style: TextStyle(
                          fontSize: 11,
                          color: foregroundColor.withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.visibility_outlined,
                        size: 14,
                        color: foregroundColor.withValues(alpha: 0.6),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  IconData _documentIcon(DocumentKind kind) {
    return switch (kind) {
      DocumentKind.pdf => Icons.picture_as_pdf,
      DocumentKind.spreadsheet => Icons.table_chart,
      DocumentKind.presentation => Icons.slideshow,
      DocumentKind.text => Icons.description,
    };
  }

  Widget _buildImagesGrid(BuildContext context, double maxWidth) {
    final imageCount = message.images?.length ?? 0;
    if (imageCount == 0) {
      return const SizedBox.shrink();
    }

    if (imageCount == 1) {
      return _buildSingleImage(context, maxWidth * 0.6);
    }
    if (imageCount == 2) {
      return _buildTwoImages(context);
    }
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

  Widget _buildImageWidget(
      BuildContext context, int index, double? width, double? height) {
    final images = message.images ?? [];
    if (index >= images.length) {
      return _buildPlaceholder(context);
    }

    final image = images[index];
    return GestureDetector(
      onTap: () {
        if (onImageTap != null) {
          onImageTap!();
          return;
        }
        _showImageViewer(context, image);
      },
      child: image.base64Data != null && image.base64Data!.isNotEmpty
          ? Image.memory(
              base64Decode(image.base64Data!),
              width: width,
              height: height,
              fit: BoxFit.cover,
              cacheWidth: 800,
              errorBuilder: (_, __, ___) => _buildPlaceholder(context),
            )
          : image.localPath != null && image.localPath!.isNotEmpty
              ? Image.file(
                  File(image.localPath!),
                  width: width,
                  height: height,
                  fit: BoxFit.cover,
                  cacheWidth: 800,
                  errorBuilder: (_, __, ___) => _buildPlaceholder(context),
                )
              : _buildPlaceholder(context),
    );
  }

  /// Visor a pantalla completa para las imágenes del mensaje.
  Future<void> _showImageViewer(
    BuildContext context,
    MessageImage image,
  ) async {
    Widget imageWidget;
    if (image.base64Data != null && image.base64Data!.isNotEmpty) {
      imageWidget = Image.memory(
        base64Decode(image.base64Data!),
        fit: BoxFit.contain,
      );
    } else if (image.localPath != null && image.localPath!.isNotEmpty) {
      imageWidget = Image.file(
        File(image.localPath!),
        fit: BoxFit.contain,
      );
    } else {
      return;
    }

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Cerrar',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Flexible(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 5,
                child: imageWidget,
              ),
            ),
          ],
        ),
      ),
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
    final footerColor = message.isUser
        ? colorScheme.onPrimaryContainer.withValues(alpha: 0.8)
        : colorScheme.onSurfaceVariant;

    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 2,
      children: [
        if (!message.isUser && message.model != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              message.model!,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        Text(
          _formatTime(message.timestamp),
          style: TextStyle(fontSize: 12, color: footerColor),
        ),
        if (message.isError)
          Icon(
            Icons.error_outline,
            size: 14,
            color: colorScheme.error,
          ),
        if (!message.isUser && message.metadata?['finishReason'] != null)
          Text(
              switch (message.metadata!['finishReason']) {
                'completed' => 'Completada',
                'length' => 'Límite de respuesta alcanzado',
                'stopped' => 'Detenida',
                'interrupted' => 'Interrumpida',
                _ => 'Finalizada',
              },
              style: TextStyle(fontSize: 12, color: footerColor)),
        if (onContinue != null)
          TextButton.icon(
              onPressed: onContinue,
              icon: const Icon(Icons.play_arrow, size: 16),
              label: const Text('Continuar')),
        if (onCopy != null || onExport != null)
          PopupMenuButton<String>(
            tooltip: 'Acciones del mensaje',
            icon: const Icon(Icons.more_horiz, size: 18),
            onSelected: (action) {
              if (action == 'copy') {
                onCopy?.call();
              }
              if (action == 'export') {
                onExport?.call();
              }
            },
            itemBuilder: (_) => [
              if (onCopy != null)
                const PopupMenuItem(value: 'copy', child: Text('Copiar')),
              if (onExport != null)
                const PopupMenuItem(
                    value: 'export', child: Text('Exportar respuesta')),
            ],
          ),
        if (!message.isUser && onRegenerate != null)
          TextButton.icon(
            onPressed: onRegenerate,
            icon: const Icon(Icons.refresh, size: 14),
            label: const Text('Regenerar'),
            style: TextButton.styleFrom(
              foregroundColor: colorScheme.primary,
              minimumSize: const Size(0, 28),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(fontSize: 12),
            ),
          ),
        if (message.isUser && onEdit != null)
          IconButton(
            tooltip: 'Editar y reenviar',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 14),
            color: footerColor,
            padding: const EdgeInsets.all(2),
            constraints: const BoxConstraints(),
            visualDensity: VisualDensity.compact,
          ),
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
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: color,
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
    );
  }
}
