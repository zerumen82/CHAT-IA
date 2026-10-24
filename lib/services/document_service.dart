import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:xml/xml.dart';

import '../models/document_attachment.dart';

/// Extrae el texto de documentos (PDF, XLSX, CSV y texto plano) para
/// enviarlo como contexto al modelo local.
///
/// Los límites son deliberadamente conservadores: el contexto de Ollama
/// configurado en la app es pequeño y un documento enorme desplazaría a la
/// conversación.
class DocumentService {
  DocumentService._();

  static const int maxFileBytes = 25 * 1024 * 1024;
  static const int maxCharsPerDocument = 8000;
  static const int maxTotalChars = 16000;
  static const int maxHistoryChars = 4000;
  static const int maxRowsPerSheet = 1000;
  static const int maxColumnsPerRow = 50;

  static const Set<String> imageExtensions = {
    'png',
    'jpg',
    'jpeg',
    'webp',
    'gif',
    'bmp',
  };

  static const Set<String> supportedExtensions = {
    'pdf',
    'xlsx',
    'xlsm',
    'csv',
    'txt',
    'md',
    'json',
    'log',
    'yaml',
    'yml',
  };

  static String extensionOf(String path) {
    final name = path.split(RegExp(r'[/\\]')).last;
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) {
      return '';
    }
    return name.substring(dot + 1).toLowerCase();
  }

  static bool isImagePath(String path) =>
      imageExtensions.contains(extensionOf(path));

  static bool isSupportedDocument(String path) =>
      supportedExtensions.contains(extensionOf(path));

  static DocumentKind kindOf(String path) {
    return switch (extensionOf(path)) {
      'pdf' => DocumentKind.pdf,
      'xlsx' || 'xlsm' || 'csv' => DocumentKind.spreadsheet,
      _ => DocumentKind.text,
    };
  }

  /// Lee [path] y devuelve el documento con su texto extraído.
  ///
  /// Nunca lanza: los fallos se devuelven en [DocumentAttachment.error] para
  /// que la UI pueda mostrarlos junto al archivo.
  static Future<DocumentAttachment> extract(
    String path, {
    String? displayName,
  }) async {
    final name = displayName ?? path.split(RegExp(r'[/\\]')).last;
    final kind = kindOf(name);

    DocumentAttachment failure(String message) => DocumentAttachment(
          path: path,
          name: name,
          kind: kind,
          sizeBytes: 0,
          error: message,
        );

    if (!isSupportedDocument(name)) {
      return failure(
        'Formato no admitido. Usa PDF, XLSX, CSV, TXT, MD, JSON o LOG.',
      );
    }

    try {
      final file = File(path);
      if (!await file.exists()) {
        return failure('No se encontró el archivo.');
      }

      final sizeBytes = await file.length();
      if (sizeBytes > maxFileBytes) {
        return failure('El archivo supera el límite de 25 MB.');
      }

      final bytes = await file.readAsBytes();
      final extension = extensionOf(name);

      String text;
      switch (extension) {
        case 'pdf':
          text = _extractPdf(bytes);
          break;
        case 'xlsx':
        case 'xlsm':
          text = _extractXlsx(bytes);
          break;
        default:
          text = _decodeText(bytes);
      }

      text = _normalize(text);
      if (text.isEmpty) {
        return DocumentAttachment(
          path: path,
          name: name,
          kind: kind,
          sizeBytes: sizeBytes,
          error: extension == 'pdf'
              ? 'El PDF no contiene texto seleccionable (puede ser un escaneo).'
              : 'El documento está vacío o no contiene texto legible.',
        );
      }

      final originalChars = text.length;
      final truncated = originalChars > maxCharsPerDocument;
      return DocumentAttachment(
        path: path,
        name: name,
        kind: kind,
        sizeBytes: sizeBytes,
        text: truncated ? truncateAtLineBreak(text, maxCharsPerDocument) : text,
        originalChars: originalChars,
        truncated: truncated,
      );
    } catch (error) {
      return DocumentAttachment(
        path: path,
        name: name,
        kind: kind,
        sizeBytes: 0,
        error: 'No se pudo leer el documento: $error',
      );
    }
  }

  /// Recorta `text` a `limit` caracteres sin partir una fila a la mitad.
  ///
  /// Añade una marca con cuánto se omitió para que el modelo (y el usuario)
  /// sepa que el documento no está completo.
  static String truncateAtLineBreak(String text, int limit) {
    if (text.isEmpty || limit <= 0) return '';
    if (text.length <= limit) return text;

    const reserve = 64;
    if (limit <= reserve + 16) {
      const shortMarker = '…[recortado]';
      if (limit <= shortMarker.length) return text.substring(0, limit);
      return '${text.substring(0, limit - shortMarker.length).trimRight()}'
          '$shortMarker';
    }

    final bodyLimit = limit - reserve;
    var cut = text.lastIndexOf('\n', bodyLimit);
    if (cut < bodyLimit ~/ 2) {
      cut = bodyLimit;
    }

    final omitted = text.length - cut;
    final marker = '\n[… recortado: $omitted caracteres omitidos]';
    return '${text.substring(0, cut).trimRight()}$marker';
  }

  /// Construye el bloque de contexto que se añade al mensaje del usuario.
  static String buildAttachmentContext(
    List<DocumentAttachment> documents, {
    int maxChars = maxTotalChars,
  }) {
    final ready = documents.where((document) => document.isReady).toList();
    if (ready.isEmpty) {
      return '';
    }

    final buffer = StringBuffer();
    buffer.writeln(
      'DOCUMENTOS ADJUNTOS (usa su contenido para responder; si la respuesta '
      'no está en ellos, indícalo):',
    );

    var remaining = maxChars;
    var included = 0;
    var omitted = 0;

    for (final document in ready) {
      if (remaining <= 0) {
        omitted++;
        continue;
      }

      final text = document.text!;
      final usable = truncateAtLineBreak(text, remaining);
      remaining -= usable.length;
      included++;

      buffer.writeln();
      buffer.writeln('--- Documento $included: ${document.name} ---');
      buffer.write(usable);
      buffer.writeln();
      buffer.writeln('--- Fin de ${document.name} ---');
    }

    if (omitted > 0) {
      buffer.writeln(
        '[$omitted documento(s) omitido(s) por límite de contexto]',
      );
    }

    return buffer.toString().trim();
  }

  // ---------------------------------------------------------------------------
  // PDF
  // ---------------------------------------------------------------------------

  static String _extractPdf(Uint8List bytes) {
    final document = PdfDocument(inputBytes: bytes);
    try {
      return PdfTextExtractor(document).extractText();
    } finally {
      document.dispose();
    }
  }

  // ---------------------------------------------------------------------------
  // XLSX (lectura directa del ZIP + XML de Office Open XML)
  // ---------------------------------------------------------------------------

  static String _extractXlsx(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final entries = <String, ArchiveFile>{};
    for (final file in archive.files) {
      if (file.isFile) {
        entries[file.name.replaceAll('\\', '/')] = file;
      }
    }

    String? read(String path) {
      final file = entries[path];
      if (file == null) {
        return null;
      }
      final content = file.readBytes();
      if (content == null) {
        return null;
      }
      return utf8.decode(content, allowMalformed: true);
    }

    final workbookXml = read('xl/workbook.xml');
    if (workbookXml == null) {
      throw const FormatException(
        'El archivo no parece un libro XLSX válido.',
      );
    }

    final sharedStrings = _parseSharedStrings(read('xl/sharedStrings.xml'));
    final dateStyles = _parseDateStyles(read('xl/styles.xml'));
    final relationships =
        _parseRelationships(read('xl/_rels/workbook.xml.rels'));
    final workbook = XmlDocument.parse(workbookXml);

    final buffer = StringBuffer();
    for (final sheet in workbook.findAllElements('sheet')) {
      if (buffer.length > maxCharsPerDocument * 2) {
        break;
      }

      final sheetName = sheet.getAttribute('name') ?? 'Hoja';
      final relationId = _attributeValue(sheet, 'id', prefix: 'r');
      final target = relationId == null ? null : relationships[relationId];
      final sheetPath = _resolveSheetPath(target, entries.keys);
      final sheetXml = sheetPath == null ? null : read(sheetPath);
      if (sheetXml == null) {
        continue;
      }

      final rows = _parseSheetRows(sheetXml, sharedStrings, dateStyles);
      if (rows.isEmpty) {
        continue;
      }

      if (buffer.isNotEmpty) {
        buffer.writeln();
      }
      buffer.writeln('Hoja "$sheetName":');
      for (final row in rows) {
        buffer.writeln(row);
      }
    }

    return buffer.toString();
  }

  static String? _resolveSheetPath(
    String? target,
    Iterable<String> availableEntries,
  ) {
    if (target == null || target.isEmpty) {
      return null;
    }

    final normalizedTarget = target.replaceAll('\\', '/');
    final candidates = <String>[
      if (normalizedTarget.startsWith('/'))
        normalizedTarget.substring(1)
      else
        'xl/$normalizedTarget',
      normalizedTarget.startsWith('/')
          ? normalizedTarget.substring(1)
          : normalizedTarget,
    ];

    for (final candidate in candidates) {
      if (availableEntries.contains(candidate)) {
        return candidate;
      }
    }
    return null;
  }

  static String? _attributeValue(
    XmlElement element,
    String localName, {
    String? prefix,
  }) {
    for (final attribute in element.attributes) {
      if (attribute.name.local == localName &&
          (prefix == null || attribute.name.prefix == prefix)) {
        return attribute.value;
      }
    }
    return null;
  }

  static List<String> _parseSharedStrings(String? xml) {
    if (xml == null || xml.isEmpty) {
      return const [];
    }
    final document = XmlDocument.parse(xml);
    return document
        .findAllElements('si')
        .map((element) =>
            element.findAllElements('t').map((text) => text.innerText).join())
        .toList();
  }

  /// Formatos integrados de Excel que representan una fecha.
  static const Set<int> _builtInDateFormats = {14, 15, 16, 17, 22};

  /// Índices de estilo (atributo `s` de cada celda) que son formato de fecha.
  static Set<int> _parseDateStyles(String? xml) {
    if (xml == null || xml.isEmpty) {
      return const {};
    }

    try {
      final document = XmlDocument.parse(xml);
      final customDateFormats = <int>{};
      for (final format in document.findAllElements('numFmt')) {
        final id = int.tryParse(format.getAttribute('numFmtId') ?? '');
        final code = format.getAttribute('formatCode') ?? '';
        if (id != null && _isDateFormatCode(code)) {
          customDateFormats.add(id);
        }
      }

      final cellXfs = document.findAllElements('cellXfs').isEmpty
          ? null
          : document.findAllElements('cellXfs').first;
      if (cellXfs == null) {
        return const {};
      }

      final dateStyles = <int>{};
      var index = 0;
      for (final xf in cellXfs.findElements('xf')) {
        final numFmtId = int.tryParse(xf.getAttribute('numFmtId') ?? '');
        if (numFmtId != null &&
            (_builtInDateFormats.contains(numFmtId) ||
                customDateFormats.contains(numFmtId))) {
          dateStyles.add(index);
        }
        index++;
      }
      return dateStyles;
    } catch (_) {
      return const {};
    }
  }

  static bool _isDateFormatCode(String code) {
    final cleaned = code
        .replaceAll(RegExp(r'"[^"]*"'), '')
        .replaceAll(RegExp(r'\[[^\]]*\]'), '')
        .toLowerCase();
    return cleaned.contains('d') || cleaned.contains('y');
  }

  /// Convierte el número de serie de Excel a `dd/mm/aaaa`.
  static String formatExcelDate(double serial) {
    final date = DateTime(1899, 12, 30).add(
      Duration(
        milliseconds: (serial * Duration.millisecondsPerDay).round(),
      ),
    );
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }

  static Map<String, String> _parseRelationships(String? xml) {
    if (xml == null || xml.isEmpty) {
      return const {};
    }
    final document = XmlDocument.parse(xml);
    final relationships = <String, String>{};
    for (final relationship in document.findAllElements('Relationship')) {
      final id = relationship.getAttribute('Id');
      final target = relationship.getAttribute('Target');
      if (id != null && target != null) {
        relationships[id] = target;
      }
    }
    return relationships;
  }

  static List<String> _parseSheetRows(
    String sheetXml,
    List<String> sharedStrings,
    Set<int> dateStyles,
  ) {
    final document = XmlDocument.parse(sheetXml);
    final rows = <String>[];
    var rowNumber = 0;

    for (final row in document.findAllElements('row')) {
      if (rows.length >= maxRowsPerSheet) {
        rows.add('[Hoja recortada: máximo de $maxRowsPerSheet filas]');
        break;
      }

      rowNumber++;
      final rowIndex = int.tryParse(row.getAttribute('r') ?? '') ?? rowNumber;
      final cells = <int, String>{};

      for (final cell in row.findElements('c')) {
        final reference = cell.getAttribute('r');
        final column = _columnIndex(reference) ?? cells.length;
        final value = _cellValue(cell, sharedStrings, dateStyles);
        if (value.trim().isNotEmpty) {
          cells[column] = value.trim();
        }
      }

      if (cells.isEmpty) {
        continue;
      }

      final maxColumn = math.min(
        cells.keys.reduce(math.max),
        maxColumnsPerRow - 1,
      );
      final values = List<String>.generate(
        maxColumn + 1,
        (index) => cells[index] ?? '',
      );
      rows.add('Fila $rowIndex: ${values.join(' | ')}');
    }

    return rows;
  }

  static String _cellValue(
    XmlElement cell,
    List<String> sharedStrings,
    Set<int> dateStyles,
  ) {
    final type = cell.getAttribute('t');
    final rawValue = cell.findElements('v').isEmpty
        ? null
        : cell.findElements('v').first.innerText;

    // Las fechas de Excel son números de serie: se convierten cuando la celda
    // usa un formato de fecha, para que el modelo no lea "45321".
    if (type == null || type == 'n') {
      final styleIndex = int.tryParse(cell.getAttribute('s') ?? '');
      final serial = double.tryParse(rawValue ?? '');
      if (styleIndex != null &&
          dateStyles.contains(styleIndex) &&
          serial != null &&
          serial > 0 &&
          serial < 2958466) {
        return formatExcelDate(serial);
      }
    }

    switch (type) {
      case 's':
        final index = int.tryParse(rawValue ?? '');
        if (index == null || index < 0 || index >= sharedStrings.length) {
          return '';
        }
        return sharedStrings[index];
      case 'inlineStr':
        return cell.findAllElements('t').map((text) => text.innerText).join();
      case 'b':
        return rawValue == '1' ? 'verdadero' : 'falso';
      case 'str':
      case 'e':
        return rawValue ?? '';
      default:
        return rawValue ?? '';
    }
  }

  static int? _columnIndex(String? reference) {
    if (reference == null || reference.isEmpty) {
      return null;
    }
    var index = 0;
    var letters = 0;
    for (final codeUnit in reference.codeUnits) {
      if (codeUnit < 65 || codeUnit > 90) {
        break;
      }
      index = index * 26 + (codeUnit - 64);
      letters++;
    }
    return letters == 0 ? null : index - 1;
  }

  // ---------------------------------------------------------------------------
  // Texto plano
  // ---------------------------------------------------------------------------

  static String _decodeText(Uint8List bytes) {
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      return _decodeUtf16(bytes.sublist(2), littleEndian: true);
    }
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return _decodeUtf16(bytes.sublist(2), littleEndian: false);
    }

    var text = utf8.decode(bytes, allowMalformed: true);
    if (text.startsWith('\uFEFF')) {
      text = text.substring(1);
    }
    return text;
  }

  static String _decodeUtf16(Uint8List bytes, {required bool littleEndian}) {
    final units = <int>[];
    for (var index = 0; index + 1 < bytes.length; index += 2) {
      units.add(littleEndian
          ? bytes[index] | (bytes[index + 1] << 8)
          : (bytes[index] << 8) | bytes[index + 1]);
    }
    return String.fromCharCodes(units);
  }

  static String _normalize(String text) {
    return text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll('\t', ' ')
        .replaceAll(RegExp(r'[ ]{2,}'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }
}
