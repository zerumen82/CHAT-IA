import 'dart:async';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import '../services/document_store_service.dart';
import '../widgets/context_settings_dialog.dart';
import '../widgets/file_actions.dart';
import '../widgets/chat_sources_dialog.dart';
import '../widgets/generation_status.dart';
import '../config/ui_config.dart';
import '../services/context_profile_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:lightchat/models/document_attachment.dart';
import 'package:lightchat/screens/ollama_manager_screen.dart';
import 'package:lightchat/services/chat_service_ollama.dart';
import 'package:lightchat/services/ollama_service.dart';
import 'package:lightchat/widgets/capsule_icon.dart';
import 'package:lightchat/widgets/chat_input.dart';
import 'package:lightchat/widgets/conversation_sidebar.dart';
import 'package:lightchat/widgets/message_bubble.dart';
import 'package:lightchat/widgets/model_selector.dart';
import 'package:lightchat/widgets/ollama_status_widget.dart';

/// Pantalla principal de chat con diseño estilo mensajería
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<ChatInputState> _chatInputKey = GlobalKey<ChatInputState>();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ValueNotifier<bool> _followingLatest = ValueNotifier(true);
  bool _showSidebar = true;
  bool _isDraggingFiles = false;
  bool _autoScroll = true;
  bool _scrollScheduled = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _followingLatest.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    _autoScroll = position.maxScrollExtent - position.pixels < 120;
    _followingLatest.value = _autoScroll;
  }

  /// Baja al final solo si el usuario ya estaba abajo, para no interrumpir
  /// la lectura mientras llega la respuesta en streaming.
  void _scheduleAutoScroll() {
    if (_scrollScheduled) {
      return;
    }
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (!mounted || !_scrollController.hasClients || !_autoScroll) {
        return;
      }
      final position = _scrollController.position;
      if (position.maxScrollExtent - position.pixels <= 0.5) {
        return;
      }
      _scrollController.jumpTo(position.maxScrollExtent);
    });
  }

  Future<bool> _submitMessage(
    String text,
    List<XFile>? images,
    List<DocumentAttachment>? documents,
  ) async {
    final chatService = context.read<ChatServiceOllama>();

    chatService.requestStorage = () async {
      if (!mounted) {
        return false;
      }
      final path = await getDirectoryPath(
          confirmButtonText: 'Usar para documentos de LightChat');
      if (path == null) {
        return false;
      }
      await DocumentStoreService.instance.configureRoot(path);
      return true;
    };
    List<String>? imagePaths;
    if (images != null && images.isNotEmpty) {
      imagePaths = images.map((img) => img.path).toList();
    }

    if (text.isNotEmpty ||
        (imagePaths?.isNotEmpty ?? false) ||
        (documents?.isNotEmpty ?? false)) {
      _jumpToLatest();
      await chatService.validateAttachments(
          imageCount: imagePaths?.length ?? 0);
      final accepted = Completer<bool>();
      Future<void> send() async {
        try {
          await chatService.sendMessage(
            text,
            imagePaths: imagePaths,
            documents: documents,
            onAccepted: () {
              if (!accepted.isCompleted) {
                accepted.complete(true);
              }
            },
          );
        } catch (error, stack) {
          if (!accepted.isCompleted) {
            accepted.completeError(error, stack);
          } else if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('No se pudo completar o guardar: $error')));
          }
        } finally {
          if (!accepted.isCompleted) {
            accepted.complete(false);
          }
        }
      }

      unawaited(send());
      return accepted.future;
    }
    return false;
  }

  void _jumpToLatest() {
    _autoScroll = true;
    _followingLatest.value = true;
    _scheduleAutoScroll();
  }

  void _retryMessage() {
    context.read<ChatServiceOllama>().retryLastMessage();
  }

  void _regenerateResponse() {
    _autoScroll = true;
    _scheduleAutoScroll();
    context.read<ChatServiceOllama>().regenerateLastResponse();
  }

  /// Edita un mensaje del usuario y lo vuelve a enviar.
  Future<void> _editMessage(int index, String currentText) async {
    final controller = TextEditingController(text: currentText);
    final chatService = context.read<ChatServiceOllama>();

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Editar mensaje'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                minLines: 3,
                maxLines: 8,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Mensaje',
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Al reenviar se descarta lo que venga después y el modelo '
                'vuelve a responder.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Reenviar'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (result == null) {
      return;
    }
    final text = result.trim();
    if (text.isEmpty || text == currentText.trim()) {
      return;
    }

    _autoScroll = true;
    _scheduleAutoScroll();
    await chatService.editAndResend(index, text);
  }

  void _stopGeneration() {
    context.read<ChatServiceOllama>().stopGeneration();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        // En ventanas estrechas la barra lateral deja el chat sin sitio.
        final canShowSidebar =
            constraints.maxWidth >= UiConfig.sidebarBreakpoint;
        final showSidebar = _showSidebar && canShowSidebar;

        return Scaffold(
          key: _scaffoldKey,
          drawer: canShowSidebar
              ? null
              : Drawer(
                  child: SafeArea(
                      child: ConversationSidebar(
                    onConversationSelected: () =>
                        _scaffoldKey.currentState?.closeDrawer(),
                  )),
                ),
          backgroundColor: colorScheme.surface,
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(kToolbarHeight),
            child: Consumer<ChatServiceOllama>(
              builder: (context, chatService, _) =>
                  _buildAppBar(context, chatService, canShowSidebar),
            ),
          ),
          body: DropTarget(
            enable: ModalRoute.of(context)?.isCurrent ?? true,
            onDragEntered: (_) {
              setState(() => _isDraggingFiles = true);
            },
            onDragExited: (_) {
              setState(() => _isDraggingFiles = false);
            },
            onDragDone: (details) {
              setState(() => _isDraggingFiles = false);
              _chatInputKey.currentState?.addFiles(details.files);
            },
            child: Row(
              children: [
                if (showSidebar) ...[
                  SizedBox(
                    width: math.min(
                        UiConfig.sidebarWidth, constraints.maxWidth * 0.38),
                    child: const ConversationSidebar(),
                  ),
                  VerticalDivider(width: 1, color: colorScheme.outlineVariant),
                ],
                Expanded(
                  child: Stack(
                    children: [
                      Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                  maxWidth: UiConfig.readingWidth),
                              child: Column(
                                children: [
                                  Selector<ChatServiceOllama, bool>(
                                    selector: (_, chatService) =>
                                        chatService.availableModels.isEmpty,
                                    builder: (context, noModels, _) {
                                      if (!noModels) {
                                        return const SizedBox.shrink();
                                      }
                                      return Selector<OllamaService, bool>(
                                        selector: (_, ollama) =>
                                            ollama.serverInfo.status !=
                                            OllamaStatus.running,
                                        builder: (context, offline, _) =>
                                            offline
                                                ? const OllamaQuickConnect()
                                                : const SizedBox.shrink(),
                                      );
                                    },
                                  ),
                                  _buildContextBar(),
                                  Expanded(
                                    child: Selector<ChatServiceOllama, int>(
                                      selector: (_, chatService) =>
                                          chatService.messagesVersion,
                                      builder: (context, _, __) =>
                                          _buildMessageList(context
                                              .read<ChatServiceOllama>()),
                                    ),
                                  ),
                                  Consumer<ChatServiceOllama>(
                                      builder: (context, chat, _) =>
                                          chat.isLoading
                                              ? GenerationStatus(
                                                  phase: chat.generationPhase,
                                                  startedAt:
                                                      chat.generationStartedAt,
                                                  onStop: _stopGeneration,
                                                )
                                              : const SizedBox.shrink()),
                                  Selector<ChatServiceOllama, String>(
                                      selector: (_, chat) =>
                                          chat.storageWarning,
                                      builder: (context, warning, _) => warning
                                              .isEmpty
                                          ? const SizedBox.shrink()
                                          : Padding(
                                              padding: const EdgeInsets.all(8),
                                              child: Text(warning,
                                                  style: TextStyle(
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .error)))),
                                  Selector<
                                      ChatServiceOllama,
                                      ({
                                        bool loading,
                                        bool connected,
                                        String model,
                                        String? conversationId,
                                        int messagesVersion,
                                        int sourceRevision,
                                        bool? supportsVision,
                                      })>(
                                    selector: (_, chatService) => (
                                      loading: chatService.isLoading,
                                      connected: chatService.isConnected &&
                                          chatService
                                              .availableModels.isNotEmpty,
                                      model: chatService.selectedModel,
                                      conversationId:
                                          chatService.activeConversationId,
                                      messagesVersion:
                                          chatService.messagesVersion,
                                      sourceRevision:
                                          chatService.contextRevision,
                                      supportsVision: chatService
                                                  .selectedProfile
                                                  ?.capabilitiesKnown ==
                                              true
                                          ? chatService
                                              .selectedProfile!.supportsVision
                                          : null,
                                    ),
                                    builder: (context, state, _) => ChatInput(
                                      key: _chatInputKey,
                                      onSubmit: _submitMessage,
                                      draftId: state.conversationId,
                                      supportsVision: state.supportsVision,
                                      onChooseVisionModel: _chooseVisionModel,
                                      sourceRevision: state.sourceRevision,
                                      onDocumentsAttached: (document) {
                                        final chat =
                                            context.read<ChatServiceOllama>();
                                        unawaited(chat.setDocumentMode(true));
                                        unawaited(chat.setSourceEnabled(
                                            document, true));
                                      },
                                      contextRevision: (
                                        model: state.model,
                                        conversationId: state.conversationId,
                                        messagesVersion: state.messagesVersion,
                                      ),
                                      onPreviewContext: !state.connected
                                          ? null
                                          : (text, documents, imageCount) =>
                                              context
                                                  .read<ChatServiceOllama>()
                                                  .previewContext(
                                                      text, documents,
                                                      currentImageCount:
                                                          imageCount),
                                      busy: state.loading,
                                      connected: state.connected,
                                    ),
                                  ),
                                ],
                              ))),
                      if (_isDraggingFiles) _buildDropOverlay(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDropOverlay() {
    final colorScheme = Theme.of(context).colorScheme;

    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: colorScheme.primary.withValues(alpha: 0.08),
          alignment: Alignment.center,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: colorScheme.primary, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.upload_file,
                  size: 40,
                  color: colorScheme.primary,
                ),
                const SizedBox(height: 12),
                Text(
                  'Suelta para adjuntar',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'PDF, Word, Excel, PowerPoint o imágenes',
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContextBar() => Consumer<ChatServiceOllama>(
        builder: (context, chat, _) {
          final profile = chat.selectedProfile;
          final capabilities = profile?.capabilitiesKnown == true
              ? [
                  'Texto',
                  if (profile!.supportsVision) 'Imágenes',
                  if (profile.supportsTools) 'Crear archivos'
                ].join(' · ')
              : 'Capacidades del modelo por comprobar';
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SegmentedButton<bool>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                            value: false,
                            label: Text('Chat general'),
                            icon: Icon(Icons.chat_bubble_outline, size: 16)),
                        ButtonSegment(
                            value: true,
                            label: Text('Consultar documentos'),
                            icon: Icon(Icons.description_outlined, size: 16)),
                      ],
                      selected: {chat.documentMode},
                      onSelectionChanged: chat.isLoading
                          ? null
                          : (values) => chat.setDocumentMode(values.first),
                      style: const ButtonStyle(
                          visualDensity: VisualDensity.compact),
                    ),
                    TextButton.icon(
                        onPressed: chat.isLoading
                            ? null
                            : () async {
                                try {
                                  await showChatSources(context,
                                      additionalDocuments: _chatInputKey
                                              .currentState
                                              ?.documentAttachments ??
                                          const []);
                                } catch (error) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                            content: Text(
                                                'No se pudieron abrir las fuentes: $error')));
                                  }
                                }
                              },
                        icon: const Icon(Icons.folder_open, size: 18),
                        label: const Text('Fuentes')),
                  ]),
              const SizedBox(height: 4),
              Text(capabilities, style: Theme.of(context).textTheme.bodySmall),
            ]),
          );
        },
      );

  Future<void> _chooseVisionModel() async {
    final chat = context.read<ChatServiceOllama>();
    if (chat.isLoading) {
      return;
    }
    final models = List<String>.of(chat.availableModels);
    final profiles = Future.wait(models.map((name) async =>
        (name, await ContextProfileService.instance.forModel(name))));
    final selected = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: const Text('Modelo para imágenes'),
              content: SizedBox(
                  width: 520,
                  child: FutureBuilder(
                    future: profiles,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Text(
                            'No se pudieron consultar las capacidades: ${snapshot.error}');
                      }
                      if (!snapshot.hasData) {
                        return const Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(child: CircularProgressIndicator()));
                      }
                      final compatible = snapshot.data!
                          .where((entry) =>
                              entry.$2.capabilitiesKnown &&
                              entry.$2.supportsVision)
                          .toList();
                      if (compatible.isEmpty) {
                        return const Text(
                            'Ningún modelo instalado tiene visión confirmada. Puedes retirar '
                            'las imágenes o instalar un modelo compatible desde el gestor. '
                            'El borrador se conserva.');
                      }
                      return Column(mainAxisSize: MainAxisSize.min, children: [
                        for (final entry in compatible)
                          ListTile(
                              title: Text(entry.$1),
                              leading: const Icon(Icons.image_outlined),
                              onTap: () =>
                                  Navigator.pop(dialogContext, entry.$1)),
                      ]);
                    },
                  )),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Cancelar'))
              ],
            ));
    if (selected != null && mounted && !chat.isLoading) {
      chat.selectModel(selected);
    }
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    ChatServiceOllama chatService,
    bool canShowSidebar,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 1,
      backgroundColor: colorScheme.surface,
      leading: canShowSidebar
          ? IconButton(
              tooltip: _showSidebar
                  ? 'Ocultar conversaciones'
                  : 'Mostrar conversaciones',
              onPressed: () => setState(() => _showSidebar = !_showSidebar),
              icon: Icon(_showSidebar ? Icons.menu_open : Icons.menu),
            )
          : IconButton(
              tooltip: 'Mostrar conversaciones',
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              icon: const Icon(Icons.menu)),
      title: Row(
        children: [
          const CapsuleIcon(size: 28),
          const SizedBox(width: 12),
          Text(
            'LightChat',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colorScheme.primary,
            ),
          ),
        ],
      ),
      actions: [
        const ModelSelector(),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          tooltip: 'Más opciones',
          onSelected: (value) => _handleMenuAction(value, chatService),
          itemBuilder: (context) => [
            PopupMenuItem(
                value: 'context',
                enabled: !chatService.isLoading,
                child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.data_usage),
                    title: Text('Contexto y archivos'))),
            PopupMenuItem(
                value: 'export',
                enabled:
                    !chatService.isLoading && chatService.messages.isNotEmpty,
                child: const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.save_alt),
                    title: Text('Exportar conversación'))),
            PopupMenuItem(
              value: 'ollama_manager',
              child: Row(
                children: [
                  Icon(Icons.dns, size: 20, color: colorScheme.primary),
                  const SizedBox(width: 12),
                  const Expanded(child: Text('Gestionar Ollama')),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'reload',
              child: Row(
                children: [
                  Icon(Icons.refresh, size: 20, color: colorScheme.primary),
                  const SizedBox(width: 12),
                  const Expanded(child: Text('Recargar modelos')),
                ],
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'free_gpu',
              child: Row(
                children: [
                  Icon(Icons.memory, size: 20, color: colorScheme.tertiary),
                  const SizedBox(width: 12),
                  const Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Liberar GPU'),
                        Text(
                          'Descargar modelos de la VRAM',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'clear',
              child: Row(
                children: [
                  Icon(Icons.clear_all, size: 20, color: colorScheme.error),
                  const SizedBox(width: 12),
                  const Expanded(child: Text('Limpiar historial')),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(width: 8),
      ],
    );
  }



  Widget _buildMessageList(ChatServiceOllama chatService) {
    final messages = chatService.messages;

    if (messages.isEmpty) {
      return _buildEmptyState();
    }

    _scheduleAutoScroll();

    return Stack(children: [
      SelectionArea(
        child: ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(vertical: 16),
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final message = messages[index];
            final isLast = index == messages.length - 1;
            return MessageBubble(
              message: message,
              canExport: !chatService.isLoading,
              onExport:
                  !message.isUser && !message.isError && !chatService.isLoading
                      ? () => showExportDialog(context,
                          title: 'Respuesta LightChat', text: message.text)
                      : null,
              onRetry: message.isError && isLast ? _retryMessage : null,
              onContinue: !message.isUser &&
                      isLast &&
                      !chatService.isLoading &&
                      ['length', 'stopped', 'interrupted']
                          .contains(message.metadata?['finishReason'])
                  ? () {
                      _jumpToLatest();
                      chatService.continueLastResponse();
                    }
                  : null,
              onRegenerate: !message.isUser &&
                      !message.isError &&
                      isLast &&
                      !chatService.isLoading
                  ? _regenerateResponse
                  : null,
              onEdit: message.isUser && !chatService.isLoading
                  ? () => _editMessage(index, message.text)
                  : null,
              onCopy: () {
                Clipboard.setData(ClipboardData(text: message.text));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Respuesta copiada'),
                    duration: Duration(milliseconds: 1500),
                    behavior: SnackBarBehavior.floating,
                    margin: EdgeInsets.only(bottom: 80, left: 16, right: 16),
                  ),
                );
              },
            );
          },
        ),
      ),
      Positioned(
        right: 16,
        bottom: 12,
        child: ValueListenableBuilder<bool>(
          valueListenable: _followingLatest,
          builder: (_, following, __) => following
              ? const SizedBox.shrink()
              : FloatingActionButton.small(
                  heroTag: 'latest-message',
                  tooltip: 'Volver al final',
                  onPressed: _jumpToLatest,
                  child: const Icon(Icons.arrow_downward)),
        ),
      )
    ]);
  }

  Widget _buildEmptyState() {
    final colorScheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 24,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.chat_bubble_outline,
                        size: 40,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      '¡Bienvenido a LightChat!',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Inicia una conversación con tu IA favorita',
                      style: TextStyle(
                        fontSize: 14,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Arrastra o adjunta un PDF, Word, Excel o PowerPoint para '
                      'preguntar sobre él',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const OllamaManagerScreen(),
                            fullscreenDialog: true,
                          ),
                        );
                      },
                      icon: const Icon(Icons.smart_toy),
                      label: const Text('Configurar Ollama'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _handleMenuAction(String action, ChatServiceOllama chatService) {
    switch (action) {
      case 'context':
        showContextSettings(context, chatService.selectedModel).then((_) {
          if (mounted) {
            _chatInputKey.currentState?.refreshContextPreview();
            _chatInputKey.currentState?.saveDraft();
          }
        });
        break;
      case 'export':
        final current = chatService.conversations
            .where((c) => c.id == chatService.activeConversationId);
        showExportDialog(context,
            title: current.isEmpty ? 'LightChat' : current.first.title,
            messages: List.of(chatService.messages));
        break;
      case 'ollama_manager':
        Navigator.of(context)
            .push(
          MaterialPageRoute(
            builder: (context) => const OllamaManagerScreen(),
            fullscreenDialog: true,
          ),
        )
            .then((_) {
          if (mounted) {
            chatService.loadModels();
          }
        });
        break;
      case 'clear':
        _showClearHistoryDialog(chatService);
        break;
      case 'reload':
        chatService.loadModels();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Recargando modelos…'),
            duration: Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
        break;
      case 'free_gpu':
        _freeGpu();
        break;
    }
  }

  /// Descarga los modelos cargados de la VRAM sin cerrar Ollama.
  Future<void> _freeGpu() async {
    final messenger = ScaffoldMessenger.of(context);
    final ollama = context.read<OllamaService>();
    if (ollama.serverInfo.status != OllamaStatus.running) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Ollama no está en marcha: no hay nada que liberar'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final freed = await ollama.unloadLoadedModels();
    if (!mounted) {
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          freed == 0
              ? 'No había modelos cargados en la GPU'
              : '$freed modelo(s) liberados. Ollama sigue en marcha y '
                  'recargará el modelo cuando escribas.',
        ),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showClearHistoryDialog(ChatServiceOllama chatService) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Limpiar historial'),
        content: const Text(
          '¿Estás seguro de que quieres borrar todo el historial de conversación?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              try {
                await chatService.clearMessages();
                if (!context.mounted) {
                  return;
                }
                Navigator.pop(context);
                messenger.showSnackBar(
                    const SnackBar(content: Text('Historial limpiado')));
              } catch (error) {
                messenger.showSnackBar(
                    SnackBar(content: Text('No se pudo limpiar: $error')));
              }
            },
            child: const Text('Limpiar'),
          ),
        ],
      ),
    );
  }
}
