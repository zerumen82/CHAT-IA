import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../config/context_config.dart';
import '../config/document_config.dart';
import '../config/ui_config.dart';
import '../models/document_attachment.dart';

/// Almacén del texto documental, separado de las preferencias de mensajes.
class DocumentStoreService {
  DocumentStoreService();

  static final DocumentStoreService instance = DocumentStoreService();
  String? _rootPath;
  String? get rootPath => _rootPath;
  final Map<String, _StoredDocument> _documents = {};
  Future<void> _pending = Future<void>.value();

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> initialize() => _serialized(() async {
        final prefs = await SharedPreferences.getInstance();
        final saved = prefs.getString(DocumentConfig.rootPreferenceKey);
        if (saved != null && saved.isNotEmpty) {
          try {
            _activate(await _readRoot(saved));
          } catch (_) {
            // Se informa del fallo al caller, pero permite elegir otra carpeta.
            _rootPath = null;
            _documents.clear();
            rethrow;
          }
        } else {
          _rootPath = null;
          _documents.clear();
        }
      });

  /// Solo se llama tras una selección explícita de carpeta por el usuario.
  Future<void> configureRoot(String path) => _serialized(() async {
        if (path.trim().isEmpty) {
          throw const FileSystemException(
              'La carpeta de documentos está vacía.');
        }
        final candidate = await _readRoot(path);
        final current = _rootPath;
        if (current != null &&
            !_same(current, candidate.path) &&
            await _hasLibraryContent(current)) {
          throw const FileSystemException(
              'La biblioteca contiene archivos. Conserva su carpeta para '
              'mantener accesibles los documentos, archivos generados y contextos.');
        }
        final prefs = await SharedPreferences.getInstance();
        final previousPreference =
            prefs.getString(DocumentConfig.rootPreferenceKey);
        try {
          if (!await prefs.setString(
              DocumentConfig.rootPreferenceKey, candidate.path)) {
            throw const FileSystemException(
                'No se pudo guardar la carpeta documental.');
          }
        } catch (_) {
          // SharedPreferences modifica su caché antes de confirmar la escritura.
          // Restaurarla también cuando el backend devuelve false o lanza.
          if (previousPreference == null) {
            await prefs.remove(DocumentConfig.rootPreferenceKey);
          } else {
            await prefs.setString(
                DocumentConfig.rootPreferenceKey, previousPreference);
          }
          rethrow;
        }
        _activate(candidate);
      });

