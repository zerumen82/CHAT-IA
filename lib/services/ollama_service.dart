import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/chat_config.dart';

/// Estado del servidor Ollama
enum OllamaStatus {
  notInstalled,
  installing,
  installed,
  starting,
  running,
  stopping,
  error,
}

/// Información del modelo Ollama
class OllamaModel {
  final String name;
  final String? digest;
  final int? size;
  final DateTime? modifiedAt;
  final String? details;

  OllamaModel({
    required this.name,
    this.digest,
    this.size,
    this.modifiedAt,
    this.details,
  });

  factory OllamaModel.fromJson(Map<String, dynamic> json) {
    return OllamaModel(
      name: json['name'] ?? json['model'] ?? '',
      digest: json['digest'],
      size: json['size'],
      modifiedAt: json['modified_at'] != null
          ? DateTime.tryParse(json['modified_at'])
          : null,
      details: json['details'] != null ? jsonEncode(json['details']) : null,
    );
  }

  /// Formatear tamaño a legible
  String get sizeFormatted {
    if (size == null) return 'Unknown';
    final bytes = size!;
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// Nombre corto (sin tag)
  String get shortName => name.split(':').first;

  /// Tag del modelo
  String get tag {
    final parts = name.split(':');
    return parts.length > 1 ? parts[1] : 'latest';
  }
}

/// Información del servidor Ollama
class OllamaServerInfo {
  final OllamaStatus status;
  final String? version;
  final String? errorMessage;
  final int port;

  const OllamaServerInfo({
    required this.status,
    this.version,
    this.errorMessage,
    this.port = 11434,
  });

  OllamaServerInfo copyWith({
    OllamaStatus? status,
    String? version,
    String? errorMessage,
    int? port,
  }) {
    return OllamaServerInfo(
      status: status ?? this.status,
      version: version ?? this.version,
      errorMessage: errorMessage ?? this.errorMessage,
      port: port ?? this.port,
    );
  }
}

/// Respuesta de generación de chat
class OllamaChatResponse {
  final String message;
  final bool done;
  final String thinking;
  final String? doneReason;
  final int? evalDuration;
  final int? totalDuration;
  final int? loadDuration;
  final int? promptEvalCount;
  final int? evalCount;
  final List<Map<String, dynamic>> toolCalls;

  OllamaChatResponse({
    required this.message,
    required this.done,
    this.thinking = '',
    this.doneReason,
    this.evalDuration,
    this.totalDuration,
    this.loadDuration,
    this.promptEvalCount,
    this.evalCount,
    this.toolCalls = const [],
  });

  factory OllamaChatResponse.fromJson(Map<String, dynamic> json) {
    return OllamaChatResponse(
      message: json['message']?['content'] ?? json['response'] ?? '',
      done: json['done'] ?? false,
      thinking: json['message']?['thinking'] ?? json['thinking'] ?? '',
      doneReason: json['done_reason'],
      evalDuration: json['eval_duration'],
      totalDuration: json['total_duration'],
      loadDuration: json['load_duration'],
      promptEvalCount: json['prompt_eval_count'],
      evalCount: json['eval_count'],
      toolCalls: (json['message']?['tool_calls'] as List? ?? const [])
          .map((call) => Map<String, dynamic>.from(call as Map))
          .toList(),
    );
  }
}

/// Mensaje para el chat
class OllamaMessage {
  final String role;
  final String content;
  final List<OllamaImage>? images;

  OllamaMessage({
    required this.role,
    required this.content,
    this.images,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'role': role,
      'content': content,
    };
    if (images != null && images!.isNotEmpty) {
      map['images'] = images!.map((i) => i.base64Data).toList();
    }
    return map;
  }
}

/// Imagen para mensaje multimodal
class OllamaImage {
  final String base64Data;

  OllamaImage(this.base64Data);

  factory OllamaImage.fromBytes(List<int> bytes) {
    return OllamaImage(base64Encode(bytes));
  }
}

/// Servicio para gestionar Ollama
/// SINGLETON: El estado persiste durante la sesión
class OllamaService extends ChangeNotifier {
  static OllamaService? _instance;

  static const String _defaultHost = 'localhost';
  static const int _defaultPort = 11434;
  static const String _ollamaModelsApi = 'https://ollama.com/search';
  static const int _catalogPageSize = 20;
  static const int _catalogMaxPages = 50;

