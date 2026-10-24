import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

/// Respuesta del asistente con formato Markdown: negritas, listas, tablas y
/// bloques de código con botón para copiar.
class AssistantMarkdown extends StatelessWidget {
  final String text;
  final Color textColor;

  const AssistantMarkdown({
    super.key,
    required this.text,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final base = MarkdownStyleSheet.fromTheme(theme);

    final styleSheet = base.copyWith(
      p: TextStyle(color: textColor, fontSize: 16, height: 1.5),
      a: TextStyle(
        color: colorScheme.primary,
        decoration: TextDecoration.underline,
      ),
      h1: TextStyle(
        color: textColor,
        fontSize: 22,
        fontWeight: FontWeight.w700,
      ),
      h2: TextStyle(
        color: textColor,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
      h3: TextStyle(
        color: textColor,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      h4: TextStyle(
        color: textColor,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      h5: TextStyle(
        color: textColor,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
      h6: TextStyle(
        color: textColor,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      strong: const TextStyle(fontWeight: FontWeight.w700),
      em: const TextStyle(fontStyle: FontStyle.italic),
      code: TextStyle(
        fontFamily: 'Consolas',
        fontSize: 13.5,
        color: textColor,
        backgroundColor: colorScheme.surfaceContainerHighest,
      ),
      blockquote: TextStyle(
        color: textColor.withValues(alpha: 0.9),
        fontSize: 15.5,
        height: 1.5,
      ),
      blockquoteDecoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(3),
        border: Border(
          left: BorderSide(color: colorScheme.primary, width: 3),
        ),
      ),
      listBullet: TextStyle(color: textColor),
      tableBody: TextStyle(color: textColor, fontSize: 14),
      tableHead: TextStyle(
        color: textColor,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      tableBorder: TableBorder.all(color: colorScheme.outlineVariant),
      codeblockDecoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
    );

    return MarkdownBody(
      data: text,
      selectable: false,
      styleSheet: styleSheet,
      builders: {'pre': _CodeBlockBuilder(textColor: textColor)},
    );
  }
}

/// Bloque de código con el lenguaje detectado y un botón para copiarlo.
class _CodeBlockBuilder extends MarkdownElementBuilder {
  final Color textColor;

  _CodeBlockBuilder({required this.textColor});

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    var code = element.textContent;
    String? language;

    final children = element.children;
    if (children != null &&
        children.isNotEmpty &&
        children.first is md.Element) {
      final codeElement = children.first as md.Element;
      if (codeElement.tag == 'code') {
        code = codeElement.textContent;
        final className = codeElement.attributes['class'];
        if (className != null && className.startsWith('language-')) {
          language = className.substring('language-'.length);
        }
      }
    }

    return _CodeBlock(
      code: code.trimRight(),
      language: language,
      textColor: textColor,
    );
  }
}

class _CodeBlock extends StatefulWidget {
  final String code;
  final String? language;
  final Color textColor;

  const _CodeBlock({
    required this.code,
    required this.language,
    required this.textColor,
  });

  @override
  State<_CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<_CodeBlock> {
  bool _copied = false;

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.code));
    setState(() => _copied = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Código copiado'),
        duration: Duration(milliseconds: 1200),
        behavior: SnackBarBehavior.floating,
      ),
    );
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 2, 0),
            child: Row(
              children: [
                Text(
                  (widget.language ?? 'código').toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Copiar código',
                  onPressed: _copy,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    _copied ? Icons.check : Icons.content_copy,
                    size: 16,
                    color: _copied
                        ? colorScheme.tertiary
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Text(
              widget.code,
              style: TextStyle(
                fontFamily: 'Consolas',
                fontSize: 13,
                height: 1.45,
                color: widget.textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
