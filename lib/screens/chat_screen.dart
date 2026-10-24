import 'dart:async';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:lightchat/models/document_attachment.dart';
import 'package:lightchat/screens/ollama_manager_screen.dart';
import 'package:lightchat/services/chat_service_ollama.dart';
import 'package:lightchat/services/ollama_service.dart';
import 'package:lightchat/widgets/capsule_icon.dart';
import 'package:lightchat/widgets/chat_input.dart';
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
  final ScrollController _consoleScrollController = ScrollController();
  final GlobalKey<ChatInputState> _chatInputKey = GlobalKey<ChatInputState>();
  bool _showConsole = false;
  bool _isDraggingFiles = false;
  bool _autoScroll = true;
  bool _scrollScheduled = false;
  int _lastLogCount = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _consoleScrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    _autoScroll = position.maxScrollExtent - position.pixels < 120;
  }

  /// Baja al final solo si el usuario ya estaba abajo, para no interrumpir
  /// la lectura mientras llega la respuesta en streaming.
  void _scheduleAutoScroll() {
    if (_scrollScheduled) return;
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (!mounted || !_scrollController.hasClients || !_autoScroll) return;
      final position = _scrollController.position;
      if (position.maxScrollExtent - position.pixels <= 0.5) return;
      _scrollController.jumpTo(position.maxScrollExtent);
    });
  }

  void _handleSendMessage(
    String text,
    List<XFile>? images,
    List<DocumentAttachment>? documents,
  ) {
    final chatService = context.read<ChatServiceOllama>();

    List<String>? imagePaths;
    if (images != null && images.isNotEmpty) {
      imagePaths = images.map((img) => img.path).toList();
    }

    if (text.isNotEmpty ||
        (imagePaths?.isNotEmpty ?? false) ||
        (documents?.isNotEmpty ?? false)) {
      _autoScroll = true;
      _scheduleAutoScroll();
      unawaited(chatService.sendMessage(
        text,
        imagePaths: imagePaths,
        documents: documents,
      ));
    }
  }

  void _retryMessage() {
    context.read<ChatServiceOllama>().retryLastMessage();
  }

  void _stopGeneration() {
    context.read<ChatServiceOllama>().stopGeneration();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Consumer<ChatServiceOllama>(
          builder: (context, chatService, _) =>
              _buildAppBar(context, chatService),
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
        child: Stack(
          children: [
            Column(
              children: [
                Selector<ChatServiceOllama, bool>(
                  selector: (_, chatService) =>
                      chatService.availableModels.isEmpty,
                  builder: (context, noModels, _) {
                    if (!noModels) return const SizedBox.shrink();
                    return Selector<OllamaService, bool>(
                      selector: (_, ollama) =>
                          ollama.serverInfo.status != OllamaStatus.running,
                      builder: (context, offline, _) => offline
                          ? const OllamaQuickConnect()
                          : const SizedBox.shrink(),
                    );
                  },
                ),
                Expanded(
                  child: Selector<ChatServiceOllama, int>(
                    selector: (_, chatService) => chatService.messagesVersion,
                    builder: (context, _, __) =>
                        _buildMessageList(context.read<ChatServiceOllama>()),
                  ),
                ),
                Selector<ChatServiceOllama, bool>(
                  selector: (_, chatService) => chatService.isLoading,
                  builder: (context, isLoading, _) => isLoading
                      ? _buildTypingIndicator(context)
                      : const SizedBox.shrink(),
                ),
                Selector<ChatServiceOllama, ({bool loading, bool connected})>(
                  selector: (_, chatService) => (
                    loading: chatService.isLoading,
                    connected: chatService.availableModels.isNotEmpty,
                  ),
                  builder: (context, state, _) => ChatInput(
                    key: _chatInputKey,
                    onSendMessage: _handleSendMessage,
                    busy: state.loading,
                    connected: state.connected,
                  ),
                ),
              ],
            ),
            if (_showConsole) _buildFloatingConsole(),
            if (_isDraggingFiles) _buildDropOverlay(),
          ],
        ),
      ),
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
                  'PDF, Excel, CSV, TXT o imágenes',
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

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    ChatServiceOllama chatService,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 1,
      backgroundColor: colorScheme.surface,
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
        _buildConsoleToggleButton(),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          tooltip: 'Más opciones',
          onSelected: (value) => _handleMenuAction(value, chatService),
          itemBuilder: (context) => [
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

  Widget _buildConsoleToggleButton() {
    return Selector<OllamaService, bool>(
      selector: (_, ollama) =>
          ollama.serverInfo.status == OllamaStatus.running ||
          ollama.serverInfo.status == OllamaStatus.starting,
      builder: (context, visible, _) {
        if (!visible) {
          return const SizedBox.shrink();
        }
        return IconButton(
          tooltip: _showConsole ? 'Cerrar consola' : 'Abrir consola de Ollama',
          onPressed: () {
            setState(() {
              _showConsole = !_showConsole;
            });
          },
          icon: Icon(_showConsole ? Icons.terminal : Icons.terminal_outlined),
        );
      },
    );
  }

  Widget _buildFloatingConsole() {
    final size = MediaQuery.sizeOf(context);
    final width = size.width < 600 ? math.max(180.0, size.width - 32) : 400.0;
    final height = math.max(140.0, math.min(360.0, size.height - 180));

    return Consumer<OllamaService>(
      builder: (context, ollama, _) {
        // Bajar al último registro cuando llega uno nuevo.
        if (ollama.logs.length != _lastLogCount) {
          _lastLogCount = ollama.logs.length;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !_consoleScrollController.hasClients) return;
            _consoleScrollController.jumpTo(
              _consoleScrollController.position.maxScrollExtent,
            );
          });
        }

        return Positioned(
          bottom: size.height < 560 ? 96 : 130,
          right: 16,
          width: width,
          height: height,
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border.all(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    border: Border(
                      bottom: BorderSide(
                          color: Theme.of(context).colorScheme.outline),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'CONSOLA OLLAMA',
                        style: TextStyle(
                          fontFamily: 'Courier',
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.primary,
                          letterSpacing: 2,
                        ),
                      ),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: ollama.serverInfo.status ==
                                      OllamaStatus.running
                                  ? Theme.of(context).colorScheme.tertiary
                                  : Theme.of(context).colorScheme.error,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'Cerrar consola',
                            onPressed: () {
                              setState(() {
                                _showConsole = false;
                              });
                            },
                            icon: Icon(
                              Icons.close,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              size: 18,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    child: ListView.builder(
                      controller: _consoleScrollController,
                      padding: const EdgeInsets.all(4),
                      itemCount: ollama.logs.length,
                      itemBuilder: (context, index) {
                        final line = ollama.logs[index];
                        return _buildConsoleLine(line);
                      },
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    border: Border(
                      top: BorderSide(
                          color: Theme.of(context).colorScheme.outline),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: ollama.clearLogs,
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Limpiar'),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          minimumSize: const Size(0, 40),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: () => _copyLogs(ollama.logs.join('\n')),
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('Copiar'),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          minimumSize: const Size(0, 40),
                        ),
                      ),
                      const SizedBox(width: 8),
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

  Widget _buildConsoleLine(String line) {
    Color textColor = Theme.of(context).colorScheme.onSurfaceVariant;

    if (line.contains('ERROR') ||
        line.contains('Error') ||
        line.contains('error')) {
      textColor = Theme.of(context).colorScheme.error;
    } else if (line.contains('WARNING') ||
        line.contains('Warning') ||
        line.contains('warning')) {
      textColor = Theme.of(context).colorScheme.secondary;
    } else if (line.contains('INFO') ||
        line.contains('INFO:') ||
        line.contains('Starting') ||
        line.contains('Started')) {
      textColor = Theme.of(context).colorScheme.primary;
    } else if (line.contains('SUCCESS') ||
        line.contains('Success') ||
        line.contains('ready') ||
        line.contains('Ready')) {
      textColor = Theme.of(context).colorScheme.tertiary;
    } else if (line.contains('stdout') || line.contains('STDOUT')) {
      textColor = Theme.of(context).colorScheme.onSurface;
    } else if (line.contains('stderr') || line.contains('STDERR')) {
      textColor = Theme.of(context).colorScheme.error;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: Text(
        line,
        style: TextStyle(
          fontFamily: 'Courier',
          fontSize: 12,
          color: textColor,
        ),
      ),
    );
  }

  void _copyLogs(String logs) {
    Clipboard.setData(ClipboardData(text: logs));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Logs copiados al portapapeles'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildMessageList(ChatServiceOllama chatService) {
    final messages = chatService.messages;

    if (messages.isEmpty) {
      return _buildEmptyState();
    }

    _scheduleAutoScroll();

    return SelectionArea(
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: 16),
        itemCount: messages.length,
        itemBuilder: (context, index) {
          final message = messages[index];
          return MessageBubble(
            message: message,
            onRetry: message.isError && index == messages.length - 1
                ? _retryMessage
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
    );
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
                      'Arrastra o adjunta un PDF o Excel para preguntar sobre él',
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

  Widget _buildTypingIndicator(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Escribiendo…',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 14,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(width: 12),
          TextButton.icon(
            onPressed: _stopGeneration,
            icon: const Icon(Icons.stop_circle_outlined, size: 18),
            label: const Text('Detener'),
            style: TextButton.styleFrom(
              foregroundColor: colorScheme.error,
              minimumSize: const Size(0, 40),
            ),
          ),
        ],
      ),
    );
  }

  void _handleMenuAction(String action, ChatServiceOllama chatService) {
    switch (action) {
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
    if (!mounted) return;
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
            onPressed: () {
              chatService.clearMessages();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Historial limpiado'),
                  duration: Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: const Text('Limpiar'),
          ),
        ],
      ),
    );
  }
}