  Future<_LoadedRoot> _readRoot(String path) async {
    final directory = Directory(path);
    if (!await directory.exists()) {
      throw FileSystemException('No existe la carpeta de documentos.', path);
    }
    final canonical = await directory.resolveSymbolicLinks();
    final store =
        Directory(_join(canonical, DocumentConfig.storeDirectoryName));
    if (await FileSystemEntity.type(store.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const FileSystemException(
          'El almacén documental no puede ser un enlace.');
    }
    await store.create();
    final resolvedStore = await store.resolveSymbolicLinks();
    if (!_inside(resolvedStore, canonical) ||
        !_same(resolvedStore, store.absolute.path)) {
      throw const FileSystemException(
          'El almacén está fuera de la carpeta elegida.');
    }
    // Validar y cargar antes de sustituir el almacén activo.
    final index = File(_join(resolvedStore, DocumentConfig.indexFileName));
    await _rejectLink(index.path);
    final loaded = <String, _StoredDocument>{};
    if (await index.exists()) {
      if (await index.length() > DocumentConfig.maxFileBytes) {
        throw const FormatException(
            'El índice documental supera el límite permitido.');
      }
      final json = jsonDecode(await index.readAsString());
      if (json is! Map<String, dynamic> ||
          json['version'] != 1 ||
          json['documents'] is! List) {
        throw const FormatException('El índice documental no es válido.');
      }
      for (final value in json['documents'] as List) {
        final entry =
            _StoredDocument.fromJson(Map<String, dynamic>.from(value as Map));
        _validateId(entry.document.storageId!);
        loaded[entry.document.storageId!] = entry;
      }
      if (loaded.length > DocumentConfig.maxDocuments) {
        throw const FormatException(
            'El índice contiene demasiados documentos.');
      }
    }
    return _LoadedRoot(canonical, loaded);
  }

  void _activate(_LoadedRoot loaded) {
    _rootPath = loaded.path;
    _documents
      ..clear()
      ..addAll(loaded.documents);
  }

  Future<bool> _hasLibraryContent(String root) async {
    if (_documents.isNotEmpty) {
      return true;
    }
    final canonical = await Directory(root).resolveSymbolicLinks();
    if (!_same(root, canonical)) {
      throw const FileSystemException(
          'La carpeta documental ha cambiado de destino.');
    }
    for (final folder in [
      ContextConfig.generatedDirectory,
      ContextConfig.snapshotsDirectory,
      UiConfig.draftsDirectory,
    ]) {
      final path = _join(root, folder);
      final type = await FileSystemEntity.type(path, followLinks: false);
      if (type == FileSystemEntityType.link ||
          type == FileSystemEntityType.file) {
        return true;
      }
      if (type == FileSystemEntityType.directory) {
        await for (final entry
            in Directory(path).list(recursive: true, followLinks: false)) {
          if (entry is File || entry is Link) {
            return true;
          }
        }
      }
    }
    final managed = await _store();
    await for (final entry in managed.list(followLinks: false)) {
      if (entry is Link ||
          (entry is File &&
              !_same(entry.path,
                  _join(managed.path, DocumentConfig.indexFileName)))) {
        // Incluye extracciones huérfanas: cambiar de raíz tampoco las oculta.
        return true;
      }
    }
    return false;
  }

  Future<Directory> _store() async {
    final root = _rootPath;
    if (root == null) {
      throw const FileSystemException(
          'Selecciona una carpeta para conservar documentos.');
    }
    // Se verifica de nuevo en cada operación para detectar cambios externos.
    final canonical = await Directory(root).resolveSymbolicLinks();
    if (!_same(canonical, root)) {
      throw const FileSystemException(
          'La carpeta documental ha cambiado de destino.');
    }
    final store = Directory(_join(root, DocumentConfig.storeDirectoryName));
    await _rejectLink(store.path);
    final resolved = await store.resolveSymbolicLinks();
    if (!_inside(resolved, root) || !_same(resolved, store.absolute.path)) {
      throw const FileSystemException(
          'Ruta documental fuera de la carpeta configurada.');
    }
    return Directory(resolved);
  }

  Future<File> _file(String id) async {
    _validateId(id);
    final store = await _store();
    final file = File(_join(store.path, '$id.json'));
    await _rejectLink(file.path);
    return file;
  }

  Future<DocumentAttachment> put(
    DocumentAttachment document, {
    required String conversationId,
  }) =>
      _serialized(() async {
        if (!document.isReady || conversationId.isEmpty) {
          throw const FormatException('Documento o conversación no válidos.');
        }
        final existing = _documents[document.storageId];
        if (existing != null) {
          if (existing.conversations.contains(conversationId)) {
            return existing.document;
          }
          final before = Set<String>.of(existing.conversations);
          existing.conversations.add(conversationId);
          try {
            await _saveIndex();
          } catch (_) {
            existing.conversations
              ..clear()
              ..addAll(before);
            rethrow;
          }
          return existing.document;
        }
        final content = document.extractedText ?? document.text!;
        if (content.length > DocumentConfig.maxExtractedChars) {
          throw const FormatException(
              'La extracción supera el límite de almacenamiento.');
        }
        if (_documents.length >= DocumentConfig.maxDocuments) {
          throw const FileSystemException(
              'El almacén ha alcanzado el máximo de documentos.');
        }
        final bytes = utf8.encode(jsonEncode({'text': content}));
        if (await _storedBytes() + bytes.length >
            DocumentConfig.maxStoredBytes) {
          throw const FileSystemException('El almacén documental está lleno.');
        }
        final random = Random.secure();
        final id = '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}-'
            '${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
        final preview = document.text!;
        final saved = document.copyWith(
          storageId: id,
          text: preview.length > DocumentConfig.persistedPreviewChars
              ? preview.substring(0, DocumentConfig.persistedPreviewChars)
              : preview,
          truncated: document.truncated ||
              preview.length > DocumentConfig.persistedPreviewChars,
          clearExtractedText: true,
        );
        final file = await _file(id);
        await _writeAtomic(file, bytes);
        _documents[id] = _StoredDocument(saved, {conversationId});
        try {
          await _saveIndex();
        } catch (_) {
          _documents.remove(id);
          await _rejectLink(file.path);
          if (await file.exists()) {
            await file.delete();
          }
          rethrow;
        }
        return saved;
      });

  Future<List<DocumentAttachment>> documentsForConversation(String id) =>
      _serialized(() async => _documents.values
          .where((entry) => entry.conversations.contains(id))
          .map((entry) => entry.document)
          .toList());

  Future<DocumentAttachment> hydrate(DocumentAttachment document) =>
      _serialized(() async {
        final id = document.storageId;
        if (id == null || document.extractedText != null) {
          return document;
        }
        final file = await _file(id);
        if (!await file.exists()) {
          throw FileSystemException(
              'No se encuentra el texto conservado de ${document.name}.',
              file.path);
        }
        if (await file.length() >
            DocumentConfig.maxExtractedChars * 4 +
                DocumentConfig.maxFileBytes) {
          throw const FormatException(
              'El archivo conservado supera el límite permitido.');
        }
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is! Map<String, dynamic> ||
            decoded['text'] is! String ||
            (decoded['text'] as String).length >
                DocumentConfig.maxExtractedChars) {
          throw const FormatException(
              'El texto documental conservado no es válido.');
        }
        return document.copyWith(extractedText: decoded['text'] as String);
      });

