import 'dart:io';

import 'web_search_service.dart';

/// Apertura de los enlaces que aparecen en las respuestas.
///
/// Los enlaces normales se abren con el navegador del sistema. Los `.onion`
/// solo existen dentro de la red Tor, así que un navegador convencional no
/// puede abrirlos: se ofrecen para Tor Browser cuando está instalado y activo.
class LinkLauncherService {
  LinkLauncherService({
    Future<bool> Function(String)? opener,
    String? torBrowserPath,
  })  : _opener = opener,
        _torBrowserPath = torBrowserPath;

  static final LinkLauncherService instance = LinkLauncherService();

  final Future<bool> Function(String)? _opener;
  String? _torBrowserPath;

  /// Un enlace es de la deep web cuando su host termina en `.onion`.
  static bool isOnion(String url) {
    final host = Uri.tryParse(url.trim())?.host.toLowerCase() ?? '';
    return host.endsWith('.onion');
  }

  /// Solo se abren enlaces http/https; el modelo no puede inyectar otros esquemas.
  static bool isWebUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    return uri != null &&
        (uri.isScheme('http') || uri.isScheme('https')) &&
        uri.host.isNotEmpty;
  }

  static final _hostChars = RegExp(r'^[a-z0-9.-]+$', caseSensitive: false);

  /// Devuelve la URL lista para abrir. Acepta hosts sin esquema
  /// ("www.ejemplo.com"), que el modelo escribe a veces, y descarta esquemas
  /// desconocidos o texto con espacios.
  static String? normalizeUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty || trimmed.contains(RegExp(r'\s'))) {
      return null;
    }
    if (trimmed.contains('://')) {
      return isWebUrl(trimmed) ? trimmed : null;
    }
    final parsed = Uri.tryParse('https://$trimmed');
    if (parsed == null ||
        parsed.host.isEmpty ||
        !parsed.host.contains('.') ||
        !_hostChars.hasMatch(parsed.host)) {
      return null;
    }
    final scheme =
        parsed.host.toLowerCase().endsWith('.onion') ? 'http' : 'https';
    return '$scheme://$trimmed';
  }

  /// Convierte en enlaces los dominios que el modelo escribe a secas
  /// («amazon.es/dp/x», «abc.onion»): Markdown solo autoenlaza `http(s)://` y
  /// `www.`, así que sin esto el texto se ve pero no se puede pulsar.
  ///
  /// También destapa las direcciones que el modelo encierra en código
  /// (`http://…`) o en un bloque que solo contiene direcciones, que es como
  /// suele escribir los enlaces .onion: si no, se ven como código y no hay
  /// forma de abrirlos. El código de verdad no se toca.
  static String linkifyMarkdown(String text) {
    if (!text.contains('.')) return text;
    final lines = text.split('\n');
    final out = <String>[];
    var i = 0;
    while (i < lines.length) {
      final line = lines[i];
      if (line.trimLeft().startsWith('```')) {
        final fence = <String>[line];
        i++;
        while (i < lines.length) {
          fence.add(lines[i]);
          final closes = lines[i].trimLeft().startsWith('```');
          i++;
          if (closes) break;
        }
        final closed =
            fence.length > 1 && fence.last.trimLeft().startsWith('```');
        final body =
            fence.sublist(1, closed ? fence.length - 1 : fence.length);
        out.addAll(_unveilCode(body, fenced: true) ?? fence);
        continue;
      }
      if (_isIndented(line) && line.trim().isNotEmpty) {
        final block = <String>[];
        while (i < lines.length &&
            (_isIndented(lines[i]) || lines[i].trim().isEmpty)) {
          block.add(lines[i]);
          i++;
        }
        out.addAll(_unveilCode(block, fenced: false) ?? block);
        continue;
      }
      out.add(_linkifyLine(line));
      i++;
    }
    return out.join('\n');
  }

  /// Dominios que se reconocen aunque el modelo omita el esquema.
  static const String _tlds = 'onion|com|org|net|es|io|co|ai|dev|app|info|me|'
      'tv|cc|gov|edu|uk|de|fr|it|nl|ru|mx|ar|cl|br|eu|se|no|fi|pl|in|jp|cn|'
      'ca|au|ch|at|be|pt|gr|cz|xyz|online|site|shop|store|news|blog|link|'
      'live|wiki';

  static final String _domain =
      '(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\\.)+($_tlds)(?::\\d+)?';

  static final _inlineTokens = RegExp(
    '(?<code>`[^`\\n]*`)'
    '|(?<markdown>!?\\[[^\\]\\n]*\\]\\([^)\\s]*\\))'
    '|(?<url>(?:https?://|www\\.)[^\\s<>()\\[\\]]+)'
    '|(?<bare>$_domain(?:/[^\\s<>()\\[\\]]*)?)',
    caseSensitive: false,
  );

  /// Una sola dirección, sin espacios: para destapar código en línea.
  static final _singleUrl = RegExp(
    '^(?:(?:https?://|www\\.)\\S+|$_domain(?:/\\S*)?)\$',
    caseSensitive: false,
  );

  /// Igual pero exigiendo esquema: un bloque con vallas solo se destapa si
  /// contiene direcciones completas.
  static final _fencedUrl = RegExp(
    r'^(?:https?://|www\.)\S+$',
    caseSensitive: false,
  );

  static bool _isIndented(String line) =>
      line.startsWith('\t') || line.startsWith('    ');

  /// Linkifica una línea normal, fuera de los bloques de código.
  static String _linkifyLine(String line) {
    if (!line.contains('.')) return line;
    return line.replaceAllMapped(_inlineTokens, (Match match) {
      final groups = match as RegExpMatch;
      final code = groups.namedGroup('code');
      if (code != null) {
        final inner = code.substring(1, code.length - 1).trim();
        final href = _singleUrl.hasMatch(inner) ? normalizeUrl(inner) : null;
        return href == null ? code : '[$inner]($href)';
      }
      final raw = groups.namedGroup('url') ?? groups.namedGroup('bare');
      if (raw == null) return match[0]!;
      var candidate = raw;
      var trailing = '';
      while (candidate.isNotEmpty &&
          '.,;:!?*'.contains(candidate[candidate.length - 1])) {
        trailing = '${candidate[candidate.length - 1]}$trailing';
        candidate = candidate.substring(0, candidate.length - 1);
      }
      final href = normalizeUrl(candidate);
      if (href == null) return match[0]!;
      return '[$candidate]($href)$trailing';
    });
  }

  /// Si el bloque solo tiene direcciones devuelve enlaces sueltos; si es código
  /// de verdad devuelve null, para no meter `[url](url)` dentro del código
  /// (se vería tal cual, con corchetes, y sin poder pulsarse).
  static List<String>? _unveilCode(List<String> block, {required bool fenced}) {
    final urls = <String>[];
    var first = true;
    for (final line in block) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final pattern = fenced ? _fencedUrl : _singleUrl;
      if (!pattern.hasMatch(trimmed)) {
        if (fenced && first) {
          first = false;
          continue; // etiqueta del lenguaje (```text)
        }
        return null;
      }
      first = false;
      urls.add(trimmed);
    }
    if (urls.isEmpty) return null;
    final out = <String>[];
    for (final url in urls) {
      if (out.isNotEmpty) out.add('');
      final href = normalizeUrl(url);
      out.add(href == null ? url : '[$url]($href)');
    }
    return out;
  }

  /// Abre el enlace con el navegador predeterminado del sistema.
  Future<bool> openExternal(String url) async {
    final opener = _opener;
    if (opener != null) {
      return opener(url);
    }
    try {
      if (Platform.isWindows) {
        await Process.start(
          'rundll32',
          <String>['url.dll,FileProtocolHandler', url],
          mode: ProcessStartMode.detached,
        );
      } else if (Platform.isMacOS) {
        await Process.start('open', <String>[url],
            mode: ProcessStartMode.detached);
      } else {
        await Process.start('xdg-open', <String>[url],
            mode: ProcessStartMode.detached);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Ruta del ejecutable de Tor Browser si está instalado.
  Future<String?> torBrowserPath() async {
    if (_torBrowserPath != null) {
      return _torBrowserPath;
    }
    for (final candidate in _candidates()) {
      if (await File(candidate).exists()) {
        _torBrowserPath = candidate;
        return candidate;
      }
    }
    return null;
  }

  /// Abre el enlace dentro de Tor Browser (necesita Tor ya conectado).
  Future<bool> openInTorBrowser(String url) async {
    final path = await torBrowserPath();
    if (path == null) {
      return false;
    }
    try {
      await Process.start(path, <String>[url],
          mode: ProcessStartMode.detached);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Comprueba si hay un proxy SOCKS5 de Tor escuchando en local.
  Future<bool> torRunning() async {
    for (final port in WebSearchService.torPorts) {
      try {
        final socket = await Socket.connect(
          '127.0.0.1',
          port,
          timeout: const Duration(milliseconds: 400),
        );
        await socket.close();
        return true;
      } catch (_) {
        continue;
      }
    }
    return false;
  }

  List<String> _candidates() {
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
    if (Platform.isWindows) {
      final local = Platform.environment['LOCALAPPDATA'] ?? '';
      final programFiles =
          Platform.environment['ProgramFiles'] ?? r'C:\Program Files';
      final programFilesX86 =
          Platform.environment['ProgramFiles(x86)'] ?? r'C:\Program Files (x86)';
      return <String>[
        if (local.isNotEmpty) ...<String>[
          '$local\\Programs\\Tor Browser\\Browser\\firefox.exe',
          '$local\\Tor Browser\\Browser\\firefox.exe',
        ],
        if (home.isNotEmpty) '$home\\Desktop\\Tor Browser\\Browser\\firefox.exe',
        '$programFiles\\Tor Browser\\Browser\\firefox.exe',
        '$programFilesX86\\Tor Browser\\Browser\\firefox.exe',
      ];
    }
    if (Platform.isMacOS) {
      return <String>[
        '/Applications/Tor Browser.app/Contents/MacOS/firefox',
        if (home.isNotEmpty)
          '$home/Applications/Tor Browser.app/Contents/MacOS/firefox',
      ];
    }
    return <String>[
      if (home.isNotEmpty) ...<String>[
        '$home/tor-browser/Browser/firefox',
        '$home/.local/share/tor-browser/Browser/firefox',
      ],
      '/opt/tor-browser/Browser/firefox',
    ];
  }
}
