// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lightchat/main.dart';
import 'package:lightchat/models/document_attachment.dart';
import 'package:lightchat/models/message.dart';
import 'package:lightchat/widgets/chat_input.dart';
import 'package:lightchat/widgets/message_bubble.dart';
import 'package:lightchat/services/document_store_service.dart';
import 'package:lightchat/services/draft_service.dart';
import 'package:lightchat/services/ollama_service.dart';

double _contrastRatio(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter =
      firstLuminance > secondLuminance ? firstLuminance : secondLuminance;
  final darker =
      firstLuminance > secondLuminance ? secondLuminance : firstLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  late Directory draftDirectory;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    // El sondeo del singleton pertenece al servicio, fuera del reloj fake de
    // un widget concreto; su ciclo de vida termina con este archivo de pruebas.
    await OllamaService.instance.initialize();
  });
  tearDownAll(() => OllamaService.instance.dispose());
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    draftDirectory =
        await Directory.systemTemp.createTemp('lightchat-widget-drafts-');
    await DocumentStoreService.instance.initialize();
    await DocumentStoreService.instance.configureRoot(draftDirectory.path);
  });
  tearDown(() async {
    await DraftService.instance.flush();
    await draftDirectory.delete(recursive: true);
  });
  testWidgets('renders the LightChat conversation screen', (tester) async {
    await tester.runAsync(() => tester.pumpWidget(const MyApp()));
    await tester.pump();

    expect(find.text('LightChat'), findsOneWidget);
    expect(find.text('Prepara tu mensaje; conecta Ollama para enviarlo…'),
        findsOneWidget);

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    final themes = [app.theme!, app.darkTheme!];
    expect(themes[0].brightness, Brightness.light);
    expect(themes[1].brightness, Brightness.dark);
    for (final theme in themes) {
      expect(theme.textTheme.bodyMedium?.color, theme.colorScheme.onSurface);
      expect(
        _contrastRatio(theme.colorScheme.onSurface, theme.colorScheme.surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrastRatio(
          theme.colorScheme.onPrimaryContainer,
          theme.colorScheme.primaryContainer,
        ),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrastRatio(
          theme.colorScheme.onSecondaryContainer,
          theme.colorScheme.secondaryContainer,
        ),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrastRatio(
          theme.colorScheme.onTertiaryContainer,
          theme.colorScheme.tertiaryContainer,
        ),
        greaterThanOrEqualTo(4.5),
      );
    }

    await tester.binding.setSurfaceSize(const Size(480, 640));
    await tester.runAsync(() => tester.pumpWidget(const MyApp()));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('shows the retry action in error message bubbles',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            message: Message(
              text: 'Error al comunicarse con Ollama',
              isUser: false,
              isError: true,
              timestamp: DateTime(2026, 10, 18),
            ),
            onRetry: () {},
          ),
        ),
      ),
    );

    expect(find.text('Error al comunicarse con Ollama'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('offers a free GPU action in the chat menu', (tester) async {
    await tester.runAsync(() => tester.pumpWidget(const MyApp()));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(find.text('Liberar GPU'), findsOneWidget);
    expect(find.text('Descargar modelos de la VRAM'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the conversation sidebar only on wide windows',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    await tester.runAsync(() => tester.pumpWidget(const MyApp()));
    await tester.pump();

    expect(find.text('Conversaciones'), findsOneWidget);
    expect(find.byTooltip('Nueva conversación'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.binding.setSurfaceSize(const Size(600, 800));
    await tester.runAsync(() => tester.pumpWidget(const MyApp()));
    await tester.pump();

    expect(find.text('Conversaciones'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Mostrar conversaciones'));
    await tester.pumpAndSettle();
    expect(find.text('Conversaciones'), findsOneWidget);
    expect(
        find.byType(TextField).evaluate().any((element) =>
            (element.widget as TextField).decoration?.hintText ==
            'Buscar conversaciones'),
        isTrue);

    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('renders assistant markdown with copyable code blocks',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            message: Message(
              text: '**Importante**\n\n```dart\nprint(1);\n```',
              isUser: false,
              timestamp: DateTime(2026, 10, 24),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(MarkdownBody), findsOneWidget);
    expect(find.text('DART'), findsOneWidget);
    expect(find.byTooltip('Copiar código'), findsOneWidget);
    expect(find.textContaining('**'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('offers regenerate on the last answer and edit on user messages',
      (tester) async {
    var regenerated = false;
    var edited = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              MessageBubble(
                message: Message(
                  text: 'Pregunta',
                  isUser: true,
                  timestamp: DateTime(2026, 10, 24),
                ),
                onEdit: () => edited = true,
              ),
              MessageBubble(
                message: Message(
                  text: 'Respuesta',
                  isUser: false,
                  timestamp: DateTime(2026, 10, 24),
                ),
                onRegenerate: () => regenerated = true,
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('Regenerar'));
    await tester.pump();
    expect(regenerated, isTrue);

    await tester.tap(find.byTooltip('Editar y reenviar'));
    await tester.pump();
    expect(edited, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('extracts an attached file and shows its text and context meter',
      (tester) async {
    final chatInputKey = GlobalKey<ChatInputState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInput(
            key: chatInputKey,
            connected: true,
            onSendMessage: (text, images, documents) {},
          ),
        ),
      ),
    );

    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('lightchat-ui'),
    ))!;
    final file = File('${directory.path}/notas.txt');
    await tester.runAsync(() async {
      await file.writeAsString('Contenido de prueba');
      await chatInputKey.currentState!.addFiles([XFile(file.path)]);
    });
    await tester.pumpAndSettle();

    expect(find.text('notas.txt'), findsOneWidget);
    // Este widget aislado no tiene planificador: no inventar presupuesto.
    expect(
        find.text('Vista previa del contexto no disponible.'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    await tester.tap(find.text('notas.txt'));
    await tester.pumpAndSettle();

    expect(find.text('Copiar texto'), findsOneWidget);
    expect(find.text('Contenido de prueba'), findsOneWidget);
    expect(find.textContaining('caracteres extraídos/conservados'),
        findsOneWidget);

    await tester.tap(find.text('Cerrar'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => directory.delete(recursive: true));
  });

  for (final extractionPartial in [false, true]) {
    testWidgets(
        'shows the document chip text with extractionPartial=$extractionPartial',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: Message(
                text: 'Resumen',
                isUser: true,
                timestamp: DateTime(2026, 10, 24),
                documents: [
                  DocumentAttachment(
                    path: 'informe.pdf',
                    name: 'informe.pdf',
                    kind: DocumentKind.pdf,
                    sizeBytes: 2048,
                    text: 'Texto extraído del PDF',
                    originalChars: 24,
                    truncated: true,
                    extractionTruncated: extractionPartial,
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(
          find.byTooltip('Ver el texto extraído/conservado'), findsOneWidget);
      expect(
          find.textContaining(extractionPartial
              ? 'extracción parcial'
              : 'vista previa acotada'),
          findsOneWidget);
      if (extractionPartial) {
        expect(find.textContaining('vista previa acotada'), findsNothing);
      }
      expect(find.textContaining('recortado'), findsNothing);
      await tester.tap(find.text('informe.pdf'));
      await tester.pumpAndSettle();

      expect(find.text('Texto extraído del PDF'), findsOneWidget);
      expect(find.textContaining('caracteres extraídos/conservados'),
          findsOneWidget);
      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();
    });
  }

  testWidgets('sends the message when Enter is pressed', (tester) async {
    String? sentText;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInput(
            connected: true,
            onSendMessage: (text, images, documents) {
              sentText = text;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'Hola mundo');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(sentText, 'Hola mundo');
    expect(tester.takeException(), isNull);
  });
}
