import '../config/document_config.dart';

/// Tipo de documento admitido como adjunto.
enum DocumentKind {
  pdf,
  spreadsheet,
  presentation,
  text,
}

/// Documento adjunto a un mensaje, con el texto extraído para el modelo.
class DocumentAttachment {
  final String path;
  final String name;
  final DocumentKind kind;
  final int sizeBytes;

  /// Texto extraído (puede estar recortado por límite de contexto).
  final String? text;

  /// Longitud del texto original antes de recortarlo.
  final int originalChars;

  /// True si el texto se recortó por límite de contexto.
  final bool truncated;

  /// Mensaje de error si no se pudo leer el documento.
  final String? error;

  /// True mientras se está extrayendo el texto.
  final bool isLoading;

  /// Identificador del contenido conservado fuera del JSON de la conversación.
  final String? storageId;

  /// Extracción completa temporal/hidratada. Nunca se serializa en preferencias.
  final String? extractedText;

  /// Pérdida real durante extracción, distinta de la vista previa recortada.
  final bool extractionTruncated;

  const DocumentAttachment({
    required this.path,
    required this.name,
    required this.kind,
    required this.sizeBytes,
    this.text,
    this.originalChars = 0,
    this.truncated = false,
    this.error,
    this.isLoading = false,
    this.storageId,
    this.extractedText,
    this.extractionTruncated = false,
  });

  bool get isReady =>
      !isLoading && error == null && (text?.trim().isNotEmpty ?? false);

  int get charCount => text?.length ?? 0;

  String get sizeFormatted {
    if (sizeBytes >= 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (sizeBytes >= 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$sizeBytes bytes';
  }

  DocumentAttachment copyWith({
    String? path,
    String? name,
    DocumentKind? kind,
    int? sizeBytes,
    String? text,
    int? originalChars,
    bool? truncated,
    String? error,
    bool? isLoading,
    bool clearError = false,
    String? storageId,
    String? extractedText,
    bool? extractionTruncated,
    bool clearExtractedText = false,
  }) {
    return DocumentAttachment(
      path: path ?? this.path,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      text: text ?? this.text,
      originalChars: originalChars ?? this.originalChars,
      truncated: truncated ?? this.truncated,
      error: clearError ? null : (error ?? this.error),
      isLoading: isLoading ?? this.isLoading,
      storageId: storageId ?? this.storageId,
      extractedText:
          clearExtractedText ? null : extractedText ?? this.extractedText,
      extractionTruncated: extractionTruncated ?? this.extractionTruncated,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'path': path,
      'name': name,
      'kind': kind.name,
      'sizeBytes': sizeBytes,
      'text': storageId != null &&
              (text?.length ?? 0) > DocumentConfig.persistedPreviewChars
          ? text!.substring(0, DocumentConfig.persistedPreviewChars)
          : text,
      'originalChars': originalChars,
      'truncated': truncated,
      'error': error,
      'storageId': storageId,
      'extractionTruncated': extractionTruncated,
    };
  }

  factory DocumentAttachment.fromJson(Map<String, dynamic> json) {
    return DocumentAttachment(
      path: json['path'] as String? ?? '',
      name: json['name'] as String? ?? 'documento',
      kind: DocumentKind.values.firstWhere(
        (kind) => kind.name == json['kind'],
        orElse: () => DocumentKind.text,
      ),
      sizeBytes: json['sizeBytes'] as int? ?? 0,
      text: json['text'] as String?,
      originalChars: json['originalChars'] as int? ?? 0,
      truncated: json['truncated'] as bool? ?? false,
      error: json['error'] as String?,
      storageId: json['storageId'] as String?,
      extractionTruncated: json['extractionTruncated'] as bool? ??
          (json['storageId'] == null && (json['truncated'] as bool? ?? false)),
    );
  }

  @override
  String toString() =>
      'DocumentAttachment(name: $name, kind: ${kind.name}, chars: $charCount)';
}
