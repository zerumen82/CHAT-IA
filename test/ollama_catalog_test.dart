import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lightchat/services/ollama_service.dart';

const _catalogUri = 'https://ollama.com/search';

String _catalogPage({
  required int modelCount,
  required List<String> cards,
}) {
  return '''
    <input id="form-input" placeholder="Search $modelCount models">
    ${cards.join()}
  ''';
}

String _modelCard({
  required String name,
  required String description,
  required List<String> tags,
}) {
  return '''
    <a href="/library/$name">
      <h2><span>$name</span></h2>
      <p title="$description">$description</p>
      <div class="mt-3">${tags.map((tag) => '<span>$tag</span>').join()}</div>
      <span title="4,179,104 downloads">4.2M</span>
    </a>
  ''';
}

void main() {
  final llama = _modelCard(
    name: 'llama3.2',
    description: 'Meta&#39;s small language model.',
    tags: ['3b'],
  );
  final uncensoredLlama = _modelCard(
    name: 'llama2-uncensored',
    description: 'Uncensored Llama 2 model.',
    tags: ['7b'],
  );
  final dolphin = _modelCard(
    name: 'dolphin-llama3',
    description: 'Dolphin fine-tuned model based on Llama 3.',
    tags: ['8b'],
  );
  final multimodal = _modelCard(
    name: 'llava',
    description: 'A multimodal vision and language model.',
    tags: ['7b'],
  );

  test('loads Ollama library pages with Llama and uncensored variants',
      () async {
    final client = MockClient((request) async {
      expect(request.url.host, 'ollama.com');
      expect(request.url.path, '/search');
      expect(request.url.queryParameters['c'], 'local');
      expect(request.headers['accept'], 'text/html');
      if (request.url.queryParameters['page'] == '1') {
        expect(request.headers['hx-request'], isNull);
        return http.Response(
          _catalogPage(
            modelCount: 21,
            cards: [llama, uncensoredLlama],
          ),
          200,
        );
      }
      expect(request.url.queryParameters['page'], '2');
      expect(request.headers['hx-request'], 'true');
      return http.Response(_catalogPage(modelCount: 21, cards: [dolphin]), 200);
    });
    final service = OllamaService.forTesting(
      catalogClient: client,
      catalogUri: Uri.parse(_catalogUri),
    );

    final models = await service.fetchAvailableModels(forceRefresh: true);

    expect(models.map((model) => model['name']), [
      'llama3.2',
      'llama2-uncensored',
      'dolphin-llama3',
    ]);
    expect(models.first['description'], "Meta's small language model.");
    expect(models.first['uncensored'], isFalse);
    expect(models[1]['uncensored'], isTrue);
    expect(models.last['uncensored'], isTrue);
    expect(models.last['size'], '~5 GB');
    expect(service.availableModelsError, isNull);
    expect(service.isLoadingAvailableModels, isFalse);
    service.dispose();
  });

  test('search and category filters return only matching visible models', () {
    final models = OllamaService.parseAvailableModels(
      _catalogPage(
        modelCount: 3,
        cards: [llama, uncensoredLlama, dolphin, multimodal],
      ),
    );

    final llamaResults = OllamaService.filterAvailableModels(
      models: models,
      query: 'llama',
    );
    expect(llamaResults, hasLength(3));

    final uncensoredResults = OllamaService.filterAvailableModels(
      models: models,
      uncensoredOnly: true,
    );
    expect(
      uncensoredResults.map((model) => model['name']),
      ['llama2-uncensored', 'dolphin-llama3'],
    );

    final smallModels = OllamaService.filterAvailableModels(
      models: models,
      smallOnly: true,
    );
    expect(smallModels, hasLength(4));

    final multimodalModels = OllamaService.filterAvailableModels(
      models: models,
      multimodalOnly: true,
    );
    expect(multimodalModels.map((model) => model['name']), ['llava']);

    final noMatches = OllamaService.filterAvailableModels(
      models: models,
      query: 'not-a-model',
    );
    expect(noMatches, isEmpty);
  });

  test('keeps the last catalog when a later page fails', () async {
    var returnError = false;
    final client = MockClient((request) async {
      if (request.url.queryParameters['page'] == '2' && returnError) {
        return http.Response('unavailable', 503);
      }
      return http.Response(
        _catalogPage(
          modelCount: 21,
          cards: [llama],
        ),
        200,
      );
    });
    final service = OllamaService.forTesting(
      catalogClient: client,
      catalogUri: Uri.parse(_catalogUri),
    );

    final initialModels =
        await service.fetchAvailableModels(forceRefresh: true);
    returnError = true;
    final modelsAfterFailure =
        await service.fetchAvailableModels(forceRefresh: true);

    expect(modelsAfterFailure, initialModels);
    expect(service.availableModelsError, contains('HTTP 503'));
    expect(service.isLoadingAvailableModels, isFalse);
    service.dispose();
  });
}
