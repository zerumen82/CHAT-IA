import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/document_attachment.dart';
import '../services/document_service.dart';

enum _AttachAction { file, gallery, camera }

/// Campo de entrada de chat con soporte multimedia y documentos
class ChatInput extends StatefulWidget {
  final void Function(
    String text,
    List<XFile>? images,
    List<DocumentAttachment>? documents,
  ) onSendMessage;
  final bool enabled;

  /// True mientras el modelo responde: se puede escribir, pero no enviar.
  final bool busy;

  /// True si hay modelos disponibles en Ollama.
  final bool connected;
  final String? hintText;

  const ChatInput({
    super.key,
    required this.onSendMessage,
    this.enabled = true,
    this.busy = false,
    this.connected = false,
    this.hintText,
  });

  @override
  State<ChatInput> createState() => ChatInputState();
}

class ChatInputState extends State<ChatInput> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ImagePicker _imagePicker = ImagePicker();

  /// Lecturas de disco en curso, cacheadas por ruta: antes se creaba un
  /// `Future` nuevo en cada `build` y la miniatura volvía a cargar.
  final Map<String, Future<Uint8List>> _imageReads = {};

  List<XFile> _selectedImages = [];
  final List<DocumentAttachment> _documents = [];
  int _pendingExtractions = 0;
  bool _hasText = false;

  static const int maxImages = 5;
  static const int maxDocuments = 5;

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
    _imageReads.clear();
    super.dispose();
  }

  void _onTextChanged() {
    // Solo importa si hay texto o no; el contador se actualiza aparte.
    final hasText = _controller.text.isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
  }

  /// Añade archivos soltados o seleccionados: imágenes o documentos.
  Future<void> addFiles(List<XFile> files) async {
    if (!widget.enabled || files.isEmpty) {
      return;
    }

    final unsupported = <String>[];
    for (final file in files) {
      final name = _displayName(file);
      if (DocumentService.isImagePath(name)) {
        if (_selectedImages.length >= maxImages) {
          _showSnack('Máximo $maxImages imágenes adjuntas.');
          continue;
        }
        if (_selectedImages.any((image) => image.path == file.path)) {
          continue;
        }
        setState(() {
          _selectedImages.add(file);
        });
      } else if (DocumentService.isSupportedDocument(name)) {
        if (_documents.length >= maxDocuments) {
          _showSnack('Máximo $maxDocuments documentos adjuntos.');
          continue;
        }
        if (_documents.any((document) => document.path == file.path)) {
          continue;
        }
        await _addDocument(file);
      } else {
        unsupported.add(name);
      }
    }

    if (unsupported.isNotEmpty) {
      _showSnack(
        'No se puede adjuntar: ${unsupported.join(', ')}. '
        'Formatos admitidos: PDF, XLSX, CSV, TXT, MD, JSON o LOG.',
      );
    }
  }

  String _displayName(XFile file) {
    if (file.name.isNotEmpty) {
      return file.name;
    }
    return file.path.split(RegExp(r'[/\\]')).last;
  }

  Future<void> _addDocument(XFile file) async {
    final name = _displayName(file);
    final placeholder = DocumentAttachment(
      path: file.path,
      name: name,
      kind: DocumentService.kindOf(name),
      sizeBytes: 0,
      isLoading: true,
    );

    setState(() {
      _documents.add(placeholder);
      _pendingExtractions++;
    });

    final attachment = await DocumentService.extract(
      file.path,
      displayName: name,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      final index = _documents.indexWhere(
        (document) => document.path == placeholder.path && document.isLoading,
      );
      if (index >= 0) {
        _documents[index] = attachment;
      }
      if (_pendingExtractions > 0) {
        _pendingExtractions--;
      }
    });

    if (attachment.error != null) {
      _showSnack('${attachment.name}: ${attachment.error}');
    }
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
      ),
    );
  }

  /// Abre el diálogo del sistema para elegir documentos o imágenes.
  Future<void> _pickFiles() async {
    try {
      final typeGroup = XTypeGroup(
        label: 'Documentos e imágenes',
        extensions: [
          ...DocumentService.supportedExtensions,
          ...DocumentService.imageExtensions,
        ],
      );
      final files = await openFiles(acceptedTypeGroups: [typeGroup]);
      if (files.isNotEmpty) {
        await addFiles(files);
      }
    } catch (e) {
      _showSnack('No se pudo abrir el selector de archivos: $e');
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      if (source == ImageSource.gallery) {
        final List<XFile> images = await _imagePicker.pickMultiImage(
          maxWidth: 2048,
          maxHeight: 2048,
          imageQuality: 85,
        );

        for (final image in images) {
          if (_selectedImages.length >= maxImages) break;
          setState(() {
            _selectedImages.add(image);
          });
        }
      } else {
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
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
      if (mounted) {
        _showSnack('Error al seleccionar imagen: $e');
      }
    }
  }

  void _removeImage(int index) {
    setState(() {
      final removedImage = _selectedImages.removeAt(index);
      _imageReads.remove(removedImage.path);
    });
  }

  void _removeDocument(int index) {
    setState(() {
      _documents.removeAt(index);
    });
  }

  Future<Uint8List> _imageBytes(int index) {
    final image = _selectedImages[index];
    return _imageReads.putIfAbsent(image.path, image.readAsBytes);
  }

  bool get _canSend =>
      widget.enabled &&
      !widget.busy &&
      _pendingExtractions == 0 &&
      (_controller.text.trim().isNotEmpty ||
          _selectedImages.isNotEmpty ||
          _documents.any((document) => document.isReady));

  void _sendMessage() {
    if (!_canSend) return;

    final text = _controller.text.trim();
    final hasImages = _selectedImages.isNotEmpty;
    final documents = _documents.where((document) => document.isReady).toList();

    widget.onSendMessage(
      text,
      hasImages ? _selectedImages : null,
      documents.isEmpty ? null : documents,
    );

    _controller.clear();
    setState(() {
      _selectedImages = [];
      _imageReads.clear();
      _documents.clear();
      _hasText = false;
    });
  }

  /// Enter envía; Shift+Enter sigue insertando un salto de línea.
  void _handleEnter() {
    if (_canSend) {
      _sendMessage();
      return;
    }

    final value = _controller.value;
    final selection = value.selection;
    if (!selection.isValid) return;
    final text = value.text.replaceRange(
      selection.start,
      selection.end,
      '\n',
    );
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: selection.start + 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isConnected = widget.connected;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_documents.isNotEmpty) _buildDocumentPreview(),
          if (_selectedImages.isNotEmpty) _buildImagePreview(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _buildAttachButton(colorScheme, isConnected),
                    const SizedBox(width: 8),
                    Expanded(child: _buildTextField(colorScheme, isConnected)),
                    const SizedBox(width: 8),
                    _buildSendButton(colorScheme, isConnected),
                  ],
                ),
                const SizedBox(height: 6),
                _buildStatusLine(colorScheme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusLine(ColorScheme colorScheme) {
    final hasAttachments = _documents.isNotEmpty || _selectedImages.isNotEmpty;

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _controller,
      builder: (context, value, _) {
        return Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 2,
          children: [
            if (value.text.length >= 800)
              Text(
                '${value.text.length} caracteres',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            if (_documents.isNotEmpty)
              Text(
                '${_documents.length}/$maxDocuments documentos',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            if (_selectedImages.isNotEmpty)
              Text(
                '${_selectedImages.length}/$maxImages imágenes',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            if (!hasAttachments)
              Text(
                'Arrastra o adjunta PDF, Excel o imágenes · Enter envía',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildDocumentPreview() {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var index = 0; index < _documents.length; index++)
            _buildDocumentChip(colorScheme, _documents[index], index),
        ],
      ),
    );
  }

  Widget _buildDocumentChip(
    ColorScheme colorScheme,
    DocumentAttachment document,
    int index,
  ) {
    final isError = document.error != null;
    final accentColor = isError ? colorScheme.error : colorScheme.primary;

    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
      decoration: BoxDecoration(
        color: isError
            ? colorScheme.errorContainer.withValues(alpha: 0.5)
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isError
              ? colorScheme.error.withValues(alpha: 0.5)
              : colorScheme.outlineVariant,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (document.isLoading)
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: accentColor,
              ),
            )
          else
            Icon(
              _documentIcon(document.kind),
              size: 20,
              color: accentColor,
            ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  document.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isError
                        ? colorScheme.onErrorContainer
                        : colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _documentSubtitle(document),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: isError
                        ? colorScheme.onErrorContainer
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Quitar documento',
            onPressed: () => _removeDocument(index),
            icon: const Icon(Icons.close, size: 16),
            visualDensity: VisualDensity.compact,
            color: colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }

  String _documentSubtitle(DocumentAttachment document) {
    if (document.isLoading) {
      return 'Leyendo documento…';
    }
    if (document.error != null) {
      return document.error!;
    }

    final parts = <String>[
      if (document.sizeBytes > 0) document.sizeFormatted,
      '${document.charCount} caracteres',
      if (document.truncated) 'recortado',
    ];
    return parts.join(' · ');
  }

  IconData _documentIcon(DocumentKind kind) {
    return switch (kind) {
      DocumentKind.pdf => Icons.picture_as_pdf,
      DocumentKind.spreadsheet => Icons.table_chart,
      DocumentKind.text => Icons.description,
    };
  }

  Widget _buildImagePreview() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 96,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _selectedImages.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: FutureBuilder<Uint8List>(
                    future: _imageBytes(index),
                    builder: (context, snapshot) {
                      if (snapshot.hasData) {
                        return Image.memory(
                          snapshot.data!,
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                          cacheWidth: 160,
                        );
                      }
                      if (snapshot.hasError) {
                        return Container(
                          width: 80,
                          height: 80,
                          color: colorScheme.surfaceContainerHighest,
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        );
                      }
                      return Container(
                        width: 80,
                        height: 80,
                        color: colorScheme.surfaceContainerHighest,
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
                Positioned(
                  top: -4,
                  right: -4,
                  child: GestureDetector(
                    onTap: () => _removeImage(index),
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.error,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        size: 16,
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
    final canAttach = isConnected && widget.enabled;

    return PopupMenuButton<_AttachAction>(
      enabled: canAttach,
      icon: const Icon(Icons.attach_file),
      tooltip: canAttach
          ? 'Adjuntar archivo, imagen o documento'
          : 'Conecta Ollama para adjuntar',
      onSelected: (action) {
        switch (action) {
          case _AttachAction.file:
            _pickFiles();
            break;
          case _AttachAction.gallery:
            _pickImage(ImageSource.gallery);
            break;
          case _AttachAction.camera:
            _pickImage(ImageSource.camera);
            break;
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _AttachAction.file,
          child: Row(
            children: [
              Icon(Icons.upload_file, size: 20, color: colorScheme.primary),
              const SizedBox(width: 12),
              const Flexible(child: Text('Archivo (PDF, Excel, CSV…)')),
            ],
          ),
        ),
        PopupMenuItem(
          value: _AttachAction.gallery,
          child: Row(
            children: [
              Icon(Icons.photo_library, size: 20, color: colorScheme.primary),
              const SizedBox(width: 12),
              const Text('Galería de imágenes'),
            ],
          ),
        ),
        if (Platform.isAndroid || Platform.isIOS)
          PopupMenuItem(
            value: _AttachAction.camera,
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
        const SingleActivator(LogicalKeyboardKey.enter): _handleEnter,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): _handleEnter,
        const SingleActivator(LogicalKeyboardKey.enter, control: true):
            _sendMessage,
        const SingleActivator(LogicalKeyboardKey.enter, meta: true):
            _sendMessage,
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
              (!isConnected
                  ? 'Conecta Ollama primero…'
                  : widget.busy
                      ? 'Generando… puedes escribir el siguiente mensaje'
                      : 'Escribe un mensaje…'),
          hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
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
    final canSend = _canSend && isConnected;

    return IconButton.filled(
      onPressed: canSend ? _sendMessage : null,
      tooltip: canSend ? 'Enviar mensaje (Enter)' : 'Enviando…',
      icon: const Icon(Icons.send_rounded),
    );
  }
}
