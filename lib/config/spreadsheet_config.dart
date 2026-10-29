/// Límites de cálculo local; si se alcanzan se rechaza el libro completo.
class SpreadsheetConfig {
  SpreadsheetConfig._();

  static const maxNumericDigits = 100;
  static const maxDecimalPlaces = 30;
  static const previewRows = 5;
  static const maxSheets = 100;
  static const maxCells = 500000;
  static const maxFormulaRanges = 128;
  static const excelMaxRows = 1048576;
}
