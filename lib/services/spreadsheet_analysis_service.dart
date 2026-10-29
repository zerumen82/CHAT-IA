import 'dart:isolate';

import '../config/spreadsheet_config.dart';
import '../models/spreadsheet_data.dart';

enum NumberTextFormat { decimalPoint, decimalComma }

class SpreadsheetGroup {
  final String label;
  final String total;
  final int numbers;
  const SpreadsheetGroup(this.label, this.total, this.numbers);
}

class SpreadsheetAnalysis {
  final List<SpreadsheetGroup> groups;
  final String total;
  final int rows;
  final int numbers;
  final int empty;
  final int nonNumeric;
  final int formulas;
  final int errors;
  final List<String> sheets;
  const SpreadsheetAnalysis({
    required this.groups,
    required this.total,
    required this.rows,
    required this.numbers,
    required this.empty,
    required this.nonNumeric,
    required this.formulas,
    required this.errors,
    required this.sheets,
  });

  bool get hasExcludedValues => nonNumeric + formulas + errors > 0;

  String toMarkdown(String fileName) {
    String escape(String value) =>
        value.replaceAll('|', '\\|').replaceAll('\n', ' ');
    return '# Cálculo local: ${escape(fileName)}\n\n'
        'Hojas: ${sheets.map(escape).join(', ')}. '
        '$rows filas de datos procesadas; $numbers valores sumados.\n\n'
        '| Grupo | Suma | Valores |\n| --- | ---: | ---: |\n'
        '${groups.map((g) => '| ${escape(g.label)} | ${g.total} | ${g.numbers} |').join('\n')}\n\n'
        '**Suma de valores admitidos: $total**\n\n'
        'Excluidos: $empty vacíos, $nonNumeric no numéricos, '
        '$formulas fórmulas y $errors errores. '
        'No se ejecutan ni recalculan fórmulas. '
        '${hasExcludedValues ? 'Hay valores excluidos: esta suma no representa todos los importes de la tabla.' : ''}\n';
  }
}

/// Suma decimal exacta de valores admitidos; jamás evalúa fórmulas.
class SpreadsheetAnalysisService {
  SpreadsheetAnalysisService._();

  static Future<SpreadsheetAnalysis> calculate({
    required SpreadsheetData data,
    required Set<String> sheetNames,
    required int valueColumn,
    int? groupColumn,
    bool firstRowIsHeader = true,
    NumberTextFormat textFormat = NumberTextFormat.decimalComma,
  }) =>
      Isolate.run(() => calculateSync(
            data: data,
            sheetNames: sheetNames,
            valueColumn: valueColumn,
            groupColumn: groupColumn,
            firstRowIsHeader: firstRowIsHeader,
            textFormat: textFormat,
          ));

