import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:system_info2/system_info2.dart';

/// Información del hardware del sistema
class HardwareInfo {
  final String cpuModel;
  final int cpuCores;
  final int systemRAM; // GB
  final bool hasGPU;
  final String? gpuModel;
  final int? gpuVRAM; // GB
  final String? gpuDriver;
  final bool supportsCUDA;
  final bool supportsROCm;
  final List<String> recommendedModels;

  const HardwareInfo({
    required this.cpuModel,
    required this.cpuCores,
    required this.systemRAM,
    required this.hasGPU,
    this.gpuModel,
    this.gpuVRAM,
    this.gpuDriver,
    this.supportsCUDA = false,
    this.supportsROCm = false,
    this.recommendedModels = const [],
  });

  /// Obtener descripción del hardware
  String get description {
    final parts = <String>[
      'CPU: $cpuModel ($cpuCores cores)',
      'RAM: $systemRAM GB',
    ];

    if (hasGPU && gpuModel != null) {
      parts.add('GPU: $gpuModel (${gpuVRAM}GB VRAM)');
    }

    return parts.join('\n');
  }

  /// Verificar si puede ejecutar un modelo
  bool canRunModel(
      {required double requiredVram, required double requiredRam}) {
    if (hasGPU && gpuVRAM != null) {
      return gpuVRAM! >= requiredVram;
    }
    return systemRAM >= requiredRam;
  }

  /// Convertir a JSON
  Map<String, dynamic> toJson() {
    return {
      'cpuModel': cpuModel,
      'cpuCores': cpuCores,
      'systemRAM': systemRAM,
      'hasGPU': hasGPU,
      'gpuModel': gpuModel,
      'gpuVRAM': gpuVRAM,
      'gpuDriver': gpuDriver,
      'supportsCUDA': supportsCUDA,
      'supportsROCm': supportsROCm,
      'recommendedModels': recommendedModels,
    };
  }

  /// Crear desde JSON
  factory HardwareInfo.fromJson(Map<String, dynamic> json) {
    return HardwareInfo(
      cpuModel: json['cpuModel'] as String? ?? 'Unknown',
      cpuCores: json['cpuCores'] as int? ?? 4,
      systemRAM: json['systemRAM'] as int? ?? 8,
      hasGPU: json['hasGPU'] as bool? ?? false,
      gpuModel: json['gpuModel'] as String?,
      gpuVRAM: json['gpuVRAM'] as int?,
      gpuDriver: json['gpuDriver'] as String?,
      supportsCUDA: json['supportsCUDA'] as bool? ?? false,
      supportsROCm: json['supportsROCm'] as bool? ?? false,
      recommendedModels:
          (json['recommendedModels'] as List<dynamic>?)?.cast<String>() ?? [],
    );
  }
}

/// Servicio para detectar hardware del sistema
class HardwareDetectorService {
  static HardwareInfo? _cachedInfo;

  /// Obtener información del hardware
  static Future<HardwareInfo> getHardwareInfo() async {
    if (_cachedInfo != null) return _cachedInfo!;

    try {
      // Obtener información del CPU
      final cpuModel = _getCPUModel();
      final cpuCores = Platform.numberOfProcessors;

      // Obtener RAM del sistema
      final systemRAM = await _getSystemRAM();

      // Detectar GPU
      final gpuInfo = await _detectGPU();

      // Generar recomendaciones
      final recommendedModels = recommendedModelsForHardware(
        hasGPU: gpuInfo['hasGPU'] as bool,
        gpuVRAM: gpuInfo['vram'] as int?,
        systemRAM: systemRAM,
      );

      _cachedInfo = HardwareInfo(
        cpuModel: cpuModel,
        cpuCores: cpuCores,
        systemRAM: systemRAM,
        hasGPU: gpuInfo['hasGPU'] as bool,
        gpuModel: gpuInfo['model'] as String?,
        gpuVRAM: gpuInfo['vram'] as int?,
        gpuDriver: gpuInfo['driver'] as String?,
        supportsCUDA: gpuInfo['cuda'] as bool? ?? false,
        supportsROCm: gpuInfo['rocm'] as bool? ?? false,
        recommendedModels: recommendedModels,
      );

      return _cachedInfo!;
    } catch (e) {
      debugPrint('Error detecting hardware: $e');
      // Retornar información por defecto
      return HardwareInfo(
        cpuModel: 'Unknown',
        cpuCores: Platform.numberOfProcessors,
        systemRAM: 8,
        hasGPU: false,
        recommendedModels: recommendedModelsForHardware(
          hasGPU: false,
          gpuVRAM: null,
          systemRAM: 8,
        ),
      );
    }
  }

