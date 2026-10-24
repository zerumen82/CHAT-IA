import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/chat_service_ollama.dart';
import '../services/ollama_service.dart';
import '../screens/ollama_manager_screen.dart';

/// Widget rápido de conexión a Ollama
class OllamaQuickConnect extends StatelessWidget {
  const OllamaQuickConnect({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.error.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.smart_toy_outlined,
                color: colorScheme.error,
                size: 32,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ollama no detectado',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Necesitas tener Ollama instalado y ejecutándose',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    context.read<ChatServiceOllama>().loadModels();
                  },
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Reintentar'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const OllamaManagerScreen(),
                        fullscreenDialog: true,
                      ),
                    );
                  },
                  icon: const Icon(Icons.settings, size: 18),
                  label: const Text('Configurar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Widget de estado compacto para Ollama
class OllamaStatusWidget extends StatelessWidget {
  const OllamaStatusWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<OllamaService>(
      builder: (context, ollama, _) {
        final status = ollama.serverInfo.status;
        final isRunning = status == OllamaStatus.running;
        final colorScheme = Theme.of(context).colorScheme;
        final statusColor =
            isRunning ? colorScheme.tertiary : colorScheme.error;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: statusColor.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                isRunning
                    ? 'Ollama • ${ollama.models.length} modelos'
                    : _getStatusText(status),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isRunning ? colorScheme.tertiary : colorScheme.error,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _getStatusText(OllamaStatus status) {
    switch (status) {
      case OllamaStatus.notInstalled:
        return 'Ollama no instalado';
      case OllamaStatus.installing:
        return 'Instalando...';
      case OllamaStatus.installed:
        return 'Instalado';
      case OllamaStatus.starting:
        return 'Iniciando...';
      case OllamaStatus.running:
        return 'Ejecutando';
      case OllamaStatus.stopping:
        return 'Deteniendo...';
      case OllamaStatus.error:
        return 'Error';
    }
  }
}
