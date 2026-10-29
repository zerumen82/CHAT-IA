import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:archive/archive.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:xml/xml.dart';

import '../config/export_config.dart';
import '../models/export_format.dart';
import '../models/message.dart';

/// Generadores de archivos auténticos, sin ejecutar código ni fórmulas del LLM.
class ExportService {
  ExportService._();

  static Future<Uint8List> encode({
    required ExportFormat format,
    required String title,
    required String markdown,
    List<Map<String, dynamic>>? sheets,
  }) async {
    if (format == ExportFormat.pdf) {
      _validateRequest(format, title, markdown);
      final blocks = _parse(_withTitle(title, markdown));
      return _checkFileSize(await _pdf(blocks, title));
    }
    // Markdown, XML y compresión ZIP pueden consumir trabajo considerable.
    // El isolate recibe solo contenido/argumentos, nunca UI ni servicios.
    return Isolate.run(() => _encodeSync(format, title, markdown, sheets));
  }

  static void _validateRequest(
      ExportFormat format, String title, String markdown) {
    if (title.trim().isEmpty || title.length > ExportConfig.maxTitleChars) {
      throw const FormatException('El título está vacío o es demasiado largo.');
    }
    if (markdown.length > ExportConfig.maxContentChars) {
      throw const FormatException(
          'El contenido supera el límite de exportación.');
    }
    _validateText(title);
    _validateText(markdown);
    if (format != ExportFormat.xlsx && markdown.trim().isEmpty) {
      throw const FormatException('No hay contenido para crear el archivo.');
    }
  }

  static Uint8List _encodeSync(ExportFormat format, String title,
      String markdown, List<Map<String, dynamic>>? sheets) {
    _validateRequest(format, title, markdown);
    final content = _withTitle(title, markdown);
    final blocks =
        format == ExportFormat.markdown || format == ExportFormat.xlsx
            ? <_Block>[]
            : _parse(content);
    final Uint8List bytes;
    switch (format) {
      case ExportFormat.txt:
        bytes = Uint8List.fromList(utf8.encode(_plainText(blocks)));
      case ExportFormat.markdown:
        bytes = Uint8List.fromList(utf8.encode(content));
      case ExportFormat.pdf:
        throw StateError('La generación PDF usa el renderizador principal.');
      case ExportFormat.docx:
        bytes = _docx(blocks, title);
      case ExportFormat.xlsx:
        bytes = _xlsx(sheets, title);
    }
    return _checkFileSize(bytes);
  }

