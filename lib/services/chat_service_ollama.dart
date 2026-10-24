import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../config/vllm_config.dart';
import '../models/document_attachment.dart';
import '../models/message.dart';
import 'context_service.dart';
import 'document_service.dart';
import 'ollama_service.dart';

/// ChatService adaptado para Ollama
class ChatServiceOllama with ChangeNotifier {
  final List<Message> _messages = [];
  List<Message> get messages => _messages;

  /// Cambia cada vez que se añade, sustituye o elimina un mensaje.
  /// Permite que la UI se reconstruya solo cuando el historial cambia de verdad.
  int _messagesVersion = 0;
  int get messagesVersion => _messagesVersion;

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

  // Servicios
  final OllamaService _ollamaService = OllamaService.instance;

  // Generación en curso
  StreamSubscription<OllamaChatResponse>? _streamSubscription;
  Completer<void>? _streamCompleter;
  bool _stopRequested = false;

  ChatServiceOllama() {
    _ollamaService.addListener(_onOllamaServiceChanged);
    _initService();
  }

  Future<void> _initService() async {
    await _ollamaService.initialize();
    await loadModels(refresh: false);
    await _loadContextData();
  }

  Future<void> _loadContextData() async {
    // Cargar mensajes guardados
    final savedMessages = await ContextService.loadMessages();
    if (savedMessages.isNotEmpty) {
      _messages.addAll(savedMessages);
      _notifyMessages();
    }

    // Cargar idioma preferido
    _userLanguage = await ContextService.loadUserLanguage();
  }

  /// Reacciona a los cambios de OllamaService (estado, modelos) sin un timer
  /// propio: antes había un sondeo cada 10 s además del health check de 30 s.
  void _onOllamaServiceChanged() {
    // Mientras se recarga la lista no se vuelve a entrar: cada notificación de
    // OllamaService (incluidos los logs) dispararía otra carga en paralelo.
    if (_isLoadingModels) return;

    final isConnected =
        _ollamaService.serverInfo.status == OllamaStatus.running;
    final modelNames =
        _ollamaService.models.map((model) => model.name).toList();

    if (isConnected == _isConnected &&
        listEquals(modelNames, _availableModels)) {
      return;
    }

    if (isConnected) {
      loadModels(refresh: false);
    } else {
      _isConnected = false;
      _availableModels = [];
      _connectionError =
          _ollamaService.serverInfo.errorMessage ?? 'Ollama no disponible';
      notifyListeners();
    }
  }

