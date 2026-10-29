import 'document_attachment.dart';

/// Selección exacta compartida por la petición, el medidor y el visor.
class ContextPlan {
  final String text;
  final List<DocumentAttachment> documents;
  final bool isPartial;
  final List<String> warnings;

  const ContextPlan({
    required this.text,
    required this.documents,
    required this.isPartial,
    this.warnings = const [],
  });

  int get chars => text.length;
}
