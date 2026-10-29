import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../config/context_config.dart';
import '../services/context_profile_service.dart';
import '../services/document_store_service.dart';

Future<void> showContextSettings(BuildContext context, String model) =>
    showDialog<void>(
        context: context, builder: (_) => _ContextSettingsDialog(model: model));

class _ContextSettingsDialog extends StatefulWidget {
  final String model;
  const _ContextSettingsDialog({required this.model});

  @override
  State<_ContextSettingsDialog> createState() => _ContextSettingsDialogState();
}

class _ContextSettingsDialogState extends State<_ContextSettingsDialog> {
  ModelContextProfile? _profile;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await DocumentStoreService.instance.initialize();
      final profile =
          await ContextProfileService.instance.forModel(widget.model);
      if (mounted) {
        setState(() {
          _profile = profile;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    }
  }

  Future<void> _chooseRoot() async {
    setState(() => _busy = true);
    try {
      final path = await getDirectoryPath(
          confirmButtonText: 'Usar carpeta para LightChat');
      if (path != null) {
        await DocumentStoreService.instance.configureRoot(path);
        if (mounted) {
          setState(() {});
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    final root = DocumentStoreService.instance.rootPath;
    return AlertDialog(
        title: const Text('Contexto y archivos'),
        content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                  Text(widget.model.isEmpty
                      ? 'Selecciona un modelo para ajustar su contexto.'
                      : widget.model),
                  const SizedBox(height: 12),
                  if (profile != null) ...[
                    Text(profile.metadataKnown
                        ? 'Límite del modelo: ${profile.nativeTokens} tokens'
                        : 'Límite no disponible. Se utiliza un perfil conservador.'),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 4, children: [
                      for (final tokens in ContextConfig.profiles)
                        if (tokens <= profile.nativeTokens)
                          ChoiceChip(
                              label: Text('${tokens ~/ 1024}k'),
                              selected: tokens == profile.tokens,
                              onSelected: _busy
                                  ? null
                                  : (_) async {
                                      setState(() => _busy = true);
                                      try {
                                        await ContextProfileService.instance
                                            .setTokens(widget.model, tokens);
                                        await _load();
                                      } catch (error) {
                                        if (mounted) {
                                          setState(
                                              () => _error = error.toString());
                                        }
                                      } finally {
                                        if (mounted) {
                                          setState(() => _busy = false);
                                        }
                                      }
                                    })
                    ]),
                    const SizedBox(height: 8),
                    const Text(
                        'Un contexto mayor consume más memoria. Cambiar el perfil recarga el modelo; '
                        'se mantiene el mismo valor en los siguientes mensajes.'),
                    const SizedBox(height: 12),
                    Text(profile.supportsTools
                        ? 'El modelo permite crear archivos PDF y Excel/XLSX.'
                        : 'Este modelo no anuncia herramientas. Para crear archivos desde el chat, usa un modelo compatible, como Qwen2.5.'),
                  ] else if (_error == null)
                    const LinearProgressIndicator(),
                  const SizedBox(height: 20),
                  const Text(
                      'Carpeta local para documentos y archivos generados'),
                  const SizedBox(height: 8),
                  Text(root ??
                      'Sin configurar. Puedes conversar y exportar respuestas; '
                          'elige una carpeta para conservar documentos y crear archivos desde el chat.'),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                      onPressed: _busy ? null : _chooseRoot,
                      icon: const Icon(Icons.folder_open),
                      label: Text(
                          root == null ? 'Elegir carpeta' : 'Cambiar carpeta')),
                  if (_error != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(_error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error))),
                ]))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'))
        ]);
  }
}
