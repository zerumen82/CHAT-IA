import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lightchat/services/api_key_store.dart';
import 'package:lightchat/services/api_service.dart';
import 'package:lightchat/services/ollama_service.dart';

/// Opt-in: llamada **real** a un proveedor cloud con la clave del APIS.txt.
///
/// Usa exactamente el transporte que usa la UI (`ApiService.generateChat`),
/// no un cliente de prueba. La clave se lee del archivo del escritorio y vive
/// solo durante la prueba: nunca se escribe en el repositorio ni en la
/// evidencia.
///
/// ```powershell
/// flutter test --no-pub --dart-define=LIGHTCHAT_LIVE=true test/live_api_test.dart
/// # proveedor/modelo alternativos:
/// #   $env:LIGHTCHAT_LIVE_API='mistral'; $env:LIGHTCHAT_LIVE_MODEL='mistral-small-latest'
/// ```
void main() {
  test('real cloud provider answers through ApiService', () async {
    final providerId =
        Platform.environment['LIGHTCHAT_LIVE_API'] ?? 'deepseek';
    final model = Platform.environment['LIGHTCHAT_LIVE_MODEL'] ??
        'deepseek-flash';
    final apisPath = Platform.environment['LIGHTCHAT_LIVE_APIS'] ??
        '${Platform.environment['USERPROFILE']}${Platform.pathSeparator}'
            'Desktop${Platform.pathSeparator}APIS.txt';

    SharedPreferences.setMockInitialValues({});
    ApiKeyStore.instance.resetForTest();
    await ApiKeyStore.instance.load();

    final content = await File(apisPath).readAsString();
    final imported = await ApiKeyStore.instance.import(content);
    expect(imported.totalParsed, greaterThan(0),
        reason: 'No se reconoció ninguna clave en $apisPath');
    expect(
      ApiKeyStore.instance.apiKeyOf(providerId),
      isNotEmpty,
      reason: 'El archivo no trae clave del proveedor $providerId',
    );

    // 1) Comprobación de la clave contra el listado real de modelos.
    final check = await ApiService.instance
        .testConnection(providerId: providerId, model: model);
    expect(check, isNotEmpty);

    // 2) Generación real con el mismo transporte que usa el chat.
    final events = await ApiService.instance
        .generateChat(
          providerId: providerId,
          model: model,
          messages: [
            OllamaMessage(
              role: 'user',
              content: 'Responde exactamente: lightchat-live-ok',
            ),
          ],
          temperature: 0,
          numPredict: 64,
        )
        .toList();

    final text = events.map((event) => event.message).join().trim();
    expect(events.last.done, isTrue,
        reason: 'El proveedor no confirmó el fin de la respuesta');
    expect(text, isNotEmpty, reason: 'El proveedor no devolvió texto');

    final date = DateTime.now().toIso8601String().substring(0, 10);
    final dir = Directory('.dart_tool/live-evidence-$date').absolute;
    await dir.create(recursive: true);
    final evidence = <String, dynamic>{
      'provider': providerId,
      'model': model,
      'connectionCheck': check,
      'done': events.last.done,
      'doneReason': events.last.doneReason,
      'chunks': events.length,
      'response': text,
      'at': DateTime.now().toIso8601String(),
    };
    final file = File(
        '${dir.path}${Platform.pathSeparator}api-$providerId.json');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(evidence));

    debugPrint('[live-api] $providerId/$model -> $text');
    debugPrint('[live-api] evidencia: ${file.path}');
  }, timeout: const Timeout(Duration(minutes: 3)),
      skip: !const bool.fromEnvironment('LIGHTCHAT_LIVE'));
}
