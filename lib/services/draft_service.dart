import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../config/ui_config.dart';
import '../models/document_attachment.dart';
import 'document_store_service.dart';

class ChatDraft {
  final String text;
  final List<String> imagePaths;
  final List<DocumentAttachment> documents;
  final String? warning;

  ChatDraft({
    this.text = '',
    List<String> imagePaths = const [],
    List<DocumentAttachment> documents = const [],
    this.warning,
  })  : imagePaths = List.unmodifiable(imagePaths),
        documents = List.unmodifiable(documents);

  bool get isEmpty => text.isEmpty && imagePaths.isEmpty && documents.isEmpty;

  Map<String, dynamic> toJson({required bool full}) => {
        'version': 1,
        'text': full || text.length <= UiConfig.smallDraftChars ? text : '',
        'textOmitted': !full && text.length > UiConfig.smallDraftChars,
        'images': imagePaths,
        'documents': [
          for (final document in documents)
            {
              ...document.toJson(),
              'text': full ? document.text : null,
              if (full) 'extractedText': document.extractedText,
            }
        ],
      };

  factory ChatDraft.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) {
      throw const FormatException('Versión de borrador no admitida.');
    }
    return ChatDraft(
      text: json['text'] as String? ?? '',
      imagePaths: (json['images'] as List? ?? const []).cast<String>(),
      documents: [
        for (final value in json['documents'] as List? ?? const [])
          DocumentAttachment.fromJson(Map<String, dynamic>.from(value as Map))
              .copyWith(extractedText: value['extractedText'] as String?),
      ],
      warning: json['textOmitted'] == true
          ? 'El texto largo de este borrador no se pudo conservar. '
              'Elige una carpeta en Contexto y archivos para los próximos borradores.'
          : null,
    );
  }
}

/// Conserva borradores por conversación, sin textos grandes en preferencias.
class DraftService {
  DraftService({DocumentStoreService? store, String? fallbackRoot})
      : _store = store ?? DocumentStoreService.instance,
        _fallbackRoot = fallbackRoot;

  static final instance = DraftService();
  final DocumentStoreService _store;
  final String? _fallbackRoot;
  final Map<String, ChatDraft> _memory = {};
  final Set<String> _deleted = {};
  final Set<String> _dirty = {};
  Future<void> _pending = Future<void>.value();

