import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../models/local_model.dart';
import 'hardware_detector_service.dart';

/// Estado del servidor vLLM
enum VllmStatus {
  notInstalled,
  installing,
  installed,
  starting,
  running,
  stopping,
  error,
}

/// Información del servidor vLLM
class VllmServerInfo {
  final VllmStatus status;
  final String? version;
  final String? modelLoaded;
  final int? port;
  final String? errorMessage;
  final String? pythonPath;
  final String? vllmPath;

  const VllmServerInfo({
    required this.status,
    this.version,
    this.modelLoaded,
    this.port,
    this.errorMessage,
    this.pythonPath,
    this.vllmPath,
  });

  VllmServerInfo copyWith({
    VllmStatus? status,
    String? version,
    String? modelLoaded,
    int? port,
    String? errorMessage,
    String? pythonPath,
    String? vllmPath,
  }) {
    return VllmServerInfo(
      status: status ?? this.status,
      version: version ?? this.version,
      modelLoaded: modelLoaded ?? this.modelLoaded,
      port: port ?? this.port,
      errorMessage: errorMessage ?? this.errorMessage,
      pythonPath: pythonPath ?? this.pythonPath,
      vllmPath: vllmPath ?? this.vllmPath,
    );
  }
}

/// Servicio para gestionar vLLM integrado
/// SINGLETON: El estado persiste aunque se cierre la ventana
class VllmService extends ChangeNotifier {
  static VllmService? _instance;

  final String defaultPort = '8000';

  VllmServerInfo _serverInfo =
      const VllmServerInfo(status: VllmStatus.notInstalled);
  VllmServerInfo get serverInfo => _serverInfo;

  Process? _vllmProcess;
  String _logs = '';
  String get logs => _logs;

  // Flag para saber si ya se inicializó (evitar reinicializaciones)
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  // Flag para saber si hay descarga en progreso
  bool _isDownloading = false;
  bool get isDownloading => _isDownloading;

  // ID del modelo que se está descargando (persistido)
  String? _downloadingModelId;
  String? get downloadingModelId => _downloadingModelId;

  List<LocalModel> _downloadedModels = [];
  List<LocalModel> get downloadedModels => _downloadedModels;

  LocalModel? _modelDownloading;
  double _downloadProgress = 0.0;
  LocalModel? get modelDownloading => _modelDownloading;
  double get downloadProgress => _downloadProgress;

  HardwareInfo? _hardwareInfo;
  HardwareInfo? get hardwareInfo => _hardwareInfo;

  String? _modelsDirectory;
  String? get modelsDirectory => _modelsDirectory;

  bool _isCheckingInstallation = false;
  bool get isCheckingInstallation => _isCheckingInstallation;

  Timer? _healthCheckTimer;

  // Archivo de logs persistente
  File? _logFile;

  VllmService._();

  static VllmService get instance {
    _instance ??= VllmService._();
    return _instance!;
  }

  /// Inicializar servicio (solo una vez)
  Future<void> initialize() async {
    // Evitar reinicializaciones
    if (_isInitialized) {
      debugPrint('VllmService ya inicializado, saltando...');
      return;
    }

    _isCheckingInstallation = true;
    notifyListeners();

    try {
      // Obtener directorio de modelos
      final appDir = await getApplicationSupportDirectory();
      _modelsDirectory = '${appDir.path}/lightchat_models';
      await Directory(_modelsDirectory!).create(recursive: true);

      // Inicializar archivo de logs persistente
      _logFile = File('${_modelsDirectory}/vllm_logs.txt');

      // Cargar logs previos
      await _loadLogs();

      debugPrint('📁 Directorio de modelos: $_modelsDirectory');

      // Cargar estado de descarga previo
      await _loadDownloadState();

      // Detectar hardware
      _hardwareInfo = await HardwareDetectorService.getHardwareInfo();

      // Verificar instalación de vLLM (sin resetear logs)
      await checkVllmInstallation(resetLogs: false);

      // Cargar modelos descargados
      await _loadDownloadedModels();

      // Limpiar descargas incompletas
      await _cleanIncompleteDownloads();

      // Iniciar health check si está corriendo
      _startHealthCheck();

      // Marcar como inicializado
      _isInitialized = true;
    } catch (e) {
      debugPrint('Error initializing VllmService: $e');
      _serverInfo = VllmServerInfo(
        status: VllmStatus.error,
        errorMessage: 'Error al inicializar: $e',
      );
    } finally {
      _isCheckingInstallation = false;
      notifyListeners();
    }
  }

