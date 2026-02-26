// Modelos y estados para gestión de modelos de IA locales

/// Estado de un modelo local
enum ModelStatus {
  notInstalled,
  downloading,
  installing,
  ready,
  error,
  updating,
}

/// Tipo de modelo
enum ModelType {
  textOnly,
  multimodal,
  embedding,
}

/// Información sobre un modelo de IA local
class LocalModel {
  final String id;
  final String name;
  final String? description;
  final String? huggingFaceId;
  final String? localPath;
  final ModelStatus status;
  final ModelType type;

  /// Tamaño en bytes
  final int? sizeBytes;

  /// Tamaño formateado (ej: "4.2 GB")
  final String? sizeFormatted;

  /// VRAM requerida en GB
  final double? requiredVram;

  /// RAM mínima requerida en GB
  final double? requiredRam;

  /// Contexto máximo en tokens
  final int? maxContext;

  /// Si el modelo es uncensored
  final bool isUncensored;

  /// Si el modelo soporta imágenes
  final bool supportsImages;

  /// Progreso de descarga (0.0 - 1.0)
  final double? downloadProgress;

  /// Velocidad de descarga en MB/s
  final double? downloadSpeed;

  /// Bytes descargados
  final int? downloadedBytes;

  /// Timestamp de última actualización
  final DateTime? lastUpdated;

  /// Mensaje de error si aplica
  final String? errorMessage;

  /// Licencia del modelo
  final String? license;

  /// Autor del modelo
  final String? author;

  /// Tags/categorías del modelo
  final List<String> tags;

  /// Número de descargas en HuggingFace
  final int? downloads;

  /// Valoración media
  final double? rating;

  const LocalModel({
    required this.id,
    required this.name,
    this.description,
    this.huggingFaceId,
    this.localPath,
    this.status = ModelStatus.notInstalled,
    this.type = ModelType.textOnly,
    this.sizeBytes,
    this.sizeFormatted,
    this.requiredVram,
    this.requiredRam,
    this.maxContext,
    this.isUncensored = false,
    this.supportsImages = false,
    this.downloadProgress,
    this.downloadSpeed,
    this.downloadedBytes,
    this.lastUpdated,
    this.errorMessage,
    this.license,
    this.author,
    this.tags = const [],
    this.downloads,
    this.rating,
  });

  /// Crear una copia con campos actualizados
  LocalModel copyWith({
    String? id,
    String? name,
    String? description,
    String? huggingFaceId,
    String? localPath,
    ModelStatus? status,
    ModelType? type,
    int? sizeBytes,
    String? sizeFormatted,
    double? requiredVram,
    double? requiredRam,
    int? maxContext,
    bool? isUncensored,
    bool? supportsImages,
    double? downloadProgress,
    double? downloadSpeed,
    int? downloadedBytes,
    DateTime? lastUpdated,
    String? errorMessage,
    String? license,
    String? author,
    List<String>? tags,
    int? downloads,
    double? rating,
  }) {
    return LocalModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      huggingFaceId: huggingFaceId ?? this.huggingFaceId,
      localPath: localPath ?? this.localPath,
      status: status ?? this.status,
      type: type ?? this.type,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      sizeFormatted: sizeFormatted ?? this.sizeFormatted,
      requiredVram: requiredVram ?? this.requiredVram,
      requiredRam: requiredRam ?? this.requiredRam,
      maxContext: maxContext ?? this.maxContext,
      isUncensored: isUncensored ?? this.isUncensored,
      supportsImages: supportsImages ?? this.supportsImages,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      downloadSpeed: downloadSpeed ?? this.downloadSpeed,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      errorMessage: errorMessage ?? this.errorMessage,
      license: license ?? this.license,
      author: author ?? this.author,
      tags: tags ?? this.tags,
      downloads: downloads ?? this.downloads,
      rating: rating ?? this.rating,
    );
  }

  /// Verificar si el modelo está instalado
  bool get isInstalled => status == ModelStatus.ready;

  /// Verificar si el modelo se está descargando
  bool get isDownloading => status == ModelStatus.downloading;

  /// Verificar si hay un error
  bool get hasError => status == ModelStatus.error;

  /// Obtener icono según el tipo
  String getTypeIcon() {
    switch (type) {
      case ModelType.textOnly:
        return '📝';
      case ModelType.multimodal:
        return '📝🖼️';
      case ModelType.embedding:
        return '🔢';
    }
  }

  /// Obtener descripción del estado
  String getStatusDescription() {
    switch (status) {
      case ModelStatus.notInstalled:
        return 'No instalado';
      case ModelStatus.downloading:
        return 'Descargando... ${(downloadProgress! * 100).toStringAsFixed(1)}%';
      case ModelStatus.installing:
        return 'Instalando...';
      case ModelStatus.ready:
        return 'Listo para usar';
      case ModelStatus.error:
        return 'Error: $errorMessage';
      case ModelStatus.updating:
        return 'Actualizando...';
    }
  }

  /// Convertir a JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'huggingFaceId': huggingFaceId,
      'localPath': localPath,
      'status': status.name,
      'type': type.name,
      'sizeBytes': sizeBytes,
      'sizeFormatted': sizeFormatted,
      'requiredVram': requiredVram,
      'requiredRam': requiredRam,
      'maxContext': maxContext,
      'isUncensored': isUncensored,
      'supportsImages': supportsImages,
      'downloadProgress': downloadProgress,
      'downloadSpeed': downloadSpeed,
      'downloadedBytes': downloadedBytes,
      'lastUpdated': lastUpdated?.toIso8601String(),
      'errorMessage': errorMessage,
      'license': license,
      'author': author,
      'tags': tags,
      'downloads': downloads,
      'rating': rating,
    };
  }

  /// Crear desde JSON
  factory LocalModel.fromJson(Map<String, dynamic> json) {
    return LocalModel(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      huggingFaceId: json['huggingFaceId'] as String?,
      localPath: json['localPath'] as String?,
      status: ModelStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => ModelStatus.notInstalled,
      ),
      type: ModelType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => ModelType.textOnly,
      ),
      sizeBytes: json['sizeBytes'] as int?,
      sizeFormatted: json['sizeFormatted'] as String?,
      requiredVram: (json['requiredVram'] as num?)?.toDouble(),
      requiredRam: (json['requiredRam'] as num?)?.toDouble(),
      maxContext: json['maxContext'] as int?,
      isUncensored: json['isUncensored'] as bool? ?? false,
      supportsImages: json['supportsImages'] as bool? ?? false,
      downloadProgress: (json['downloadProgress'] as num?)?.toDouble(),
      downloadSpeed: (json['downloadSpeed'] as num?)?.toDouble(),
      downloadedBytes: json['downloadedBytes'] as int?,
      lastUpdated: json['lastUpdated'] != null
          ? DateTime.parse(json['lastUpdated'] as String)
          : null,
      errorMessage: json['errorMessage'] as String?,
      license: json['license'] as String?,
      author: json['author'] as String?,
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
      downloads: json['downloads'] as int?,
      rating: (json['rating'] as num?)?.toDouble(),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LocalModel && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'LocalModel(id: $id, name: $name, status: $status)';
}
