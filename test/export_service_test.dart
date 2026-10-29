import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightchat/config/export_config.dart';
import 'package:lightchat/models/document_attachment.dart';
import 'package:lightchat/models/export_format.dart';
import 'package:lightchat/models/generated_file.dart';
import 'package:lightchat/models/message.dart';
import 'package:lightchat/services/document_service.dart';
import 'package:lightchat/services/export_service.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:xml/xml.dart';

const _sample = '''## Resumen de ventas

El café cuesta **12,50 €** y el té cuesta 8 €.

- Primera partida
- Segunda partida

| Producto | Importe |
| --- | --- |
| Café | 12,50 |
| Té | 8 |

```dart
final total = 20.5;
print(total);
```
''';

Map<String, String> _xmlParts(List<int> bytes) {
  final zip = ZipDecoder().decodeBytes(bytes);
  final result = <String, String>{};
  for (final file in zip.files) {
    if (file.isFile &&
        (file.name.endsWith('.xml') || file.name.endsWith('.rels'))) {
      final text = utf8.decode(file.readBytes()!);
      final xml = XmlDocument.parse(text);
      // El parser Dart tolera xmlns:="..."; comprobar también la semántica
      // del namespace para no aceptar paquetes que Office rechaza.
      expect(text, isNot(contains('xmlns:=')), reason: file.name);
      final root = xml.rootElement;
      const rootNamespaces = {
        'Types': 'http://schemas.openxmlformats.org/package/2006/content-types',
        'Relationships':
            'http://schemas.openxmlformats.org/package/2006/relationships',
        'workbook': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main',
        'worksheet':
            'http://schemas.openxmlformats.org/spreadsheetml/2006/main',
        'document':
            'http://schemas.openxmlformats.org/wordprocessingml/2006/main',
      };
      if (rootNamespaces.containsKey(root.name.local)) {
        expect(root.namespaceUri, rootNamespaces[root.name.local],
            reason: file.name);
      }
      result[file.name] = text;
    }
  }
  return result;
}

Future<void> _writeOfficeEvidence(String name, List<int> bytes) async {
  final configured = Platform.environment['LIGHTCHAT_EXPORT_EVIDENCE_DIR'];
  if (configured == null || configured.isEmpty) {
    return;
  }
  final directory = Directory(configured);
  await directory.create(recursive: true);
  await File('${directory.path}/$name').writeAsBytes(bytes, flush: true);
}

