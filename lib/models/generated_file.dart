import 'export_format.dart';

/// Referencia al archivo creado en el almacén local, nunca una ruta del modelo.
class GeneratedFile {
  final String id;
  final String name;
  final ExportFormat format;
  final int sizeBytes;
  final String relativePath;

  const GeneratedFile({
    required this.id,
    required this.name,
    required this.format,
    required this.sizeBytes,
    required this.relativePath,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'format': format.extension,
        'sizeBytes': sizeBytes,
        'relativePath': relativePath,
      };

  factory GeneratedFile.fromJson(Map<String, dynamic> json) {
    final path = json['relativePath'] as String? ?? '';
    final parts = path.split(RegExp(r'[/\\]'));
    if (path.isEmpty ||
        path.startsWith(RegExp(r'[/\\]')) ||
        path.contains(':') ||
        path.codeUnits.any((code) => code < 32) ||
        parts.any((part) => part.isEmpty || part == '..' || part == '.')) {
      throw const FormatException('Referencia de archivo local no válida.');
    }
    final size = json['sizeBytes'] as int? ?? 0;
    if (size <= 0) {
      throw const FormatException(
          'El archivo generado no tiene tamaño válido.');
    }
    return GeneratedFile(
      id: json['id'] as String,
      name: json['name'] as String,
      format: ExportFormat.fromExtension(json['format'] as String),
      sizeBytes: size,
      relativePath: path,
    );
  }
}
