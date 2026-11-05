import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../config/chat_config.dart';
import 'api_key_store.dart';
import 'ollama_service.dart';

/// Cliente HTTP de los proveedores de API cloud (backend opcional del chat).
///
/// Devuelve el mismo tipo de evento que `OllamaService.generateChat`
/// (`OllamaChatResponse`) para que `ChatServiceOllama` use ambos backends con
/// la misma lógica de streaming, parada, regenerar y error visible.
///
/// Adaptadores: `openai-compatible` (SSE), `anthropic` (SSE), `gemini` (SSE)
/// y `ai-horde` (cola asíncrona **sin streaming**: se declara, no se simula
/// un flujo falso).
class ApiService {
  ApiService({http.Client? client}) : _injectedClient = client;

  static final ApiService instance = ApiService();

  /// Cliente inyectado solo por las pruebas; en producción cada petición
  /// crea el suyo para poder cancelar cerrando la conexión.
  final http.Client? _injectedClient;

  http.Client _newClient() => _injectedClient ?? http.Client();

  void _releaseClient(http.Client client) {
    if (_injectedClient == null) {
      client.close();
    }
  }

  // ───────────────────────────── Chat (streaming) ───────────────────────────

  /// Genera una respuesta del proveedor [providerId] con el modelo [model].
  ///
  /// El contrato es idéntico al de `OllamaService.generateChat`: emite
  /// fragmentos con `done: false` y un último evento con `done: true`; los
  /// fallos se lanzan como excepción (nunca se ocultan); [cancellation]
  /// cancela la petición.
  Stream<OllamaChatResponse> generateChat({
    required String providerId,
    required String model,
    required List<OllamaMessage> messages,
    double? temperature,
    int? numPredict,
    Future<void>? cancellation,
    Duration connectionTimeout = ChatConfig.connectionTimeout,
    Duration inactivityTimeout = ChatConfig.inactivityTimeout,
  }) async* {
    final provider = _requireProvider(providerId);
    final apiKey = _requireKey(provider);
    final normalizedModel = model.trim();
    if (normalizedModel.isEmpty) {
      throw StateError(
          'Sin modelo definido para ${provider.displayName}. '
          'Elige un modelo en la pestaña APIs.');
    }

    if (provider.adapter == ApiAdapter.aiHorde) {
      yield* _generateHorde(
        provider: provider,
        apiKey: apiKey,
        model: normalizedModel,
        messages: messages,
        temperature: temperature,
        numPredict: numPredict,
        cancellation: cancellation,
        connectionTimeout: connectionTimeout,
        inactivityTimeout: inactivityTimeout,
      );
      return;
    }

    final client = _newClient();
    var cancelled = false;
    try {
      final request = _buildRequest(
        provider: provider,
        apiKey: apiKey,
        model: normalizedModel,
        messages: messages,
        temperature: temperature,
        numPredict: numPredict,
        stream: true,
      );
      final sending = client.send(request).timeout(
            connectionTimeout,
            onTimeout: () => throw TimeoutException(
              '${provider.displayName} no respondió al iniciar la petición.',
              connectionTimeout,
            ),
          );
      final abort = cancellation?.then<http.StreamedResponse>((_) {
        cancelled = true;
        _releaseClient(client);
        throw const HttpException('Petición cancelada');
      });
      final response = await (abort == null
          ? sending
          : Future.any<http.StreamedResponse>([sending, abort]));
      if (cancelled) {
        return;
      }
      if (response.statusCode != HttpStatus.ok) {
        final detail = await _errorDetail(response, inactivityTimeout);
        throw HttpException('HTTP ${response.statusCode}'
            '${detail.isEmpty ? '' : ': $detail'}');
      }

      final parser = _StreamParser(provider.adapter);
      await for (final event in _sseLines(response.stream, inactivityTimeout)) {
        if (cancelled) {
          return;
        }
        for (final item in parser.parse(event.event, event.data)) {
          yield item;
        }
      }
      if (cancelled) {
        return;
      }
      // EOF sin `done` es interrupción (AGENTS.md §12), no un final limpio.
      if (!parser.doneSeen) {
        throw const HttpException(
            'La conexión terminó antes de confirmar la respuesta completa.');
      }
    } catch (error) {
      if (!cancelled) {
        rethrow;
      }
    } finally {
      _releaseClient(client);
    }
  }

  // ─────────────────────────── AI Horde (sin streaming) ─────────────────────

