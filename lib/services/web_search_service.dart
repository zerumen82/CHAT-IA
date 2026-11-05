import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Búsqueda web normal y segura para modelos con herramientas.
///
/// Usa la API pública de respuestas instantáneas de DuckDuckGo, que no exige
/// clave ni registro. Devuelve resúmenes y temas relacionados, nunca ejecuta
/// código ni accede a la dark net.
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
          'Busca información actual en internet (web normal, no dark net). '
          'Devuelve un resumen y enlaces relacionados. Úsala solo cuando el '
          'usuario pida buscar información actual o verificar datos.',
      'parameters': <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'query': <String, dynamic>{
            'type': 'string',
            'description': 'Consulta de búsqueda en texto libre',
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
      {Duration timeout = const Duration(seconds: 15)}) async {
    final query = rawQuery.trim();
    if (query.isEmpty) {
      throw ArgumentError('La consulta de búsqueda no puede estar vacía.');
    }
    if (query.length > 300) {
      throw ArgumentError('La consulta de búsqueda es demasiado larga.');
    }

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
