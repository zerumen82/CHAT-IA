import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lightchat/config/api_config.dart';
import 'package:lightchat/services/api_key_store.dart';
import 'package:lightchat/services/api_service.dart';
import 'package:lightchat/services/ollama_service.dart';

/// Contenido con los mismos formatos de separador que el APIS.txt real.
const sampleFile = '''
DEEPSEEK : sk-aaaa
GEMINI : AIzaBBBBBB
OPENMROUTER : sk-or-v1-cccc
MISTRAL : dddd
xAI: xai-eeee
ANTROPIC: ffff
openai: sk-gggg
PERPLEXITY: pplx-hhhh
xiaomi: sk-iiii
ZEN: sk-jjjj
hugginfac= hf_kkkk
minmax: sk-llll
sambanova; mmmm
AI-HORDE: nnn
			ooo
Groq= gsk_pppp
''';

/// Cliente de prueba que registra la petición y responde con [respond].
MockClient capture(
  void Function(http.BaseRequest request, List<int> body) onRequest,
  http.StreamedResponse Function(http.BaseRequest request) respond,
) {
  return MockClient.streaming((request, bodyStream) async {
    final body = await bodyStream.toBytes();
    onRequest(request, body);
    return respond(request);
  });
}

http.StreamedResponse sse(String body, {int status = 200}) =>
    http.StreamedResponse(
      Stream.fromIterable(<List<int>>[utf8.encode(body)]),
      status,
    );

/// Lectura de cabeceras sin depender de la caja de mayúsculas.
String header(Map<String, String> headers, String name) {
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == name.toLowerCase()) {
      return entry.value;
    }
  }
  return '';
}

Matcher throwsHttpContaining(String text) => throwsA(
      isA<HttpException>().having(
        (error) => error.message,
        'message',
        contains(text),
      ),
    );

