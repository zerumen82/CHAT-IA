import 'dart:isolate';
import 'dart:math' as math;

import '../config/document_config.dart';
import '../models/context_plan.dart';
import '../models/document_attachment.dart';
import '../models/document_chunk.dart';
import 'document_service.dart';
import 'document_store_service.dart';

/// Recuperación léxica local: no descarga modelos ni envía datos a terceros.
class DocumentContextService {
  DocumentContextService({DocumentStoreService? store})
      : _store = store ?? DocumentStoreService.instance;

  final DocumentStoreService _store;

  Future<ContextPlan> plan({
    required String query,
    required List<DocumentAttachment> documents,
    required int maxChars,
  }) async {
    final hydrated = <DocumentAttachment>[];
    final warnings = <String>[];
    final seen = <String>{};
    for (final document in documents) {
      final key = document.storageId ?? document.path;
      if (!document.isReady || !seen.add(key)) {
        continue;
      }
      try {
        hydrated.add(await _store.hydrate(document));
      } catch (error) {
        warnings
            .add('${document.name}: no se pudo recuperar el texto ($error).');
      }
    }
    return Isolate.run(() => _select(query, hydrated, maxChars, warnings));
  }

  static ContextPlan _select(String query, List<DocumentAttachment> sources,
      int maxChars, List<String> initialWarnings) {
    final warnings = List<String>.of(initialWarnings);
    if (sources.isEmpty) {
      return ContextPlan(
          text: '',
          documents: const [],
          isPartial: warnings.isNotEmpty,
          warnings: warnings);
    }
    final preamble = '${DocumentConfig.contextPreamble}\n';
    final partialNotice = '${DocumentConfig.partialWarning}\n';
    var count = sources.length;
    final contents = [
      for (final source in sources) source.extractedText ?? source.text!
    ];
    int overhead(int index) =>
        _block(index + 1, sources[index].name, '').length;
    // Reservar el aviso antes de seleccionar evita que el aviso cause overflow.
    while (count > 0) {
      final needed = List<int>.generate(
              count,
              (index) =>
                  overhead(index) + math.min(contents[index].length, 100))
          .fold<int>(0, (sum, size) => sum + size);
      if (needed + preamble.length + partialNotice.length <= maxChars) {
        break;
      }
      count--;
    }
    if (count == 0) {
      warnings.add(
          'El presupuesto no permite incluir cabeceras y texto documental.');
      return ContextPlan(
          text: '', documents: const [], isPartial: true, warnings: warnings);
    }
    final remaining = maxChars -
        preamble.length -
        partialNotice.length -
        List.generate(count, overhead).fold<int>(0, (sum, size) => sum + size);
    final needs = [
      for (final content in contents.take(count))
        content.length + '[líneas 1–${content.split('\n').length}]\n'.length
    ];
    final grants = _share(needs, remaining);
    final terms = _terms(query);
    final selected = <DocumentAttachment>[];
    var partial = initialWarnings.isNotEmpty || count < sources.length;
    for (var index = 0; index < count; index++) {
      final source = sources[index];
      final content = contents[index];
      final chunks = _chunks(content);
      final allReference = '[líneas 1–${content.split('\n').length}]\n';
      final String selectedText;
      final bool cut;
      if (allReference.length + content.length <= grants[index]) {
        selectedText = '$allReference$content';
        cut = false;
      } else {
        selectedText = _retrieve(chunks, terms, grants[index]);
        cut = true;
      }
      final lostAtExtraction = source.extractionTruncated ||
          (source.extractedText == null &&
              source.storageId == null &&
              source.truncated);
      partial = partial || cut || lostAtExtraction;
      selected.add(source.copyWith(
          text: selectedText,
          truncated: cut || lostAtExtraction,
          clearExtractedText: true));
      if (lostAtExtraction) {
        warnings.add('${source.name}: la extracción conservada es parcial; '
            'el contenido descartado necesita volver a adjuntarse.');
      }
    }
    if (count < sources.length) {
      warnings.add(
          '${sources.length - count} documento(s) omitido(s) por límite de contexto.');
    }
    if (partial) {
      warnings.insert(0, DocumentConfig.partialWarning);
    }
    final buffer = StringBuffer(preamble);
    if (partial) {
      buffer.write(partialNotice);
    }
    for (var index = 0; index < selected.length; index++) {
      buffer.write(
          _block(index + 1, selected[index].name, selected[index].text!));
    }
    return ContextPlan(
        text: buffer.toString().trimRight(),
        documents: selected,
        isPartial: partial,
        warnings: warnings);
  }

  static String _block(int number, String name, String content) =>
      '\n--- Documento $number: $name ---\n$content\n--- Fin de $name ---\n';