void main() {
  late Directory temporary;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('lightchat-export-');
  });
  tearDown(() async {
    ExportConfig.pdfFontPath = null;
    await temporary.delete(recursive: true);
  });

  test('exports UTF-8 text and preserves the original Markdown structure',
      () async {
    final text = await ExportService.encode(
        format: ExportFormat.txt, title: 'Informe', markdown: _sample);
    final markdown = await ExportService.encode(
        format: ExportFormat.markdown, title: 'Informe', markdown: _sample);
    final plain = utf8.decode(text);
    expect(plain, contains('Informe'));
    expect(plain, contains('café cuesta 12,50 €'));
    expect(plain, contains('Producto | Importe'));
    expect(plain, contains('final total = 20.5;'));
    expect(plain, isNot(contains('**')));
    expect(utf8.decode(markdown), '# Informe\n\n$_sample');
  });

  test('creates an editable OOXML Word with headings, lists, tables and code',
      () async {
    final bytes = await ExportService.encode(
        format: ExportFormat.docx, title: 'Informe', markdown: _sample);
    await _writeOfficeEvidence('informe_corregido.docx', bytes);
    final parts = _xmlParts(bytes);
    expect(
        parts.keys,
        containsAll([
          '[Content_Types].xml',
          '_rels/.rels',
          'word/document.xml',
          'word/_rels/document.xml.rels',
          'word/styles.xml',
          'word/numbering.xml'
        ]));
    final document = XmlDocument.parse(parts['word/document.xml']!);
    expect(
        document.descendants
            .whereType<XmlElement>()
            .where((node) => node.name.local == 'tbl'),
        hasLength(1));
    expect(parts['word/document.xml'], contains('Heading2'));
    expect(parts['word/document.xml'], contains('w:numPr'));
    expect(parts['word/document.xml'], contains('w:val="Code"'));
    expect(parts['word/document.xml'], contains('final total = 20.5;'));
    expect(parts['word/numbering.xml'], contains('w:val="decimal"'));
    final file = File('${temporary.path}/informe con espacios.docx');
    await file.writeAsBytes(bytes);
    final extracted = await DocumentService.extract(file.path);
    expect(extracted.error, isNull);
    expect(extracted.text, contains('Resumen de ventas'));
    expect(extracted.text, contains('Café | 12,50'));
    expect(extracted.text, contains('print(total);'));
  });

  test('creates typed XLSX sheets and stores formula-looking strings literally',
      () async {
    final bytes = await ExportService.encode(
        format: ExportFormat.xlsx,
        title: 'Ventas',
        markdown: '',
        sheets: [
          {
            'name': 'Ventas',
            'rows': [
              ['Producto', 'Importe', 'Pagado'],
              ['Café & té <especial>', 12.5, true],
              ['=HYPERLINK("https://example.com")', -2, null],
            ],
          },
          {
            'name': 'Resumen',
            'rows': [
              ['Total', 10.5]
            ],
          },
        ]);
    final parts = _xmlParts(bytes);
    await _writeOfficeEvidence('ventas_corregido.xlsx', bytes);
    expect(
        parts.keys,
        containsAll([
          '[Content_Types].xml',
          '_rels/.rels',
          'xl/workbook.xml',
          'xl/_rels/workbook.xml.rels',
          'xl/worksheets/sheet1.xml',
          'xl/worksheets/sheet2.xml'
        ]));
    final sheet = XmlDocument.parse(parts['xl/worksheets/sheet1.xml']!);
    expect(sheet.findAllElements('f'), isEmpty);
    expect(parts['xl/worksheets/sheet1.xml'], contains('t="inlineStr"'));
    expect(parts['xl/worksheets/sheet1.xml'], contains('<v>12.5</v>'));
    expect(parts['xl/worksheets/sheet1.xml'], contains('t="b"'));
    final file = File('${temporary.path}/ventas reales.xlsx');
    await file.writeAsBytes(bytes);
    final extracted = await DocumentService.extract(file.path);
    expect(extracted.error, isNull);
    expect(extracted.text, contains('Hoja "Ventas"'));
    expect(extracted.text, contains('Hoja "Resumen"'));
    expect(extracted.text, contains('Café & té <especial>'));
    expect(extracted.text, contains('12.5'));
  });

  test('rejects malformed or oversized generated workbooks without truncating',
      () async {
    Future<List<int>> workbook(List<Map<String, dynamic>> sheets) =>
        ExportService.encode(
            format: ExportFormat.xlsx,
            title: 'Libro',
            markdown: '',
            sheets: sheets);
    expect(workbook([]), throwsFormatException);
    expect(
        workbook([
          {
            'name': '../Libro',
            'rows': [
              ['x']
            ]
          }
        ]),
        throwsFormatException);
    expect(
        workbook([
          {
            'name': 'Ventas',
            'rows': [
              ['x']
            ]
          },
          {
            'name': 'ventas',
            'rows': [
              ['y']
            ]
          },
        ]),
        throwsFormatException);
    expect(
        workbook([
          {
            'name': 'Datos',
            'rows': [
              [double.nan]
            ]
          }
        ]),
        throwsFormatException);
    expect(
        workbook([
          {
            'name': 'Datos',
            'rows': [
              [
                {'formula': 'SUM(A1)'}
              ]
            ]
          }
        ]),
        throwsFormatException);
    expect(
        workbook([
          {
            'name': 'Datos',
            'rows': [List.filled(ExportConfig.maxColumns + 1, 'x')]
          }
        ]),
        throwsFormatException);
    expect(
        workbook([
          {
            'name': 'Datos',
            'rows': [
              ['x' * (ExportConfig.maxCellChars + 1)]
            ]
          }
        ]),
        throwsFormatException);
  });

  test('PDF is paginated and preserves Spanish Unicode through extraction',
      () async {
    final content = List.generate(
            90,
            (index) =>
                '## Apartado $index\n\nCafé, té, información, año y 12,50 €. Esta es una línea de prueba suficientemente larga para verificar el ajuste de texto.')
        .join('\n\n');
    final bytes = await ExportService.encode(
        format: ExportFormat.pdf,
        title: 'Informe español',
        markdown: '$_sample\n\n$content\n\nMARCADOR-FINAL');
    expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
    final document = PdfDocument(inputBytes: bytes);
    try {
      expect(document.pages.count, greaterThan(1));
      final text = PdfTextExtractor(document).extractText();
      expect(text, contains('Café'));
      expect(text, contains('información'));
      expect(text, contains('12,50 €'));
      expect(text, contains('MARCADOR-FINAL'));
    } finally {
      document.dispose();
    }
  });

  test('PDF does not silently replace characters absent from local fonts',
      () async {
    expect(
        ExportService.encode(
            format: ExportFormat.pdf,
            title: 'Unicode',
            markdown: 'Sin glifo: ${String.fromCharCode(0x10ffff)}'),
        throwsFormatException);
  });

  test('conversation export includes retained turns and excludes paths/base64',
      () {
    final markdown = ExportService.conversationMarkdown([
      Message(
          text: 'Pregunta',
          isUser: true,
          timestamp: DateTime.utc(2026, 10, 26),
          documents: [
            const DocumentAttachment(
                path: 'C:/privado/original.txt',
                name: 'original.txt',
                kind: DocumentKind.text,
                sizeBytes: 10,
                text: 'contenido privado no exportado'),
          ]),
      Message(
          text: 'Respuesta',
          isUser: false,
          timestamp: DateTime.utc(2026, 10, 26, 1),
          model: 'qwen2.5:7b',
          generatedFiles: [
            const GeneratedFile(
                id: 'report1',
                name: 'informe.pdf',
                format: ExportFormat.pdf,
                sizeBytes: 200,
                relativePath: 'private-artifacts/report1.pdf'),
          ]),
    ], 'Conversación');
    expect(markdown, contains('Usuario'));
    expect(markdown, contains('qwen2.5:7b'));
    expect(markdown, contains('original.txt'));
    expect(markdown, isNot(contains('C:/privado')));
    expect(markdown, isNot(contains('contenido privado')));
    expect(markdown, contains('Archivos generados: informe.pdf (PDF)'));
    expect(markdown, isNot(contains('private-artifacts')));
    expect(markdown, contains('podados'));
    expect(
        markdown.indexOf('Pregunta'), lessThan(markdown.indexOf('Respuesta')));
  });

  test('generated file references round trip and reject external paths', () {
    const file = GeneratedFile(
        id: 'file1',
        name: 'ventas.xlsx',
        format: ExportFormat.xlsx,
        sizeBytes: 100,
        relativePath: 'conversation1/file1.xlsx');
    final restored = GeneratedFile.fromJson(file.toJson());
    expect(restored.format, ExportFormat.xlsx);
    expect(restored.relativePath, file.relativePath);
    for (final path in [
      '../escape.pdf',
      '/absolute.pdf',
      'C:/escape.pdf',
      'folder/../escape.pdf',
      r'folder\..\escape.pdf'
    ]) {
      expect(
          () =>
              GeneratedFile.fromJson({...file.toJson(), 'relativePath': path}),
          throwsFormatException);
    }
    expect(() => ExportFormat.fromExtension('xls'), throwsFormatException);
  });

  test('rejects empty exports and XML control characters visibly', () {
    expect(
        ExportService.encode(
            format: ExportFormat.docx, title: 'Informe', markdown: ''),
        throwsFormatException);
    expect(
        ExportService.encode(
            format: ExportFormat.docx, title: 'Informe', markdown: 'A\u0001B'),
        throwsFormatException);
    expect(
        ExportService.encode(
            format: ExportFormat.txt, title: '', markdown: 'Hola'),
        throwsFormatException);
  });
}
