import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/api_config.dart';
import '../config/vllm_config.dart';
import '../services/chat_service_ollama.dart';
import '../services/context_profile_service.dart';

class ModelSelector extends StatelessWidget {
  const ModelSelector({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatServiceOllama>(
      builder: (context, chatService, _) {
        final models = chatService.availableModels;
        final cloudModels = chatService.availableApiModels;
        final colorScheme = Theme.of(context).colorScheme;
        final selectedLabel =
            ApiConfig.displayNameFor(chatService.selectedModel);

        if (models.isEmpty && cloudModels.isEmpty) {
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
              if (v == 'reload') {
                chatService.loadModels();
              }
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
          enabled: !chatService.isLoading,
          tooltip:
              '${chatService.isLoading ? 'Detén la respuesta para cambiar de modelo. ' : ''}'
              'Modelo: ${chatService.selectedModel.isNotEmpty ? selectedLabel : "ninguno"}'
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
                    selectedLabel,
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
            PopupMenuItem<String>(
                enabled: false,
                child: Text(_capabilities(chatService.selectedProfile))),
            const PopupMenuDivider(),
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
            if (cloudModels.isNotEmpty) ...[
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                enabled: false,
                child: Row(
                  children: [
                    Icon(Icons.cloud, size: 16),
                    SizedBox(width: 8),
                    Text('APIs cloud'),
                  ],
                ),
              ),
              ..._groupedCloudItems(chatService, cloudModels, colorScheme),
            ],
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

  List<PopupMenuItem<String>> _groupedCloudItems(
      ChatServiceOllama chat, List<String> cloudModels, ColorScheme cs) {
    final groups = <String, List<String>>{};
    for (final m in cloudModels) {
      final parsed = ApiConfig.parseApiModelId(m);
      final id = parsed?.providerId ?? 'otro';
      groups.putIfAbsent(id, () => <String>[]);
      groups[id]!.add(m);
    }
    final items = <PopupMenuItem<String>>[];
    for (final entry in groups.entries.toList()..sort((a, b) => a.key.compareTo(b.key))) {
      final providerName = ApiConfig.byId(entry.key)?.displayName ?? entry.key;
      final providerColor = cs.primary; // podría extenderse a colores por proveedor
      // Encabezado del grupo con fondo sutil y separador arriba
      items.add(PopupMenuItem<String>(
        enabled: false,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          margin: const EdgeInsets.only(top: 4, bottom: 2),
          decoration: BoxDecoration(
            color: cs.secondaryContainer.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.cloud_queue, size: 18, color: providerColor),
              const SizedBox(width: 8),
              Text(
                providerName.toUpperCase(),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  letterSpacing: 0.5,
                  color: cs.onSecondaryContainer,
                ),
              ),
            ],
          ),
        ),
      ));
      for (final model in entry.value) {
        final isSel = model == chat.selectedModel;
        items.add(PopupMenuItem<String>(
          value: model,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(
                  isSel ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  size: 18,
                  color: isSel ? cs.primary : cs.outline,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    ApiConfig.displayNameFor(model).split(' · ').last,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                      fontSize: 13,
                      color: isSel ? cs.primary : cs.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ));
      }
      // Separador visual entre proveedores
      items.add(PopupMenuItem<String>(
        enabled: false,
        child: SizedBox(height: 4),
      ));
    }
    return items;
  }

  String _capabilities(ModelContextProfile? profile) {
    if (profile == null || !profile.capabilitiesKnown) {
      return 'Capacidades por comprobar';
    }
    return [
      'Texto',
      if (profile.supportsVision) 'Imágenes',
      if (profile.supportsTools) 'Herramientas'
    ].join(' · ');
  }
}