  Stream<OllamaChatResponse> _generateHorde({
    required ApiProvider provider,
    required String apiKey,
    required String model,
    required List<OllamaMessage> messages,
    required double? temperature,
    required int? numPredict,
    required Future<void>? cancellation,
    required Duration connectionTimeout,
    required Duration inactivityTimeout,
  }) async* {
    final client = _newClient();
    var cancelled = false;
    final signal = cancellation ?? Completer<void>().future;
    if (cancellation != null) {
      unawaited(cancellation.then((_) => cancelled = true));
    }
    try {
      final submit = _hordePost(
        client: client,
        provider: provider,
        apiKey: apiKey,
        path: '/generate/text/async',
        body: <String, dynamic>{
          'prompt': _hordePrompt(messages),
          'params': <String, dynamic>{
            'max_length': numPredict ?? 512,
            if (temperature != null) 'temperature': temperature,
            'n': 1,
          },
          if (model.isNotEmpty) 'models': [model],
        },
      ).timeout(
        connectionTimeout,
        onTimeout: () => throw TimeoutException(
          'AI Horde no respondió al enviar la petición.',
          connectionTimeout,
        ),
      );
      final abort = cancellation?.then<http.Response>((_) {
        cancelled = true;
        _releaseClient(client);
        throw const HttpException('Petición cancelada');
      });
      final response = await (abort == null
          ? submit
          : Future.any<http.Response>([submit, abort]));
      if (cancelled) {
        return;
      }
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('HTTP ${response.statusCode}'
            '${_hordeMessage(response.body).isEmpty
                ? ''
                : ': ${_hordeMessage(response.body)}'}');
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final jobId = decoded is Map ? decoded['id'] : null;
      if (jobId is! String || jobId.isEmpty) {
        throw StateError('AI Horde no devolvió identificador de trabajo.');
      }

      final deadline = DateTime.now().add(inactivityTimeout);
      while (true) {
        await Future.any<void>([
          Future<void>.delayed(const Duration(seconds: 3)),
          signal.then<void>((_) {}),
        ]);
        if (cancelled) {
          return;
        }
        if (DateTime.now().isAfter(deadline)) {
          throw TimeoutException(
              'AI Horde sigue en cola tras '
              '${inactivityTimeout.inMinutes} minutos.',
              inactivityTimeout);
        }
        final statusResponse = await _hordeGet(
          client: client,
          provider: provider,
          apiKey: apiKey,
          path: '/generate/text/status/$jobId',
        ).timeout(
          connectionTimeout,
          onTimeout: () => throw TimeoutException(
            'AI Horde dejó de responder al consultar el estado.',
            connectionTimeout,
          ),
        );
        if (statusResponse.statusCode != HttpStatus.ok) {
          throw HttpException('HTTP ${statusResponse.statusCode}'
              '${_hordeMessage(statusResponse.body).isEmpty
                  ? ''
                  : ': ${_hordeMessage(statusResponse.body)}'}');
        }
        final status = jsonDecode(utf8.decode(statusResponse.bodyBytes));
        if (status is! Map) {
          throw StateError('AI Horde devolvió un estado no interpretable.');
        }
        if (status['faulted'] == true) {
          throw StateError(
              'AI Horde falló: ${_hordeMessage(jsonEncode(status))}');
        }
        if (status['done'] == true) {
          final generations = status['generations'];
          final text = generations is List && generations.isNotEmpty
              ? (generations.first is Map
                  ? (generations.first['text'] as String? ?? '')
                  : '')
              : '';
          if (text.isEmpty) {
            throw StateError('AI Horde terminó sin texto.');
          }
          yield OllamaChatResponse(message: text, done: false);
          yield OllamaChatResponse(
              message: '', done: true, doneReason: 'stop');
          return;
        }
      }
    } catch (error) {
      if (!cancelled) {
        rethrow;
      }
    } finally {
      _releaseClient(client);
    }
  }

  Map<String, String> _hordeHeaders(String apiKey) => <String, String>{
        'apikey': apiKey,
        'Content-Type': 'application/json',
        'Client-Agent': 'LightChat:desktop:1.0',
      };

  Future<http.Response> _hordePost({
    required http.Client client,
    required ApiProvider provider,
    required String apiKey,
    required String path,
    required Map<String, dynamic> body,
  }) {
    return client.post(
      Uri.parse('${_trimSlash(provider.baseUrl)}$path'),
      headers: _hordeHeaders(apiKey),
      body: jsonEncode(body),
    );
  }

