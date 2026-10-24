import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/document_attachment.dart';

/// Abre un visor con el texto exacto que se envía al modelo para [document].
///
/// Sirve para comprobar que el documento se leyó bien y ver qué parte se
/// recortó por límite de contexto.
Future<void> showDocumentTextDialog(
  BuildContext context,
  DocumentAttachment document,
) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _DocumentTextDialog(document: document),
  );
}

class _DocumentTextDialog extends StatelessWidget {
  final DocumentAttachment document;

  const _DocumentTextDialog({required this.document});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final text = document.text?.trim() ?? '';

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 12, 8),
      title: Row(
        children: [
          Icon(
            _documentIcon(document.kind),
            color: document.error == null
                ? colorScheme.primary
                : colorScheme.error,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              document.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 720,
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildMetadata(context, colorScheme, text),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: _buildBody(context, colorScheme, text),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: text.isEmpty
              ? null
              : () {
                  Clipboard.setData(ClipboardData(text: text));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Texto del documento copiado'),
                      duration: Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
          icon: const Icon(Icons.copy, size: 18),
          label: const Text('Copiar texto'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }

  Widget _buildMetadata(
    BuildContext context,
    ColorScheme colorScheme,
    String text,
  ) {
    final details = <String>[
      if (document.sizeBytes > 0) document.sizeFormatted,
      if (text.isNotEmpty) '${text.length} caracteres enviados',
      if (document.truncated)
        'recortado de ${document.originalChars} caracteres',
    ];

    if (details.isEmpty) {
      return const SizedBox.shrink();
    }

    return Text(
      details.join(' · '),
      style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
    );
  }

  Widget _buildBody(
    BuildContext context,
    ColorScheme colorScheme,
    String text,
  ) {
    if (document.isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Leyendo documento…'),
          ],
        ),
      );
    }

    final error = document.error;
    if (error != null) {
      return SingleChildScrollView(
        child: Text(
          error,
          style: TextStyle(color: colorScheme.error, fontSize: 14),
        ),
      );
    }

    if (text.isEmpty) {
      return Center(
        child: Text(
          'El documento no contiene texto.',
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
      );
    }

    return SelectionArea(
      child: SingleChildScrollView(
        child: Text(
          text,
          style: TextStyle(
            fontFamily: 'Courier',
            fontSize: 12.5,
            height: 1.45,
            color: colorScheme.onSurface,
          ),
        ),
      ),
    );
  }

  IconData _documentIcon(DocumentKind kind) {
    return switch (kind) {
      DocumentKind.pdf => Icons.picture_as_pdf,
      DocumentKind.spreadsheet => Icons.table_chart,
      DocumentKind.presentation => Icons.slideshow,
      DocumentKind.text => Icons.description,
    };
  }
}
