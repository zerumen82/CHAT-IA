import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/api_config.dart';
import '../services/api_key_store.dart';
import '../services/api_service.dart';
import 'api_provider_dialog.dart';

/// Pestaña «APIs» del gestor: alta, prueba y borrado de proveedores cloud.
///
/// No hace HTTP directamente: delega en `ApiService` (regla Widget → Service
/// de AGENTS.md). Las claves viven en `ApiKeyStore` y no se muestran en claro.
class ApiProvidersTab extends StatefulWidget {
  const ApiProvidersTab({super.key});

  @override
  State<ApiProvidersTab> createState() => _ApiProvidersTabState();
}

class _ApiProvidersTabState extends State<ApiProvidersTab>
    with AutomaticKeepAliveClientMixin {
  String? _testingId;
  bool _importing = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ApiKeyStore.instance.load();
    });
  }

  void _showMessage(String text, {bool error = false}) {
    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  Future<void> _importFile() async {
    setState(() => _importing = true);
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(label: 'Texto', extensions: ['txt']),
        ],
      );
      if (file == null) {
        return;
      }
      final content = await file.readAsString();
      final result = await ApiKeyStore.instance.import(content);
      final parts = <String>[
        if (result.imported.isNotEmpty)
          '${result.imported.length} dados de alta: '
              '${result.imported.join(', ')}',
        if (result.updated.isNotEmpty)
          '${result.updated.length} actualizados: '
              '${result.updated.join(', ')}',
        if (result.unrecognized.isNotEmpty)
          'no reconocidos: ${result.unrecognized.join(' · ')}',
        if (result.extraKeys.isNotEmpty)
          'claves repetidas ignoradas (revísalas a mano): '
              '${result.extraKeys.keys.join(', ')}',
      ];
      if (!result.hasChanges && parts.isEmpty) {
        _showMessage('No se reconoció ninguna clave en el archivo.',
            error: true);
        return;
      }
      _showMessage(parts.isEmpty
          ? 'Importación completada.'
          : 'Importación: ${parts.join(' | ')}');
    } catch (error) {
      _showMessage('No se pudo importar el archivo: $error', error: true);
    } finally {
      if (mounted) {
        setState(() => _importing = false);
      }
    }
  }

  Future<void> _edit(ApiProvider? provider, ApiKeyEntry? existing) async {
    final entry = await showApiProviderDialog(
      context,
      provider: provider,
      existing: existing,
    );
    if (entry == null) {
      return;
    }
    try {
      await ApiKeyStore.instance.save(
        providerId: entry.providerId,
        apiKey: entry.apiKey,
        model: entry.model,
      );
      final name =
          ApiConfig.byId(entry.providerId)?.displayName ?? entry.providerId;
      _showMessage('Guardado: $name.');
    } catch (error) {
      _showMessage('No se pudo guardar: $error', error: true);
    }
  }

  Future<void> _test(ApiProvider provider, ApiKeyEntry? entry) async {
    if (entry == null || entry.apiKey.isEmpty) {
      _showMessage(
          '${provider.displayName} no tiene clave guardada. Edítalo primero.',
          error: true);
      return;
    }
    setState(() => _testingId = provider.id);
    try {
      final message = await ApiService.instance.testConnection(
        providerId: provider.id,
        model: entry.model,
      );
      _showMessage(message);
    } catch (error) {
      _showMessage('${provider.displayName}: $error', error: true);
    } finally {
      if (mounted) {
        setState(() => _testingId = null);
      }
    }
  }

  Future<void> _remove(ApiProvider provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Borrar clave de ${provider.displayName}'),
        content: const Text(
            'Se elimina la clave y el modelo guardados en este equipo. '
            'El archivo del que la importaste no se toca.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await ApiKeyStore.instance.remove(provider.id);
    _showMessage('Clave de ${provider.displayName} eliminada.');
  }

  String _adapterLabel(ApiAdapter adapter) {
    switch (adapter) {
      case ApiAdapter.openaiCompatible:
        return 'OpenAI compatible · streaming';
      case ApiAdapter.anthropic:
        return 'Anthropic · streaming';
      case ApiAdapter.gemini:
        return 'Gemini · streaming';
      case ApiAdapter.aiHorde:
        return 'AI Horde · sin streaming (cola)';
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Consumer<ApiKeyStore>(
      builder: (context, store, _) {
        final configured =
            store.entries.where((entry) => entry.apiKey.isNotEmpty).length;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$configured de ${ApiConfig.providers.length} '
                          'proveedores con clave · Ollama local sigue siendo '
                          'el backend por defecto',
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _importing ? null : _importFile,
                        icon: _importing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              )
                            : const Icon(Icons.file_upload, size: 16),
                        label: const Text('Importar APIS.txt'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonalIcon(
                        onPressed: () => _edit(null, null),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Añadir'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Al elegir una API, el mensaje sale de esta máquina '
                      'hacia el servidor del proveedor. Las claves se guardan '
                      'en este equipo y nunca se envían a otro sitio. Para '
                      'trabajo sensible, usa Ollama local.',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: ApiConfig.providers.length,
                itemBuilder: (context, index) {
                  final provider = ApiConfig.providers[index];
                  final entry = store.entry(provider.id);
                  final hasKey = entry != null && entry.apiKey.isNotEmpty;
                  final isTesting = _testingId == provider.id;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    color: colorScheme.surfaceContainerLow,
                    child: ListTile(
                      leading: Icon(
                        hasKey ? Icons.cloud_done : Icons.cloud_off,
                        color: hasKey
                            ? colorScheme.primary
                            : colorScheme.outline,
                      ),
                      title: Text(provider.displayName),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_adapterLabel(provider.adapter)),
                          Text(
                            hasKey
                                ? entry.model.isEmpty
                                    ? 'Clave guardada · sin modelo elegido'
                                    : 'Modelo: ${entry.model}'
                                : 'Sin clave',
                            style: TextStyle(
                              color: hasKey
                                  ? colorScheme.primary
                                  : colorScheme.error,
                              fontSize: 12,
                            ),
                          ),
                          if (provider.notes.isNotEmpty)
                            Text(
                              provider.notes,
                              style: TextStyle(
                                color: colorScheme.outline,
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                      isThreeLine: true,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Probar conexión real',
                            onPressed: isTesting
                                ? null
                                : () => _test(provider, entry),
                            icon: isTesting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.wifi_tethering, size: 18),
                          ),
                          PopupMenuButton<String>(
                            tooltip: 'Acciones',
                            onSelected: (action) {
                              if (action == 'edit') {
                                _edit(provider, entry);
                              } else if (action == 'delete') {
                                _remove(provider);
                              }
                            },
                            itemBuilder: (menuContext) => [
                              const PopupMenuItem(
                                value: 'edit',
                                child: ListTile(
                                  leading: Icon(Icons.edit, size: 18),
                                  title: Text('Editar'),
                                ),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                enabled: hasKey,
                                child: const ListTile(
                                  leading: Icon(Icons.delete, size: 18),
                                  title: Text('Borrar clave'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
