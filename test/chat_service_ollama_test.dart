import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lightchat/config/vllm_config.dart';
import 'package:lightchat/models/document_attachment.dart';
import 'package:lightchat/models/message.dart';
import 'package:lightchat/models/generation_phase.dart';
import 'package:lightchat/services/chat_service_ollama.dart';
import 'package:lightchat/services/ollama_service.dart';
import 'package:lightchat/services/document_store_service.dart';
import 'package:lightchat/services/generated_file_service.dart';
import 'package:lightchat/services/context_profile_service.dart';
import 'package:lightchat/models/export_format.dart';

void main() {
  late HttpServer server;
  late List<Map<String, dynamic>> chatRequests;
  late bool failChatRequests;
  Map<String, dynamic>? fileCall;
  var chatMode = 'normal';
  Completer<void>? streamRelease;
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
            {'name': 'llama3:latest', 'model': 'llama3:latest', 'size': 1024},
            {'name': 'text-only:latest', 'size': 1024},
            {'name': 'unknown:latest', 'size': 1024}
          ]
        }));
      } else if (request.uri.path == '/api/show') {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        request.response.write(jsonEncode({
          'model_info': {'test.context_length': 32768},
          if (body['name'] != 'unknown:latest')
            'capabilities': [
              'completion',
              'tools',
              if (body['name'] == 'llama3:latest') 'vision'
            ],
        }));
      } else if (request.uri.path == '/api/version') {
        request.response.write(jsonEncode({'version': 'test'}));
      } else if (request.uri.path == '/api/chat') {
        if (failChatRequests) {
          request.response.statusCode = HttpStatus.internalServerError;
          request.response.write('{"error":"El modelo no se pudo cargar"}');
          await request.response.close();
          return;
        }
        final body = await utf8.decoder.bind(request).join();
        chatRequests.add(jsonDecode(body) as Map<String, dynamic>);
        request.response.bufferOutput = false;
        request.response.headers.contentType =
            ContentType('application', 'x-ndjson', charset: 'utf-8');
        if (chatMode == 'errorAfterPartial' || chatMode == 'eof') {
          request.response.writeln(jsonEncode({
            'message': {
              'content': 'Texto parcial importante que debe conservarse.'
            },
            'done': false,
          }));
          await request.response.flush();
          if (chatMode == 'errorAfterPartial') {
            request.response
                .writeln('{"error":"Conexión interrumpida de prueba"}');
          }
          await request.response.close();
          return;
        }
        if (chatMode == 'length') {
          request.response.writeln(jsonEncode({
            'message': {'content': 'Respuesta que alcanza el límite.'},
            'done': true,
            'done_reason': 'length',
            'prompt_eval_count': 42,
            'eval_count': 20,
            'eval_duration': 1000000000,
            'total_duration': 2000000000,
          }));
          await request.response.close();
          return;
        }
        if (chatMode == 'waiting') {
          try {
            request.response.writeln(jsonEncode({
              'message': {
                'content': 'Texto antes de detener que debe conservarse.'
              },
              'done': false,
            }));
            await request.response.flush();
            await streamRelease!.future;
            request.response
                .writeln('{"message":{"content":"final"},"done":true}');
            await request.response.close();
          } on HttpException {
            // El cliente cierra realmente la conexión al detener.
          } on SocketException {
            // El cliente cierra realmente la conexión al detener.
          }
          return;
        }
        if (fileCall != null) {
          request.response.write(jsonEncode({
            'message': {
              'role': 'assistant',
              'content': '',
              'tool_calls': [fileCall]
            },
            'done': true,
            'prompt_eval_count': 333
          }));
          await request.response.close();
          return;
        }
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
    fileCall = null;
    chatMode = 'normal';
    streamRelease = null;
    failChatRequests = false;
    SharedPreferences.setMockInitialValues({
      'ollama_host': '127.0.0.1',
      'ollama_port': server.port,
      'chat_messages': '[]',
    });
    temporaryDirectory =
        await Directory.systemTemp.createTemp('lightchat-test');
    await DocumentStoreService.instance.initialize();
    await DocumentStoreService.instance.configureRoot(temporaryDirectory.path);
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

    // La conversación inicial se crea después de cargar los modelos.
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (chatService.activeConversationId == null &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  });

  tearDown(() async {
    chatService.dispose();
    if (streamRelease != null && !streamRelease!.isCompleted) {
      streamRelease!.complete();
    }
    await temporaryDirectory.delete(recursive: true);
  });

  tearDownAll(() async {
    OllamaService.instance.dispose();
    await server.close(force: true);
  });

  Future<void> attachAndSend(String text,
      {required List<DocumentAttachment> documents}) async {
    for (final doc in documents) {
      await chatService.setSourceEnabled(doc, true);
    }
    await chatService.setDocumentMode(true);
    await chatService.sendMessage(text, documents: documents);
  }

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
    expect(
        secondTurn.first['content'],
        startsWith(
            'Eres LightChat, un asistente útil y directo. Responde siempre en español.'));
    expect(secondTurn.skip(1).map((message) => message['content']),
        ['Hola', 'primera respuesta!', '¿Qué respondiste?']);
    expect(chatRequests[0]['options'], {
      'temperature': 0.7,
      'num_predict': 2048,
      'num_ctx': OllamaConfig.maxContextTokens,
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

    await attachAndSend(
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
    expect(request['options']['num_ctx'], OllamaConfig.maxContextTokens);
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

  test('regenerates the last answer without duplicating the question',
      () async {
    await chatService.sendMessage('Hola');
    chatRequests.clear();
    fileCall = null;

    await chatService.regenerateLastResponse();

    final sentMessages = (chatRequests.single['messages'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    expect(sentMessages.map((message) => message['role']), ['system', 'user']);
    expect(sentMessages.last['content'], 'Hola');
    expect(
      chatService.messages.where((message) => message.isUser).length,
      1,
    );
    expect(chatService.messages.last.text, 'primera respuesta!');
  });

  test('edits a user message and drops the later turns', () async {
    await chatService.sendMessage('Primera pregunta');
    await chatService.sendMessage('Segunda pregunta');
    expect(
      chatService.messages.where((message) => message.isUser).length,
      2,
    );
    chatRequests.clear();
    fileCall = null;

    final userIndex = chatService.messages.indexWhere(
      (message) => message.isUser,
    );
    await chatService.editAndResend(userIndex, 'Pregunta corregida');

    final sentMessages = (chatRequests.single['messages'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    expect(sentMessages.map((message) => message['role']), ['system', 'user']);
    expect(sentMessages.last['content'], 'Pregunta corregida');
    expect(
      chatService.messages.where((message) => message.isUser).length,
      1,
    );
    expect(chatService.messages.first.text, 'Pregunta corregida');
  });

  test('keeps separate conversations and restores their messages', () async {
    await chatService.sendMessage('Hola desde la primera');
    final firstId = chatService.activeConversationId;
    expect(firstId, isNotNull);
    expect(chatService.conversations.first.title, 'Hola desde la primera');

    await chatService.newConversation();
    expect(chatService.messages, isEmpty);
    expect(chatService.activeConversationId, isNot(firstId));

    await chatService.sendMessage('Hola desde la segunda');
    final secondId = chatService.activeConversationId;
    expect(chatService.conversations.length, 2);

    await chatService.selectConversation(firstId!);
    expect(
      chatService.messages.map((message) => message.text),
      contains('Hola desde la primera'),
    );
    expect(
      chatService.messages.map((message) => message.text),
      isNot(contains('Hola desde la segunda')),
    );

    await chatService.deleteConversation(firstId);
    expect(
      chatService.conversations
          .any((conversation) => conversation.id == firstId),
      isFalse,
    );
    expect(chatService.activeConversationId, secondId);
    expect(
      chatService.messages.map((message) => message.text),
      contains('Hola desde la segunda'),
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
  test(
      'creates real files from streamed tool calls and persists their references',
      () async {
    fileCall = {
      'function': {
        'name': 'create_spreadsheet',
        'arguments': {
          'name': 'ventas.xlsx',
          'title': 'Ventas',
          'sheets': [
            {
              'name': 'Ventas',
              'rows': [
                ['Producto', 'Importe'],
                ['Café', 12.5]
              ]
            }
          ]
        }
      }
    };
    await chatService.sendMessage('Genera un Excel de ventas');
    final answer = chatService.messages.last;
    expect(answer.isError, isFalse, reason: answer.text);
    expect(answer.generatedFiles.single.format, ExportFormat.xlsx);
    expect(await GeneratedFileService.read(answer.generatedFiles.single),
        isNotEmpty);
    expect(answer.metadata?['promptEvalCount'], 333);
    expect(chatRequests.single['tools'], isNotEmpty);
    final originalId = chatService.activeConversationId!;
    await chatService.newConversation();
    await chatService.selectConversation(originalId);
    expect(chatService.messages.last.generatedFiles.single.name, 'ventas.xlsx');
    expect(
        await GeneratedFileService.read(
            chatService.messages.last.generatedFiles.single),
        isNotEmpty);
  });

  test(
      'keeps documents available beyond ten messages and after another attachment',
      () async {
    const original = DocumentAttachment(
        path: 'enero.txt',
        name: 'enero.txt',
        kind: DocumentKind.text,
        sizeBytes: 24,
        text: 'Clave antigua: PLATINO-4819',
        originalChars: 26);
    await attachAndSend('Lee este documento', documents: [original]);
    for (var index = 0; index < 6; index++) {
      await chatService.sendMessage('Continuamos con el turno $index');
    }
    const second = DocumentAttachment(
        path: 'febrero.txt',
        name: 'febrero.txt',
        kind: DocumentKind.text,
        sizeBytes: 20,
        text: 'Código febrero: LUNA-22',
        originalChars: 22);
    await attachAndSend('Recuerda los códigos de enero y febrero',
        documents: [second]);
    final finalRequest = chatRequests.last;
    final last = (finalRequest['messages'] as List).last as Map;
    expect(last['content'], contains('PLATINO-4819'));
    expect(last['content'], contains('LUNA-22'));
    final preview = await chatService.previewContext('Dime los códigos', []);
    expect(preview.documents.text, contains('PLATINO-4819'));
    expect(preview.documents.chars,
        lessThanOrEqualTo(preview.documentBudgetChars));
  });

  test(
      'persists explicit context profile and uses it with and without documents',
      () async {
    await ContextProfileService.instance.setTokens('llama3:latest', 32768);
    await chatService.sendMessage('Hola, responde brevemente');
    await attachAndSend('Consulta el informe', documents: [
      const DocumentAttachment(
          path: 'nota.txt',
          name: 'nota.txt',
          kind: DocumentKind.text,
          sizeBytes: 10,
          text: 'Una nota local.')
    ]);
    expect(
        chatRequests.map((r) => r['options']['num_ctx']), everyElement(32768));
  });

  test(
      'tool validation failures are visible and do not claim a file was created',
      () async {
    fileCall = {
      'function': {
        'name': 'create_pdf',
        'arguments': {
          'name': '../escape',
          'title': 'Informe',
          'content': 'Hola'
        }
      }
    };
    await chatService.sendMessage('Genera un PDF');
    expect(chatService.messages.last.isError, isTrue);
    expect(chatService.messages.last.generatedFiles, isEmpty);
    expect(chatService.messages.last.text, contains('Nombre o título'));
  });
  test('asks for storage only when a file tool actually needs it', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('lightchat_document_root_v1');
    await DocumentStoreService.instance.initialize();
    var storageRequests = 0;
    chatService.requestStorage = () async {
      storageRequests++;
      return false;
    };
    await chatService.sendMessage('Hola de nuevo');
    expect(storageRequests, 0);
    expect(chatService.messages.last.isError, isFalse);
    fileCall = {
      'function': {
        'name': 'create_pdf',
        'arguments': {
          'name': 'informe',
          'title': 'Informe',
          'content': 'Contenido'
        }
      }
    };
    await chatService.sendMessage('Crea un PDF');
    expect(storageRequests, 1);
    expect(chatService.messages.last.isError, isTrue);
    expect(chatService.messages.last.text, contains('cancelada'));
    expect(chatService.messages.last.generatedFiles, isEmpty);
  });

  test('clearing history also removes documentary sources and saved selections',
      () async {
    await attachAndSend('Lee esta nota', documents: [
      const DocumentAttachment(
          path: 'confidencial.txt',
          name: 'confidencial.txt',
          kind: DocumentKind.text,
          sizeBytes: 10,
          text: 'Clave privada AZUL-9921')
    ]);
    final serialized = chatService.messages.first.toJson();
    expect((serialized['metadata'] as Map).containsKey('contextText'), isFalse);
    expect((serialized['metadata'] as Map)['contextSnapshot'], isNotNull);
    await chatService.clearMessages();
    expect(chatService.messages, isEmpty);
    expect(
        await DocumentStoreService.instance
            .documentsForConversation(chatService.activeConversationId!),
        isEmpty);
    final preview = await chatService.previewContext('Dime la clave', []);
    expect(preview.documents.text, isEmpty);
  });

  test('an unavailable document folder does not prevent conversations loading',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'lightchat_document_root_v1', '${temporaryDirectory.path}/missing');
    final reopened = ChatServiceOllama();
    try {
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (reopened.activeConversationId == null &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(reopened.activeConversationId, isNotNull);
      expect(reopened.storageWarning, contains('No se pudo abrir'));
    } finally {
      reopened.dispose();
    }
  });
  test(
      'clearing locks sending and switching conversations until cleanup completes',
      () async {
    await chatService.sendMessage('Mensaje que se limpia');
    final original = chatService.activeConversationId;
    final clearing = chatService.clearMessages();
    expect(chatService.isLoading, isTrue);
    final blockedSend =
        chatService.sendMessage('No debe entrar durante la limpieza');
    final blockedSwitch = chatService.newConversation();
    await Future.wait([clearing, blockedSend, blockedSwitch]);
    expect(chatService.activeConversationId, original);
    expect(chatService.messages, isEmpty);
    expect(chatRequests, hasLength(1));
    expect(chatService.isLoading, isFalse);
  });

  test('preserves partial response and useful server error separately',
      () async {
    chatMode = 'errorAfterPartial';
    var accepted = 0;
    await chatService.sendMessage('Responde', onAccepted: () => accepted++);
    final answer = chatService.messages.last;
    expect(accepted, 1);
    expect(answer.text, 'Texto parcial importante que debe conservarse.');
    expect(answer.metadata?['finishReason'], 'interrupted');
    expect(answer.metadata?['error'], contains('Conexión interrumpida'));
    expect(answer.metadata?['partialResponse'], isTrue);
    expect(answer.isError, isTrue);
    chatMode = 'normal';
    await chatService.continueLastResponse();
    final sent = jsonEncode(chatRequests.last['messages']);
    expect(sent, contains('Texto parcial importante que debe conservarse.'));
    expect(chatService.messages.length, 4);
  });

  test('EOF without done is interrupted instead of completed', () async {
    chatMode = 'eof';
    await chatService.sendMessage('Responde');
    final answer = chatService.messages.last;
    expect(answer.text, contains('Texto parcial importante'));
    expect(answer.metadata?['finishReason'], 'interrupted');
    expect(answer.metadata?['error'], contains('antes de confirmar'));
  });

  test('records response limit and real generation metrics', () async {
    chatMode = 'length';
    await chatService.sendMessage('Respuesta larga');
    final answer = chatService.messages.last;
    expect(answer.metadata?['finishReason'], 'length');
    expect(answer.metadata?['evalCount'], 20);
    expect(answer.metadata?['evalDuration'], 1000000000);
    expect(answer.metadata?['promptEvalCount'], 42);
    expect(answer.metadata?['elapsedMs'], isNonNegative);
  });

  test(
      'stop closes transport and preserves partial answer before allowing send',
      () async {
    chatMode = 'waiting';
    streamRelease = Completer<void>();
    final receivedPartial = Completer<void>();
    chatService.addListener(() {
      if (!receivedPartial.isCompleted &&
          chatService.messages.any(
              (message) => message.text.startsWith('Texto antes de detener'))) {
        receivedPartial.complete();
      }
    });
    final sending = chatService.sendMessage('Responde despacio');
    await receivedPartial.future.timeout(const Duration(seconds: 3),
        onTimeout: () => throw StateError('No llegó el fragmento parcial.'));
    expect(chatService.generationPhase, GenerationPhase.responding);
    expect(chatService.generationStartedAt, isNotNull);
    chatService.stopGeneration();
    expect(chatService.isLoading, isTrue);
    await sending.timeout(const Duration(seconds: 3),
        onTimeout: () =>
            throw StateError('El transporte no terminó al detener.'));
    expect(chatService.messages.last.metadata?['finishReason'], 'stopped');
    expect(chatService.messages.last.text, contains('Texto antes de detener'));
    expect(chatService.isLoading, isFalse);
    expect(chatService.generationPhase, GenerationPhase.idle);
    streamRelease!.complete();
    chatMode = 'normal';
    await chatService.sendMessage('Ahora sigue');
    expect(chatService.messages.last.metadata?['finishReason'], 'completed');
  });

  test('rejects unsupported and unknown vision before accepting the draft',
      () async {
    final image = File('${temporaryDirectory.path}/imagen.png');
    await image.writeAsBytes([1, 2, 3]);
    var accepted = false;
    chatService.selectModel('text-only:latest');
    await expectLater(
        chatService.sendMessage('Mira',
            imagePaths: [image.path], onAccepted: () => accepted = true),
        throwsStateError);
    expect(accepted, isFalse);
    expect(chatRequests, isEmpty);
    expect(chatService.messages, isEmpty);
    chatService.selectModel('unknown:latest');
    await expectLater(chatService.sendMessage('Mira', imagePaths: [image.path]),
        throwsStateError);
    expect(chatService.messages, isEmpty);
  });

  test('switches general/documentary context and excludes sources from history',
      () async {
    const first = DocumentAttachment(
        path: 'primero.txt',
        name: 'primero.txt',
        kind: DocumentKind.text,
        sizeBytes: 10,
        text: 'SECRETO-PRIMERO-771');
    const second = DocumentAttachment(
        path: 'segundo.txt',
        name: 'segundo.txt',
        kind: DocumentKind.text,
        sizeBytes: 10,
        text: 'DATO-SEGUNDO-882');
    await attachAndSend('Consulta las fuentes', documents: [first, second]);
    expect(chatService.documentMode, isTrue);
    final sources = await chatService.getDocumentSources();
    await chatService.setSourceEnabled(
        sources.firstWhere((doc) => doc.name == 'primero.txt'), false);
    final preview = await chatService.previewContext('Dime los datos', []);
    expect(preview.documents.text, isNot(contains('SECRETO-PRIMERO')));
    expect(preview.documents.text, contains('DATO-SEGUNDO'));
    await chatService.sendMessage('Dime los datos');
    expect(jsonEncode(chatRequests.last), isNot(contains('SECRETO-PRIMERO')));
    expect(jsonEncode(chatRequests.last['messages']),
        isNot(contains('primera respuesta!')));
    await chatService.setDocumentMode(false);
    final general =
        await chatService.previewContext('Explica las estrellas', []);
    expect(general.documents.text, isEmpty);
    expect(
        general.messages.first.content, isNot(contains('responde únicamente')));
    await chatService.sendMessage('Explica las estrellas');
    expect(jsonEncode(chatRequests.last), isNot(contains('DATO-SEGUNDO')));
    final id = chatService.activeConversationId!;
    await chatService.newConversation();
    expect(chatService.documentMode, isFalse);
    await chatService.selectConversation(id);
    expect(chatService.documentMode, isFalse);
    expect(
        chatService.isSourceEnabled(
            sources.firstWhere((doc) => doc.name == 'primero.txt')),
        isFalse);
  });

  test('explicit general and disabled pending sources prevail at send',
      () async {
    const source = DocumentAttachment(
        path: 'nueva.txt',
        name: 'nueva.txt',
        kind: DocumentKind.text,
        sizeBytes: 10,
        text: 'TEXTO-NUEVO-329');
    expect(chatService.documentMode, isFalse);
    await chatService.setSourceEnabled(source, true);
    await chatService.setDocumentMode(true);
    final preview = await chatService.previewContext('Lee', [source]);
    expect(preview.documents.text, contains('TEXTO-NUEVO'));
    // Elección General posterior al evento adjuntar debe prevalecer.
    await chatService.setDocumentMode(false);
    final general = await chatService.previewContext('Lee', [source]);
    expect(general.documents.text, isEmpty);
    await chatService.sendMessage('Lee', documents: [source]);
    expect(chatService.documentMode, isFalse);
    expect(jsonEncode(chatRequests.last), isNot(contains('TEXTO-NUEVO')));
    await chatService.setDocumentMode(true);
    await chatService.setSourceEnabled(source, false);
    final disabled = await chatService.previewContext('Consulta', [source]);
    expect(disabled.documents.text, isEmpty);
    await chatService.sendMessage('Consulta', documents: [source]);
    expect(jsonEncode(chatRequests.last), isNot(contains('TEXTO-NUEVO')));
    expect(
        chatService
            .isSourceEnabled((await chatService.getDocumentSources()).single),
        isFalse);
  });

  test('keeps saved history while exposing partial request history', () async {
    for (var index = 0; index < 120; index++) {
      chatService.messages.add(Message(
          text: 'Turno antiguo $index ${'texto ' * 60}',
          isUser: index.isEven,
          timestamp: DateTime.now()));
    }
    await chatService.sendMessage('Nueva pregunta');
    expect(chatService.messages.length, 122);
    expect(chatService.messages.last.metadata?['historyPartial'], isTrue);
  });

  test('Windows path aliases cannot reintroduce an excluded legacy source',
      () async {
    const first = DocumentAttachment(
        path: r'C:\DOC\a.txt',
        name: 'a.txt',
        kind: DocumentKind.text,
        sizeBytes: 10,
        text: 'SECRETO-ALIAS-ANTERIOR');
    await attachAndSend('Consulta original', documents: [first]);
    // Mensajes previos a la normalización solo tenían ID y ruta cruda.
    for (var index = 0; index < chatService.messages.length; index++) {
      final message = chatService.messages[index];
      final raw = (message.metadata?['sourceIds'] as List)
          .whereType<String>()
          .where((id) => id != 'c:/doc/a.txt')
          .toList();
      chatService.messages[index] =
          message.copyWith(metadata: {...message.metadata!, 'sourceIds': raw});
    }
    final next =
        first.copyWith(path: 'c:/doc/a.txt', text: 'SECRETO-ALIAS-NUEVO');
    await attachAndSend('Consulta otra versión', documents: [next]);
    final sources = await chatService.getDocumentSources();
    expect(sources, hasLength(1));
    await chatService.setSourceEnabled(sources.single, false);
    await chatService.sendMessage('Responde sin esa fuente');
    final request = jsonEncode(chatRequests.last['messages']);
    expect(request, isNot(contains('SECRETO-ALIAS')));
    expect(request, isNot(contains('primera respuesta!')));
  }, skip: !Platform.isWindows);
}