  /// Obtener modelo del CPU
  static String _getCPUModel() {
    try {
      if (Platform.isWindows) {
        // En Windows, usar system_info2
        final processorName =
            SysInfo.cores.isNotEmpty ? SysInfo.cores.first.name : 'Unknown CPU';
        return processorName;
      } else if (Platform.isLinux) {
        // Leer de /proc/cpuinfo
        final file = File('/proc/cpuinfo');
        if (file.existsSync()) {
          final content = file.readAsStringSync();
          final match = RegExp(r'model name\s*:\s*(.+)').firstMatch(content);
          if (match != null) {
            return match.group(1)?.trim() ?? 'Unknown CPU';
          }
        }
      } else if (Platform.isMacOS) {
        // En Mac, usar sysctl
        final result =
            Process.runSync('sysctl', ['-n', 'machdep.cpu.brand_string']);
        return result.stdout.toString().trim();
      }
    } catch (e) {
      debugPrint('Error getting CPU model: $e');
    }
    return 'Unknown CPU';
  }

  /// Obtener RAM del sistema en GB
  static Future<int> _getSystemRAM() async {
    try {
      final totalMemory = SysInfo.getTotalPhysicalMemory();
      return (totalMemory / (1024 * 1024 * 1024)).round();
    } catch (e) {
      debugPrint('Error getting system RAM: $e');
      return 8; // Valor por defecto
    }
  }

  /// Detectar GPU y sus características
  static Future<Map<String, dynamic>> _detectGPU() async {
    try {
      if (Platform.isWindows) {
        return await _detectGPUWindows();
      } else if (Platform.isLinux) {
        return await _detectGPULinux();
      }
    } catch (e) {
      debugPrint('Error detecting GPU: $e');
    }
    return {'hasGPU': false};
  }

