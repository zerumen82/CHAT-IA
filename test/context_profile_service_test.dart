import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lightchat/services/context_profile_service.dart';
import 'package:lightchat/services/ollama_service.dart';

void main() {
  late HttpServer server;
  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/api/show') {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        final native =
            {'tiny': 2048, 'small': 8192, 'large': 32768}[body['name']];
        request.response.write(jsonEncode({
          'model_info': {if (native != null) 'model.context_length': native},
          'capabilities': ['completion'],
        }));
      } else if (request.uri.path == '/api/tags') {
        request.response.write('{"models":[]}');
      } else {
        request.response.write('{"version":"test"}');
      }
      await request.response.close();
    });
    SharedPreferences.setMockInitialValues(
        {'ollama_host': '127.0.0.1', 'ollama_port': server.port});
    await OllamaService.instance.initialize();
  });
  tearDownAll(() async {
    OllamaService.instance.dispose();
    await server.close(force: true);
  });

  test('respects native 2k and 8k limits instead of applying 16k universally',
      () async {
    final service = ContextProfileService();
    expect((await service.forModel('tiny')).tokens, 2048);
    expect((await service.forModel('small')).tokens, 8192);
    expect((await service.forModel('large')).tokens, 16384);
    expect((await service.forModel('unknown')).tokens, 4096);
    await expectLater(service.setTokens('tiny', 32768), throwsArgumentError);
    await expectLater(service.setTokens('small', 16384), throwsArgumentError);
    await service.setTokens('large', 32768);
    expect((await ContextProfileService().forModel('large')).tokens, 32768);
  });
}
