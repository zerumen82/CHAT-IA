import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../services/api_key_store.dart';

/// Diálogo de alta/edición de un proveedor de API cloud.
///
/// La clave se pide aquí y se guarda en `ApiKeyStore` (SharedPreferences);
/// nunca se escribe en el código fuente ni se muestra ya guardada en claro.
Future<ApiKeyEntry?> showApiProviderDialog(
  BuildContext context, {
  ApiProvider? provider,
  ApiKeyEntry? existing,
}) {
  return showDialog<ApiKeyEntry>(
    context: context,
    builder: (_) => ApiProviderDialog(provider: provider, existing: existing),
  );
}

class ApiProviderDialog extends StatefulWidget {
  const ApiProviderDialog({
    super.key,
    this.provider,
    this.existing,
  });

  /// Proveedor preseleccionado (alta nueva).
  final ApiProvider? provider;

  /// Entrada existente (edición).
  final ApiKeyEntry? existing;

  @override
  State<ApiProviderDialog> createState() => _ApiProviderDialogState();
}

class _ApiProviderDialogState extends State<ApiProviderDialog> {
  late String _providerId;
  late final TextEditingController _keyController;
  late final TextEditingController _modelController;
  bool _obscureKey = true;
  String? _error;

  ApiProvider get _provider =>
      ApiConfig.byId(_providerId) ?? ApiConfig.providers.first;

  @override
  void initState() {
    super.initState();
    _providerId = widget.existing?.providerId ?? widget.provider?.id ?? '';
    _keyController = TextEditingController(text: widget.existing?.apiKey ?? '');
    _modelController = TextEditingController(text: widget.existing?.model ?? '');
    if (_providerId.isEmpty) {
      // Solo se ofrecen proveedores todavía sin clave.
      final firstFree = ApiConfig.providers
          .where((candidate) => ApiKeyStore.instance.entry(candidate.id) == null)
          .toList(growable: false);
      _providerId = firstFree.isEmpty
          ? ApiConfig.providers.first.id
          : firstFree.first.id;
    }
  }

  /// Proveedores elegibles en el desplegable: los sin clave y el actual.
  List<ApiProvider> get _freeProviders => [
        for (final provider in ApiConfig.providers)
          if (provider.id == _providerId ||
              ApiKeyStore.instance.entry(provider.id) == null)
            provider,
      ];

  @override
  void dispose() {
    _keyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  void _save() {
    final key = _keyController.text.trim();
    final model = _modelController.text.trim();
    if (key.isEmpty && model.isEmpty) {
      setState(() => _error = 'Escribe al menos la clave o un modelo.');
      return;
    }
    if (key.isNotEmpty && key.length < 8) {
      setState(() => _error = 'Esa clave es demasiado corta para ser válida.');
      return;
    }
    Navigator.of(context).pop(
      ApiKeyEntry(providerId: _providerId, apiKey: key, model: model),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final existing = widget.existing;
    final freeEntries = _freeProviders;

    return AlertDialog(
      title: Text(existing == null
          ? 'Añadir proveedor de API'
          : 'Editar ${_provider.displayName}'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (existing == null) ...[
                if (freeEntries.isEmpty)
                  Text(
                    'Todos los proveedores del catálogo ya tienen clave '
                    'guardada.',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  )
                else ...[
                  DropdownButtonFormField<String>(
                    initialValue: _providerId,
                    decoration: const InputDecoration(labelText: 'Proveedor'),
                    items: [
                      for (final provider in freeEntries)
                        DropdownMenuItem(
                          value: provider.id,
                          child: Text(provider.displayName),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() {
                        _providerId = value;
                        _error = null;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                ],
              ],
              TextField(
                controller: _keyController,
                obscureText: _obscureKey,
                decoration: InputDecoration(
                  labelText: 'Clave de API',
                  hintText: 'Pégala tal cual la dio el proveedor',
                  errorText: _error,
                  suffixIcon: IconButton(
                    icon: Icon(
                        _obscureKey ? Icons.visibility : Icons.visibility_off),
                    tooltip:
                        _obscureKey ? 'Mostrar clave' : 'Ocultar clave',
                    onPressed: () => setState(() => _obscureKey = !_obscureKey),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _modelController,
                decoration: InputDecoration(
                  labelText: 'Modelo (opcional ahora)',
                  hintText: 'Se puede elegir luego; si lo sabes, escríbelo',
                  helperText: _provider.notes.isEmpty
                      ? null
                      : _provider.notes,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Aviso de privacidad',
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Al usar este proveedor el mensaje sale de tu máquina '
                      'hacia su servidor. Ollama local sigue siendo el '
                      'backend por defecto.',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
