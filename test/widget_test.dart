// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lightchat/main.dart';
import 'package:lightchat/models/message.dart';
import 'package:lightchat/widgets/chat_input.dart';
import 'package:lightchat/widgets/message_bubble.dart';

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
  testWidgets('renders the LightChat conversation screen', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    expect(find.text('LightChat'), findsOneWidget);
    expect(find.text('Conecta Ollama primero…'), findsOneWidget);

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
    await tester.pumpWidget(const MyApp());
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
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(find.text('Liberar GPU'), findsOneWidget);
    expect(find.text('Descargar modelos de la VRAM'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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