  String _key(String id) => '${UiConfig.draftsPreferencePrefix}$id';

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final future = _pending.then((_) => operation());
    _pending = future.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return future;
  }

  Future<ChatDraft> load(String id) async {
    _validateId(id);
    if (_deleted.contains(id)) {
      return ChatDraft();
    }
    final cached = _memory[id];
    if (cached != null) {
      return cached;
    }
    await _pending;
    if (_deleted.contains(id)) {
      return ChatDraft();
    }
    if (_memory.containsKey(id)) {
      return _memory[id]!;
    }
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(id));
    ChatDraft draft;
    if (raw == null) {
      draft = ChatDraft();
    } else {
      final json = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      if (json['file'] == true) {
        final file = await _file(id, fallback: json['fallback'] == true);
        if (await file.length() > UiConfig.maxDraftBytes) {
          throw const FormatException(
              'El borrador supera el límite permitido.');
        }
        draft = ChatDraft.fromJson(Map<String, dynamic>.from(
            jsonDecode(await file.readAsString()) as Map));
      } else {
        draft = ChatDraft.fromJson(json);
      }
    }
    // Una edición local puede llegar mientras se lee el archivo anterior.
    if (_deleted.contains(id)) {
      return ChatDraft();
    }
    return _memory.putIfAbsent(id, () => draft);
  }

  void remember(String id, ChatDraft draft) {
    _validateId(id);
    if (!_deleted.contains(id)) {
      if (!identical(_memory[id], draft)) {
        _memory[id] = draft;
        _dirty.add(id);
      }
    }
  }

  /// Permite esperar los últimos cambios al cerrar antes del debounce de la UI.
  Future<void> flush() async {
    while (true) {
      await _pending;
      if (_dirty.isEmpty) {
        return;
      }
      for (final id in List<String>.of(_dirty)) {
        final current = _memory[id];
        if (!_deleted.contains(id) && current != null) {
          // Persistir nunca reinstala el snapshot en memoria: una edición
          // llegada durante la E/S pertenece a la siguiente vuelta.
          await _persist(id, current);
        }
      }
    }
  }

  Future<String?> save(String id, ChatDraft draft) {
    _validateId(id);
    if (_deleted.contains(id)) {
      return Future<String?>.value();
    }
    remember(id, draft);
    return _persist(id, draft);
  }

  Future<String?> _persist(String id, ChatDraft draft) => _serialized(() async {
        if (_deleted.contains(id)) {
          return null;
        }
        final prefs = await SharedPreferences.getInstance();
        if (draft.isEmpty) {
          await _removePersisted(id, prefs);
          _markPersisted(id, draft);
          return null;
        }
        final bytes = utf8.encode(jsonEncode(draft.toJson(full: true)));
        if (bytes.length > UiConfig.maxDraftBytes) {
          throw const FileSystemException(
              'El borrador supera el límite de almacenamiento.');
        }
        final fallback = _store.rootPath == null;
        final oldRaw = prefs.getString(_key(id));
        final old = oldRaw == null ? null : jsonDecode(oldRaw) as Map;
        final file = await _file(id, fallback: fallback);
        final temporary = File('${file.path}.pending');
        await _rejectLink(temporary.path);
        await temporary.writeAsBytes(bytes, flush: true);
        await _rejectLink(file.path);
        await temporary.rename(file.path);
        try {
          if (!await prefs.setString(
              _key(id), jsonEncode({'file': true, 'fallback': fallback}))) {
            throw const FileSystemException(
                'No se pudo registrar el borrador guardado.');
          }
        } catch (_) {
          if (oldRaw == null) {
            await prefs.remove(_key(id));
          } else {
            await prefs.setString(_key(id), oldRaw);
          }
          rethrow;
        }
        _markPersisted(id, draft);
        if (old?['file'] == true && (old?['fallback'] == true) != fallback) {
          try {
            final previousFile =
                await _file(id, fallback: old?['fallback'] == true);
            if (await previousFile.exists()) {
              await previousFile.delete();
            }
          } catch (error) {
            return 'Borrador guardado; no se pudo retirar la copia anterior: $error';
          }
        }
        return null;
      });

  /// Vacía el borrador de una conversación que sigue existiendo.
  Future<void> clear(String id) async {
    await save(id, ChatDraft());
  }

  /// Impide que callbacks tardíos resuciten un borrador de un chat eliminado.
  Future<void> delete(String id) {
    _validateId(id);
    final previous = _memory[id];
    _deleted.add(id);
    _memory.remove(id);
    _dirty.remove(id);
    return _serialized(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await _removePersisted(id, prefs);
      } catch (_) {
        _deleted.remove(id);
        if (previous != null) {
          _memory[id] = previous;
          _dirty.add(id);
        }
        rethrow;
      }
    });
  }

  void _markPersisted(String id, ChatDraft draft) {
    if (identical(_memory[id], draft)) {
      _dirty.remove(id);
    }
  }

  Future<void> _removePersisted(String id, SharedPreferences prefs) async {
    final raw = prefs.getString(_key(id));
    final marker = raw == null ? null : jsonDecode(raw) as Map;
    if (marker?['file'] == true) {
      final file = await _file(id, fallback: marker?['fallback'] == true);
      if (await file.exists()) {
        await file.delete();
      }
    }
    if (!await prefs.remove(_key(id))) {
      throw const FileSystemException(
          'No se pudo retirar el borrador guardado.');
    }
  }

  String _localRoot() {
    final fallbackRoot = _fallbackRoot;
    if (fallbackRoot != null) {
      return fallbackRoot;
    }
    final env = Platform.environment;
    final home = env['HOME'] ?? env['USERPROFILE'];
    String? base;
    if (Platform.isWindows) {
      base = env['LOCALAPPDATA'];
    } else if (Platform.isMacOS && home != null) {
      base = '$home/Library/Application Support';
    } else {
      base =
          env['XDG_STATE_HOME'] ?? (home == null ? null : '$home/.local/state');
    }
    if (base == null || base.trim().isEmpty) {
      throw const FileSystemException(
          'No se encontró la carpeta local de borradores.');
    }
    return '$base${Platform.pathSeparator}${UiConfig.applicationDataDirectory}';
  }

  Future<File> _file(String id, {bool fallback = false}) async {
    _validateId(id);
    final root = fallback ? _localRoot() : _store.rootPath;
    if (root == null) {
      throw const FileSystemException(
          'La carpeta de borradores no está disponible.');
    }
    if (fallback) {
      await _rejectLink(root);
      await Directory(root).create(recursive: true);
    }
    final canonicalRoot = await Directory(root).resolveSymbolicLinks();
    if (!_same(root, canonicalRoot)) {
      throw const FileSystemException(
          'La carpeta de borradores ha cambiado de destino.');
    }
    final directory =
        Directory('$root${Platform.pathSeparator}${UiConfig.draftsDirectory}');
    await _rejectLink(directory.path);
    await directory.create();
    if (!_same(
        await directory.resolveSymbolicLinks(), directory.absolute.path)) {
      throw const FileSystemException(
          'La carpeta de borradores no puede ser un enlace.');
    }
    final file = File('${directory.path}${Platform.pathSeparator}$id.json');
    await _rejectLink(file.path);
    if (await file.exists() &&
        !_same(await file.resolveSymbolicLinks(), file.absolute.path)) {
      throw const FileSystemException('El borrador está fuera de su carpeta.');
    }
    return file;
  }

  static Future<void> _rejectLink(String path) async {
    if (await FileSystemEntity.type(path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const FileSystemException(
          'No se permiten enlaces en los borradores.');
    }
  }

  static void _validateId(String id) {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id)) {
      throw const FormatException('Identificador de conversación inválido.');
    }
  }

  static bool _same(String a, String b) =>
      Platform.isWindows ? a.toLowerCase() == b.toLowerCase() : a == b;
}