Matcher throwsStateContaining(String text) => throwsA(
      isA<StateError>().having(
        (error) => error.message,
        'message',
        contains(text),
      ),
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ApiKeyStore.instance.resetForTest();
  });

  tearDown(() {
    ApiKeyStore.instance.resetForTest();
  });

  group('ApiConfig', () {
    test('reconoce los nombres reales del archivo, incluidas sus erratas', () {
      expect(ApiConfig.resolveAlias('OPENMROUTER'), 'openrouter');
      expect(ApiConfig.resolveAlias('ANTROPIC'), 'anthropic');
      expect(ApiConfig.resolveAlias('hugginfac'), 'huggingface');
      expect(ApiConfig.resolveAlias('minmax'), 'minimax');
      expect(ApiConfig.resolveAlias('AI-HORDE'), 'aihorde');
      expect(ApiConfig.resolveAlias('xAI'), 'xai');
      expect(ApiConfig.resolveAlias('ZEN'), 'zen');
      expect(ApiConfig.resolveAlias('esto no es un proveedor'), isNull);
    });

    test('describe y compone identificadores de modelo cloud', () {
      expect(ApiConfig.isApiModel('llama3:latest'), isFalse);
      expect(ApiConfig.isApiModel('api:groq/llama-3.1-8b-instant'), isTrue);

      final parsed = ApiConfig.parseApiModelId('api:groq/llama-3.1-8b-instant');
      expect(parsed, isNotNull);
      expect(parsed!.providerId, 'groq');
      expect(parsed.model, 'llama-3.1-8b-instant');

      expect(ApiConfig.parseApiModelId('api:sin-modelo'), isNull);
      expect(
        ApiConfig.displayNameFor('api:groq/llama-3.1-8b-instant'),
        'Groq · llama-3.1-8b-instant',
      );
      expect(ApiConfig.displayNameFor('llama3:latest'), 'llama3:latest');
    });
  });

  group('ApiKeyStore.parse', () {
    test('analiza separadores :, = y ; con líneas en blanco y continuación',
        () {
      final result = ApiKeyStore.instance.parse(sampleFile);

      expect(result.totalParsed, 15);
      expect(result.imported, hasLength(15));
      expect(result.unrecognized, isEmpty);
      expect(result.ignored, isEmpty);
      // La segunda línea bajo AI-HORDE no se descarta en silencio.
      expect(result.extraKeys['aihorde'], 'ooo');
      expect(
        result.imported,
        containsAll(<String>[
          'deepseek',
          'gemini',
          'openrouter',
          'mistral',
          'xai',
          'anthropic',
          'openai',
          'perplexity',
          'xiaomi',
          'zen',
          'huggingface',
          'minimax',
          'sambanova',
          'aihorde',
          'groq',
        ]),
      );
    });

    test('deja constancia de lo que no reconoce en lugar de ignorarlo', () {
      final result =
          ApiKeyStore.instance.parse('FALOO: clave\nlinea sin separador\n');

      expect(result.imported, isEmpty);
      expect(result.unrecognized.single, contains('FALOO'));
      expect(result.ignored.single, contains('linea sin separador'));
    });
  });

  group('ApiKeyStore importación', () {
    test('guarda las claves y sobreviven a una recarga', () async {
      final store = ApiKeyStore.instance;
      await store.load();

      final result = await store.import(sampleFile);
      expect(result.hasChanges, isTrue);
      expect(store.apiKeyOf('groq'), 'gsk_pppp');
      expect(store.entry('anthropic')!.apiKey, 'ffff');

      // Recarga desde las preferencias: mismo estado, sin memoria en RAM.
      store.resetForTest();
      await store.load();
      expect(store.apiKeyOf('groq'), 'gsk_pppp');
      expect(store.configured, hasLength(15));
    });

    test('conserva el modelo elegido al reimportar la clave', () async {
      final store = ApiKeyStore.instance;
      await store.load();
      await store.save(
          providerId: 'groq', apiKey: 'gsk_nueva', model: 'llama-3.1-8b');
      await store.import('Groq= gsk_otra\n');

      expect(store.apiKeyOf('groq'), 'gsk_otra');
      expect(store.modelOf('groq'), 'llama-3.1-8b');
      expect(store.selectableModelIds(), ['api:groq/llama-3.1-8b']);
    });

    test('rechaza guardar un proveedor fuera del catálogo', () async {
      final store = ApiKeyStore.instance;
      await store.load();
      await expectLater(
        store.save(providerId: 'inventado', apiKey: 'x' * 16),
        throwsArgumentError,
      );
    });
  });

  group('ApiService openai-compatible', () {
    late List<int> sentBody;
    late String sentPath;
    late Map<String, String> sentHeaders;

    ApiService serviceWith(String response, {int status = 200}) {
      return ApiService(
        client: capture(
          (request, body) {
            sentBody = body;
            sentPath = request.url.path;
            sentHeaders = request.headers;
          },
          (_) => sse(response, status: status),
        ),
      );
    }

    setUp(() async {
      final store = ApiKeyStore.instance;
      await store.load();
      await store.save(providerId: 'groq', apiKey: 'gsk_prueba');
      sentBody = <int>[];
      sentPath = '';
      sentHeaders = <String, String>{};
    });

    test('emite fragmentos y un cierre done con el finish_reason real',
        () async {
      final service = serviceWith(
        'data: {"choices":[{"delta":{"content":"Hola"}}]}\n\n'
        'data: {"choices":[{"delta":{"content":" mundo"}}]}\n\n'
        'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}\n\n'
        'data: [DONE]\n\n',
      );

      final events = await service
          .generateChat(
            providerId: 'groq',
            model: 'llama-3.1-8b-instant',
            messages: [OllamaMessage(role: 'user', content: 'hola')],
          )
          .toList();

      expect(sentPath, '/openai/v1/chat/completions');
      expect(header(sentHeaders, 'authorization'), 'Bearer gsk_prueba');
      final payload = jsonDecode(utf8.decode(sentBody)) as Map<String, dynamic>;
      expect(payload['model'], 'llama-3.1-8b-instant');
      expect(payload['stream'], isTrue);

      expect(events.map((event) => event.message).join(), 'Hola mundo');
      expect(events.last.done, isTrue);
      expect(events.last.doneReason, 'stop');
    });

    test('devuelve el mensaje de error real del proveedor', () async {
      final service = serviceWith(
        '{"error":{"message":"Invalid API key provided"}}',
        status: 401,
      );

      await expectLater(
        service
            .generateChat(
              providerId: 'groq',
              model: 'llama-3.1-8b-instant',
              messages: [OllamaMessage(role: 'user', content: 'hola')],
            )
            .toList(),
        throwsHttpContaining('Invalid API key provided'),
      );
    });

    test('falla sin clave y con el nombre real del proveedor', () async {
      final service = serviceWith('data: [DONE]\n\n');
      await expectLater(
        service
            .generateChat(
              providerId: 'deepseek',
              model: 'deepseek-chat',
              messages: [OllamaMessage(role: 'user', content: 'hola')],
            )
            .toList(),
        throwsStateContaining('DeepSeek'),
      );
    });
  });

  group('ApiService anthropic', () {
    setUp(() async {
      final store = ApiKeyStore.instance;
      await store.load();
      await store.save(providerId: 'anthropic', apiKey: 'ant_prueba');
    });

    test('usa el protocolo propio y separa el system', () async {
      late String path;
      late Map<String, String> headers;
      late Map<String, dynamic> payload;
      final service = ApiService(
        client: capture(
          (request, body) {
            path = request.url.path;
            headers = request.headers;
            payload = jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
          },
          (_) => sse(
            'event: content_block_delta\n'
            'data: {"delta":{"type":"text_delta","text":"hola"}}\n\n'
            'event: message_delta\n'
            'data: {"delta":{"stop_reason":"end_turn"}}\n\n'
            'event: message_stop\n'
            'data: {"type":"message_stop"}\n\n',
          ),
        ),
      );

      final events = await service
          .generateChat(
            providerId: 'anthropic',
            model: 'claude-3-5-haiku-latest',
            messages: [
              OllamaMessage(role: 'system', content: 'Eres breve.'),
              OllamaMessage(role: 'user', content: 'hola'),
            ],
          )
          .toList();

      expect(path, '/v1/messages');
      expect(header(headers, 'x-api-key'), isNotEmpty);
      expect(header(headers, 'anthropic-version'), '2023-06-01');
      expect(payload['system'], 'Eres breve.');
      expect(payload['stream'], isTrue);
      expect(payload['messages'], hasLength(1));

      expect(events.first.message, 'hola');
      expect(events.last.done, isTrue);
      expect(events.last.doneReason, 'end_turn');
    });
  });

  group('ApiService gemini', () {
    setUp(() async {
      final store = ApiKeyStore.instance;
      await store.load();
      await store.save(providerId: 'gemini', apiKey: 'AIzaprueba');
    });

    test('apunta a streamGenerateContent con la cabecera de clave', () async {
      late String path;
      late Map<String, String> headers;
      final service = ApiService(
        client: capture(
          (request, _) {
            path = request.url.toString();
            headers = request.headers;
          },
          (_) => sse(
            'data: {"candidates":[{"content":{"parts":[{"text":"hola"}]},'
            '"finishReason":"STOP"}]}\n\n',
          ),
        ),
      );

      final events = await service
          .generateChat(
            providerId: 'gemini',
            model: 'gemini-2.0-flash',
            messages: [OllamaMessage(role: 'user', content: 'hola')],
          )
          .toList();

      expect(path, contains('/v1beta/models/gemini-2.0-flash:'));
      expect(path, contains('streamGenerateContent'));
      expect(header(headers, 'x-goog-api-key'), isNotEmpty);
      expect(events.first.message, 'hola');
      expect(events.last.done, isTrue);
    });
  });

  group('ApiService AI Horde', () {
    setUp(() async {
      final store = ApiKeyStore.instance;
      await store.load();
      await store.save(providerId: 'aihorde', apiKey: 'horde_prueba');
    });

    test('cola sin streaming: espera y devuelve el texto final', () async {
      final paths = <String>[];
      final service = ApiService(
        client: capture(
          (request, _) => paths.add(request.url.path),
          (request) {
            if (request.url.path.endsWith('/async')) {
              return sse('{"id":"job-1"}');
            }
            return sse('{"done":true,"generations":[{"text":"respuesta"}]}');
          },
        ),
      );

      final events = await service
          .generateChat(
            providerId: 'aihorde',
            model: 'anything',
            messages: [OllamaMessage(role: 'user', content: 'hola')],
          )
          .toList();

      expect(paths.first, '/api/v2/generate/text/async');
      expect(paths.last, '/api/v2/generate/text/status/job-1');
      // Un solo texto y un solo cierre: no se simula un stream falso.
      expect(
        events
            .where((event) => event.message.isNotEmpty)
            .map((event) => event.message),
        ['respuesta'],
      );
      expect(events.last.done, isTrue);
      expect(events.where((event) => event.done), hasLength(1));
    });
  });

  group('ApiService testConnection', () {
    test('valida la clave contra el listado de modelos sin modelo elegido',
        () async {
      final store = ApiKeyStore.instance;
      await store.load();
      await store.save(providerId: 'groq', apiKey: 'gsk_prueba');

      final service = ApiService(
        client: MockClient.streaming(
          (_, __) async => sse('{"data":[{"id":"a"},{"id":"b"}]}'),
        ),
      );

      final message = await service.testConnection(providerId: 'groq');
      expect(message, contains('Clave válida'));
      expect(message, contains('2 modelos'));
    });

    test('hace una generación mínima cuando hay modelo elegido', () async {
      final store = ApiKeyStore.instance;
      await store.load();
      await store.save(
          providerId: 'groq', apiKey: 'gsk_prueba', model: 'llama-3.1-8b');

      final service = ApiService(
        client: MockClient.streaming(
          (_, __) async => sse('{"choices":[{"message":{"content":"hola"}}]}'),
        ),
      );

      final message = await service.testConnection(
        providerId: 'groq',
        model: 'llama-3.1-8b',
      );
      expect(message, contains('Conexión real OK'));
      expect(message, contains('Groq'));
    });

    test('propaga el error real cuando la clave no vale', () async {
      final store = ApiKeyStore.instance;
      await store.load();
      await store.save(providerId: 'groq', apiKey: 'gsk_mala');

      final service = ApiService(
        client: MockClient.streaming(
          (_, __) async =>
              sse('{"error":{"message":"Invalid API Key"}}', status: 401),
        ),
      );

      await expectLater(
        service.testConnection(providerId: 'groq'),
        throwsHttpContaining('Invalid API Key'),
      );
    });
  });
}
