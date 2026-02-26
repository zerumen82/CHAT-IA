import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

/// Servicio para manejo de imágenes en el chat multimodal
class ImageService {
  static final ImageService _instance = ImageService._internal();
  factory ImageService() => _instance;
  ImageService._internal();

  final ImagePicker _picker = ImagePicker();
  final Uuid _uuid = const Uuid();

  // Configuración
  static const int maxImageSizeBytes = 10 * 1024 * 1024; // 10MB
  static const int maxImageWidth = 2048;
  static const int maxImageHeight = 2048;
  static const int maxImagesPerMessage = 5;
  static const int thumbnailSize = 200;

  /// Seleccionar imagen desde galería
  Future<List<File>> pickImagesFromGallery({int maxImages = 5}) async {
    try {
      final List<XFile> images = await _picker.pickMultiImage(
        maxWidth: maxImageWidth.toDouble(),
        maxHeight: maxImageHeight.toDouble(),
        imageQuality: 85,
      );

      if (images.isEmpty) return [];

      // Limitar cantidad de imágenes
      final limitedImages = images.take(maxImages).toList();

      return limitedImages.map((xfile) => File(xfile.path)).toList();
    } catch (e) {
      debugPrint('Error picking images from gallery: $e');
      return [];
    }
  }

  /// Tomar foto con cámara
  Future<File?> takePhotoWithCamera() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: maxImageWidth.toDouble(),
        maxHeight: maxImageHeight.toDouble(),
        imageQuality: 85,
      );

      if (photo == null) return null;
      return File(photo.path);
    } catch (e) {
      debugPrint('Error taking photo: $e');
      return null;
    }
  }

  /// Procesar imagen para envío
  Future<ProcessedImage?> processImageForSending(File imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();

      // Verificar tamaño
      if (bytes.length > maxImageSizeBytes) {
        // Comprimir imagen
        final compressed = await _compressImage(bytes);
        if (compressed == null) return null;
        return _createProcessedImage(compressed, imageFile.path);
      }

      return _createProcessedImage(bytes, imageFile.path);
    } catch (e) {
      debugPrint('Error processing image: $e');
      return null;
    }
  }

  /// Crear objeto ProcessedImage desde bytes
  ProcessedImage? _createProcessedImage(Uint8List bytes, String originalPath) {
    try {
      // Decodificar para obtener dimensiones
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;

      final id = _uuid.v4();
      final extension = p.extension(originalPath).toLowerCase();
      final format = _getImageFormat(extension);

      return ProcessedImage(
        id: id,
        bytes: bytes,
        width: decoded.width,
        height: decoded.height,
        format: format,
        originalPath: originalPath,
      );
    } catch (e) {
      debugPrint('Error creating processed image: $e');
      return null;
    }
  }

  /// Comprimir imagen si excede el tamaño máximo
  Future<Uint8List?> _compressImage(Uint8List bytes) async {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;

      // Redimensionar si es necesario
      img.Image resized = decoded;
      if (decoded.width > maxImageWidth || decoded.height > maxImageHeight) {
        resized = img.copyResize(
          decoded,
          width: maxImageWidth,
          height: maxImageHeight,
          maintainAspect: true,
        );
      }

      // Codificar como JPEG con calidad reducida
      return Uint8List.fromList(img.encodeJpg(resized, quality: 70));
    } catch (e) {
      debugPrint('Error compressing image: $e');
      return null;
    }
  }

  /// Crear thumbnail para preview
  Future<Uint8List?> createThumbnail(Uint8List imageBytes) async {
    try {
      final decoded = img.decodeImage(imageBytes);
      if (decoded == null) return null;

      final thumbnail = img.copyResize(
        decoded,
        width: thumbnailSize,
        height: thumbnailSize,
        maintainAspect: true,
      );

      return Uint8List.fromList(img.encodeJpg(thumbnail, quality: 80));
    } catch (e) {
      debugPrint('Error creating thumbnail: $e');
      return null;
    }
  }

  /// Guardar imagen en directorio de la app
  Future<String?> saveImageToLocal(Uint8List bytes, String filename) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final imagesDir = Directory('${appDir.path}/chat_images');

      if (!await imagesDir.exists()) {
        await imagesDir.create(recursive: true);
      }

      final file = File('${imagesDir.path}/$filename');
      await file.writeAsBytes(bytes);

      return file.path;
    } catch (e) {
      debugPrint('Error saving image: $e');
      return null;
    }
  }

  /// Cargar imagen desde path local
  Future<Uint8List?> loadImageFromLocal(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      return await file.readAsBytes();
    } catch (e) {
      debugPrint('Error loading image: $e');
      return null;
    }
  }

  /// Eliminar imagen local
  Future<bool> deleteLocalImage(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
      return true;
    } catch (e) {
      debugPrint('Error deleting image: $e');
      return false;
    }
  }

  /// Limpiar imágenes antiguas del directorio de chat
  Future<void> cleanupOldImages({int maxAgeDays = 30}) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final imagesDir = Directory('${appDir.path}/chat_images');

      if (!await imagesDir.exists()) return;

      final now = DateTime.now();
      final files = await imagesDir.list().toList();

      for (final entity in files) {
        if (entity is File) {
          final stat = await entity.stat();
          final age = now.difference(stat.modified).inDays;

          if (age > maxAgeDays) {
            await entity.delete();
            debugPrint('Deleted old image: ${entity.path}');
          }
        }
      }
    } catch (e) {
      debugPrint('Error cleaning up images: $e');
    }
  }

  /// Convertir imagen a base64 para API
  String imageToBase64(Uint8List bytes) {
    return 'data:image/jpeg;base64,${_encodeBase64(bytes)}';
  }

  /// Convertir base64 a bytes
  Uint8List? base64ToBytes(String base64) {
    try {
      // Remover prefijo data:image/...;base64,
      final startIndex = base64.indexOf(',');
      final data = startIndex >= 0 ? base64.substring(startIndex + 1) : base64;
      return _decodeBase64(data);
    } catch (e) {
      debugPrint('Error decoding base64: $e');
      return null;
    }
  }

  /// Obtener formato de imagen desde extensión
  ImageFormat _getImageFormat(String extension) {
    switch (extension.toLowerCase()) {
      case '.png':
        return ImageFormat.png;
      case '.gif':
        return ImageFormat.gif;
      case '.webp':
        return ImageFormat.webp;
      case '.jpg':
      case '.jpeg':
      default:
        return ImageFormat.jpeg;
    }
  }

  /// Codificar a base64
  String _encodeBase64(Uint8List bytes) {
    return base64Encode(bytes);
  }

  /// Decodificar desde base64
  Uint8List _decodeBase64(String data) {
    return base64Decode(data);
  }

  /// Verificar si el formato es soportado
  bool isFormatSupported(String filename) {
    final ext = p.extension(filename).toLowerCase();
    return ['.jpg', '.jpeg', '.png', '.gif', '.webp'].contains(ext);
  }

  /// Obtener tamaño formateado
  String formatSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes bytes';
  }
}

