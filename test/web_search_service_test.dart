import 'dart:async';

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

  test('detener la generación corta la búsqueda en curso', () async {
    final pending = Completer<http.Response>();
    final cancellation = Completer<void>();
    final search = WebSearchService(client: MockClient((_) => pending.future))
        .search('lento', cancellation: cancellation.future);
    cancellation.complete();
    await expectLater(search, throwsA(isA<WebSearchCancelledException>()));
  });

  test('web_search rechaza consulta vacía', () async {
    final client = MockClient((request) async {
      return http.Response('{}', 200);
    });
    final service = WebSearchService(client: client);
    expect(() => service.search('   '), throwsArgumentError);
  });

  test('web_search propaga error HTTP', () async {
    final client = MockClient((request) async {
      return http.Response('error', 500);
    });
    final service = WebSearchService(client: client);
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
    expect(
      (WebSearchService.tool['function']['parameters']['properties'] as Map)
          .containsKey('source'),
      isTrue,
    );
  });

  test('web_search con source=tor parsea enlaces .onion', () async {
    final html = '<html><body>'
        '<a href="http://exampleonion1234567890abcdef.onion/page">Sitio Onion</a>'
        '<p>Descripción del sitio</p>'
        '</body></html>';
    final client = MockClient((request) async {
      return http.Response(html, 200, headers: {'content-type': 'text/html'});
    });
    final service = WebSearchService(client: client);
    final result = await service.search('privacy', source: 'tor');
    expect(result, contains('Sitio Onion'));
    expect(result, contains('exampleonion1234567890abcdef.onion/page'));
  });

  test('web_search con source=tor usa el token de Ahmia y la URL real',
      () async {
    const home = '<html><body><form id="searchForm" action="/search/" '
        'method="get"><input id="id_q" type="search" name="q">'
        '<input type="hidden" name="18df05" value="4abde3">'
        '</form></body></html>';
    const page = '<html><body><ol class="searchResults">'
        '<li class="result"><h4><a href="/search/redirect?search_term=test'
        '&redirect_url=http://gbkxefzhrrjh5prrbhdlbtgnrrubelyukalgct7jesqrv6b3mjtkb5yd.onion/page/x">'
        'Foro XMR</a></h4><p>xmrstars for everybody.</p>'
        '<cite>gbkxefzhrrjh5prrbhdlbtgnrrubelyukalgct7jesqrv6b3mjtkb5yd.onion</cite>'
        '</li>'
        '<li class="result"><h4><a href="/search/redirect?search_term=test'
        '&redirect_url=http://juhanurmihxlp77nkq76byazcldy2hlmovfu2epvl5ankdibsot4csyd.onion/search/?q=test">'
        'Enlace de Ahmia</a></h4></li></ol></body></html>';

    final requested = <Uri>[];

    void Function()? cacheInvalidate;

    final clientForCache = MockClient((request) async {
      requested.add(request.url);
      if (request.url.path == '/search/') {
        expect(request.url.queryParameters['18df05'], '4abde3',
            reason: 'la búsqueda en tor debe enviar el token oculto de la portada');
        expect(request.url.queryParameters['q'], 'privacidad');
        return http.Response(page, 200,
            headers: {'content-type': 'text/html'});
      }
      if (request.url.path == '/') {
        cacheInvalidate?.call();
        return http.Response(home, 200, headers: {'content-type': 'text/html'});
      }
      throw UnsupportedError('Ruta inesperada: ${request.url.path}');
    });

    final cache = AhmiaCache(
      client: clientForCache,
      ttl: Duration.zero,
    );
    cacheInvalidate = () => cache.invalidate();

    final result = await WebSearchService(
        client: clientForCache, cache: cache)
        .search('privacidad', source: 'tor');

    expect(requested.first.path, '/');
    expect(result, contains('Foro XMR'));
    expect(
      result,
      contains(
          'gbkxefzhrrjh5prrbhdlbtgnrrubelyukalgct7jesqrv6b3mjtkb5yd.onion/page/x'),
    );
    expect(result, contains('xmrstars for everybody.'));
    expect(result, isNot(contains('/search/redirect')));
    expect(result, isNot(contains('Enlace de Ahmia')));
  });
}
