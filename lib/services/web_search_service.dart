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
      return _searchTor(query, timeout);
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

  Future<String> _searchTor(String query, Duration timeout) async {
    // En pruebas se inyecta un http.Client; en producción se verifica Tor.
    final port = _injectedClient == null ? await _torPort() : 9050;

    final client = _torClient(port);
    try {
      final encoded = Uri.encodeQueryComponent(query);
      final engines = <Map<String, String>>[
        <String, String>{
          'name': 'Ahmia',
          'url':
              'http://juhanurmihxlp77nkq76byazcldy2hlmovfu2epvl5ankdibsot4csyd.onion/search/?q=$encoded',
        },
      ];

      for (final engine in engines) {
        try {
          final uri = Uri.parse(engine['url']!);
          final response = await client.get(uri).timeout(timeout);
          if (response.statusCode != 200) continue;
          final results = _parseTorResults(response.body);
          if (results.isNotEmpty) {
            return _formatTor(results, query, engine['name']!);
          }
        } catch (_) {
          continue;
        }
      }
      throw StateError(
          'No se obtuvieron resultados de la deep web (motores .onion no '
          'disponibles o sin resultados).');
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

  static List<Map<String, String>> _parseTorResults(String html) {
    final results = <Map<String, String>>[];
    final seen = <String>{};
    final document = html_parser.parse(html);
    for (final anchor in document.querySelectorAll('a')) {
      final href = (anchor.attributes['href'] ?? '').trim();
      if (!href.contains('.onion')) continue;
      if (!seen.add(href)) continue;
      final title = anchor.text.trim();
      String snippet = '';
      final parent = anchor.parent;
      if (parent != null) {
        snippet = parent.text.trim().replaceAll(RegExp(r'\\s+'), ' ');
        if (snippet.length > 180) {
          snippet = snippet.substring(0, 180);
        }
      }
      results.add(<String, String>{
        'title': title.isEmpty ? href : title,
        'url': href,
        'snippet': snippet,
      });
      if (results.length >= 10) break;
    }
    if (results.isEmpty) {
      final regex = RegExp(r'https?://[a-z2-7]{16,56}\\.onion[^\\s"<>]*');
      for (final match in regex.allMatches(html)) {
        final url = match.group(0)!;
        if (seen.add(url)) {
          results.add(<String, String>{
            'title': url,
            'url': url,
            'snippet': '',
          });
          if (results.length >= 10) break;
        }
      }
    }
    return results;
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
