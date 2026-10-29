import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lightchat/config/ui_config.dart';
import 'package:lightchat/models/document_attachment.dart';
import 'package:lightchat/services/document_store_service.dart';
import 'package:lightchat/services/draft_service.dart';

void main() {
  late Directory temporary;
  late DocumentStoreService store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temporary = await Directory.systemTemp.createTemp('lightchat-drafts-');
    store = DocumentStoreService();
    await store.initialize();
  });

  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  DraftService service() => DraftService(
      store: store,
      fallbackRoot: '${temporary.path}${Platform.pathSeparator}local-data');

  test('restores complete long draft without a document library', () async {
    final text = List.filled(6000, 'ñ').join();
    final draft = ChatDraft(text: text, imagePaths: [
      'imagen original.png'
    ], documents: [
      DocumentAttachment(
          path: 'original.txt',
          name: 'original.txt',
          kind: DocumentKind.text,
          sizeBytes: 100,
          text: 'Vista previa',
          extractedText: 'Texto completo conservado')
    ]);
    expect(await service().save('chat-a', draft), isNull);
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('${UiConfig.draftsPreferencePrefix}chat-a')!;
    expect(raw, isNot(contains(text)));
    expect(jsonDecode(raw), {'file': true, 'fallback': true});
    final restarted = await service().load('chat-a');
    expect(restarted.text, text);
    expect(restarted.imagePaths, ['imagen original.png']);
    expect(
        restarted.documents.single.extractedText, 'Texto completo conservado');
  });

  test('fallback marker remains readable after selecting a library', () async {
    final text = List.filled(5000, 'b').join();
    await service().save('chat-b', ChatDraft(text: text));
    final library = await Directory('${temporary.path}/biblioteca').create();
    await store.configureRoot(library.path);
    expect((await service().load('chat-b')).text, text);
    await service().save('chat-b', ChatDraft(text: '$text actualizado'));
    expect((await service().load('chat-b')).text, '$text actualizado');
    final prefs = await SharedPreferences.getInstance();
    expect(
        jsonDecode(
            prefs.getString('${UiConfig.draftsPreferencePrefix}chat-b')!),
        {'file': true, 'fallback': false});
  });

  test('deleted conversation ignores queued and late snapshots', () async {
    final drafts = service();
    await drafts.save('removed', ChatDraft(text: 'antes'));
    final queued = drafts.save('removed', ChatDraft(text: 'en cola'));
    final deleted = drafts.delete('removed');
    await queued;
    await deleted;
    await drafts.save('removed', ChatDraft(text: 'callback tardío'));
    expect((await drafts.load('removed')).isEmpty, isTrue);
    expect((await service().load('removed')).isEmpty, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('${UiConfig.draftsPreferencePrefix}removed'),
        isFalse);
  });

  test('clear permits a later draft in the same conversation', () async {
    final drafts = service();
    await drafts.save('retained', ChatDraft(text: 'primero'));
    await drafts.clear('retained');
    await drafts.save('retained', ChatDraft(text: 'siguiente'));
    expect((await service().load('retained')).text, 'siguiente');
  });

  test('flush persists remembered edits before a UI debounce fires', () async {
    final drafts = service();
    drafts.remember('closing', ChatDraft(text: 'Últimos caracteres al cerrar'));
    await drafts.flush();
    expect(
        (await service().load('closing')).text, 'Últimos caracteres al cerrar');
  });

  test('flush repeats when drafts change while persistence awaits', () async {
    final drafts = service();
    drafts.remember('first', ChatDraft(text: 'Primero antiguo'));
    drafts.remember('second', ChatDraft(text: 'Segundo antiguo'));
    final flushing = drafts.flush();
    drafts.remember(
        'first', ChatDraft(text: 'Primero actualizado durante E/S'));
    drafts.remember(
        'second', ChatDraft(text: 'Segundo actualizado durante E/S'));
    await flushing;
    expect((await service().load('first')).text,
        'Primero actualizado durante E/S');
    expect((await service().load('second')).text,
        'Segundo actualizado durante E/S');
  });

  test('rejects path traversal instead of using a conversation as a path', () {
    expect(() => service().save('../escape', ChatDraft(text: 'texto')),
        throwsFormatException);
  });
}
