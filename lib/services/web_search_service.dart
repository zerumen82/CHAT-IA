import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:socks5_proxy/socks.dart';

/// Búsqueda web normal y en la red Tor (deep web) para modelos con herramientas.
///
/// `source=web` usa DuckDuckGo (sin clave). `source=tor` usa un proxy SOCKS5
/// local de Tor y consulta el índice .onion de Ahmia, devolviendo enlaces
/// .onion que solo se abren con Tor Browser.
/// Nunca ejecuta código ni accede a URLs arbitrarias por el modelo.
class WebSearchService {
  WebSearchService({http.Client? client}) : _injectedClient = client;

  static final WebSearchService instance = WebSearchService();

  final http.Client? _injectedClient;

  http.Client _client() => _injectedClient ?? http.Client();

  static const Map<String, dynamic> tool = <String, dynamic>{
    'type': 'function',
    'function': <String, dynamic>{
      'name': 'web_search',
      'description':
          'Busca información en internet. source="web" (por defecto) busca en la '
          'web normal (DuckDuckGo). source="tor" busca en la red Tor / deep web '
          '(índice .onion de Ahmia) y devuelve enlaces .onion. Usar "tor" solo si el '
          'usuario pide deep web, dark web o Tor. Devuelve resumen y enlaces. '
          'Úsala solo cuando el usuario pida buscar información o verificar datos.',
      'parameters': <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'query': <String, dynamic>{
            'type': 'string',
            'description': 'Consulta de búsqueda en texto libre',
          },
          'source': <String, dynamic>{
            'type': 'string',
            'enum': <String>['web', 'tor'],
            'description': 'Fuente de búsqueda: web (normal) o tor (deep web).',
          },
        },
        'required': <String>['query'],
      },
    },
  };

  static List<Map<String, dynamic>> get tools =>
      <Map<String, dynamic>>[tool];

  static List<Map<String, dynamic>> allChatTools(
          List<Map<String, dynamic>> fileTools) =>
      <Map<String, dynamic>>[...fileTools, tool];

  /// Ejecuta una búsqueda y devuelve texto legible para el modelo.
  Future<String> search(String rawQuery,
      {String source = 'web', Duration timeout = const Duration(seconds: 15)}) async {
    final query = rawQuery.trim();
    if (query.isEmpty) {
      throw ArgumentError('La consulta de búsqueda no puede estar vacía.');
    }
    if (query.length > 300) {
      throw ArgumentError('La consulta de búsqueda es demasiado larga.');
    }

    final normalizedSource = source.trim().toLowerCase();
    if (normalizedSource == 'tor') {
      // Ahmia por Tor tarda 4-12 s medidos (portada + resultados).
      return _searchTor(
          query, timeout < _minTorTimeout ? _minTorTimeout : timeout);
    }
    return _searchWeb(query, timeout);
  }

  Future<String> _searchWeb(String query, Duration timeout) async {
    final client = _client();
    try {
      final uri = Uri.https('api.duckduckgo.com', '/', <String, String>{
        'q': query,
        'format': 'json',
        'no_html': '1',
        'skip_disambig': '1',
      });
      final response = await client.get(uri).timeout(timeout);
      if (response.statusCode != 200) {
        throw StateError(
            'La búsqueda web falló con HTTP ${response.statusCode}.');
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Respuesta de búsqueda no interpretable.');
      }
      return _format(decoded, query);
    } on TimeoutException {
      throw StateError('La búsqueda web agotó el tiempo de espera.');
    } on SocketException {
      throw StateError('No hay conexión a internet para buscar.');
    } finally {
      if (_injectedClient == null) {
        client.close();
      }
    }
  }

  /// Índice .onion de Ahmia. Su buscador exige un token oculto que solo
  /// aparece en la portada; sin él `/search/` redirige a la portada.
  static const _ahmiaBase =
      'http://juhanurmihxlp77nkq76byazcldy2hlmovfu2epvl5ankdibsot4csyd.onion';
  static const _ahmiaHost =
      'juhanurmihxlp77nkq76byazcldy2hlmovfu2epvl5ankdibsot4csyd.onion';

  Future<String> _searchTor(String query, Duration timeout) async {
    // En pruebas se inyecta un http.Client; en producción se verifica Tor.
    final port = _injectedClient == null ? await _torPort() : 9050;

    final client = _torClient(port);
    try {
      var token = <String, String>{};
      try {
        token = _ahmiaToken(await _get(client, '$_ahmiaBase/', timeout));
      } catch (_) {
        // Sin portada se intenta la búsqueda directa, que puede redirigir.
      }

      final uri = Uri.parse('$_ahmiaBase/search/')
          .replace(queryParameters: <String, String>{...token, 'q': query});
      final results = _parseTorResults(await _get(client, '$uri', timeout));
      if (results.isEmpty) {
        throw StateError('Ahmia no devolvió resultados .onion para «$query».');
      }
      return _formatTor(results, query, 'Ahmia');
    } on TimeoutException {
      throw StateError('La búsqueda en Tor agotó el tiempo de espera.');
    } on SocketException {
      throw StateError('No hay conexión a Tor para buscar.');
    } finally {
      if (_injectedClient == null) {
        client.close();
      }
    }
  }

  /// Puertos SOCKS5 locales habituales: servicio `tor` y Tor Browser.
  static const torPorts = <int>[9050, 9150];

  /// Margen mínimo en Tor: medido 12,3 s en frío y 4-5 s en caliente.
  static const _minTorTimeout = Duration(seconds: 30);

  /// Devuelve el primer puerto SOCKS5 local que acepta conexiones.
  static Future<int> _torPort() async {
    for (final port in torPorts) {
      try {
        final socket = await Socket.connect('127.0.0.1', port,
            timeout: const Duration(seconds: 3));
        await socket.close();
        return port;
      } catch (_) {
        continue;
      }
    }
    throw StateError(
        'Tor no está disponible. Abre Tor Browser (SOCKS5 en 127.0.0.1:9150) '
        'o ejecuta el servicio Tor (127.0.0.1:9050) para buscar en la deep web.');
  }

  http.Client _torClient(int port) {
    if (_injectedClient != null) {
      return _injectedClient!;
    }
    final httpClient = HttpClient();
    SocksTCPClient.assignToHttpClient(httpClient,
        <ProxySettings>[ProxySettings(InternetAddress.loopbackIPv4, port)]);
    return IOClient(httpClient);
  }

  static Future<String> _get(
      http.Client client, String url, Duration timeout) async {
    final response = await client.get(Uri.parse(url)).timeout(timeout);
    if (response.statusCode != 200) {
      throw StateError(
          'La búsqueda en Tor falló con HTTP ${response.statusCode}.');
    }
    return response.body;
  }

  /// Token oculto del formulario de portada de Ahmia.
  static Map<String, String> _ahmiaToken(String html) {
    final params = <String, String>{};
    final document = html_parser.parse(html);
    for (final input
        in document.querySelectorAll('#searchForm input[type="hidden"]')) {
      final name = input.attributes['name']?.trim() ?? '';
      final value = input.attributes['value'] ?? '';
      if (name.isNotEmpty && value.isNotEmpty) {
        params[name] = value;
      }
    }
    return params;
  }

  static List<Map<String, String>> _parseTorResults(String html) {
    final document = html_parser.parse(html);
    final results = <Map<String, String>>[];
    final seen = <String>{};

    void add(String rawUrl, String title, String snippet) {
      final url = _onionUrl(rawUrl);
      if (url == null || !seen.add(url)) return;
      results.add(<String, String>{
        'title': title.isEmpty ? url : title,
        'url': url,
        'snippet': _shorten(snippet),
      });
    }

    // Ahmia: ol.searchResults > li.result > h4 a + p + cite. El href pasa por
    // su redirector, así que la URL .onion real viaja en redirect_url.
    for (final item in document.querySelectorAll('ol.searchResults li.result')) {
      if (results.length >= 10) break;
      final anchor = item.querySelector('h4 a') ?? item.querySelector('a');
      final cite = item.querySelector('cite')?.text ?? '';
      add(
        anchor?.attributes['href'] ?? cite,
        _clean(anchor?.text ?? ''),
        item.querySelector('p')?.text ?? '',
      );
    }

    // Índices .onion con otro marcado: cualquier enlace directo.
    if (results.isEmpty) {
      for (final anchor in document.querySelectorAll('a')) {
        if (results.length >= 10) break;
        add(anchor.attributes['href'] ?? '', _clean(anchor.text), '');
      }
    }
    return results;
  }

  /// URL .onion real a partir de un enlace directo o del redirector de Ahmia.
  static String? _onionUrl(String raw) {
    var candidate = raw.trim();
    if (candidate.isEmpty) return null;
    final marker = candidate.indexOf('redirect_url=');
    if (marker >= 0) {
      candidate = candidate.substring(marker + 'redirect_url='.length);
      try {
        candidate = Uri.decodeComponent(candidate);
      } catch (_) {
        // Codificación no válida: se usa el valor tal cual.
      }
      candidate = candidate.trim();
    }
    if (!candidate.toLowerCase().contains('.onion')) return null;
    if (!candidate.contains('://')) {
      final host =
          candidate.startsWith('//') ? candidate.substring(2) : candidate;
      candidate = 'http://$host';
    }
    final parsed = Uri.tryParse(candidate);
    final host = parsed?.host.toLowerCase() ?? '';
    if (!host.endsWith('.onion') || host == _ahmiaHost) return null;
    return candidate;
  }

  static String _clean(String text) =>
      text.replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _shorten(String text) {
    final clean = _clean(text);
    return clean.length > 180 ? clean.substring(0, 180) : clean;
  }

  static String _formatTor(
      List<Map<String, String>> results, String query, String engine) {
    final buffer = StringBuffer();
    buffer.writeln('Consulta (Tor/deep web): $query');
    buffer.writeln('Motor: $engine');
    buffer.writeln('Resultados .onion (requieren Tor Browser para abrir):');
    for (final item in results) {
      buffer.writeln('- ${item['title']}');
      final snippet = item['snippet'] ?? '';
      if (snippet.isNotEmpty) {
        buffer.writeln('  $snippet');
      }
      buffer.writeln('  ${item['url']}');
    }
    return buffer.toString().trim();
  }

  static String _format(Map<String, dynamic> data, String query) {
    final buffer = StringBuffer();
    buffer.writeln('Consulta: $query');
    final heading = (data['Heading'] as String? ?? '').trim();
    if (heading.isNotEmpty) {
      buffer.writeln('Tema: $heading');
    }
    final abstractText = (data['Abstract'] as String? ?? '').trim();
    final abstractSource = (data['AbstractSource'] as String? ?? '').trim();
    final abstractUrl = (data['AbstractURL'] as String? ?? '').trim();
    if (abstractText.isNotEmpty) {
      buffer.writeln('Resumen: $abstractText');
      if (abstractSource.isNotEmpty) {
        buffer.writeln('Fuente: $abstractSource');
      }
      if (abstractUrl.isNotEmpty) {
        buffer.writeln('URL: $abstractUrl');
      }
    }

    final related = <Map<String, String>>[];
    _collectRelated(data['RelatedTopics'], related);
    if (related.isNotEmpty) {
      buffer.writeln('Temas relacionados:');
      for (final item in related.take(5)) {
        final text = item['text'] ?? '';
        final url = item['url'] ?? '';
        if (text.isEmpty) continue;
        buffer.write('- $text');
        if (url.isNotEmpty) {
          buffer.write(' ($url)');
        }
        buffer.writeln();
      }
    }

    if (abstractText.isEmpty && related.isEmpty) {
      return 'Consulta: $query\nNo se encontraron resultados directos en la '
          'búsqueda web. El modelo debe indicar que no hay información '
          'verificada disponible.';
    }
    return buffer.toString().trim();
  }

  static void _collectRelated(dynamic node, List<Map<String, String>> output) {
    if (node is List) {
      for (final item in node) {
        _collectRelated(item, output);
      }
      return;
    }
    if (node is Map) {
      final text = (node['Text'] as String? ?? '').trim();
      final url = (node['FirstURL'] as String? ?? '').trim();
      if (text.isNotEmpty) {
        output.add(<String, String>{'text': text, 'url': url});
      }
      final topics = node['Topics'];
      if (topics != null) {
        _collectRelated(topics, output);
      }
    }
  }
}
