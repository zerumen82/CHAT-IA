import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightchat/config/context_config.dart';
import 'package:lightchat/models/context_plan.dart';
import 'package:lightchat/models/prepared_context.dart';
import 'package:lightchat/services/context_profile_service.dart';
import 'package:lightchat/widgets/chat_input.dart';

PreparedContext preview(int tokens) => PreparedContext(
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
      historyPartial: false,
    );

void main() {
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
