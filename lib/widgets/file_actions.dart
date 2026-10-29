import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../models/export_format.dart';
import '../models/generated_file.dart';
import '../models/message.dart';
import '../models/document_attachment.dart';
import '../services/context_snapshot_service.dart';
import 'document_text_dialog.dart';
import '../services/export_service.dart';
import '../services/generated_file_service.dart';

String _suggestedName(String title) {
  final safe = title.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_').trim();
  return safe.isEmpty
      ? 'LightChat'
      : safe.substring(0, safe.length.clamp(0, 80));
}

Future<void> showSentContext(BuildContext context, Message message) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final metadata = message.metadata;
    final snapshot = metadata?['contextSnapshot'] as String?;
    final text = metadata?['contextText'] as String? ??
        (snapshot == null ? '' : await ContextSnapshotService.read(snapshot));
    if (!context.mounted) return;
    await showDocumentTextDialog(
        context,
        DocumentAttachment(
            path: '',
            name: 'Contexto enviado',
            kind: DocumentKind.text,
            sizeBytes: 0,
            text: text),
        exactSelection: true);
  } catch (error) {
    messenger.showSnackBar(
        SnackBar(content: Text('No se pudo abrir el contexto: $error')));
  }
}

Future<void> showExportDialog(
  BuildContext context, {
  required String title,
  String? text,
  List<Message>? messages,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final format = await showDialog<ExportFormat>(
      context: context,
      builder: (dialogContext) =>
          SimpleDialog(title: const Text('Exportar'), children: [
            for (final format in [
              ExportFormat.txt,
              ExportFormat.markdown,
              ExportFormat.pdf,
              ExportFormat.docx
            ])
              SimpleDialogOption(
                  onPressed: () => Navigator.pop(dialogContext, format),
                  child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(format.label))),
            if (messages != null)
              const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                      'Se exportan todos los mensajes conservados. Los turnos eliminados anteriormente no se pueden recuperar.')),
          ]));
  if (format == null) {
    return;
  }
  try {
    final destination = await getSaveLocation(
        suggestedName: '${_suggestedName(title)}.${format.extension}',
        acceptedTypeGroups: [
          XTypeGroup(label: format.label, extensions: [format.extension])
        ]);
    if (destination == null) {
      return;
    }
    final markdown = messages == null
        ? (text ?? '')
        : ExportService.conversationMarkdown(messages, title);
    final bytes = await ExportService.encode(
        format: format, title: title, markdown: markdown);
    await File(destination.path).writeAsBytes(bytes, flush: true);
    messenger.showSnackBar(const SnackBar(content: Text('Archivo guardado')));
  } catch (error) {
    messenger
        .showSnackBar(SnackBar(content: Text('No se pudo exportar: $error')));
  }
}

Future<void> saveGeneratedFile(BuildContext context, GeneratedFile file) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final destination =
        await getSaveLocation(suggestedName: file.name, acceptedTypeGroups: [
      XTypeGroup(label: file.format.label, extensions: [file.format.extension])
    ]);
    if (destination == null) {
      return;
    }
    final bytes = await GeneratedFileService.read(file);
    await File(destination.path).writeAsBytes(bytes, flush: true);
    messenger.showSnackBar(const SnackBar(content: Text('Archivo guardado')));
  } catch (error) {
    messenger
        .showSnackBar(SnackBar(content: Text('No se pudo guardar: $error')));
  }
}