  Future<http.Response> _hordeGet({
    required http.Client client,
    required ApiProvider provider,
    required String apiKey,
    required String path,
  }) {
    return client.get(
      Uri.parse('${_trimSlash(provider.baseUrl)}$path'),
      headers: <String, String>{'apikey': apiKey},
    );
  }

  /// Traduce el mensaje de error real de AI Horde (texto o JSON).
  String _hordeMessage(String body) {
    var detail = body.trim();
    if (detail.isEmpty) {
      return '';
    }
    try {
      final decoded = jsonDecode(detail);
      if (decoded is Map) {
        final message = decoded['message'] ?? decoded['errors'];
        if (message != null) {
          detail = message.toString();
        }
      }
    } on FormatException {
      // AI Horde a veces responde texto plano.
    }
    return detail;
  }

  /// Formato de prompt de AI Horde: no tiene roles, solo texto continuo.
  String _hordePrompt(List<OllamaMessage> messages) {
    final buffer = StringBuffer();
    for (final message in messages) {
      if (message.role == 'system') {
        buffer
          ..writeln(message.content)
          ..writeln();
      } else if (message.role == 'user') {
        buffer.writeln('Usuario: ${message.content}');
      } else {
        buffer.writeln('Asistente: ${message.content}');
      }
    }
    buffer.write('Asistente:');
    return buffer.toString().trim();
  }

  // ────────────────────────────── Construcción ──────────────────────────────

  ApiProvider _requireProvider(String providerId) {
    final provider = ApiConfig.byId(providerId);
    if (provider == null) {
      throw StateError('Proveedor de API no reconocido: $providerId');
    }
    return provider;
  }

  String _requireKey(ApiProvider provider) {
    final apiKey = ApiKeyStore.instance.apiKeyOf(provider.id) ?? '';
    if (apiKey.isEmpty) {
      throw StateError(
          'Falta la clave de API de ${provider.displayName}. '
          'Añádela en la pestaña APIs.');
    }
    return apiKey;
  }