  static List<int> _share(List<int> needs, int budget) {
    final grants = List<int>.filled(needs.length, 0);
    var pending = List<int>.generate(needs.length, (index) => index);
    while (budget > 0 && pending.isNotEmpty) {
      final share = math.max(1, budget ~/ pending.length);
      final next = <int>[];
      for (final index in pending) {
        final grant =
            math.min(budget, math.min(share, needs[index] - grants[index]));
        grants[index] += grant;
        budget -= grant;
        if (grants[index] < needs[index]) {
          next.add(index);
        }
      }
      pending = next;
    }
    return grants;
  }

  static List<DocumentChunk> _chunks(String text) {
    final chunks = <DocumentChunk>[];
    final lines = text.split('\n');
    var buffer = StringBuffer();
    var firstLine = 1;
    String? section;
    void flush(int lastLine) {
      if (buffer.isNotEmpty) {
        chunks.add(DocumentChunk(
            text: buffer.toString().trimRight(),
            firstLine: firstLine,
            lastLine: lastLine,
            section: section));
        buffer = StringBuffer();
      }
    }

    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final isSection =
          RegExp(r'^(Hoja ".*":|Página \d+:|Diapositiva \d+:)$').hasMatch(line);
      if (isSection ||
          buffer.length + line.length + 1 > DocumentConfig.chunkChars) {
        flush(math.max(firstLine, index));
      }
      if (isSection) {
        section = line;
      }
      if (buffer.isEmpty) {
        firstLine = index + 1;
      }
      if (line.length > DocumentConfig.chunkChars) {
        for (var offset = 0;
            offset < line.length;
            offset += DocumentConfig.chunkChars) {
          chunks.add(DocumentChunk(
            text: line.substring(offset,
                math.min(line.length, offset + DocumentConfig.chunkChars)),
            firstLine: index + 1,
            lastLine: index + 1,
            section: section,
          ));
        }
      } else {
        buffer.writeln(line);
      }
    }
    flush(lines.length);
    return chunks;
  }

  static Set<String> _terms(String text) => RegExp(r'[a-záéíóúüñ0-9]+')
      .allMatches(text.toLowerCase())
      .map((match) => match.group(0)!)
      .where((word) => word.length > 2 && !_stopWords.contains(word))
      .toSet();

  static const Set<String> _stopWords = {
    'que',
    'qué',
    'del',
    'las',
    'los',
    'una',
    'uno',
    'unos',
    'unas',
    'para',
    'por',
    'con',
    'sin',
    'este',
    'esta',
    'estos',
    'estas',
    'como',
    'cómo',
    'dame',
    'dime',
    'puedes',
    'documento',
    'archivo',
    'sobre',
    'the',
    'and',
    'from',
    'what',
    'which',
    'please',
  };

  static String _retrieve(
      List<DocumentChunk> chunks, Set<String> terms, int budget) {
    if (budget <= 0 || chunks.isEmpty) {
      return '';
    }
    final chunkTerms = [for (final chunk in chunks) _terms(chunk.text)];
    final frequency = {
      for (final term in terms)
        term: chunkTerms.where((words) => words.contains(term)).length
    };
    final scores = [
      for (var index = 0; index < chunks.length; index++)
        terms.where(chunkTerms[index].contains).fold<double>(
            0,
            (sum, term) =>
                sum + math.log(1 + chunks.length / (1 + frequency[term]!)))
    ];
    final ranked = List<int>.generate(chunks.length, (index) => index)
      ..sort((first, second) {
        final difference = scores[second].compareTo(scores[first]);
        return difference == 0 ? first.compareTo(second) : difference;
      });
    if (scores.every((score) => score == 0) && ranked.length > 2) {
      // Una pregunta amplia obtiene muestras separadas, con cobertura parcial.
      ranked
        ..remove(chunks.length ~/ 2)
        ..remove(chunks.length - 1)
        ..insert(1, chunks.length ~/ 2)
        ..insert(2, chunks.length - 1);
    }
    final pieces = <int, String>{};
    var remaining = budget;
    for (final index in ranked) {
      final chunk = chunks[index];
      final reference = '${chunk.reference}\n';
      final separator = pieces.isEmpty ? 0 : 2;
      if (remaining <=
          reference.length + separator + DocumentConfig.minExcerptChars) {
        continue;
      }
      final body = DocumentService.truncateAtLineBreak(
          chunk.text, remaining - reference.length - separator);
      pieces[index] = '$reference$body';
      remaining -= reference.length + body.length + separator;
    }
    final positions = pieces.keys.toList()..sort();
    return positions.map((position) => pieces[position]!).join('\n\n');
  }
}
