import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Widget para seleccionar y previsualizar imágenes antes de enviar
class ImagePickerWidget extends StatelessWidget {
  final List<XFile> selectedImages;
  final Function(XFile image) onImageAdded;
  final Function(int index) onImageRemoved;
  final int maxImages;
  final bool enabled;

  const ImagePickerWidget({
    super.key,
    required this.selectedImages,
    required this.onImageAdded,
    required this.onImageRemoved,
    this.maxImages = 5,
    this.enabled = true,
  });

  Future<void> _pickImage(BuildContext context, ImageSource source) async {
    if (!enabled) return;
    if (selectedImages.length >= maxImages) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Máximo $maxImages imágenes permitidas'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    final ImagePicker picker = ImagePicker();

    try {
      if (source == ImageSource.gallery) {
        // Permitir selección múltiple en galería
        final List<XFile> images = await picker.pickMultiImage(
          maxWidth: 2048,
          maxHeight: 2048,
          imageQuality: 85,
        );

        for (final image in images) {
          if (selectedImages.length >= maxImages) break;
          onImageAdded(image);
        }
      } else {
        // Cámara: solo una imagen
        final XFile? image = await picker.pickImage(
          source: source,
          maxWidth: 2048,
          maxHeight: 2048,
          imageQuality: 85,
        );

        if (image != null) {
          onImageAdded(image);
        }
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al seleccionar imagen: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final canAddMore = selectedImages.length < maxImages && enabled;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Lista de imágenes seleccionadas
        if (selectedImages.isNotEmpty)
          Container(
            height: 100,
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: selectedImages.length,
              itemBuilder: (context, index) {
                return _ImagePreviewCard(
                  image: selectedImages[index],
                  index: index,
                  onRemove: onImageRemoved,
                );
              },
            ),
          ),

        // Botones de acción
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Botón galería
              _ActionButton(
                icon: Icons.photo_library,
                label: 'Galería',
                enabled: canAddMore,
                onPressed: () => _pickImage(context, ImageSource.gallery),
              ),

              const SizedBox(width: 16),

              // Botón cámara
              _ActionButton(
                icon: Icons.camera_alt,
                label: 'Cámara',
                enabled: canAddMore,
                onPressed: () => _pickImage(context, ImageSource.camera),
              ),

              const SizedBox(width: 16),

              // Contador
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  '${selectedImages.length}/$maxImages',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Tarjeta de previsualización de imagen
class _ImagePreviewCard extends StatelessWidget {
  final XFile image;
  final int index;
  final Function(int index) onRemove;

  const _ImagePreviewCard({
    required this.image,
    required this.index,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Stack(
        children: [
          // Imagen
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colorScheme.outlineVariant,
                width: 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: FutureBuilder<Uint8List>(
                future: image.readAsBytes(),
                builder: (context, snapshot) {
                  if (snapshot.hasData) {
                    return Image.memory(
                      snapshot.data!,
                      fit: BoxFit.cover,
                    );
                  }
                  return Container(
                    color: colorScheme.surfaceContainerHighest,
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // Botón eliminar
          Positioned(
            top: -6,
            right: -6,
            child: GestureDetector(
              onTap: () => onRemove(index),
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: colorScheme.error,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(51),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.close,
                  size: 16,
                  color: Colors.white,
                ),
              ),
            ),
          ),

          // Nombre del archivo
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(179),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(11),
                  bottomRight: Radius.circular(11),
                ),
              ),
              child: Text(
                image.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Botón de acción estilizado
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: enabled
                ? colorScheme.primaryContainer
                : colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: enabled
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurfaceVariant.withAlpha(128),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: enabled
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurfaceVariant.withAlpha(128),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
