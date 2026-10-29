import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lightchat/config/ui_config.dart';
import 'package:lightchat/services/document_store_service.dart';
import 'package:lightchat/services/draft_service.dart';
import 'package:lightchat/widgets/chat_input.dart';
import 'package:lightchat/widgets/message_bubble.dart';
import 'package:lightchat/models/message.dart';

class _PendingDrafts extends DraftService {
  _PendingDrafts({required super.fallbackRoot});
  final pending = Completer<ChatDraft>();
  @override
  Future<ChatDraft> load(String id) => pending.future;
}

void main() {
  testWidgets('allows preparing a message while Ollama is offline',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body:
                ChatInput(connected: false, onSendMessage: (_, __, ___) {}))));
    await tester.enterText(find.byType(TextField), 'Borrador sin conexión');
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
    expect(find.byTooltip('Conecta Ollama para enviar'), findsOneWidget);
    expect(
        find.byWidgetPredicate((widget) =>
            widget is PopupMenuButton &&
            widget.tooltip == 'Adjuntar archivo, imagen o documento' &&
            widget.enabled),
        findsOneWidget);
  });

  testWidgets(
      'keeps a rejected draft and does not clear edits during acceptance',
      (tester) async {
    final accepted = Completer<bool>();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ChatInput(
                connected: true, onSubmit: (_, __, ___) => accepted.future))));
    await tester.enterText(find.byType(TextField), 'Primer borrador');
    await tester.pump();
    await tester.tap(find.byTooltip('Enviar mensaje (Enter)'));
    await tester.pump();
    await tester.enterText(
        find.byType(TextField), 'Borrador editado durante la espera');
    accepted.complete(true);
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Borrador editado durante la espera');
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ChatInput(
                key: const ValueKey('rejection'),
                connected: true,
                onSubmit: (_, __, ___) async => false))));
    await tester.enterText(find.byType(TextField), 'No aceptado');
    await tester.pump();
    await tester.tap(find.byTooltip('Enviar mensaje (Enter)'));
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'No aceptado');
  });

  testWidgets('clears only after accepting the unchanged draft',
      (tester) async {
    final accepted = Completer<bool>();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ChatInput(
                connected: true, onSubmit: (_, __, ___) => accepted.future))));
    await tester.enterText(find.byType(TextField), 'Enviar');
    await tester.pump();
    await tester.tap(find.byTooltip('Enviar mensaje (Enter)'));
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Enviar');
    accepted.complete(true);
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
  });

  testWidgets(
      'switching and disposing cannot recreate an explicitly deleted draft',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('lightchat-draft-ui-')))!;
    await tester.runAsync(() async {
      await DocumentStoreService.instance.initialize();
      await DocumentStoreService.instance.configureRoot(directory.path);
      await DraftService.instance
          .save('deleted-ui-chat', ChatDraft(text: 'Borrador anterior'));
    });
    var id = 'deleted-ui-chat';
    Widget input() => MaterialApp(
        home: Scaffold(
            body: ChatInput(
                draftId: id, connected: true, onSendMessage: (_, __, ___) {})));
    await tester.pumpWidget(input());
    await tester.pump();
    await tester.enterText(
        find.byType(TextField), 'Borrador con debounce pendiente');
    await tester
        .runAsync(() => DraftService.instance.delete('deleted-ui-chat'));
    id = 'other-ui-chat';
    await tester.pumpWidget(input());
    await tester
        .pump(const Duration(milliseconds: UiConfig.draftDebounceMs + 1));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      final prefs = await SharedPreferences.getInstance();
      expect(
          prefs
              .containsKey('${UiConfig.draftsPreferencePrefix}deleted-ui-chat'),
          isFalse);
      expect((await DraftService.instance.load('deleted-ui-chat')).isEmpty,
          isTrue);
      await DraftService.instance.clear('other-ui-chat');
      await directory.delete(recursive: true);
    });
  });

  testWidgets('drop during initial restore cannot leave the editor disabled',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(() => DocumentStoreService.instance.initialize());
    final key = GlobalKey<ChatInputState>();
    final temporary = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('lightchat-pending-draft-')))!;
    final drafts = _PendingDrafts(fallbackRoot: temporary.path);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ChatInput(
                key: key,
                draftId: 'restore-drop-chat',
                connected: true,
                draftService: drafts,
                onSendMessage: (_, __, ___) {}))));
    await key.currentState!.addFiles([XFile('archivo-inexistente.txt')]);
    drafts.pending.complete(ChatDraft(text: 'Borrador restaurado'));
    await tester.pump();
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
    await tester.runAsync(() async {
      // dispose inicia E/S real al conservar el texto restaurado.
      await tester.pumpWidget(const SizedBox.shrink());
      await drafts.clear('restore-drop-chat');
      await temporary.delete(recursive: true);
    });
  });

  testWidgets(
      'keeps partial content readable alongside interruption and continuation',
      (tester) async {
    var continued = false;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: MessageBubble(
                message: Message(
                    text: 'Contenido recibido',
                    isUser: false,
                    isError: true,
                    timestamp: DateTime(2026),
                    metadata: {
                      'finishReason': 'interrupted',
                      'error': 'Conexión cerrada'
                    }),
                onContinue: () => continued = true))));
    expect(find.text('Contenido recibido'), findsOneWidget);
    expect(find.textContaining('Conexión cerrada'), findsOneWidget);
    expect(find.text('Interrumpida'), findsOneWidget);
    await tester.tap(find.text('Continuar'));
    expect(continued, isTrue);
  });
}
