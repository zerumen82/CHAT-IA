import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/chat_service.dart';

class ModelSelector extends StatelessWidget {
  const ModelSelector({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatService>(
      builder: (context, chatService, _) {
        final models = chatService.availableModels;

        if (models.isEmpty) {
          return PopupMenuButton<String>(
            icon: Icon(
              Icons.cloud_off,
              size: 20,
              color: chatService.isLoadingModels
                  ? Theme.of(context)
                      .colorScheme
                      .primary
                      .withAlpha((0.6 * 255).round())
                  : Theme.of(context)
                      .colorScheme
                      .error
                      .withAlpha((0.8 * 255).round()),
            ),
            tooltip: chatService.isLoadingModels
                ? 'Cargando modelos...'
                : 'Sin conexión a vLLM',
            position: PopupMenuPosition.under,
            onSelected: (v) {
              if (v == 'reload') chatService.loadModels();
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                value: 'reload',
                child: Row(
                  children: [
                    Icon(
                      chatService.isLoadingModels
                          ? Icons.hourglass_empty
                          : Icons.refresh,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(chatService.isLoadingModels
                        ? 'Cargando...'
                        : 'Conectar a vLLM'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                enabled: false,
                child: Text(
                  'Asegúrate de que vLLM\nesté ejecutándose en\nlocalhost:8000',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
            ],
          );
        }

        return PopupMenuButton<String>(
          icon: Icon(
            chatService.autoSelectModel
                ? Icons.auto_awesome
                : Icons.model_training,
            color: chatService.autoSelectModel ? Colors.orange : null,
          ),
          tooltip: chatService.autoSelectModel
              ? 'Auto-selección: ${chatService.selectedModel}'
              : 'Modelo: ${chatService.selectedModel.isNotEmpty ? chatService.selectedModel : "ninguno"}',
          onSelected: (model) {
            if (model == 'toggle_auto') {
              chatService.toggleAutoSelectModel();
            } else {
              chatService.selectModel(model);
            }
          },
          itemBuilder: (context) => [
            // Opción para activar/desactivar auto-selección
            PopupMenuItem<String>(
              value: 'toggle_auto',
              child: Row(
                children: [
                  Icon(
                    chatService.autoSelectModel
                        ? Icons.auto_awesome
                        : Icons.settings,
                    size: 18,
                    color: chatService.autoSelectModel
                        ? Colors.orange
                        : Colors.grey,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      chatService.autoSelectModel
                          ? 'Auto-selección ON'
                          : 'Auto-selección OFF',
                      style: TextStyle(
                        fontWeight: chatService.autoSelectModel
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color:
                            chatService.autoSelectModel ? Colors.orange : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const PopupMenuDivider(),
            ...models.map((model) {
              final isSelected = model == chatService.selectedModel;
              return PopupMenuItem<String>(
                value: model,
                child: Row(
                  children: [
                    Icon(
                      isSelected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 18,
                      color: isSelected ? Colors.blue : null,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        model,
                        style: TextStyle(
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        );
      },
    );
  }
}
