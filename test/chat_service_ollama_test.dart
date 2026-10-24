import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lightchat/models/document_attachment.dart';
import 'package:lightchat/services/chat_service_ollama.dart';
import 'package:lightchat/services/ollama_service.dart';

void main() {
  late HttpServer server;
  late List<Map<String, dynamic>> chatRequests;
  late bool failChatRequests;
  late ChatServiceOllama chatService;
  late Directory temporaryDirectory;

  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    chatRequests = [];
    failChatRequests = false;
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/api/tags') {
        request.response.write(jsonEncode({
          'models': [
            {'name': 'llama3:latest', 'model': 'llama3:latest', 'size': 1024}
          ]
        }));
      } else if (request.uri.path == '/api/version') {
        request.response.write(jsonEncode({'version': 'test'}));
      } else if (request.uri.path == '/api/chat') {
        if (failChatRequests) {
          request.response.statusCode = HttpStatus.internalServerError;
          await request.response.close();
          return;
        }
        final body = await utf8.decoder.bind(request).join();
        chatRequests.add(jsonDecode(body) as Map<String, dynamic>);
        request.response.headers.contentType =
            ContentType('application', 'x-ndjson');
        request.response
            .write('{"message":{"role":"assistant","content":"prim');
        await request.response.flush();
        await Future<void>.delayed(const Duration(milliseconds: 5));
        request.response.write(
            'era respuesta"},"done":false}\n{"message":{"role":"assistant","content":"!"},"done":true}\n');
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    SharedPreferences.setMockInitialValues({
      'ollama_host': '127.0.0.1',
      'ollama_port': server.port,
    });
    await OllamaService.instance.initialize();
  });

  setUp(() async {
    chatRequests.clear();
    failChatRequests = false;
    SharedPreferences.setMockInitialValues({
      'ollama_host': '127.0.0.1',
      'ollama_port': server.port,
      'chat_messages': '[]',
    });
    temporaryDirectory =
        await Directory.systemTemp.createTemp('lightchat-test');
    chatService = ChatServiceOllama();
    final initialLoad = Completer<void>();
    var loadingObserved = false;
    chatService.addListener(() {
      if (chatService.isLoadingModels) {
        loadingObserved = true;
      } else if (loadingObserved && !initialLoad.isCompleted) {
        initialLoad.complete();
      }
    });
    await initialLoad.future;
  });

  tearDown(() async {
    chatService.dispose();
    await temporaryDirectory.delete(recursive: true);
  });

  tearDownAll(() async {
    OllamaService.instance.dispose();
    await server.close(force: true);
  });

  test('preserves conversation turns and streams partial responses', () async {
    var sawPartialResponse = false;
    chatService.addListener(() {
      sawPartialResponse |= chatService.messages.any(
        (message) => !message.isUser && message.text.startsWith('prim'),
      );
    });

    await chatService.sendMessage('Hola');
    await chatService.sendMessage('¿Qué respondiste?');

    final secondTurn = (chatRequests[1]['messages'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    expect(secondTurn.map((message) => message['role']),
        ['system', 'user', 'assistant', 'user']);
    expect(secondTurn.map((message) => message['content']), [
      'Eres LightChat, un asistente útil y directo. Responde siempre en español.',
      'Hola',
      'primera respuesta!',
      '¿Qué respondiste?'
    ]);
    expect(chatRequests[0]['options'], {
      'temperature': 0.7,
      'num_predict': 2048,
      'num_ctx': 8192,
    });
    expect(sawPartialResponse, isTrue);
  });

  test('sends image-only messages and keeps images in conversation context',
      () async {
    final imageFile = File('${temporaryDirectory.path}\\test.png');
    await imageFile.writeAsBytes([1, 2, 3, 4]);

    await chatService.sendMessage('', imagePaths: [imageFile.path]);

    final sentMessages = (chatRequests.single['messages'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final sentUserMessage = sentMessages.last;
    expect(sentUserMessage['content'], '');
    expect(sentUserMessage['images'], isNotEmpty);
    expect(chatService.messages.first.hasImages, isTrue);

    await chatService.sendMessage('Describe la imagen');

    final nextMessages = (chatRequests.last['messages'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final imageInHistory = nextMessages.firstWhere(
      (message) => message['role'] == 'user',
    );
    expect(imageInHistory['images'], isNotEmpty);
  });

  test('sends attached document text and widens the context window', () async {
    const document = DocumentAttachment(
      path: 'informe.pdf',
      name: 'informe.pdf',
      kind: DocumentKind.pdf,
      sizeBytes: 2048,
      text: 'El informe concluye que las ventas crecieron un 20%.',
      originalChars: 50,
    );

    await chatService.sendMessage(
      '¿Qué concluye el informe?',
      documents: [document],
    );

    final request = chatRequests.single;
    final sentMessages =
        (request['messages'] as List<dynamic>).cast<Map<String, dynamic>>();
    final userMessage = sentMessages.last;

    expect(userMessage['content'], contains('¿Qué concluye el informe?'));
    expect(
      userMessage['content'],
      contains('El informe concluye que las ventas crecieron un 20%.'),
    );
    expect(userMessage['content'], contains('informe.pdf'));
    expect(request['options']['num_ctx'], 8192);
    expect(request['options']['temperature'], 0.2);
    expect(
      sentMessages.first['content'],
      contains('responde únicamente con la información del texto extraído'),
    );
    expect(chatService.messages.first.documents, isNotEmpty);
  });

  test('does not resend failed turns as conversation context', () async {
    failChatRequests = true;
    await chatService.sendMessage('Esta petición va a fallar');
    failChatRequests = false;

    await chatService.sendMessage('Ahora sí responde');

    final sentMessages = (chatRequests.single['messages'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    expect(sentMessages.map((message) => message['role']),
        ['system', 'user', 'user']);
    expect(
      sentMessages.any(
        (message) => (message['content'] as String).contains('Error'),
      ),
      isFalse,
    );
  });

  test('retries the last user question instead of the error text', () async {
    failChatRequests = true;
    await chatService.sendMessage('¿Cuál es la capital de Francia?');

    expect(chatService.messages.last.isError, isTrue);
    expect(
      chatService.messages.where((message) => message.isUser).length,
      1,
    );

    failChatRequests = false;
    await chatService.retryLastMessage();

    final sentMessages = (chatRequests.single['messages'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    expect(sentMessages.last['role'], 'user');
    expect(sentMessages.last['content'], '¿Cuál es la capital de Francia?');
    expect(
      chatService.messages.where((message) => message.isUser).length,
      1,
    );
    expect(chatService.messages.last.isError, isFalse);
    expect(chatService.messages.last.text, 'primera respuesta!');
  });
}
