import 'package:flutter_test/flutter_test.dart';
import 'package:lightchat/config/vllm_config.dart';

void main() {
  test('detects uncensored model variants by name', () {
    expect(
      OllamaConfig.isUncensoredModel(
        'huihui_ai/qwen2.5-abliterate:7b-instruct-q4_K_M',
      ),
      isTrue,
    );
    expect(OllamaConfig.isUncensoredModel('dolphin3:8b'), isTrue);
    expect(OllamaConfig.isUncensoredModel('llama2-uncensored:latest'), isTrue);
    expect(OllamaConfig.isUncensoredModel('dolphin-mistral:7b'), isTrue);
  });

  test('does not flag regular models as uncensored', () {
    expect(OllamaConfig.isUncensoredModel('qwen2.5:7b'), isFalse);
    expect(OllamaConfig.isUncensoredModel('llama3:latest'), isFalse);
    expect(OllamaConfig.isUncensoredModel('llama3.2-vision:11b'), isFalse);
    expect(OllamaConfig.isUncensoredModel(''), isFalse);
  });
}
