import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lightchat/models/export_format.dart';
import 'package:lightchat/services/chat_service_ollama.dart';
import 'package:lightchat/services/context_profile_service.dart';
import 'package:lightchat/services/document_service.dart';
import 'package:lightchat/services/document_store_service.dart';
import 'package:lightchat/services/export_service.dart';
import 'package:lightchat/services/generated_file_service.dart';
import 'package:lightchat/services/ollama_service.dart';
import 'package:lightchat/services/spreadsheet_analysis_service.dart';

/// Opt-in: Ollama real, disco real y generadores de producción.
/// Preferencias aisladas para no modificar la configuración personal del usuario.
void main() {
  test(
      'real Ollama creates XLSX and PDF, retrieves long documents and runs 32k',
      () async {
    final date =
        DateTime.now().toIso8601String().substring(0, 10).replaceAll('-', '');
    final root = Directory('.dart_tool/live-evidence-$date').absolute;
    await root.create(recursive: true);
    SharedPreferences.setMockInitialValues({
      'ollama_host': 'localhost',
      'ollama_port': 11434,
    });
    await DocumentStoreService.instance.configureRoot(root.path);
    await OllamaService.instance.initialize();
    final chat = ChatServiceOllama();
    final phases = <String>{};
    chat.addListener(() => phases.add(chat.generationPhase.name));
    try {
      final ready = DateTime.now().add(const Duration(seconds: 30));
      while (
          chat.activeConversationId == null && DateTime.now().isBefore(ready)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(chat.activeConversationId, isNotNull);
      chat.selectModel('qwen2.5:7b');
      expect(chat.selectedModel, 'qwen2.5:7b');
      final evidence = <String, dynamic>{
        'model': chat.selectedModel,
        'root': root.path,
        'results': []
      };
      final timer = Stopwatch()..start();
      await chat.sendMessage(
          'Genera un Excel llamado ventas_octubre con una hoja Ventas. '
          'Incluye las columnas Producto, Unidades e Importe y dos filas: Café, 3, 12.5; Té, 2, 8.');
      final excel = chat.messages.last;
      expect(excel.isError, isFalse, reason: excel.text);
      expect(excel.generatedFiles, isNotEmpty, reason: excel.text);
      expect(excel.generatedFiles.single.format, ExportFormat.xlsx);
      final xlsx = File('${root.path}/ventas_octubre.xlsx');
      await xlsx.writeAsBytes(
          await GeneratedFileService.read(excel.generatedFiles.single));
      final parsedXlsx = await DocumentService.extract(xlsx.path);
      expect(parsedXlsx.isReady, isTrue, reason: parsedXlsx.error);
      expect(parsedXlsx.extractedText, contains('Café'));
      expect(parsedXlsx.extractedText, contains('12.5'));
      final table = await DocumentService.readSpreadsheet(xlsx.path);
      final calculation = await SpreadsheetAnalysisService.calculate(
          data: table,
          sheetNames: {table.sheets.single.name},
          valueColumn: 2,
          groupColumn: 0);
      expect(calculation.rows, 2);
      expect(calculation.total, '20.5');
      expect(calculation.hasExcludedValues, isFalse);
      evidence['localCalculation'] = {
        'total': calculation.total,
        'rows': calculation.rows,
        'numbers': calculation.numbers,
        'groups': [
          for (final group in calculation.groups)
            {'name': group.label, 'total': group.total}
        ],
      };
      (evidence['results'] as List).add({
        'kind': 'xlsx',
        'path': xlsx.path,
        'bytes': await xlsx.length(),
        'milliseconds': timer.elapsedMilliseconds,
        'prompt_eval_count': excel.metadata?['promptEvalCount'],
        'text': parsedXlsx.extractedText
      });
      timer.reset();
      await chat.sendMessage(
          'Ahora genera un PDF llamado resumen_ventas con un informe de esas ventas '
          'y sus datos. Incluye un título y una tabla.');
      final pdfMessage = chat.messages.last;
      expect(pdfMessage.isError, isFalse, reason: pdfMessage.text);
      expect(pdfMessage.generatedFiles, isNotEmpty, reason: pdfMessage.text);
      final pdfFiles = pdfMessage.generatedFiles
          .where((file) => file.format == ExportFormat.pdf)
          .toList();
      expect(pdfFiles, hasLength(1), reason: pdfMessage.text);
      final pdf = File('${root.path}/resumen_ventas.pdf');
      await pdf.writeAsBytes(await GeneratedFileService.read(pdfFiles.single));
      final parsedPdf = await DocumentService.extract(pdf.path);
      expect(parsedPdf.isReady, isTrue, reason: parsedPdf.error);
      expect(parsedPdf.extractedText, contains('Café'));
      (evidence['results'] as List).add({
        'kind': 'pdf',
        'path': pdf.path,
        'bytes': await pdf.length(),
        'milliseconds': timer.elapsedMilliseconds,
        'prompt_eval_count': pdfMessage.metadata?['promptEvalCount'],
        'text': parsedPdf.extractedText
      });
      for (final format in [
        ExportFormat.txt,
        ExportFormat.markdown,
        ExportFormat.docx
      ]) {
        final output = File('${root.path}/conversacion.${format.extension}');
        await output.writeAsBytes(await ExportService.encode(
            format: format,
            title: 'Conversación de ventas',
            markdown: ExportService.conversationMarkdown(
                chat.messages, 'Conversación de ventas')));
        expect(await output.length(), greaterThan(0));
      }
      await chat.newConversation();
      final source = File('${root.path}/informe_extenso.txt');
      await source.writeAsString([
        for (var index = 1; index <= 1800; index++)
          index == 1723
              ? 'El código de autorización del informe es ZAFIRO-72841.'
              : 'Registro $index: observaciones administrativas del periodo archivado.'
      ].join('\n'));
      final attached = await DocumentService.extract(source.path);
      expect(attached.originalChars, greaterThan(16000));
      expect(attached.text, isNot(contains('ZAFIRO-72841')));
      await chat.setDocumentMode(true);
      await chat.sendMessage(
          '¿Cuál es el código de autorización del informe? Responde con el código y la referencia.',
          documents: [attached]);
      expect(chat.messages.last.isError, isFalse,
          reason: chat.messages.last.text);
      expect(chat.messages.last.text, contains('ZAFIRO-72841'));
      final storedId = chat.activeConversationId!;
      await source.delete();
      await chat.newConversation();
      await chat.selectConversation(storedId);
      await ContextProfileService.instance.setTokens(chat.selectedModel, 32768);
      timer.reset();
      await chat.sendMessage(
          '¿Cuál era el código de autorización? Devuelve el código.');
      final enlarged = chat.messages.last;
      expect(enlarged.isError, isFalse, reason: enlarged.text);
      expect(enlarged.text, contains('ZAFIRO-72841'));
      expect(enlarged.metadata?['contextTokens'], 32768);
      final running =
          await http.get(Uri.parse('http://localhost:11434/api/ps'));
      evidence['profile32k'] = {
        'milliseconds': timer.elapsedMilliseconds,
        'answer': enlarged.text,
        'prompt_eval_count': enlarged.metadata?['promptEvalCount'],
        'running': jsonDecode(running.body)
      };
      await chat.setDocumentMode(false);
      final general = await chat
          .previewContext('¿Cuánto es 2 + 2? Responde solo con el número.', []);
      expect(general.documents.text, isEmpty);
      expect(general.messages.first.content,
          isNot(contains('responde únicamente')));
      await chat.sendMessage('¿Cuánto es 2 + 2? Responde solo con el número.');
      final answer = chat.messages.last;
      expect(answer.isError, isFalse, reason: answer.text);
      expect(answer.text, contains(RegExp(r'\b4\b')));
      expect(answer.metadata?['finishReason'], 'completed');
      final profile =
          await ContextProfileService.instance.forModel(chat.selectedModel);
      expect(profile.capabilitiesKnown, isTrue);
      expect(profile.supportsVision, isFalse);
      await expectLater(
          chat.validateAttachments(imageCount: 1), throwsStateError);
      evidence['generalMode'] = {
        'answer': answer.text,
        'documentChars': general.documents.chars,
        'finishReason': answer.metadata?['finishReason'],
        'phases': phases.toList(),
        'capabilities': {
          'known': profile.capabilitiesKnown,
          'tools': profile.supportsTools,
          'vision': profile.supportsVision
        }
      };
      await File('${root.path}/evidence.json')
          .writeAsString(const JsonEncoder.withIndent('  ').convert(evidence));
      // ignore: avoid_print -- evidencia del ensayo opt-in, fuera de producción.
      stdout.writeln('LIVE_EVIDENCE=${root.path}/evidence.json');
    } finally {
      chat.dispose();
      OllamaService.instance.dispose();
    }
  },
      skip: !const bool.fromEnvironment('LIGHTCHAT_LIVE'),
      timeout: const Timeout(Duration(minutes: 8)));
}
