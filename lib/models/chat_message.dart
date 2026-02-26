// Tipos de contenido y modelos para mensajes de chat con soporte multimedia

/// Tipo de contenido del mensaje
enum MessageContentType {
  text,
  image,
  textWithImage,
}

/// Contenido multimedia de un mensaje
class MessageContent {
  final MessageContentType type;
  final String? text;
  final String? imageUrl;
  final String? imageBase64;
  final String? imageFormat; // jpeg, png, webp, gif

  const MessageContent({
    required this.type,
    this.text,
    this.imageUrl,
    this.imageBase64,
    this.imageFormat,
  });

  /// Crear contenido de texto
  factory MessageContent.text(String text) {
    return MessageContent(
      type: MessageContentType.text,
      text: text,
    );
  }

  /// Crear contenido de imagen desde URL
  factory MessageContent.fromUrl(String url, {String? format}) {
    return MessageContent(
      type: MessageContentType.image,
      imageUrl: url,
      imageFormat: format ?? 'jpeg',
    );
  }

  /// Crear contenido de imagen desde base64
  factory MessageContent.fromBase64(String base64, {String format = 'jpeg'}) {
    return MessageContent(
      type: MessageContentType.image,
      imageBase64: base64,
      imageFormat: format,
    );
  }

  /// Crear contenido combinado texto + imagen
  factory MessageContent.textWithImage({
    required String text,
    String? imageUrl,
    String? imageBase64,
    String imageFormat = 'jpeg',
  }) {
    return MessageContent(
      type: MessageContentType.textWithImage,
      text: text,
      imageUrl: imageUrl,
      imageBase64: imageBase64,
      imageFormat: imageFormat,
    );
  }

  /// Verificar si tiene imagen
  bool get hasImage =>
      type == MessageContentType.image ||
      type == MessageContentType.textWithImage;

  /// Verificar si tiene texto
  bool get hasText =>
      type == MessageContentType.text ||
      type == MessageContentType.textWithImage;

  /// Convertir a formato para API de vLLM/OpenAI
  Map<String, dynamic> toApiFormat() {
    switch (type) {
      case MessageContentType.text:
        return {
          'type': 'text',
          'text': text ?? '',
        };

      case MessageContentType.image:
        if (imageBase64 != null) {
          return {
            'type': 'image_url',
            'image_url': {
              'url': 'data:image/$imageFormat;base64,$imageBase64',
            },
          };
        } else if (imageUrl != null) {
          return {
            'type': 'image_url',
            'image_url': {
              'url': imageUrl,
            },
          };
        }
        return {'type': 'text', 'text': ''};

      case MessageContentType.textWithImage:
        // Para mensajes combinados, se maneja desde ChatMessage
        return {
          'type': 'text',
          'text': text ?? '',
        };
    }
  }

  /// Convertir a JSON
  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'text': text,
      'imageUrl': imageUrl,
      'imageBase64': imageBase64,
      'imageFormat': imageFormat,
    };
  }

  /// Crear desde JSON
  factory MessageContent.fromJson(Map<String, dynamic> json) {
    return MessageContent(
      type: MessageContentType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => MessageContentType.text,
      ),
      text: json['text'] as String?,
      imageUrl: json['imageUrl'] as String?,
      imageBase64: json['imageBase64'] as String?,
      imageFormat: json['imageFormat'] as String?,
    );
  }
}

/// Mensaje de chat con soporte multimedia
class ChatMessage {
  final String id;
  final String role; // 'user', 'assistant', 'system'
  final List<MessageContent> content;
  final DateTime timestamp;
  final String? model;
  final Map<String, dynamic>? metadata;
  final bool isError;
  final int? tokenCount;
  final int? imageCount;

  ChatMessage({
    String? id,
    required this.role,
    required this.content,
    DateTime? timestamp,
    this.model,
    this.metadata,
    this.isError = false,
    this.tokenCount,
    this.imageCount,
  })  : id = id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        timestamp = timestamp ?? DateTime.now();

  /// Crear mensaje de texto simple
  factory ChatMessage.text({
    required String role,
    required String text,
    String? model,
    Map<String, dynamic>? metadata,
    bool isError = false,
  }) {
    return ChatMessage(
      role: role,
      content: [MessageContent.text(text)],
      model: model,
      metadata: metadata,
      isError: isError,
    );
  }