  static String _trimSlash(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;

  http.Request _buildRequest({
    required ApiProvider provider,
    required String apiKey,
    required String model,
    required List<OllamaMessage> messages,
    required double? temperature,
    required int? numPredict,
    required bool stream,
  }) {
    final base = _trimSlash(provider.baseUrl);
    switch (provider.adapter) {
      case ApiAdapter.openaiCompatible:
        final request =
            http.Request('POST', Uri.parse('$base/chat/completions'));
        request.headers['Authorization'] = 'Bearer $apiKey';
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(<String, dynamic>{
          'model': model,
          'messages': _openaiMessages(messages),
          'stream': stream,
          if (temperature != null) 'temperature': temperature,
          if (numPredict != null) 'max_tokens': numPredict,
        });
        return request;
      case ApiAdapter.anthropic:
        final request = http.Request('POST', Uri.parse('$base/messages'));
        request.headers['x-api-key'] = apiKey;
        request.headers['anthropic-version'] = '2023-06-01';
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(<String, dynamic>{
          'model': model,
          'messages': _anthropicMessages(messages),
          if (_systemText(messages).isNotEmpty)
            'system': _systemText(messages),
          'max_tokens': numPredict ?? 1024,
          if (temperature != null) 'temperature': temperature,
          'stream': stream,
        });
        return request;
      case ApiAdapter.gemini:
        final cleanModel = model.startsWith('models/')
            ? model.substring('models/'.length)
            : model;
        final action = stream ? 'streamGenerateContent?alt=sse' : 'generateContent';
        final request =
            http.Request('POST', Uri.parse('$base/models/$cleanModel:$action'));
        request.headers['x-goog-api-key'] = apiKey;
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(<String, dynamic>{
          'contents': _geminiContents(messages),
          if (_systemText(messages).isNotEmpty)
            'systemInstruction': <String, dynamic>{
              'parts': <Map<String, dynamic>>[
                {'text': _systemText(messages)},
              ],
            },
          if (temperature != null || numPredict != null)
            'generationConfig': <String, dynamic>{
              if (temperature != null) 'temperature': temperature,
              if (numPredict != null) 'maxOutputTokens': numPredict,
            },
        });
        return request;
      case ApiAdapter.aiHorde:
        throw StateError('AI Horde no usa peticiones de chat directas.');
    }
  }

  String _systemText(List<OllamaMessage> messages) => messages
      .where((message) => message.role == 'system')
      .map((message) => message.content)
      .join('\n\n');

  List<Map<String, dynamic>> _openaiMessages(List<OllamaMessage> messages) =>
      messages.map((message) {
        final images = message.images ?? const <OllamaImage>[];
        if (images.isEmpty) {
          return <String, dynamic>{
            'role': message.role,
            'content': message.content,
          };
        }
        return <String, dynamic>{
          'role': message.role,
          'content': <dynamic>[
            <String, dynamic>{'type': 'text', 'text': message.content},
            for (final image in images)
              <String, dynamic>{
                'type': 'image_url',
                'image_url': <String, dynamic>{'url': _dataUrl(image.base64Data)},
              },
          ],
        };
      }).toList(growable: false);

  List<Map<String, dynamic>> _anthropicMessages(List<OllamaMessage> messages) =>
      messages
          .where((message) => message.role != 'system')
          .map((message) {
            final images = message.images ?? const <OllamaImage>[];
            if (images.isEmpty) {
              return <String, dynamic>{
                'role': message.role,
                'content': message.content,
              };
            }
            return <String, dynamic>{
              'role': message.role,
              'content': <dynamic>[
                <String, dynamic>{'type': 'text', 'text': message.content},
                for (final image in images)
                  <String, dynamic>{
                    'type': 'image',
                    'source': <String, dynamic>{
                      'type': 'base64',
                      'media_type': _imageMediaType(image.base64Data),
                      'data': image.base64Data,
                    },
                  },
              ],
            };
          })
          .toList(growable: false);

  List<Map<String, dynamic>> _geminiContents(List<OllamaMessage> messages) =>
      messages
          .where((message) => message.role != 'system')
          .map((message) {
            final images = message.images ?? const <OllamaImage>[];
            return <String, dynamic>{
              'role': message.role == 'assistant' ? 'model' : 'user',
              'parts': <dynamic>[
                if (message.content.isNotEmpty)
                  <String, dynamic>{'text': message.content},
                for (final image in images)
                  <String, dynamic>{
                    'inlineData': <String, dynamic>{
                      'mimeType': _imageMediaType(image.base64Data),
                      'data': image.base64Data,
                    },
                  },
              ],
            };
          })
          .toList(growable: false);

  /// MIME deducido de los primeros bytes reales de la imagen (no del nombre).
  static String _imageMediaType(String base64) {
    final head = base64.length > 12 ? base64.substring(0, 12) : base64;
    if (head.startsWith('/9j/')) {
      return 'image/jpeg';
    }
    if (head.startsWith('R0lGOD')) {
      return 'image/gif';
    }
    if (head.startsWith('UklGR')) {
      return 'image/webp';
    }
    if (head.startsWith('AAAAIGZt') || head.startsWith('AAAAIGZo')) {
      return 'image/heic';
    }
    return 'image/png';
  }

  static String _dataUrl(String base64) =>
      'data:${_imageMediaType(base64)};base64,$base64';

  // ─────────────────────────────── SSE ──────────────────────────────────────

  /// Divide un flujo SSE en pares `(event, data)`.
  Stream<({String event, String data})> _sseLines(
    Stream<List<int>> stream,
    Duration inactivityTimeout,
  ) async* {
    var event = 'message';
    await for (final line in stream
        .timeout(inactivityTimeout)
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (line.isEmpty) {
        event = 'message';
        continue;
      }
      if (line.startsWith(':')) {
        continue;
      }
      if (line.startsWith('event:')) {
        event = line.substring(6).trim();
        continue;
      }
      if (line.startsWith('data:')) {
        yield (event: event, data: line.substring(5).trim());
        event = 'message';
      }
    }
  }

  // ───────────────────────────── Errores ────────────────────────────────────

  Future<String> _errorDetail(
    http.StreamedResponse response,
    Duration inactivityTimeout,
  ) async {
    final body = <int>[];
    try {
      await for (final chunk in response.stream.timeout(inactivityTimeout)) {
        final remaining = ChatConfig.maxErrorBodyBytes - body.length;
        body.addAll(chunk.take(remaining));
        if (body.length >= ChatConfig.maxErrorBodyBytes) {
          break;
        }
      }
    } on TimeoutException {
      // Sin cuerpo: el código de estado ya es el dato real.
    }
    return _detailFromBytes(body);
  }

  /// Extrae el mensaje real del cuerpo de un error (JSON o texto plano).
  String _detailFromBytes(List<int> body) {
    var detail = utf8.decode(body, allowMalformed: true).trim();
    if (detail.isEmpty) {
      return '';
    }
    try {
      final decoded = jsonDecode(detail);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map) {
          detail = (error['message'] ?? error).toString();
        } else if (error != null) {
          detail = error.toString();
        } else if (decoded['message'] != null) {
          detail = decoded['message'].toString();
        }
      }
    } on FormatException {
      // El proveedor devolvió texto plano.
    }
    return detail;
  }

  // ───────────────────────── Test de conexión ───────────────────────────────

  /// Comprueba la clave con una llamada **real** al proveedor.
  ///
  /// Sin [model] valida la clave contra el listado de modelos; con [model]
  /// hace una generación mínima. Devuelve un mensaje con lo observado y
  /// lanza excepción con el error real del proveedor si falla.
  Future<String> testConnection({
    required String providerId,
    String model = '',
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final provider = _requireProvider(providerId);
    final apiKey = _requireKey(provider);
    final normalizedModel = model.trim();
    if (provider.adapter == ApiAdapter.aiHorde) {
      return _testHorde(provider, apiKey, timeout);
    }
    final client = _newClient();
    try {
      switch (provider.adapter) {
        case ApiAdapter.openaiCompatible:
          if (normalizedModel.isEmpty) {
            return await _testList(
              client: client,
              url: '${_trimSlash(provider.baseUrl)}/models',
              headers: {'Authorization': 'Bearer $apiKey'},
              emptyMessage:
                  'Clave válida en ${provider.displayName}, pero el listado '
                  'de modelos vino vacío.',
              timeout: timeout,
            );
          }
          return await _testChat(
            client: client,
            request: _buildRequest(
              provider: provider,
              apiKey: apiKey,
              model: normalizedModel,
              messages: [OllamaMessage(role: 'user', content: 'hola')],
              temperature: 0,
              numPredict: 1,
              stream: false,
            ),
            providerName: provider.displayName,
            timeout: timeout,
          );
        case ApiAdapter.anthropic:
          if (normalizedModel.isEmpty) {
            return await _testList(
              client: client,
              url: '${_trimSlash(provider.baseUrl)}/models',
              headers: {
                'x-api-key': apiKey,
                'anthropic-version': '2023-06-01',
              },
              emptyMessage:
                  'Clave válida en ${provider.displayName}, pero el listado '
                  'de modelos vino vacío.',
              timeout: timeout,
            );
          }
          return await _testChat(
            client: client,
            request: _buildRequest(
              provider: provider,
              apiKey: apiKey,
              model: normalizedModel,
              messages: [OllamaMessage(role: 'user', content: 'hola')],
              temperature: 0,
              numPredict: 1,
              stream: false,
            ),
            providerName: provider.displayName,
            timeout: timeout,
          );
        case ApiAdapter.gemini:
          final cleanModel = normalizedModel.startsWith('models/')
              ? normalizedModel.substring('models/'.length)
              : normalizedModel;
          if (cleanModel.isEmpty) {
            return await _testList(
              client: client,
              url: '${_trimSlash(provider.baseUrl)}/models',
              headers: {'x-goog-api-key': apiKey},
              emptyMessage:
                  'Clave válida en ${provider.displayName}, pero el listado '
                  'de modelos vino vacío.',
              timeout: timeout,
            );
          }
          return await _testChat(
            client: client,
            request: _buildRequest(
              provider: provider,
              apiKey: apiKey,
              model: cleanModel,
              messages: [OllamaMessage(role: 'user', content: 'hola')],
              temperature: 0,
              numPredict: 1,
              stream: false,
            ),
            providerName: provider.displayName,
            timeout: timeout,
          );
        case ApiAdapter.aiHorde:
          return 'AI Horde se comprueba con una cola real.';
      }
    } finally {
      _releaseClient(client);
    }
  }

  Future<String> _testList({
    required http.Client client,
    required String url,
    required Map<String, String> headers,
    required String emptyMessage,
    required Duration timeout,
  }) async {
    final response = await client
        .get(Uri.parse(url), headers: headers)
        .timeout(timeout, onTimeout: () => throw TimeoutException(
              'Sin respuesta en ${timeout.inSeconds} s.',
              timeout,
            ));
    if (response.statusCode != HttpStatus.ok) {
      final detail = _detailFromBytes(response.bodyBytes);
      throw HttpException('HTTP ${response.statusCode}'
          '${detail.isEmpty ? '' : ': $detail'}');
    }
    var count = 0;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        final list = decoded['data'] ?? decoded['models'];
        count = list is List ? list.length : 0;
      } else if (decoded is List) {
        count = decoded.length;
      }
    } on FormatException {
      return 'Clave aceptada por el proveedor (respuesta no JSON).';
    }
    if (count == 0) {
      return emptyMessage;
    }
    return 'Clave válida: $count modelos disponibles.';
  }

  Future<String> _testChat({
    required http.Client client,
    required http.Request request,
    required String providerName,
    required Duration timeout,
  }) async {
    final response = await client
        .send(request)
        .timeout(timeout, onTimeout: () => throw TimeoutException(
              '$providerName no respondió en ${timeout.inSeconds} s.',
              timeout,
            ));
    if (response.statusCode != HttpStatus.ok) {
      final detail = await _errorDetail(response, timeout);
      throw HttpException('HTTP ${response.statusCode}'
          '${detail.isEmpty ? '' : ': $detail'}');
    }
    final body = await response.stream
        .bytesToString()
        .timeout(timeout, onTimeout: () => throw TimeoutException(
              '$providerName no terminó la respuesta de prueba.',
              timeout,
            ));
    var text = '';
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final choices = decoded['choices'];
        if (choices is List && choices.isNotEmpty && choices.first is Map) {
          final choice = choices.first as Map;
          final message = choice['message'] ?? choice['delta'];
          if (message is Map && message['content'] is String) {
            text = message['content'] as String;
          }
        }
        final candidates = decoded['candidates'];
        if (candidates is List && candidates.isNotEmpty) {
          final candidate = candidates.first;
          if (candidate is Map && candidate['content'] is Map) {
            final parts = (candidate['content'] as Map)['parts'];
            if (parts is List) {
              text = parts
                  .whereType<Map>()
                  .map((part) => part['text'] ?? '')
                  .join();
            }
          }
        }
      }
    } on FormatException {
      throw StateError('$providerName devolvió una respuesta no interpretable.');
    }
    final suffix = text.isEmpty
        ? ''
        : ' «${text.length > 40 ? '${text.substring(0, 40)}…' : text}»';
    return 'Conexión real OK con $providerName: el modelo respondió$suffix.';
  }

  Future<String> _testHorde(
    ApiProvider provider,
    String apiKey,
    Duration timeout,
  ) async {
    final client = _newClient();
    try {
      final response = await _hordePost(
        client: client,
        provider: provider,
        apiKey: apiKey,
        path: '/generate/text/async',
        body: <String, dynamic>{
          'prompt': 'Responde solo: hola',
          'params': <String, dynamic>{'max_length': 16, 'n': 1},
        },
      ).timeout(timeout, onTimeout: () => throw TimeoutException(
            'AI Horde no respondió en ${timeout.inSeconds} s.',
            timeout,
          ));
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('HTTP ${response.statusCode}'
            '${_hordeMessage(response.body).isEmpty
                ? ''
                : ': ${_hordeMessage(response.body)}'}');
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final jobId = decoded is Map ? decoded['id'] : null;
      if (jobId is! String || jobId.isEmpty) {
        throw StateError('AI Horde no devolvió identificador de trabajo.');
      }
      final deadline = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(seconds: 3));
        final status = await _hordeGet(
          client: client,
          provider: provider,
          apiKey: apiKey,
          path: '/generate/text/status/$jobId',
        ).timeout(timeout, onTimeout: () => throw TimeoutException(
              'AI Horde dejó de responder al consultar el estado.',
              timeout,
            ));
        if (status.statusCode != HttpStatus.ok) {
          throw HttpException('HTTP ${status.statusCode}'
              '${_hordeMessage(status.body).isEmpty
                  ? ''
                  : ': ${_hordeMessage(status.body)}'}');
        }
        final decodedStatus = jsonDecode(status.body);
        if (decodedStatus is! Map) {
          throw StateError('AI Horde devolvió un estado no interpretable.');
        }
        if (decodedStatus['faulted'] == true) {
          throw StateError(
              'AI Horde falló: ${_hordeMessage(status.body)}');
        }
        if (decodedStatus['done'] == true) {
          return 'Cola de AI Horde aceptó la petición y devolvió texto real.';
        }
        final position = decodedStatus['queue_position'];
        if (position is num && position >= 0) {
          return 'Clave aceptada por AI Horde: en cola (posición $position). '
              'Los trabajadores son voluntarios, la respuesta tarda.';
        }
      }
      throw TimeoutException('AI Horde no confirmó la cola a tiempo.', timeout);
    } finally {
      _releaseClient(client);
    }
  }
}

