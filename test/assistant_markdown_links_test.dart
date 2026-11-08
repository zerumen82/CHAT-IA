import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightchat/models/message.dart';
import 'package:lightchat/widgets/message_bubble.dart';

Widget _app(String text) {
  return MaterialApp(
    home: Scaffold(
      body: SelectionArea(
        child: ListView(
          children: [
            MessageBubble(
              message: Message(
                text: text,
                isUser: false,
                timestamp: DateTime(2026, 1, 1),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.mouse]) {
    testWidgets('abre el enlace en línea con $kind', (tester) async {
      await tester.pumpWidget(_app('http://abc.onion/foro'));
      await tester.pump();
      final center = tester.getCenter(find.text('http://abc.onion/foro'));
      final gesture = await tester.startGesture(center, kind: kind);
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Enlace .onion'), findsOneWidget);
      expect(find.text('Enlaces de la respuesta'), findsNothing);
    });
  }

  testWidgets('ofrece pulsable el enlace que Markdown no dibuja',
      (tester) async {
    await tester.pumpWidget(
        _app('```\nresultado 1\nhttp://abc.onion/foro\n```\nfin'));
    await tester.pump();
    expect(find.text('Enlaces de la respuesta'), findsOneWidget);
    await tester.tap(find.text('abc.onion/foro'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Enlace .onion'), findsOneWidget);
  });
}