  /// Crear mensaje de usuario con imagen
  factory ChatMessage.withImage({
    required String role,
    required String text,
    String? imageBase64,
    String? imageUrl,
    String imageFormat = 'jpeg',
    String? model,
    Map<String, dynamic>? metadata,
  }) {
    return ChatMessage(
      role: role,
      content: [
        MessageContent.textWithImage(
          text: text,
          imageBase64: imageBase64,
          imageUrl: imageUrl,
          imageFormat: imageFormat,
        ),
      ],
      model: model,
      metadata: metadata,
      imageCount: 1,
    );
  }

  /// Crear mensaje con múltiples imágenes
  factory ChatMessage.withImages({
    required String role,
    required String text,
    required List<MessageContent> images,
    String? model,
    Map<String, dynamic>? metadata,
  }) {
    final allContent = <MessageContent>[
      MessageContent.text(text),
      ...images,
    ];
    return ChatMessage(
      role: role,
      content: allContent,
      model: model,
      metadata: metadata,
      imageCount: images.length,
    );
  }

  /// Obtener texto del mensaje
  String get text {
    final textParts = content
        .where((c) => c.hasText)
        .map((c) => c.text ?? '')
        .where((t) => t.isNotEmpty);
    return textParts.join('\n');
  }

  /// Verificar si tiene imágenes
  bool get hasImages => content.any((c) => c.hasImage);

  /// Obtener solo contenido de imágenes
  List<MessageContent> get imageContent =>
      content.where((c) => c.hasImage).toList();

  /// Verificar si es del usuario
  bool get isUser => role == 'user';

  /// Verificar si es del asistente
  bool get isAssistant => role == 'assistant';

  /// Verificar si es del sistema
  bool get isSystem => role == 'system';

  /// Convertir a formato para API de vLLM/OpenAI
  Map<String, dynamic> toApiFormat() {
    if (!hasImages) {
      return {
        'role': role,
        'content': text,
      };
    }

    // Formato multimodal
    final contentList = <Map<String, dynamic>>[];

    for (final c in content) {
      if (c.hasText && c.text?.isNotEmpty == true) {
        contentList.add({
          'type': 'text',
          'text': c.text!,
        });
      }
      if (c.hasImage) {
        if (c.imageBase64 != null) {
          contentList.add({
            'type': 'image_url',
            'image_url': {
              'url':
                  'data:image/${c.imageFormat ?? "jpeg"};base64,${c.imageBase64}',
            },
          });
        } else if (c.imageUrl != null) {
          contentList.add({
            'type': 'image_url',
            'image_url': {
              'url': c.imageUrl!,
            },
          });
        }
      }
    }

    return {
      'role': role,
      'content': contentList,
    };
  }

  /// Crear una copia con campos actualizados
  ChatMessage copyWith({
    String? id,
    String? role,
    List<MessageContent>? content,
    DateTime? timestamp,
    String? model,
    Map<String, dynamic>? metadata,
    bool? isError,
    int? tokenCount,
    int? imageCount,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      model: model ?? this.model,
      metadata: metadata ?? this.metadata,
      isError: isError ?? this.isError,
      tokenCount: tokenCount ?? this.tokenCount,
      imageCount: imageCount ?? this.imageCount,
    );
  }

  /// Convertir a JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'role': role,
      'content': content.map((c) => c.toJson()).toList(),
      'timestamp': timestamp.toIso8601String(),
      'model': model,
      'metadata': metadata,
      'isError': isError,
      'tokenCount': tokenCount,
      'imageCount': imageCount,
    };
  }

  /// Crear desde JSON
  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      role: json['role'] as String,
      content: (json['content'] as List<dynamic>)
          .map((c) => MessageContent.fromJson(c as Map<String, dynamic>))
          .toList(),
      timestamp: DateTime.parse(json['timestamp'] as String),
      model: json['model'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
      isError: json['isError'] as bool? ?? false,
      tokenCount: json['tokenCount'] as int?,
      imageCount: json['imageCount'] as int?,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ChatMessage && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'ChatMessage(id: $id, role: $role, hasImages: $hasImages)';
}
