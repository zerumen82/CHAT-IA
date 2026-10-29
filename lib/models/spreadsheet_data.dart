enum SpreadsheetCellKind { text, number, boolean, date, formula, error }

class SpreadsheetCell {
  final String text;
  final SpreadsheetCellKind kind;
  const SpreadsheetCell(this.text, [this.kind = SpreadsheetCellKind.text]);
}

class SpreadsheetRow {
  final int number;
  final Map<int, SpreadsheetCell> cells;
  const SpreadsheetRow(this.number, this.cells);
}

class SpreadsheetSheet {
  final String name;
  final List<SpreadsheetRow> rows;
  const SpreadsheetSheet(this.name, this.rows);

  List<int> get columns =>
      (rows.expand((r) => r.cells.keys).toSet().toList()..sort());
}

/// Resultado de lectura estructurada; no contiene filas recortadas ni texto LLM.
class SpreadsheetData {
  final String name;
  final int sizeBytes;
  final List<SpreadsheetSheet> sheets;
  final List<String> warnings;
  const SpreadsheetData(this.name, this.sizeBytes, this.sheets,
      {this.warnings = const []});
}