  /// Detectar GPU en Windows
  static Future<Map<String, dynamic>> _detectGPUWindows() async {
    try {
      // Método 1: Usar PowerShell para obtener información de GPU
      final psResult = Process.runSync(
        'powershell',
        [
          '-Command',
          'Get-CimInstance Win32_VideoController | Select-Object Name, AdapterRAM, DriverVersion | ConvertTo-Json'
        ],
      );

      String? gpuModel;
      int? vram;
      bool hasCUDA = false;
      bool hasROCm = false;

      final psOutput = psResult.stdout.toString();

      // Parsear JSON de PowerShell
      if (psOutput.isNotEmpty && !psOutput.contains('error')) {
        try {
          final decoded = jsonDecode(psOutput);
          final controllers = switch (decoded) {
            List<dynamic> values =>
              values.whereType<Map<String, dynamic>>().toList(),
            Map<String, dynamic> value => [value],
            _ => <Map<String, dynamic>>[],
          };
          final data = controllers.firstWhere(
            (controller) => controller['Name'] != null,
            orElse: () => <String, dynamic>{},
          );

          if (data['Name'] != null) {
            gpuModel = data['Name'].toString();
            final estimatedVram = _estimateVRAMFromModel(gpuModel);
            final reportedBytes =
                int.tryParse(data['AdapterRAM']?.toString() ?? '');

            if (reportedBytes != null && reportedBytes > 0) {
              const adapterRamLimit = 4294967295;
              if (reportedBytes >= adapterRamLimit && estimatedVram != null) {
                vram = estimatedVram;
              } else {
                vram = (reportedBytes / (1024 * 1024 * 1024)).round();
              }
            } else {
              vram = estimatedVram;
            }
          }
        } catch (e) {
          debugPrint('Error parsing PowerShell JSON: $e');
        }
      }

      // Método 2: Usar wmic como fallback
      if (gpuModel == null || gpuModel.isEmpty) {
        final wmicResult = Process.runSync(
          'wmic',
          ['path', 'win32_VideoController', 'get', 'name,AdapterRAM'],
        );

        final wmicOutput = wmicResult.stdout.toString();
        debugPrint('WMIC GPU output: $wmicOutput');

        final lines = wmicOutput.split('\n');
        for (final line in lines) {
          final trimmedLine = line.trim();
          if (trimmedLine.isEmpty ||
              trimmedLine.toLowerCase().contains('name') ||
              trimmedLine.toLowerCase().contains('adapterram')) {
            continue;
          }

          // Buscar GPU NVIDIA
          if (trimmedLine.toLowerCase().contains('nvidia') ||
              trimmedLine.toLowerCase().contains('rtx') ||
              trimmedLine.toLowerCase().contains('gtx') ||
              trimmedLine.toLowerCase().contains('geforce')) {
            gpuModel = trimmedLine.replaceAll(RegExp(r'\s+'), ' ').trim();
            hasCUDA = true;

            // Estimar VRAM basado en el modelo
            vram = _estimateVRAMFromModel(trimmedLine);
            break;
          }

          // Buscar GPU AMD
          if (trimmedLine.toLowerCase().contains('amd') ||
              trimmedLine.toLowerCase().contains('radeon') ||
              trimmedLine.toLowerCase().contains('rx ')) {
            gpuModel = trimmedLine.replaceAll(RegExp(r'\s+'), ' ').trim();
            hasROCm = true;
            vram ??= 8;
            break;
          }

          // Buscar Intel Arc
          if (trimmedLine.toLowerCase().contains('intel') &&
              (trimmedLine.toLowerCase().contains('arc') ||
                  trimmedLine.toLowerCase().contains('iris'))) {
            gpuModel = trimmedLine.replaceAll(RegExp(r'\s+'), ' ').trim();
            vram ??= 8;
            break;
          }
        }
      }

      // Verificar si es NVIDIA para CUDA
      if (gpuModel != null) {
        final gpuLower = gpuModel.toLowerCase();
        hasCUDA = gpuLower.contains('nvidia') ||
            gpuLower.contains('rtx') ||
            gpuLower.contains('gtx') ||
            gpuLower.contains('geforce');
        hasROCm = gpuLower.contains('amd') || gpuLower.contains('radeon');

        // Si no tenemos VRAM, estimar del modelo
        vram ??= _estimateVRAMFromModel(gpuModel);

        return {
          'hasGPU': true,
          'model': gpuModel,
          'vram': vram,
          'cuda': hasCUDA,
          'rocm': hasROCm,
        };
      }
    } catch (e) {
      debugPrint('Error detecting GPU on Windows: $e');
    }
    return {'hasGPU': false};
  }

