import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/local_model.dart';
import 'hardware_detector_service.dart';
import '../config/vllm_config.dart';

/// Servicio para gestión de modelos locales
/// Descarga, instala y administra modelos de IA desde HuggingFace
class ModelManagerService with ChangeNotifier {
  // Lista de modelos instalados
  List<LocalModel> _installedModels = [];
  List<LocalModel> get installedModels => _installedModels;

  // Modelo en descarga
  LocalModel? _downloadingModel;
  LocalModel? get downloadingModel => _downloadingModel;

  // Estado de carga
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  // Error si lo hay
  String? _error;
  String? get error => _error;

  // Directorio de modelos
  String? _modelsDirectory;
  String? get modelsDirectory => _modelsDirectory;

  // Dio para descargas con progreso
  final Dio _dio = Dio();

  // CancelToken para cancelar descargas
  CancelToken? _cancelToken;

  ModelManagerService() {
    _initService();
  }

  Future<void> _initService() async {
    await _setupModelsDirectory();
    await _loadInstalledModels();
  }

  /// Configurar directorio de modelos
  Future<void> _setupModelsDirectory() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      _modelsDirectory = '${appDir.path}/${VllmConfig.modelsDirectory}';

      final dir = Directory(_modelsDirectory!);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      debugPrint('Models directory: $_modelsDirectory');
    } catch (e) {
      debugPrint('Error setting up models directory: $e');
    }
  }

  /// Cargar modelos instalados desde disco
  Future<void> _loadInstalledModels() async {
    _isLoading = true;
    notifyListeners();

    try {
      if (_modelsDirectory == null) return;

      final dir = Directory(_modelsDirectory!);
      if (!await dir.exists()) {
        _installedModels = [];
        return;
      }

      final entities = await dir.list().toList();
      final modelDirs = entities.whereType<Directory>();

      _installedModels = [];

      for (final modelDir in modelDirs) {
        final modelName = modelDir.path.split(Platform.pathSeparator).last;

        // Verificar si el modelo está completo
        final configFile = File('${modelDir.path}/config.json');
        final isComplete = await configFile.exists();

        final stat = await modelDir.stat();
        final model = LocalModel(
          id: modelName,
          name: modelName,
          localPath: modelDir.path,
          status: isComplete ? ModelStatus.ready : ModelStatus.error,
          type: _detectModelType(modelName),
          lastUpdated: stat.modified,
        );

        _installedModels.add(model);
      }

      // Guardar en preferencias
      await _saveInstalledModels();
    } catch (e) {
      debugPrint('Error loading installed models: $e');
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Detectar tipo de modelo por nombre
  ModelType _detectModelType(String modelName) {
    final name = modelName.toLowerCase();
    if (name.contains('vision') ||
        name.contains('vl') ||
        name.contains('pixtral')) {
      return ModelType.multimodal;
    }
    if (name.contains('embed')) {
      return ModelType.embedding;
    }
    return ModelType.textOnly;
  }

  /// Guardar lista de modelos instalados en preferencias
  Future<void> _saveInstalledModels() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final modelsJson = _installedModels.map((m) => m.toJson()).toList();
      await prefs.setString('installed_models', modelsJson.toString());
    } catch (e) {
      debugPrint('Error saving installed models: $e');
    }
  }

  /// Descargar modelo desde HuggingFace
  Future<bool> downloadModel(LocalModel model) async {
    if (_downloadingModel != null) {
      _error = 'Ya hay una descarga en progreso';
      notifyListeners();
      return false;
    }

    _downloadingModel = model.copyWith(status: ModelStatus.downloading);
    _cancelToken = CancelToken();
    notifyListeners();

    try {
      final modelDir = '$_modelsDirectory/${model.id}';
      final dir = Directory(modelDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // Descargar archivos del modelo
      final filesToDownload =
          await _getModelFiles(model.huggingFaceId ?? model.id);

      int totalFiles = filesToDownload.length;
      int downloadedFiles = 0;

      for (final file in filesToDownload) {
        if (_cancelToken?.isCancelled ?? false) {
          throw Exception('Descarga cancelada');
        }

        final success = await _downloadFile(
          model.huggingFaceId ?? model.id,
          file,
          modelDir,
          (received, total) {
            // Actualizar progreso
            final fileProgress = total > 0 ? received / total : 0;
            final overallProgress =
                (downloadedFiles + fileProgress) / totalFiles;

            _downloadingModel = _downloadingModel!.copyWith(
              downloadProgress: overallProgress,
              downloadedBytes: received,
              downloadSpeed: _calculateSpeed(received),
            );
            notifyListeners();
          },
        );

        if (success) {
          downloadedFiles++;
        }
      }

      // Marcar como completado
      final installedModel = model.copyWith(
        status: ModelStatus.ready,
        localPath: modelDir,
        downloadProgress: 1.0,
        lastUpdated: DateTime.now(),
      );

      _installedModels.add(installedModel);
      await _saveInstalledModels();

      _downloadingModel = null;
      notifyListeners();

      return true;
    } catch (e) {
      debugPrint('Error downloading model: $e');
      _error = e.toString();

      _downloadingModel = _downloadingModel?.copyWith(
        status: ModelStatus.error,
        errorMessage: e.toString(),
      );
      notifyListeners();

      return false;
    }
  }

  /// Obtener lista de archivos a descargar for a model
  Future<List<String>> _getModelFiles(String modelId) async {
    // Archivos esenciales para la mayoría de modelos
    return [
      'config.json',
      'tokenizer.json',
      'tokenizer.model',
      'tokenizer_config.json',
      'special_tokens_map.json',
      'pytorch_model.bin',
      'model.safetensors',
      'pytorch_model.bin.index.json',
      'model.safetensors.index.json',
    ];
  }

  /// Descargar un archivo individual
  Future<bool> _downloadFile(
    String modelId,
    String filename,
    String savePath,
    void Function(int received, int total) onProgress,
  ) async {
    try {
      final url = 'https://huggingface.co/$modelId/resolve/main/$filename';
      final saveFile = File('$savePath/$filename');

      await _dio.download(
        url,
        saveFile.path,
        cancelToken: _cancelToken,
        onReceiveProgress: onProgress,
        options: Options(
          receiveTimeout: const Duration(hours: 2),
          sendTimeout: const Duration(minutes: 30),
        ),
      );

      return true;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        throw Exception('Descarga cancelada');
      }
      // Algunos archivos pueden no existir, no es error crítico
      debugPrint('File $filename not found or error: $e');
      return false;
    } catch (e) {
      debugPrint('Error downloading $filename: $e');
      return false;
    }
  }

  double? _calculateSpeed(int bytesReceived) {
    // Simplificado: retornar MB/s estimado
    return bytesReceived / (1024 * 1024);
  }

  /// Cancelar descarga actual
  void cancelDownload() {
    _cancelToken?.cancel('Usuario canceló la descarga');
    _downloadingModel = null;
    notifyListeners();
  }

  /// Eliminar modelo instalado
  Future<bool> deleteModel(LocalModel model) async {
    try {
      if (model.localPath == null) return false;

      final dir = Directory(model.localPath!);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }

      _installedModels.removeWhere((m) => m.id == model.id);
      await _saveInstalledModels();
      notifyListeners();

      return true;
    } catch (e) {
      debugPrint('Error deleting model: $e');
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Obtener espacio usado por modelos
  Future<int> getUsedSpace() async {
    if (_modelsDirectory == null) return 0;

    try {
      final dir = Directory(_modelsDirectory!);
      if (!await dir.exists()) return 0;

      int totalSize = 0;
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }
      return totalSize;
    } catch (e) {
      return 0;
    }
  }

  /// Formatear tamaño en GB/MB
  String formatSize(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    } else if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    } else {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    }
  }

  /// Verificar si un modelo es compatible con el hardware
  Future<bool> isModelCompatible(LocalModel model) async {
    final hardware = await HardwareDetectorService.getHardwareInfo();

    if (model.requiredVram != null && hardware.hasGPU) {
      if (hardware.gpuVRAM != null && hardware.gpuVRAM! < model.requiredVram!) {
        return false;
      }
    }

    if (model.requiredRam != null) {
      if (hardware.systemRAM < model.requiredRam!) {
        return false;
      }
    }

    return true;
  }

  /// Obtener modelos recomendados para el hardware actual
  Future<List<LocalModel>> getRecommendedModels() async {
    final hardware = await HardwareDetectorService.getHardwareInfo();
    final recommendedIds = hardware.recommendedModels;

    return _installedModels
        .where((m) => recommendedIds
            .any((r) => m.id.toLowerCase().contains(r.toLowerCase())))
        .toList();
  }

  @override
  void dispose() {
    _dio.close();
    super.dispose();
  }
}
