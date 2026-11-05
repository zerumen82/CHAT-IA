/// Configuración de proveedores de API cloud (backend opcional).
///
/// Este archivo solo declara **catálogo y endpoints** (regla NO HARDCODE de
/// AGENTS.md: las URLs viven aquí, no dispersas por el código). Las **claves
/// del usuario** nunca se escriben aquí: se guardan en SharedPreferences a
/// través de `ApiKeyStore`.
///
/// Ollama sigue siendo el backend por defecto (local-first); elegir un
/// proveedor cloud es una acción explícita del usuario.
library;

/// Adaptadores de transporte. Cada proveedor usa uno.
///
/// - [openaiCompatible]: SSE sobre `POST {base}/chat/completions`.
/// - [anthropic]: SSE sobre `POST {base}/messages`.
/// - [gemini]: SSE sobre `POST {base}/models/{modelo}:streamGenerateContent`.
/// - [aiHorde]: cola asíncrona (envío + sondeo); **no** produce streaming.
enum ApiAdapter { openaiCompatible, anthropic, gemini, aiHorde }

/// Definición estática de un proveedor del catálogo.
class ApiProvider {
  /// Identificador estable: también es la clave de `modelId` y de preferencias.
  final String id;

  /// Nombre visible en la UI.
  final String displayName;

  /// URL raíz. El adaptador añade su propio camino (`/chat/completions`…).
  final String baseUrl;

  /// Adaptador de transporte.
  final ApiAdapter adapter;

  /// Observaciones mostradas en la UI (formato de clave, avisos…).
  final String notes;

  const ApiProvider({
    required this.id,
    required this.displayName,
    required this.baseUrl,
    required this.adapter,
    this.notes = '',
  });
}

/// Catálogo de proveedores y utilidades sobre los identificadores de modelo.
class ApiConfig {
  ApiConfig._();

  /// Prefijo que distingue un modelo cloud de un modelo local de Ollama.
  static const String modelPrefix = 'api:';

  /// Contexto declarado para modelos cloud en el perfil de contexto.
  ///
  /// La VRAM no limita a un modelo remoto: se declara un valor amplio y
  /// conocido. El límite real lo fija el proveedor y lo reportará su error si
  /// se supera (nunca se promete un número que no se haya comprobado).
  static const int cloudContextTokens = 65536;

  /// Modelo sugerido por proveedor: se usa como default al importar o al
  /// dar de alta un proveedor sin escribir el modelo. Los valores son los
  /// IDs reales verificados contra el endpoint del proveedor (ver
  /// `MEMORY.md` §11). Si el proveedor no tiene sugerido, el campo queda
  /// vacío y el usuario debe escribirlo a mano.
  static const Map<String, String> suggestedModels = {
    'groq': 'openai/gpt-oss-20b',
    'mistral': 'ministral-8b-latest',
    'deepseek': 'deepseek-flash',
    'openrouter': 'deepseek/deepseek-v4.1-flash-1017',
    'huggingface': 'deepseek-ai/DeepSeek-V4.1-Flash-1017',
    'minimax': 'MiniMax-M3.1-Flash',
    'sambanova': 'DeepSeek-V3.1',
    'nvidia': 'deepseek-ai/deepseek-v4.1-flash',
    'xiaomi': 'mimo-v2.6-flash',
    'zen': 'openai/gpt-oss-20b',
    'perplexity': 'sonar-pro',
    'openai': 'gpt-4o-mini',
    'anthropic': 'claude-3-5-haiku-latest',
    'gemini': 'gemini-flash-latest',
    'moonshot': 'moonshot-v1-8k',
  };

  /// Modelo sugerido para un proveedor, o vacío si no hay.
  static String suggestedModelFor(String providerId) =>
      suggestedModels[providerId] ?? '';

  /// Clave de preferencias con el JSON de las entradas del usuario.
  static const String storeKey = 'lightchat_api_providers_v1';

