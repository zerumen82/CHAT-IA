import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/local_model.dart';
import '../config/vllm_config.dart';

/// Servicio para obtener catálogo de modelos online dinámicamente
/// Consulta HuggingFace Hub API para detectar nuevos modelos disponibles
class ModelCatalogService with ChangeNotifier {
  // Cache de modelos disponibles
  List<LocalModel> _cachedModels = [];
  List<LocalModel> get cachedModels => _cachedModels;

  // Estado de carga
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  // Timestamp de última actualización
  DateTime? _lastUpdate;
  DateTime? get lastUpdate => _lastUpdate;

  // Error si lo hay
  String? _error;
  String? get error => _error;

  // Si hay conexión a internet
  bool _isOnline = true;
  bool get isOnline => _isOnline;

  // API de HuggingFace
  static const String _huggingFaceApi = 'https://huggingface.co/api';

  // Tags de modelos uncensored preferidos
  static const List<String> _uncensoredTags = [
    'uncensored',
    'dolphin',
    'openhermes',
    'nous-hermes',
    'wizardlm',
    'wizard',
  ];

  // Tags de modelos multimodales
  static const List<String> _multimodalTags = [
    'vision',
    'image-text-to-text',
    'multimodal',
    'vl',
    'pixtral',
  ];

  ModelCatalogService() {
    _loadCachedData();
    // Actualizar catálogo al iniciar
    refreshCatalog();
  }

  /// Cargar datos en caché desde almacenamiento local
  Future<void> _loadCachedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString('model_catalog_cache');
      final lastUpdateStr = prefs.getString('model_catalog_last_update');

      if (cachedJson != null) {
        final List<dynamic> modelsJson = json.decode(cachedJson);
        _cachedModels = modelsJson
            .map((m) => LocalModel.fromJson(m as Map<String, dynamic>))
            .toList();
      }