  static Uint8List _checkFileSize(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > ExportConfig.maxFileBytes) {
      throw const FormatException('El archivo supera el tamaño permitido.');
    }
    return bytes;
  }

  /// Exporta todo lo conservado, sin incrustar adjuntos ni rutas privadas.
  static String conversationMarkdown(List<Message> messages, String title) {
    final buffer = StringBuffer('# ${_oneLine(title)}\n\n');
    buffer.writeln(
      '> Incluye los mensajes conservados. Los turnos eliminados o podados '
      'anteriormente no se pueden recuperar.\n',
    );
    for (final message in messages) {
      final role = message.isUser ? 'Usuario' : 'Asistente';
      buffer.writeln('## $role · ${message.timestamp.toIso8601String()}');
      if (!message.isUser && message.model?.isNotEmpty == true) {
        buffer.writeln('\nModelo: ${_oneLine(message.model!)}');
      }
      if (message.isError) buffer.writeln('\n[Error de la conversación]');
      buffer.writeln('\n${message.text}\n');
      final documents = message.documents;
      if (documents != null && documents.isNotEmpty) {
        buffer.writeln(
            'Documentos: ${documents.map((d) => _oneLine(d.name)).join(', ')}\n');
      }
      if (message.hasImages) {
        buffer.writeln(
            '[${message.images!.length} imagen(es) adjunta(s), no incluidas]\n');
      }
      if (message.generatedFiles.isNotEmpty) {
        final names = message.generatedFiles
            .map((file) =>
                '${_oneLine(file.name)} (${file.format.extension.toUpperCase()})')
            .join(', ');
        buffer.writeln('Archivos generados: $names\n');
      }
    }
    return buffer.toString();
  }

  static String _oneLine(String text) =>
      text.replaceAll(RegExp(r'[\r\n]+'), ' ');

  static String _withTitle(String title, String markdown) {
    final heading = '# ${_oneLine(title)}';
    return markdown.trimLeft().startsWith('$heading\n') ||
            markdown.trim() == heading
        ? markdown
        : '$heading\n\n$markdown';
  }

  static void _validateText(String text) {
    for (final rune in text.runes) {
      if ((rune < 32 && rune != 9 && rune != 10 && rune != 13) ||
          rune == 0xfffe ||
          rune == 0xffff) {
        throw const FormatException(
            'El contenido contiene caracteres de control no válidos.');
      }
    }
  }

  static List<_Block> _parse(String source) {
    final document = md.Document(
        extensionSet: md.ExtensionSet.gitHubFlavored, encodeHtml: false);
    final nodes =
        document.parseLines(source.replaceAll('\r\n', '\n').split('\n'));
    final result = <_Block>[];
    void visit(md.Node node, {String? prefix, int level = 0}) {
      if (node is md.Text) {
        if (node.text.trim().isNotEmpty) result.add(_Block('p', node.text));
        return;
      }
      final element = node as md.Element;
      if (element.tag == 'table') {
        final rows = <List<String>>[];
        void rowVisit(md.Node current) {
          if (current is! md.Element) {
            return;
          }
          if (current.tag == 'tr') {
            rows.add((current.children ?? [])
                .whereType<md.Element>()
                .map((cell) => cell.textContent)
                .toList());
          } else {
            for (final child in current.children ?? <md.Node>[]) {
              rowVisit(child);
            }
          }
        }

        rowVisit(element);
        result.add(_Block('table', '', rows: rows));
      } else if (element.tag == 'ul' || element.tag == 'ol') {
        var index = int.tryParse(element.attributes['start'] ?? '') ?? 1;
        for (final child in element.children ?? <md.Node>[]) {
          visit(child,
              prefix: element.tag == 'ol' ? '${index++}.' : '•', level: level);
        }
      } else if (element.tag == 'li') {
        final children = element.children ?? <md.Node>[];
        final nested = children
            .whereType<md.Element>()
            .where((child) => child.tag == 'ul' || child.tag == 'ol')
            .toSet();
        final text = children
            .where((child) => !nested.contains(child))
            .map((child) => child.textContent)
            .join(' ')
            .trim();
        result.add(_Block('list', text, prefix: prefix ?? '•', level: level));
        for (final child in nested) {
          visit(child, level: level + 1);
        }
      } else if (element.tag == 'blockquote') {
        result.add(_Block('quote', element.textContent));
      } else if (element.tag == 'pre') {
        result.add(_Block('code', element.textContent.trimRight()));
      } else if (element.tag == 'hr') {
        result.add(const _Block('p', '────────────────────'));
      } else {
        result.add(_Block(element.tag, element.textContent));
      }
    }

    for (final node in nodes) {
      visit(node);
    }
    return result;
  }

  static String _plainText(List<_Block> blocks) => '${blocks.map((block) {
        if (block.kind == 'table') {
          return block.rows.map((row) => row.join(' | ')).join('\n');
        }
        return block.kind == 'list'
            ? '${'  ' * block.level}${block.prefix} ${block.text}'
            : block.text;
      }).join('\n\n')}\n';

  static Future<Uint8List> _pdf(List<_Block> blocks, String title) async {
    final text = _plainText(blocks);
    final fontBytes = await _resolveFont(text);
    final document = PdfDocument();
    document.documentInformation.title = title;
    document.pageSettings.margins.all = ExportConfig.pageMargin;
    var page = document.pages.add();
    var y = 0.0;
    final width = page.getClientSize().width;
    final fonts = <String, PdfFont>{};
    PdfFont font(double size, {bool bold = false}) => fonts.putIfAbsent(
          '$size/$bold',
          () => PdfTrueTypeFont(fontBytes, size,
              style: bold ? PdfFontStyle.bold : PdfFontStyle.regular),
        );
    try {
      for (final block in blocks) {
        if (y > page.getClientSize().height - ExportConfig.bodyFontSize * 3) {
          page = document.pages.add();
          y = 0;
        }
        PdfLayoutResult? result;
        if (block.kind == 'table' &&
            block.rows.isNotEmpty &&
            block.rows.first.length <= ExportConfig.maxPdfTableColumns) {
          final grid = PdfGrid();
          final columnCount =
              block.rows.map((row) => row.length).reduce(math.max);
          grid.columns.add(count: columnCount);
          grid.style.font = font(ExportConfig.codeFontSize);
          grid.style.cellPadding = PdfPaddings(
            left: ExportConfig.cellPadding,
            right: ExportConfig.cellPadding,
            top: ExportConfig.cellPadding,
            bottom: ExportConfig.cellPadding,
          );
          final headers = grid.headers.add(1);
          for (var column = 0; column < columnCount; column++) {
            headers[0].cells[column].value = column < block.rows.first.length
                ? block.rows.first[column]
                : '';
          }
          headers[0].style.font = font(ExportConfig.codeFontSize, bold: true);
          for (final values in block.rows.skip(1)) {
            final row = grid.rows.add();
            for (var column = 0; column < columnCount; column++) {
              row.cells[column].value =
                  column < values.length ? values[column] : '';
            }
          }
          result = grid.draw(
              page: page,
              bounds: Rect.fromLTWH(0, y, width, 0),
              format: PdfLayoutFormat(layoutType: PdfLayoutType.paginate));
        } else {
          final heading = RegExp(r'^h([1-6])$').firstMatch(block.kind);
          final size = heading != null
              ? ExportConfig.bodyFontSize +
                  (7 - int.parse(heading.group(1)!)) * 1.5
              : block.kind == 'code'
                  ? ExportConfig.codeFontSize
                  : ExportConfig.bodyFontSize;
          final content = block.kind == 'table'
              ? block.rows.map((row) => row.join(' | ')).join('\n')
              : block.kind == 'list'
                  ? '${'  ' * block.level}${block.prefix} ${block.text}'
                  : block.text;
          if (content.isEmpty) {
            continue;
          }
          result = PdfTextElement(
                  text: content,
                  font: font(size, bold: heading != null),
                  brush: PdfBrushes.black)
              .draw(
            page: page,
            bounds: Rect.fromLTWH(0, y, width, 0),
            format: PdfLayoutFormat(layoutType: PdfLayoutType.paginate),
          );
        }
        if (result != null) {
          page = result.page;
          y = result.bounds.bottom + ExportConfig.blockSpacing;
        }
      }
      return Uint8List.fromList(await document.save());
    } finally {
      document.dispose();
    }
  }

  static Future<Uint8List> _resolveFont(String text) async {
    final errors = <String>[];
    for (final path in ExportConfig.pdfFontCandidates) {
      final file = File(path);
      if (!await file.exists()) {
        continue;
      }
      try {
        final bytes = await file.readAsBytes();
        if (_TrueTypeCoverage(bytes).covers(text)) {
          return bytes;
        }
        errors.add(
            'La fuente ${file.uri.pathSegments.last} no cubre todos los caracteres.');
      } on FormatException catch (error) {
        errors.add(error.message);
      }
    }
    throw FormatException(
        'No hay una fuente Unicode local apta para este PDF. Configura LIGHTCHAT_PDF_FONT con una fuente TrueType compatible. ${errors.join(' ')}');
  }

  static Uint8List _docx(List<_Block> blocks, String title) {
    final builder = XmlBuilder();
    builder.processing(
        'xml', 'version="1.0" encoding="UTF-8" standalone="yes"');
    builder.element('w:document', namespaceUris: {'w': _wordNs}, nest: () {
      builder.element('w:body', nest: () {
        for (final block in blocks) {
          if (block.kind == 'table') {
            builder.element('w:tbl', nest: () {
              builder.element('w:tblPr', nest: () {
                builder
                    .element('w:tblStyle', attributes: {'w:val': 'TableGrid'});
                builder.element('w:tblW',
                    attributes: {'w:w': '0', 'w:type': 'auto'});
              });
              builder.element('w:tblGrid', nest: () {
                final columns =
                    block.rows.map((row) => row.length).fold<int>(0, math.max);
                final width = (ExportConfig.wordPageWidthTwips -
                        2 * ExportConfig.wordMarginTwips) ~/
                    math.max(columns, 1);
                for (var column = 0; column < columns; column++) {
                  builder.element('w:gridCol', attributes: {'w:w': '$width'});
                }
              });
              for (final row in block.rows) {
                builder.element('w:tr', nest: () {
                  for (final cell in row) {
                    builder.element('w:tc',
                        nest: () => _wordParagraph(builder, _Block('p', cell)));
                  }
                });
              }
            });
          } else {
            _wordParagraph(builder, block);
          }
        }
        builder.element('w:sectPr', nest: () {
          builder.element('w:pgSz', attributes: {
            'w:w': '${ExportConfig.wordPageWidthTwips}',
            'w:h': '${ExportConfig.wordPageHeightTwips}'
          });
          builder.element('w:pgMar', attributes: {
            'w:top': '${ExportConfig.wordMarginTwips}',
            'w:right': '${ExportConfig.wordMarginTwips}',
            'w:bottom': '${ExportConfig.wordMarginTwips}',
            'w:left': '${ExportConfig.wordMarginTwips}'
          });
        });
      });
    });
    final archive = Archive();
    _addXml(
        archive,
        '[Content_Types].xml',
        _contentTypes({
          '/word/document.xml':
              'application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml',
          '/word/styles.xml':
              'application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml',
          '/word/numbering.xml':
              'application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml',
          '/docProps/core.xml':
              'application/vnd.openxmlformats-package.core-properties+xml',
        }));
    _addXml(
        archive,
        '_rels/.rels',
        _relationships([
          {
            'Id': 'rId1',
            'Type': '$_officeRel/officeDocument',
            'Target': 'word/document.xml'
          },
          {
            'Id': 'rId2',
            'Type':
                'http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties',
            'Target': 'docProps/core.xml'
          },
        ]));
    _addXml(
        archive, 'word/document.xml', builder.buildDocument().toXmlString());
    _addXml(
        archive,
        'word/_rels/document.xml.rels',
        _relationships([
          {'Id': 'rId1', 'Type': '$_officeRel/styles', 'Target': 'styles.xml'},
          {
            'Id': 'rId2',
            'Type': '$_officeRel/numbering',
            'Target': 'numbering.xml'
          },
        ]));
    _addXml(archive, 'word/styles.xml', _wordStyles());
    _addXml(archive, 'word/numbering.xml', _wordNumbering());
    _addXml(archive, 'docProps/core.xml', _coreProperties(title));
    return ZipEncoder().encodeBytes(archive);
  }

  static void _wordParagraph(XmlBuilder builder, _Block block) {
    builder.element('w:p', nest: () {
      builder.element('w:pPr', nest: () {
        final heading = RegExp(r'^h([1-6])$').firstMatch(block.kind);
        final style = heading != null
            ? 'Heading${heading.group(1)}'
            : block.kind == 'code'
                ? 'Code'
                : block.kind == 'quote'
                    ? 'Quote'
                    : 'Normal';
        builder.element('w:pStyle', attributes: {'w:val': style});
        if (block.kind == 'list') {
          builder.element('w:numPr', nest: () {
            builder.element('w:ilvl', attributes: {
              'w:val': math
                  .min(block.level, ExportConfig.maxWordListLevels - 1)
                  .toString()
            });
            builder.element('w:numId',
                attributes: {'w:val': block.prefix == '•' ? '1' : '2'});
          });
        }
      });
      builder.element('w:r', nest: () {
        final lines = block.text.split('\n');
        for (var index = 0; index < lines.length; index++) {
          if (index > 0) {
            builder.element('w:br');
          }
          builder.element('w:t',
              attributes: {'xml:space': 'preserve'}, nest: lines[index]);
        }
      });
    });
  }

  static String _wordStyles() {
    final builder = XmlBuilder();
    builder.element('w:styles', namespaceUris: {'w': _wordNs}, nest: () {
      void style(String id, String name,
          {bool bold = false, int size = 22, String? font, String? color}) {
        builder.element('w:style',
            attributes: {'w:type': 'paragraph', 'w:styleId': id}, nest: () {
          builder.element('w:name', attributes: {'w:val': name});
          if (id != 'Normal') {
            builder.element('w:basedOn', attributes: {'w:val': 'Normal'});
          }
          builder.element('w:pPr',
              nest: () => builder.element('w:spacing', attributes: {
                    'w:after': '${ExportConfig.wordParagraphSpacingTwips}'
                  }));
          builder.element('w:rPr', nest: () {
            if (bold) {
              builder.element('w:b');
            }
            if (font != null) {
              builder.element('w:rFonts',
                  attributes: {'w:ascii': font, 'w:hAnsi': font});
            }
            if (color != null) {
              builder.element('w:color', attributes: {'w:val': color});
            }
            builder.element('w:sz', attributes: {'w:val': '$size'});
          });
        });
      }

      style('Normal', 'Normal');
      for (var level = 1; level <= 6; level++) {
        style('Heading$level', 'heading $level',
            bold: true, size: 22 + (7 - level) * 3);
      }
      style('Code', 'Código',
          size: (ExportConfig.codeFontSize * 2).toInt(),
          font: ExportConfig.wordCodeFont);
      style('Quote', 'Cita', color: ExportConfig.wordQuoteColor);
      builder.element('w:style',
          attributes: {'w:type': 'table', 'w:styleId': 'TableGrid'}, nest: () {
        builder.element('w:name', attributes: {'w:val': 'Table Grid'});
        builder.element('w:tblPr', nest: () {
          builder.element('w:tblBorders', nest: () {
            for (final edge in [
              'top',
              'left',
              'bottom',
              'right',
              'insideH',
              'insideV'
            ]) {
              builder.element('w:$edge', attributes: {
                'w:val': 'single',
                'w:sz': '4',
                'w:color': ExportConfig.wordTableBorderColor
              });
            }
          });
        });
      });
    });
    return builder.buildDocument().toXmlString();
  }

  static String _wordNumbering() {
    final builder = XmlBuilder();
    builder.element('w:numbering', namespaceUris: {'w': _wordNs}, nest: () {
      for (var type = 0; type < 2; type++) {
        builder.element('w:abstractNum',
            attributes: {'w:abstractNumId': '$type'}, nest: () {
          builder
              .element('w:multiLevelType', attributes: {'w:val': 'multilevel'});
          for (var level = 0; level < ExportConfig.maxWordListLevels; level++) {
            builder.element('w:lvl', attributes: {'w:ilvl': '$level'},
                nest: () {
              builder.element('w:start', attributes: {'w:val': '1'});
              builder.element('w:numFmt',
                  attributes: {'w:val': type == 0 ? 'bullet' : 'decimal'});
              builder.element('w:lvlText',
                  attributes: {'w:val': type == 0 ? '•' : '%${level + 1}.'});
              builder.element('w:pPr',
                  nest: () => builder.element('w:ind', attributes: {
                        'w:left':
                            '${ExportConfig.wordListIndentTwips * (level + 1)}',
                        'w:hanging': '${ExportConfig.wordListHangingTwips}'
                      }));
            });
          }
        });
        builder.element('w:num',
            attributes: {'w:numId': '${type + 1}'},
            nest: () => builder
                .element('w:abstractNumId', attributes: {'w:val': '$type'}));
      }
    });
    return builder.buildDocument().toXmlString();
  }

  static Uint8List _xlsx(List<Map<String, dynamic>>? rawSheets, String title) {
    if (rawSheets == null ||
        rawSheets.isEmpty ||
        rawSheets.length > ExportConfig.maxSheets) {
      throw const FormatException(
          'Indica entre 1 y ${ExportConfig.maxSheets} hojas para el Excel.');
    }
    final archive = Archive();
    final relationships = <Map<String, String>>[];
    final contentTypes = <String, String>{
      '/xl/workbook.xml':
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml',
      '/docProps/core.xml':
          'application/vnd.openxmlformats-package.core-properties+xml',
    };
    final names = <String>{};
    var totalCells = 0;
    var totalTextChars = 0;
    final workbook = XmlBuilder();
    workbook.element('workbook',
        attributes: {'xmlns': _spreadsheetNs},
        namespaceUris: {'r': _officeRel}, nest: () {
      workbook.element('sheets', nest: () {
        for (var sheetIndex = 0; sheetIndex < rawSheets.length; sheetIndex++) {
          final raw = rawSheets[sheetIndex];
          final name = raw['name'];
          if (name is! String ||
              name.trim().isEmpty ||
              name.length > ExportConfig.maxSheetNameChars ||
              RegExp(r"[\[\]:*?/\\]").hasMatch(name) ||
              name.startsWith("'") ||
              name.endsWith("'") ||
              !names.add(name.toLowerCase())) {
            throw const FormatException('Nombre de hoja no válido o repetido.');
          }
          _validateText(name);
          final rows = raw['rows'];
          if (rows is! List ||
              rows.isEmpty ||
              rows.length > ExportConfig.maxRowsPerSheet) {
            throw const FormatException(
                'La hoja está vacía o supera el límite de filas.');
          }
          final sheet = XmlBuilder();
          sheet.element('worksheet', attributes: {'xmlns': _spreadsheetNs},
              nest: () {
            sheet.element('sheetData', nest: () {
              for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
                final row = rows[rowIndex];
                if (row is! List || row.length > ExportConfig.maxColumns) {
                  throw const FormatException(
                      'La fila no es válida o tiene demasiadas columnas.');
                }
                totalCells += row.length;
                if (totalCells > ExportConfig.maxCells) {
                  throw const FormatException(
                      'El Excel supera el límite de celdas.');
                }
                sheet.element('row', attributes: {'r': '${rowIndex + 1}'},
                    nest: () {
                  for (var column = 0; column < row.length; column++) {
                    final cell = row[column];
                    final reference = '${_columnName(column)}${rowIndex + 1}';
                    if (cell == null) {
                      continue;
                    }
                    if (cell is num && cell.isFinite) {
                      sheet.element('c',
                          attributes: {'r': reference},
                          nest: () => sheet.element('v', nest: '$cell'));
                    } else if (cell is bool) {
                      sheet.element('c',
                          attributes: {'r': reference, 't': 'b'},
                          nest: () =>
                              sheet.element('v', nest: cell ? '1' : '0'));
                    } else if (cell is String) {
                      totalTextChars += cell.length;
                      if (totalTextChars > ExportConfig.maxContentChars) {
                        throw const FormatException(
                            'El texto del Excel supera el límite de exportación.');
                      }
                      if (cell.length > ExportConfig.maxCellChars) {
                        throw const FormatException(
                            'Una celda supera el límite de texto de Excel.');
                      }
                      _validateText(cell);
                      sheet.element('c',
                          attributes: {'r': reference, 't': 'inlineStr'},
                          nest: () => sheet.element('is',
                              nest: () => sheet.element('t',
                                  attributes: {'xml:space': 'preserve'},
                                  nest: cell)));
                    } else {
                      throw const FormatException(
                          'Las celdas deben ser texto, números finitos, booleanos o null.');
                    }
                  }
                });
              }
            });
          });
          final position = sheetIndex + 1;
          final part = 'worksheets/sheet$position.xml';
          _addXml(archive, 'xl/$part', sheet.buildDocument().toXmlString());
          contentTypes['/xl/$part'] =
              'application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml';
          relationships.add({
            'Id': 'rId$position',
            'Type': '$_officeRel/worksheet',
            'Target': part
          });
          workbook.element('sheet', attributes: {
            'name': name,
            'sheetId': '$position',
            'r:id': 'rId$position'
          });
        }
      });
    });
    _addXml(archive, 'xl/workbook.xml', workbook.buildDocument().toXmlString());
    _addXml(
        archive, 'xl/_rels/workbook.xml.rels', _relationships(relationships));
    _addXml(archive, '[Content_Types].xml', _contentTypes(contentTypes));
    _addXml(
        archive,
        '_rels/.rels',
        _relationships([
          {
            'Id': 'rId1',
            'Type': '$_officeRel/officeDocument',
            'Target': 'xl/workbook.xml'
          },
          {
            'Id': 'rId2',
            'Type':
                'http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties',
            'Target': 'docProps/core.xml'
          },
        ]));
    _addXml(archive, 'docProps/core.xml', _coreProperties(title));
    return ZipEncoder().encodeBytes(archive);
  }

  static String _columnName(int zeroBased) {
    var value = zeroBased + 1;
    var name = '';
    while (value > 0) {
      value--;
      name = '${String.fromCharCode(65 + value % 26)}$name';
      value ~/= 26;
    }
    return name;
  }

  static String _relationships(List<Map<String, String>> items) {
    final builder = XmlBuilder();
    builder.element('Relationships', attributes: {'xmlns': _packageRel},
        nest: () {
      for (final item in items) {
        builder.element('Relationship', attributes: item);
      }
    });
    return builder.buildDocument().toXmlString();
  }

  static String _contentTypes(Map<String, String> overrides) {
    final builder = XmlBuilder();
    builder.element('Types', attributes: {
      'xmlns': 'http://schemas.openxmlformats.org/package/2006/content-types'
    }, nest: () {
      builder.element('Default', attributes: {
        'Extension': 'rels',
        'ContentType':
            'application/vnd.openxmlformats-package.relationships+xml'
      });
      builder.element('Default',
          attributes: {'Extension': 'xml', 'ContentType': 'application/xml'});
      overrides.forEach((part, type) => builder.element('Override',
          attributes: {'PartName': part, 'ContentType': type}));
    });
    return builder.buildDocument().toXmlString();
  }

  static String _coreProperties(String title) {
    final builder = XmlBuilder();
    builder.element('cp:coreProperties', namespaceUris: {
      'cp':
          'http://schemas.openxmlformats.org/package/2006/metadata/core-properties',
      'dc': 'http://purl.org/dc/elements/1.1/'
    }, nest: () {
      builder.element('dc:title', nest: title);
      builder.element('dc:creator', nest: 'LightChat');
    });
    return builder.buildDocument().toXmlString();
  }

  static void _addXml(Archive archive, String name, String content) =>
      archive.addFile(ArchiveFile.string(name, content));

  static const String _wordNs =
      'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
  static const String _spreadsheetNs =
      'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
  static const String _officeRel =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
  static const String _packageRel =
      'http://schemas.openxmlformats.org/package/2006/relationships';
}