  /// Alias normalizados → id del catálogo.
  ///
  /// Cubre los nombres reales de `APIS.txt` (algunos con erratas: OPENMROUTER,
  /// ANTROPIC, hugginfac, minmax, moonshopt.ai).
  static const Map<String, String> aliases = {
    'deepseek': 'deepseek',
    'gemini': 'gemini',
    'google': 'gemini',
    'openrouter': 'openrouter',
    'openmrouter': 'openrouter',
    'mistral': 'mistral',
    'xai': 'xai',
    'grok': 'xai',
    'anthropic': 'anthropic',
    'antropic': 'anthropic',
    'claude': 'anthropic',
    'openai': 'openai',
    'perplexity': 'perplexity',
    'xiaomi': 'xiaomi',
    'mimo': 'xiaomi',
    'zen': 'zen',
    'opencode': 'zen',
    'huggingface': 'huggingface',
    'hugginfac': 'huggingface',
    'hf': 'huggingface',
    'minimax': 'minimax',
    'minmax': 'minimax',
    'sambanova': 'sambanova',
    'aihorde': 'aihorde',
    'stablehorde': 'aihorde',
    'groq': 'groq',
    'nvidia': 'nvidia',
    'moonshot': 'moonshot',
    'moonshoptai': 'moonshot',
    'moonshotai': 'moonshot',
  };

  /// Catálogo completo. Sin claves: solo identidad y endpoint.
  static const List<ApiProvider> providers = [
    ApiProvider(
      id: 'deepseek',
      displayName: 'DeepSeek',
      baseUrl: 'https://api.deepseek.com/v1',
      adapter: ApiAdapter.openaiCompatible,
      notes: 'Clave con formato sk-…',
    ),
    ApiProvider(
      id: 'gemini',
      displayName: 'Google Gemini',
      baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
      adapter: ApiAdapter.gemini,
      notes: 'Clave con formato AIza… (Google AI Studio)',
    ),
    ApiProvider(
      id: 'openrouter',
      displayName: 'OpenRouter',
      baseUrl: 'https://openrouter.ai/api/v1',
      adapter: ApiAdapter.openaiCompatible,
      notes: 'El modelo se escribe como fabricante/modelo',
    ),
    ApiProvider(
      id: 'mistral',
      displayName: 'Mistral',
      baseUrl: 'https://api.mistral.ai/v1',
      adapter: ApiAdapter.openaiCompatible,
    ),
    ApiProvider(
      id: 'xai',
      displayName: 'xAI (Grok)',
      baseUrl: 'https://api.x.ai/v1',
      adapter: ApiAdapter.openaiCompatible,
    ),
    ApiProvider(
      id: 'anthropic',
      displayName: 'Anthropic (Claude)',
      baseUrl: 'https://api.anthropic.com/v1',
      adapter: ApiAdapter.anthropic,
      notes: 'Protocolo propio de Anthropic (x-api-key)',
    ),
    ApiProvider(
      id: 'openai',
      displayName: 'OpenAI',
      baseUrl: 'https://api.openai.com/v1',
      adapter: ApiAdapter.openaiCompatible,
    ),
    ApiProvider(
      id: 'perplexity',
      displayName: 'Perplexity',
      baseUrl: 'https://api.perplexity.ai',
      adapter: ApiAdapter.openaiCompatible,
      notes: 'La URL raíz no lleva /v1',
    ),
    ApiProvider(
      id: 'xiaomi',
      displayName: 'Xiaomi MiMo',
      baseUrl: 'https://api.xiaomimimo.com/v1',
      adapter: ApiAdapter.openaiCompatible,
    ),
    ApiProvider(
      id: 'zen',
      displayName: 'OpenCode Zen',
      baseUrl: 'https://opencode.ai/zen/v1',
      adapter: ApiAdapter.openaiCompatible,
      notes: 'Modelos con sufijo -free',
    ),
    ApiProvider(
      id: 'huggingface',
      displayName: 'Hugging Face',
      baseUrl: 'https://router.huggingface.co/v1',
      adapter: ApiAdapter.openaiCompatible,
      notes: 'Inference Providers (router)',
    ),
    ApiProvider(
      id: 'minimax',
      displayName: 'MiniMax',
      baseUrl: 'https://api.minimax.io/v1',
      adapter: ApiAdapter.openaiCompatible,
      notes: 'Cuentas China: cambiar a https://api.minimaxi.com/v1',
    ),
    ApiProvider(
      id: 'sambanova',
      displayName: 'SambaNova',
      baseUrl: 'https://api.sambanova.ai/v1',
      adapter: ApiAdapter.openaiCompatible,
    ),
    ApiProvider(
      id: 'aihorde',
      displayName: 'AI Horde',
      baseUrl: 'https://aihorde.net/api/v2',
      adapter: ApiAdapter.aiHorde,
      notes: 'Cola comunitaria: sin streaming y respuesta lenta. '
          'Los trabajadores son voluntarios; no usar con datos sensibles.',
    ),
    ApiProvider(
      id: 'groq',
      displayName: 'Groq',
      baseUrl: 'https://api.groq.com/openai/v1',
      adapter: ApiAdapter.openaiCompatible,
      notes: 'Clave con prefijo gsk_',
    ),
    ApiProvider(
      id: 'nvidia',
      displayName: 'NVIDIA (build.nvidia.com)',
      baseUrl: 'https://integrate.api.nvidia.com/v1',
      adapter: ApiAdapter.openaiCompatible,
      notes: 'Clave con prefijo nvapi-',
    ),
    ApiProvider(
      id: 'moonshot',
      displayName: 'Moonshot (Kimi)',
      baseUrl: 'https://api.moonshot.ai/v1',
      adapter: ApiAdapter.openaiCompatible,
    ),
  ];