  /// Cargar logs desde archivo
  Future<void> _loadLogs() async {
    try {
      if (_logFile != null && await _logFile!.exists()) {
        _logs = await _logFile!.readAsString();
        debugPrint('📁 Logs cargados: ${_logs.length} caracteres');
      }
    } catch (e) {
      debugPrint('Error cargando logs: $e');
    }
  }

  /// Guardar logs en archivo
  Future<void> _saveLogs() async {
    try {
      if (_logFile != null) {
        // Solo guardar los últimos 50KB de logs para no crecer infinitamente
        String logsToSave = _logs;
        if (logsToSave.length > 50000) {
          logsToSave = logsToSave.substring(logsToSave.length - 50000);
        }
        await _logFile!.writeAsString(logsToSave);
      }
    } catch (e) {
      debugPrint('Error guardando logs: $e');
    }
  }

  /// Añadir línea de log y guardar
  void _addLog(String line) {
    _logs += line;
    notifyListeners();
    // Guardar de forma asíncrona sin bloquear
    _saveLogs();
  }

  /// Cargar estado de descarga previo
  Future<void> _loadDownloadState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _downloadingModelId = prefs.getString('downloading_model_id');
      _downloadProgress = prefs.getDouble('download_progress') ?? 0.0;
      _isDownloading = prefs.getBool('is_downloading') ?? false;

