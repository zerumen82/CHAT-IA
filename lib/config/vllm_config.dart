/// Configuración para Ollama (anteriormente vLLM)
class OllamaConfig {
  /// URL base del servidor Ollama
  static String serverUrl = 'http://localhost:11434';

  /// Puerto por defecto
  static const int defaultPort = 11434;

  /// Timeout para peticiones HTTP (en segundos)
  static const int timeoutSeconds = 120;

  /// Timeout para carga de modelos (en segundos)
  static const int modelLoadTimeoutSeconds = 300;

  /// Máximo de tokens en contexto.
  ///
  /// Se usa siempre el mismo valor (también sin documentos) porque Ollama
  /// recarga el modelo cuando cambia `num_ctx`, lo que cuesta varios segundos.
  static const int maxContextTokens = 8192;

  /// Alias histórico del contexto ampliado para documentos.
  static const int documentContextTokens = maxContextTokens;

  /// Máximo de tokens en respuesta
  static const int maxResponseTokens = 2048;

  /// Temperatura por defecto
  static const double defaultTemperature = 0.7;

  /// Temperatura para preguntas sobre documentos: menos inventiva, más exacta.
  static const double documentTemperature = 0.2;

  /// Top-p por defecto
  static const double defaultTopP = 0.9;

  /// Modelos Ollama preferidos
  static const List<String> preferredModels = [
    'llama3.2',
    'mistral',
    'codellama',
    'phi3',
    'qwen2.5',
  ];

  /// Modelos multimodales soportados (soporte de imágenes)
  static const List<String> multimodalModels = [
    'llava',
    'llama3.2-vision',
    'bakllava',
    'qwen2-vl',
  ];

  /// Directorio de modelos por defecto
  static String modelsDirectory = 'models';

  /// Subdirectorio para Ollama
  static const String ollamaSubdir = 'ollama';

  /// Subdirectorio para modelos descargados
  static const String downloadedModelsSubdir = 'downloaded_models';

  /// Subdirectorio para caché
  static const String cacheSubdir = 'cache';

  /// Obtener URL completa para un endpoint
  static String getEndpoint(String endpoint) {
    if (endpoint.startsWith('/')) {
      return '$serverUrl$endpoint';
    }
    return '$serverUrl/$endpoint';
  }

  /// Endpoints de la API Ollama
  static const String modelsEndpoint = '/api/tags';
  static const String chatCompletionsEndpoint = '/api/chat';
  static const String completionsEndpoint = '/api/generate';
  static const String embeddingsEndpoint = '/api/embeddings';
  static const String healthEndpoint = '/';

  /// Configuración de reintentos
  static const int maxRetries = 3;
  static const Duration retryDelay = Duration(seconds: 2);

  /// Configuración de caché de modelos
  static const Duration modelCacheExpiry = Duration(hours: 24);

  /// Verificar si un modelo es multimodal
  static bool isMultimodalModel(String modelName) {
    final name = modelName.toLowerCase();
    return multimodalModels.any((m) => name.contains(m.toLowerCase())) ||
        name.contains('vision') ||
        name.contains('llava') ||
        name.contains('vl');
  }

  /// Verificar si el modelo es una variante sin censura (abliterated,
  /// uncensored o Dolphin).
  static bool isUncensoredModel(String modelName) {
    final name = modelName.toLowerCase();
    return name.contains('uncensored') ||
        name.contains('abliterated') ||
        name.contains('abliterate') ||
        name.contains('dolphin');
  }

  /// Modelos que razonan antes de responder. Se les envía `think: false`
  /// para que no gasten el presupuesto de tokens pensando y devuelvan vacío.
  static bool isThinkingModel(String modelName) {
    final name = modelName.toLowerCase();
    return name.contains('qwen3') ||
        name.contains('deepseek-r1') ||
        name.contains('reasoner') ||
        name.contains('thinking');
  }

  /// Verificar si es un modelo de código
  static bool isCodeModel(String modelName) {
    final name = modelName.toLowerCase();
    return name.contains('codellama') ||
        name.contains('code') ||
        name.contains('deepseek-coder');
  }

  /// Obtener configuración de parámetros por defecto
  static Map<String, dynamic> getDefaultParameters({
    int? maxTokens,
  }) {
    return {
      'temperature': defaultTemperature,
      'top_p': defaultTopP,
      'num_predict': maxTokens ?? maxResponseTokens,
    };
  }

  /// Estructura de directorios para instalación:
  /// LightChat/lightchat.exe - Aplicación principal
  /// LightChat/ollama/ - Modelos Ollama
  /// LightChat/models/ - Modelos incluidos
  /// LightChat/data/ - Datos de la aplicación
  static const Map<String, String> installDirectories = {
    'ollama': ollamaSubdir,
    'models': 'models',
    'downloaded': downloadedModelsSubdir,
    'cache': cacheSubdir,
    'data': 'data',
    'logs': 'logs',
  };
}

// Alias para compatibilidad hacia atrás
typedef VllmConfig = OllamaConfig;
