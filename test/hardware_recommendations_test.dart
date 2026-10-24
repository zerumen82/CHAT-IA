import 'package:flutter_test/flutter_test.dart';
import 'package:lightchat/services/hardware_detector_service.dart';

void main() {
  test('recommends small models when available memory is limited', () {
    final models = HardwareDetectorService.recommendedModelsForHardware(
      hasGPU: false,
      gpuVRAM: null,
      systemRAM: 8,
    );

    expect(models, contains('llama3.2:1b'));
    expect(
        models.any((model) => model.contains('70b') || model.contains('405b')),
        isFalse);
  });

  test('limits GPU recommendations by system RAM as well as VRAM', () {
    final models = HardwareDetectorService.recommendedModelsForHardware(
      hasGPU: true,
      gpuVRAM: 24,
      systemRAM: 12,
    );

    expect(models, contains('llama3.2:3b'));
    expect(models.any((model) => model.contains('14b')), isFalse);
  });

  test('allows a 14B model only when the conservative memory budget permits',
      () {
    final models = HardwareDetectorService.recommendedModelsForHardware(
      hasGPU: true,
      gpuVRAM: 24,
      systemRAM: 32,
    );

    expect(models, contains('qwen2.5:14b'));
    expect(
        models.any((model) => model.contains('70b') || model.contains('405b')),
        isFalse);
  });
}
