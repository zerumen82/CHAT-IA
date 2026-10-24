import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightchat/models/document_attachment.dart';
import 'package:lightchat/services/document_service.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

Uint8List _buildTestWorkbook() {
  final archive = Archive();

  void add(String name, String content) {
    archive.addFile(ArchiveFile.string(name, content));
  }

  add(
    'xl/workbook.xml',
    '<?xml version="1.0" encoding="UTF-8"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<sheets><sheet name="Ventas" sheetId="1" r:id="rId1"/></sheets></workbook>',
  );
  add(
    'xl/_rels/workbook.xml.rels',
    '<?xml version="1.0" encoding="UTF-8"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" '
        'Target="worksheets/sheet1.xml"/></Relationships>',
  );
  add(
    'xl/sharedStrings.xml',
    '<?xml version="1.0" encoding="UTF-8"?>'
        '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<si><t>Producto</t></si><si><t>Precio</t></si></sst>',
  );
  add(
    'xl/styles.xml',
    '<?xml version="1.0" encoding="UTF-8"?>'
        '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<cellXfs count="2"><xf numFmtId="0"/><xf numFmtId="14"/></cellXfs>'
        '</styleSheet>',
  );
  add(
    'xl/worksheets/sheet1.xml',
    '<?xml version="1.0" encoding="UTF-8"?>'
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<sheetData>'
        '<row r="1"><c r="A1" t="s"><v>0</v></c>'
        '<c r="B1" t="s"><v>1</v></c></row>'
        '<row r="2"><c r="A2" t="inlineStr"><is><t>Manzanas</t></is></c>'
        '<c r="B2"><v>12.5</v></c></row>'
        '<row r="3"><c r="A3" t="inlineStr"><is><t>Entrega</t></is></c>'
        '<c r="C3" s="1"><v>45321</v></c></row>'
        '</sheetData></worksheet>',
  );

  return ZipEncoder().encodeBytes(archive);
}

Uint8List _buildTestPdf() {
  final document = PdfDocument();
  final page = document.pages.add();
  page.graphics.drawString(
    'Hello LightChat',
    PdfStandardFont(PdfFontFamily.helvetica, 12),
    brush: PdfSolidBrush(PdfColor(0, 0, 0)),
    bounds: const Rect.fromLTWH(10, 10, 300, 40),
  );
  final bytes = Uint8List.fromList(document.saveSync());
  document.dispose();
  return bytes;
}

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory =
        await Directory.systemTemp.createTemp('lightchat-documents');
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('extracts plain text and normalizes line endings', () async {
    final file = File('${temporaryDirectory.path}/notas.txt');
    await file.writeAsString('Hola mundo\r\nSegunda línea');

    final document = await DocumentService.extract(file.path);

    expect(document.error, isNull);
    expect(document.isReady, isTrue);
    expect(document.kind, DocumentKind.text);
    expect(document.text, 'Hola mundo\nSegunda línea');
    expect(document.truncated, isFalse);
  });

  test('truncates documents longer than the context budget', () async {
    final file = File('${temporaryDirectory.path}/largo.txt');
    await file.writeAsString(List.filled(9000, 'a').join());

    final document = await DocumentService.extract(file.path);

    expect(document.truncated, isTrue);
    expect(
      document.charCount,
      lessThanOrEqualTo(DocumentService.maxCharsPerDocument),
    );
    expect(document.text, contains('recortado'));
    expect(document.originalChars, 9000);
    expect(document.isReady, isTrue);
  });

  test('rejects formats that are not supported', () async {
    final file = File('${temporaryDirectory.path}/contrato.docx');
    await file.writeAsBytes(utf8.encode('contenido'));

    final document = await DocumentService.extract(file.path);

    expect(document.isReady, isFalse);
    expect(document.error, contains('Formato no admitido'));
  });

  test('extracts shared strings, inline strings and numbers from XLSX',
      () async {
    final file = File('${temporaryDirectory.path}/ventas.xlsx');
    await file.writeAsBytes(_buildTestWorkbook());

    final document = await DocumentService.extract(file.path);

    expect(document.error, isNull);
    expect(document.kind, DocumentKind.spreadsheet);
    expect(document.text, contains('Hoja "Ventas"'));
    expect(document.text, contains('Fila 1: Producto | Precio'));
    expect(document.text, contains('Fila 2: Manzanas | 12.5'));
  });

  test('converts Excel date serials to readable dates', () async {
    final file = File('${temporaryDirectory.path}/fechas.xlsx');
    await file.writeAsBytes(_buildTestWorkbook());

    final document = await DocumentService.extract(file.path);

    expect(document.text, contains('30/01/2024'));
    expect(document.text, isNot(contains('45321')));
  });

  test('extracts selectable text from PDF', () async {
    final file = File('${temporaryDirectory.path}/informe.pdf');
    await file.writeAsBytes(_buildTestPdf());

    final document = await DocumentService.extract(file.path);

    expect(document.error, isNull);
    expect(document.kind, DocumentKind.pdf);
    expect(document.text, contains('Hello LightChat'));
  });

  test('builds the attachment context within the character budget', () {
    final documents = [
      DocumentAttachment(
        path: 'a.txt',
        name: 'primero.txt',
        kind: DocumentKind.text,
        sizeBytes: 10,
        text: List.filled(50, 'A').join(),
        originalChars: 50,
      ),
      DocumentAttachment(
        path: 'b.txt',
        name: 'segundo.txt',
        kind: DocumentKind.text,
        sizeBytes: 10,
        text: List.filled(50, 'B').join(),
        originalChars: 50,
      ),
      const DocumentAttachment(
        path: 'c.docx',
        name: 'fallido.docx',
        kind: DocumentKind.text,
        sizeBytes: 10,
        error: 'No se pudo leer',
      ),
    ];

    final context = DocumentService.buildAttachmentContext(
      documents,
      maxChars: 40,
    );

    expect(context, contains('Documento 1: primero.txt'));
    expect(context, contains('recortado'));
    expect(context, contains('omitido(s) por límite de contexto'));
    expect(context, isNot(contains('segundo.txt')));
    expect(context, isNot(contains('fallido.docx')));
  });
}
