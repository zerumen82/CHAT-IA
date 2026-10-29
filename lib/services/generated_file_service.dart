import 'dart:io';
import 'dart:typed_data';

import '../config/context_config.dart';
import '../models/export_format.dart';
import '../models/generated_file.dart';
import 'conversation_service.dart';
import 'document_store_service.dart';
import 'export_service.dart';

/// Solo convierte datos estructurados a documentos; nunca ejecuta código.
class GeneratedFileService {
  static const tools = <Map<String, dynamic>>[
    {
      'type': 'function',
      'function': {
        'name': 'create_pdf',
        'description': 'Crea un archivo PDF real con el contenido solicitado.',
        'parameters': {
          'type': 'object',
          'properties': {
            'name': {
              'type': 'string',
              'description': 'Nombre del archivo sin ruta'
            },
            'title': {'type': 'string'},
            'content': {
              'type': 'string',
              'description': 'Contenido completo en Markdown'
            },
          },
          'required': ['name', 'title', 'content'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'create_spreadsheet',
        'description': 'Crea un Excel XLSX real con hojas y celdas literales.',
        'parameters': {
          'type': 'object',
          'properties': {
            'name': {
              'type': 'string',
              'description': 'Nombre del archivo sin ruta'
            },
            'title': {'type': 'string'},
            'sheets': {
              'type': 'array',
              'items': {
                'type': 'object',
                'properties': {
                  'name': {'type': 'string'},
                  'rows': {
                    'type': 'array',
                    'items': {'type': 'array', 'items': {}},
                  },
                },
                'required': ['name', 'rows'],
              },
            },
          },
          'required': ['name', 'title', 'sheets'],
        },
      },
    },
  ];

  static bool _safeId(String value) => RegExp(r'^[a-z0-9-]+$').hasMatch(value);

  static Future<Directory> _conversationDirectory(String id) async {
    if (!_safeId(id)) {
      throw const FormatException('Identificador de conversación no válido.');
    }
    final root = DocumentStoreService.instance.rootPath;
    if (root == null) {
      throw StateError(
          'Selecciona una carpeta de documentos en Contexto y archivos.');
    }
    final directory =
        Directory('$root/${ContextConfig.generatedDirectory}/$id');
    await validateInsideRoot(directory.path);
    await directory.create(recursive: true);
    await validateInsideRoot(directory.path);
    return directory;
  }

  /// Rechaza enlaces y referencias manipuladas antes de leer, crear o borrar.
  static Future<void> validateInsideRoot(String path,
      {String? rootPath}) async {
    final root = rootPath ?? DocumentStoreService.instance.rootPath;
    if (root == null) throw StateError('No hay carpeta de documentos.');
    final rootDirectory = Directory(root).absolute;
    final rootResolved = await rootDirectory.resolveSymbolicLinks();
    final target = File(path).absolute.uri.normalizePath();
    final rootUri = Directory(rootResolved).uri;
    if (!target.toString().startsWith(rootUri.toString())) {
      throw const FileSystemException('El archivo está fuera del almacén.');
    }
    var current = File(path).absolute.path;
    while (current.length > rootDirectory.path.length) {
      final type = await FileSystemEntity.type(current, followLinks: false);
      if (type == FileSystemEntityType.link) {
        throw const FileSystemException(
            'No se permiten enlaces en el almacén.');
      }
      if (type != FileSystemEntityType.notFound) {
        final resolved = await File(current).resolveSymbolicLinks();
        final expected = File(current).absolute.path.replaceAll('\\', '/');
        final canonical = resolved.replaceAll('\\', '/');
        final matches = Platform.isWindows
            ? canonical.toLowerCase() == expected.toLowerCase()
            : canonical == expected;
        if (!matches) {
          throw const FileSystemException(
              'La ruta del almacén ha cambiado de destino.');
        }
      }
      final parent = File(current).parent.path;
      if (parent == current) break;
      current = parent;
    }
  }

  static Future<GeneratedFile> create({
    required Map<String, dynamic> call,
    required String conversationId,
  }) async {
    final function = call['function'];
    if (function is! Map || function['arguments'] is! Map) {
      throw const FormatException(
          'La herramienta no recibió argumentos válidos.');
    }
    final args = Map<String, dynamic>.from(function['arguments'] as Map);
    final format = switch (function['name']) {
      'create_pdf' => ExportFormat.pdf,
      'create_spreadsheet' => ExportFormat.xlsx,
      _ => throw const FormatException('Herramienta desconocida.'),
    };
    final name = args['name'];
    final title = args['title'];
    if (name is! String ||
        name.trim().isEmpty ||
        name.length > ContextConfig.maxGeneratedNameChars ||
        RegExp(r'[<>:"/\\|?*\x00-\x1f]').hasMatch(name) ||
        name == '.' ||
        name == '..' ||
        title is! String ||
        title.trim().isEmpty) {
      throw const FormatException('Nombre o título de archivo no válido.');
    }
    final content = args['content'];
    if (format == ExportFormat.pdf && content is! String) {
      throw const FormatException('Falta el contenido del PDF.');
    }
    final rawSheets = args['sheets'];
    if (format == ExportFormat.xlsx && rawSheets is! List) {
      throw const FormatException('Faltan las hojas del Excel.');
    }
    final bytes = await ExportService.encode(
      format: format,
      title: title,
      markdown: content is String ? content : '',
      sheets: rawSheets is List
          ? rawSheets
              .map((sheet) => Map<String, dynamic>.from(sheet as Map))
              .toList()
          : null,
    );
    if (bytes.isEmpty || bytes.length > ContextConfig.maxGeneratedFileBytes) {
      throw StateError('El archivo supera el tamaño permitido.');
    }
    final directory = await _conversationDirectory(conversationId);
    var occupied = 0;
    final generatedRoot = directory.parent;
    await for (final entry
        in generatedRoot.list(recursive: true, followLinks: false)) {
      if (entry is File) occupied += await entry.length();
    }
    if (occupied + bytes.length > ContextConfig.maxGeneratedStorageBytes) {
      throw StateError('El almacén de archivos generados está lleno.');
    }
    final id = ConversationService.newId();
    final extension = format.extension;
    final stem = name
        .replaceFirst(RegExp(r'\.(pdf|xlsx)$', caseSensitive: false), '')
        .trim();
    final filename = '$stem.$extension';
    final relative =
        '${ContextConfig.generatedDirectory}/$conversationId/$id.$extension';
    final root = DocumentStoreService.instance.rootPath!;
    final output = File('$root/$relative');
    final temporary = File('${output.path}.partial');
    await validateInsideRoot(output.path);
    try {
      await validateInsideRoot(temporary.path, rootPath: root);
      await temporary.writeAsBytes(bytes, flush: true);
      await validateInsideRoot(temporary.path, rootPath: root);
      await validateInsideRoot(output.path, rootPath: root);
      await temporary.rename(output.path);
    } finally {
      await validateInsideRoot(temporary.path, rootPath: root);
      if (await temporary.exists()) await temporary.delete();
    }
    return GeneratedFile(
        id: id,
        name: filename,
        format: format,
        sizeBytes: bytes.length,
        relativePath: relative);
  }

  static Future<Uint8List> read(GeneratedFile file) async {
    final root = DocumentStoreService.instance.rootPath;
    if (root == null) throw StateError('No hay carpeta de documentos.');
    final parts = file.relativePath.replaceAll('\\', '/').split('/');
    if (parts.length != 3 ||
        parts.first != ContextConfig.generatedDirectory ||
        !_safeId(parts[1]) ||
        !RegExp(r'^[a-z0-9-]+\.(pdf|xlsx)$').hasMatch(parts[2])) {
      throw const FormatException('Referencia de archivo no válida.');
    }
    final path = '$root/${parts.join('/')}';
    await validateInsideRoot(path);
    final source = File(path);
    if (await source.length() > ContextConfig.maxGeneratedFileBytes) {
      throw StateError('Archivo demasiado grande.');
    }
    return source.readAsBytes();
  }

  static Future<void> deleteConversation(String id) async {
    if (!_safeId(id) || DocumentStoreService.instance.rootPath == null) return;
    final path =
        '${DocumentStoreService.instance.rootPath}/${ContextConfig.generatedDirectory}/$id';
    await validateInsideRoot(path);
    final directory = Directory(path);
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}
