import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightchat/models/export_format.dart';
import 'package:lightchat/models/generated_file.dart';
import 'package:lightchat/models/message.dart';
import 'package:lightchat/widgets/file_actions.dart';
import 'package:lightchat/widgets/message_bubble.dart';

void main() {
  for (final outcome in ['saved', 'cancelled', 'write-error']) {
    testWidgets('export reports $outcome after the selected destination',
        (tester) async {
      final directory = await tester.runAsync(
          () => Directory.systemTemp.createTemp('lightchat export UI '));
      final output = File('${directory!.path}/respuesta con tildes.txt');
      const channel = MethodChannel('plugins.flutter.io/file_selector');
      var selected = false;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
          (call) async {
        expect(call.method, 'getSavePath');
        selected = true;
        return switch (outcome) {
          'cancelled' => null,
          'write-error' => directory.path,
          _ => output.path,
        };
      });
      try {
        late Future<void> export;
        await tester.pumpWidget(MaterialApp(
            home: Scaffold(
                body: Builder(
                    builder: (context) => TextButton(
                        onPressed: () {
                          export = showExportDialog(context,
                              title: 'Informe', text: 'Café y té');
                        },
                        child: const Text('Exportar'))))));
        await tester.runAsync(() => tester.tap(find.text('Exportar')));
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await tester.tap(find.text(ExportFormat.txt.label));
          await export;
        });
        await tester.pumpAndSettle();
        expect(selected, isTrue);
        if (outcome == 'saved') {
          expect(await tester.runAsync(output.readAsString),
              contains('Café y té'));
          expect(find.text('Archivo guardado'), findsOneWidget);
        } else {
          expect(await tester.runAsync(output.exists), isFalse);
          expect(find.text('Archivo guardado'), findsNothing);
          expect(find.textContaining('No se pudo exportar:'),
              outcome == 'write-error' ? findsOneWidget : findsNothing);
        }
        expect(tester.takeException(), isNull);
      } finally {
        tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() => directory.delete(recursive: true));
      }
    });
  }

  testWidgets(
      'generated file cards show real names and disable saving while busy',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: MessageBubble(
      message: Message(
          text: 'Archivo creado',
          isUser: false,
          timestamp: DateTime(2026),
          generatedFiles: const [
            GeneratedFile(
                id: 'file-1',
                name: 'ventas.xlsx',
                format: ExportFormat.xlsx,
                sizeBytes: 1816,
                relativePath: 'generated/chat-1/file-1.xlsx')
          ]),
      canExport: false,
    ))));
    expect(find.text('ventas.xlsx'), findsOneWidget);
    expect(find.text('1.8 KB'), findsOneWidget);
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Guardar'))
            .onPressed,
        isNull);
  });

  testWidgets('export action offers all four formats and can be cancelled',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => MessageBubble(
                      message: Message(
                          text: '# Informe\nUna respuesta.',
                          isUser: false,
                          timestamp: DateTime(2026)),
                      onExport: () => showExportDialog(context,
                          title: 'Informe', text: '# Informe\nUna respuesta.'),
                    )))));
    await tester.tap(find.byTooltip('Acciones del mensaje'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Exportar respuesta'));
    await tester.pumpAndSettle();
    for (final format in [
      ExportFormat.txt,
      ExportFormat.markdown,
      ExportFormat.pdf,
      ExportFormat.docx
    ]) {
      expect(find.text(format.label), findsOneWidget);
    }
    Navigator.of(tester.element(find.byType(SimpleDialog))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(SimpleDialog), findsNothing);
  });

  testWidgets(
      'context dialog displays the exact sent selection instead of stored document text',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: MessageBubble(
      message: Message(
          text: 'Consulta',
          isUser: true,
          timestamp: DateTime(2026),
          metadata: const {
            'contextText': 'Fragmento seleccionado: ZAFIRO-72841',
            'contextPartial': true
          }),
    ))));
    await tester.tap(find.text('Ver contexto enviado · parcial'));
    await tester.pumpAndSettle();
    expect(find.text('Fragmento seleccionado: ZAFIRO-72841'), findsOneWidget);
    expect(find.textContaining('caracteres enviados'), findsOneWidget);
  });
}