class _Block {
  final String kind;
  final String text;
  final List<List<String>> rows;
  final String prefix;
  final int level;

  const _Block(this.kind, this.text,
      {this.rows = const [], this.prefix = '', this.level = 0});
}

/// Comprueba el cmap TrueType antes de generar: no sustituir glifos por cajas.
class _TrueTypeCoverage {
  final ByteData data;
  final List<int> subtables = [];

  _TrueTypeCoverage(Uint8List bytes) : data = ByteData.sublistView(bytes) {
    try {
      final count = data.getUint16(4);
      for (var index = 0; index < count; index++) {
        final entry = 12 + index * 16;
        if (data.getUint32(entry) != 0x636d6170) {
          continue;
        }
        final table = data.getUint32(entry + 8);
        final records = data.getUint16(table + 2);
        for (var record = 0; record < records; record++) {
          final location = table + 4 + record * 8;
          final platform = data.getUint16(location);
          final encoding = data.getUint16(location + 2);
          if (platform == 0 ||
              (platform == 3 && (encoding == 1 || encoding == 10))) {
            final offset = table + data.getUint32(location + 4);
            final format = data.getUint16(offset);
            if (format == 4 || format == 12) {
              subtables.add(offset);
            }
          }
        }
      }
    } on RangeError {
      throw const FormatException('Fuente TrueType dañada.');
    }
    if (subtables.isEmpty) {
      throw const FormatException(
          'Fuente sin mapa Unicode TrueType compatible.');
    }
  }

