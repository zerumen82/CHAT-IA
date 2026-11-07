import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../services/link_launcher_service.dart';

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
      // El modelo escribe a veces los dominios a secas; sin esto se ven pero
      // no se pueden pulsar.
      data: LinkLauncherService.linkifyMarkdown(text),
      selectable: false,
      styleSheet: styleSheet,
      builders: {'pre': _CodeBlockBuilder(textColor: textColor)},
      onTapLink: (label, href, title) => _openLink(context, href),
    );
  }

  /// Los enlaces normales se abren en el navegador del sistema. Los `.onion`
  /// solo existen dentro de Tor, así que se explican y se ofrecen a Tor Browser.
  Future<void> _openLink(BuildContext context, String? href) async {
    final url = LinkLauncherService.normalizeUrl(href ?? '');
    if (url == null) {
      _notify(context, 'El enlace no es válido.');
      return;
    }
    if (LinkLauncherService.isOnion(url)) {
      await showDialog<void>(
        context: context,
        builder: (_) => _OnionLinkDialog(url: url),
      );
      return;
    }
    final opened = await LinkLauncherService.instance.openExternal(url);
    if (!opened && context.mounted) {
      _notify(context, 'No se pudo abrir el navegador del sistema.');
    }
  }

  void _notify(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}

/// Aviso al pulsar un enlace .onion: un navegador normal no puede abrirlo.
class _OnionLinkDialog extends StatefulWidget {
  final String url;

  const _OnionLinkDialog({required this.url});

  @override
  State<_OnionLinkDialog> createState() => _OnionLinkDialogState();
}

class _OnionLinkDialogState extends State<_OnionLinkDialog> {
  bool _checking = true;
  bool _torRunning = false;
  bool _hasTorBrowser = false;

  @override
  void initState() {
    super.initState();
    _detect();
  }

  Future<void> _detect() async {
    final launcher = LinkLauncherService.instance;
    final hasBrowser = await launcher.torBrowserPath() != null;
    final torRunning = await launcher.torRunning();
    if (!mounted) {
      return;
    }
    setState(() {
      _hasTorBrowser = hasBrowser;
      _torRunning = torRunning;
      _checking = false;
    });
  }

  Future<void> _copy() async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: widget.url));
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
    messenger.showSnackBar(const SnackBar(
      content: Text('Enlace .onion copiado. Pégalo en Tor Browser.'),
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _open() async {
    final messenger = ScaffoldMessenger.of(context);
    final opened = await LinkLauncherService.instance.openInTorBrowser(widget.url);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
    messenger.showSnackBar(SnackBar(
      content: Text(opened
          ? 'Abriendo en Tor Browser…'
          : 'No se pudo abrir Tor Browser. Copia el enlace y pégalo allí.'),
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canOpen = !_checking && _torRunning && _hasTorBrowser;

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.lock_outline, size: 20),
          SizedBox(width: 8),
          Expanded(child: Text('Enlace .onion')),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              widget.url,
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontFamily: 'Consolas'),
            ),
            const SizedBox(height: 12),
            const Text('Esta dirección solo existe dentro de la red Tor: '
                'Chrome, Edge o Firefox no pueden abrirla por sí solos.'),
            const SizedBox(height: 12),
            const Text('Copia el enlace y pégalo en la barra de direcciones de '
                'Tor Browser. LightChat no puede verificar el contenido de '
                'esos sitios.'),
            const SizedBox(height: 12),
            if (_checking)
              const LinearProgressIndicator()
            else
              Text(
                _torRunning
                    ? (_hasTorBrowser
                        ? 'Tor está activo y se ha encontrado Tor Browser.'
                        : 'Tor está activo, pero no se ha encontrado Tor Browser.')
                    : 'No se detecta Tor activo: abre Tor Browser y espera a '
                        'que conecte antes de abrir el enlace.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
        TextButton(
          onPressed: _copy,
          child: const Text('Copiar enlace'),
        ),
        if (canOpen)
          FilledButton(
            onPressed: _open,
            child: const Text('Abrir en Tor Browser'),
          ),
      ],
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
