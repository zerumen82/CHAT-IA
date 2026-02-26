import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/message.dart';
import 'context_service.dart';
import 'image_service.dart';

class ChatService with ChangeNotifier {
  final List<Message> _messages = [];
  List<Message> get messages => _messages;
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  // Estado de carga de modelos
  bool _isLoadingModels = false;
  bool get isLoadingModels => _isLoadingModels;

  // Estado de conexión
  bool _isConnected = false;
  bool get isConnected => _isConnected;
  String _connectionError = '';
  String get connectionError => _connectionError;

  // Configuración vLLM
  String _vllmServerUrl = 'http://localhost:8000';
  String get vllmServerUrl => _vllmServerUrl;

  String _selectedModel = '';
  String get selectedModel => _selectedModel;
  List<String> _availableModels = [];
  List<String> get availableModels => _availableModels;

  // Variables para contexto inteligente
  String _userLanguage = 'español';
  String get userLanguage => _userLanguage;
  bool _autoSelectModel = true;
  bool get autoSelectModel => _autoSelectModel;

  // Servicio de imágenes
  final ImageService _imageService = ImageService();

  // Timer para monitoreo de conexión
  Timer? _connectionTimer;

  ChatService() {
    _initService();
    _startConnectionMonitor();
  }

  Future<void> _initService() async {
    await loadModels();
    await _loadContextData();
  }

  Future<void> _loadContextData() async {
    // Cargar mensajes guardados
    final savedMessages = await ContextService.loadMessages();
    if (savedMessages.isNotEmpty) {
      _messages.addAll(savedMessages);
      notifyListeners();
    }

    // Cargar idioma preferido del usuario
    _userLanguage = await ContextService.loadUserLanguage();

    // Cargar modelo preferido
    final preferredModel = await ContextService.loadPreferredModel();
    if (preferredModel.isNotEmpty &&
        _availableModels.contains(preferredModel)) {
      _selectedModel = preferredModel;
    }
  }

  void setVllmServerUrl(String url) {
    _vllmServerUrl = url;
    loadModels();
    notifyListeners();
  }

