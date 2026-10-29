import 'dart:io';

import '../config/context_config.dart';
import 'conversation_service.dart';
import 'document_store_service.dart';
import 'generated_file_service.dart';

/// Guarda la selección enviada fuera de SharedPreferences.
class ContextSnapshotService {
  static Future<String> save(String conversationId, String text) async {
    if (!RegExp(r'^[a-z0-9-]+$').hasMatch(conversationId)) {
      throw const FormatException('Conversación no válida.');
    }
    final root = DocumentStoreService.instance.rootPath;
    if (root == null) throw StateError('No hay carpeta de documentos.');
    final directory =
        Directory('$root/${ContextConfig.snapshotsDirectory}/$conversationId');
    await GeneratedFileService.validateInsideRoot(directory.path,
        rootPath: root);
    await directory.create(recursive: true);
    await GeneratedFileService.validateInsideRoot(directory.path,
        rootPath: root);
    var occupied = 0;
    await for (final entry
        in directory.parent.list(recursive: true, followLinks: false)) {
      if (entry is File) occupied += await entry.length();
    }
    if (occupied + text.length * 4 > ContextConfig.maxSnapshotStorageBytes) {
      throw StateError('El almacén de selecciones de contexto está lleno.');
    }
    final id = '$conversationId/${ConversationService.newId()}';
    final output = File('$root/${ContextConfig.snapshotsDirectory}/$id.txt');
    await GeneratedFileService.validateInsideRoot(output.path, rootPath: root);
    await output.writeAsString(text, flush: true);
    return id;
  }

  static Future<String> read(String id) async {
    if (!RegExp(r'^[a-z0-9-]+/[a-z0-9-]+$').hasMatch(id)) {
      throw const FormatException('Referencia de contexto no válida.');
    }
    final root = DocumentStoreService.instance.rootPath;
    if (root == null) throw StateError('No hay carpeta de documentos.');
    final path = '$root/${ContextConfig.snapshotsDirectory}/$id.txt';
    await GeneratedFileService.validateInsideRoot(path, rootPath: root);
    final file = File(path);
    if (await file.length() >
        ContextConfig.profiles.last * ContextConfig.charsPerToken * 4) {
      throw StateError('La selección guardada supera el límite permitido.');
    }
    return file.readAsString();
  }

  static Future<void> deleteConversation(String id) async {
    if (!RegExp(r'^[a-z0-9-]+$').hasMatch(id)) {
      throw const FormatException('Conversación no válida.');
    }
    final root = DocumentStoreService.instance.rootPath;
    if (root == null) return;
    final path = '$root/${ContextConfig.snapshotsDirectory}/$id';
    await GeneratedFileService.validateInsideRoot(path, rootPath: root);
    final directory = Directory(path);
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}
