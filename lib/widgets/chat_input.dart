import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../services/chat_service.dart';

/// Campo de entrada de chat con soporte multimedia
class ChatInput extends StatefulWidget {
  final Function(String text, List<XFile>? images) onSendMessage;
  final bool enabled;
  final String? hintText;

  const ChatInput({
    super.key,
    required this.onSendMessage,
    this.enabled = true,
    this.hintText,
  });

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ImagePicker _imagePicker = ImagePicker();
  List<XFile> _selectedImages = [];
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    setState(() {
      _hasText = _controller.text.isNotEmpty;
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          _selectedImages.add(image);
        });
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al seleccionar imagen: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
    });
  }

  void _sendMessage() {
    if (!widget.enabled) return;
    
    final text = _controller.text.trim();
    final hasImages = _selectedImages.isNotEmpty;
    
    if (text.isEmpty && !hasImages) return;

    widget.onSendMessage(text, hasImages ? _selectedImages : null);
    
    _controller.clear();
    setState(() {
      _selectedImages = [];
      _hasText = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final chatService = context.watch<ChatService>();
    final isConnected = chatService.availableModels.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant,
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(13),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Preview de imágenes seleccionadas
          if (_selectedImages.isNotEmpty)
            _buildImagePreview(),

          // Fila principal de entrada
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Botón adjuntar
                _buildAttachButton(colorScheme, isConnected),
                
                const SizedBox(width: 8),
                
                // Campo de texto
                Expanded(
                  child: _buildTextField(colorScheme, isConnected),
                ),
                
                const SizedBox(width: 8),
                
                // Botón enviar
                _buildSendButton(colorScheme, isConnected),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePreview() {
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _selectedImages.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Stack(
              children: [
                // Imagen
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: FutureBuilder<Uint8List>(
                    future: _selectedImages[index].readAsBytes(),
                    builder: (context, snapshot) {
                      if (snapshot.hasData) {
                        return Image.memory(
                          snapshot.data!,
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                        );
                      }
                      return Container(
                        width: 64,
                        height: 64,
                        color: Colors.grey[300],
                        child: const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                
                // Botón eliminar
                Positioned(
                  top: -4,
                  right: -4,
                  child: GestureDetector(
                    onTap: () => _removeImage(index),
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.error,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        size: 14,
                        color: Colors.white,
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

  Widget _buildAttachButton(ColorScheme colorScheme, bool isConnected) {
    return PopupMenuButton<ImageSource>(
      enabled: isConnected && widget.enabled,
      icon: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.attach_file,
          size: 20,
          color: isConnected
              ? colorScheme.onSurfaceVariant
              : colorScheme.onSurfaceVariant.withAlpha(128),
        ),
      ),
      tooltip: 'Adjuntar imagen',
      onSelected: (source) => _pickImage(source),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: ImageSource.gallery,
          child: Row(
            children: [
              Icon(Icons.photo_library, size: 20, color: colorScheme.primary),
              const SizedBox(width: 12),
              const Text('Galería'),
            ],
          ),
        ),
        PopupMenuItem(
          value: ImageSource.camera,
          child: Row(
            children: [
              Icon(Icons.camera_alt, size: 20, color: colorScheme.primary),
              const SizedBox(width: 12),
              const Text('Cámara'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTextField(ColorScheme colorScheme, bool isConnected) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _sendMessage,
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): _sendMessage,
      },
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        enabled: widget.enabled && isConnected,
        maxLines: 5,
        minLines: 1,
        textInputAction: TextInputAction.newline,
        decoration: InputDecoration(
          hintText: widget.hintText ??
              (isConnected
                  ? 'Escribe un mensaje...'
                  : 'Conecta vLLM primero...'),
          hintStyle: TextStyle(
            color: colorScheme.onSurfaceVariant.withAlpha(180),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: colorScheme.surfaceContainerHighest,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildSendButton(ColorScheme colorScheme, bool isConnected) {
    final canSend = (_hasText || _selectedImages.isNotEmpty) && isConnected && widget.enabled;
    
    return GestureDetector(
      onTap: canSend ? _sendMessage : null,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: canSend
              ? colorScheme.primary
              : colorScheme.surfaceContainerHighest,
          shape: BoxShape.circle,
          boxShadow: canSend
              ? [
                  BoxShadow(
                    color: colorScheme.primary.withAlpha(77),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Icon(
          Icons.send_rounded,
          size: 20,
          color: canSend
              ? colorScheme.onPrimary
              : colorScheme.onSurfaceVariant.withAlpha(128),
        ),
      ),
    );
  }
}
