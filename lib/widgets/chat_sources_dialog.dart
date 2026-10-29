import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/document_attachment.dart';
import '../services/chat_service_ollama.dart';
import 'document_text_dialog.dart';

Future<void> showChatSources(BuildContext context,
    {List<DocumentAttachment> additionalDocuments = const []}) async {
  final chat = context.read<ChatServiceOllama>();
  final conversationId = chat.activeConversationId;
  final sources = <String, DocumentAttachment>{
    for (final doc in await chat.getDocumentSources())
      chat.sourceKey(doc): doc,
    for (final doc in additionalDocuments) chat.sourceKey(doc): doc,
  };
  final documents = sources.values.toList();
  if (!context.mounted || chat.activeConversationId != conversationId) {
    return;
  }
  await showDialog<void>(
      context: context,
      builder: (_) => ChangeNotifierProvider.value(
          value: chat,
          child: _SourcesDialog(
              documents: documents, conversationId: conversationId)));
}

class _SourcesDialog extends StatelessWidget {
  final List<DocumentAttachment> documents;
  final String? conversationId;
  const _SourcesDialog({required this.documents, required this.conversationId});

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatServiceOllama>();
    final enabled =
        !chat.isLoading && chat.activeConversationId == conversationId;
    return AlertDialog(
      title: const Text('Fuentes de esta conversación'),
      content: SizedBox(
          width: 600,
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                    'Elige los documentos que puede consultar el modelo. '
                    'Seleccionarlos no garantiza que todos quepan completos en el contexto.'),
                const SizedBox(height: 12),
                if (documents.isEmpty)
                  const Text('Adjunta un documento para añadir una fuente.'),
                Flexible(
                    child: SingleChildScrollView(
                        child: Column(children: [
                  for (final document in documents)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: chat.isSourceEnabled(document),
                      onChanged: enabled
                          ? (value) =>
                              chat.setSourceEnabled(document, value ?? false)
                          : null,
                      title: Text(document.name),
                      subtitle: document.extractionTruncated
                          ? const Text(
                              'Extracción parcial: no sirve para totales completos')
                          : null,
                      secondary: IconButton(
                          tooltip: 'Ver texto conservado',
                          onPressed: () =>
                              showDocumentTextDialog(context, document),
                          icon: const Icon(Icons.visibility_outlined)),
                    ),
                ]))),
              ])),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'))
      ],
    );
  }
}
