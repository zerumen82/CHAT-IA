enum ExportFormat {
  txt('txt', 'Texto (.txt)'),
  markdown('md', 'Markdown (.md)'),
  pdf('pdf', 'PDF (.pdf)'),
  docx('docx', 'Word (.docx)'),
  xlsx('xlsx', 'Excel (.xlsx)');

  final String extension;
  final String label;

  const ExportFormat(this.extension, this.label);

  static ExportFormat fromExtension(String value) {
    final normalized = value.toLowerCase().replaceFirst(RegExp(r'^\.'), '');
    if (normalized == 'markdown') {
      return ExportFormat.markdown;
    }
    return ExportFormat.values.firstWhere(
      (format) => format.extension == normalized,
      orElse: () => throw FormatException('Formato no admitido: $value'),
    );
  }
}
