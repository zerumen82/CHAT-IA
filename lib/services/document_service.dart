import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel2003/excel2003.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:xml/xml.dart';

import '../models/document_attachment.dart';
import '../config/document_config.dart';
import '../config/spreadsheet_config.dart';
import '../models/spreadsheet_data.dart';

/// Extrae el texto de documentos (PDF, XLSX, XLS, CSV y texto plano) para
/// enviarlo como contexto al modelo local.
///
/// Los límites son deliberadamente conservadores: el contexto de Ollama
/// configurado en la app es pequeño y un documento enorme desplazaría a la
/// conversación.
class DocumentService {
  DocumentService._();

  static const int maxFileBytes = DocumentConfig.maxFileBytes;

  // Presupuesto de texto para 16.384 tokens de contexto (`num_ctx`). El texto
  // de una hoja de cálculo gasta más tokens por carácter que la prosa, así que
  // se deja holgura para el historial y la respuesta.
  static const int maxCharsPerDocument = DocumentConfig.previewChars;
  static const int maxTotalChars = 24000;
  static const int maxHistoryChars = 8000;

  /// Texto mínimo que merece la pena enviar de un documento, para que las
  /// cabeceras de los demás no lo dejen en una línea inservible.
  static const int minCharsPerDocument = 200;

  /// Extracto mínimo cuando el presupuesto es menor que ese mínimo.
  static const int _minExcerptChars = DocumentConfig.minExcerptChars;
  static const int maxRowsPerSheet = DocumentConfig.maxRowsPerSheet;
  static const int maxColumnsPerRow = DocumentConfig.maxColumnsPerRow;

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
    'xls',
    'csv',
    'tsv',
    'docx',
    'pptx',
    'html',
    'htm',
    'xml',
    'txt',
    'md',
    'json',
    'log',
    'yaml',
    'yml',
  };

  /// Texto para la UI con los formatos admitidos.
  static const String supportedFormatsLabel =
      'PDF, Word, Excel, PowerPoint, CSV/TSV, HTML, XML, TXT, MD, JSON o LOG';

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
      'xlsx' || 'xlsm' || 'xls' || 'csv' || 'tsv' => DocumentKind.spreadsheet,
      'pptx' => DocumentKind.presentation,
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
  }) =>
      Isolate.run(() => _extractInWorker(path, displayName: displayName));

  /// Lectura completa y estructurada para cálculos, independiente del contexto.
  /// Si una región no se puede leer o excede límites, rechaza todo el libro.
  static Future<SpreadsheetData> readSpreadsheet(String path,
          {String csvDelimiter = ','}) =>
      Isolate.run(() => _readSpreadsheetInWorker(path, csvDelimiter));

  static Future<SpreadsheetData> _readSpreadsheetInWorker(
      String path, String csvDelimiter) async {
    final file = File(path);
    final size = await file.length();
    if (size > DocumentConfig.maxFileBytes) {
      throw const FormatException(
          'El archivo supera el límite de lectura local.');
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > DocumentConfig.maxFileBytes) {
      throw const FormatException(
          'El archivo cambió de tamaño y supera el límite.');
    }
    final extension = extensionOf(path);
    final sheets = <SpreadsheetSheet>[];
    final warnings = <String>[];
    var totalCells = 0;
    void checkCellCount(int count) {
      totalCells += count;
      if (totalCells > SpreadsheetConfig.maxCells) {
        throw const FormatException(
            'Demasiadas celdas: no se calcularán totales sobre un libro incompleto.');
      }
    }

    if (extension == 'csv' || extension == 'tsv') {
      if (!{',', ';', '\t'}.contains(csvDelimiter)) {
        throw const FormatException('Separador de tabla no admitido.');
      }
      final rows = _splitDelimitedRows(
          _decodeText(bytes), extension == 'tsv' ? '\t' : csvDelimiter,
          bounded: true);
      final structured = <SpreadsheetRow>[];
      for (var i = 0; i < rows.length; i++) {
        checkCellCount(rows[i].length);
        if (rows[i].every((c) => c.trim().isEmpty)) {
          continue;
        }
        structured.add(SpreadsheetRow(i + 1, {
          for (var column = 0; column < rows[i].length; column++)
            column: SpreadsheetCell(rows[i][column]),
        }));
      }
      sheets.add(SpreadsheetSheet('Tabla', structured));
    } else if (extension == 'xlsx' ||
        extension == 'xlsm' ||
        (extension == 'xls' && _looksLikeZip(bytes))) {
      final entries = _zipEntries(bytes);
      final workbookXml = _zipText(entries, 'xl/workbook.xml');
      if (workbookXml == null) {
        throw const FormatException('Libro XLSX inválido.');
      }
      final workbook = XmlDocument.parse(workbookXml);
      final relations =
          _parseRelationships(_zipText(entries, 'xl/_rels/workbook.xml.rels'));
      final shared =
          _parseSharedStrings(_zipText(entries, 'xl/sharedStrings.xml'));
      final dates = _parseDateStyles(_zipText(entries, 'xl/styles.xml'));
      final elements = workbook.findAllElements('sheet').toList();
      if (elements.length > SpreadsheetConfig.maxSheets) {
        throw const FormatException('El libro supera el límite de hojas.');
      }
      for (final sheet in elements) {
        final name = sheet.getAttribute('name') ?? 'Hoja';
        final relation = _attributeValue(sheet, 'id', prefix: 'r');
        final sheetPath = _resolveSheetPath(relations[relation], entries.keys);
        final xml = sheetPath == null ? null : _zipText(entries, sheetPath);
        if (xml == null) {
          throw FormatException('No se pudo leer la hoja «$name».');
        }
        final document = XmlDocument.parse(xml);
        final formulaRanges =
            <({int firstRow, int lastRow, int firstColumn, int lastColumn})>[];
        for (final formula in document.findAllElements('f')) {
          final reference = formula.getAttribute('ref');
          if (reference == null) {
            continue;
          }
          if (formulaRanges.length >= SpreadsheetConfig.maxFormulaRanges) {
            throw const FormatException(
                'Demasiados rangos de fórmulas para una lectura completa segura.');
          }
          final match = RegExp(
                  r'^\$?([A-Z]{1,3})\$?([1-9][0-9]{0,6})(?::\$?([A-Z]{1,3})\$?([1-9][0-9]{0,6}))?$')
              .firstMatch(reference.toUpperCase());
          if (match == null) {
            throw const FormatException(
                'Rango de fórmula inválido; no se suman posibles valores cacheados.');
          }
          final firstColumn = _columnIndex(match.group(1));
          final lastColumn = _columnIndex(match.group(3) ?? match.group(1));
          final firstRow = int.tryParse(match.group(2)!);
          final lastRow = int.tryParse(match.group(4) ?? match.group(2)!);
          if (firstColumn == null ||
              lastColumn == null ||
              firstRow == null ||
              lastRow == null ||
              lastColumn < firstColumn ||
              lastRow < firstRow ||
              lastRow > SpreadsheetConfig.excelMaxRows ||
              lastColumn >= DocumentConfig.maxColumnsPerRow ||
              lastRow - firstRow + 1 > DocumentConfig.maxRowsPerSheet) {
            throw const FormatException(
                'Un rango de fórmula supera los límites de lectura segura.');
          }
          formulaRanges.add((
            firstRow: firstRow,
            lastRow: lastRow,
            firstColumn: firstColumn,
            lastColumn: lastColumn
          ));
        }
        final rows = <SpreadsheetRow>[];
        final seenRows = <int>{};
        for (final row in document.findAllElements('row')) {
          if (seenRows.length >= DocumentConfig.maxRowsPerSheet) {
            throw FormatException(
                '«$name» supera el límite de filas; no se recorta para calcular.');
          }
          final rowReference = row.getAttribute('r');
          final rowNumber = rowReference == null
              ? seenRows.length + 1
              : int.tryParse(rowReference);
          if (rowNumber == null ||
              rowNumber < 1 ||
              rowNumber > SpreadsheetConfig.excelMaxRows ||
              !seenRows.add(rowNumber)) {
            throw FormatException('Coordenadas de fila inválidas en «$name».');
          }
          final cells = <int, SpreadsheetCell>{};
          var nextColumn = 0;
          for (final cell in row.findElements('c')) {
            final reference = cell.getAttribute('r');
            if (reference != null) {
              final coordinate = RegExp(r'^([A-Z]{1,3})([1-9][0-9]{0,6})$')
                  .firstMatch(reference);
              if (coordinate == null ||
                  int.tryParse(coordinate.group(2)!) != rowNumber) {
                throw FormatException(
                    'Coordenadas de celda inválidas en «$name».');
              }
            }
            final column = _columnIndex(reference) ?? nextColumn;
            nextColumn = column + 1;
            if (column >= DocumentConfig.maxColumnsPerRow ||
                cells.containsKey(column)) {
              throw FormatException(
                  'Columnas fuera del límite o duplicadas en «$name».');
            }
            checkCellCount(1);
            final type = cell.getAttribute('t');
            final style = int.tryParse(cell.getAttribute('s') ?? '');
            final formula = cell.findElements('f').isNotEmpty ||
                formulaRanges.any((range) =>
                    rowNumber >= range.firstRow &&
                    rowNumber <= range.lastRow &&
                    column >= range.firstColumn &&
                    column <= range.lastColumn);
            final kind = formula
                ? SpreadsheetCellKind.formula
                : type == 'e'
                    ? SpreadsheetCellKind.error
                    : type == 'b'
                        ? SpreadsheetCellKind.boolean
                        : type == 'd' ||
                                ((type == null || type == 'n') &&
                                    dates.contains(style))
                            ? SpreadsheetCellKind.date
                            : type == null || type == 'n'
                                ? SpreadsheetCellKind.number
                                : SpreadsheetCellKind.text;
            if (type == 's') {
              final raw = cell.findElements('v').firstOrNull?.innerText;
              final index = int.tryParse(raw ?? '');
              if (index == null || index < 0 || index >= shared.length) {
                throw FormatException(
                    'Índice de texto inválido en «$name», fila $rowNumber.');
              }
            }
            final value = _cellValue(cell, shared, dates);
            cells[column] = SpreadsheetCell(
                formula ? '(fórmula no evaluada)' : value, kind);
          }
          if (cells.values.any((c) => c.text.trim().isNotEmpty)) {
            rows.add(SpreadsheetRow(rowNumber, cells));
          }
        }
        sheets.add(SpreadsheetSheet(name, rows));
      }
    } else if (extension == 'xls') {
      // excel2003 mezcla resultados cacheados de fórmulas con números normales.
      // No es posible distinguirlos con su API, así que nunca sumamos BIFF8.
      throw const FormatException(
          'Para calcular, guarda el XLS antiguo como XLSX o CSV. '
          'El lector XLS no distingue las fórmulas de sus valores guardados. '
          'Puedes seguir adjuntando XLS al chat para consultar su texto.');
    } else {
      throw const FormatException('Selecciona XLSX, XLSM, XLS, CSV o TSV.');
    }
    if (sheets.map((s) => s.name).toSet().length != sheets.length) {
      throw const FormatException(
          'El libro tiene nombres de hojas duplicados.');
    }
    if (!sheets.any((s) => s.rows.isNotEmpty)) {
      throw const FormatException('El archivo no contiene filas de datos.');
    }
    return SpreadsheetData(path.split(RegExp(r'[/\\]')).last, size, sheets,
        warnings: warnings);
  }

  static Future<DocumentAttachment> _extractInWorker(
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
      return failure('Formato no admitido. Usa $supportedFormatsLabel.');
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
      String? completeText;
      // Caracteres del documento completo, antes de repartir el presupuesto
      // entre sus hojas.
      int? fullChars;
      switch (extension) {
        case 'pdf':
          text = _extractPdf(bytes);
          break;
        case 'xlsx':
        case 'xlsm':
          {
            final sheets = _readXlsxSheets(bytes);
            text = _renderSheetTexts(sheets, maxCharsPerDocument);
            completeText =
                _renderSheetTexts(sheets, DocumentConfig.maxExtractedChars);
            fullChars = _sheetChars(sheets);
            break;
          }
        case 'xls':
          {
            // Muchos "Excel" con extensión .xls son en realidad .xlsx
            // renombrados: se leen con el mismo lector que los .xlsx.
            final sheets = _looksLikeZip(bytes)
                ? _readXlsxSheets(bytes)
                : _readXlsSheets(bytes);
            text = _renderSheetTexts(sheets, maxCharsPerDocument);
            completeText =
                _renderSheetTexts(sheets, DocumentConfig.maxExtractedChars);
            fullChars = _sheetChars(sheets);
            break;
          }
        case 'docx':
          text = _extractDocx(bytes);
          break;
        case 'pptx':
          text = _extractPptx(bytes);
          break;
        case 'html':
        case 'htm':
          text = _extractHtml(bytes);
          break;
        case 'xml':
          text = _extractXml(bytes);
          break;
        case 'csv':
          text = _formatDelimited(_decodeText(bytes), ',');
          break;
        case 'tsv':
          text = _formatDelimited(_decodeText(bytes), '\t');
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
              : extension == 'pptx'
                  ? 'Las diapositivas solo contienen imágenes o no tienen texto.'
                  : 'El documento está vacío o no contiene texto legible.',
        );
      }

      final fullText = _normalize(completeText ?? text);
      final originalChars =
          math.max(fullChars ?? fullText.length, fullText.length);
      final oversized = text.length > maxCharsPerDocument;
      return DocumentAttachment(
        path: path,
        name: name,
        kind: kind,
        sizeBytes: sizeBytes,
        text: oversized ? truncateAtLineBreak(text, maxCharsPerDocument) : text,
        originalChars: originalChars,
        truncated: oversized || originalChars > text.length,
        extractedText: fullText.length > DocumentConfig.maxExtractedChars
            ? truncateAtLineBreak(fullText, DocumentConfig.maxExtractedChars)
            : fullText,
        extractionTruncated:
            fullText.length > DocumentConfig.maxExtractedChars ||
                fullText.contains('[Hoja recortada:') ||
                fullText.contains('[Tabla recortada:') ||
                fullText.contains('[Columnas omitidas:'),
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

  /// Longitud exacta del bloque que producirá [buildAttachmentContext].
  static int contextCharsFor(
    List<DocumentAttachment> documents, {
    int maxChars = maxTotalChars,
  }) =>
      buildAttachmentContext(documents, maxChars: maxChars).length;

  /// Incluye tanto el recorte previo como el realizado para esta petición.
  static bool isContextTruncated(
    List<DocumentAttachment> documents, {
    int maxChars = maxTotalChars,
  }) {
    final ready = documents.where((document) => document.isReady).toList();
    if (ready.any(
        (document) => document.truncated || document.extractionTruncated)) {
      return true;
    }
    return _documentSlices(ready, maxChars).any((slice) =>
        slice.text == null || slice.text!.length < slice.document.charCount);
  }

  /// Cabeceras, avisos y fragmentos comparten el mismo presupuesto final.
  static String buildAttachmentContext(
    List<DocumentAttachment> documents, {
    int maxChars = maxTotalChars,
  }) {
    final ready = documents.where((document) => document.isReady).toList();
    if (ready.isEmpty || maxChars <= 0) {
      return '';
    }
    final slices = _documentSlices(ready, maxChars);
    final included = slices.where((slice) => slice.text != null).toList();
    if (included.isEmpty) {
      return '';
    }
    final buffer = StringBuffer('${DocumentConfig.contextPreamble}\n');
    for (var index = 0; index < included.length; index++) {
      final slice = included[index];
      buffer
          .write(_renderDocument(index + 1, slice.document.name, slice.text!));
    }
    final omitted = ready.length - included.length;
    if (omitted > 0) {
      buffer.write(_omissionMarker(omitted));
    }
    return buffer.toString().trimRight();
  }

  static String _renderDocument(int position, String name, String text) =>
      '\n--- Documento $position: $name ---\n$text\n--- Fin de $name ---\n';

  static String _omissionMarker(int count) =>
      '[$count documento(s) omitido(s) por límite de contexto]\n';

  static int _blockOverhead(int position, String name) =>
      _renderDocument(position, name, '').length;

  static List<_DocumentSlice> _documentSlices(
    List<DocumentAttachment> ready,
    int maxChars,
  ) {
    if (ready.isEmpty) {
      return [];
    }
    final available = maxChars - DocumentConfig.contextPreamble.length - 1;
    var included = ready.length;
    // Se reserva también el aviso de omisión antes de repartir los extractos.
    while (included > 0) {
      final overhead = List.generate(
              included, (index) => _blockOverhead(index + 1, ready[index].name))
          .fold(0, (sum, length) => sum + length);
      final notice = included < ready.length
          ? _omissionMarker(ready.length - included).length
          : 0;
      final minimum = ready.take(included).fold(
          0,
          (sum, document) =>
              sum + math.min(_minExcerptChars, document.charCount));
      if (overhead + notice + minimum <= available) {
        break;
      }
      included--;
    }
    if (included == 0) {
      return [for (final document in ready) _DocumentSlice(document, null)];
    }
    final overheads = [
      for (var index = 0; index < included; index++)
        _blockOverhead(index + 1, ready[index].name)
    ];
    final notice = included < ready.length
        ? _omissionMarker(ready.length - included).length
        : 0;
    final grants = _shareBudget(
      [for (final document in ready.take(included)) document.charCount],
      available -
          overheads.fold<int>(0, (sum, length) => sum + length) -
          notice,
    );
    return [
      for (var index = 0; index < included; index++)
        _DocumentSlice(ready[index],
            truncateAtLineBreak(ready[index].text!, grants[index])),
      for (final document in ready.skip(included))
        _DocumentSlice(document, null),
    ];
  }

  /// Reparte [total] entre las [needs] indicadas: primero a partes iguales y
  /// después el sobrante de las que ya estaban saciadas.
  static List<int> _shareBudget(List<int> needs, int total) {
    final grants = List<int>.filled(needs.length, 0);
    if (needs.isEmpty || total <= 0) {
      return grants;
    }

    var remaining = total;
    var pending = [
      for (var index = 0; index < needs.length; index++)
        if (needs[index] > 0) index,
    ];

    while (remaining > 0 && pending.isNotEmpty) {
      final share = remaining ~/ pending.length;
      if (share <= 0) {
        break;
      }

      final next = <int>[];
      for (final index in pending) {
        final missing = needs[index] - grants[index];
        final grant = math.min(share, missing);
        grants[index] += grant;
        remaining -= grant;
        if (grants[index] < needs[index]) {
          next.add(index);
        }
      }
      pending = next;
    }

    return grants;
  }

  // ---------------------------------------------------------------------------
  // PDF
  // ---------------------------------------------------------------------------

  static String _extractPdf(Uint8List bytes) {
    final document = PdfDocument(inputBytes: bytes);
    try {
      final extractor = PdfTextExtractor(document);
      final buffer = StringBuffer();
      for (var page = 0; page < document.pages.count; page++) {
        final text =
            extractor.extractText(startPageIndex: page, endPageIndex: page);
        if (text.trim().isNotEmpty) {
          buffer.writeln('Página ${page + 1}:');
          buffer.writeln(text);
        }
      }
      return buffer.toString();
    } finally {
      document.dispose();
    }
  }

  // ---------------------------------------------------------------------------
  // DOCX / PPTX (ZIP + XML de Office Open XML)
  // ---------------------------------------------------------------------------

  static Map<String, ArchiveFile> _zipEntries(Uint8List bytes) {
    final archive = _decodeOfficeZip(bytes);
    final entries = <String, ArchiveFile>{};
    for (final file in archive.files) {
      if (file.isFile) {
        entries[file.name.replaceAll('\\', '/')] = file;
      }
    }
    return entries;
  }

  /// Valida tamaños declarados antes de que el decodificador descomprima nada.
  static Archive _decodeOfficeZip(Uint8List bytes) {
    final directory = ZipDirectory()..read(InputMemoryStream(bytes));
    if (directory.fileHeaders.length > DocumentConfig.maxZipEntries) {
      throw const FormatException(
          'El documento contiene demasiadas entradas ZIP.');
    }
    var expanded = 0;
    for (final header in directory.fileHeaders) {
      expanded += header.uncompressedSize;
      if (header.uncompressedSize > DocumentConfig.maxZipEntryBytes ||
          expanded > DocumentConfig.maxExpandedZipBytes) {
        throw const FormatException(
            'El documento supera el límite de expansión ZIP.');
      }
      final mode = header.externalFileAttributes >> 16;
      if ((mode & 0xf000) == 0xa000) {
        throw const FormatException(
            'No se permiten enlaces simbólicos en documentos Office.');
      }
    }
    final archive = ZipDecoder().decodeBytes(bytes);
    final bounded = Archive();
    for (final entry in archive.files.where((entry) => entry.isFile)) {
      final output = _BoundedZipOutput(entry.size);
      entry.decompress(output);
      if (output.length != entry.size) {
        throw const FormatException(
            'El tamaño descomprimido no coincide con el ZIP.');
      }
      bounded.add(ArchiveFile(entry.name, output.length, output.getBytes()));
    }
    return bounded;
  }

  static String? _zipText(Map<String, ArchiveFile> entries, String path) {
    final content = entries[path]?.readBytes();
    if (content == null) {
      return null;
    }
    return utf8.decode(content, allowMalformed: true);
  }

  /// Elementos por nombre local: OOXML usa prefijos (`w:p`, `a:p`) y
  /// `findAllElements('p')` no los encontraría.
  static Iterable<XmlElement> _elementsNamed(
    XmlElement element,
    String localName,
  ) {
    return element.descendants
        .whereType<XmlElement>()
        .where((child) => child.name.local == localName);
  }

  static String _extractDocx(Uint8List bytes) {
    final entries = _zipEntries(bytes);
    final xml = _zipText(entries, 'word/document.xml');
    if (xml == null) {
      throw const FormatException(
        'El archivo no parece un documento Word válido.',
      );
    }

    final document = XmlDocument.parse(xml);
    final bodies = _elementsNamed(document.rootElement, 'body');
    final body = bodies.isEmpty ? document.rootElement : bodies.first;
    final buffer = StringBuffer();
    _writeDocxBlocks(body, buffer);
    return buffer.toString();
  }

  static void _writeDocxBlocks(XmlElement element, StringBuffer buffer) {
    for (final child in element.children.whereType<XmlElement>()) {
      switch (child.name.local) {
        case 'p':
          final line = StringBuffer();
          _writeDocxInline(child, line);
          final text = line.toString().trim();
          if (text.isNotEmpty) {
            buffer.writeln(text);
          }
          break;
        case 'tbl':
          for (final row in _elementsNamed(child, 'tr')) {
            final cells = <String>[];
            for (final cell in _elementsNamed(row, 'tc')) {
              final value = _elementsNamed(cell, 't')
                  .map((text) => text.innerText)
                  .join(' ')
                  .replaceAll(RegExp(r'\s+'), ' ')
                  .trim();
              if (value.isNotEmpty) {
                cells.add(value);
              }
            }
            if (cells.isNotEmpty) {
              buffer.writeln(cells.join(' | '));
            }
          }
          break;
        default:
          _writeDocxBlocks(child, buffer);
      }
    }
  }

  static void _writeDocxInline(XmlNode node, StringBuffer buffer) {
    for (final child in node.children) {
      if (child is! XmlElement) continue;
      switch (child.name.local) {
        case 't':
          buffer.write(child.innerText);
          break;
        case 'tab':
          buffer.write('\t');
          break;
        case 'br':
        case 'cr':
          buffer.write('\n');
          break;
        case 'delText':
        case 'instrText':
          // Texto tachado o instrucciones de campo: no forma parte del texto.
          break;
        default:
          _writeDocxInline(child, buffer);
      }
    }
  }

  static final RegExp _slidePathPattern =
      RegExp(r'^ppt/slides/slide(\d+)\.xml$');

  static String _extractPptx(Uint8List bytes) {
    final entries = _zipEntries(bytes);
    final slides = entries.keys
        .where((path) => _slidePathPattern.hasMatch(path))
        .toList()
      ..sort((first, second) {
        final firstNumber =
            int.tryParse(_slidePathPattern.firstMatch(first)!.group(1)!) ?? 0;
        final secondNumber =
            int.tryParse(_slidePathPattern.firstMatch(second)!.group(1)!) ?? 0;
        return firstNumber.compareTo(secondNumber);
      });

    if (slides.isEmpty) {
      throw const FormatException(
        'El archivo no parece una presentación PowerPoint válida.',
      );
    }

    final buffer = StringBuffer();
    var slideNumber = 0;
    for (final slidePath in slides) {
      final xml = _zipText(entries, slidePath);
      if (xml == null) continue;

      final document = XmlDocument.parse(xml);
      final lines = <String>[];
      for (final paragraph in _elementsNamed(document.rootElement, 'p')) {
        final text = _elementsNamed(paragraph, 't')
            .map((element) => element.innerText)
            .join()
            .trim();
        if (text.isNotEmpty) {
          lines.add(text);
        }
      }

      if (lines.isEmpty) continue;
      slideNumber++;
      buffer.writeln('Diapositiva $slideNumber:');
      for (final line in lines) {
        buffer.writeln(line);
      }
      buffer.writeln();
    }
    return buffer.toString();
  }

  // ---------------------------------------------------------------------------
  // HTML / XML
  // ---------------------------------------------------------------------------

  static const Set<String> _htmlBlockTags = {
    'address',
    'article',
    'aside',
    'blockquote',
    'dd',
    'div',
    'dl',
    'dt',
    'figcaption',
    'figure',
    'footer',
    'form',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'header',
    'hr',
    'li',
    'main',
    'nav',
    'ol',
    'p',
    'pre',
    'section',
    'table',
    'tr',
    'ul',
  };

  static String _extractHtml(Uint8List bytes) {
    final document = html_parser.parse(_decodeText(bytes));
    for (final element
        in document.querySelectorAll('script, style, noscript, head, svg')) {
      element.remove();
    }

    final buffer = StringBuffer();
    final root = document.body ?? document.documentElement;
    if (root != null) {
      _writeHtml(root, buffer);
    }
    return buffer.toString();
  }

  static void _writeHtml(dom.Node node, StringBuffer buffer) {
    if (node is dom.Text) {
      final text = node.text.replaceAll(RegExp(r'\s+'), ' ');
      if (text.trim().isNotEmpty) {
        buffer.write(text);
      }
      return;
    }
    if (node is! dom.Element) return;

    final tag = node.localName ?? '';
    if (tag == 'br') {
      buffer.write('\n');
      return;
    }

    final isBlock = _htmlBlockTags.contains(tag);
    if (isBlock) buffer.write('\n');
    if (tag == 'li') buffer.write('• ');

    for (final child in node.nodes) {
      _writeHtml(child, buffer);
    }

    if (tag == 'td' || tag == 'th') buffer.write(' | ');
    if (isBlock) buffer.write('\n');
  }

  static String _extractXml(Uint8List bytes) {
    var text = _decodeText(bytes);
    text = text
        .replaceAll(RegExp(r'<!--[\s\S]*?-->'), ' ')
        .replaceAll(RegExp(r'<\?[\s\S]*?\?>'), ' ')
        .replaceAll(
          RegExp(r'<(script|style)[\s\S]*?</\1>', caseSensitive: false),
          ' ',
        )
        .replaceAll(RegExp(r'<[^>]*>'), '\n');
    return _decodeXmlEntities(text);
  }

  static String _decodeXmlEntities(String text) {
    return text.replaceAllMapped(
      RegExp(r'&(#x?[0-9a-fA-F]+|[a-zA-Z]+);'),
      (match) {
        final entity = match.group(1)!;
        if (entity.startsWith('#x') || entity.startsWith('#X')) {
          final code = int.tryParse(entity.substring(2), radix: 16);
          return code == null ? match.group(0)! : String.fromCharCode(code);
        }
        if (entity.startsWith('#')) {
          final code = int.tryParse(entity.substring(1));
          return code == null ? match.group(0)! : String.fromCharCode(code);
        }
        return switch (entity) {
          'amp' => '&',
          'lt' => '<',
          'gt' => '>',
          'quot' => '"',
          'apos' => "'",
          'nbsp' => ' ',
          _ => match.group(0)!,
        };
      },
    );
  }

  // ---------------------------------------------------------------------------
  // CSV / TSV
  // ---------------------------------------------------------------------------

  /// Presenta CSV y TSV como filas (`Fila 2: Ana | 12`), igual que un XLSX,
  /// en lugar de una línea larga de separadores.
  static String _formatDelimited(String text, String delimiter) {
    final rows = _splitDelimitedRows(text, delimiter);
    if (rows.isEmpty) return text;

    final buffer = StringBuffer();
    for (var index = 0; index < rows.length; index++) {
      if (index >= maxRowsPerSheet) {
        buffer.writeln('[Tabla recortada: máximo de $maxRowsPerSheet filas]');
        break;
      }
      final cells = rows[index]
          .map((cell) => cell.trim())
          .take(maxColumnsPerRow)
          .toList();
      if (cells.every((cell) => cell.isEmpty)) continue;
      buffer.writeln('Fila ${index + 1}: ${cells.join(' | ')}');
      if (rows[index].length > maxColumnsPerRow) {
        buffer.writeln(
            '[Columnas omitidas: ${rows[index].length - maxColumnsPerRow} en la fila ${index + 1}]');
      }
    }
    return buffer.toString();
  }

  /// Divide CSV/TSV respetando las comillas dobles y los saltos entre comillas.
  static List<List<String>> _splitDelimitedRows(
    String text,
    String delimiter, {
    bool bounded = false,
  }) {
    final rows = <List<String>>[];
    var row = <String>[];
    final cell = StringBuffer();
    var inQuotes = false;
    final separator = delimiter.codeUnitAt(0);

    void endRow() {
      if (bounded &&
          (rows.length >= DocumentConfig.maxRowsPerSheet ||
              row.length >= DocumentConfig.maxColumnsPerRow)) {
        throw const FormatException(
            'La tabla supera los límites de filas o columnas; no se calculará un total parcial.');
      }
      row.add(cell.toString());
      rows.add(row);
      row = <String>[];
      cell.clear();
    }

    for (var index = 0; index < text.length; index++) {
      final unit = text.codeUnitAt(index);
      if (inQuotes) {
        if (unit == 34) {
          final isEscapedQuote =
              index + 1 < text.length && text.codeUnitAt(index + 1) == 34;
          if (isEscapedQuote) {
            cell.write('"');
            index++;
          } else {
            inQuotes = false;
          }
        } else {
          cell.writeCharCode(unit);
        }
        continue;
      }

      if (unit == 34) {
        inQuotes = true;
      } else if (unit == separator) {
        if (bounded && row.length >= DocumentConfig.maxColumnsPerRow - 1) {
          throw const FormatException('La tabla supera el límite de columnas.');
        }
        row.add(cell.toString());
        cell.clear();
      } else if (unit == 10) {
        endRow();
      } else if (unit != 13) {
        cell.writeCharCode(unit);
      }
    }

    if (bounded && inQuotes) {
      throw const FormatException('La tabla tiene comillas sin cerrar.');
    }
    if (cell.isNotEmpty || row.isNotEmpty) {
      endRow();
    }
    return rows;
  }

  // ---------------------------------------------------------------------------
  // Hojas de cálculo (XLSX por ZIP + XML, XLS por BIFF8)
  // ---------------------------------------------------------------------------

  /// Texto de una hoja ya formateado en filas (`Fila 2: Ana | 12`).
  static List<_SheetText> _readXlsxSheets(Uint8List bytes) {
    final archive = _decodeOfficeZip(bytes);
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

    final sheets = <_SheetText>[];
    for (final sheet in workbook.findAllElements('sheet')) {
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
      sheets.add(_SheetText(sheetName, rows));
    }

    return sheets;
  }

  /// Texto de un libro .xls (Excel 97-2003, BIFF8).
  static List<_SheetText> _readXlsSheets(Uint8List bytes) {
    try {
      final reader = XlsReader.fromBytes(bytes);
      final sheets = <_SheetText>[];

      for (var index = 0; index < reader.sheetCount; index++) {
        final sheet = reader.sheet(index);
        final rowsByIndex = <int, Map<int, String>>{};
        for (final cell in sheet.cells) {
          final value = _xlsCellText(cell.value);
          if (value.isEmpty) {
            continue;
          }
          rowsByIndex.putIfAbsent(cell.row, () => {})[cell.col] = value;
        }
        if (rowsByIndex.isEmpty) {
          continue;
        }

        final rowNumbers = rowsByIndex.keys.toList()..sort();
        final rows = <String>[];
        for (final rowNumber in rowNumbers) {
          if (rows.length >= maxRowsPerSheet) {
            rows.add('[Hoja recortada: máximo de $maxRowsPerSheet filas]');
            break;
          }

          final cells = rowsByIndex[rowNumber]!;
          final maxColumn = math.min(
            cells.keys.reduce(math.max),
            maxColumnsPerRow - 1,
          );
          final values = List<String>.generate(
            maxColumn + 1,
            (column) => cells[column] ?? '',
          );
          if (values.every((value) => value.isEmpty)) {
            continue;
          }
          rows.add('Fila ${rowNumber + 1}: ${values.join(' | ')}');
          if (cells.keys.any((column) => column >= maxColumnsPerRow)) {
            rows.add(
                '[Columnas omitidas: a partir de la columna ${maxColumnsPerRow + 1} en la fila ${rowNumber + 1}]');
          }
        }

        if (rows.isNotEmpty) {
          sheets.add(_SheetText(sheet.name, rows));
        }
      }

      return sheets;
    } on FormatException {
      rethrow;
    } catch (error) {
      throw FormatException(
        'El archivo no parece un libro de Excel 97-2003 válido ($error).',
      );
    }
  }

  /// Valor de una celda .xls como texto legible.
  static String _xlsCellText(Object? value) {
    if (value == null) {
      return '';
    }
    if (value is DateTime) {
      final day = value.day.toString().padLeft(2, '0');
      final month = value.month.toString().padLeft(2, '0');
      final date = '$day/$month/${value.year}';
      if (value.hour == 0 && value.minute == 0 && value.second == 0) {
        return date;
      }
      final hour = value.hour.toString().padLeft(2, '0');
      final minute = value.minute.toString().padLeft(2, '0');
      return '$date $hour:$minute';
    }
    if (value is double) {
      if (value.isFinite && value == value.roundToDouble()) {
        return value.toInt().toString();
      }
      return value.toString();
    }
    if (value is bool) {
      return value ? 'verdadero' : 'falso';
    }
    return value.toString().trim();
  }

  /// Caracteres que ocupa el texto completo de todas las hojas.
  static int _sheetChars(List<_SheetText> sheets) {
    var total = 0;
    for (final sheet in sheets) {
      total += sheet.chars;
    }
    return total;
  }

  /// Vuelca las hojas repartiendo [maxChars] entre todas, de modo que ninguna
  /// desaparezca: cada una aporta su cabecera, sus primeras filas y una marca
  /// con cuántas quedaron fuera.
  static String _renderSheetTexts(List<_SheetText> sheets, int maxChars) {
    if (sheets.isEmpty) {
      return '';
    }

    final headerLengths = [
      for (final sheet in sheets) 'Hoja "${sheet.name}":'.length + 2,
    ];
    final grants = _shareBudget(
      [
        for (var index = 0; index < sheets.length; index++)
          sheets[index].chars + headerLengths[index],
      ],
      maxChars,
    );

    final buffer = StringBuffer();
    for (var index = 0; index < sheets.length; index++) {
      final sheet = sheets[index];
      if (buffer.isNotEmpty) {
        buffer.writeln();
      }
      buffer.writeln('Hoja "${sheet.name}":');

      var available = grants[index] - headerLengths[index];
      var written = 0;
      for (final row in sheet.rows) {
        if (available <= 0) {
          break;
        }
        if (row.length + 1 > available) {
          if (written == 0) {
            buffer.writeln(truncateAtLineBreak(row, available));
            written = 1;
          }
          break;
        }
        buffer.writeln(row);
        available -= row.length + 1;
        written++;
      }

      if (written < sheet.rows.length) {
        buffer.writeln(
          '[Hoja recortada: se muestran $written de ${sheet.rows.length} filas]',
        );
      }
    }

    return buffer.toString();
  }

  static bool _looksLikeZip(Uint8List bytes) =>
      bytes.length >= 4 && bytes[0] == 0x50 && bytes[1] == 0x4B;

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
      if (cells.keys.any((column) => column >= maxColumnsPerRow)) {
        rows.add(
            '[Columnas omitidas: a partir de la columna ${maxColumnsPerRow + 1} en la fila $rowIndex]');
      }
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
        .replaceAll(RegExp(r'[ ]+\n'), '\n')
        .replaceAll(RegExp(r'\n[ ]+'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }
}

/// Documento con el texto que finalmente ocupa el presupuesto de contexto.
class _DocumentSlice {
  final DocumentAttachment document;

  /// Texto recortado que se envía, o `null` si el documento queda fuera.
  final String? text;

  const _DocumentSlice(this.document, this.text);
}

/// Hoja de cálculo ya convertida a filas de texto.
class _SheetText {
  final String name;
  final List<String> rows;

  const _SheetText(this.name, this.rows);

  /// Caracteres del texto de la hoja, contando el salto de línea de cada fila.
  int get chars {
    var total = 0;
    for (final row in rows) {
      total += row.length + 1;
    }
    return total;
  }
}

/// Impide que una cabecera ZIP falsificada eluda el límite al expandirse.
class _BoundedZipOutput extends OutputMemoryStream {
  final int limit;
  _BoundedZipOutput(this.limit)
      : super(size: math.min(limit, OutputMemoryStream.defaultBufferSize));

  void _check(int additional) {
    if (additional < 0 || length + additional > limit) {
      throw const FormatException(
          'El contenido ZIP excede el tamaño declarado.');
    }
  }

  @override
  void writeByte(int value) {
    _check(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    _check(length ?? bytes.length);
    super.writeBytes(bytes, length: length);
  }

  @override
  void writeStream(InputStream stream) {
    _check(stream.length);
    super.writeStream(stream);
  }

  @override
  void writeBackReference(int distance, int count) {
    _check(count);
    super.writeBackReference(distance, count);
  }
}
