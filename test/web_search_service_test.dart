import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lightchat/services/web_search_service.dart';

void main() {
  test('web_search devuelve resumen y temas relacionados', () async {
    final client = MockClient((request) async {
      expect(request.url.host, 'api.duckduckgo.com');
      expect(request.url.queryParameters['q'], 'flutter');
      expect(request.url.queryParameters['format'], 'json');
      return http.Response(
        '{"Heading":"Flutter","Abstract":"UI toolkit.","AbstractSource":"Wikipedia","AbstractURL":"https://example.com/flutter","RelatedTopics":[{"Text":"Flutter docs","FirstURL":"https://docs.flutter.dev"}]}',
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final service = WebSearchService(client: client);
    final result = await service.search('flutter');
    expect(result, contains('Resumen: UI toolkit.'));
    expect(result, contains('Fuente: Wikipedia'));
    expect(result, contains('URL: https://example.com/flutter'));
    expect(result, contains('Flutter docs'));
  });

  test('web_search informa cuando no hay resultados', () async {
    final client = MockClient((request) async {
      return http.Response('{"RelatedTopics":[]}', 200);
    });
    final service = WebSearchService(client: client);
    final result = await service.search('xyz');
    expect(result, contains('No se encontraron resultados directos'));
  });

  test('web_search rechaza consulta vacía', () async {
    final service = WebSearchService(client: MockClient((_) async {
      return http.Response('{}', 200);
    }));
    expect(() => service.search('   '), throwsArgumentError);
  });

  test('web_search propaga error HTTP', () async {
    final service = WebSearchService(client: MockClient((_) async {
      return http.Response('error', 500);
    }));
    expect(() => service.search('flutter'), throwsStateError);
  });

  test('la herramienta web_search tiene el esquema esperado', () {
    expect(WebSearchService.tool['type'], 'function');
    expect(WebSearchService.tool['function']['name'], 'web_search');
    expect(
      (WebSearchService.tool['function']['parameters']['required'] as List)
          .contains('query'),
      isTrue,
    );
  });
}