  /// Devuelve el proveedor por id, o `null` si no está en el catálogo.
  static ApiProvider? byId(String id) {
    for (final provider in providers) {
      if (provider.id == id) {
        return provider;
      }
    }
    return null;
  }

  /// Resuelve un nombre escrito por el usuario (o leído de un archivo) a un id
  /// del catálogo. Devuelve `null` si no se reconoce.
  static String? resolveAlias(String rawName) {
    final normalized = rawName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (normalized.isEmpty) {
      return null;
    }
    final direct = aliases[normalized];
    if (direct != null) {
      return direct;
    }
    // Búsqueda por contenido: «AI-HORDE texto», «ANTROPIC api», etc.
    for (final entry in aliases.entries) {
      if (normalized.contains(entry.key)) {
        return entry.value;
      }
    }
    return null;
  }

  /// ¿Es este id un modelo cloud en lugar de uno de Ollama?
  static bool isApiModel(String modelId) => modelId.startsWith(modelPrefix);

  /// Construye el id de modelo selectable: `api:<proveedor>/<modelo>`.
  static String apiModelId(String providerId, String model) =>
      '$modelPrefix$providerId/$model';

  /// Descompone un id `api:<proveedor>/<modelo>`.
  /// Devuelve `null` si no cumple el formato.
  static ({String providerId, String model})? parseApiModelId(String modelId) {
    if (!isApiModel(modelId)) {
      return null;
    }
    final rest = modelId.substring(modelPrefix.length);
    final separator = rest.indexOf('/');
    if (separator <= 0 || separator == rest.length - 1) {
      return null;
    }
    return (
      providerId: rest.substring(0, separator),
      model: rest.substring(separator + 1),
    );
  }

  /// Nombre legible de un id de modelo para la UI.
  static String displayNameFor(String modelId) {
    final parsed = parseApiModelId(modelId);
    if (parsed == null) {
      return modelId;
    }
    final provider = byId(parsed.providerId);
    return '${provider?.displayName ?? parsed.providerId} · ${parsed.model}';
  }
}