  bool covers(String text) {
    try {
      return text.runes
          .toSet()
          .where((rune) => rune > 32)
          .every((rune) => subtables.any((offset) => _hasGlyph(offset, rune)));
    } on RangeError {
      throw const FormatException('Mapa Unicode de la fuente dañado.');
    }
  }

  bool _hasGlyph(int offset, int rune) {
    if (data.getUint16(offset) == 12) {
      final groups = data.getUint32(offset + 12);
      var left = 0;
      var right = groups - 1;
      while (left <= right) {
        final middle = (left + right) ~/ 2;
        final group = offset + 16 + middle * 12;
        final start = data.getUint32(group);
        final end = data.getUint32(group + 4);
        if (rune < start) {
          right = middle - 1;
        } else if (rune > end) {
          left = middle + 1;
        } else {
          return data.getUint32(group + 8) + rune - start != 0;
        }
      }
      return false;
    }
    if (rune > 0xffff) {
      return false;
    }
    final segments = data.getUint16(offset + 6) ~/ 2;
    final ends = offset + 14;
    final starts = ends + segments * 2 + 2;
    final deltas = starts + segments * 2;
    final ranges = deltas + segments * 2;
    for (var index = 0; index < segments; index++) {
      if (rune > data.getUint16(ends + index * 2)) {
        continue;
      }
      if (rune < data.getUint16(starts + index * 2)) {
        return false;
      }
      final delta = data.getInt16(deltas + index * 2);
      final rangeLocation = ranges + index * 2;
      final range = data.getUint16(rangeLocation);
      if (range == 0) {
        return ((rune + delta) & 0xffff) != 0;
      }
      final glyphLocation = rangeLocation +
          range +
          2 * (rune - data.getUint16(starts + index * 2));
      final glyph = data.getUint16(glyphLocation);
      return glyph != 0 && ((glyph + delta) & 0xffff) != 0;
    }
    return false;
  }
}