      if (lastUpdateStr != null) {
        _lastUpdate = DateTime.parse(lastUpdateStr);
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Error loading cached catalog: $e');
    }
  }

  /// Guardar datos en caché
  Future<void> _saveCachedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final modelsJson = _cachedModels.map((m) => m.toJson()).toList();
      await prefs.setString('model_catalog_cache', json.encode(modelsJson));
      if (_lastUpdate != null) {
        await prefs.setString(
            'model_catalog_last_update', _lastUpdate!.toIso8601String());
      }
    } catch (e) {
      debugPrint('Error saving cached catalog: $e');
    }
  }

  /// Refrescar catálogo desde APIs online
  Future<void> refreshCatalog() async {
    if (_isLoading) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Verificar conexión
      final models = await _fetchModelsFromHuggingFace();

      if (models.isNotEmpty) {
        _cachedModels = models;
        _lastUpdate = DateTime.now();
        _isOnline = true;
        await _saveCachedData();
      } else {
        // Si no hay modelos, usar caché
        _isOnline = false;
      }
    } catch (e) {
      debugPrint('Error refreshing catalog: $e');
      _error = e.toString();
      _isOnline = false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Obtener modelos desde HuggingFace Hub API
  Future<List<LocalModel>> _fetchModelsFromHuggingFace() async {
    final models = <LocalModel>[];

    try {
      // Buscar modelos de texto generativo
      final textModels = await _searchModels(
        task: 'text-generation',
        limit: 50,
      );
      models.addAll(textModels);

      // Buscar modelos multimodales
      final multimodalModels = await _searchModels(
        task: 'image-text-to-text',
        limit: 20,
      );
      models.addAll(multimodalModels);

      // Buscar modelos uncensored específicos
      for (final tag in _uncensoredTags) {
        final uncensoredModels = await _searchModels(
          tag: tag,
          limit: 10,
        );
        models.addAll(uncensoredModels);
      }

      // Eliminar duplicados por ID
      final uniqueModels = <String, LocalModel>{};
      for (final model in models) {
        uniqueModels[model.id] = model;
      }

      return uniqueModels.values.toList()
        ..sort((a, b) => (b.downloads ?? 0).compareTo(a.downloads ?? 0));
    } catch (e) {
      debugPrint('Error fetching from HuggingFace: $e');
      rethrow;
    }
  }

  /// Buscar modelos con filtros específicos
  Future<List<LocalModel>> _searchModels({
    String? task,
    String? tag,
    int limit = 20,
  }) async {
    try {
      final queryParams = <String, String>{
        'limit': limit.toString(),
        'sort': 'downloads',
        'direction': '-1',
      };

      if (task != null) {
        queryParams['filter'] = task;
      }
      if (tag != null) {
        queryParams['search'] = tag;
      }

      final uri = Uri.parse('$_huggingFaceApi/models')
          .replace(queryParameters: queryParams);

      final response = await http.get(uri).timeout(
            const Duration(seconds: 30),
          );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((m) => _parseHuggingFaceModel(m)).toList();
      }

      return [];
    } catch (e) {
      debugPrint('Error searching models: $e');
      return [];
    }
  }

  /// Parsear modelo desde respuesta de HuggingFace
  LocalModel _parseHuggingFaceModel(Map<String, dynamic> data) {
    final modelId =
        data['id'] as String? ?? data['_id'] as String? ?? 'unknown';
    final tags = (data['tags'] as List<dynamic>?)?.cast<String>() ?? [];
    final downloads = data['downloads'] as int?;
    final likes = data['likes'] as int?;

    // Detectar si es multimodal
    final isMultimodal = tags.any((t) => _multimodalTags
        .any((mt) => t.toLowerCase().contains(mt.toLowerCase())));

    // Detectar si es uncensored
    final isUncensored = tags.any((t) => _uncensoredTags
        .any((ut) => t.toLowerCase().contains(ut.toLowerCase())));

    // Intentar obtener tamaño real desde los datos del modelo
    int? sizeBytes;
    String? sizeFormatted;
    double? requiredVram;

    // HuggingFace a veces proporciona 'library_name' y 'model_size'
    final modelSize = data['model_size'] as int?;
    if (modelSize != null) {
      sizeBytes = modelSize;
      sizeFormatted = _formatSize(modelSize);
    } else {
      // Estimar tamaño basado en el nombre (más conservador)
      final nameLower = modelId.toLowerCase();

      // Detectar si es cuantizado (GGUF, GPTQ, AWQ)
      final isQuantized = nameLower.contains('gguf') ||
          nameLower.contains('gptq') ||
          nameLower.contains('awq') ||
          nameLower.contains('q4') ||
          nameLower.contains('q5') ||
          nameLower.contains('q8');

      if (nameLower.contains('70b')) {
        // 70B cuantizado es ~25-40GB, full es ~140GB
        sizeBytes = isQuantized
            ? (35 * 1024 * 1024 * 1024)
            : (140 * 1024 * 1024 * 1024);
        sizeFormatted = isQuantized ? '~35 GB (quant)' : '~140 GB (full)';
        requiredVram = isQuantized ? 24.0 : 80.0;
      } else if (nameLower.contains('34b') || nameLower.contains('35b')) {
        sizeBytes =
            isQuantized ? (18 * 1024 * 1024 * 1024) : (70 * 1024 * 1024 * 1024);
        sizeFormatted = isQuantized ? '~18 GB (quant)' : '~70 GB (full)';
        requiredVram = isQuantized ? 12.0 : 40.0;
      } else if (nameLower.contains('22b')) {
        sizeBytes =
            isQuantized ? (12 * 1024 * 1024 * 1024) : (45 * 1024 * 1024 * 1024);
        sizeFormatted = isQuantized ? '~12 GB (quant)' : '~45 GB (full)';
        requiredVram = isQuantized ? 8.0 : 24.0;
      } else if (nameLower.contains('8x7b') || nameLower.contains('mixtral')) {
        sizeBytes =
            isQuantized ? (22 * 1024 * 1024 * 1024) : (93 * 1024 * 1024 * 1024);
        sizeFormatted = isQuantized ? '~22 GB (quant)' : '~93 GB (full)';
        requiredVram = isQuantized ? 12.0 : 48.0;
      } else if (nameLower.contains('13b') || nameLower.contains('14b')) {
        sizeBytes =
            isQuantized ? (7 * 1024 * 1024 * 1024) : (26 * 1024 * 1024 * 1024);
        sizeFormatted = isQuantized ? '~7 GB (quant)' : '~26 GB (full)';
        requiredVram = isQuantized ? 6.0 : 16.0;
      } else if (nameLower.contains('11b') || nameLower.contains('12b')) {
        sizeBytes =
            isQuantized ? (6 * 1024 * 1024 * 1024) : (24 * 1024 * 1024 * 1024);
        sizeFormatted = isQuantized ? '~6 GB (quant)' : '~24 GB (full)';
        requiredVram = isQuantized ? 6.0 : 14.0;
      } else if (nameLower.contains('7b') || nameLower.contains('8b')) {
        // 7B/8B cuantizado es ~4-5GB, full es ~15-16GB
        sizeBytes =
            isQuantized ? (4 * 1024 * 1024 * 1024) : (16 * 1024 * 1024 * 1024);
        sizeFormatted = isQuantized ? '~4 GB (quant)' : '~16 GB (full)';
        requiredVram = isQuantized ? 4.0 : 10.0;
      } else if (nameLower.contains('3b') || nameLower.contains('4b')) {
        sizeBytes =
            isQuantized ? (2 * 1024 * 1024 * 1024) : (8 * 1024 * 1024 * 1024);
        sizeFormatted = isQuantized ? '~2 GB (quant)' : '~8 GB (full)';
        requiredVram = isQuantized ? 2.0 : 6.0;
      } else if (nameLower.contains('1b') ||
          nameLower.contains('2b') ||
          nameLower.contains('0.5b')) {
        sizeBytes =
            isQuantized ? (1 * 1024 * 1024 * 1024) : (4 * 1024 * 1024 * 1024);
        sizeFormatted = isQuantized ? '~1 GB (quant)' : '~4 GB (full)';
        requiredVram = isQuantized ? 1.0 : 4.0;
      } else {
        // Modelo sin indicación de tamaño - marcar como desconocido
        sizeFormatted = 'Tamaño desconocido';
      }
    }

    return LocalModel(
      id: modelId,
      name: modelId.split('/').last,
      huggingFaceId: modelId,
      status: ModelStatus.notInstalled,
      type: isMultimodal ? ModelType.multimodal : ModelType.textOnly,
      sizeBytes: sizeBytes,
      sizeFormatted: sizeFormatted,
      requiredVram: requiredVram,
      isUncensored: isUncensored,
      supportsImages: isMultimodal,
      tags: tags,
      downloads: downloads,
      rating: likes != null ? likes / 100.0 : null,
      author: modelId.split('/').first,
    );
  }

  /// Formatear tamaño en bytes a formato legible
  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// Filtrar modelos por hardware disponible
  List<LocalModel> filterByHardware({
    required double availableVram,
    required double availableRam,
    bool preferUncensored = true,
    bool includeMultimodal = true,
  }) {
    var filtered = _cachedModels.where((model) {
      // Verificar requisitos de VRAM/RAM
      if (model.requiredVram != null && model.requiredVram! > availableVram) {
        return false;
      }
      if (model.requiredRam != null && model.requiredRam! > availableRam) {
        return false;
      }
      // Filtrar multimodal si no se quiere
      if (!includeMultimodal && model.supportsImages) {
        return false;
      }
      return true;
    }).toList();

    // Ordenar por preferencia uncensored
    if (preferUncensored) {
      filtered.sort((a, b) {
        if (a.isUncensored && !b.isUncensored) return -1;
        if (!a.isUncensored && b.isUncensored) return 1;
        return (b.downloads ?? 0).compareTo(a.downloads ?? 0);
      });
    }

    return filtered;
  }

  /// Obtener modelos uncensored
  List<LocalModel> get uncensoredModels =>
      _cachedModels.where((m) => m.isUncensored).toList();

  /// Obtener modelos multimodales
  List<LocalModel> get multimodalModels =>
      _cachedModels.where((m) => m.supportsImages).toList();

  /// Obtener modelos recomendados por hardware
  List<LocalModel> getRecommendedModels({
    double vram = 8.0,
    double ram = 16.0,
    bool preferUncensored = true,
  }) {
    return filterByHardware(
      availableVram: vram,
      availableRam: ram,
      preferUncensored: preferUncensored,
    ).take(10).toList();
  }

  /// Buscar modelos por texto
  List<LocalModel> searchModels(String query) {
    final queryLower = query.toLowerCase();
    return _cachedModels.where((m) {
      return m.id.toLowerCase().contains(queryLower) ||
          m.name.toLowerCase().contains(queryLower) ||
          m.tags.any((t) => t.toLowerCase().contains(queryLower));
    }).toList();
  }

  /// Verificar si el catálogo necesita actualización
  bool get needsUpdate {
    if (_lastUpdate == null) return true;
    final timeSinceUpdate = DateTime.now().difference(_lastUpdate!);
    return timeSinceUpdate > VllmConfig.modelCacheExpiry;
  }

  /// Obtener información de un modelo específico
  Future<LocalModel?> getModelInfo(String modelId) async {
    try {
      final uri = Uri.parse('$_huggingFaceApi/models/$modelId');
      final response = await http.get(uri).timeout(
            const Duration(seconds: 15),
          );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return _parseHuggingFaceModel(data as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      debugPrint('Error getting model info: $e');
      return null;
    }
  }
}
