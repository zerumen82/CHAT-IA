import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightchat/config/document_config.dart';
import 'package:lightchat/models/spreadsheet_data.dart';
import 'package:lightchat/models/export_format.dart';
import 'package:lightchat/services/document_service.dart';
import 'package:lightchat/services/export_service.dart';
import 'package:lightchat/services/spreadsheet_analysis_service.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('lightchat-table-');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  Future<File> file(String name, String content) async =>
      File('${directory.path}/$name').writeAsString(content);

  test('CSV real: grupos, negativos, decimales exactos y exclusiones visibles',
      () async {
    final source = await file('ventas con tildes.csv',
        'Concepto;Importe\nCafé;0,1\nCafé;0,2\nTé;-2,50\nTé;1.234,56\nOtros;sin dato\nOtros;\n');
    final data =
        await DocumentService.readSpreadsheet(source.path, csvDelimiter: ';');
    final result = await SpreadsheetAnalysisService.calculate(
        data: data, sheetNames: {'Tabla'}, valueColumn: 1, groupColumn: 0);
    expect(result.total, '1232.36');
    expect(result.groups.firstWhere((g) => g.label == 'Café').total, '0.3');
    expect(result.rows, 6);
    expect(result.numbers, 4);
    expect(result.nonNumeric, 1);
    expect(result.empty, 1);
    expect(result.hasExcludedValues, isTrue);
    expect(result.toMarkdown(data.name),
        contains('no representa todos los importes'));
  });

  test('CSV respeta comillas, delimitadores y saltos dentro de una celda',
      () async {
    final source = await file(
        'quotes.csv', 'Grupo,Valor\n"A | B\nC",0.1\n"A | B\nC",0.2\n');
    final data = await DocumentService.readSpreadsheet(source.path);
    final result = await SpreadsheetAnalysisService.calculate(
        data: data,
        sheetNames: {'Tabla'},
        valueColumn: 1,
        groupColumn: 0,
        textFormat: NumberTextFormat.decimalPoint);
    expect(result.total, '0.3');
    expect(result.groups.single.label, 'A | B\nC');
    final broken = await file('broken.csv', 'grupo,valor\n"sin cerrar,12');
    await expectLater(
        DocumentService.readSpreadsheet(broken.path), throwsFormatException);
  });

  test(
      'bloquea tabla que supera filas o columnas, sin devolver una selección parcial',
      () async {
    final source = await file('muchas.csv',
        List.filled(DocumentConfig.maxRowsPerSheet + 1, 'a,1').join('\n'));
    await expectLater(
        DocumentService.readSpreadsheet(source.path), throwsFormatException);
    final wide = await file('ancha.csv',
        List.filled(DocumentConfig.maxColumnsPerRow + 1, '1').join(','));
    await expectLater(
        DocumentService.readSpreadsheet(wide.path), throwsFormatException);
  });

  test(
      'XLSX real multihoja, fórmula cacheada excluida y celda nativa independiente de locale',
      () async {
    final source = File('${directory.path}/libro.xlsx');
    final archive = ZipDecoder().decodeBytes(await ExportService.encode(
        format: ExportFormat.xlsx,
        title: 'Ventas',
        markdown: '',
        sheets: [
          {
            'name': 'Enero',
            'rows': [
              ['Grupo', 'Importe'],
              ['Café', 0.1]
            ]
          },
          {
            'name': 'Febrero',
            'rows': [
              ['Grupo', 'Importe'],
              ['Café', 0.2]
            ]
          },
        ]));
    void entry(String name, String content) {
      final bytes = utf8.encode(content);
      archive.add(ArchiveFile(name, bytes.length, bytes));
    }

    String sheet(String number, {bool formula = false}) =>
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>Grupo</t></is></c><c r="B1" t="inlineStr"><is><t>Importe</t></is></c></row><row r="2"><c r="A2" t="inlineStr"><is><t>Café</t></is></c><c r="B2"><v>$number</v></c></row>${formula ? '<row r="3"><c r="A3" t="inlineStr"><is><t>Total</t></is></c><c r="B3"><f t="array" ref="B3:B4">SUM(B2:B2)</f><v>9999</v></c></row><row r="4"><c r="A4" t="inlineStr"><is><t>Cache</t></is></c><c r="B4"><v>9999</v></c></row>' : ''}</sheetData></worksheet>';
    entry('xl/worksheets/sheet1.xml', sheet('0.1', formula: true));
    entry('xl/worksheets/sheet2.xml', sheet('2e-1'));
    await source.writeAsBytes(ZipEncoder().encode(archive));
    final data = await DocumentService.readSpreadsheet(source.path);
    final result = await SpreadsheetAnalysisService.calculate(
        data: data,
        sheetNames: {'Enero', 'Febrero'},
        valueColumn: 1,
        groupColumn: 0);
    expect(result.total, '0.3');
    expect(result.formulas, 2);
    expect(result.rows, 4);
    expect(result.groups.single.numbers, 2);
    expect(result.sheets, ['Enero', 'Febrero']);
    final renamed = File('${directory.path}/renombrado.xls');
    await renamed.writeAsBytes(await source.readAsBytes());
    expect(
        (await DocumentService.readSpreadsheet(renamed.path)).sheets.length, 2);
  });

  test('rechaza agrupar por fórmula y selección de columnas ausentes',
      () async {
    const data = SpreadsheetData('test', 0, [
      SpreadsheetSheet('Hoja', [
        SpreadsheetRow(
            1, {0: SpreadsheetCell('Grupo'), 1: SpreadsheetCell('Valor')}),
        SpreadsheetRow(2, {
          0: SpreadsheetCell('cache', SpreadsheetCellKind.formula),
          1: SpreadsheetCell('12', SpreadsheetCellKind.number)
        }),
      ])
    ]);
    expect(
        () => SpreadsheetAnalysisService.calculateSync(
            data: data, sheetNames: {'Hoja'}, valueColumn: 1, groupColumn: 0),
        throwsFormatException);
    expect(
        () => SpreadsheetAnalysisService.calculateSync(
            data: data, sheetNames: {'Hoja'}, valueColumn: 8),
        throwsFormatException);
    expect(
        () => SpreadsheetAnalysisService.calculateSync(
            data: data, sheetNames: {'No existe'}, valueColumn: 1),
        throwsFormatException);
  });

  test('BIFF8 real se rechaza para no sumar fórmulas cacheadas como números',
      () async {
    await expectLater(
        DocumentService.readSpreadsheet('test/fixtures/ventas_ligero.xls'),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'explicación', contains('XLSX o CSV'))));
    // La lectura documental preexistente sigue permitida.
    expect(
        (await DocumentService.extract('test/fixtures/ventas_ligero.xls'))
            .isReady,
        isTrue);
  });
}