/// Convierte los eventos SSE de cada adaptador al contrato de Ollama.
class _StreamParser {
  _StreamParser(this.adapter);

  final ApiAdapter adapter;

  String _finishReason = '';
  bool doneSeen = false;

  List<OllamaChatResponse> parse(String event, String data) {
    if (data.isEmpty) {
      return const [];
    }
    switch (adapter) {
      case ApiAdapter.openaiCompatible:
        return _parseOpenAi(data);
      case ApiAdapter.anthropic:
        return _parseAnthropic(event, data);
      case ApiAdapter.gemini:
        return _parseGemini(data);
      case ApiAdapter.aiHorde:
        return const [];
    }
  }

  List<OllamaChatResponse> _parseOpenAi(String data) {
    if (data == '[DONE]') {
      return _finish();
    }
    final decoded = _decode(data);
    final error = decoded['error'];
    if (error != null) {
      throw StateError(error is Map
          ? (error['message'] ?? error).toString()
          : error.toString());
    }
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      return const [];
    }
    final choice = choices.first as Map;
    final source = choice['delta'] ?? choice['message'];
    final texts = <OllamaChatResponse>[];
    if (source is Map && source['content'] is String) {
      final text = source['content'] as String;
      if (text.isNotEmpty) {
        texts.add(OllamaChatResponse(message: text, done: false));
      }
    }
    final finish = choice['finish_reason'];
    if (finish is String && finish.isNotEmpty) {
      _finishReason = finish;
      return [...texts, ..._finish()];
    }
    return texts;
  }

  List<OllamaChatResponse> _parseAnthropic(String event, String data) {
    final decoded = _decode(data);
    switch (event) {
      case 'error':
        final error = decoded['error'];
        throw StateError(error is Map
            ? (error['message'] ?? error).toString()
            : (error ?? data).toString());
      case 'content_block_delta':
        final delta = decoded['delta'];
        if (delta is Map && delta['text'] is String) {
          final text = delta['text'] as String;
          if (text.isEmpty) {
            return const [];
          }
          return [OllamaChatResponse(message: text, done: false)];
        }
        return const [];
      case 'message_delta':
        final delta = decoded['delta'];
        final stop = delta is Map ? delta['stop_reason'] : null;
        if (stop is String && stop.isNotEmpty) {
          _finishReason = stop;
        }
        return const [];
      case 'message_stop':
        return _finish();
      default:
        return const [];
    }
  }

  List<OllamaChatResponse> _parseGemini(String data) {
    final decoded = _decode(data);
    final feedback = decoded['promptFeedback'];
    if (feedback is Map && feedback['blockReason'] != null) {
      throw StateError(
          'Respuesta bloqueada por el proveedor: ${feedback['blockReason']}');
    }
    final candidates = decoded['candidates'];
    if (candidates is! List || candidates.isEmpty || candidates.first is! Map) {
      return const [];
    }
    final candidate = candidates.first as Map;
    final texts = <OllamaChatResponse>[];
    final content = candidate['content'];
    if (content is Map && content['parts'] is List) {
      for (final part in content['parts'] as List) {
        if (part is Map && part['text'] is String) {
          final text = part['text'] as String;
          if (text.isNotEmpty) {
            texts.add(OllamaChatResponse(message: text, done: false));
          }
        }
      }
    }
    final finish = candidate['finishReason'];
    if (finish is String && finish.isNotEmpty) {
      _finishReason = finish;
      return [...texts, ..._finish()];
    }
    return texts;
  }

  Map<String, dynamic> _decode(String data) {
    final decoded = jsonDecode(data);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('El proveedor envió un evento no interpretable.');
    }
    return decoded;
  }

  List<OllamaChatResponse> _finish() {
    if (doneSeen) {
      return const [];
    }
    doneSeen = true;
    return [
      OllamaChatResponse(
        message: '',
        done: true,
        doneReason: _finishReason.isEmpty ? null : _finishReason,
      ),
    ];
  }
}
