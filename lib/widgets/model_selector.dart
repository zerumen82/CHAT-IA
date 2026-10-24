import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/vllm_config.dart';
import '../services/chat_service_ollama.dart';

class ModelSelector extends StatelessWidget {
  const ModelSelector({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatServiceOllama>(
      builder: (context, chatService, _) {
        final models = chatService.availableModels;
        final colorScheme = Theme.of(context).colorScheme;

        if (models.isEmpty) {
          return PopupMenuButton<String>(
            icon: Icon(
              Icons.cloud_off,
              size: 20,
              color: chatService.isLoadingModels
                  ? colorScheme.primary.withValues(alpha: 0.7)
                  : colorScheme.error,
            ),
            tooltip: chatService.isLoadingModels
                ? 'Cargando modelos...'
                : 'Sin conexión a Ollama',
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
                        : 'Conectar a Ollama'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem<String>(
                enabled: false,
                child: Text(
                  'Asegúrate de que Ollama esté ejecutándose en\nlocalhost:11434',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          );
        }

        final maxWidth = (MediaQuery.sizeOf(context).width * 0.28)
            .clamp(112.0, 240.0)
            .toDouble();
        final selectedIsUncensored =
            OllamaConfig.isUncensoredModel(chatService.selectedModel);

        return PopupMenuButton<String>(
          tooltip:
              'Modelo: ${chatService.selectedModel.isNotEmpty ? chatService.selectedModel : "ninguno"}'
              '${selectedIsUncensored ? ' · Sin censura' : ''}',
          child: Container(
            width: maxWidth,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.model_training,
                  size: 18,
                  color: colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    chatService.selectedModel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colorScheme.onSecondaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (selectedIsUncensored)
                  Padding(
                    padding: const EdgeInsets.only(right: 2),
                    child: Tooltip(
                      message: 'Modelo sin censura',
                      child: Icon(
                        Icons.lock_open,
                        size: 16,
                        color: colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                Icon(
                  Icons.expand_more,
                  size: 18,
                  color: colorScheme.onSecondaryContainer,
                ),
              ],
            ),
          ),
          onSelected: (model) {
            if (model == '__reload__') {
              chatService.loadModels();
            } else {
              chatService.selectModel(model);
            }
          },
          itemBuilder: (context) => [
            ...models.map((model) {
              final isSelected = model == chatService.selectedModel;
              final isUncensored = OllamaConfig.isUncensoredModel(model);
              return PopupMenuItem<String>(
                value: model,
                child: Row(
                  children: [
                    Icon(
                      isSelected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 18,
                      color: isSelected ? colorScheme.primary : null,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            model,
                            style: TextStyle(
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          if (isUncensored)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: colorScheme.tertiaryContainer,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.lock_open,
                                      size: 11,
                                      color: colorScheme.onTertiaryContainer,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      'Sin censura',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: colorScheme.onTertiaryContainer,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
            const PopupMenuDivider(),
            PopupMenuItem<String>(
              value: '__reload__',
              child: Row(
                children: [
                  Icon(Icons.refresh, size: 18, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  const Text('Recargar modelos'),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