  /// Estimar VRAM basado en el modelo de GPU
  static int? _estimateVRAMFromModel(String model) {
    final modelLower = model.toLowerCase();

    // NVIDIA RTX 40 series
    if (modelLower.contains('4090')) return 24;
    if (modelLower.contains('4080')) return 16;
    if (modelLower.contains('4070 ti')) return 12;
    if (modelLower.contains('4070')) return 12;
    if (modelLower.contains('4060 ti')) return 16;
    if (modelLower.contains('4060')) return 8;
    if (modelLower.contains('4050')) return 6;

    // NVIDIA RTX 30 series
    if (modelLower.contains('3090 ti')) return 24;
    if (modelLower.contains('3090')) return 24;
    if (modelLower.contains('3080 ti')) return 12;
    if (modelLower.contains('3080')) return 10;
    if (modelLower.contains('3070 ti')) return 8;
    if (modelLower.contains('3070')) return 8;
    if (modelLower.contains('3060 ti')) return 8;
    if (modelLower.contains('3060')) return 12;
    if (modelLower.contains('3050')) return 8;

    // NVIDIA RTX 20 series
    if (modelLower.contains('2080 ti')) return 11;
    if (modelLower.contains('2080 super')) return 8;
    if (modelLower.contains('2080')) return 8;
    if (modelLower.contains('2070 super')) return 8;
    if (modelLower.contains('2070')) return 8;
    if (modelLower.contains('2060 super')) return 8;
    if (modelLower.contains('2060')) return 6;

    // NVIDIA GTX 16/10 series
    if (modelLower.contains('1660')) return 6;
    if (modelLower.contains('1650')) return 4;
    if (modelLower.contains('1080 ti')) return 11;
    if (modelLower.contains('1080')) return 8;
    if (modelLower.contains('1070')) return 8;
    if (modelLower.contains('1060')) return 6;
    if (modelLower.contains('1050')) return 4;

    // AMD Radeon RX 7000 series
    if (modelLower.contains('7900 xtx')) return 24;
    if (modelLower.contains('7900 xt')) return 20;
    if (modelLower.contains('7800 xt')) return 16;
    if (modelLower.contains('7700 xt')) return 12;
    if (modelLower.contains('7600')) return 8;

    // AMD Radeon RX 6000 series
    if (modelLower.contains('6900')) return 16;
    if (modelLower.contains('6800')) return 16;
    if (modelLower.contains('6700')) return 10;
    if (modelLower.contains('6600')) return 8;
    if (modelLower.contains('6500')) return 4;

    // Intel Arc
    if (modelLower.contains('a770')) return 16;
    if (modelLower.contains('a750')) return 8;
    if (modelLower.contains('a580')) return 8;
    if (modelLower.contains('a380')) return 6;

    return null;
  }

  /// Detectar GPU en Linux
  static Future<Map<String, dynamic>> _detectGPULinux() async {
    try {
      // Verificar nvidia-smi
      final nvidiaResult = Process.runSync('nvidia-smi',
          ['--query-gpu=name,memory.total', '--format=csv,noheader']);

      if (nvidiaResult.exitCode == 0) {
        final output = nvidiaResult.stdout.toString();
        final parts = output.split(',');
        if (parts.length >= 2) {
          final model = parts[0].trim();
          final memoryStr = parts[1].trim();

          // Parsear memoria (ej: "8192 MiB")
          final memoryMatch = RegExp(r'(\d+)').firstMatch(memoryStr);
          final vramMB =
              memoryMatch != null ? int.parse(memoryMatch.group(1)!) : 8192;

          return {
            'hasGPU': true,
            'model': model,
            'vram': (vramMB / 1024).round(),
            'cuda': true,
            'rocm': false,
          };
        }
      }

      // Verificar AMD con rocm-smi
      final rocmResult = Process.runSync('rocm-smi', ['--showproductname']);
      if (rocmResult.exitCode == 0) {
        return {
          'hasGPU': true,
          'model': 'AMD GPU',
          'vram': 8, // Estimación
          'cuda': false,
          'rocm': true,
        };
      }
    } catch (e) {
      debugPrint('Error detecting GPU on Linux: $e');
    }
    return {'hasGPU': false};
  }

  /// Generar recomendaciones de modelos basadas en hardware
  static List<String> recommendedModelsForHardware({
    required bool hasGPU,
    required int? gpuVRAM,
    required int systemRAM,
  }) {
    final recommendations = <String>[];

    final memoryBudgetGb = hasGPU && gpuVRAM != null
        ? (gpuVRAM < systemRAM - 4 ? gpuVRAM : systemRAM - 4)
        : systemRAM - 4;

    if (memoryBudgetGb >= 20) {
      recommendations.addAll([
        'qwen2.5:14b',
        'llama3.1:8b',
        'mistral:7b',
      ]);
    } else if (memoryBudgetGb >= 12) {
      recommendations.addAll([
        'llama3.1:8b',
        'qwen2.5:7b',
        'mistral:7b',
      ]);
    } else if (memoryBudgetGb >= 6) {
      recommendations.addAll([
        'llama3.2:3b',
        'phi3:mini',
        'qwen2.5:3b',
      ]);
    } else {
      recommendations.addAll([
        'llama3.2:1b',
        'tinyllama:1.1b',
        'qwen2.5:0.5b',
      ]);
    }

    return recommendations;
  }

  /// Limpiar caché
  static void clearCache() {
    _cachedInfo = null;
  }
}
