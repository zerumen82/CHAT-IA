/// Configuración para el servidor vLLM
class VllmConfig {
  /// URL base del servidor vLLM
  static String serverUrl = 'http://localhost:8000';

  /// Puerto por defecto
  static const int defaultPort = 8000;

  /// Timeout para peticiones HTTP (en segundos)
  static const int timeoutSeconds = 120;

  /// Timeout para carga de modelos (en segundos)
  static const int modelLoadTimeoutSeconds = 300;

  /// Máximo de tokens en contexto
  static const int maxContextTokens = 4096;

  /// Máximo de tokens en respuesta
  static const int maxResponseTokens = 2048;

  /// Temperatura por defecto
  static const double defaultTemperature = 0.7;

  /// Top-p por defecto
  static const double defaultTopP = 0.9;

  /// Configuración de modelos uncensored preferidos
  static const List<String> preferredUncensoredModels = [
    'dolphin-2.9-llama3-8b',
    'mistral-7b-openhermes',
    'nous-hermes-2-mixtral-8x7b',
    'wizardlm-2-8x22b',
    'dolphin-2.6-phi-2',
  ];

  /// Modelos multimodales soportados
  static const List<String> multimodalModels = [
    'llama-3.2-11b-vision',
    'pixtral-12b',
    'qwen2-vl-7b',
    'phi-3.5-vision',
  ];

  /// Directorio de modelos por defecto (relativo a la instalación)
  static String modelsDirectory = 'models';

  /// Subdirectorio para vLLM dentro de la instalación
  static const String vllmSubdir = 'vllm';

  /// Subdirectorio para modelos descargados
  static const String downloadedModelsSubdir = 'downloaded_models';

  /// Subdirectorio para caché de modelos
  static const String cacheSubdir = 'cache';

  /// Obtener URL completa para un endpoint
  static String getEndpoint(String endpoint) {
    if (endpoint.startsWith('/')) {
      return '$serverUrl$endpoint';
    }
    return '$serverUrl/$endpoint';
  }

  /// Endpoints de la API vLLM (compatible con OpenAI)
  static const String modelsEndpoint = '/v1/models';
  static const String chatCompletionsEndpoint = '/v1/chat/completions';
  static const String completionsEndpoint = '/v1/completions';
  static const String embeddingsEndpoint = '/v1/embeddings';
  static const String healthEndpoint = '/health';

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
        name.contains('vl') ||
        name.contains('pixtral');
  }

  /// Verificar si un modelo es uncensored
  static bool isUncensoredModel(String modelName) {
    final name = modelName.toLowerCase();
    return name.contains('dolphin') ||
        name.contains('openhermes') ||
        name.contains('nous-hermes') ||
        name.contains('wizardlm') ||
        name.contains('uncensored');
  }

  /// Obtener configuración de parámetros por defecto
  static Map<String, dynamic> getDefaultParameters({
    int? maxTokens,
  }) {
    return {
      'temperature': defaultTemperature,
      'top_p': defaultTopP,
      'max_tokens': maxTokens ?? maxResponseTokens,
      'frequency_penalty': 0.1,
      'presence_penalty': 0.1,
    };
  }

  /// Estructura de directorios recomendada para la instalación:
  /// LightChat/lightchat.exe - Aplicación principal
  /// LightChat/vllm/ - Motor vLLM con Python embebido
  /// LightChat/models/ - Modelos incluidos
  /// LightChat/downloaded_models/ - Modelos descargados por el usuario
  /// LightChat/cache/ - Caché de modelos HuggingFace
  /// LightChat/data/ - Datos de la aplicación
  /// LightChat/logs/ - Logs del servidor
  static const Map<String, String> installDirectories = {
    'vllm': vllmSubdir,
    'models': 'models',
    'downloaded': downloadedModelsSubdir,
    'cache': cacheSubdir,
    'data': 'data',
    'logs': 'logs',
  };
}