  Future<void> loadModels({bool refresh = true}) async {
    if (_isLoadingModels) return;
    _isLoadingModels = true;
    notifyListeners();

    try {
      if (refresh) {
        await _ollamaService.checkInstallation();
      }

      // Usar modelos de OllamaService
      final models = _ollamaService.models;
      _availableModels = models.map((m) => m.name).toList();

      // Si ya hay un modelo preferido y está disponible, usarlo
      if (_selectedModel.isEmpty && _availableModels.isNotEmpty) {
        // Primero intentar usar el modelo preferido si ya estaba cargado
        final preferredModel = await ContextService.loadPreferredModel();
        if (preferredModel.isNotEmpty &&
            _availableModels.contains(preferredModel)) {
          _selectedModel = preferredModel;
        } else {
          // Si no, usar el primer modelo disponible
          _selectedModel = _availableModels.first;
        }
      } else if (_selectedModel.isNotEmpty &&
          !_availableModels.contains(_selectedModel)) {
        // El modelo preferido ya no está disponible, usar el primero
        if (_availableModels.isNotEmpty) {
          _selectedModel = _availableModels.first;
        }
      }

      _isConnected = _ollamaService.serverInfo.status == OllamaStatus.running;
      _connectionError = _isConnected
          ? ''
          : _ollamaService.serverInfo.errorMessage ?? 'Ollama no disponible';

      debugPrint(
          '[ChatServiceOllama] ${_availableModels.length} modelos disponibles');
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

  /// Reenvía la última pregunta cuando la respuesta terminó en error,
  /// sin duplicar el mensaje del usuario ni reenviar el texto del error.
  Future<void> retryLastMessage() async {
    if (_isLoading || !_isConnected || _selectedModel.isEmpty) {
      return;
    }

    final userIndex = _messages.lastIndexWhere((message) => message.isUser);
    if (userIndex < 0) {
      return;
    }

    final userMessage = _messages[userIndex];
    final imagePaths = userMessage.images
        ?.map((image) => image.localPath)
        .whereType<String>()
        .toList();
    final documents =
        userMessage.documents?.where((document) => document.isReady).toList();

    if (userMessage.text.trim().isEmpty &&
        (imagePaths?.isEmpty ?? true) &&
        (documents?.isEmpty ?? true)) {
      return;
    }

    if (userIndex < _messages.length - 1) {
      _messages.removeRange(userIndex + 1, _messages.length);
      _notifyMessages();
    }

    await _sendMessage(
      userMessage.text,
      imagePaths: imagePaths,
      documents: documents,
      addUserMessage: false,
    );
  }

  Future<void> sendMessage(
    String text, {
    List<String>? imagePaths,
    List<DocumentAttachment>? documents,
  }) {
    return _sendMessage(
      text,
      imagePaths: imagePaths,
      documents: documents,
      addUserMessage: true,
    );
  }

  Future<void> _sendMessage(
    String text, {
    List<String>? imagePaths,
    List<DocumentAttachment>? documents,
    required bool addUserMessage,
  }) async {
    final readyDocuments = (documents ?? const <DocumentAttachment>[])
        .where((document) => document.isReady)
        .toList();
    final hasDocuments = readyDocuments.isNotEmpty;

    if (!_isConnected ||
        (text.trim().isEmpty &&
            !(imagePaths?.isNotEmpty ?? false) &&
            !hasDocuments) ||
        _selectedModel.isEmpty) {
      return;
    }

    // Detectar idioma. No se cambia el idioma por una palabra suelta ("hola",
    // "si"), que es donde más se equivocaba el detector.
    final trimmedText = text.trim();
    if (trimmedText.isNotEmpty &&
        trimmedText.split(RegExp(r'\s+')).length >= 3) {
      final detectedLanguage = ContextService.detectLanguage(trimmedText);
      if (detectedLanguage != _userLanguage) {
        _userLanguage = detectedLanguage;
        await ContextService.saveUserLanguage(_userLanguage);
      }
    }

    // Limpiar historial si es necesario
    if (_messages.length > 100) {
      final cleanedMessages = ContextService.cleanOldHistory(_messages);
      _messages.clear();
      _messages.addAll(cleanedMessages);
    }

    // Procesar imágenes si hay
    List<OllamaImage>? ollamaImages;
    final messageImages = <MessageImage>[];
    if (imagePaths != null && imagePaths.isNotEmpty) {
      ollamaImages = [];
      for (final path in imagePaths) {
        try {
          final file = File(path);
          final bytes = await file.readAsBytes();
          ollamaImages.add(OllamaImage.fromBytes(bytes));
          messageImages.add(MessageImage(
            id: '${DateTime.now().microsecondsSinceEpoch}-${messageImages.length}',
            localPath: path,
            width: 0,
            height: 0,
            sizeBytes: bytes.length,
            mimeType: _imageMimeType(path),
          ));
        } catch (e) {
          debugPrint('Error cargando imagen: $e');
        }
      }
    }

    if (trimmedText.isEmpty &&
        (ollamaImages?.isNotEmpty ?? false) == false &&
        !hasDocuments) {
      return;
    }

    // Añadir mensaje del usuario (salvo al regenerar una respuesta)
    if (addUserMessage) {
      _messages.add(Message(
        text: text,
        isUser: true,
        timestamp: DateTime.now(),
        model: _selectedModel,
        metadata: {
          'language': _userLanguage,
          'hasImages': ollamaImages?.isNotEmpty ?? false,
          'hasDocuments': hasDocuments,
          'documents': readyDocuments.map((document) => document.name).toList(),
        },
        images: messageImages.isEmpty ? null : messageImages,
        documents: hasDocuments ? readyDocuments : null,
      ));
    }

    _isLoading = true;
    _stopRequested = false;
    _notifyMessages();

    // Guardado diferido: el historial se escribe una sola vez al terminar.
    ContextService.saveMessagesDebounced(_messages);

    final buffer = StringBuffer();
    int? streamingMessageIndex;
    try {
      // Construir historial de mensajes para Ollama
      final ollamaMessages = <OllamaMessage>[];

      // Mantener los últimos 10 turnos/mensajes en el orden original y sin
      // los mensajes de error, que no forman parte de la conversación.
      final previousMessages = _messages
          .sublist(0, _messages.length - 1)
          .where((message) =>
              !message.isError &&
              (message.text.trim().isNotEmpty ||
                  message.hasImages ||
                  message.hasDocuments))
          .toList();
      final contextMessages = previousMessages.length > 10
          ? previousMessages.sublist(previousMessages.length - 10)
          : previousMessages;

      // Solo el último mensaje con documentos aporta su texto completo,
      // para no desplazar la conversación reciente del contexto.
      var lastDocumentMessageIndex = -1;
      for (var index = contextMessages.length - 1; index >= 0; index--) {
        if (contextMessages[index].hasDocuments) {
          lastDocumentMessageIndex = index;
          break;
        }
      }

      final hasDocumentContext = hasDocuments || lastDocumentMessageIndex >= 0;

      ollamaMessages.add(OllamaMessage(
        role: 'system',
        content: _buildSystemPrompt(hasDocumentContext),
      ));

      for (var index = 0; index < contextMessages.length; index++) {
        final msg = contextMessages[index];
        final contextImages = <OllamaImage>[];
        for (final image in msg.images ?? const <MessageImage>[]) {
          if (image.base64Data != null && image.base64Data!.isNotEmpty) {
            contextImages.add(OllamaImage(image.base64Data!));
          } else if (image.localPath != null) {
            try {
              contextImages.add(
                OllamaImage.fromBytes(
                    await File(image.localPath!).readAsBytes()),
              );
            } catch (e) {
              debugPrint('Error cargando imagen del historial: $e');
            }
          }
        }
        ollamaMessages.add(OllamaMessage(
          role: msg.isUser ? 'user' : 'assistant',
          content: _contentWithDocuments(
            msg,
            includeDocuments: index == lastDocumentMessageIndex,
          ),
          images: contextImages.isEmpty ? null : contextImages,
        ));
      }

      // Mensaje actual con imágenes y documentos si aplica
      final documentContext = hasDocuments
          ? DocumentService.buildAttachmentContext(readyDocuments)
          : '';
      final promptText = documentContext.isEmpty
          ? text
          : (trimmedText.isEmpty
              ? documentContext
              : '$trimmedText\n\n$documentContext');
      final hasCurrentImages = ollamaImages != null && ollamaImages.isNotEmpty;
      ollamaMessages.add(OllamaMessage(
        role: 'user',
        content: promptText,
        images: hasCurrentImages ? ollamaImages : null,
      ));

      debugPrint(
          '[ChatServiceOllama] Enviando mensaje con modelo: $_selectedModel');

      // Acumular respuesta
      var lastNotifiedLength = 0;
      final done = Completer<void>();
      _streamCompleter = done;

      final subscription = _ollamaService
          .generateChat(
        model: _selectedModel,
        messages: ollamaMessages,
        temperature: hasDocumentContext
            ? OllamaConfig.documentTemperature
            : OllamaConfig.defaultTemperature,
        numPredict: OllamaConfig.maxResponseTokens,
        numCtx: OllamaConfig.maxContextTokens,
        think: OllamaConfig.isThinkingModel(_selectedModel) ? false : null,
      )
          .listen(
        (response) {
          if (response.message.isEmpty) {
            return;
          }
          buffer.write(response.message);

          if (streamingMessageIndex == null) {
            streamingMessageIndex = _messages.length;
            _messages.add(Message(
              text: buffer.toString(),
              isUser: false,
              timestamp: DateTime.now(),
              model: _selectedModel,
            ));
          } else {
            _messages[streamingMessageIndex!] =
                _messages[streamingMessageIndex!]
                    .copyWith(text: buffer.toString());
          }
          if (buffer.length - lastNotifiedLength >= 24) {
            lastNotifiedLength = buffer.length;
            _notifyMessages();
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!done.isCompleted) {
            done.completeError(error, stackTrace);
          }
        },
        onDone: () {
          if (!done.isCompleted) {
            done.complete();
          }
        },
        cancelOnError: true,
      );
      _streamSubscription = subscription;
      if (_stopRequested && !done.isCompleted) {
        subscription.cancel();
        done.complete();
      }

      await done.future;

      final responseText = buffer.toString().trim();

      if (responseText.isNotEmpty) {
        final completedMessage = Message(
          text: responseText,
          isUser: false,
          timestamp: DateTime.now(),
          model: _selectedModel,
          metadata: {
            'language': _userLanguage,
            if (_stopRequested) 'stopped': true,
          },
        );
        if (streamingMessageIndex == null) {
          _messages.add(completedMessage);
        } else {
          _messages[streamingMessageIndex!] = completedMessage;
        }
      } else if (!_stopRequested) {
        _messages.add(Message(
          text:
              'Lo siento, no pude generar una respuesta. Por favor, intenta de nuevo.',
          isUser: false,
          timestamp: DateTime.now(),
          model: _selectedModel,
          isError: true,
        ));
      }
    } catch (e) {
      debugPrint('[ChatServiceOllama] Error: $e');
      // Si el usuario detuvo la generación, no se muestra como error.
      if (!_stopRequested) {
        final errorText = 'Error al comunicarse con Ollama: $e';
        final errorMessage = Message(
          text:
              buffer.isEmpty ? errorText : '${buffer.toString()}\n\n$errorText',
          isUser: false,
          timestamp: DateTime.now(),
          model: _selectedModel,
          isError: true,
        );
        if (streamingMessageIndex == null) {
          _messages.add(errorMessage);
        } else {
          _messages[streamingMessageIndex!] = errorMessage;
        }
      }
    } finally {
      _streamSubscription = null;
      _streamCompleter = null;
      _isLoading = false;
      _stopRequested = false;
      await ContextService.flushMessages(_messages);
      _notifyMessages();
    }
  }

  /// Detiene la generación en curso conservando lo ya recibido.
  void stopGeneration() {
    if (!_isLoading) return;
    _stopRequested = true;
    _streamSubscription?.cancel();
    _streamSubscription = null;
    final done = _streamCompleter;
    if (done != null && !done.isCompleted) {
      done.complete();
    }
    notifyListeners();
  }

  String _buildSystemPrompt(bool hasDocumentContext) {
    final prompt =
        'Eres LightChat, un asistente útil y directo. Responde siempre en '
        '$_userLanguage.';
    if (!hasDocumentContext) return prompt;
    return '$prompt Cuando el usuario adjunta documentos, responde únicamente '
        'con la información del texto extraído, cita el nombre del archivo del '
        'que sale cada dato y di claramente que no aparece en el documento si '
        'no encuentras la respuesta. No inventes cifras ni filas.';
  }

  String _contentWithDocuments(
    Message message, {
    required bool includeDocuments,
  }) {
    if (!includeDocuments ||
        message.documents == null ||
        message.documents!.isEmpty) {
      return message.text;
    }

    final block = DocumentService.buildAttachmentContext(
      message.documents!,
      maxChars: DocumentService.maxHistoryChars,
    );
    if (block.isEmpty) {
      return message.text;
    }
    return message.text.trim().isEmpty ? block : '${message.text}\n\n$block';
  }

  String _imageMimeType(String path) {
    final extension = path.split('.').last.toLowerCase();
    return switch (extension) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      'bmp' => 'image/bmp',
      _ => 'image/jpeg',
    };
  }

  void selectModel(String model) {
    if (_availableModels.contains(model)) {
      _selectedModel = model;
      ContextService.savePreferredModel(model);
      notifyListeners();
    }
  }

  void clearMessages() {
    _messages.clear();
    _messagesVersion++;
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

  void _notifyMessages() {
    _messagesVersion++;
    notifyListeners();
  }

  @override
  void dispose() {
    _ollamaService.removeListener(_onOllamaServiceChanged);
    _streamSubscription?.cancel();
    ContextService.cancelPendingSave();
    super.dispose();
  }
}
