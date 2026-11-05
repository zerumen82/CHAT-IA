import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lightchat/services/api_key_store.dart';
import 'package:lightchat/widgets/api_providers_tab.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ApiKeyStore.instance.resetForTest();
  });

  tearDown(() {
    ApiKeyStore.instance.resetForTest();
  });

  Future<void> pumpTab(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChangeNotifierProvider<ApiKeyStore>.value(
            value: ApiKeyStore.instance,
            child: const ApiProvidersTab(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lista los proveedores del catálogo con su estado real',
      (tester) async {
    await pumpTab(tester);

    expect(find.text('DeepSeek'), findsOneWidget);
    expect(find.text('Google Gemini'), findsOneWidget);
    expect(find.text('Importar APIS.txt'), findsOneWidget);
    expect(find.text('Añadir'), findsOneWidget);
    expect(find.textContaining('Sin clave'), findsWidgets);
    expect(
      find.textContaining('Ollama local sigue siendo el backend por defecto'),
      findsOneWidget,
    );
  });

  testWidgets('refleja en el recuento las claves guardadas', (tester) async {
    await pumpTab(tester);

    await ApiKeyStore.instance.save(
      providerId: 'groq',
      apiKey: 'gsk_prueba',
      model: 'llama-3.1-8b',
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('1 de'), findsOneWidget);
    expect(find.textContaining('proveedores con clave'), findsOneWidget);
  });

  testWidgets('el botón Añadir abre el alta de proveedor', (tester) async {
    await pumpTab(tester);

    await tester.tap(find.text('Añadir'));
    await tester.pumpAndSettle();

    expect(find.text('Añadir proveedor de API'), findsOneWidget);
    expect(find.text('Clave de API'), findsOneWidget);
    expect(find.text('Cancelar'), findsOneWidget);
    expect(find.text('Guardar'), findsOneWidget);
    expect(find.textContaining('el mensaje sale de tu máquina'), findsOneWidget);
  });
}
