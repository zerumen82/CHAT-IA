import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

/// Burbuja de mensaje con soporte para imágenes
class ImageMessageBubble extends StatelessWidget {
  final String? text;
  final List<XFile>? images;
  final List<Uint8List>? imageBytes;
  final List<String>? imageUrls;
  final bool isUser;
  final DateTime timestamp;
  final String? model;
  final bool isError;

  const ImageMessageBubble({
    super.key,
    this.text,
    this.images,
    this.imageBytes,
    this.imageUrls,
    required this.isUser,
    required this.timestamp,
    this.model,
    this.isError = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
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
              child: Column(
                crossAxisAlignment:
                    isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Imágenes
                  if (_hasImages) ...[
                    _buildImagesGrid(context),
                    if (text != null && text!.isNotEmpty)
                      const SizedBox(height: 8),
                  ],

                  // Texto
                  if (text != null && text!.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: isUser
                            ? colorScheme.primary
                                .withAlpha((0.15 * 255).round())
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
                              ? colorScheme.primary
                                  .withAlpha((0.3 * 255).round())
                              : Colors.transparent,
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SelectableText(
                            text!,
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
                    )
                  else if (_hasImages)
                    // Solo imágenes, sin texto
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: isUser
                            ? colorScheme.primary
                                .withAlpha((0.15 * 255).round())
                            : colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isUser
                              ? colorScheme.primary
                                  .withAlpha((0.3 * 255).round())
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
                ],
              ),
            ),
          ),

          // Botón copiar
          if (!isUser && text != null) ...[
            const SizedBox(width: 4),
            _CopyButton(text: text!),
          ],
        ],
      ),
    );
  }

  bool get _hasImages {
    return (images != null && images!.isNotEmpty) ||
        (imageBytes != null && imageBytes!.isNotEmpty) ||
        (imageUrls != null && imageUrls!.isNotEmpty);
  }

  int get _imageCount {
    return (images?.length ?? 0) +
        (imageBytes?.length ?? 0) +
        (imageUrls?.length ?? 0);
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

  Widget _buildImagesGrid(BuildContext context) {
    final imageCount = _imageCount;

    if (imageCount == 1) {
      return _buildSingleImage(context);
    } else if (imageCount == 2) {
      return _buildTwoImages(context);
    } else {
      return _buildMultipleImages(context);
    }
  }

  Widget _buildSingleImage(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(20),
      ),
      child: _buildImageWidget(
          context, 0, MediaQuery.of(context).size.width * 0.6, 200),
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
        itemCount: _imageCount > 4 ? 4 : _imageCount,
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

                // Indicador de más imágenes
                if (index == 3 && _imageCount > 4)
                  Container(
                    color: Colors.black.withAlpha(128),
                    child: Center(
                      child: Text(
                        '+${_imageCount - 4}',
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
    // Prioridad: imageBytes > images > imageUrls

    if (imageBytes != null && index < imageBytes!.length) {
      return Image.memory(
        imageBytes![index],
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return _buildPlaceholder(context);
        },
      );
    }

    // Ajustar índice si hay imageBytes
    int adjustedIndex = index - (imageBytes?.length ?? 0);

    if (images != null &&
        adjustedIndex >= 0 &&
        adjustedIndex < images!.length) {
      return FutureBuilder<Uint8List>(
        future: images![adjustedIndex].readAsBytes(),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return Image.memory(
              snapshot.data!,
              width: width,
              height: height,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return _buildPlaceholder(context);
              },
            );
          }
          return _buildPlaceholder(context);
        },
      );
    }

    // Ajustar índice si hay images
    adjustedIndex = index - (imageBytes?.length ?? 0) - (images?.length ?? 0);

    if (imageUrls != null &&
        adjustedIndex >= 0 &&
        adjustedIndex < imageUrls!.length) {
      return Image.network(
        imageUrls![adjustedIndex],
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return _buildPlaceholder(context);
        },
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return _buildPlaceholder(context);
        },
      );
    }

    return _buildPlaceholder(context);
  }

  Widget _buildPlaceholder(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.image,
          size: 40,
          color: Theme.of(context).colorScheme.onSurfaceVariant.withAlpha(128),
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
        // Modelo usado
        if (!isUser && model != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withAlpha(128),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              model!,
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
          _formatTime(timestamp),
          style: TextStyle(
            fontSize: 11,
            color: colorScheme.onSurfaceVariant,
          ),
        ),

        // Indicador de error
        if (isError) ...[
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
