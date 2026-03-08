import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/message.dart';
import 'context_service.dart';
import 'image_service.dart';
import 'ollama_service.dart';

/// ChatService adaptado para Ollama
class ChatServiceOllama with ChangeNotifier {
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

  // Modelo seleccionado
  String _selectedModel = '';
  String get selectedModel => _selectedModel;
  List<String> _availableModels = [];
  List<String> get availableModels => _availableModels;

  // Contexto
  String _userLanguage = 'español';
  String get userLanguage => _userLanguage;
  bool _autoSelectModel = true;
  bool get autoSelectModel => _autoSelectModel;

  // Servicios
  final ImageService _imageService = ImageService();
  final OllamaService _ollamaService = OllamaService.instance;

  // Timer para monitoreo
  Timer? _connectionTimer;

  ChatServiceOllama() {
    _initService();
    _startConnectionMonitor();
  }

  Future<void> _initService() async {
    // Primero cargar el modelo preferido antes de loadModels
    _selectedModel = await ContextService.loadPreferredModel();
    
    await _ollamaService.initialize();
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

    // Cargar idioma preferido
    _userLanguage = await ContextService.loadUserLanguage();

    // Si el modelo preferido ya está disponible, usarlo
    // (ya se cargó en _initService)
  }

  void _startConnectionMonitor() {
    _connectionTimer?.cancel();
    _connectionTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _checkConnection();
    });
  }

  Future<void> _checkConnection() async {
    final wasConnected = _isConnected;
    _isConnected = _ollamaService.serverInfo.status == OllamaStatus.running;
    
    if (_isConnected != wasConnected) {
      if (_isConnected) {
        await loadModels();
        _connectionError = '';
      } else {
        _connectionError = 'Ollama no está ejecutándose';
      }
      notifyListeners();
    }
  }

  Future<void> loadModels() async {
    _isLoadingModels = true;
    notifyListeners();

    try {
      // Usar modelos de OllamaService
      final models = _ollamaService.models;
      _availableModels = models.map((m) => m.name).toList();

      // Si ya hay un modelo preferido y está disponible, usarlo
      if (_selectedModel.isEmpty && _availableModels.isNotEmpty) {
        // Primero intentar usar el modelo preferido si ya estaba cargado
        final preferredModel = await ContextService.loadPreferredModel();
        if (preferredModel.isNotEmpty && _availableModels.contains(preferredModel)) {
          _selectedModel = preferredModel;
        } else {
          // Si no, usar el primer modelo disponible
          _selectedModel = _availableModels.first;
        }
      } else if (_selectedModel.isNotEmpty && !_availableModels.contains(_selectedModel)) {
        // El modelo preferido ya no está disponible, usar el primero
        if (_availableModels.isNotEmpty) {
          _selectedModel = _availableModels.first;
        }
      }

      _isConnected = _ollamaService.serverInfo.status == OllamaStatus.running;
      _connectionError = _isConnected ? '' : 'Ollama no disponible';

      debugPrint('[ChatServiceOllama] ${_availableModels.length} modelos disponibles');
      debugPrint('[ChatServiceOllama] Modelo seleccionado: $_selectedModel');
    } catch (e) {
      debugPrint('[ChatServiceOllama] Error cargando modelos: $e');
      _availableModels = [];
      _isConnected = false;
      _connectionError = 'Error: $e';
    } finally {
      _isLoadingModels = false;
      notifyListeners();
    }
  }

  Future<void> sendMessage(String text, {List<String>? imagePaths}) async {
    if (text.isEmpty || _selectedModel.isEmpty) return;

    // Detectar idioma
    final detectedLanguage = ContextService.detectLanguage(text);
    if (detectedLanguage != _userLanguage) {
      _userLanguage = detectedLanguage;
      await ContextService.saveUserLanguage(_userLanguage);
    }

    // Limpiar historial si es necesario
    if (_messages.length > 100) {
      final cleanedMessages = ContextService.cleanOldHistory(_messages);
      _messages.clear();
      _messages.addAll(cleanedMessages);
    }

    // Procesar imágenes si hay
    List<OllamaImage>? ollamaImages;
    if (imagePaths != null && imagePaths.isNotEmpty) {
      ollamaImages = [];
      for (final path in imagePaths) {
        try {
          final file = File(path);
          final bytes = await file.readAsBytes();
          ollamaImages.add(OllamaImage.fromBytes(bytes));
        } catch (e) {
          debugPrint('Error cargando imagen: $e');
        }
      }
    }

    // Añadir mensaje del usuario
    _messages.add(Message(
      text: text,
      isUser: true,
      timestamp: DateTime.now(),
      model: _selectedModel,
      metadata: {'language': _userLanguage, 'hasImages': ollamaImages?.isNotEmpty ?? false},
    ));
    
    _isLoading = true;
    notifyListeners();

    // Guardar mensajes
    await ContextService.saveMessages(_messages);

    try {
      // Construir historial de mensajes para Ollama
      final ollamaMessages = <OllamaMessage>[];
      
      // System message
      ollamaMessages.add(OllamaMessage(
        role: 'system',
        content: 'Eres un asistente de IA útil y amigable. Responde siempre en $_userLanguage de manera natural y conversacional.',
      ));

      // Mensajes previos (últimos 10 para contexto)
      final contextMessages = _messages.length > 11 
          ? _messages.sublist(_messages.length - 11, _messages.length - 1)
          : _messages.where((m) => m.isUser).toList();

      for (final msg in contextMessages) {
        ollamaMessages.add(OllamaMessage(
          role: msg.isUser ? 'user' : 'assistant',
          content: msg.text,
        ));
      }

      // Mensaje actual con imágenes si aplica
      ollamaMessages.add(OllamaMessage(
        role: 'user',
        content: text,
        images: ollamaImages?.isNotEmpty == true ? ollamaImages : null,
      ));

      debugPrint('[ChatServiceOllama] Enviando mensaje con modelo: $_selectedModel');

      // Acumular respuesta
      final buffer = StringBuffer();
      
      await for (final response in _ollamaService.generateChat(
        model: _selectedModel,
        messages: ollamaMessages,
        temperature: 0.7,
        numPredict: 2048,
      )) {
        buffer.write(response.message);
        
        // Notificar progreso parcial para UI responsiva
        if (buffer.length % 50 == 0) {
          notifyListeners();
        }
      }

      final responseText = buffer.toString().trim();

      if (responseText.isNotEmpty) {
        _messages.add(Message(
          text: responseText,
          isUser: false,
          timestamp: DateTime.now(),
          model: _selectedModel,
          metadata: {
            'language': _userLanguage,
            'responseTime': DateTime.now().toIso8601String(),
          },
        ));

        await ContextService.saveMessages(_messages);
      } else {
        _messages.add(Message(
          text: 'Lo siento, no pude generar una respuesta. Por favor, intenta de nuevo.',
          isUser: false,
          timestamp: DateTime.now(),
          model: _selectedModel,
          isError: true,
        ));
      }
    } catch (e) {
      debugPrint('[ChatServiceOllama] Error: $e');
      _messages.add(Message(
        text: 'Error al comunicarse con Ollama: $e',
        isUser: false,
        timestamp: DateTime.now(),
        model: _selectedModel,
        isError: true,
      ));
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void selectModel(String model) {
    if (_availableModels.contains(model)) {
      _selectedModel = model;
      ContextService.savePreferredModel(model);
      notifyListeners();
    }
  }

  void toggleAutoSelectModel() {
    _autoSelectModel = !_autoSelectModel;
    notifyListeners();
  }

  void clearMessages() {
    _messages.clear();
    ContextService.saveMessages(_messages);
    notifyListeners();
  }

  void clearError() {
    _connectionError = '';
    notifyListeners();
  }

  void retryConnection() {
    _connectionError = '';
    loadModels();
  }

  @override
  void dispose() {
    _connectionTimer?.cancel();
    super.dispose();
  }
}