      if (_isDownloading && _downloadingModelId != null) {
        _logs +=
            '\n[INFO] Descarga previa detectada: $_downloadingModelId (${(_downloadProgress * 100).toStringAsFixed(1)}%)\n';
        _logs +=
            '[INFO] Si la descarga falló, puedes eliminar el modelo parcial desde DESCARGADOS\n';
      }
    } catch (e) {
      debugPrint('Error cargando estado de descarga: $e');
    }
  }

  /// Guardar estado de descarga
  Future<void> _saveDownloadState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_downloadingModelId != null) {
        await prefs.setString('downloading_model_id', _downloadingModelId!);
      } else {
        await prefs.remove('downloading_model_id');
      }
      await prefs.setDouble('download_progress', _downloadProgress);
      await prefs.setBool('is_downloading', _isDownloading);
    } catch (e) {
      debugPrint('Error guardando estado de descarga: $e');
    }
  }

  /// Limpiar descargas incompletas al iniciar
  Future<void> _cleanIncompleteDownloads() async {
    try {
      final modelsDir = Directory(_modelsDirectory!);
      if (!await modelsDir.exists()) return;

      // Buscar carpetas de modelos temporales o scripts de descarga
      await for (final entity in modelsDir.list()) {
        if (entity is File) {
          final name = entity.path.split(Platform.pathSeparator).last;
          // Eliminar scripts de descarga temporales
          if (name.startsWith('download_') && name.endsWith('.py')) {
            try {
              await entity.delete();
              debugPrint('🧹 Limpiado script temporal: $name');
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      debugPrint('Error limpiando descargas incompletas: $e');
    }
  }

  /// Escanear modelos en disco (incluyendo parciales/fallidos)
  Future<List<Map<String, dynamic>>> scanModelsOnDisk() async {
    final modelsOnDisk = <Map<String, dynamic>>[];

    try {
      final modelsDir = Directory(_modelsDirectory!);
      if (!await modelsDir.exists()) return modelsOnDisk;

      await for (final entity in modelsDir.list()) {
        if (entity is Directory) {
          final dirName = entity.path.split(Platform.pathSeparator).last;

          // Ignorar archivos especiales
          if (dirName.startsWith('.') || dirName == 'vllm_logs.txt') continue;

          // Calcular tamaño del directorio
          int totalSize = 0;
          int fileCount = 0;

          await for (final file in entity.list(recursive: true)) {
            if (file is File) {
              try {
                totalSize += await file.length();
                fileCount++;
              } catch (_) {}
            }
          }

          // Verificar si parece un modelo completo (tiene config.json o model files)
          bool isComplete = false;
          final configFile = File('${entity.path}/config.json');
          final modelFile = File('${entity.path}/model.safetensors');
          final ggufFile = File('${entity.path}${Platform.pathSeparator}')
              .path; // Buscar archivos .gguf

          if (await configFile.exists()) {
            isComplete = true;
          } else {
            // Buscar archivos GGUF
            await for (final f in entity.list()) {
              if (f is File && f.path.toLowerCase().endsWith('.gguf')) {
                isComplete = true;
                break;
              }
            }
          }

          // Verificar si está en la lista de descargados
          final isRegistered = _downloadedModels.any((m) =>
              m.localPath == entity.path ||
              m.id.replaceAll('/', '_') == dirName);

          modelsOnDisk.add({
            'path': entity.path,
            'name': dirName,
            'size': totalSize,
            'sizeFormatted': _formatBytes(totalSize),
            'fileCount': fileCount,
            'isComplete': isComplete,
            'isRegistered': isRegistered,
            'isPartial': !isComplete,
            'isOrphan': !isRegistered,
          });
        }
      }
    } catch (e) {
      debugPrint('Error escaneando modelos en disco: $e');
    }

    return modelsOnDisk;
  }

  /// Eliminar modelo del disco (por ruta)
  Future<bool> deleteModelByPath(String path) async {
    try {
      final dir = Directory(path);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        debugPrint('🗑️ Eliminado: $path');

        // Actualizar lista de modelos descargados
        _downloadedModels.removeWhere((m) => m.localPath == path);
        await _saveDownloadedModels();
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error eliminando modelo: $e');
      return false;
    }
  }

  /// Sincronizar modelos descargados con lo que hay en disco
  Future<void> syncDownloadedModels() async {
    try {
      final modelsOnDisk = await scanModelsOnDisk();

      // Eliminar de la lista los que no existen en disco
      _downloadedModels.removeWhere((model) {
        if (model.localPath == null) return true;
        return !Directory(model.localPath!).existsSync();
      });

      // Añadir modelos completos que no están registrados
      for (final diskModel in modelsOnDisk) {
        if (diskModel['isComplete'] == true && diskModel['isOrphan'] == true) {
          // Crear modelo para el huérfano
          final model = LocalModel(
            id: diskModel['name'],
            name: diskModel['name'],
            status: ModelStatus.ready,
            localPath: diskModel['path'],
            sizeBytes: diskModel['size'],
            sizeFormatted: diskModel['sizeFormatted'],
          );
          _downloadedModels.add(model);
        }
      }

      await _saveDownloadedModels();
      notifyListeners();
    } catch (e) {
      debugPrint('Error sincronizando modelos: $e');
    }
  }

  /// Obtener información de espacio usado por modelos
  Future<Map<String, dynamic>> getStorageInfo() async {
    try {
      final modelsDir = Directory(_modelsDirectory!);
      if (!await modelsDir.exists()) {
        return {'totalSize': 0, 'modelCount': 0, 'path': _modelsDirectory};
      }

      int totalSize = 0;
      int modelCount = 0;

      await for (final entity in modelsDir.list()) {
        if (entity is Directory) {
          modelCount++;
          await for (final file in entity.list(recursive: true)) {
            if (file is File) {
              totalSize += await file.length();
            }
          }
        }
      }

      return {
        'totalSize': totalSize,
        'totalSizeFormatted': _formatBytes(totalSize),
        'modelCount': modelCount,
        'path': _modelsDirectory,
      };
    } catch (e) {
      return {
        'totalSize': 0,
        'modelCount': 0,
        'path': _modelsDirectory,
        'error': e.toString()
      };
    }
  }

  /// Formatear bytes a formato legible
  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// Abrir carpeta de modelos en el explorador
  Future<bool> openModelsFolder() async {
    try {
      if (_modelsDirectory == null) return false;

      if (Platform.isWindows) {
        await Process.run('explorer', [_modelsDirectory!]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [_modelsDirectory!]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [_modelsDirectory!]);
      }
      return true;
    } catch (e) {
      debugPrint('Error abriendo carpeta: $e');
      return false;
    }
  }

  /// Eliminar modelo parcialmente descargado (limpieza manual)
  Future<bool> cleanPartialDownload(String modelId) async {
    try {
      final modelDir = '$_modelsDirectory/${modelId.replaceAll('/', '_')}';
      final dir = Directory(modelDir);

      if (await dir.exists()) {
        await dir.delete(recursive: true);
        debugPrint('🧹 Eliminado modelo parcial: $modelId');

        // Actualizar lista
        _downloadedModels.removeWhere((m) => m.id == modelId);
        await _saveDownloadedModels();
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error limpiando modelo parcial: $e');
      return false;
    }
  }

  /// Buscar Python en el sistema
  Future<String?> _findPython() async {
    // Lista de posibles ejecutables de Python (orden de preferencia)
    final pythonCommands = ['python', 'python3', 'py'];

    for (final cmd in pythonCommands) {
      final result = await _runCommand(cmd, ['--version']);
      if (result.exitCode == 0) {
        debugPrint('Python encontrado: $cmd');
        return cmd;
      }
    }

    // Buscar en variables de entorno PATH
    final envPath = Platform.environment['PATH'] ?? '';
    final pathSeparator = Platform.isWindows ? ';' : ':';
    final paths = envPath.split(pathSeparator);

    for (final path in paths) {
      if (path.isEmpty) continue;

      // Buscar ejecutables de Python en cada directorio del PATH
      final pythonNames = Platform.isWindows
          ? ['python.exe', 'python3.exe', 'py.exe']
          : ['python', 'python3'];

      for (final pythonName in pythonNames) {
        final pythonPath = '$path${Platform.pathSeparator}$pythonName';
        if (await File(pythonPath).exists()) {
          debugPrint('Python encontrado en PATH: $pythonPath');
          return pythonPath;
        }
      }
    }

    // Buscar en rutas comunes de Windows (solo si estamos en Windows)
    if (Platform.isWindows) {
      // Obtener directorio de usuario dinámicamente
      final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';

      final commonPaths = <String>[
        if (localAppData.isNotEmpty) ...[
          '$localAppData\\Programs\\Python\\Python312\\python.exe',
          '$localAppData\\Programs\\Python\\Python311\\python.exe',
          '$localAppData\\Programs\\Python\\Python310\\python.exe',
          '$localAppData\\Programs\\Python\\Python39\\python.exe',
        ],
        'C:\\Python312\\python.exe',
        'C:\\Python311\\python.exe',
        'C:\\Python310\\python.exe',
        'C:\\Python39\\python.exe',
      ];

      for (final path in commonPaths) {
        if (await File(path).exists()) {
          debugPrint('Python encontrado en: $path');
          return path;
        }
      }
    }

    return null;
  }

  /// Verificar instalación de vLLM (público para permitir refresh)
  Future<void> checkVllmInstallation({bool resetLogs = true}) async {
    try {
      if (resetLogs) {
        _logs = 'Buscando Python...\n';
      } else {
        _logs += '\n--- Verificando instalación ---\nBuscando Python...\n';
      }
      notifyListeners();

      // Buscar Python
      String? pythonPath = await _findPython();

      if (pythonPath == null) {
        _logs += 'Python no encontrado en el sistema\n';
        _serverInfo = VllmServerInfo(
          status: VllmStatus.notInstalled,
          errorMessage:
              'Python no está instalado. Instala Python 3.10+ desde python.org',
        );
        notifyListeners();
        return;
      }

      _logs += 'Python encontrado: $pythonPath\n';

      // Verificar pip
      final pipResult =
          await _runCommand(pythonPath, ['-m', 'pip', '--version']);
      if (pipResult.exitCode != 0) {
        _logs += 'pip no disponible\n';
        _serverInfo = VllmServerInfo(
          status: VllmStatus.notInstalled,
          errorMessage: 'pip no está disponible. Reinstala Python con pip',
          pythonPath: pythonPath,
        );
        notifyListeners();
        return;
      }

      _logs += 'pip encontrado\n';
      notifyListeners();

      // Verificar vLLM
      _logs += 'Verificando vLLM...\n';
      notifyListeners();

      final vllmResult = await _runCommand(
          pythonPath, ['-c', 'import vllm; print(vllm.__version__)']);
      if (vllmResult.exitCode != 0) {
        _logs += 'vLLM no está instalado\n';
        _logs += 'Error: ${vllmResult.stderr}\n';
        _serverInfo = VllmServerInfo(
          status: VllmStatus.notInstalled,
          errorMessage:
              'vLLM no está instalado. Ve a SERVIDOR y pulsa INSTALAR vLLM',
          pythonPath: pythonPath,
        );
        notifyListeners();
        return;
      }

      final version = vllmResult.stdout.toString().trim();
      _logs += 'vLLM version: $version\n';
      notifyListeners();

      // Verificar huggingface_hub
      final hfResult = await _runCommand(pythonPath,
          ['-c', 'import huggingface_hub; print(huggingface_hub.__version__)']);

      if (hfResult.exitCode != 0) {
        _logs += 'Instalando huggingface_hub...\n';
        notifyListeners();

        final hfInstall = await _runCommand(
          pythonPath,
          ['-m', 'pip', 'install', '-U', 'huggingface_hub'],
        );

        if (hfInstall.exitCode == 0) {
          _logs += 'huggingface_hub instalado\n';
        }
      } else {
        _logs += 'huggingface_hub disponible\n';
      }
      notifyListeners();

      _serverInfo = VllmServerInfo(
        status: VllmStatus.installed,
        version: version,
        pythonPath: pythonPath,
        vllmPath: pythonPath,
      );

      // Verificar si hay un servidor corriendo
      await _checkRunningServer();

      notifyListeners();
    } catch (e) {
      debugPrint('Error checking vLLM installation: $e');
      _serverInfo = VllmServerInfo(
        status: VllmStatus.error,
        errorMessage: 'Error al verificar instalación: $e',
      );
      notifyListeners();
    }
  }

  /// Instalar vLLM
  Future<bool> installVllm({VoidCallback? onProgress}) async {
    if (_serverInfo.pythonPath == null) {
      await checkVllmInstallation(resetLogs: false);
    }

    if (_serverInfo.pythonPath == null) {
      _serverInfo = VllmServerInfo(
        status: VllmStatus.error,
        errorMessage: 'Python no encontrado. Instala Python 3.10+ primero.',
      );
      notifyListeners();
      return false;
    }

    _serverInfo = _serverInfo.copyWith(status: VllmStatus.installing);
    _logs = 'Instalando vLLM...\n';
    notifyListeners();

    try {
      // Instalar vLLM con CUDA si hay GPU NVIDIA
      String installCmd = 'vllm';

      if (_hardwareInfo?.supportsCUDA == true) {
        _logs += 'Detectada GPU NVIDIA, instalando con soporte CUDA...\n';
        notifyListeners();
      }

      // Ejecutar instalación
      final result = await _runCommandWithOutput(
        _serverInfo.pythonPath!,
        ['-m', 'pip', 'install', '-U', installCmd, '--no-cache-dir'],
        onOutput: (line) {
          _logs += '$line\n';
          onProgress?.call();
          notifyListeners();
        },
      );

      if (result.exitCode == 0) {
        _logs += '\n¡vLLM instalado correctamente!\n';

        // Instalar huggingface_hub para descargar modelos
        _logs += 'Instalando huggingface_hub...\n';
        notifyListeners();

        final hfResult = await _runCommandWithOutput(
          _serverInfo.pythonPath!,
          ['-m', 'pip', 'install', '-U', 'huggingface_hub', '-q'],
          onOutput: (line) {
            _logs += '$line\n';
            onProgress?.call();
            notifyListeners();
          },
        );

        if (hfResult.exitCode == 0) {
          _logs += 'huggingface_hub instalado correctamente.\n';
        }

        // Verificar instalación
        await checkVllmInstallation();
        return true;
      } else {
        _logs += '\nError al instalar vLLM:\n${result.stderr}\n';
        _serverInfo = VllmServerInfo(
          status: VllmStatus.error,
          errorMessage: 'Error al instalar vLLM',
        );
        notifyListeners();
        return false;
      }
    } catch (e) {
      _logs += '\nError: $e\n';
      _serverInfo = VllmServerInfo(
        status: VllmStatus.error,
        errorMessage: 'Error al instalar: $e',
      );
      notifyListeners();
      return false;
    }
  }

  /// Descargar modelo desde HuggingFace con progreso detallado
  Future<bool> downloadModel(LocalModel model,
      {VoidCallback? onProgress}) async {
    if (_serverInfo.pythonPath == null) {
      _serverInfo = VllmServerInfo(
        status: VllmStatus.error,
        errorMessage: 'Python no encontrado',
      );
      notifyListeners();
      return false;
    }

    _modelDownloading = model;
    _downloadProgress = 0.0;
    _isDownloading = true;
    _downloadingModelId = model.id;
    await _saveDownloadState();
    notifyListeners();

    try {
      _addLog('\n========== NUEVA DESCARGA ==========\n');
      _addLog('Preparando descarga de ${model.huggingFaceId ?? model.id}...\n');

      // Primero verificar/instalar huggingface_hub
      _addLog('Verificando huggingface_hub...\n');

      final hfCheck = await _runCommand(
        _serverInfo.pythonPath!,
        ['-c', 'import huggingface_hub'],
      );

      if (hfCheck.exitCode != 0) {
        _addLog('Instalando huggingface_hub...\n');

        final hfInstall = await _runCommandWithOutput(
          _serverInfo.pythonPath!,
          ['-m', 'pip', 'install', '-U', 'huggingface_hub', 'tqdm', '-q'],
          onOutput: (line) {
            _addLog('$line\n');
          },
        );

        if (hfInstall.exitCode != 0) {
          _addLog('\nError instalando huggingface_hub:\n${hfInstall.stderr}\n');
          _modelDownloading = null;
          _isDownloading = false;
          await _saveDownloadState();
          notifyListeners();
          return false;
        }
        _addLog('huggingface_hub instalado correctamente.\n');
      } else {
        _addLog('huggingface_hub disponible.\n');
      }

      _addLog('\nDescargando modelo ${model.huggingFaceId ?? model.id}...\n');
      if (model.sizeFormatted != null) {
        _addLog('Tamaño estimado: ${model.sizeFormatted}\n');
      }

      final modelDir = '$_modelsDirectory/${model.id.replaceAll('/', '_')}';

      // Crear script de Python para descargar con progreso detallado
      final downloadScript = '''
import sys
import os
from huggingface_hub import snapshot_download, hf_api
from tqdm import tqdm
import threading
import time

model_id = "${model.huggingFaceId ?? model.id}"
local_dir = r"$modelDir"

print(f"MODEL_ID:{model_id}", flush=True)
print(f"LOCAL_DIR:{local_dir}", flush=True)

# Crear directorio si no existe
os.makedirs(local_dir, exist_ok=True)

# Variable para tracking de progreso
current_file = [""]
total_files = [0]
current_file_num = [0]

class ProgressCallback:
    def __init__(self):
        self.last_progress = 0
        
    def __call__(self, repo_info):
        pass

def track_progress():
    """Monitorear progreso de descarga"""
    pass

try:
    print("DOWNLOAD_START:Iniciando descarga...", flush=True)
    
    # Usar snapshot_download con tqdm para progreso
    def progress_callback(repo_id, filename, bytes_downloaded, bytes_total):
        if bytes_total > 0:
            percent = (bytes_downloaded / bytes_total) * 100
            mb_downloaded = bytes_downloaded / (1024 * 1024)
            mb_total = bytes_total / (1024 * 1024)
            print(f"PROGRESS:{percent:.1f}:{mb_downloaded:.1f}:{mb_total:.1f}:{filename}", flush=True)
    
    # Descargar con progreso
    snapshot_download(
        repo_id=model_id,
        local_dir=local_dir,
        resume_download=True,
        etag_timeout=30,
    )
    
    print("DOWNLOAD_COMPLETE:Descarga completada!", flush=True)
    
except Exception as e:
    print(f"ERROR:{type(e).__name__}:{str(e)}", flush=True)
    sys.exit(1)
''';

      // Guardar script temporal
      final scriptPath =
          '$_modelsDirectory/download_${DateTime.now().millisecondsSinceEpoch}.py';
      await File(scriptPath).writeAsString(downloadScript);

      bool hasError = false;
      String errorMsg = '';

      // Ejecutar script de Python
      final result = await _runCommandWithOutput(
        _serverInfo.pythonPath!,
        [scriptPath],
        onOutput: (line) {
          // Parsear líneas de progreso especiales
          if (line.startsWith('PROGRESS:')) {
            final parts = line.substring(9).split(':');
            if (parts.length >= 2) {
              try {
                final percent = double.parse(parts[0]);
                _downloadProgress = percent / 100.0;
                _saveDownloadState(); // Guardar progreso

                if (parts.length >= 4) {
                  final mbDownloaded = parts[1];
                  final mbTotal = parts[2];
                  final filename = parts[3];
                  _addLog(
                      'Descargando: $filename ($mbDownloaded/$mbTotal MB) - ${percent.toStringAsFixed(1)}%\n');
                }
              } catch (_) {}
            }
          } else if (line.startsWith('ERROR:')) {
            hasError = true;
            errorMsg = line.substring(6);
            _addLog('ERROR: $errorMsg\n');
          } else if (line.startsWith('DOWNLOAD_START:')) {
            _addLog('⬇️ Iniciando descarga...\n');
          } else if (line.startsWith('DOWNLOAD_COMPLETE:')) {
            _addLog('✅ Descarga completada!\n');
            _downloadProgress = 1.0;
          } else if (!line.startsWith('MODEL_ID:') &&
              !line.startsWith('LOCAL_DIR:') &&
              line.trim().isNotEmpty) {
            _addLog('$line\n');
          }

          onProgress?.call();
          notifyListeners();
        },
      );

      // Limpiar script temporal
      try {
        await File(scriptPath).delete();
      } catch (_) {}

      if (!hasError && result.exitCode == 0) {
        _addLog('\n✅ ¡Modelo descargado correctamente en:\n$modelDir\n');

        // Agregar a lista de modelos descargados
        final downloadedModel = model.copyWith(
          status: ModelStatus.ready,
          localPath: modelDir,
        );

        _downloadedModels.removeWhere((m) => m.id == model.id);
        _downloadedModels.add(downloadedModel);
        await _saveDownloadedModels();

        _modelDownloading = null;
        _isDownloading = false;
        _downloadingModelId = null;
        _downloadProgress = 1.0;
        await _saveDownloadState();
        notifyListeners();
        return true;
      } else {
        _addLog(
            '\n❌ Error al descargar modelo:\n${errorMsg.isNotEmpty ? errorMsg : result.stderr}\n');
        _modelDownloading = null;
        _isDownloading = false;
        await _saveDownloadState();
        notifyListeners();
        return false;
      }
    } catch (e) {
      _addLog('\n❌ Error: $e\n');
      _modelDownloading = null;
      _isDownloading = false;
      await _saveDownloadState();
      notifyListeners();
      return false;
    }
  }

  /// Iniciar servidor vLLM con un modelo
  Future<bool> startServer(LocalModel model, {String? port}) async {
    if (_serverInfo.status == VllmStatus.running) {
      await stopServer();
    }

    if (_serverInfo.pythonPath == null || model.localPath == null) {
      _serverInfo = VllmServerInfo(
        status: VllmStatus.error,
        errorMessage: 'vLLM o modelo no disponible',
      );
      notifyListeners();
      return false;
    }

    _serverInfo = _serverInfo.copyWith(status: VllmStatus.starting);
    _addLog('\n========== INICIANDO SERVIDOR ==========\n');
    _addLog('Modelo: ${model.name}\n');
    _addLog('Ruta local: ${model.localPath}\n');
    notifyListeners();

    try {
      final serverPort = port ?? defaultPort;

      // Usar la ruta local del modelo si está disponible, sino usar el ID de HuggingFace
      final modelPath = model.localPath ?? model.huggingFaceId ?? model.id;

      _addLog('Usando modelo desde: $modelPath\n');

      // Construir comando de inicio
      final args = [
        '-m',
        'vllm.entrypoints.openai.api_server',
        '--model',
        modelPath,
        '--host',
        '0.0.0.0',
        '--port',
        serverPort,
      ];

      // Agregar parámetros según hardware
      if (_hardwareInfo?.hasGPU == true &&
          _hardwareInfo?.supportsCUDA == true) {
        // Usar GPU
        args.addAll(['--gpu-memory-utilization', '0.9']);
        _addLog('Modo: GPU (CUDA) con 90% memoria\n');
      } else {
        // Usar CPU
        args.addAll(['--device', 'cpu']);
        _addLog('Modo: CPU\n');
      }

      _addLog('Comando: ${_serverInfo.pythonPath} ${args.join(' ')}\n');
      _addLog('Puerto: $serverPort\n');
      _addLog('Esperando a que el servidor esté listo...\n');
      notifyListeners();

      // Iniciar proceso con ventana oculta (usando pythonw si está disponible)
      String pythonExe = _serverInfo.pythonPath!;
      // Intentar usar pythonw.exe para ocultar la ventana de consola
      if (pythonExe.endsWith('python.exe')) {
        final pythonwPath = pythonExe.replaceAll('python.exe', 'pythonw.exe');
        final pythonwFile = File(pythonwPath);
        if (await pythonwFile.exists()) {
          pythonExe = pythonwPath;
          _addLog('Usando pythonw.exe para ventana oculta\n');
        }
      }

      // Iniciar proceso
      _vllmProcess = await Process.start(
        pythonExe,
        args,
        workingDirectory: _modelsDirectory,
      );

      // Capturar salida
      _vllmProcess!.stdout.transform(utf8.decoder).listen((data) {
        _logs += data;
        notifyListeners();
      });

      _vllmProcess!.stderr.transform(utf8.decoder).listen((data) {
        _logs += data;
        notifyListeners();
      });

      // Esperar a que el servidor esté listo
      bool isReady = false;
      for (int i = 0; i < 60; i++) {
        await Future.delayed(const Duration(seconds: 1));
        try {
          final response = await http
              .get(
                Uri.parse('http://localhost:$serverPort/health'),
              )
              .timeout(const Duration(seconds: 2));

          if (response.statusCode == 200) {
            isReady = true;
            break;
          }
        } catch (_) {
          // Servidor aún no listo
        }
      }

      if (isReady) {
        _serverInfo = VllmServerInfo(
          status: VllmStatus.running,
          modelLoaded: model.id,
          port: int.parse(serverPort),
          pythonPath: _serverInfo.pythonPath,
          vllmPath: _serverInfo.vllmPath,
          version: _serverInfo.version,
        );
        _logs += '\n¡Servidor iniciado en puerto $serverPort!\n';
        notifyListeners();
        return true;
      } else {
        _serverInfo = VllmServerInfo(
          status: VllmStatus.error,
          errorMessage: 'El servidor no respondió a tiempo',
        );
        _logs += '\nError: El servidor no respondió a tiempo\n';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _serverInfo = VllmServerInfo(
        status: VllmStatus.error,
        errorMessage: 'Error al iniciar servidor: $e',
      );
      _logs += '\nError: $e\n';
      notifyListeners();
      return false;
    }
  }

  /// Detener servidor vLLM
  Future<void> stopServer() async {
    if (_vllmProcess != null) {
      _serverInfo = _serverInfo.copyWith(status: VllmStatus.stopping);
      notifyListeners();

      try {
        _vllmProcess!.kill(ProcessSignal.sigterm);
        await _vllmProcess!.exitCode.timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            _vllmProcess!.kill(ProcessSignal.sigkill);
            return -1;
          },
        );
      } catch (e) {
        debugPrint('Error stopping vLLM: $e');
      }

      _vllmProcess = null;
    }

    _serverInfo = VllmServerInfo(
      status: VllmStatus.installed,
      pythonPath: _serverInfo.pythonPath,
      vllmPath: _serverInfo.vllmPath,
      version: _serverInfo.version,
    );
    notifyListeners();
  }

  /// Eliminar modelo descargado
  Future<bool> deleteModel(LocalModel model) async {
    if (model.localPath == null) return false;

    try {
      final dir = Directory(model.localPath!);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }

      _downloadedModels.removeWhere((m) => m.id == model.id);
      await _saveDownloadedModels();
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Error deleting model: $e');
      return false;
    }
  }

  /// Verificar servidor corriendo
  Future<void> _checkRunningServer() async {
    try {
      final response = await http
          .get(
            Uri.parse('http://localhost:$defaultPort/v1/models'),
          )
          .timeout(const Duration(seconds: 2));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map &&
            data['data'] is List &&
            (data['data'] as List).isNotEmpty) {
          final modelId = data['data'][0]['id'] as String;
          _serverInfo = _serverInfo.copyWith(
            status: VllmStatus.running,
            modelLoaded: modelId,
            port: int.parse(defaultPort),
          );
        }
      }
    } catch (_) {
      // No hay servidor corriendo
    }
  }

  /// Iniciar health check periódico
  void _startHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer =
        Timer.periodic(const Duration(seconds: 30), (timer) async {
      if (_serverInfo.status == VllmStatus.running) {
        try {
          final response = await http
              .get(
                Uri.parse(
                    'http://localhost:${_serverInfo.port ?? defaultPort}/health'),
              )
              .timeout(const Duration(seconds: 5));

          if (response.statusCode != 200) {
            _serverInfo = _serverInfo.copyWith(
              status: VllmStatus.error,
              errorMessage: 'El servidor no responde correctamente',
            );
            notifyListeners();
          }
        } catch (_) {
          _serverInfo = _serverInfo.copyWith(
            status: VllmStatus.error,
            errorMessage: 'Conexión perdida con el servidor',
          );
          notifyListeners();
        }
      }
    });
  }

  /// Cargar modelos descargados desde caché
  Future<void> _loadDownloadedModels() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final modelsJson = prefs.getString('downloaded_models');

      if (modelsJson != null) {
        final List<dynamic> list = json.decode(modelsJson);
        _downloadedModels = list
            .map((m) => LocalModel.fromJson(m as Map<String, dynamic>))
            .toList();
      }

      // Verificar que los directorios existen
      _downloadedModels.removeWhere((model) {
        if (model.localPath == null) return true;
        return !Directory(model.localPath!).existsSync();
      });

      notifyListeners();
    } catch (e) {
      debugPrint('Error loading downloaded models: $e');
    }
  }

  /// Guardar modelos descargados en caché
  Future<void> _saveDownloadedModels() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final modelsJson = _downloadedModels.map((m) => m.toJson()).toList();
      await prefs.setString('downloaded_models', json.encode(modelsJson));
    } catch (e) {
      debugPrint('Error saving downloaded models: $e');
    }
  }

  /// Ejecutar comando
  Future<ProcessResult> _runCommand(String command, List<String> args) async {
    try {
      return await Process.run(command, args);
    } catch (e) {
      return ProcessResult(0, -1, '', e.toString());
    }
  }

  /// Ejecutar comando con salida en tiempo real
  Future<ProcessResult> _runCommandWithOutput(
    String command,
    List<String> args, {
    void Function(String)? onOutput,
  }) async {
    try {
      final process = await Process.start(command, args);
      final stdoutBuffer = StringBuffer();
      final stderrBuffer = StringBuffer();

      process.stdout.transform(utf8.decoder).listen((data) {
        stdoutBuffer.write(data);
        onOutput?.call(data);
      });

      process.stderr.transform(utf8.decoder).listen((data) {
        stderrBuffer.write(data);
        onOutput?.call(data);
      });

      final exitCode = await process.exitCode;

      return ProcessResult(
        process.pid,
        exitCode,
        stdoutBuffer.toString(),
        stderrBuffer.toString(),
      );
    } catch (e) {
      return ProcessResult(0, -1, '', e.toString());
    }
  }

  /// Limpiar logs
  void clearLogs() {
    _logs = '';
    notifyListeners();
  }

  @override
  void dispose() {
    _healthCheckTimer?.cancel();
    _vllmProcess?.kill();
    super.dispose();
  }
}