  final http.Client _catalogClient;
  final Uri _catalogUri;

  OllamaServerInfo _serverInfo = const OllamaServerInfo(
    status: OllamaStatus.notInstalled,
  );
  OllamaServerInfo get serverInfo => _serverInfo;

  List<OllamaModel> _models = [];
  List<OllamaModel> get models => _models;

  // Flag para saber si ya se inicializó
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  // Flag de carga
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  // Estado de descarga
  bool _isPulling = false;
  bool get isPulling => _isPulling;
  String? _pullingModel;
  String? get pullingModel => _pullingModel;
  double _pullProgress = 0.0;
  double get pullProgress => _pullProgress;

  // Configuración
  String _host = _defaultHost;
  int _port = _defaultPort;

  // Timer para health check
  Timer? _healthCheckTimer;

  // Logs
  final List<String> _logs = [];
  late final List<String> _logsView = UnmodifiableListView(_logs);
  List<String> get logs => _logsView;

  // Proceso que arrancó LightChat (null si el servidor ya estaba corriendo).
  Process? _serverProcess;

  OllamaService._()
      : _catalogClient = http.Client(),
        _catalogUri = Uri.parse(_ollamaModelsApi);

  @visibleForTesting
  OllamaService.forTesting({
    required http.Client catalogClient,
    required Uri catalogUri,
  })  : _catalogClient = catalogClient,
        _catalogUri = catalogUri;

  static OllamaService get instance {
    _instance ??= OllamaService._();
    return _instance!;
  }

  /// URL base de la API
  String get baseUrl => 'http://$_host:$_port';

  /// Inicializar servicio
  Future<void> initialize() async {
    if (_isInitialized) return;

    _isLoading = true;
    notifyListeners();

    try {
      // Cargar configuración guardada
      await _loadConfig();

      // Verificar si Ollama está instalado y corriendo
      await checkInstallation();

      // Sondeo único: también reintenta si Ollama aún no estaba corriendo.
      _startHealthCheck();

      _isInitialized = true;
      _addLog('OllamaService inicializado');
    } catch (e) {
      _addLog('Error inicializando: $e');
      _serverInfo = OllamaServerInfo(
        status: OllamaStatus.error,
        errorMessage: 'Error al inicializar: $e',
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Cargar configuración
  Future<void> _loadConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _host = prefs.getString('ollama_host') ?? _defaultHost;
      _port = prefs.getInt('ollama_port') ?? _defaultPort;
    } catch (e) {
      debugPrint('Error cargando config: $e');
    }
  }

  /// Guardar configuración
  Future<void> saveConfig({String? host, int? port}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (host != null) {
        _host = host;
        await prefs.setString('ollama_host', host);
      }
      if (port != null) {
        _port = port;
        await prefs.setInt('ollama_port', port);
      }
      notifyListeners();
      _addLog('Configuración guardada: $baseUrl');
    } catch (e) {
      debugPrint('Error guardando config: $e');
    }
  }

  /// Verificar instalación de Ollama
  Future<void> checkInstallation() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/tags'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        // Ollama está corriendo
        final data = json.decode(response.body);
        final modelsList = (data['models'] as List<dynamic>? ?? []);
        _models = modelsList
            .map((m) => OllamaModel.fromJson(m as Map<String, dynamic>))
            .toList();

        _serverInfo = OllamaServerInfo(
          status: OllamaStatus.running,
          version: await _getVersion(),
        );

