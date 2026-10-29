import 'document_attachment.dart';
import 'generated_file.dart';

/// Modelo de mensaje con soporte multimodal (texto + imágenes + documentos)
class Message {
  final String text;
  final bool isUser;
  final bool isError;
  final DateTime timestamp;
  final String? model;
  final Map<String, dynamic>? metadata;
  final int? tokenCount;
  final List<GeneratedFile> generatedFiles;

  // Soporte para imágenes
  final List<MessageImage>? images;
  final bool hasImages;

  // Soporte para documentos adjuntos (PDF, Excel, texto)
  final List<DocumentAttachment>? documents;
  final bool hasDocuments;

  Message({
    required this.text,
    required this.isUser,
    this.isError = false,
    required this.timestamp,
    this.model,
    this.metadata,
    this.tokenCount,
    this.images,
    this.documents,
    this.generatedFiles = const [],
  })  : hasImages = images != null && images.isNotEmpty,
        hasDocuments = documents != null && documents.isNotEmpty;

  /// Crear mensaje de solo texto
  factory Message.text({
    required String text,
    required bool isUser,
    bool isError = false,
    required DateTime timestamp,
    String? model,
    Map<String, dynamic>? metadata,
    int? tokenCount,
  }) {
    return Message(
      text: text,
      isUser: isUser,
      isError: isError,
      timestamp: timestamp,
      model: model,
      metadata: metadata,
      tokenCount: tokenCount,
    );
  }

  /// Crear mensaje con imágenes
  factory Message.withImages({
    required String text,
    required bool isUser,
    required DateTime timestamp,
    required List<MessageImage> images,
    String? model,
    Map<String, dynamic>? metadata,
  }) {
    return Message(
      text: text,
      isUser: isUser,
      timestamp: timestamp,
      images: images,
      model: model,
      metadata: metadata,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'isUser': isUser,
      'isError': isError,
      'timestamp': timestamp.toIso8601String(),
      'model': model,
      'metadata': metadata == null
          ? null
          : {
              for (final entry in metadata!.entries)
                if (entry.key != 'contextText' && entry.key != 'sentDocuments')
                  entry.key: entry.value,
            },
      'tokenCount': tokenCount,
      'images': images?.map((i) => i.toJson()).toList(),
      'documents': documents?.map((d) => d.toJson()).toList(),
      'generatedFiles': generatedFiles.map((file) => file.toJson()).toList(),
    };
  }

  factory Message.fromJson(Map<String, dynamic> json) {
    List<MessageImage>? imagesList;
    if (json['images'] != null) {
      imagesList = (json['images'] as List)
          .map((i) => MessageImage.fromJson(i as Map<String, dynamic>))
          .toList();
    }

    List<DocumentAttachment>? documentsList;
    if (json['documents'] != null) {
      documentsList = (json['documents'] as List)
          .map((d) => DocumentAttachment.fromJson(d as Map<String, dynamic>))
          .toList();
    }

    return Message(
      text: json['text'],
      isUser: json['isUser'],
      isError: json['isError'] ?? false,
      timestamp: DateTime.parse(json['timestamp']),
      model: json['model'],
      metadata: json['metadata'],
      tokenCount: json['tokenCount'],
      images: imagesList,
      documents: documentsList,
      generatedFiles: (json['generatedFiles'] as List? ?? const [])
          .map((file) =>
              GeneratedFile.fromJson(Map<String, dynamic>.from(file as Map)))
          .toList(),
    );
  }

  /// Crear una copia con campos actualizados
  Message copyWith({
    String? text,
    bool? isUser,
    bool? isError,
    DateTime? timestamp,
    String? model,
    Map<String, dynamic>? metadata,
    int? tokenCount,
    List<MessageImage>? images,
    List<DocumentAttachment>? documents,
    List<GeneratedFile>? generatedFiles,
  }) {
    return Message(
      text: text ?? this.text,
      isUser: isUser ?? this.isUser,
      isError: isError ?? this.isError,
      timestamp: timestamp ?? this.timestamp,
      model: model ?? this.model,
      metadata: metadata ?? this.metadata,
      tokenCount: tokenCount ?? this.tokenCount,
      images: images ?? this.images,
      documents: documents ?? this.documents,
      generatedFiles: generatedFiles ?? this.generatedFiles,
    );
  }

  @override
  String toString() {
    return 'Message(text: ${text.length > 50 ? '${text.substring(0, 50)}...' : text}, '
        'isUser: $isUser, hasImages: $hasImages, '
        'hasDocuments: $hasDocuments, timestamp: $timestamp)';
  }
}

/// Imagen asociada a un mensaje
class MessageImage {
  final String id;
  final String? localPath;
  final String? base64Data;
  final String? url;
  final int width;
  final int height;
  final int sizeBytes;
  final String mimeType;
  final String? caption;

  const MessageImage({
    required this.id,
    this.localPath,
    this.base64Data,
    this.url,
    required this.width,
    required this.height,
    required this.sizeBytes,
    this.mimeType = 'image/jpeg',
    this.caption,
  });

  /// Verificar si la imagen tiene datos locales
  bool get hasLocalData => localPath != null || base64Data != null;

  /// Verificar si la imagen tiene URL remota
  bool get hasRemoteUrl => url != null;

  /// Obtener tamaño formateado
  String get sizeFormatted {
    if (sizeBytes >= 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else if (sizeBytes >= 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$sizeBytes bytes';
  }

  /// Aspect ratio de la imagen
  double get aspectRatio => width / height;

  /// Si la imagen es horizontal
  bool get isLandscape => width > height;

  /// Si la imagen es vertical
  bool get isPortrait => height > width;

  /// Si la imagen es cuadrada
  bool get isSquare => width == height;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'localPath': localPath,
      'base64Data': base64Data,
      'url': url,
      'width': width,
      'height': height,
      'sizeBytes': sizeBytes,
      'mimeType': mimeType,
      'caption': caption,
    };
  }

  factory MessageImage.fromJson(Map<String, dynamic> json) {
    return MessageImage(
      id: json['id'] as String,
      localPath: json['localPath'] as String?,
      base64Data: json['base64Data'] as String?,
      url: json['url'] as String?,
      width: json['width'] as int,
      height: json['height'] as int,
      sizeBytes: json['sizeBytes'] as int,
      mimeType: json['mimeType'] as String? ?? 'image/jpeg',
      caption: json['caption'] as String?,
    );
  }

  /// Crear copia con campos actualizados
  MessageImage copyWith({
    String? id,
    String? localPath,
    String? base64Data,
    String? url,
    int? width,
    int? height,
    int? sizeBytes,
    String? mimeType,
    String? caption,
  }) {
    return MessageImage(
      id: id ?? this.id,
      localPath: localPath ?? this.localPath,
      base64Data: base64Data ?? this.base64Data,
      url: url ?? this.url,
      width: width ?? this.width,
      height: height ?? this.height,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      mimeType: mimeType ?? this.mimeType,
      caption: caption ?? this.caption,
    );
  }

  @override
  String toString() {
    return 'MessageImage(id: $id, size: ${width}x$height, bytes: $sizeFormatted)';
  }
}
