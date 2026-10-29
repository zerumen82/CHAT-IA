import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lightchat/services/ollama_service.dart';

void main() {
  late HttpServer server;
  late OllamaService service;
  var mode = 'normal';
  Completer<void>? release;
  Completer<void>? entered;

  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      try {
        if (request.uri.path == '/api/version') {
          request.response.write('{"version":"test"}');
        } else if (request.uri.path == '/api/tags') {
          request.response.write('{"models":[]}');
        } else if (request.uri.path == '/api/chat') {
          await utf8.decoder.bind(request).join();
          entered?.complete();
          // HttpResponse retiene bloques pequeños incluso entre addStream/flush.
          // El servidor debe entregar cada evento antes de quedar esperando.
          request.response.bufferOutput = false;
          request.response.headers.contentType =
              ContentType('application', 'x-ndjson');
          if (mode == 'beforeHeaders') {
            await release!.future;
          } else if (mode == 'inactive') {
            request.response
                .writeln('{"message":{"content":"parcial"},"done":false}');
            await request.response.flush();
            await release!.future;
          } else if (mode == 'thinking') {
            for (var i = 0; i < 5; i++) {
              request.response.writeln(jsonEncode({
                'message': {'thinking': 'paso $i'},
                'done': false,
              }));
              await request.response.flush();
              await Future<void>.delayed(const Duration(milliseconds: 50));
            }
          }
          request.response.writeln(
              '{"message":{"content":"final"},"done":true,"done_reason":"stop"}');
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      } on HttpException {
        // Los ensayos de cancelación/timeout cierran el cliente de verdad.
      } on SocketException {
        // Los ensayos de cancelación/timeout cierran el cliente de verdad.
      }
    });
    SharedPreferences.setMockInitialValues({
      'ollama_host': '127.0.0.1',
      'ollama_port': server.port,
    });
    service = OllamaService.instance;
    await service.initialize();
  });
  setUp(() {
    mode = 'normal';
    release = null;
    entered = null;
  });
  tearDown(() {
    if (release != null && !release!.isCompleted) {
      release!.complete();
    }
  });
  tearDownAll(() async {
    service.dispose();
    await server.close(force: true);
  });

  Stream<OllamaChatResponse> request(
          {Future<void>? cancellation,
          Duration connectionTimeout = const Duration(seconds: 3),
          Duration inactivityTimeout = const Duration(milliseconds: 150)}) =>
      service.generateChat(
          model: 'test',
          messages: [OllamaMessage(role: 'user', content: 'Hola')],
          cancellation: cancellation,
          connectionTimeout: connectionTimeout,
          inactivityTimeout: inactivityTimeout);

  test('cancels HTTP while still awaiting response headers', () async {
    mode = 'beforeHeaders';
    entered = Completer<void>();
    release = Completer<void>();
    final cancel = Completer<void>();
    final response = request(cancellation: cancel.future).toList();
    await entered!.future;
    cancel.complete();
    expect(await response.timeout(const Duration(seconds: 2)), isEmpty);
  });

  test('connection timeout includes the wait for first headers', () async {
    mode = 'beforeHeaders';
    release = Completer<void>();
    await expectLater(
        request(connectionTimeout: const Duration(milliseconds: 100)).toList(),
        throwsA(isA<TimeoutException>()));
  });

  test('inactivity timeout follows last data event', () async {
    mode = 'inactive';
    release = Completer<void>();
    final received = <OllamaChatResponse>[];
    await expectLater(
        request().map((item) {
          received.add(item);
          return item;
        }).toList(),
        throwsA(isA<TimeoutException>()));
    expect(received.single.message, 'parcial');
  });

  test('thinking events reset inactivity even with no visible answer tokens',
      () async {
    mode = 'thinking';
    final responses = await request().toList();
    expect(responses.where((item) => item.thinking.isNotEmpty).length, 5);
    expect(responses.last.message, 'final');
    expect(responses.last.doneReason, 'stop');
  });
}
