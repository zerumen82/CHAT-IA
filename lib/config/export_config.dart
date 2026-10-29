import 'dart:io';

/// Límites y presentación de los archivos creados localmente.
class ExportConfig {
  ExportConfig._();

  static const int maxContentChars = 2 * 1024 * 1024;
  static const int maxTitleChars = 200;
  static const int maxSheets = 16;
  static const int maxSheetNameChars = 31;
  static const int maxRowsPerSheet = 10000;
  static const int maxColumns = 256;
  static const int maxCells = 100000;
  static const int maxCellChars = 32767;
  static const int maxFileBytes = 32 * 1024 * 1024;
  static const double pageMargin = 40;
  static const double bodyFontSize = 11;
  static const double codeFontSize = 9;
  static const double blockSpacing = 8;
  static const double cellPadding = 4;
  static const int maxPdfTableColumns = 12;
  static const int wordPageWidthTwips = 11906;
  static const int wordPageHeightTwips = 16838;
  static const int wordMarginTwips = 1134;
  static const int wordParagraphSpacingTwips = 160;
  static const int wordListIndentTwips = 720;
  static const int wordListHangingTwips = 360;
  static const int maxWordListLevels = 9;
  static const String wordCodeFont = 'Consolas';
  static const String wordQuoteColor = '555555';
  static const String wordTableBorderColor = '999999';

  /// Ruta opcional elegida por configuración; no se descarga ninguna fuente.
  static String? pdfFontPath;

  static List<String> get pdfFontCandidates {
    final configured =
        pdfFontPath ?? Platform.environment['LIGHTCHAT_PDF_FONT'];
    final windows = Platform.environment['WINDIR'];
    return [
      if (configured != null && configured.isNotEmpty) configured,
      if (Platform.isWindows && windows != null) ...[
        '$windows/Fonts/arial.ttf',
        '$windows/Fonts/segoeui.ttf',
        '$windows/Fonts/calibri.ttf',
      ],
      if (Platform.isLinux) ...[
        '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
        '/usr/share/fonts/truetype/liberation2/LiberationSans-Regular.ttf',
      ],
      if (Platform.isMacOS) ...[
        '/System/Library/Fonts/Supplemental/Arial.ttf',
        '/Library/Fonts/Arial.ttf',
      ],
    ];
  }
}
