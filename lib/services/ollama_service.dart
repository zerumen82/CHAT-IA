import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
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
  final int? totalDuration;
  final int? loadDuration;
  final int? promptEvalCount;
  final int? evalCount;

  OllamaChatResponse({
    required this.message,
    required this.done,
    this.totalDuration,
    this.loadDuration,
    this.promptEvalCount,
    this.evalCount,
  });

  factory OllamaChatResponse.fromJson(Map<String, dynamic> json) {
    return OllamaChatResponse(
      message: json['message']?['content'] ?? json['response'] ?? '',
      done: json['done'] ?? false,
      totalDuration: json['total_duration'],
      loadDuration: json['load_duration'],
      promptEvalCount: json['prompt_eval_count'],
      evalCount: json['eval_count'],
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
  static const String _apiVersion = 'v1';

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
  List<String> get logs => List.unmodifiable(_logs);

  OllamaService._();

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
        _serverInfo = const OllamaServerInfo(
          status: OllamaStatus.notInstalled,
        );
      }
    } on SocketException {
      _serverInfo = OllamaServerInfo(
        status: OllamaStatus.notInstalled,
        errorMessage: 'Ollama no está corriendo en $baseUrl',
      );
    } on TimeoutException {
      _serverInfo = const OllamaServerInfo(
        status: OllamaStatus.notInstalled,
        errorMessage: 'Timeout conectando a Ollama',
      );
    } catch (e) {
      _serverInfo = OllamaServerInfo(
        status: OllamaStatus.error,
        errorMessage: 'Error: $e',
      );
    }
    notifyListeners();
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
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/tags'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200 && _serverInfo.status != OllamaStatus.running) {
        await checkInstallation();
      } else if (response.statusCode != 200 && _serverInfo.status == OllamaStatus.running) {
        _serverInfo = _serverInfo.copyWith(status: OllamaStatus.error);
        notifyListeners();
      }
    } catch (e) {
      if (_serverInfo.status == OllamaStatus.running) {
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

  /// Generar respuesta de chat (streaming)
  Stream<OllamaChatResponse> generateChat({
    required String model,
    required List<OllamaMessage> messages,
    double? temperature,
    int? numPredict,
  }) async* {
    try {
      final request = http.Request('POST', Uri.parse('$baseUrl/api/chat'));
      request.headers['Content-Type'] = 'application/json';
      request.body = json.encode({
        'model': model,
        'messages': messages.map((m) => m.toJson()).toList(),
        'stream': true,
        'options': {
          if (temperature != null) 'temperature': temperature,
          if (numPredict != null) 'num_predict': numPredict,
        },
      });

      final response = await request.send();

      if (response.statusCode == 200) {
        await for (final chunk in response.stream.transform(utf8.decoder)) {
          final lines = chunk.split('\n');
          for (final line in lines) {
            if (line.trim().isEmpty) continue;
            try {
              final data = json.decode(line);
              yield OllamaChatResponse.fromJson(data);
            } catch (_) {
              // Ignorar líneas inválidas
            }
          }
        }
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      _addLog('Error en generateChat: $e');
      rethrow;
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

      Process? process;
      if (Platform.isWindows) {
        process = await Process.start('ollama', ['serve']);
      } else {
        process = await Process.start('ollama', ['serve']);
      }

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

  /// Detener health check
  void dispose() {
    _healthCheckTimer?.cancel();
    super.dispose();
  }

  /// Buscar modelos populares disponibles
  static List<Map<String, dynamic>> get popularModels => [
    {
      'name': 'llama3.2',
      'description': 'Meta Llama 3.2 - Balance rendimiento/tamaño',
      'tags': ['3b', '1b'],
      'size': '~2GB',
    },
    {
      'name': 'llama3.1',
      'description': 'Meta Llama 3.1 - Modelo principal',
      'tags': ['8b', '70b', '405b'],
      'size': '~4.7GB (8b)',
    },
    {
      'name': 'mistral',
      'description': 'Mistral 7B - Rápido y eficiente',
      'tags': ['7b'],
      'size': '~4.1GB',
    },
    {
      'name': 'qwen2.5',
      'description': 'Qwen 2.5 - Multilingüe excelente',
      'tags': ['0.5b', '1.5b', '3b', '7b', '14b', '32b', '72b'],
      'size': '~500MB - 47GB',
    },
    {
      'name': 'phi3',
      'description': 'Microsoft Phi-3 - Muy rápido',
      'tags': ['mini', 'small', 'medium'],
      'size': '~2GB - 8GB',
    },
    {
      'name': 'gemma2',
      'description': 'Google Gemma 2 - Abierto y eficiente',
      'tags': ['2b', '9b', '27b'],
      'size': '~1.6GB - 18GB',
    },
    {
      'name': 'codellama',
      'description': 'CodeLlama - Especializado en código',
      'tags': ['7b', '13b', '34b', '70b'],
      'size': '~3.8GB - 39GB',
    },
    {
      'name': 'llava',
      'description': 'LLaVA - Multimodal (visión)',
      'tags': ['7b', '13b', '34b'],
      'size': '~4.5GB',
      'multimodal': true,
    },
    {
      'name': 'deepseek-coder',
      'description': 'DeepSeek Coder - Excelente para código',
      'tags': ['1.3b', '6.7b', '33b'],
      'size': '~800MB - 19GB',
    },
    {
      'name': 'neural-chat',
      'description': 'Neural Chat - Optimizado para conversación',
      'tags': ['7b'],
      'size': '~4GB',
    },
  ];
}