  Future<void> deleteConversation(String id) => _serialized(() async {
        if (_rootPath == null || _documents.isEmpty) {
          return;
        }
        final previous = <String, Set<String>>{
          for (final entry in _documents.entries)
            entry.key: Set<String>.of(entry.value.conversations),
        };
        final removed = <String, _StoredDocument>{};
        for (final entry in _documents.entries) {
          entry.value.conversations.remove(id);
          if (entry.value.conversations.isEmpty) {
            removed[entry.key] = entry.value;
          }
        }
        for (final key in removed.keys) {
          _documents.remove(key);
        }
        try {
          await _saveIndex();
        } catch (_) {
          _documents.addAll(removed);
          for (final entry in _documents.entries) {
            entry.value.conversations
              ..clear()
              ..addAll(previous[entry.key]!);
          }
          rethrow;
        }
        for (final key in removed.keys) {
          final file = await _file(key);
          if (await file.exists()) {
            await file.delete();
          }
        }
      });

  Future<int> _storedBytes() async {
    final store = await _store();
    var total = 0;
    await for (final entry in store.list(followLinks: false)) {
      if (entry is File) {
        total += await entry.length();
      }
    }
    return total;
  }

  Future<void> _saveIndex() async {
    final store = await _store();
    final index = File(_join(store.path, DocumentConfig.indexFileName));
    await _rejectLink(index.path);
    await _writeAtomic(
        index,
        utf8.encode(jsonEncode({
          'version': 1,
          'documents':
              _documents.values.map((entry) => entry.toJson()).toList(),
        })));
  }

  Future<void> _writeAtomic(File file, List<int> bytes) async {
    final temporary = File('${file.path}.pending');
    await _rejectLink(temporary.path);
    await temporary.writeAsBytes(bytes, flush: true);
    try {
      await _rejectLink(file.path);
      await temporary.rename(file.path);
    } finally {
      // No borrar una ruta que otro proceso sustituyó por un enlace.
      await _rejectLink(temporary.path);
      if (await temporary.exists()) {
        await temporary.delete();
      }
    }
  }

  static Future<void> _rejectLink(String path) async {
    if (await FileSystemEntity.type(path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw FileSystemException(
          'No se permiten enlaces en el almacén documental.', path);
    }
  }

  static void _validateId(String id) {
    if (!RegExp(r'^[a-f0-9]+-[a-f0-9]{32}$').hasMatch(id)) {
      throw const FormatException('Referencia documental no válida.');
    }
  }

  static String _join(String parent, String child) =>
      parent.endsWith(Platform.pathSeparator)
          ? '$parent$child'
          : '$parent${Platform.pathSeparator}$child';
  static bool _same(String first, String second) => Platform.isWindows
      ? first.toLowerCase() == second.toLowerCase()
      : first == second;
  static bool _inside(String child, String parent) {
    final prefix = parent.endsWith(Platform.pathSeparator)
        ? parent
        : '$parent${Platform.pathSeparator}';
    return Platform.isWindows
        ? child.toLowerCase().startsWith(prefix.toLowerCase())
        : child.startsWith(prefix);
  }
}

class _LoadedRoot {
  final String path;
  final Map<String, _StoredDocument> documents;
  _LoadedRoot(this.path, this.documents);
}

class _StoredDocument {
  final DocumentAttachment document;
  final Set<String> conversations;
  _StoredDocument(this.document, this.conversations);

  Map<String, dynamic> toJson() => {
        'document': document.toJson(),
        'conversations': conversations.toList(),
      };

  factory _StoredDocument.fromJson(Map<String, dynamic> json) =>
      _StoredDocument(
        DocumentAttachment.fromJson(
            Map<String, dynamic>.from(json['document'] as Map)),
        (json['conversations'] as List).cast<String>().toSet(),
      );
}
