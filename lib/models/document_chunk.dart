/// Fragmento con referencia verificable al texto extraído de su archivo.
class DocumentChunk {
  final String text;
  final int firstLine;
  final int lastLine;
  final String? section;

  const DocumentChunk({
    required this.text,
    required this.firstLine,
    required this.lastLine,
    this.section,
  });

  String get reference =>
      '[${section == null ? '' : '$section; '}líneas $firstLine–$lastLine]';
}