  static SpreadsheetAnalysis calculateSync({
    required SpreadsheetData data,
    required Set<String> sheetNames,
    required int valueColumn,
    int? groupColumn,
    bool firstRowIsHeader = true,
    NumberTextFormat textFormat = NumberTextFormat.decimalComma,
  }) {
    final selected =
        data.sheets.where((s) => sheetNames.contains(s.name)).toList();
    if (selected.isEmpty ||
        selected.length != sheetNames.length ||
        valueColumn < 0) {
      throw const FormatException(
          'Selecciona al menos una hoja y una columna válida.');
    }
    if (groupColumn != null &&
        (groupColumn < 0 || groupColumn == valueColumn)) {
      throw const FormatException(
          'La columna de agrupación debe ser distinta de la suma.');
    }
    var rows = 0,
        numbers = 0,
        empty = 0,
        nonNumeric = 0,
        formulas = 0,
        errors = 0;
    final sums = <String, _Decimal>{};
    final counts = <String, int>{};
    var total = _Decimal.zero();
    for (final sheet in selected) {
      if (!sheet.columns.contains(valueColumn) ||
          (groupColumn != null && !sheet.columns.contains(groupColumn))) {
        throw FormatException(
            'La hoja «${sheet.name}» no contiene las columnas elegidas.');
      }
      for (final row in sheet.rows.skip(firstRowIsHeader ? 1 : 0)) {
        rows++;
        final cell = row.cells[valueColumn];
        if (cell == null || cell.text.trim().isEmpty) {
          empty++;
          continue;
        }
        if (cell.kind == SpreadsheetCellKind.formula) {
          formulas++;
          continue;
        }
        if (cell.kind == SpreadsheetCellKind.error) {
          errors++;
          continue;
        }
        if (cell.kind == SpreadsheetCellKind.boolean ||
            cell.kind == SpreadsheetCellKind.date) {
          nonNumeric++;
          continue;
        }
        final normalized = cell.kind == SpreadsheetCellKind.number
            ? cell.text.trim()
            : _normalizeNumber(cell.text, textFormat);
        final number = normalized == null ? null : _Decimal.parse(normalized);
        if (number == null) {
          nonNumeric++;
          continue;
        }
        String label;
        final group = groupColumn == null ? null : row.cells[groupColumn];
        if (groupColumn == null) {
          label = 'Todos';
        } else if (group?.kind == SpreadsheetCellKind.formula ||
            group?.kind == SpreadsheetCellKind.error) {
          throw FormatException(
              'La agrupación incluye una fórmula/error en «${sheet.name}», fila ${row.number}. Elige otra columna.');
        } else {
          label = group?.text.trim() ?? '';
        }
        numbers++;
        sums[label] = (sums[label] ?? _Decimal.zero()).add(number);
        counts[label] = (counts[label] ?? 0) + 1;
        total = total.add(number);
      }
    }
    if (numbers == 0) {
      throw FormatException(
          'No hay valores numéricos admitidos. Revisa columna y formato decimal. Excluidos: $empty vacíos, $nonNumeric no numéricos, $formulas fórmulas, $errors errores.');
    }
    final labels = sums.keys.toList()..sort();
    return SpreadsheetAnalysis(
      groups: [
        for (final label in labels)
          SpreadsheetGroup(label.isEmpty ? '(grupo vacío)' : label,
              sums[label].toString(), counts[label]!)
      ],
      total: total.toString(),
      rows: rows,
      numbers: numbers,
      empty: empty,
      nonNumeric: nonNumeric,
      formulas: formulas,
      errors: errors,
      sheets: selected.map((s) => s.name).toList(),
    );
  }

  static String? _normalizeNumber(String text, NumberTextFormat format) {
    final value = text.trim();
    // Separadores de miles solo en grupos exactos de tres; no se adivina locale.
    final decimal = format == NumberTextFormat.decimalComma ? ',' : '.';
    final thousand = decimal == ',' ? '.' : ',';
    final d = RegExp.escape(decimal), t = RegExp.escape(thousand);
    if (!RegExp('^[+-]?(?:[0-9]+|[0-9]{1,3}(?:$t[0-9]{3})+)(?:$d[0-9]+)?\$')
        .hasMatch(value)) {
      return null;
    }
    return value.replaceAll(thousand, '').replaceAll(decimal, '.');
  }
}

class _Decimal {
  final BigInt coefficient;
  final int scale;
  _Decimal(this.coefficient, this.scale);
  factory _Decimal.zero() => _Decimal(BigInt.zero, 0);

  static _Decimal? parse(String text) {
    final match =
        RegExp(r'^([+-]?)([0-9]+)(?:\.([0-9]+))?(?:[eE]([+-]?[0-9]+))?$')
            .firstMatch(text);
    if (match == null) {
      return null;
    }
    final fraction = match.group(3) ?? '';
    final digits = '${match.group(2)}$fraction';
    final exponent = int.tryParse(match.group(4) ?? '0');
    if (exponent == null ||
        digits.length > SpreadsheetConfig.maxNumericDigits ||
        exponent.abs() > SpreadsheetConfig.maxNumericDigits) {
      return null;
    }
    var scale = fraction.length - exponent;
    if (scale > SpreadsheetConfig.maxDecimalPlaces) {
      return null;
    }
    var coefficient = BigInt.parse('${match.group(1)}$digits');
    if (scale < 0) {
      coefficient *= BigInt.from(10).pow(-scale);
      scale = 0;
    }
    return _Decimal(coefficient, scale);
  }

  _Decimal add(_Decimal other) {
    final common = scale > other.scale ? scale : other.scale;
    return _Decimal(
        coefficient * BigInt.from(10).pow(common - scale) +
            other.coefficient * BigInt.from(10).pow(common - other.scale),
        common);
  }

  @override
  String toString() {
    var digits = coefficient.abs().toString().padLeft(scale + 1, '0');
    if (scale > 0) {
      digits =
          '${digits.substring(0, digits.length - scale)}.${digits.substring(digits.length - scale)}';
      digits = digits
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');
    }
    return '${coefficient.isNegative ? '-' : ''}$digits';
  }
}