  Future<void> loadModels() async {
    _isLoadingModels = true;
    notifyListeners();

    try {
      debugPrint(
          '[ChatService] loadModels: requesting model list from vLLM...');
      final response = await http
          .get(Uri.parse('$_vllmServerUrl/v1/models'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final body = response.body;
        final data = json.decode(body);
        if (data is Map && data['data'] is List) {
          _availableModels =
              List<String>.from(data['data'].map((m) => m['id'].toString()));

          // Auto-seleccionar primer modelo si no hay uno seleccionado
          if (_selectedModel.isEmpty && _availableModels.isNotEmpty) {
            _selectedModel = _availableModels.first;
          }

          // Actualizar estado de conexión
          _isConnected = true;
          _connectionError = '';
        } else {
          _availableModels = [];
          _isConnected = false;
          _connectionError = 'Respuesta inválida del servidor';
        }
      } else {
        _availableModels = [];
        _isConnected = false;
        _connectionError = 'Error HTTP ${response.statusCode}';
      }
    } catch (e, stackTrace) {
      debugPrint('=== ERROR CARGANDO MODELOS ===');
      debugPrint('Error: $e');
      debugPrint('Stack Trace: $stackTrace');
      debugPrint('============================');
      _availableModels = [];
      _isConnected = false;

      // Mensaje de error más amigable
      if (e is SocketException) {
        _connectionError =
            'vLLM no está ejecutándose. Inicia el servidor desde la pestaña SERVIDOR.';
      } else if (e.toString().contains('Connection refused')) {
        _connectionError =
            'Conexión rechazada. Verifica que vLLM esté activo en puerto 8000.';
      } else if (e.toString().contains('TimeoutException') ||
          e.toString().contains('timed out')) {
        _connectionError =
            'Tiempo de espera agotado. El servidor puede estar iniciando.';
      } else {
        _connectionError = 'Error de conexión: $e';
      }
    } finally {
      _isLoadingModels = false;
      notifyListeners();
      debugPrint(
          '[ChatService] loadModels: finished, available=${_availableModels.length}, connected=$_isConnected');
    }
  }

  Future<void> sendMessage(String text) async {
    if (text.isEmpty || _selectedModel.isEmpty) return;

    // Detectar idioma automáticamente del mensaje del usuario
    final detectedLanguage = ContextService.detectLanguage(text);
    if (detectedLanguage != _userLanguage) {
      _userLanguage = detectedLanguage;
      await ContextService.saveUserLanguage(_userLanguage);
    }

    // Auto-seleccionar modelo óptimo si está habilitado
    if (_autoSelectModel && _availableModels.isNotEmpty) {
      final optimalModel = ContextService.selectOptimalModel(
          text, _availableModels, _userLanguage);
      if (optimalModel != _selectedModel) {
        _selectedModel = optimalModel;
        await ContextService.savePreferredModel(_selectedModel);
      }
    }

    // Solo limpiar si excedemos el límite de mensajes
    if (_messages.length > 100) {
      final cleanedMessages = ContextService.cleanOldHistory(_messages);
      _messages.clear();
      _messages.addAll(cleanedMessages);
    }

    _messages.add(Message(
        text: text,
        isUser: true,
        timestamp: DateTime.now(),
        model: _selectedModel,
        metadata: {'language': _userLanguage}));
    _isLoading = true;
    notifyListeners();

    // Guardar mensajes inmediatamente
    await ContextService.saveMessages(_messages);

    try {
      debugPrint('[ChatService] sendMessage: model=$_selectedModel');

      // Generar contexto inteligente
      final context = ContextService.generateContext(_messages, _userLanguage);
      final contextSummary = ContextService.generateContextSummary(_messages);

      const systemPrompt =
          'Eres un asistente de IA útil y amigable. Responde siempre en el idioma del usuario de manera natural y conversacional.';
      final userPrompt = '''$context

$contextSummary

Eres un asistente de IA amigable y útil. Responde a la siguiente consulta en $_userLanguage de manera natural, conversacional y completa. Puedes ayudar con cualquier tema general, desde preguntas cotidianas hasta análisis complejos:

$text''';

      // Formato de chat para vLLM (compatible con OpenAI API)
      final messages = [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userPrompt}
      ];

      final requestBody = {
        'model': _selectedModel,
        'messages': messages,
        'temperature': 0.7,
        'max_tokens': 2048,
        'top_p': 0.9,
        'frequency_penalty': 0.1,
        'presence_penalty': 0.1,
        'stream': false,
      };

      final response = await http
          .post(
            Uri.parse('$_vllmServerUrl/v1/chat/completions'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(requestBody),
          )
          .timeout(const Duration(seconds: 120));

      if (response.statusCode == 200) {
        final body = response.body;
        try {
          final data = json.decode(body);
          String responseText = '';

          if (data is Map &&
              data.containsKey('choices') &&
              data['choices'] is List &&
              data['choices'].isNotEmpty) {
            responseText =
                data['choices'][0]['message']['content'].toString().trim();
          }

          if (responseText.isNotEmpty) {
            _messages.add(Message(
              text: responseText,
              isUser: false,
              timestamp: DateTime.now(),
              model: _selectedModel,
              metadata: {
                'language': _userLanguage,
                'context_used': context.isNotEmpty,
              },
              tokenCount: responseText.length ~/ 4, // Estimación aproximada
            ));

            // Guardar mensajes actualizados
            await ContextService.saveMessages(_messages);
          } else {
            _messages.add(Message(
              text: 'Respuesta vacía del modelo',
              isUser: false,
              isError: true,
              timestamp: DateTime.now(),
            ));
          }
        } catch (e) {
          _messages.add(Message(
            text: 'Error al procesar respuesta: $e',
            isUser: false,
            isError: true,
            timestamp: DateTime.now(),
          ));
        }
      } else if (response.statusCode == 404) {
        _messages.add(Message(
          text:
              'Modelo no encontrado. Verifica que $_selectedModel esté disponible en vLLM.',
          isUser: false,
          isError: true,
          timestamp: DateTime.now(),
        ));
      } else {
        _messages.add(Message(
          text: 'Error del servidor: ${response.statusCode}',
          isUser: false,
          isError: true,
          timestamp: DateTime.now(),
        ));
        // Recargar modelos si hay error de servidor
        await loadModels();
      }
    } catch (e, stackTrace) {
      String errorMsg = 'ERROR COMPLETO:\n\n';
      errorMsg += 'Tipo: ${e.runtimeType}\n';
      errorMsg += 'Mensaje: $e\n\n';
      errorMsg += 'Stack Trace:\n$stackTrace';

      debugPrint('=== ERROR DETALLADO ===');
      debugPrint('Error: $e');
      debugPrint('Stack Trace: $stackTrace');
      debugPrint('=====================');

      if (e is SocketException) {
        // Limpiar modelos disponibles para mostrar estado desconectado
        _availableModels = [];
        _selectedModel = '';
      } else if (e.toString().contains('Connection refused')) {
        _availableModels = [];
        _selectedModel = '';
      }

      _messages.add(Message(
        text: errorMsg,
        isUser: false,
        isError: true,
        timestamp: DateTime.now(),
      ));

      // Intentar reconectar automáticamente
      Future.delayed(const Duration(seconds: 2), () {
        if (_availableModels.isEmpty) {
          loadModels();
        }
      });
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Enviar mensaje con imágenes (multimodal)
  Future<void> sendMessageWithImages(
    String text,
    List<File> imageFiles,
  ) async {
    if (_selectedModel.isEmpty) return;
    if (imageFiles.isEmpty) {
      // Si no hay imágenes, usar el método normal
      await sendMessage(text);
      return;
    }

    // Procesar imágenes
    final List<MessageImage> messageImages = [];
    for (final file in imageFiles) {
      final processed = await _imageService.processImageForSending(file);
      if (processed != null) {
        // Guardar imagen localmente
        final localPath = await processed.saveLocal();

        messageImages.add(MessageImage(
          id: processed.id,
          localPath: localPath,
          base64Data: processed.toBase64(),
          width: processed.width,
          height: processed.height,
          sizeBytes: processed.sizeBytes,
          mimeType: processed.mimeType,
        ));
      }
    }

    if (messageImages.isEmpty) {
      // Si no se pudo procesar ninguna imagen, enviar solo texto
      await sendMessage(text);
      return;
    }

    // Detectar idioma
    final detectedLanguage = ContextService.detectLanguage(text);
    if (detectedLanguage != _userLanguage) {
      _userLanguage = detectedLanguage;
      await ContextService.saveUserLanguage(_userLanguage);
    }

    // Crear mensaje del usuario con imágenes
    _messages.add(Message.withImages(
      text: text,
      isUser: true,
      timestamp: DateTime.now(),
      images: messageImages,
      model: _selectedModel,
      metadata: {'language': _userLanguage, 'multimodal': true},
    ));
    _isLoading = true;
    notifyListeners();

    await ContextService.saveMessages(_messages);

    try {
      // Construir contenido multimodal para la API
      final List<Map<String, dynamic>> content = [];

      // Agregar imágenes primero
      for (final img in messageImages) {
        if (img.base64Data != null) {
          content.add({
            'type': 'image_url',
            'image_url': {'url': img.base64Data},
          });
        }
      }

      // Agregar texto
      content.add({
        'type': 'text',
        'text': _buildMultimodalPrompt(text),
      });

      final messages = [
        {
          'role': 'system',
          'content': 'Eres un asistente de IA útil que puede analizar imágenes. '
              'Responde siempre en $_userLanguage de manera natural y conversacional.'
        },
        {'role': 'user', 'content': content}
      ];

      final requestBody = {
        'model': _selectedModel,
        'messages': messages,
        'temperature': 0.7,
        'max_tokens': 2048,
        'top_p': 0.9,
        'stream': false,
      };

      final response = await http
          .post(
            Uri.parse('$_vllmServerUrl/v1/chat/completions'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(requestBody),
          )
          .timeout(const Duration(seconds: 180));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        String responseText = '';

        if (data is Map &&
            data.containsKey('choices') &&
            data['choices'] is List &&
            data['choices'].isNotEmpty) {
          responseText =
              data['choices'][0]['message']['content'].toString().trim();
        }

        if (responseText.isNotEmpty) {
          _messages.add(Message(
            text: responseText,
            isUser: false,
            timestamp: DateTime.now(),
            model: _selectedModel,
            metadata: {
              'language': _userLanguage,
              'multimodal': true,
              'images_processed': messageImages.length,
            },
            tokenCount: responseText.length ~/ 4,
          ));

          await ContextService.saveMessages(_messages);
        } else {
          _messages.add(Message(
            text: 'El modelo no pudo procesar las imágenes.',
            isUser: false,
            isError: true,
            timestamp: DateTime.now(),
          ));
        }
      } else {
        _messages.add(Message(
          text: 'Error del servidor: ${response.statusCode}',
          isUser: false,
          isError: true,
          timestamp: DateTime.now(),
        ));
      }
    } catch (e) {
      debugPrint('Error sending multimodal message: $e');
      _messages.add(Message(
        text: 'Error al procesar imágenes: $e',
        isUser: false,
        isError: true,
        timestamp: DateTime.now(),
      ));
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Construir prompt para mensajes multimodales
  String _buildMultimodalPrompt(String userText) {
    return 'Por favor, analiza las imágenes proporcionadas y responde a la siguiente '
        'consulta en $_userLanguage:\n\n$userText';
  }

  void selectModel(String model) {
    _selectedModel = model;
    ContextService.savePreferredModel(model);
    notifyListeners();
  }

  void toggleAutoSelectModel() {
    _autoSelectModel = !_autoSelectModel;
    notifyListeners();
  }

  void clearHistory() {
    _messages.clear();
    ContextService.saveMessages(_messages);
    notifyListeners();
  }

  void _startConnectionMonitor() {
    // Verificar conexión cada 30 segundos
    _connectionTimer?.cancel();
    _connectionTimer =
        Timer.periodic(const Duration(seconds: 30), (timer) async {
      if (!_isLoadingModels) {
        await loadModels();
      }
    });
  }

  /// Verificar conexión manualmente
  Future<bool> checkConnection() async {
    await loadModels();
    return _isConnected;
  }

  @override
  void dispose() {
    _connectionTimer?.cancel();
    super.dispose();
  }
}
