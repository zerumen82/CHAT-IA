import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/vllm_config.dart';
import '../config/context_config.dart';
import '../config/chat_config.dart';
import '../models/generation_phase.dart';
import 'draft_service.dart';
import '../models/prepared_context.dart';
import '../models/generated_file.dart';
import 'context_profile_service.dart';
import 'document_store_service.dart';
import 'document_context_service.dart';
import 'generated_file_service.dart';
import 'context_snapshot_service.dart';
import '../models/conversation.dart';
import '../models/document_attachment.dart';
import '../models/message.dart';
import 'context_service.dart';
import 'conversation_service.dart';
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

  bool _disposed = false;
  GenerationPhase _generationPhase = GenerationPhase.idle;
  GenerationPhase get generationPhase => _generationPhase;
  DateTime? _generationStartedAt;
  DateTime? get generationStartedAt => _generationStartedAt;
  ModelContextProfile? _selectedProfile;
  ModelContextProfile? get selectedProfile => _selectedProfile;
  int _contextRevision = 0;
  int get contextRevision => _contextRevision;
  bool _documentMode = false;
  bool get documentMode => _documentMode;
  final Set<String> _excludedSources = {};

  void _setPhase(GenerationPhase phase) {
    if (_generationPhase != phase) {
      _generationPhase = phase;
      notifyListeners();
    }
  }

  Future<void> _refreshSelectedProfile() async {
    final model = _selectedModel;
    _selectedProfile = null;
    if (model.isEmpty) {
      return;
    }
    try {
      final profile = await ContextProfileService.instance.forModel(model);
      if (!_disposed && model == _selectedModel) {
        _selectedProfile = profile;
        notifyListeners();
      }
    } catch (error) {
      debugPrint('No se pudieron consultar capacidades de $model: $error');
    }
  }

  Future<void> validateAttachments({int imageCount = 0}) async {
    if (imageCount <= 0) {
      return;
    }
    final profile =
        await ContextProfileService.instance.forModel(_selectedModel);
    if (!profile.capabilitiesKnown) {
      throw StateError(
          'No se pudieron verificar las capacidades de imágenes del '
          'modelo. Reconecta Ollama o selecciona otro modelo antes de enviar.');
    }
    if (!profile.supportsVision) {
      throw StateError('El modelo seleccionado no admite imágenes. Selecciona '
          'un modelo con visión o retira las imágenes; el borrador se conserva.');
    }
  }

  Future<void> _loadConversationSettings() async {
    _documentMode = false;
    _excludedSources.clear();
    final id = _activeConversationId;
    if (id != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString('${ChatConfig.settingsPrefix}$id');
        if (raw == null) {
          _documentMode = _messages.any((message) => message.hasDocuments);
          if (!_documentMode) {
            _documentMode = (await DocumentStoreService.instance
                    .documentsForConversation(id))
                .isNotEmpty;
          }
        } else {
          final data = jsonDecode(raw) as Map;
          _documentMode = data['documentMode'] == true;
          _excludedSources.addAll((data['excludedSources'] as List? ?? const [])
              .whereType<String>()
              .map(_normalizeSourceId));
        }
      } catch (error) {
        _storageWarning = 'No se pudieron cargar las fuentes activas: $error';
      }
    }
    _contextRevision++;
  }

  Future<void> _persistConversationSettings() async {
    final id = _activeConversationId;
    if (id == null) {
      return;
    }
    final encoded = jsonEncode({
      'documentMode': _documentMode,
      'excludedSources': _excludedSources.toList(),
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString('${ChatConfig.settingsPrefix}$id', encoded)) {
        throw StateError('No se guardó la preferencia de fuentes.');
      }
    } catch (error) {
      if (id == _activeConversationId) {
        _storageWarning = 'No se pudieron guardar las fuentes activas: $error';
        notifyListeners();
      }
    }
  }

  Future<void> setDocumentMode(bool enabled) async {
    if (_isLoading || _documentMode == enabled) {
      return;
    }
    _documentMode = enabled;
    _contextRevision++;
    notifyListeners();
    await _persistConversationSettings();
  }

  bool isSourceEnabled(DocumentAttachment document) =>
      !_excludedSources
          .contains(_normalizeSourceId(document.storageId ?? document.path)) &&
      !_excludedSources.contains(sourceKey(document));

  Future<void> setSourceEnabled(
      DocumentAttachment document, bool enabled) async {
    if (_isLoading) {
      return;
    }
    final keys = {
      document.storageId ?? document.path,
      document.path,
      sourceKey(document)
    }.map(_normalizeSourceId).toSet()
      ..remove('');
    if (enabled) {
      _excludedSources.removeAll(keys);
    } else {
      _excludedSources.addAll(keys);
    }
    _contextRevision++;
    notifyListeners();
    await _persistConversationSettings();
  }

  Future<List<DocumentAttachment>> getDocumentSources() async {
    final id = _activeConversationId;
    final messages = List<Message>.of(_messages);
    final sources = <String, DocumentAttachment>{};
    if (id != null) {
      for (final doc
          in await DocumentStoreService.instance.documentsForConversation(id)) {
        sources[sourceKey(doc)] = doc;
      }
    }
    for (final message in messages) {
      for (final doc in message.documents ?? const <DocumentAttachment>[]) {
        sources[sourceKey(doc)] = doc;
      }
    }
    return sources.values.toList();
  }

  /// La última versión de un archivo sustituye su fuente visible anterior.
  /// El almacén conserva las versiones referenciadas por otros mensajes.
  String sourceKey(DocumentAttachment document) {
    if (document.path.isEmpty) {
      return document.storageId ?? document.name;
    }
    return _normalizeSourceId(document.path);
  }

  String _normalizeSourceId(String value) {
    final normalized = value.replaceAll('\\', '/');
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  /// Continúa sin retirar la respuesta ni los turnos anteriores.
  Future<void> continueLastResponse() async {
    if (_isLoading || _messages.isEmpty || _messages.last.isUser) {
      return;
    }
    final last = _messages.last;
    if (last.text.isEmpty ||
        (last.isError && last.metadata?['partialResponse'] != true)) {
      return;
    }
    await sendMessage(ChatConfig.continuePrompt);
  }

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

  // Conversaciones guardadas
  final List<ConversationSummary> _conversations = [];
  List<ConversationSummary> get conversations => _conversations;
  String? _activeConversationId;
  String? get activeConversationId => _activeConversationId;

  // Servicios
  final OllamaService _ollamaService = OllamaService.instance;

  // Generación en curso
  StreamSubscription<OllamaChatResponse>? _streamSubscription;
  Completer<void>? _streamCompleter;
  bool _stopRequested = false;
  Completer<void>? _requestCancellation;
  Future<bool> Function()? requestStorage;
  String _storageWarning = '';
  String get storageWarning => _storageWarning;

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
    try {
      await DocumentStoreService.instance.initialize();
    } catch (error) {
      _storageWarning = 'No se pudo abrir la carpeta de documentos: $error';
    }
    // Cargar idioma preferido
    _userLanguage = await ContextService.loadUserLanguage();

    final savedConversations = await ConversationService.loadIndex();
    _conversations
      ..clear()
      ..addAll(savedConversations);

    if (_conversations.isEmpty) {
      // Primera vez: se migra el historial antiguo a una conversación.
      final legacyMessages = await ContextService.loadMessages();
      final summary = ConversationSummary(
        id: ConversationService.newId(),
        title: _titleFor(legacyMessages),
        updatedAt: DateTime.now(),
        messageCount: legacyMessages.length,
      );
      _conversations.add(summary);
      _activeConversationId = summary.id;
      _messages.addAll(legacyMessages);
      await _loadConversationSettings();
      _notifyMessages();
      return;
    }

    final savedActiveId = await ConversationService.loadActiveId();
    _activeConversationId =
        _conversations.any((conversation) => conversation.id == savedActiveId)
            ? savedActiveId
            : _conversations.first.id;
    final savedMessages = await ConversationService.loadMessages(
      _activeConversationId!,
    );
    _messages.addAll(savedMessages);
    await _loadConversationSettings();
    _notifyMessages();
  }

  /// Título automático a partir del primer mensaje del usuario.
  String _titleFor(List<Message> messages) {
    String text = '';
    for (final message in messages) {
      if (message.isUser && message.text.trim().isNotEmpty) {
        text = message.text.trim();
        break;
      }
    }
    if (text.isEmpty) {
      return ConversationSummary.defaultTitle;
    }
    final singleLine = text.replaceAll(RegExp(r'\s+'), ' ');
    return singleLine.length > 42
        ? '${singleLine.substring(0, 42)}…'
        : singleLine;
  }

  /// Mantiene el resumen de la conversación activa al día (título, fecha y
  /// número de mensajes) y lo reordena como la más reciente.
  void _syncActiveMeta() {
    final activeId = _activeConversationId;
    if (activeId == null) return;

    final index = _conversations.indexWhere(
      (conversation) => conversation.id == activeId,
    );
    if (index < 0) return;

    final current = _conversations[index];
    final hasUserMessage = _messages.any((message) => message.isUser);
    final shouldTitle =
        hasUserMessage && current.title == ConversationSummary.defaultTitle;

    _conversations[index] = current.copyWith(
      title: shouldTitle ? _titleFor(_messages) : current.title,
      updatedAt: DateTime.now(),
      messageCount: _messages.length,
    );
    _conversations.sort(
      (first, second) => second.updatedAt.compareTo(first.updatedAt),
    );
  }

  Future<void> _flushCurrentConversation() async {
    final activeId = _activeConversationId;
    if (activeId == null) return;
    await ConversationService.flushAll(
      activeId,
      _messages,
      _conversations,
    );
    ConversationService.cancelPendingSaves();
  }

  Future<void> _mutateConversation(Future<void> Function() operation) async {
    if (_isLoading) {
      return;
    }
    _isLoading = true;
    notifyListeners();
    try {
      await operation();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> newConversation() => _mutateConversation(_newConversation);
  Future<void> selectConversation(String id) =>
      _mutateConversation(() => _selectConversation(id));
  Future<void> deleteConversation(String id) =>
      _mutateConversation(() => _deleteConversation(id));
  Future<void> clearMessages() => _mutateConversation(_clearMessages);

  /// Abre una conversación nueva y vacía.
  Future<void> _newConversation() async {
    await _flushCurrentConversation();

    final summary = ConversationSummary(
      id: ConversationService.newId(),
      title: ConversationSummary.defaultTitle,
      updatedAt: DateTime.now(),
      messageCount: 0,
    );
    _conversations.insert(0, summary);
    _activeConversationId = summary.id;
    _messages.clear();
    await _loadConversationSettings();
    _messagesVersion++;
    await ConversationService.flushAll(
      summary.id,
      _messages,
      _conversations,
    );
    await ConversationService.saveActiveId(summary.id);
    notifyListeners();
  }

  /// Carga otra conversación guardada.
  Future<void> _selectConversation(String id) async {
    if (id == _activeConversationId) return;
    if (!_conversations.any((conversation) => conversation.id == id)) {
      return;
    }

    await _flushCurrentConversation();
    final loadedMessages = await ConversationService.loadMessages(id);
    _activeConversationId = id;
    _messages
      ..clear()
      ..addAll(loadedMessages);
    await _loadConversationSettings();
    _messagesVersion++;
    await ConversationService.saveActiveId(id);
    notifyListeners();
  }

  Future<void> _deleteConversation(String id) async {
    ConversationService.cancelPendingSaves();
    await DocumentStoreService.instance.deleteConversation(id);
    await GeneratedFileService.deleteConversation(id);
    await ContextSnapshotService.deleteConversation(id);
    _conversations.removeWhere((conversation) => conversation.id == id);
    await ConversationService.delete(id);
    await DraftService.instance.delete(id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('${ChatConfig.settingsPrefix}$id');
    await ConversationService.saveIndex(_conversations);

    if (_activeConversationId != id) {
      notifyListeners();
      return;
    }

    _activeConversationId = null;
    _messages.clear();
    _messagesVersion++;

    if (_conversations.isEmpty) {
      await _newConversation();
      return;
    }

    final next = _conversations.first;
    final loadedMessages = await ConversationService.loadMessages(next.id);
    _activeConversationId = next.id;
    _messages.addAll(loadedMessages);
    await _loadConversationSettings();
    _messagesVersion++;
    await ConversationService.saveActiveId(next.id);
    notifyListeners();
  }

  Future<void> renameConversation(String id, String title) async {
    final index = _conversations.indexWhere(
      (conversation) => conversation.id == id,
    );
    final trimmed = title.trim();
    if (index < 0 || trimmed.isEmpty) return;

    _conversations[index] = _conversations[index].copyWith(
      title: trimmed,
      updatedAt: DateTime.now(),
    );
    _conversations.sort(
      (first, second) => second.updatedAt.compareTo(first.updatedAt),
    );
    await ConversationService.saveIndex(_conversations);
    notifyListeners();
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

      unawaited(_refreshSelectedProfile());
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

    await _rerunFrom(userIndex);
  }

  /// Vuelve a pedir la última respuesta al modelo, descartándola.
  Future<void> regenerateLastResponse() async {
    if (_isLoading || !_isConnected || _selectedModel.isEmpty) {
      return;
    }

    final lastIndex = _messages.length - 1;
    if (lastIndex < 0 || _messages[lastIndex].isUser) {
      return;
    }

    final userIndex = _messages.lastIndexWhere((message) => message.isUser);
    if (userIndex < 0) {
      return;
    }

    await _rerunFrom(userIndex);
  }

  /// Sustituye el texto de un mensaje del usuario y vuelve a preguntar,
  /// descartando la conversación posterior a ese mensaje.
  Future<void> editAndResend(int index, String newText) async {
    if (_isLoading || !_isConnected || _selectedModel.isEmpty) {
      return;
    }
    if (index < 0 || index >= _messages.length) {
      return;
    }

    final message = _messages[index];
    final text = newText.trim();
    if (!message.isUser || text.isEmpty) {
      return;
    }

    await validateAttachments(imageCount: _imagePathsOf(message)?.length ?? 0);

    if (index < _messages.length - 1) {
      _messages.removeRange(index + 1, _messages.length);
    }
    _messages[index] = message.copyWith(text: text);
    _notifyMessages();

    await _sendMessage(
      text,
      imagePaths: _imagePathsOf(message),
      documents: _documentsOf(message),
      addUserMessage: false,
    );
  }

  List<String>? _imagePathsOf(Message message) {
    final paths = message.images
        ?.map((image) => image.localPath)
        .whereType<String>()
        .toList();
    return paths == null || paths.isEmpty ? null : paths;
  }

  List<DocumentAttachment>? _documentsOf(Message message) {
    final documents =
        message.documents?.where((document) => document.isReady).toList();
    return documents == null || documents.isEmpty ? null : documents;
  }

  /// Reenvía el turno que empieza en [userIndex] conservando sus adjuntos.
  Future<void> _rerunFrom(int userIndex) async {
    final userMessage = _messages[userIndex];
    final imagePaths = _imagePathsOf(userMessage);
    final documents = _documentsOf(userMessage);

    if (userMessage.text.trim().isEmpty &&
        imagePaths == null &&
        documents == null) {
      return;
    }

    await validateAttachments(imageCount: imagePaths?.length ?? 0);

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
    VoidCallback? onAccepted,
  }) {
    return _sendMessage(
      text,
      imagePaths: imagePaths,
      documents: documents,
      addUserMessage: true,
      onAccepted: onAccepted,
    );
  }

  /// El mismo planificador alimenta la vista previa y la petición final.
  Future<PreparedContext> previewContext(
      String query, List<DocumentAttachment> attachments,
      {List<OllamaImage>? images, int currentImageCount = 0}) async {
    final profile =
        await ContextProfileService.instance.forModel(_selectedModel);
    final sources = <String, DocumentAttachment>{};
    if (_documentMode) {
      for (final doc in await getDocumentSources()) {
        if (isSourceEnabled(doc)) {
          sources[sourceKey(doc)] = doc;
        }
      }
      for (final doc in attachments) {
        if (isSourceEnabled(doc)) {
          sources[sourceKey(doc)] = doc;
        }
      }
    }
    final useTools = profile.supportsTools;
    final system = _buildSystemPrompt(sources.isNotEmpty) +
        (useTools
            ? ' ${ContextConfig.toolPrompt}'
            : ' Para crear archivos, elige una carpeta en Contexto y archivos y usa un modelo con herramientas. No inventes enlaces.');
    final responseTokens =
        math.min(OllamaConfig.maxResponseTokens, profile.tokens ~/ 4);
    final toolChars =
        useTools ? jsonEncode(GeneratedFileService.tools).length : 0;
    final imageTokens = (images?.length ?? currentImageCount) *
        ContextConfig.imageReserveTokens;
    final available = (profile.tokens -
                responseTokens -
                ContextConfig.safetyTokens -
                imageTokens -
                ContextConfig.messageOverheadTokens * 2) *
            ContextConfig.charsPerToken -
        system.length -
        toolChars -
        query.length;
    if (available < 0) {
      throw StateError(
          'La pregunta y las imágenes superan el contexto del modelo. Reduce el texto o selecciona un perfil mayor.');
    }
    final historyLimit = sources.isEmpty
        ? available
        : (available * ContextConfig.historyShare).floor();
    var historyChars = 0;
    final history = <OllamaMessage>[];
    // Las respuestas documentales llevan procedencia. No reintroducir fuentes
    // desmarcadas a través de una respuesta previa ni al volver al chat general.
    final previous = <Message>[];
    var documentaryTurn = false;
    var turnSourceIds = <String>[];
    var unknownDocumentSources = false;
    for (final message in _messages) {
      if (message.isUser) {
        documentaryTurn = message.metadata?['documentMode'] == true ||
            message.hasDocuments ||
            message.metadata?['contextSnapshot'] != null;
        turnSourceIds = (message.metadata?['sourceIds'] as List? ?? const [])
            .whereType<String>()
            .map(_normalizeSourceId)
            .toList();
        unknownDocumentSources = documentaryTurn && turnSourceIds.isEmpty;
      }
      final sourceIds = (message.metadata?['sourceIds'] as List?)
              ?.whereType<String>()
              .map(_normalizeSourceId)
              .toList() ??
          turnSourceIds;
      final documentaryAnswer = !message.isUser &&
          (message.metadata?['documentMode'] == true || documentaryTurn);
      if (documentaryAnswer &&
          (!_documentMode ||
              sourceIds.any(_excludedSources.contains) ||
              (unknownDocumentSources && _excludedSources.isNotEmpty))) {
        continue;
      }
      if (!message.isError || message.metadata?['partialResponse'] == true) {
        previous.add(message);
      }
    }
    for (final message in previous.reversed) {
      final content = message.generatedFiles.isEmpty
          ? message.text
          : '${message.text}\nArchivos creados: ${message.generatedFiles.map((file) => file.name).join(', ')}';
      final cost = content.length +
          (message.images?.length ?? 0) *
              ContextConfig.imageReserveTokens *
              ContextConfig.charsPerToken +
          ContextConfig.messageOverheadTokens * ContextConfig.charsPerToken;
      if (historyChars + cost > historyLimit) {
        break;
      }
      final contextImages = <OllamaImage>[];
      for (final image in profile.supportsVision
          ? message.images ?? const <MessageImage>[]
          : const <MessageImage>[]) {
        if (image.base64Data != null) {
          contextImages.add(OllamaImage(image.base64Data!));
        } else if (image.localPath != null) {
          try {
            contextImages.add(OllamaImage.fromBytes(
                await File(image.localPath!).readAsBytes()));
          } catch (error) {
            debugPrint('Imagen del historial no disponible: $error');
          }
        }
      }
      history.insert(
          0,
          OllamaMessage(
              role: message.isUser ? 'user' : 'assistant',
              content: content,
              images: contextImages.isEmpty ? null : contextImages));
      historyChars += cost;
    }
    final budget = math.max(0, available - historyChars);
    final plan = await DocumentContextService().plan(
        query: query, documents: sources.values.toList(), maxChars: budget);
    final content = plan.text.isEmpty ? query : '$query\n\n${plan.text}';
    final messages = <OllamaMessage>[
      OllamaMessage(role: 'system', content: system),
      ...history,
      OllamaMessage(role: 'user', content: content, images: images)
    ];
    final estimated = ((system.length +
                    toolChars +
                    query.length +
                    historyChars +
                    plan.text.length) /
                ContextConfig.charsPerToken)
            .ceil() +
        imageTokens +
        ContextConfig.messageOverheadTokens * 2;
    return PreparedContext(
        documents: plan,
        profile: profile,
        messages: messages,
        responseTokens: responseTokens,
        documentBudgetChars: budget,
        estimatedPromptTokens: estimated,
        historyPartial: history.length <
            _messages
                .where(
                    (m) => !m.isError || m.metadata?['partialResponse'] == true)
                .length);
  }

  Future<void> _sendMessage(String text,
      {List<String>? imagePaths,
      List<DocumentAttachment>? documents,
      required bool addUserMessage,
      VoidCallback? onAccepted}) async {
    var readyDocuments = (documents ?? const <DocumentAttachment>[])
        .where((d) => d.isReady)
        .toList();
    if (_isLoading ||
        !_isConnected ||
        _selectedModel.isEmpty ||
        _activeConversationId == null ||
        (text.trim().isEmpty &&
            !(imagePaths?.isNotEmpty ?? false) &&
            readyDocuments.isEmpty)) {
      return;
    }
    _isLoading = true;
    _stopRequested = false;
    _requestCancellation = Completer<void>();
    _generationStartedAt = DateTime.now();
    _setPhase(GenerationPhase.preparing);
    final buffer = StringBuffer();
    final generated = <GeneratedFile>[];
    int? streamingIndex;
    int? promptEvalCount;
    int? evalCount;
    int? totalDuration;
    int? loadDuration;
    int? evalDuration;
    String? doneReason;
    var receivedDone = false;
    Map<String, dynamic> contextMetadata = {};
    var userAdded = !addUserMessage;
    try {
      await validateAttachments(imageCount: imagePaths?.length ?? 0);
      final trimmed = text.trim();
      if (trimmed.isNotEmpty && trimmed.split(RegExp(r'\s+')).length >= 3) {
        _userLanguage = ContextService.detectLanguage(trimmed);
        await ContextService.saveUserLanguage(_userLanguage);
      }
      final store = DocumentStoreService.instance;
      if (readyDocuments.isNotEmpty &&
          store.rootPath == null &&
          requestStorage != null) {
        final configured = await requestStorage!();
        if (!configured) {
          _storageWarning =
              'Sin carpeta: el texto completo de estos adjuntos no se conservará tras cerrar la app.';
        }
      }
      if (store.rootPath != null && _activeConversationId != null) {
        for (var index = 0; index < _messages.length; index++) {
          final old = _messages[index];
          if (!old.hasDocuments) {
            continue;
          }
          final migrated = <DocumentAttachment>[];
          for (final doc in old.documents!) {
            migrated.add(
                await store.put(doc, conversationId: _activeConversationId!));
          }
          _messages[index] = old.copyWith(documents: migrated);
        }
        final stored = <DocumentAttachment>[];
        for (final doc in readyDocuments) {
          stored.add(
              await store.put(doc, conversationId: _activeConversationId!));
        }
        readyDocuments = stored;
      }
      final images = <OllamaImage>[];
      final messageImages = <MessageImage>[];
      for (final path in imagePaths ?? const <String>[]) {
        final bytes = await File(path).readAsBytes();
        images.add(OllamaImage.fromBytes(bytes));
        messageImages.add(MessageImage(
            id: '${DateTime.now().microsecondsSinceEpoch}-${images.length}',
            localPath: path,
            width: 0,
            height: 0,
            sizeBytes: bytes.length,
            mimeType: _imageMimeType(path)));
      }
      Message? rerunUser;
      if (!addUserMessage && _messages.isNotEmpty && _messages.last.isUser) {
        rerunUser = _messages.removeLast();
      }
      late PreparedContext prepared;
      try {
        prepared = await previewContext(text, readyDocuments,
            images: images.isEmpty ? null : images);
      } finally {
        if (rerunUser != null) {
          _messages.add(rerunUser);
        }
      }
      if (text.trim().isEmpty &&
          images.isEmpty &&
          prepared.documents.text.isEmpty) {
        throw StateError('Escribe una pregunta o activa una fuente documental '
            'antes de enviar. El borrador se conserva.');
      }
      if (_stopRequested) {
        return;
      }
      final contextSnapshot =
          prepared.documents.text.isNotEmpty && store.rootPath != null
              ? await ContextSnapshotService.save(
                  _activeConversationId!, prepared.documents.text)
              : null;
      final sourceIds = <String>{};
      if (_documentMode) {
        for (final doc in await getDocumentSources()) {
          if (isSourceEnabled(doc)) {
            sourceIds
                .addAll([doc.storageId ?? doc.path, doc.path, sourceKey(doc)]);
          }
        }
        for (final doc in readyDocuments) {
          if (isSourceEnabled(doc)) {
            sourceIds
                .addAll([doc.storageId ?? doc.path, doc.path, sourceKey(doc)]);
          }
        }
      }
      sourceIds.remove('');
      contextMetadata = <String, dynamic>{
        'documentMode': _documentMode,
        'sourceIds': sourceIds.toList(),
        if (contextSnapshot != null) 'contextSnapshot': contextSnapshot,
        'contextTokens': prepared.profile.tokens,
        'estimatedPromptTokens': prepared.estimatedPromptTokens,
        'documentBudgetChars': prepared.documentBudgetChars,
        'contextText': prepared.documents.text,
        'contextPartial': prepared.documents.isPartial,
        'contextWarnings': prepared.documents.warnings,
        'historyPartial': prepared.historyPartial,
      };
      if (addUserMessage) {
        _messages.add(Message(
            text: text,
            isUser: true,
            timestamp: DateTime.now(),
            model: _selectedModel,
            images: messageImages.isEmpty ? null : messageImages,
            documents: readyDocuments.isEmpty ? null : readyDocuments,
            metadata: contextMetadata));
        userAdded = true;
      } else if (_messages.isNotEmpty) {
        _messages[_messages.length - 1] =
            _messages.last.copyWith(metadata: contextMetadata);
      }
      _notifyMessages();
      onAccepted?.call();
      _setPhase(GenerationPhase.waiting);
      final calls = <Map<String, dynamic>>[];
      var notifiedLength = 0;
      final done = Completer<void>();
      _streamCompleter = done;
      final toolsEnabled = prepared.profile.supportsTools;
      _streamSubscription = _ollamaService
          .generateChat(
        model: _selectedModel,
        messages: prepared.messages,
        temperature: prepared.documents.text.isEmpty
            ? OllamaConfig.defaultTemperature
            : OllamaConfig.documentTemperature,
        numPredict: prepared.responseTokens,
        numCtx: prepared.profile.tokens,
        think: OllamaConfig.isThinkingModel(_selectedModel) ? false : null,
        tools: toolsEnabled ? GeneratedFileService.tools : null,
        cancellation: _requestCancellation!.future,
      )
          .listen((response) {
        promptEvalCount = response.promptEvalCount ?? promptEvalCount;
        evalCount = response.evalCount ?? evalCount;
        totalDuration = response.totalDuration ?? totalDuration;
        loadDuration = response.loadDuration ?? loadDuration;
        evalDuration = response.evalDuration ?? evalDuration;
        if (response.done) {
          receivedDone = true;
          doneReason = response.doneReason;
        }
        if (response.thinking.isNotEmpty) {
          _setPhase(GenerationPhase.thinking);
        }
        calls.addAll(response.toolCalls);
        if (response.message.isEmpty || _stopRequested) {
          return;
        }
        _setPhase(GenerationPhase.responding);
        buffer.write(response.message);
        final partial = Message(
            text: buffer.toString(),
            isUser: false,
            timestamp: DateTime.now(),
            model: _selectedModel);
        if (streamingIndex == null) {
          streamingIndex = _messages.length;
          _messages.add(partial);
        } else {
          _messages[streamingIndex!] = partial;
        }
        if (buffer.length - notifiedLength >= 24) {
          notifiedLength = buffer.length;
          _notifyMessages();
        }
      }, onError: (Object error, StackTrace stack) {
        if (!done.isCompleted) {
          done.completeError(error, stack);
        }
      }, onDone: () {
        if (!done.isCompleted) {
          done.complete();
        }
      }, cancelOnError: true);
      if (_stopRequested) {
        await _streamSubscription?.cancel();
        if (!done.isCompleted) {
          done.complete();
        }
      }
      await done.future;
      if (!_stopRequested && !receivedDone) {
        throw const HttpException(
            'La respuesta se interrumpió antes de terminar.');
      }
      if (!_stopRequested && calls.isNotEmpty) {
        _setPhase(GenerationPhase.creatingFiles);
        if (!toolsEnabled) {
          throw StateError(
              'El modelo intentó usar una herramienta no habilitada.');
        }
        if (calls.length > ContextConfig.maxToolCalls) {
          throw StateError('Se pidieron demasiados archivos en una respuesta.');
        }
        if (store.rootPath == null) {
          if (requestStorage == null || !await requestStorage!()) {
            throw StateError(
                'Creación de archivos cancelada: selecciona una carpeta en Contexto y archivos.');
          }
        }
        final seen = <String>{};
        for (final call in calls) {
          if (_stopRequested) {
            break;
          }
          if (!seen.add(jsonEncode(call))) {
            continue;
          }
          generated.add(await GeneratedFileService.create(
              call: call, conversationId: _activeConversationId!));
        }
        buffer.clear();
        if (generated.isNotEmpty) {
          buffer.write('Archivos creados. Usa Guardar para elegir el destino.');
        }
      }
      if (buffer.isEmpty && generated.isEmpty && !_stopRequested) {
        throw StateError('El modelo no devolvió contenido ni archivos.');
      }
      if (_stopRequested && buffer.isEmpty && generated.isEmpty) {
        buffer.write('Generación detenida antes de recibir texto.');
      }
      if (buffer.isNotEmpty || generated.isNotEmpty) {
        final completed = Message(
            text: buffer.toString().trim(),
            isUser: false,
            timestamp: DateTime.now(),
            model: _selectedModel,
            generatedFiles: generated,
            tokenCount: promptEvalCount,
            metadata: {
              ...contextMetadata,
              'finishReason': _stopRequested
                  ? 'stopped'
                  : doneReason == 'length'
                      ? 'length'
                      : 'completed',
              if (doneReason != null) 'doneReason': doneReason,
              if (evalCount != null) 'evalCount': evalCount,
              if (totalDuration != null) 'totalDuration': totalDuration,
              if (loadDuration != null) 'loadDuration': loadDuration,
              if (evalDuration != null) 'evalDuration': evalDuration,
              'elapsedMs': DateTime.now()
                  .difference(_generationStartedAt!)
                  .inMilliseconds,
              'contextTokens': prepared.profile.tokens,
              'estimatedPromptTokens': prepared.estimatedPromptTokens,
              if (promptEvalCount != null) 'promptEvalCount': promptEvalCount,
              if (_stopRequested) 'stopped': true
            });
        if (streamingIndex == null) {
          _messages.add(completed);
        } else {
          _messages[streamingIndex!] = completed;
        }
      }
    } catch (error) {
      if (!_stopRequested) {
        if (!userAdded) {
          // El compositor sólo retira el borrador después de onAccepted.
          rethrow;
        }
        final hasPartial = buffer.isNotEmpty;
        final failure = Message(
            text: hasPartial
                ? buffer.toString().trim()
                : 'No se pudo completar la petición: $error',
            isUser: false,
            isError: true,
            timestamp: DateTime.now(),
            model: _selectedModel,
            generatedFiles: generated,
            metadata: {
              ...contextMetadata,
              'finishReason': 'interrupted',
              'partialResponse': hasPartial,
              'error': error.toString(),
              'elapsedMs': DateTime.now()
                  .difference(_generationStartedAt!)
                  .inMilliseconds,
            });
        if (streamingIndex == null) {
          _messages.add(failure);
        } else {
          _messages[streamingIndex!] = failure;
        }
      }
    } finally {
      final cancellation = _requestCancellation;
      if (cancellation != null && !cancellation.isCompleted) {
        cancellation.complete();
      }
      await _streamSubscription?.cancel();
      _streamSubscription = null;
      _streamCompleter = null;
      _requestCancellation = null;
      _setPhase(GenerationPhase.saving);
      await _flushCurrentConversation();
      _isLoading = false;
      _stopRequested = false;
      _generationStartedAt = null;
      _setPhase(GenerationPhase.idle);
      _notifyMessages();
    }
  }

  /// Pide cancelar el transporte; sigue ocupado hasta que su cierre termina.
  void stopGeneration() {
    if (!_isLoading || _generationPhase == GenerationPhase.idle) {
      return;
    }
    _stopRequested = true;
    final cancellation = _requestCancellation;
    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.complete();
    }
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
        'que sale cada dato y di claramente que no aparece en el texto adjunto '
        'si no encuentras la respuesta. Si el texto lleva una marca de recorte, '
        'indica que solo has recibido una parte del documento. No inventes '
        'cifras ni filas. Los fragmentos recuperados no son una lectura exhaustiva: '
        'no calcules sumas ni recuentos globales si la cobertura es parcial.';
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
    if (_isLoading) {
      return;
    }
    if (_availableModels.contains(model)) {
      _selectedModel = model;
      unawaited(_refreshSelectedProfile());
      ContextService.savePreferredModel(model);
      notifyListeners();
    }
  }

  Future<void> _clearMessages() async {
    final id = _activeConversationId;
    if (id == null) {
      return;
    }
    ConversationService.cancelPendingSaves();
    await DocumentStoreService.instance.deleteConversation(id);
    await GeneratedFileService.deleteConversation(id);
    await ContextSnapshotService.deleteConversation(id);
    await DraftService.instance.clear(id);
    _documentMode = false;
    _excludedSources.clear();
    _contextRevision++;
    await _persistConversationSettings();
    _messages.clear();
    _messagesVersion++;
    _syncActiveMeta();
    await ConversationService.flushAll(id, _messages, _conversations);
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
    _syncActiveMeta();
    final activeId = _activeConversationId;
    if (activeId != null) {
      ConversationService.saveMessagesDebounced(activeId, _messages);
      ConversationService.saveIndexDebounced(_conversations);
    }
    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (!_disposed) {
      super.notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    final cancellation = _requestCancellation;
    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.complete();
    }
    final done = _streamCompleter;
    if (done != null && !done.isCompleted) {
      done.complete();
    }
    _ollamaService.removeListener(_onOllamaServiceChanged);
    _streamSubscription?.cancel();
    ContextService.cancelPendingSave();
    ConversationService.cancelPendingSaves();
    super.dispose();
  }
}