        _startHealthCheck();
        _addLog('Ollama detectado en $baseUrl');
        _addLog('${_models.length} modelos disponibles');
      } else {
        _models = [];
        _serverInfo = _parseHttpError(response.statusCode, baseUrl);
      }
    } on SocketException {
      _models = [];
      _serverInfo = OllamaServerInfo(
        status: OllamaStatus.notInstalled,
        errorMessage: 'Ollama no está corriendo en $baseUrl',
      );
    } on TimeoutException {
      _models = [];
      _serverInfo = const OllamaServerInfo(
        status: OllamaStatus.notInstalled,
        errorMessage: 'Timeout conectando a Ollama',
      );
    } catch (e) {
      _models = [];
      _serverInfo = OllamaServerInfo(
        status: OllamaStatus.error,
        errorMessage: 'Error: $e',
      );
    }
    notifyListeners();
  }

  /// Parsear código de estado HTTP a información de servidor
  OllamaServerInfo _parseHttpError(int statusCode, String baseUrl) {
    switch (statusCode) {
      case 401:
        return OllamaServerInfo(
          status: OllamaStatus.error,
          errorMessage: 'No autorizado: verifica autenticación en $baseUrl',
        );
      case 403:
        return OllamaServerInfo(
          status: OllamaStatus.error,
          errorMessage: 'Acceso denegado a $baseUrl',
        );
      case 404:
        return const OllamaServerInfo(
          status: OllamaStatus.notInstalled,
          errorMessage: 'API de Ollama no encontrada (¿versión incompatible?)',
        );
      case 500:
        return OllamaServerInfo(
          status: OllamaStatus.error,
          errorMessage: 'Error interno del servidor Ollama',
        );
      case 502:
        return OllamaServerInfo(
          status: OllamaStatus.notInstalled,
          errorMessage: 'Bad gateway: Ollama no responde correctamente',
        );
      case 503:
        return OllamaServerInfo(
          status: OllamaStatus.notInstalled,
          errorMessage: 'Servicio no disponible: Ollama no está corriendo',
        );
      default:
        return OllamaServerInfo(
          status: OllamaStatus.error,
          errorMessage: 'Error HTTP $statusCode conectando a $baseUrl',
        );
    }
  }

  /// Obtener versión de Ollama
  Future<String?> _getVersion() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/version'))
          .timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['version']?.toString();
      }
    } catch (e) {
      debugPrint('Error obteniendo versión: $e');
    }
    return null;
  }

  /// Iniciar health check periódico
  void _startHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      await _doHealthCheck();
    });
  }

  /// Health check
  Future<void> _doHealthCheck() async {
    // Si el servidor no está disponible, reintentar la conexión completa.
    if (_serverInfo.status != OllamaStatus.running) {
      await checkInstallation();
      return;
    }

    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/tags'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200 &&
          _serverInfo.status != OllamaStatus.running) {
        await checkInstallation();
      } else if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final modelsList = data['models'] as List<dynamic>? ?? [];
        final models = modelsList
            .map((model) => OllamaModel.fromJson(model as Map<String, dynamic>))
            .toList();
        if (!listEquals(
          models.map((model) => model.name).toList(),
          _models.map((model) => model.name).toList(),
        )) {
          _models = models;
          notifyListeners();
        }
      } else if (_serverInfo.status == OllamaStatus.running) {
        _models = [];
        _serverInfo = _serverInfo.copyWith(status: OllamaStatus.error);
        notifyListeners();
      }
    } catch (e) {
      if (_serverInfo.status == OllamaStatus.running) {
        _models = [];
        _serverInfo = _serverInfo.copyWith(status: OllamaStatus.error);
        notifyListeners();
      }
    }
  }

  /// Descargar/pull un modelo
  Future<bool> pullModel(String modelName) async {
    if (_isPulling) return false;

    _isPulling = true;
    _pullingModel = modelName;
    _pullProgress = 0.0;
    notifyListeners();

    _addLog('Descargando modelo: $modelName...');

    try {
      final request = http.Request('POST', Uri.parse('$baseUrl/api/pull'));
      request.headers['Content-Type'] = 'application/json';
      request.body = json.encode({'name': modelName, 'stream': true});

      final response = await request.send();

      if (response.statusCode == 200) {
        await for (final chunk in response.stream.transform(utf8.decoder)) {
          final lines = chunk.split('\n');
          for (final line in lines) {
            if (line.trim().isEmpty) continue;
            try {
              final data = json.decode(line);
              if (data['status'] == 'pulling') {
                final completed = data['completed'];
                final total = data['total'];
                if (completed != null && total != null) {
                  _pullProgress = completed / total;
                  notifyListeners();
                }
              } else if (data['status'] == 'success') {
                _pullProgress = 1.0;
                _addLog('Modelo $modelName descargado correctamente');
              } else {
                _addLog(data['status'] ?? line);
              }
            } catch (_) {
              // Ignorar líneas que no son JSON
            }
          }
        }

        // Actualizar lista de modelos
        await checkInstallation();
        return true;
      } else {
        _addLog('Error descargando modelo: HTTP ${response.statusCode}');
        return false;
      }
    } catch (e) {
      _addLog('Error descargando modelo: $e');
      return false;
    } finally {
      _isPulling = false;
      _pullingModel = null;
      _pullProgress = 0.0;
      notifyListeners();
    }
  }

  /// Eliminar un modelo
  Future<bool> deleteModel(String modelName) async {
    try {
      final response = await http
          .delete(
            Uri.parse('$baseUrl/api/delete'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'name': modelName}),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        _addLog('Modelo $modelName eliminado');
        await checkInstallation();
        return true;
      } else {
        _addLog('Error eliminando modelo: HTTP ${response.statusCode}');
        return false;
      }
    } catch (e) {
      _addLog('Error eliminando modelo: $e');
      return false;
    }
  }

  /// Cada petición posee su cliente: cancelar cierra también la conexión HTTP.
  Stream<OllamaChatResponse> generateChat({
    required String model,
    required List<OllamaMessage> messages,
    double? temperature,
    int? numPredict,
    int? numCtx,
    bool? think,
    List<Map<String, dynamic>>? tools,
    Future<void>? cancellation,
    Duration connectionTimeout = ChatConfig.connectionTimeout,
    Duration inactivityTimeout = ChatConfig.inactivityTimeout,
  }) async* {
    final client = http.Client();
    var cancelled = false;
    try {
      final request = http.Request('POST', Uri.parse('$baseUrl/api/chat'));
      request.headers['Content-Type'] = 'application/json';
      request.body = json.encode({
        'model': model,
        'messages': messages.map((m) => m.toJson()).toList(),
        'stream': true,
        if (think != null) 'think': think,
        if (tools != null && tools.isNotEmpty) 'tools': tools,
        'options': {
          if (temperature != null) 'temperature': temperature,
          if (numPredict != null) 'num_predict': numPredict,
          if (numCtx != null) 'num_ctx': numCtx,
        },
      });
      final sending = client.send(request).timeout(connectionTimeout,
          onTimeout: () => throw TimeoutException(
              'Ollama no respondió al iniciar la petición.',
              connectionTimeout));
      final abort = cancellation?.then<http.StreamedResponse>((_) {
        cancelled = true;
        client.close();
        throw const HttpException('Petición cancelada');
      });
      final response = await (abort == null
          ? sending
          : Future.any<http.StreamedResponse>([sending, abort]));
      if (cancelled) {
        return;
      }
      if (response.statusCode != HttpStatus.ok) {
        final body = <int>[];
        await for (final chunk in response.stream.timeout(inactivityTimeout)) {
          final remaining = ChatConfig.maxErrorBodyBytes - body.length;
          body.addAll(chunk.take(remaining));
          if (body.length >= ChatConfig.maxErrorBodyBytes) {
            break;
          }
        }
        var detail = utf8.decode(body, allowMalformed: true).trim();
        try {
          final decoded = jsonDecode(detail);
          if (decoded is Map && decoded['error'] != null) {
            detail = decoded['error'].toString();
          }
        } on FormatException {
          // Un servidor puede devolver un error de texto, no JSON.
        }
        throw HttpException('HTTP ${response.statusCode}'
            '${detail.isEmpty ? '' : ': $detail'}');
      }
      var receivedDone = false;
      await for (final line in response.stream
          .timeout(inactivityTimeout)
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (cancelled) {
          return;
        }
        if (line.trim().isEmpty) {
          continue;
        }
        final data = json.decode(line) as Map<String, dynamic>;
        if (data['error'] != null) {
          throw StateError(data['error'].toString());
        }
        final item = OllamaChatResponse.fromJson(data);
        yield item;
        if (item.done) {
          receivedDone = true;
          break;
        }
      }
      if (!cancelled && !receivedDone) {
        throw const HttpException(
            'La conexión terminó antes de confirmar la respuesta completa.');
      }
    } catch (error) {
      if (!cancelled) {
        _addLog('Error en generateChat: $error');
        rethrow;
      }
    } finally {
      client.close();
    }
  }

  /// Generar respuesta simple (non-streaming)
  Future<OllamaChatResponse> generate({
    required String model,
    required String prompt,
    double? temperature,
    int? numPredict,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/generate'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'model': model,
              'prompt': prompt,
              'stream': false,
              'options': {
                if (temperature != null) 'temperature': temperature,
                if (numPredict != null) 'num_predict': numPredict,
              },
            }),
          )
          .timeout(const Duration(seconds: 120));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return OllamaChatResponse.fromJson(data);
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      _addLog('Error en generate: $e');
      rethrow;
    }
  }

  /// Obtener información de un modelo
  Future<Map<String, dynamic>?> showModel(String modelName) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/show'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'name': modelName}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('Error mostrando modelo: $e');
    }
    return null;
  }

  /// Añadir log
  void _addLog(String message) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 19);
    _logs.add('[$timestamp] $message');
    // Mantener solo últimos 100 logs
    if (_logs.length > 100) {
      _logs.removeAt(0);
    }
    notifyListeners();
  }

  /// Limpiar logs
  void clearLogs() {
    _logs.clear();
    _addLog('Registros limpiados por el usuario');
  }

  /// Modelos publicados en el catálogo oficial de Ollama.
  List<Map<String, dynamic>> _availableModels = [];
  List<Map<String, dynamic>> get availableModels => _availableModels;
  bool _isLoadingAvailableModels = false;
  bool get isLoadingAvailableModels => _isLoadingAvailableModels;
  String? _availableModelsError;
  String? get availableModelsError => _availableModelsError;

  /// Timestamp de última actualización del catálogo remoto
  DateTime? _availableModelsLastUpdate;
  DateTime? get availableModelsLastUpdate => _availableModelsLastUpdate;

  /// Cargar el catálogo local de Ollama, sin perder datos si falla la red.
  Future<List<Map<String, dynamic>>> fetchAvailableModels({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh &&
        _availableModels.isNotEmpty &&
        _availableModelsLastUpdate != null &&
        DateTime.now().difference(_availableModelsLastUpdate!).inHours < 1) {
      return _availableModels;
    }
    if (_isLoadingAvailableModels && !forceRefresh) {
      return _availableModels;
    }

    _isLoadingAvailableModels = true;
    _availableModelsError = null;
    _addLog('Consultando el catálogo de modelos de Ollama...');

    try {
      final firstPage = await _fetchCatalogPage(1);
      final pageCount = _parseCatalogPageCount(firstPage.body);
      final results = parseAvailableModels(firstPage.body);
      if (pageCount == null && results.length >= _catalogPageSize) {
        throw const FormatException(
          'No se pudo determinar cuántas páginas tiene el catálogo de Ollama.',
        );
      }
      final lastPage = pageCount ?? 1;

      for (var firstPageNumber = 2;
          firstPageNumber <= lastPage;
          firstPageNumber += 4) {
        final requests = <Future<http.Response>>[];
        for (var page = firstPageNumber;
            page <= lastPage && page < firstPageNumber + 4;
            page++) {
          requests.add(_fetchCatalogPage(page));
        }
        for (final response in await Future.wait(requests)) {
          results.addAll(parseAvailableModels(response.body));
        }
      }

      if (results.isEmpty) {
        throw const FormatException(
          'La búsqueda de Ollama no contiene modelos locales.',
        );
      }

      _availableModels = {
        for (final model in results) model['name'] as String: model,
      }.values.toList();
      _availableModelsLastUpdate = DateTime.now();
      _addLog('${_availableModels.length} modelos cargados desde Ollama.');
    } catch (e) {
      _availableModelsError =
          'No se pudo cargar el catálogo oficial de Ollama: $e';
      _addLog(_availableModelsError!);
    } finally {
      _isLoadingAvailableModels = false;
      notifyListeners();
    }

    return _availableModels;
  }

  Future<http.Response> _fetchCatalogPage(int page) async {
    final headers = <String, String>{'Accept': 'text/html'};
    if (page > 1) {
      headers['HX-Request'] = 'true';
      headers['HX-Target'] = 'searchresults';
    }
    final response = await _catalogClient
        .get(
          _catalogUri.replace(queryParameters: {
            'page': '$page',
            'c': 'local',
          }),
          headers: headers,
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw HttpException(
        'HTTP ${response.statusCode} al consultar el catálogo de Ollama.',
        uri: _catalogUri,
      );
    }
    return response;
  }

  static int? _parseCatalogPageCount(String body) {
    final document = html_parser.parse(body);
    final placeholder =
        document.querySelector('#form-input')?.attributes['placeholder'];
    final modelCount = int.tryParse(
      RegExp(r'\d+').firstMatch(placeholder ?? '')?.group(0) ?? '',
    );
    if (modelCount == null) {
      return null;
    }
    final pageCount = (modelCount / _catalogPageSize).ceil();
    if (pageCount > _catalogMaxPages) {
      throw const FormatException(
        'El catálogo de Ollama supera el límite de páginas admitido.',
      );
    }
    return pageCount.clamp(1, _catalogMaxPages).toInt();
  }

  @visibleForTesting
  static List<Map<String, dynamic>> parseAvailableModels(String body) {
    final document = html_parser.parse(body);
    final results = <Map<String, dynamic>>[];
    for (final card in document.querySelectorAll('a[href^="/library/"]')) {
      final modelId = card.querySelector('h2')?.text.trim() ?? '';
      if (modelId.isEmpty) {
        continue;
      }

      final description = card.querySelector('p')?.text.trim() ?? '';
      final labels = card
          .querySelectorAll('div.mt-3 span')
          .map((element) => element.text.trim())
          .where((label) => label.isNotEmpty)
          .toSet()
          .toList();
      final lowerName = modelId.toLowerCase();
      final lowerDescription = description.toLowerCase();
      final isUncensored = lowerName.contains('uncensored') ||
          lowerDescription.contains('uncensored') ||
          lowerName.contains('dolphin');
      final isMultimodal = labels.any((label) {
            final lowerLabel = label.toLowerCase();
            return lowerLabel.contains('vision') ||
                lowerLabel.contains('multimodal');
          }) ||
          lowerDescription.contains('vision') ||
          lowerDescription.contains('multimodal') ||
          lowerName.contains('vision') ||
          lowerName.contains('llava') ||
          lowerName.contains('pixtral') ||
          lowerName.contains('vl');
      final downloadTitle =
          card.querySelector('[title*="downloads"]')?.attributes['title'];
      final pulls = int.tryParse(
        (downloadTitle ?? '').replaceAll(RegExp(r'[^0-9]'), ''),
      );

      results.add({
        'name': modelId,
        'repository': modelId,
        'tags': labels,
        'description': description,
        'size': _estimateSizeFromLabels(labels),
        'pulls': pulls ?? 0,
        'multimodal': isMultimodal,
        'uncensored': isUncensored,
      });
    }

    return results;
  }

  static List<Map<String, dynamic>> filterAvailableModels({
    required List<Map<String, dynamic>> models,
    String query = '',
    bool uncensoredOnly = false,
    bool multimodalOnly = false,
    bool smallOnly = false,
  }) {
    final normalizedQuery = query.trim().toLowerCase();
    return models.where((model) {
      final name = (model['name'] as String? ?? '').toLowerCase();
      final description = (model['description'] as String? ?? '').toLowerCase();
      final tags =
          (model['tags'] as List<dynamic>? ?? []).whereType<String>().toList();
      if (normalizedQuery.isNotEmpty &&
          !name.contains(normalizedQuery) &&
          !description.contains(normalizedQuery) &&
          !tags.any((tag) => tag.toLowerCase().contains(normalizedQuery))) {
        return false;
      }
      if (uncensoredOnly && model['uncensored'] != true) {
        return false;
      }
      if (multimodalOnly && model['multimodal'] != true) {
        return false;
      }
      if (smallOnly &&
          !tags.any((tag) {
            final match = RegExp(r'(\d+(?:\.\d+)?)b', caseSensitive: false)
                .firstMatch(tag);
            final size = double.tryParse(match?.group(1) ?? '');
            return size != null && size <= 8;
          })) {
        return false;
      }
      return true;
    }).toList();
  }

  /// Estimar tamaño basado en las etiquetas del modelo (ej: "8B", "70B")
  static String _estimateSizeFromLabels(List<String> labels) {
    for (final label in labels) {
      final lower = label.toLowerCase();
      final sizeMatch = RegExp(r'(\d+(?:\.\d+)?)b').firstMatch(lower);
      final parameterSize = double.tryParse(sizeMatch?.group(1) ?? '');
      if (parameterSize != null) {
        if (parameterSize <= 1) return '~800 MB';
        if (parameterSize <= 3) return '~2 GB';
        if (parameterSize <= 8) return '~5 GB';
        if (parameterSize <= 14) return '~8 GB';
        if (parameterSize <= 35) return '~20 GB';
        if (parameterSize <= 70) return '~40 GB';
        return '~230 GB';
      }
      if (lower.contains('405b')) return '~230 GB';
      if (lower.contains('70b')) return '~40 GB';
      if (lower.contains('34b') || lower.contains('35b')) return '~20 GB';
      if (lower.contains('13b') || lower.contains('14b')) return '~8 GB';
      if (lower.contains('9b')) return '~5 GB';
      if (lower.contains('8b')) return '~5 GB';
      if (lower.contains('7b')) return '~4 GB';
      if (lower.contains('3b')) return '~2 GB';
      if (lower.contains('2b')) return '~1.5 GB';
      if (lower.contains('1b') || lower.contains('0.5b')) return '~800 MB';
    }
    return 'Desconocido';
  }

  /// Verificar si Ollama está instalado en el sistema
  Future<bool> isOllamaInstalled() async {
    try {
      if (Platform.isWindows) {
        final result = await Process.run('where', ['ollama']);
        return result.exitCode == 0;
      } else {
        final result = await Process.run('which', ['ollama']);
        return result.exitCode == 0;
      }
    } catch (e) {
      return false;
    }
  }

  /// Iniciar servidor Ollama (si está instalado localmente)
  Future<bool> startServer() async {
    try {
      _serverInfo = _serverInfo.copyWith(status: OllamaStatus.starting);
      notifyListeners();

      final process = await Process.start('ollama', ['serve']);
      _serverProcess = process;
      unawaited(process.stdout.drain<void>());
      unawaited(process.stderr.drain<void>());
      unawaited(process.exitCode.then((_) {
        if (identical(_serverProcess, process)) {
          _serverProcess = null;
        }
      }));

      // Esperar a que inicie
      await Future.delayed(const Duration(seconds: 3));

      // Verificar si está corriendo
      await checkInstallation();

      return _serverInfo.status == OllamaStatus.running;
    } catch (e) {
      _addLog('Error iniciando servidor: $e');
      _serverInfo = _serverInfo.copyWith(
        status: OllamaStatus.error,
        errorMessage: 'No se pudo iniciar: $e',
      );
      notifyListeners();
      return false;
    }
  }

  /// Descarga de la memoria los modelos cargados sin cerrar Ollama.
  ///
  /// Es la forma segura de liberar VRAM al cerrar LightChat: Ollama sigue
  /// disponible para otras aplicaciones y el modelo se recarga al pedirlo.
  Future<int> unloadLoadedModels() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/ps'))
          .timeout(const Duration(milliseconds: 1200));
      if (response.statusCode != 200) {
        return 0;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final loaded = (data['models'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map((model) =>
              model['name']?.toString() ?? model['model']?.toString())
          .whereType<String>()
          .where((name) => name.isNotEmpty)
          .toList();
      if (loaded.isEmpty) {
        return 0;
      }

      await Future.wait(
        loaded.map(
          (name) => http
              .post(
                Uri.parse('$baseUrl/api/generate'),
                headers: {'Content-Type': 'application/json'},
                body: json.encode({'model': name, 'keep_alive': 0}),
              )
              .timeout(const Duration(milliseconds: 1200))
              .catchError((_) => http.Response('', 0)),
        ),
      );
      _addLog('${loaded.length} modelo(s) descargados de memoria');
      return loaded.length;
    } catch (e) {
      debugPrint('No se pudieron descargar los modelos: $e');
      return 0;
    }
  }

  /// Detener el servidor Ollama **solo si lo inició LightChat**.
  ///
  /// Antes se ejecutaba `taskkill /F /IM ollama.exe`, que cerraba también el
  /// Ollama que el usuario tuviera abierto para otras aplicaciones.
  Future<void> stopServer() async {
    final process = _serverProcess;
    if (process == null) {
      _addLog('Ollama no lo inició LightChat; se deja en marcha');
      await unloadLoadedModels();
      return;
    }

    try {
      _addLog('Deteniendo el servidor Ollama iniciado por LightChat...');
      if (Platform.isWindows) {
        await Process.run('taskkill', ['/F', '/PID', '${process.pid}']);
      } else {
        process.kill();
      }
      _serverProcess = null;
      await Future.delayed(const Duration(seconds: 1));
      await checkInstallation();
      _addLog('Servidor Ollama detenido, VRAM liberada');
    } catch (e) {
      _addLog('Error deteniendo servidor: $e');
    }
  }

  /// Detener health check
  @override
  void dispose() {
    _healthCheckTimer?.cancel();
    _catalogClient.close();
    super.dispose();
  }

  /// Buscar modelos populares disponibles (método de compatibilidad,
  /// usa fetchAvailableModels() para obtener datos reales del registry)
  static List<Map<String, dynamic>> get popularModels => [];
}