/// Imagen procesada lista para envío
class ProcessedImage {
  final String id;
  final Uint8List bytes;
  final int width;
  final int height;
  final ImageFormat format;
  final String? originalPath;

  const ProcessedImage({
    required this.id,
    required this.bytes,
    required this.width,
    required this.height,
    required this.format,
    this.originalPath,
  });

  int get sizeBytes => bytes.length;
  String get sizeFormatted => ImageService().formatSize(sizeBytes);

  double get aspectRatio => width / height;
  bool get isLandscape => width > height;
  bool get isPortrait => height > width;
  bool get isSquare => width == height;

  /// Obtener MIME type
  String get mimeType {
    switch (format) {
      case ImageFormat.jpeg:
        return 'image/jpeg';
      case ImageFormat.png:
        return 'image/png';
      case ImageFormat.gif:
        return 'image/gif';
      case ImageFormat.webp:
        return 'image/webp';
    }
  }

  /// Convertir a base64 para API
  String toBase64() => ImageService().imageToBase64(bytes);

  /// Crear thumbnail
  Future<Uint8List?> createThumbnail() async {
    return ImageService().createThumbnail(bytes);
  }

  /// Guardar en almacenamiento local
  Future<String?> saveLocal() async {
    final extension = format == ImageFormat.png ? 'png' : 'jpg';
    final filename = 'img_$id.$extension';
    return ImageService().saveImageToLocal(bytes, filename);
  }
}

/// Formato de imagen
enum ImageFormat {
  jpeg,
  png,
  gif,
  webp,
}

/// Helper para base64
String base64Encode(Uint8List bytes) {
  return base64.encode(bytes);
}

Uint8List base64Decode(String data) {
  return base64.decode(data);
}
