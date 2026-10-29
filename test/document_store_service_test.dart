import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lightchat/config/context_config.dart';
import 'package:lightchat/config/document_config.dart';
import 'package:lightchat/models/document_attachment.dart';
import 'package:lightchat/services/document_service.dart';
import 'package:lightchat/services/document_store_service.dart';

void main() {
  late Directory directory;
  late DocumentStoreService store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('lightchat-store-test-');
    store = DocumentStoreService();
    await store.configureRoot(directory.path);
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('keeps the full extraction after restart and original removal',
      () async {
    final original = File('${directory.path}/original.txt');
    final content = '${List.filled(20000, 'A').join()}\nFIN CONSERVADO';
    await original.writeAsString(content);
    final extracted = await DocumentService.extract(original.path);
    final saved = await store.put(extracted, conversationId: 'chat-one');
    expect(saved.storageId, isNotNull);
    expect(saved.extractedText, isNull);
    expect((saved.toJson()['text'] as String).length,
        lessThanOrEqualTo(DocumentConfig.persistedPreviewChars));
    await original.delete();

    final restarted = DocumentStoreService();
    await restarted.initialize();
    final sources = await restarted.documentsForConversation('chat-one');
    expect(sources, hasLength(1));
    final hydrated = await restarted.hydrate(sources.single);
    expect(hydrated.extractedText, content);
    expect(hydrated.extractionTruncated, isFalse);
  });

  test('reference cleanup preserves other chats and original files', () async {
    final original = File('${directory.path}/original.txt');
    await original.writeAsString('Contenido local');
    final saved = await store.put(await DocumentService.extract(original.path),
        conversationId: 'chat-one');
    await store.put(saved, conversationId: 'chat-two');

    await store.deleteConversation('chat-one');
    expect(await store.documentsForConversation('chat-one'), isEmpty);
    expect((await store.hydrate(saved)).extractedText, 'Contenido local');
    await store.deleteConversation('chat-two');
    expect(await store.documentsForConversation('chat-two'), isEmpty);
    expect(() => store.hydrate(saved), throwsA(isA<FileSystemException>()));
    expect(await original.readAsString(), 'Contenido local');
  });

  test('rejects traversal references without reading external files', () async {
    final document = DocumentAttachment(
      path: 'old.txt',
      name: 'old.txt',
      kind: DocumentKind.text,
      sizeBytes: 1,
      text: 'preview',
      storageId: '../outside',
    );
    expect(() => store.hydrate(document), throwsFormatException);
    expect(await store.documentsForConversation('unknown'), isEmpty);
  });

  test('old attachments remain readable without a configured store', () async {
    final legacy = DocumentAttachment.fromJson({
      'path': 'old.txt',
      'name': 'old.txt',
      'text': 'vista parcial',
      'truncated': true,
    });
    expect(
        (await DocumentStoreService().hydrate(legacy)).text, 'vista parcial');
    expect(legacy.extractionTruncated, isTrue);
    await DocumentStoreService().deleteConversation('missing');
  });

  test('failed root configuration preserves the active library and preference',
      () async {
    final original = File('${directory.path}/original.txt');
    await original.writeAsString('Dato que debe conservarse');
    final saved = await store.put(await DocumentService.extract(original.path),
        conversationId: 'chat');
    final previousRoot = store.rootPath;
    await expectLater(store.configureRoot('${directory.path}/missing'),
        throwsA(isA<FileSystemException>()));
    expect(store.rootPath, previousRoot);
    expect(
        (await SharedPreferences.getInstance())
            .getString(DocumentConfig.rootPreferenceKey),
        previousRoot);
    expect((await store.documentsForConversation('chat')).single.storageId,
        saved.storageId);
    expect((await store.hydrate(saved)).extractedText,
        'Dato que debe conservarse');
  });

  test('blocks moving a library with documents to a different root', () async {
    final original = File('${directory.path}/original.txt');
    await original.writeAsString('Documento conservado');
    final saved = await store.put(await DocumentService.extract(original.path),
        conversationId: 'chat');
    final next = await Directory('${directory.path}/next').create();
    final previousRoot = store.rootPath;
    await expectLater(
        store.configureRoot(next.path),
        throwsA(isA<FileSystemException>().having((error) => error.message,
            'message', contains('La biblioteca contiene archivos'))));
    expect(store.rootPath, previousRoot);
    expect((await store.hydrate(saved)).extractedText, 'Documento conservado');
    expect(
        (await SharedPreferences.getInstance())
            .getString(DocumentConfig.rootPreferenceKey),
        previousRoot);
  });

  for (final folder in [
    ContextConfig.generatedDirectory,
    ContextConfig.snapshotsDirectory
  ]) {
    test('blocks moving a library with files under $folder', () async {
      final owned = await Directory('${directory.path}/$folder/chat')
          .create(recursive: true);
      final file = File('${owned.path}/conservado.txt');
      await file.writeAsString('Contenido conservado');
      final next = await Directory('${directory.path}/next').create();
      final previousRoot = store.rootPath;
      await expectLater(
          store.configureRoot(next.path), throwsA(isA<FileSystemException>()));
      expect(store.rootPath, previousRoot);
      expect(await file.readAsString(), 'Contenido conservado');
    });
  }

  test('can change an empty library and reopen the same populated root',
      () async {
    final next = await Directory('${directory.path}/next').create();
    await store.configureRoot(next.path);
    final original = File('${directory.path}/original.txt');
    await original.writeAsString('Conservar tras abrir otra vez');
    final saved = await store.put(await DocumentService.extract(original.path),
        conversationId: 'chat');
    await store.configureRoot(next.path);
    expect((await store.hydrate(saved)).extractedText,
        'Conservar tras abrir otra vez');
  });

  test('initialization reports an unavailable root and permits reconfiguration',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        DocumentConfig.rootPreferenceKey, '${directory.path}/unavailable');
    await expectLater(store.initialize(), throwsA(isA<FileSystemException>()));
    expect(store.rootPath, isNull);
    expect(await store.documentsForConversation('chat'), isEmpty);
    await store.configureRoot(directory.path);
    expect(store.rootPath, await directory.resolveSymbolicLinks());
  });
}
