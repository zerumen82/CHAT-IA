import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightchat/config/context_config.dart';
import 'package:lightchat/models/context_plan.dart';
import 'package:lightchat/models/prepared_context.dart';
import 'package:lightchat/services/context_profile_service.dart';
import 'package:lightchat/widgets/chat_input.dart';

PreparedContext preview(int tokens, {bool historyPartial = false}) =>
    PreparedContext(
      documents: const ContextPlan(
          text: 'Documento conservado', documents: [], isPartial: false),
      profile: ModelContextProfile(
          nativeTokens: tokens,
          tokens: tokens,
          supportsTools: false,
          metadataKnown: true),
      messages: const [],
      responseTokens: 512,
      documentBudgetChars: 1000,
      estimatedPromptTokens: 100,
      historyPartial: historyPartial,
    );

void main() {
  testWidgets('pending preview does not label a fully extracted file as cut',
      (tester) async {
    final pending = Completer<PreparedContext>();
    final key = GlobalKey<ChatInputState>();
    final temporary = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('lightchat-context-file-')))!;
    final file = File('${temporary.path}/documento.txt');
    await tester
        .runAsync(() => file.writeAsString('Texto conservado.\n' * 2000));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ChatInput(
                key: key,
                connected: true,
                onSendMessage: (_, __, ___) {},
                onPreviewContext: (_, __, ___) => pending.future))));
    await tester.runAsync(() => key.currentState!.addFiles([XFile(file.path)]));
    // La extracción usa E/S real; rearmar el debounce en el reloj del widget.
    key.currentState!.refreshContextPreview();
    await tester.pump();
    final attachment = key.currentState!.documentAttachments.single;
    expect(attachment.truncated, isTrue);
    expect(attachment.extractionTruncated, isFalse);
    expect(find.textContaining('Calculando contexto'), findsOneWidget);
    expect(find.textContaining('recortado'), findsNothing);
    expect(find.textContaining('Contexto parcial'), findsNothing);
    expect(
        find.textContaining(
            '${attachment.extractedText!.length} caracteres conservados'),
        findsOneWidget);
    expect(find.byTooltip('Ver el texto extraído/conservado'), findsOneWidget);
    pending.complete(preview(32768));
    await tester
        .pump(const Duration(milliseconds: ContextConfig.previewDebounceMs));
    await tester.pump();
    expect(find.textContaining('Contexto parcial'), findsNothing);
    expect(find.textContaining('/32768 tokens'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => temporary.delete(recursive: true));
  });

  testWidgets('moving the cursor does not recalculate document context',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ChatInput(
                connected: true,
                onSendMessage: (_, __, ___) {},
                onPreviewContext: (_, __, ___) async {
                  calls++;
                  return preview(32768);
                }))));
    await tester.enterText(find.byType(TextField), 'Segunda pregunta');
    await tester
        .pump(const Duration(milliseconds: ContextConfig.previewDebounceMs));
    await tester.pump();
    final field = tester.widget<TextField>(find.byType(TextField));
    final before = calls;
    field.controller!.selection = const TextSelection.collapsed(offset: 3);
    await tester.pump();
    expect(find.textContaining('/32768 tokens'), findsOneWidget);
    await tester
        .pump(const Duration(milliseconds: ContextConfig.previewDebounceMs));
    await tester.pump();
    expect(calls, before);
    expect(field.controller!.selection.baseOffset, 3);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('keeps the document context area while editing after a reply',
      (tester) async {
    final pending = Completer<PreparedContext>();
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Align(
                alignment: Alignment.bottomCenter,
                child: ChatInput(
                    connected: true,
                    onSendMessage: (_, __, ___) {},
                    onPreviewContext: (_, __, ___) {
                      calls++;
                      return calls == 1
                          ? Future.value(preview(32768, historyPartial: true))
                          : pending.future;
                    })))));
    await tester.enterText(find.byType(TextField), 'Pregunta');
    await tester
        .pump(const Duration(milliseconds: ContextConfig.previewDebounceMs));
    await tester.pump();
    final position = tester.getTopLeft(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'Otra pregunta');
    await tester.pump();
    expect(find.textContaining('Calculando contexto'), findsOneWidget);
    expect(tester.getTopLeft(find.byType(TextField)), position);
    expect(find.textContaining('/32768 tokens'), findsNothing);
    await tester
        .pump(const Duration(milliseconds: ContextConfig.previewDebounceMs));
    pending.complete(preview(32768, historyPartial: true));
    await tester.pump();
    await tester.pump();
    expect(tester.getTopLeft(find.byType(TextField)), position);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Otra pregunta');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('defers next context preview until streaming finishes',
      (tester) async {
    var busy = false;
    var version = 0;
    var calls = 0;
    Widget input() => MaterialApp(
        home: Scaffold(
            body: ChatInput(
                connected: true,
                busy: busy,
                contextRevision: (
                  model: 'local',
                  conversationId: 'a',
                  messagesVersion: version
                ),
                onSendMessage: (_, __, ___) {},
                onPreviewContext: (_, __, ___) async {
                  calls++;
                  return preview(32768);
                })));
    await tester.pumpWidget(input());
    await tester.enterText(find.byType(TextField), 'Primera');
    await tester
        .pump(const Duration(milliseconds: ContextConfig.previewDebounceMs));
    await tester.pump();
    final before = calls;
    busy = true;
    for (version = 1; version <= 3; version++) {
      await tester.pumpWidget(input());
      await tester.enterText(find.byType(TextField), 'Siguiente $version');
      await tester
          .pump(const Duration(milliseconds: ContextConfig.previewDebounceMs));
      await tester.pump();
    }
    expect(calls, before);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
    busy = false;
    await tester.pumpWidget(input());
    await tester
        .pump(const Duration(milliseconds: ContextConfig.previewDebounceMs));
    await tester.pump();
    expect(calls, before + 1);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Siguiente 3');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final change in ['model', 'conversation', 'history']) {
    testWidgets(
        'refreshes context after $change changes and ignores an older result',
        (tester) async {
      final obsolete = Completer<PreparedContext>();
      final current = Completer<PreparedContext>();
      var calls = 0;
      final drafts = <String>[];
      var revision =
          (model: 'large', conversationId: 'chat-a', messagesVersion: 1);

      Widget input() => MaterialApp(
          home: Scaffold(
              body: Align(
                  alignment: Alignment.bottomCenter,
                  child: ChatInput(
                      connected: true,
                      contextRevision: revision,
                      onSendMessage: (_, __, ___) {},
                      onPreviewContext: (text, _, __) {
                        drafts.add(text);
                        calls++;
                        if (calls == 1) return Future.value(preview(32768));
                        return calls == 2 ? obsolete.future : current.future;
                      }))));

      const debounce = Duration(milliseconds: ContextConfig.previewDebounceMs);
      await tester.pumpWidget(input());
      await tester.enterText(find.byType(TextField), 'borrador conservado');
      await tester.pumpAndSettle();
      await tester.pump(debounce);
      await tester.pump();
      expect(find.textContaining('/32768 tokens'), findsOneWidget);

      // Iniciar otro cálculo del contexto anterior y dejarlo pendiente.
      tester
          .state<ChatInputState>(find.byType(ChatInput))
          .refreshContextPreview();
      await tester.pump();
      await tester.pump(debounce);
      expect(calls, 2);
      expect(drafts, everyElement('borrador conservado'));
      revision = switch (change) {
        'model' => (
            model: 'small',
            conversationId: 'chat-a',
            messagesVersion: 1
          ),
        'conversation' => (
            model: 'large',
            conversationId: 'chat-b',
            messagesVersion: 1
          ),
        _ => (model: 'large', conversationId: 'chat-a', messagesVersion: 2),
      };
      await tester.pumpWidget(input());
      expect(find.textContaining('/32768 tokens'), findsNothing);
      await tester.pump(debounce);
      expect(calls, 3);
      current.complete(preview(2048));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('/2048 tokens'), findsOneWidget);

      // Una respuesta antigua que llega después nunca sustituye la actual.
      obsolete.complete(preview(32768));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('/2048 tokens'), findsOneWidget);
      expect(find.textContaining('/32768 tokens'), findsNothing);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'borrador conservado');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
