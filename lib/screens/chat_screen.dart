import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lightchat/services/chat_service_ollama.dart';
import 'package:lightchat/services/ollama_service.dart';
import 'package:lightchat/widgets/model_selector.dart';
import 'package:lightchat/widgets/message_bubble.dart';
import 'package:lightchat/widgets/capsule_icon.dart';
import 'package:lightchat/widgets/chat_input.dart';
import 'package:lightchat/widgets/ollama_status_widget.dart';
import 'package:lightchat/screens/ollama_manager_screen.dart';

/// Pantalla principal de chat con diseño estilo mensajería
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ScrollController _scrollController = ScrollController();
  final ScrollController _consoleScrollController = ScrollController();
  bool _showConsole = false;

  @override
  void dispose() {
    _scrollController.dispose();
    _consoleScrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _handleSendMessage(String text, List<XFile>? images) async {
    final chatService = context.read<ChatServiceOllama>();

    // Soporte multimodal con Ollama
    List<String>? imagePaths;
    if (images != null && images.isNotEmpty) {
      imagePaths = images.map((img) => img.path).toList();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Procesando ${images.length} imagen(es)...'),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    if (text.isNotEmpty) {
      await chatService.sendMessage(text, imagePaths: imagePaths);
      Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatService = context.watch<ChatServiceOllama>();
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: _buildAppBar(context, chatService),
      body: Stack(
        children: [
          Column(
            children: [
              // Widget de estado de Ollama cuando no hay conexión
              Consumer<OllamaService>(
                builder: (context, ollama, _) {
                  if (chatService.availableModels.isEmpty &&
                      ollama.serverInfo.status != OllamaStatus.running) {
                    return const OllamaQuickConnect();
                  }
                  return const SizedBox.shrink();
                },
              ),

              // Lista de mensajes
              Expanded(
                child: _buildMessageList(chatService),
              ),

              // Indicador de carga
              if (chatService.isLoading) _buildLoadingIndicator(context),

              // Campo de entrada
              ChatInput(
                onSendMessage: _handleSendMessage,
                enabled: !chatService.isLoading,
                hintText: _getHintText(chatService),
              ),
            ],
          ),

          // Botón flotante de consola
          Positioned(
            bottom: 80,
            right: 16,
            child: _buildConsoleToggleButton(),
          ),

          // Consola flotante
          if (_showConsole) _buildFloatingConsole(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
      BuildContext context, ChatServiceOllama chatService) {
    final colorScheme = Theme.of(context).colorScheme;

    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 1,
      backgroundColor: colorScheme.surface,
      title: Row(
        children: [
          const CapsuleIcon(size: 28),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'LightChat',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.primary,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildConnectionIndicator(chatService),
                  const SizedBox(width: 4),
                  Text(
                    chatService.selectedModel.isNotEmpty
                        ? chatService.selectedModel
                        : 'Sin modelo',
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      actions: [
        // Selector de modelo
        const ModelSelector(),

        const SizedBox(width: 8),

        // Menú de acciones
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
                  const Text('Gestionar Ollama'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'clear',
              child: Row(
                children: [
                  Icon(Icons.clear_all, size: 20, color: colorScheme.error),
                  const SizedBox(width: 12),
                  const Text('Limpiar historial'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'reload',
              child: Row(
                children: [
                  Icon(Icons.refresh, size: 20, color: colorScheme.primary),
                  const SizedBox(width: 12),
                  const Text('Recargar modelos'),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildConnectionIndicator(ChatServiceOllama chatService) {
    final colorScheme = Theme.of(context).colorScheme;
    final isConnected = chatService.availableModels.isNotEmpty;

    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: isConnected ? Colors.green : colorScheme.error,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color:
                (isConnected ? Colors.green : colorScheme.error).withAlpha(77),
            blurRadius: 4,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }

  /// Botón para mostrar/ocultar consola
  Widget _buildConsoleToggleButton() {
    return Consumer<OllamaService>(
      builder: (context, ollama, _) {
        // Solo mostrar si el servidor está corriendo o iniciando
        if (ollama.serverInfo.status != OllamaStatus.running &&
            ollama.serverInfo.status != OllamaStatus.starting) {
          return const SizedBox.shrink();
        }

        return GestureDetector(
          onTap: () {
            setState(() {
              _showConsole = !_showConsole;
            });
          },
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _showConsole
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              border: Border.all(
                color: Theme.of(context).colorScheme.outline,
                width: 1,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _showConsole ? Icons.terminal : Icons.terminal_outlined,
              color: Theme.of(context).colorScheme.onSurface,
              size: 20,
            ),
          ),
        );
      },
    );
  }

  /// Consola flotante con stdout/stderr
  Widget _buildFloatingConsole() {
    return Consumer<OllamaService>(
      builder: (context, ollama, _) {
        // Auto-scroll al final cuando llegan nuevos logs
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_consoleScrollController.hasClients) {
            _consoleScrollController.animateTo(
              _consoleScrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeOut,
            );
          }
        });

        return Positioned(
          bottom: 130,
          right: 16,
          width: 400,
          height: 300,
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
                // Header de la consola
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
                          fontSize: 10,
                          color: Theme.of(context).colorScheme.primary,
                          letterSpacing: 2,
                        ),
                      ),
                      Row(
                        children: [
                          // Indicador de estado
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color:
                                  ollama.serverInfo.status == OllamaStatus.running
                                      ? Colors.green
                                      : Colors.orange,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Botón cerrar
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _showConsole = false;
                              });
                            },
                            child: Icon(
                              Icons.close,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              size: 16,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Contenido de la consola
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

                // Footer con acciones
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
                      // Botón copiar
                      TextButton.icon(
                        onPressed: () => _copyLogs(ollama.logs.join('\n')),
                        icon: const Icon(Icons.copy, size: 14),
                        label: const Text('COPIAR'),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Botón limpiar
                      TextButton.icon(
                        onPressed: () {
                          // Ollama no tiene clearLogs, es un getter
                        },
                        icon: const Icon(Icons.clear_all, size: 14),
                        label: const Text('LIMPIAR'),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                        ),
                      ),
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

  /// Parsear líneas de consola
  List<String> _parseConsoleLines(String logs) {
    return logs.split('\n').where((line) => line.trim().isNotEmpty).toList();
  }

  /// Construir línea de consola con color según tipo
  Widget _buildConsoleLine(String line) {
    Color textColor = Theme.of(context).colorScheme.onSurfaceVariant;

    // Colorear según tipo de mensaje
    if (line.contains('ERROR') ||
        line.contains('Error') ||
        line.contains('error')) {
      textColor = Colors.red.shade400;
    } else if (line.contains('WARNING') ||
        line.contains('Warning') ||
        line.contains('warning')) {
      textColor = Colors.orange.shade400;
    } else if (line.contains('INFO') ||
        line.contains('INFO:') ||
        line.contains('Starting') ||
        line.contains('Started')) {
      textColor = Colors.blue.shade400;
    } else if (line.contains('SUCCESS') ||
        line.contains('Success') ||
        line.contains('ready') ||
        line.contains('Ready')) {
      textColor = Colors.green.shade400;
    } else if (line.contains('stdout') || line.contains('STDOUT')) {
      textColor = Theme.of(context).colorScheme.onSurface;
    } else if (line.contains('stderr') || line.contains('STDERR')) {
      textColor = Colors.yellow.shade400;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: Text(
        line,
        style: TextStyle(
          fontFamily: 'Courier',
          fontSize: 9,
          color: textColor,
        ),
      ),
    );
  }

  /// Copiar logs al portapapeles
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

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 16),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        return MessageBubble(message: message);
      },
    );
  }

  Widget _buildEmptyState() {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icono
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

          // Título
          Text(
            '¡Bienvenido a LightChat!',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),

          const SizedBox(height: 8),

          // Subtítulo
          Text(
            'Inicia una conversación con tu IA favorita',
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingIndicator(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
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
            'Pensando...',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  String _getHintText(ChatServiceOllama chatService) {
    if (chatService.availableModels.isEmpty) {
      return 'Conecta Ollama primero...';
    }
    if (chatService.isLoading) {
      return 'Esperando respuesta...';
    }
    return 'Escribe un mensaje...';
  }

  void _handleMenuAction(String action, ChatServiceOllama chatService) {
    switch (action) {
      case 'ollama_manager':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const OllamaManagerScreen(),
            fullscreenDialog: true,
          ),
        );
        break;
      case 'clear':
        _showClearHistoryDialog(chatService);
        break;
      case 'reload':
        chatService.loadModels();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Recargando modelos...'),
            duration: Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
        break;
    }
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
