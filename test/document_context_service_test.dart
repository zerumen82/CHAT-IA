import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lightchat/models/document_attachment.dart';
import 'package:lightchat/services/document_context_service.dart';
import 'package:lightchat/services/document_store_service.dart';

DocumentAttachment document(String text, {String name = 'notas.txt'}) =>
    DocumentAttachment(
        path: name,
        name: name,
        kind: DocumentKind.text,
        sizeBytes: text.length,
        text: text,
        originalChars: text.length);

void main() {
  test('retrieves referenced facts at the start, middle and end', () async {
    final text = List.generate(
        900,
        (index) => switch (index) {
              0 => 'CLAVEINICIO = ámbar',
              450 => 'CLAVECENTRO = zafiro',
              899 => 'CLAVEFINAL = rubí',
              _ =>
                'Fila $index: texto general para completar el informe sin datos clave.',
            }).join('\n');
    final service = DocumentContextService();
    for (final key in ['CLAVEINICIO', 'CLAVECENTRO', 'CLAVEFINAL']) {
      final plan = await service.plan(
          query: 'Dime el valor de $key',
          documents: [document(text)],
          maxChars: 2400);
      expect(plan.text, contains(key));
      expect(plan.text, contains('notas.txt'));
      expect(plan.text, contains('líneas'));
      expect(plan.isPartial, isTrue);
      expect(plan.chars, lessThanOrEqualTo(2400));
      expect(plan.warnings.join(), contains('Cobertura parcial'));
      expect(plan.text, contains(plan.documents.single.text!));
    }
  });

  test('includes every source within a strict final budget', () async {
    final sources = [
      for (var index = 1; index <= 3; index++)
        document(List.filled(80, 'FUENTE$index importe 25').join('\n'),
            name: 'fuente$index.txt')
    ];
    final service = DocumentContextService();
    final plan = await service.plan(
        query: 'Compara los importes', documents: sources, maxChars: 3000);
    expect(plan.documents, hasLength(3));
    for (var index = 1; index <= 3; index++) {
      expect(plan.text, contains('fuente$index.txt'));
      expect(plan.text, contains('FUENTE$index'));
    }
    for (final budget in [0, 1, 40, 200, 700, 1500, 3000]) {
      final bounded = await service.plan(
          query: 'importes', documents: sources, maxChars: budget);
      expect(bounded.chars, lessThanOrEqualTo(budget));
    }
  });

  test('distinguishes full coverage from a historical lost extraction',
      () async {
    final service = DocumentContextService();
    final full = await service.plan(
        query: 'importe', documents: [document('Importe 25')], maxChars: 1000);
    expect(full.isPartial, isFalse);
    final legacy = document('Importe 25').copyWith(truncated: true);
    final partial = await service.plan(
        query: 'total de todas las filas', documents: [legacy], maxChars: 1000);
    expect(partial.isPartial, isTrue);
    expect(partial.text, contains('no calcules totales globales'));
    expect(partial.warnings.join(), contains('volver a adjuntarse'));
  });

  test('queries preserved sources after restart without original path',
      () async {
    SharedPreferences.setMockInitialValues({});
    final directory =
        await Directory.systemTemp.createTemp('lightchat-search-test-');
    try {
      final store = DocumentStoreService();
      await store.configureRoot(directory.path);
      final content =
          '${List.filled(15000, 'c').join()}\nCLAVEFINAL persistida';
      final saved = await store.put(
          document(content).copyWith(text: 'preview', extractedText: content),
          conversationId: 'chat');
      final restarted = DocumentStoreService();
      await restarted.initialize();
      final plan = await DocumentContextService(store: restarted).plan(
          query: 'CLAVEFINAL',
          documents: await restarted.documentsForConversation('chat'),
          maxChars: 1800);
      expect(saved.storageId, isNotNull);
      expect(plan.text, contains('CLAVEFINAL persistida'));
      expect(plan.isPartial, isTrue);
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
